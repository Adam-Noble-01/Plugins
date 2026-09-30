# =============================================================================
# NA SKETCHUP MCP - HANDLERS - SOLID BOOLEANS
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Booleans__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Booleans
# PURPOSE    : solid_boolean: union, subtract, intersect, trim, split, outer_shell
# CREATED    : 2026
#
# OPERAND ORDER (InsertPrimatives 5.1.4 devlog, measured, and matching
# SketchUp's own Solid Tools "the first solid you select is your cutting tool"):
#   cutter.subtract(target)  ->  NEW group = target - cutter; BOTH erased
#   cutter.trim(target)      ->  target trimmed by cutter; cutter KEPT
# The Group#subtract doc summary says "this - arg" and is wrong. Getting it
# backwards makes a small cutter inside a large solid compute an empty result,
# which erases both operands: the target silently disappears.
#
# SO THIS HANDLER:
# - takes target_id (the thing kept/cut) and tool_ids (cutters/others) by role,
#   never by argument position;
# - checks every operand is manifold and shares the target's parent collection;
# - carries the target's name, tag, material, shadow flags and attribute
#   dictionaries onto the NEW result group (the API returns a new container);
# - validates the result while the undo operation is still open and raises if
#   the target was destroyed without a replacement, so the router's abort
#   restores the model and the agent gets a message instead of a lost model.
# Solid tools need SketchUp Pro/Studio (the API self-test checks Group#subtract).
#
# FAIL FAST, EXPLAIN, WARN (1.0.2, from Adam's MCP__Testing__ log):
# SketchUp's solid engine can run 30 s on a few thousand curved faces and then
# return nothing, or return a result with holes. So before it runs:
#   - a non-solid operand is described in counts (Na__SolidHealth);
#   - an inside-out operand is refused, with how to reverse its faces;
#   - a cutter whose box does not reach the target is skipped, or refused when
#     it is the only one, instead of spending 30 s to learn that;
#   - dense operands are flagged.
# After it runs, a failure names the cutter that failed and the likely causes,
# and a result that is not a solid is reported at once.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Booleans

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OPERATIONS = %w[union subtract intersect trim split outer_shell].freeze

        # Operations whose cutters must reach the target to do anything (union/outer_shell merge apart solids).
        NA_NEEDS_OVERLAP = %w[subtract intersect trim split].freeze

        # Boxes that only touch are not overlapping (inches, about 0.025 mm).
        NA_TOUCH_TOLERANCE = 0.001

        # Above this many faces across the operands the engine is warned about as slow.
        NA_DENSE_FACES = 2000

        # Above this many seconds a boolean is reported as slow (clients give up near 60 s).
        NA_SLOW_SECONDS = 10.0

        # Outliner name of a result whose target had no name: "Cut solid 4000 x 215 x 2400".
        NA_RESULT_KINDS = {
            'union'       => 'Union',
            'subtract'    => 'Cut solid',
            'intersect'   => 'Intersection',
            'trim'        => 'Trimmed solid',
            'split'       => 'Split piece',
            'outer_shell' => 'Outer shell'
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | solid_boolean
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Booleans__Boolean(params, ctx)
            model = ctx[:model]
            operation = Na__Params.Na__Params__Enum(params, 'operation', NA_OPERATIONS, nil, required: true)
            target = Na__EntityResolver.Na__EntityResolver__RequireInstance(model, Na__Params.Na__Params__Integer(params, 'target_id', nil, required: true), 'target_id')
            tools = Na__Params.Na__Params__IdArray(params, 'tool_ids').map do |tool_id|
                Na__EntityResolver.Na__EntityResolver__RequireInstance(model, tool_id, 'tool_ids')
            end
            if tools.include?(target)
                raise Na__McpError.new('invalid_params', 'target_id also appears in tool_ids.', 'List each solid once: the target, then the tools.')
            end

            na_validate_operands([target] + tools, target)
            tools = na_reaching_tools(operation, target, tools, ctx)
            faces = ([target] + tools).sum { |solid| Na__SolidHealth.Na__SolidHealth__FaceCount(solid) }
            if faces > NA_DENSE_FACES
                ctx[:warnings] << "These solids have #{faces} faces between them. SketchUp's solid engine is slow on dense curved meshes " \
                                  '(30 s or more) and can fail or leave holes there.'
            end
            keep_tools = Na__Params.Na__Params__Boolean(params, 'keep_tools', false)
            properties = na_capture_properties(target)
            target_id = target.persistent_id

            started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            result, failed_tool_id = case operation
                                     when 'split' then [na_split(target, tools.first, keep_tools, ctx), tools.first.persistent_id]
                                     else na_sequence(operation, target, tools, keep_tools)
                                     end
            seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

            results = Array(result).compact.select(&:valid?)
            na_raise_engine_failure(operation, target_id, tools.length, failed_tool_id, seconds, faces) if results.empty?
            na_warn_slow(seconds, faces, ctx)

            result_name = Na__Params.Na__Params__String(params, 'result_name', nil)
            # split yields three pieces of the same parts; each carries the target's properties.
            (operation == 'split' ? results : [results.first]).each do |piece|
                na_restore_properties(piece, properties, result_name)
                # An unnamed target gives an unnamed result: name it so it is not another "Group".
                Na__Creation.Na__Creation__EnsureName(piece, {}, NA_RESULT_KINDS.fetch(operation, 'Solid'), ctx)
            end
            broken = results.reject(&:manifold?)
            broken.each do |piece|
                ctx[:warnings] << "The result is NOT a solid: #{Na__SolidHealth.Na__SolidHealth__Describe(piece)}. SketchUp's engine left it that way, " \
                                  'so the next solid_boolean on it will be refused. Undo this step (model_undo) and retry with cutters that pass ' \
                                  '1 mm beyond the faces they cut, or with simpler geometry.'
            end
            {
                'operation' => operation,
                'seconds'   => seconds.round(2),
                'result'    => results.map { |group| Na__Serializer.Na__Serializer__Summary(group, ctx, nil, true) },
                'summary'   => "#{operation} complete: #{results.length} result#{results.length == 1 ? '' : 's'}" \
                               "#{broken.empty? ? '' : " (#{broken.length} NOT a solid, see warnings)"}."
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Operations
# -----------------------------------------------------------------------------

        # Applies each tool in turn; the running result is the next step's target.
        # Returns [result, nil], or [nil, id of the tool the engine failed on].
        def self.na_sequence(operation, target, tools, keep_tools)
            current = target
            tools.each do |tool|
                tool_id = tool.persistent_id
                operand = keep_tools && operation != 'trim' ? na_copy(tool) : tool
                current = na_apply(operation, current, operand)
                return [nil, tool_id] if current.nil?
            end
            [current, nil]
        end

        # The engine returned nothing although every operand is a solid and reaches the target.
        def self.na_raise_engine_failure(operation, target_id, tool_count, failed_tool_id, seconds, faces)
            at_tool = tool_count > 1 && failed_tool_id ? " at tool id #{failed_tool_id}" : ''
            raise Na__McpError.new('operation_failed',
                                   "SketchUp's solid engine returned nothing for #{operation} on target #{target_id}#{at_tool}, " \
                                   "after #{seconds.round(1)} s on #{faces} faces. The model was left unchanged.",
                                   'Usual causes: faces or edges lying exactly on each other (let cutters pass 1 mm beyond the faces they cut), ' \
                                   'very short edges, or dense curved meshes (use fewer segments). With several tools, run them one at a time ' \
                                   'to find the one that fails.',
                                   { 'target_id' => target_id, 'failed_tool_id' => failed_tool_id, 'seconds' => seconds.round(2), 'faces' => faces })
        end

        def self.na_warn_slow(seconds, faces, ctx)
            return if seconds < NA_SLOW_SECONDS

            ctx[:slow_reported] = true
            ctx[:warnings] << "SketchUp's solid engine took #{seconds.round(1)} s on #{faces} faces. Clients may give up at about 60 s: " \
                              'simplify dense meshes (fewer segments) or cut in smaller steps.'
        end

        def self.na_apply(operation, current, tool)
            case operation
            when 'union'       then current.union(tool)
            when 'intersect'   then current.intersect(tool)
            when 'outer_shell' then current.outer_shell(tool)
            when 'subtract'    then tool.subtract(current)       # cutter.subtract(target) = target - cutter
            when 'trim'        then tool.trim(current)           # cutter kept, target trimmed
            end
        end

        # Group#split returns [intersection, this - arg, arg - this].
        def self.na_split(target, tool, keep_tools, ctx)
            tool = na_copy(tool) if keep_tools
            pieces = target.split(tool)
            return nil unless pieces

            ctx[:warnings] << 'split returns up to three solids: [overlap, target minus tool, tool minus target].'
            pieces
        end

        def self.na_copy(instance)
            return instance.copy if instance.is_a?(Sketchup::Group)

            instance.parent.entities.add_instance(instance.definition, instance.transformation)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Validation and Property Transplant
# -----------------------------------------------------------------------------

        def self.na_validate_operands(operands, target)
            not_solid = operands.reject(&:manifold?)
            unless not_solid.empty?
                reasons = not_solid.first(3).map { |solid| Na__SolidHealth.Na__SolidHealth__Describe(solid) }
                raise Na__McpError.new('invalid_params', "Not a solid: #{reasons.join('; ')}.",
                                       'If a solid_boolean made it, undo that step (model_undo) and retry with cutters that pass 1 mm beyond the ' \
                                       'faces they cut. Otherwise close the holes and delete internal faces and stray edges (geometry_edit ' \
                                       'erase_stray_edges), or ask the user to check it with Solid Inspector (Extensions menu).',
                                       { 'not_solid_ids' => not_solid.map(&:persistent_id) })
            end

            inside_out = operands.select { |solid| Na__SolidHealth.Na__SolidHealth__SignedVolume(solid.definition.entities.grep(Sketchup::Face)) <= 0.0 }
            unless inside_out.empty?
                ids = inside_out.map(&:persistent_id)
                raise Na__McpError.new('invalid_params',
                                       "Inside out (its faces point inward): id #{ids.join(', ')}. SketchUp's solid engine gives empty or wrong results on it.",
                                       "Reverse all its faces first: geometry_edit with operation reverse_faces and ids #{ids.inspect}.",
                                       { 'inside_out_ids' => ids })
            end

            outsiders = operands.reject { |operand| operand.parent == target.parent }
            return if outsiders.empty?

            raise Na__McpError.new('context_error', 'All solids must be in the same parent (group or model root) as the target.',
                                   'Move them into one context first (e.g. group_create around them, or explode the extra nesting).')
        end

        # A tool whose world box does not reach the target's cannot cut, trim or intersect it.
        # Drops such tools (they are left untouched) and refuses when none is left, or when an
        # intersect/split tool misses, instead of letting the engine spend 30 s finding that out.
        def self.na_reaching_tools(operation, target, tools, ctx)
            return tools unless NA_NEEDS_OVERLAP.include?(operation)

            target_box = Na__Serializer.Na__Serializer__WorldBoundsOfMany([target], ctx)
            return tools unless target_box

            missing = tools.reject do |tool|
                box = Na__Serializer.Na__Serializer__WorldBoundsOfMany([tool], ctx)
                box.nil? || na_boxes_overlap?(target_box, box)
            end
            return tools if missing.empty?

            ids = missing.map(&:persistent_id)
            if %w[intersect split].include?(operation) || missing.length == tools.length
                first_box = Na__Serializer.Na__Serializer__WorldBoundsOfMany([missing.first], ctx)
                raise Na__McpError.new('invalid_params',
                                       "Tool id #{ids.join(', ')} does not reach target #{target.persistent_id}: their bounding boxes do not overlap, " \
                                       "so #{operation} has nothing to work on. Nothing was changed.",
                                       'Compare positions with geometry_measure bounds, then move the tool into the target (entity_transform).',
                                       { 'target_bounds' => Na__Handlers__Selection.Na__Handlers__Selection__BoundsHash(target_box, ctx[:unit]),
                                         'tool_bounds'   => Na__Handlers__Selection.Na__Handlers__Selection__BoundsHash(first_box, ctx[:unit]) })
            end
            ctx[:warnings] << "Skipped tool id #{ids.join(', ')}: its box does not reach the target, so it was left untouched."
            tools - missing
        end

        def self.na_boxes_overlap?(first, second)
            (0..2).all? do |axis|
                first[0][axis] < second[1][axis] - NA_TOUCH_TOLERANCE && second[0][axis] < first[1][axis] - NA_TOUCH_TOLERANCE
            end
        end

        def self.na_capture_properties(target)
            {
                name: target.name.to_s,
                layer: target.layer,
                material: target.material,
                casts_shadows: target.casts_shadows?,
                receives_shadows: target.receives_shadows?,
                attributes: na_attribute_snapshot(target)
            }
        end

        def self.na_attribute_snapshot(entity)
            dictionaries = entity.attribute_dictionaries
            return [] unless dictionaries

            dictionaries.map do |dictionary|
                pairs = []
                dictionary.each_pair { |key, value| pairs << [key, value] }
                [dictionary.name, pairs]
            end
        end

        def self.na_restore_properties(result, properties, result_name)
            result.name = result_name || properties[:name] if result.respond_to?(:name=)
            result.layer = properties[:layer] if properties[:layer]
            result.material = properties[:material] if properties[:material]
            result.casts_shadows = properties[:casts_shadows]
            result.receives_shadows = properties[:receives_shadows]
            properties[:attributes].each do |dictionary_name, pairs|
                pairs.each { |key, value| result.set_attribute(dictionary_name, key, value) }
            end
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Booleans
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
