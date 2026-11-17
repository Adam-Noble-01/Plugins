# =============================================================================
# NA SKETCHUP MCP - HANDLERS - ASSEMBLY RUN STUDIO
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__AssemblyRun__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__AssemblyRun
# PURPOSE    : assembly_run, assembly_run_edit
# CREATED    : 16-Nov-2026 (1.0.36); flip_side and a product on set_span_type 1.0.37
#
# A THIN SEAM:
# The rules live in Adam's Element Assembly Studio Pro, in its Assembly Run
# Studio (02__Src__AppModules/55__System__AssemblyRunSystem, reached through
# 60__System__McpOperations). These handlers only resolve what the call names
# - the run (instance_id), the path's points and the side point in the call's
# units - then call Na__AssemblyStudio::Na__McpOperations, swap the run it
# returns for its id and world bounds, and turn its refusals
# (Na__McpOperationsError: code, message, hint, details) into Na__McpError.
# If that plugin is not loaded, or is older than 2.7.0, both tools refuse and
# name the fix. flip_side and set_span_type's product need 2.7.2: an older
# plugin refuses them by name, with the actions it does have.
#
# COORDINATES:
# path and side are model (world) points in the call's units. Everything
# else that is a length (settings, a panel type's width, a column's width,
# path_local) is millimetres whatever units says, as the run stores it.
#
# UNDO:
# assembly_run does not mutate. assembly_run_edit has "operation": false: the
# run pipelines open ONE undo step of their own ("Create Assembly Run",
# "Make Panel Unique" ...) and build every window, door and cabinet of the
# run inside it. One Ctrl+Z (or model_undo) removes a whole run. That is
# also why assembly_run_edit is not allowed in batch_execute.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__AssemblyRun

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_READ_ACTIONS = %w[status parameters columns runs inspect layout].freeze
        NA_EDIT_ACTIONS = %w[build update set_path flip_side make_unique recode set_span_type rename
                             edit_path finish_path_edit discard_path_edit open_dialog].freeze
        NA_SLOW_ACTIONS = %w[build update set_path flip_side make_unique recode set_span_type runs inspect].freeze
        NA_PARTNER_ERROR = 'Na__AssemblyStudio::Na__McpOperationsError'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | assembly_run / assembly_run_edit
# -----------------------------------------------------------------------------

        def self.Na__Handlers__AssemblyRun__Read(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_READ_ACTIONS, nil, required: true)
            operations = na_operations
            arguments = na_arguments(params, ctx)
            ctx[:slow_reported] = true if NA_SLOW_ACTIONS.include?(action)
            result = na_forward(ctx) { operations.Na__AssemblyStudio__McpRunRead(action, arguments) }
            na_report_instance(result, ctx)
        end

        def self.Na__Handlers__AssemblyRun__Edit(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_EDIT_ACTIONS, nil, required: true)
            operations = na_operations
            arguments = na_arguments(params, ctx)
            ctx[:slow_reported] = true if NA_SLOW_ACTIONS.include?(action)
            result = na_forward(ctx) { operations.Na__AssemblyStudio__McpRunEdit(action, arguments) }
            na_report_instance(result, ctx)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Resolving What the Call Names
# -----------------------------------------------------------------------------

        # The Assembly Run seam, or a refusal that names the fix.
        def self.na_operations
            if defined?(::Na__AssemblyStudio::Na__McpOperations) &&
               ::Na__AssemblyStudio::Na__McpOperations.respond_to?(:Na__AssemblyStudio__McpRunRead)
                return ::Na__AssemblyStudio::Na__McpOperations
            end

            raise Na__McpError.new('unsupported',
                                   'The Assembly Run tools need Element Assembly Studio Pro 2.7.0 or newer, loaded in this SketchUp.',
                                   'Install or update Element Assembly Studio Pro, then use its Reload Scripts (or restart SketchUp).')
        end

        # The call's own values, plus the run and the points it names.
        def self.na_arguments(params, ctx)
            arguments = params.dup
            arguments['instance_object'] = na_instance(params, ctx) if Na__Params.Na__Params__Has(params, 'instance_id')
            if Na__Params.Na__Params__Has(params, 'path')
                points = Na__Params.Na__Params__Array(params, 'path', nil, required: true)
                arguments['path_points'] = points.each_with_index.map do |point, index|
                    Na__Units.Na__Units__Point(point, ctx[:unit], "path[#{index}]")
                end
            end
            if Na__Params.Na__Params__Has(params, 'side')
                arguments['side_point'] = Na__Units.Na__Units__Point(params['side'], ctx[:unit], 'side')
            end
            arguments
        end

        def self.na_instance(params, ctx)
            id = Na__Params.Na__Params__Integer(params, 'instance_id')
            instance = Na__EntityResolver.Na__EntityResolver__RequireInstance(ctx[:model], id, 'instance_id')
            return instance if instance.is_a?(Sketchup::ComponentInstance)

            raise Na__McpError.new('wrong_type', "Entity #{id} is a group, not an assembly run.",
                                   'List the runs with assembly_run runs and pass one of their instance_id values (or run_id, e.g. "ARN001").')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Results and Refusals
# -----------------------------------------------------------------------------

        # Swaps the run the seam returns for its id and world bounds.
        def self.na_report_instance(result, ctx)
            return result unless result.is_a?(Hash) && result.key?('instance_object')

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

    end # module Na__Handlers__AssemblyRun
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
