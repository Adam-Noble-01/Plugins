# =============================================================================
# NA SKETCHUP MCP - HANDLERS - GROUPS AND COMPONENTS
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Components__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Components
# PURPOSE    : group_create, component_place, component_manage
# CREATED    : 2026
#
# GROUPING ONLY IN THE ACTIVE CONTEXT:
# Entities#add_group(existing_entities) is only called on the ACTIVE entities.
# Grouping entities that live in another collection is the classic way to crash
# SketchUp from Ruby, so it is refused with the fix (open their parent first
# with context_set) rather than risked on a user's model.
#
# PLACEMENT:
# component_place uses the same position / x_axis / z_axis / rotation_z / scale
# contract as geometry_create_solid, carried into any parent at any depth by
# Na__Creation. add_instance inside an open group reads its transform as world,
# which is exactly what input_to_reported produces for the active context.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Components

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MANAGE_ACTIONS = %w[make_unique replace_definition explode rename_definition set_definition_properties
                               save_definition_as reset_scale].freeze
        NA_SNAP_NAMES = { 'any' => 'SnapTo_Arbitrary', 'horizontal' => 'SnapTo_Horizontal',
                          'vertical' => 'SnapTo_Vertical', 'sloped' => 'SnapTo_Sloped' }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | group_create
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Components__GroupCreate(params, ctx)
            model = ctx[:model]
            entities = Na__EntityResolver.Na__EntityResolver__RequireEntities(model, Na__Params.Na__Params__IdArray(params, 'ids'))
            na_require_active_parent(model, entities)

            group = model.active_entities.add_group(entities)
            raise Na__McpError.new('operation_failed', 'SketchUp could not group those entities.', nil) unless group && group.valid?

            instance = group
            if Na__Params.Na__Params__Boolean(params, 'as_component', false)
                instance = group.to_component
                definition_name = params['definition_name'] || params['name']
                instance.definition.name = definition_name.to_s if definition_name && !definition_name.to_s.empty?
                instance.definition.description = params['description'].to_s if params['description']
            end
            Na__Creation.Na__Creation__ApplyCommonProperties([instance], params, ctx, false)
            Na__Creation.Na__Creation__EnsureName(instance, params, 'Group', ctx)
            Na__Serializer.Na__Serializer__Summary(instance, ctx, nil, true)
        end

        def self.na_require_active_parent(model, entities)
            active_path = Na__Coordinates.Na__Coordinates__ActivePath(model)
            active_owner = active_path.empty? ? model : active_path.last.definition
            outside = entities.reject { |entity| entity.parent == active_owner }
            return if outside.empty?

            raise Na__McpError.new('context_error',
                                   "group_create only groups entities of the active context; id #{outside.first.persistent_id} is elsewhere.",
                                   'Open the group that holds them with context_set action "open" (id = that group), then group them.')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | component_place
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Components__Place(params, ctx)
            model = ctx[:model]
            unit = ctx[:unit]
            definition = na_definition_for_place(params, model, ctx)
            prepared = Na__Creation.Na__Creation__Prepare(params.merge('wrap_in' => 'none'), ctx, 'none')
            scaling = na_scaling(params)

            positions = Na__Params.Na__Params__Array(params, 'positions', nil, max_items: 1000)
            positions ||= [params['position'] || [0, 0, 0]]
            placed = positions.each_with_index.map do |position, index|
                placement = Na__Handlers__Primitives.Na__Handlers__Primitives__InputPlacement(params.merge('position' => position), unit, [0.0, 0.0, 0.0])
                instance = prepared[:entities].add_instance(definition, prepared[:input_to_reported] * placement * scaling)
                raise Na__McpError.new('operation_failed', "Could not place instance #{index}.", nil) unless instance

                instance
            end

            Na__Creation.Na__Creation__ApplyCommonProperties(placed, params, ctx, false)
            summaries = placed.first(50).map { |instance| Na__Serializer.Na__Serializer__Summary(instance, ctx, prepared[:container][:path], false) }
            { 'definition' => definition.name, 'definition_id' => definition.persistent_id, 'placed' => placed.length,
              'ids' => placed.map(&:persistent_id), 'instances' => summaries, 'parent' => prepared[:container][:label], 'units' => unit }
        end

        def self.na_definition_for_place(params, model, ctx)
            if Na__Params.Na__Params__Has(params, 'skp_path')
                path = File.expand_path(params['skp_path'].to_s)
                raise Na__McpError.new('file_error', "File not found: #{path}.", nil) unless File.file?(path)
                raise Na__McpError.new('invalid_params', 'skp_path must be a .skp file.', nil) unless File.extname(path).casecmp?('.skp')

                begin
                    definition = model.definitions.load(path)
                rescue IOError, RuntimeError => error
                    raise Na__McpError.new('file_error', "SketchUp could not load #{File.basename(path)}: #{error.message}", 'The file may be empty, newer than this SketchUp, or the open model itself.')
                end
                ctx[:warnings] << "Loaded definition '#{definition.name}' from #{File.basename(path)}."
                return definition
            end

            reference = params.key?('definition_id') ? Na__Params.Na__Params__Integer(params, 'definition_id') : Na__Params.Na__Params__String(params, 'definition', nil)
            unless reference
                raise Na__McpError.new('invalid_params', 'Say which component to place.', 'Pass definition (name), definition_id, or skp_path.')
            end

            Na__EntityResolver.Na__EntityResolver__ResolveDefinition(model, reference)
        end

        # scale: number (uniform) or [sx, sy, sz]; applied in the component's own axes.
        def self.na_scaling(params)
            scale = params['scale']
            return Geom::Transformation.new if scale.nil?

            factors = scale.is_a?(Array) ? scale : [scale, scale, scale]
            unless factors.length == 3 && factors.all? { |factor| factor.is_a?(Numeric) && factor.to_f.abs > 1.0e-9 }
                raise Na__McpError.new('invalid_params', 'scale must be a non-zero number or [sx, sy, sz].', 'Negative factors mirror; zero is not allowed.')
            end

            Geom::Transformation.scaling(*factors.map(&:to_f))
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | component_manage
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Components__Manage(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_MANAGE_ACTIONS, nil, required: true)
            case action
            when 'make_unique'               then na_make_unique(params, ctx)
            when 'replace_definition'        then na_replace_definition(params, ctx)
            when 'explode'                   then na_explode(params, ctx)
            when 'rename_definition'         then na_rename_definition(params, ctx)
            when 'set_definition_properties' then na_definition_properties(params, ctx)
            when 'save_definition_as'        then na_save_definition(params, ctx)
            when 'reset_scale'               then na_reset_scale(params, ctx)
            end
        end

        def self.na_instances(params, ctx)
            Na__Params.Na__Params__IdArray(params, 'ids').map { |id| Na__EntityResolver.Na__EntityResolver__RequireInstance(ctx[:model], id, 'ids') }
        end

        def self.na_definition_param(params, ctx, key = 'definition')
            reference = params.key?("#{key}_id") ? Na__Params.Na__Params__Integer(params, "#{key}_id") : Na__Params.Na__Params__String(params, key, nil)
            raise Na__McpError.new('invalid_params', "Pass #{key} (name) or #{key}_id.", nil) unless reference

            Na__EntityResolver.Na__EntityResolver__ResolveDefinition(ctx[:model], reference, key)
        end

        def self.na_make_unique(params, ctx)
            instances = na_instances(params, ctx)
            instances.each(&:make_unique)
            { 'made_unique' => instances.length, 'definitions' => instances.map { |instance| instance.definition.name },
              'summary' => "#{instances.length} instance(s) now have their own definitions." }
        end

        def self.na_replace_definition(params, ctx)
            instances = na_instances(params, ctx)
            groups = instances.select { |instance| instance.is_a?(Sketchup::Group) }
            unless groups.empty?
                raise Na__McpError.new('wrong_type', 'Groups cannot swap definitions.', 'Convert them with group_create as_component, or pass component instance ids.')
            end

            replacement = na_definition_param(params, ctx, 'to_definition')
            instances.each { |instance| instance.definition = replacement }
            { 'replaced' => instances.length, 'definition' => replacement.name, 'summary' => "Swapped #{instances.length} instance(s) to '#{replacement.name}'." }
        end

        def self.na_explode(params, ctx)
            instances = na_instances(params, ctx)
            exploded = instances.flat_map { |instance| Array(instance.explode) }.select { |entity| entity.respond_to?(:persistent_id) && entity.valid? }
            types = Hash.new(0)
            exploded.each { |entity| types[Na__EntityResolver.Na__EntityResolver__TypeName(entity)] += 1 }
            { 'exploded' => instances.length, 'released' => types,
              'ids' => exploded.select { |entity| entity.is_a?(Sketchup::Drawingelement) }.first(500).map(&:persistent_id),
              'summary' => "Exploded #{instances.length} instance(s) into #{exploded.length} entities." }
        end

        def self.na_rename_definition(params, ctx)
            definition = na_definition_param(params, ctx)
            new_name = Na__Params.Na__Params__String(params, 'new_name', nil, required: true)
            definition.name = new_name
            { 'definition_id' => definition.persistent_id, 'name' => definition.name,
              'summary' => definition.name == new_name ? "Renamed to '#{new_name}'." : "Name taken; SketchUp used '#{definition.name}'." }
        end

        def self.na_definition_properties(params, ctx)
            definition = na_definition_param(params, ctx)
            definition.description = params['description'].to_s if params.key?('description')
            behavior_params = Na__Params.Na__Params__Hash(params, 'behavior', {}) || {}
            na_apply_behavior(definition.behavior, behavior_params)
            { 'definition_id' => definition.persistent_id, 'name' => definition.name, 'description' => definition.description.to_s,
              'behavior' => Na__Handlers__Collections.Na__Handlers__Collections__BehaviorHash(definition.behavior) }
        end

        def self.na_apply_behavior(behavior, settings)
            settings.each do |key, value|
                case key
                when 'is2d' then behavior.is2d = value ? true : false
                when 'cuts_opening' then behavior.cuts_opening = value ? true : false
                when 'always_face_camera' then behavior.always_face_camera = value ? true : false
                when 'shadows_face_sun' then behavior.shadows_face_sun = value ? true : false
                when 'no_scale_mask' then behavior.no_scale_mask = value.to_i
                when 'glue_to'
                    if value.to_s == 'none'
                        behavior.is2d = false
                    else
                        constant_name = NA_SNAP_NAMES[value.to_s]
                        raise Na__McpError.new('invalid_params', "behavior.glue_to '#{value}' is not recognised.", "Use: none, #{NA_SNAP_NAMES.keys.join(', ')}.") unless constant_name

                        behavior.is2d = true
                        behavior.snapto = Object.const_get(constant_name)
                    end
                else
                    raise Na__McpError.new('invalid_params', "Unknown behavior key '#{key}'.", 'Use is2d, cuts_opening, always_face_camera, shadows_face_sun, no_scale_mask, glue_to.')
                end
            end
        end

        def self.na_save_definition(params, ctx)
            definition = na_definition_param(params, ctx)
            path = Na__Handlers__ModelFile.Na__Handlers__ModelFile__TargetPath(params, '.skp')
            unless definition.save_as(path)
                raise Na__McpError.new('operation_failed', "SketchUp could not save '#{definition.name}'.", 'Check the folder is writable.')
            end

            { 'saved' => true, 'path' => path, 'definition' => definition.name, 'bytes' => File.size(path) }
        end

        # Keeps each instance's position, rotation and mirroring; drops its scale.
        def self.na_reset_scale(params, ctx)
            instances = na_instances(params, ctx)
            instances.each do |instance|
                parts = Na__Coordinates.Na__Coordinates__Decompose(instance.transformation)
                axes = parts[:axes].map { |axis| Geom::Vector3d.new(*axis) }
                instance.transformation = Geom::Transformation.axes(Geom::Point3d.new(*parts[:origin]), *axes)
            end
            { 'reset' => instances.length, 'summary' => "Removed scaling from #{instances.length} instance(s)." }
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Components
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
