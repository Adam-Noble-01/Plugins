# =============================================================================
# NA SKETCHUP MCP - HANDLERS - ELEMENT ASSEMBLY STUDIO PRO
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__EntityStudio__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__EntityStudio
# PURPOSE    : entity_studio, entity_studio_edit
# CREATED    : 09-Nov-2026 (1.0.8)
# UPDATED    : 11-Nov-2026 (1.0.27) Every product, every setting, openings
#
# A THIN SEAM:
# The rules live in Adam's Element Assembly Studio Pro (also called Entity
# Studio Pro: 02__Src__AppModules/60__System__McpOperations). These handlers
# only resolve what the call names - instance_id, a wall (wall_id, path) and
# its reported-to-world transform, points and directions in the call's units
# - then call Na__AssemblyStudio::Na__McpOperations, swap the instance it
# returns for its id and world bounds, and turn its refusals
# (Na__McpOperationsError: code, message, hint, details) into Na__McpError.
# If that plugin is not loaded, both tools refuse and name the fix.
#
# COORDINATES:
# A wall's faces are read in its definition's REPORTED coordinates and
# carried to world with Na__Coordinates__ReportedToWorld (container path +
# the wall), so an open group, a moved, rotated or nested wall all read
# true. Points and directions given in the call are world.
#
# UNDO:
# entity_studio does not mutate. entity_studio_edit has "operation": false,
# because the Studio's build pipelines open and commit their own undo
# operation (with the dialog's names) and SketchUp does not nest
# operations: one Ctrl+Z (or model_undo) removes a build. That is also why
# entity_studio_edit is not allowed in batch_execute.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__EntityStudio

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_READ_ACTIONS = %w[status parameters elements inspect openings list_presets get_preset assets list_handles].freeze
        NA_EDIT_ACTIONS = %w[build update rename place_copies export_dxf save_preset update_preset archive_preset restore_preset
                             refresh_preview open_dialog reload].freeze
        NA_SLOW_ACTIONS = %w[build update rename place_copies reload export_dxf elements].freeze
        NA_PARTNER_ERROR = 'Na__AssemblyStudio::Na__McpOperationsError'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | entity_studio / entity_studio_edit
# -----------------------------------------------------------------------------

        def self.Na__Handlers__EntityStudio__Read(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_READ_ACTIONS, nil, required: true)
            operations = na_operations
            arguments = params.dup
            arguments['instance_object'] = na_instance(params, ctx) if Na__Params.Na__Params__Has(params, 'instance_id')
            if action == 'openings'
                wall, to_world = na_wall(params, ctx, 'wall_id')
                arguments['wall_object']   = wall
                arguments['wall_to_world'] = to_world
                na_outside(params, arguments, ctx, '')
                na_plane(params, arguments, ctx, '') if Na__Params.Na__Params__Has(params, 'plane')
            end
            ctx[:slow_reported] = true if NA_SLOW_ACTIONS.include?(action)
            result = na_forward(ctx) { operations.Na__AssemblyStudio__McpRead(action, arguments) }
            na_report_instance(result, ctx)
        end

        def self.Na__Handlers__EntityStudio__Edit(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_EDIT_ACTIONS, nil, required: true)
            operations = na_operations
            arguments = params.dup
            arguments['instance_object'] = na_instance(params, ctx) if Na__Params.Na__Params__Has(params, 'instance_id')
            na_require_model_root(ctx) if (action == 'build' || action == 'place_copies') && params['dry_run'] != true
            if Na__Params.Na__Params__Has(params, 'position')
                arguments['position_point'] = Na__Units.Na__Units__Point(params['position'], ctx[:unit], 'position')
            end
            if Na__Params.Na__Params__Has(params, 'direction')
                arguments['direction_vector'] = Na__Units.Na__Units__Direction(params['direction'], 'direction')
            end
            na_stations(params, arguments, ctx) if Na__Params.Na__Params__Has(params, 'stations')
            na_opening(params, arguments, ctx) if Na__Params.Na__Params__Has(params, 'opening')
            na_run(params, arguments, ctx) if Na__Params.Na__Params__Has(params, 'run')
            if Na__Params.Na__Params__Has(params, 'run_offset')
                arguments['run_offset_mm'] = Na__Units.Na__Units__ToInches(params['run_offset'], ctx[:unit], 'run_offset') * 25.4
            end
            if action == 'build'
                na_parent(params, arguments, ctx) if Na__Params.Na__Params__Has(params, 'parent_id')
                if Na__Params.Na__Params__Has(params, 'instance_name')
                    arguments['instance_name'] = Na__Params.Na__Params__String(params, 'instance_name', '', allow_empty: true)
                end
            end
            ctx[:slow_reported] = true if NA_SLOW_ACTIONS.include?(action)
            result = na_forward(ctx) { operations.Na__AssemblyStudio__McpEdit(action, arguments) }
            na_report_instance(result, ctx)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Resolving What the Call Names
# -----------------------------------------------------------------------------

        # The Element Assembly Studio seam, or a refusal that names the fix.
        def self.na_operations
            if defined?(::Na__AssemblyStudio::Na__McpOperations) &&
               ::Na__AssemblyStudio::Na__McpOperations.respond_to?(:Na__AssemblyStudio__McpRead)
                return ::Na__AssemblyStudio::Na__McpOperations
            end

            raise Na__McpError.new('unsupported',
                                   'The Entity Studio tools need Element Assembly Studio Pro 2.6.0 or newer, loaded in this SketchUp.',
                                   'Install or update Element Assembly Studio Pro, then use its Reload Scripts (or restart SketchUp).')
        end

        def self.na_instance(params, ctx)
            id = Na__Params.Na__Params__Integer(params, 'instance_id')
            instance = Na__EntityResolver.Na__EntityResolver__RequireInstance(ctx[:model], id, 'instance_id')
            return instance if instance.is_a?(Sketchup::ComponentInstance)

            raise Na__McpError.new('wrong_type', "Entity #{id} is a group, not an Element Assembly Studio element.",
                                   'List the elements with entity_studio elements and pass one of their instance_id values.')
        end

        # The wall (a group or component) and its reported -> world transform.
        def self.na_wall(params, ctx, label)
            id = Na__Params.Na__Params__Integer(params, 'wall_id', nil, required: true)
            wall = Na__EntityResolver.Na__EntityResolver__RequireInstance(ctx[:model], id, label)
            container = if Na__Params.Na__Params__Has(params, 'path')
                            Na__Coordinates.Na__Coordinates__PathFromIds(ctx[:model], Na__Params.Na__Params__IdArray(params, 'path'))
                        else
                            Na__Coordinates.Na__Coordinates__ContainerPathForEntity(ctx[:model], wall, ctx[:warnings])
                        end
            [wall, Na__Coordinates.Na__Coordinates__ReportedToWorld(ctx[:model], container + [wall])]
        end

        def self.na_outside(source, arguments, ctx, label_prefix)
            if Na__Params.Na__Params__Has(source, 'outside')
                arguments['outside_vector'] = Na__Units.Na__Units__Direction(source['outside'], "#{label_prefix}outside")
            end
            if Na__Params.Na__Params__Has(source, 'outside_point')
                arguments['outside_point'] = Na__Units.Na__Units__Point(source['outside_point'], ctx[:unit], "#{label_prefix}outside_point")
            end
        end

        # opening: a wall's opening by index, or the points themselves.
        def self.na_opening(params, arguments, ctx)
            opening = Na__Params.Na__Params__Hash(params, 'opening', nil, required: true)
            if Na__Params.Na__Params__Has(opening, 'wall_id')
                wall, to_world = na_wall(opening, ctx, 'opening.wall_id')
                spec = {
                    'wall_object'   => wall,
                    'wall_to_world' => to_world,
                    'index'         => Na__Params.Na__Params__Integer(opening, 'index', nil, required: true, min: 0)
                }
                na_outside(opening, spec, ctx, 'opening.')
                na_plane(opening, spec, ctx, 'opening.') if Na__Params.Na__Params__Has(opening, 'plane')
                arguments['opening_wall'] = spec
                return
            end

            unless Na__Params.Na__Params__Has(opening, 'point_a') && Na__Params.Na__Params__Has(opening, 'point_b')
                raise Na__McpError.new('invalid_params', 'opening needs wall_id and index, or point_a and point_b.',
                                       'List a wall\'s openings with entity_studio openings (wall_id), then pass {wall_id, index}.')
            end
            points = {
                a: Na__Units.Na__Units__Point(opening['point_a'], ctx[:unit], 'opening.point_a'),
                b: Na__Units.Na__Units__Point(opening['point_b'], ctx[:unit], 'opening.point_b')
            }
            points[:d] = Na__Units.Na__Units__Point(opening['point_d'], ctx[:unit], 'opening.point_d') if Na__Params.Na__Params__Has(opening, 'point_d')
            arguments['opening_points'] = points
        end

        # run: a cabinet run, as Measure Run picks it.
        def self.na_run(params, arguments, ctx)
            run = Na__Params.Na__Params__Hash(params, 'run', nil, required: true)
            arguments['run_points'] = {
                a:    Na__Units.Na__Units__Point(run['point_a'], ctx[:unit], 'run.point_a'),
                b:    Na__Units.Na__Units__Point(run['point_b'], ctx[:unit], 'run.point_b'),
                side: Na__Units.Na__Units__Point(run['side'], ctx[:unit], 'run.side')
            }
        end

        # stations: placement list for place_copies.
        def self.na_stations(params, arguments, ctx)
            raw = Na__Params.Na__Params__Array(params, 'stations', nil, required: true, min_items: 1)
            arguments['resolved_stations'] = raw.each_with_index.map do |entry, idx|
                unless entry.is_a?(Hash)
                    raise Na__McpError.new('invalid_params', "stations[#{idx}] must be an object.", nil)
                end

                row = {
                    'position_point' => Na__Units.Na__Units__Point(
                        Na__Params.Na__Params__Required(entry, 'position'),
                        ctx[:unit],
                        "stations[#{idx}].position"
                    ),
                    'rotation_z_deg' => Na__Params.Na__Params__Number(entry, 'rotation_z_deg', 0.0),
                    'name'           => Na__Params.Na__Params__String(entry, 'name', '', allow_empty: true),
                    'tag'            => Na__Params.Na__Params__String(entry, 'tag', '', allow_empty: true)
                }
                if Na__Params.Na__Params__Has(entry, 'direction')
                    row['direction_vector'] = Na__Units.Na__Units__Direction(entry['direction'], "stations[#{idx}].direction")
                end
                row
            end
        end

        # plane: optional vertical face plane filter for multi-wing compound wall solids (1.0.44).
        def self.na_plane(source, arguments, ctx, label_prefix)
            raw = Na__Params.Na__Params__Hash(source, 'plane', nil, required: true)
            spec = {}
            if Na__Params.Na__Params__Has(raw, 'axis')
                spec[:axis] = Na__Params.Na__Params__Enum(raw, 'axis', %w[x y], nil, required: true)
            end
            if Na__Params.Na__Params__Has(raw, 'value_mm')
                spec[:value_in] = Na__Params.Na__Params__Number(raw, 'value_mm', nil, required: true) / 25.4
            elsif Na__Params.Na__Params__Has(raw, 'value')
                spec[:value_in] = Na__Units.Na__Units__ToInches(raw['value'], ctx[:unit], "#{label_prefix}plane.value")
            end
            if Na__Params.Na__Params__Has(raw, 'normal')
                spec[:normal] = Na__Units.Na__Units__Direction(raw['normal'], "#{label_prefix}plane.normal")
            end
            if Na__Params.Na__Params__Has(raw, 'point')
                spec[:point] = Na__Units.Na__Units__Point(raw['point'], ctx[:unit], "#{label_prefix}plane.point")
            end
            if Na__Params.Na__Params__Has(raw, 'outside')
                spec[:outside] = Na__Units.Na__Units__Direction(raw['outside'], "#{label_prefix}plane.outside")
            end
            if Na__Params.Na__Params__Has(raw, 'tolerance_mm')
                spec[:tolerance_in] = Na__Params.Na__Params__Number(raw, 'tolerance_mm', nil, required: true, min: 0.01) / 25.4
            elsif Na__Params.Na__Params__Has(raw, 'tolerance')
                spec[:tolerance_in] = Na__Units.Na__Units__Positive(raw['tolerance'], ctx[:unit], "#{label_prefix}plane.tolerance")
            end
            if Na__Params.Na__Params__Has(raw, 'thickness_mm')
                spec[:thickness_in] = Na__Params.Na__Params__Number(raw, 'thickness_mm', nil, required: true, min: 1.0) / 25.4
            elsif Na__Params.Na__Params__Has(raw, 'thickness')
                spec[:thickness_in] = Na__Units.Na__Units__Positive(raw['thickness'], ctx[:unit], "#{label_prefix}plane.thickness")
            end
            arguments['plane_spec'] = spec
        end

        # parent_id: optional target container to reparent the built element into atomically (1.0.44).
        def self.na_parent(params, arguments, ctx)
            parent_id = Na__Params.Na__Params__Integer(params, 'parent_id', nil, required: true, min: 0)
            return if parent_id.zero?

            parent_path = Na__Params.Na__Params__Has(params, 'parent_path') ? Na__Params.Na__Params__IdArray(params, 'parent_path') : nil
            container = Na__Coordinates.Na__Coordinates__ResolveContainer(ctx[:model], parent_id, parent_path, ctx[:warnings])
            owner = container[:owner]
            if owner && !owner.definition.group? && owner.definition.instances.length > 1
                raise Na__McpError.new('shared_parent',
                                       "The destination component '#{owner.definition.name}' is used #{owner.definition.instances.length} times: building into it would appear in every copy.",
                                       'Make it unique first (component_manage make_unique), or pass a group parent_id.')
            end
            arguments['parent_entities'] = container[:entities]
            arguments['parent_to_world'] = container[:to_world]
            arguments['parent_label']    = container[:label]
        end

        # The build pipelines place at the model root, so a build waits for it
        # rather than guessing a transform.
        def self.na_require_model_root(ctx)
            path = ctx[:model].active_path
            return if path.nil? || path.empty?

            raise Na__McpError.new('context_error', 'A group or component is open for editing; Element Assembly Studio builds at the model root.',
                                   'Close it first with context_set {action: "close_all"}, build, then move the element with entity_reparent if it belongs inside.')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Results and Refusals
# -----------------------------------------------------------------------------

        # Swaps the instance(s) the seam returns for their ids and world bounds.
        def self.na_report_instance(result, ctx)
            return result unless result.is_a?(Hash)

            if result.key?('created_objects')
                instances = Array(result.delete('created_objects'))
                result['created'] = instances.filter_map do |inst|
                    next nil unless inst && inst.valid?

                    entry = {
                        'instance_id' => inst.persistent_id,
                        'name'        => inst.name,
                        'tag'         => Na__EntityResolver.Na__EntityResolver__TagDisplayName(inst.layer)
                    }
                    corners = Na__Serializer.Na__Serializer__WorldBoundsOfMany([inst], ctx)
                    if corners
                        minimum, maximum = corners.map { |point| point.map { |value| Na__Units.Na__Units__FromInches(value, ctx[:unit]).round(2) } }
                        entry['bounds'] = { 'min' => minimum, 'max' => maximum, 'size' => [0, 1, 2].map { |axis| (maximum[axis] - minimum[axis]).round(2) } }
                    end
                    entry
                end
            end

            return result unless result.key?('instance_object')

            instance = result.delete('instance_object')
            return result unless instance && instance.valid?

            result['instance_id'] = instance.persistent_id
            corners = Na__Serializer.Na__Serializer__WorldBoundsOfMany([instance], ctx)
            if corners
                minimum, maximum = corners.map { |point| point.map { |value| Na__Units.Na__Units__FromInches(value, ctx[:unit]).round(2) } }
                result['bounds'] = { 'min' => minimum, 'max' => maximum, 'size' => [0, 1, 2].map { |axis| (maximum[axis] - minimum[axis]).round(2) } }
            end
            result
        end

        # Runs the seam call, moves its warnings onto the response and turns
        # its refusals into Na__McpError.
        def self.na_forward(ctx)
            result = yield
            if result.is_a?(Hash)
                Array(result.delete('warnings')).each { |text| ctx[:warnings] << text.to_s }
            end
            result
        rescue Na__McpError
            raise
        rescue StandardError => error
            raise unless error.class.name.to_s == NA_PARTNER_ERROR

            raise Na__McpError.new(error.na_code, error.message, error.na_hint, error.na_details)
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__EntityStudio
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
