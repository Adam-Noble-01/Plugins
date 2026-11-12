# =============================================================================
# NA SKETCHUP MCP - HANDLERS - PROFILE PATH TRACER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__ProfileTracer__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__ProfileTracer
# PURPOSE    : profile_tracer, profile_tracer_edit, profile_tracer_library
# CREATED    : 11-Nov-2026 (1.0.24)
#
# A THIN SEAM:
# The rules live in Adam's Na Profile Path Tracer (1.6.17 or newer:
# 02__Src__AppModules/60__System__McpOperations). These handlers check the
# action, drop keys sent as null, and turn what only the MCP can resolve into
# objects the seam takes as they are:
#   path            [[x,y,z], ...] or [[[x,y,z], ...], ...] -> 'path_runs'
#                   (world Geom::Point3d, inches)
#   path_edge_ids   edges, curves (every edge of the curve) or groups (their
#                   own edges) -> 'path_segments', world
#   parent_id       -> 'container' (entities, reported-to-world, owner): where
#                   create builds, the active context when omitted
#   wrapper.origin  -> a world Geom::Point3d
#   profile_face_id -> 'profile_face_object'
# and hands over the open model, 'per_inch' (the call's unit) and two
# resolvers the seam calls for any trace: 'world_of' (an instance's
# definition coordinates -> world, open contexts and shared definitions
# included, through Na__Coordinates) and 'path_of' (the instances above an
# entity). The seam's refusals (Na__McpOperationsError: code, message, hint,
# details) become Na__McpError. Without the plugin every tool refuses and
# names the fix.
#
# UNDO:
# profile_tracer_edit has "operation": false and opens the step itself:
# "MCP: Profile Tracer Edit (<action>)" through
# Na__CommandRouter__WithOperation, so a call inside batch_execute joins the
# batch's step instead (the tool is batchable: every engine runs with
# wrap_in_operation: false). open_dialog and reload change no model and open
# no step; reload is refused inside a batch. profile_tracer_library writes
# files, never the model: no step, and it is in NA_BATCH_FORBIDDEN.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__ProfileTracer

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_READ_ACTIONS      = %w[status profiles profile traces trace check_path].freeze
        NA_EDIT_ACTIONS      = %w[create set_path set_placement swap_profile set_local_profile revert_local
                                  regenerate recreate rename delete open_dialog reload].freeze
        NA_LIBRARY_ACTIONS   = %w[save_new overwrite set_meta rename_file redatum flip delete].freeze
        NA_EDIT_WITHOUT_UNDO = %w[open_dialog reload].freeze
        NA_BUILD_ACTIONS     = %w[create recreate].freeze
        NA_PARTNER_ERROR     = 'Na__ProfileTools__ProfilePathTracer::Na__McpOperationsError'.freeze
        NA_UNDO_NAME         = 'MCP: Profile Tracer Edit'.freeze
        NA_MAX_PATH_POINTS   = 5000
        NA_MAX_PATH_EDGES    = 5000

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | profile_tracer / profile_tracer_edit / profile_tracer_library
# -----------------------------------------------------------------------------

        def self.Na__Handlers__ProfileTracer__Read(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_READ_ACTIONS, nil, required: true)
            operations = na_operations
            arguments = na_arguments(params, ctx, action)
            na_forward(ctx) { operations.Na__ProfileTracer__McpRead(action, arguments) }
        end

        def self.Na__Handlers__ProfileTracer__Edit(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_EDIT_ACTIONS, nil, required: true)
            operations = na_operations
            if action == 'reload' && ctx[:in_operation]
                raise Na__McpError.new('invalid_params', 'reload is not allowed inside batch_execute: it replaces the plugin\'s code mid-step.',
                                       'Call profile_tracer_edit {action: "reload"} on its own.')
            end
            arguments = na_arguments(params, ctx, action)
            call = -> { na_forward(ctx) { operations.Na__ProfileTracer__McpEdit(action, arguments) } }
            return call.call if NA_EDIT_WITHOUT_UNDO.include?(action)

            ctx[:slow_reported] = true
            Na__CommandRouter.Na__CommandRouter__WithOperation(ctx, "#{NA_UNDO_NAME} (#{action})") { call.call }
        end

        def self.Na__Handlers__ProfileTracer__Library(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_LIBRARY_ACTIONS, nil, required: true)
            operations = na_operations
            arguments = na_arguments(params, ctx, action)
            na_forward(ctx) { operations.Na__ProfileTracer__McpLibrary(action, arguments) }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # The Profile Path Tracer seam, or a refusal that names the fix.
        def self.na_operations
            if defined?(::Na__ProfileTools__ProfilePathTracer::Na__McpOperations) &&
               ::Na__ProfileTools__ProfilePathTracer::Na__McpOperations.respond_to?(:Na__ProfileTracer__McpRead)
                return ::Na__ProfileTools__ProfilePathTracer::Na__McpOperations
            end

            raise Na__McpError.new('unsupported',
                                   'The profile tracer tools need Na Profile Path Tracer 1.6.17 or newer, loaded in this SketchUp.',
                                   'Update the Profile Path Tracer, then use its Reload Plugin Files (Settings tab) or restart SketchUp.')
        end

        # The call's arguments without 'action' and without keys sent as null,
        # plus what only the MCP can resolve (see the header).
        def self.na_arguments(params, ctx, action)
            arguments = params.each_with_object({}) do |(key, value), list|
                next if key.to_s == 'action' || !Na__Params.Na__Params__Has(params, key)

                list[key.to_s] = value
            end
            model = ctx[:model]
            arguments['model_object'] = model
            arguments['per_inch']     = Na__Units.Na__Units__FromInches(1.0, ctx[:unit])
            arguments['world_of']     = ->(instance) { na_world_of(ctx, instance) }
            arguments['path_of']      = ->(entity) { Na__Coordinates.Na__Coordinates__ContainerPathForEntity(model, entity, ctx[:warnings]) }

            arguments['path_runs']     = na_path_runs(params['path'], ctx) if Na__Params.Na__Params__Has(params, 'path')
            arguments['path_segments'] = na_path_segments(params['path_edge_ids'], ctx) if Na__Params.Na__Params__Has(params, 'path_edge_ids')
            if Na__Params.Na__Params__Has(params, 'profile_face_id')
                arguments['profile_face_object'] = Na__EntityResolver.Na__EntityResolver__RequireOfClass(model, Na__Params.Na__Params__Integer(params, 'profile_face_id'),
                                                                                                       Sketchup::Face, 'profile_face_id')
            end
            if NA_BUILD_ACTIONS.include?(action) && (action == 'create' || Na__Params.Na__Params__Has(params, 'parent_id'))
                parent_id = Na__Params.Na__Params__Has(params, 'parent_id') ? Na__Params.Na__Params__Integer(params, 'parent_id') : nil
                path_ids  = Na__Params.Na__Params__Has(params, 'path_ids') ? Array(params['path_ids']).map(&:to_i) : nil
                arguments['container'] = Na__Coordinates.Na__Coordinates__ResolveContainer(model, parent_id, path_ids, ctx[:warnings])
            end
            wrapper = params['wrapper']
            if wrapper.is_a?(Hash) && wrapper['origin'].is_a?(Array)
                arguments['wrapper'] = wrapper.merge('origin' => Na__Units.Na__Units__Point(wrapper['origin'], ctx[:unit], 'wrapper.origin'))
            end
            arguments
        end

        # An instance's definition coordinates -> world, whatever is open.
        def self.na_world_of(ctx, instance)
            path = Na__Coordinates.Na__Coordinates__ContainerPathForEntity(ctx[:model], instance, ctx[:warnings]) + [instance]
            Na__Coordinates.Na__Coordinates__ReportedToWorld(ctx[:model], path)
        end

        # One run [[x,y,z], ...] or several [[[x,y,z], ...], ...] -> world points.
        def self.na_path_runs(value, ctx)
            unless value.is_a?(Array) && !value.empty?
                raise Na__McpError.new('invalid_params', 'path must be a list of [x, y, z] points, or a list of such lists (one per run).', nil)
            end
            runs = value.first.is_a?(Array) && value.first.first.is_a?(Array) ? value : [value]
            count = runs.sum { |run| Array(run).length }
            if count > NA_MAX_PATH_POINTS
                raise Na__McpError.new('invalid_params', "path has #{count} points; the most is #{NA_MAX_PATH_POINTS}.", 'Split it into several traces.')
            end
            runs.each_with_index.map do |run, run_index|
                unless run.is_a?(Array) && run.length >= 2
                    raise Na__McpError.new('invalid_params', "path run #{run_index} needs two or more points.", nil)
                end
                run.each_with_index.map { |point, index| Na__Units.Na__Units__Point(point, ctx[:unit], "path[#{run_index}][#{index}]") }
            end
        end

        # Edges (a curve's edge brings the whole curve) and groups or
        # components (their own edges) -> world [start, end] pairs.
        def self.na_path_segments(value, ctx)
            ids = Array(value)
            raise Na__McpError.new('invalid_params', 'path_edge_ids must list edge, curve or group ids.', nil) if ids.empty?

            model = ctx[:model]
            edges = []
            ids.each do |id|
                entity = Na__EntityResolver.Na__EntityResolver__RequireEntity(model, id.to_i, 'path_edge_ids')
                if entity.is_a?(Sketchup::Edge)
                    curve = entity.curve
                    edges.concat(curve ? curve.edges : [entity])
                elsif Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                    edges.concat(Na__EntityResolver.Na__EntityResolver__InstanceEntities(entity).grep(Sketchup::Edge))
                else
                    raise Na__McpError.new('wrong_type', "path_edge_ids: #{id} is a #{Na__EntityResolver.Na__EntityResolver__TypeName(entity)}, not an edge, curve or group.", nil)
                end
            end
            edges = edges.uniq
            if edges.length > NA_MAX_PATH_EDGES
                raise Na__McpError.new('invalid_params', "path_edge_ids gives #{edges.length} edges; the most is #{NA_MAX_PATH_EDGES}.", nil)
            end
            edges.map do |edge|
                to_world = Na__Serializer.Na__Serializer__ToWorld(ctx, Na__Serializer.Na__Serializer__ContainerPath(ctx, edge))[:transform]
                [edge.start.position.transform(to_world), edge.end.position.transform(to_world)]
            end
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

    end # module Na__Handlers__ProfileTracer
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
