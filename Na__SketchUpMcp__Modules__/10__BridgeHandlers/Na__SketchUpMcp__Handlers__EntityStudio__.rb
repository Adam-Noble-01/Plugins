# =============================================================================
# NA SKETCHUP MCP - HANDLERS - ELEMENT ASSEMBLY STUDIO PRO
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__EntityStudio__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__EntityStudio
# PURPOSE    : entity_studio, entity_studio_edit
# CREATED    : 09-Nov-2026 (1.0.8)
#
# A THIN SEAM:
# The rules live in Adam's Element Assembly Studio Pro (also called Entity
# Studio Pro: 02__Src__AppModules/60__System__McpOperations). These handlers
# only resolve instance_id and position from the call, call
# Na__AssemblyStudio::Na__McpOperations, swap the instance it returns for its
# id and world bounds, and turn its refusals (Na__McpOperationsError: code,
# message, hint, details) into Na__McpError. If that plugin is not loaded,
# both tools refuse and name the fix.
#
# UNDO:
# entity_studio does not mutate. entity_studio_edit has "operation": false,
# because the door engines open and commit their own undo operation and
# SketchUp does not nest operations: one Ctrl+Z (or model_undo) removes a
# build. That is also why entity_studio_edit is not allowed in batch_execute.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__EntityStudio

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_READ_ACTIONS = %w[status list_presets get_preset list_handles inspect].freeze
        NA_EDIT_ACTIONS = %w[build update save_preset refresh_preview open_dialog reload].freeze
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
            result = na_forward(ctx) { operations.Na__AssemblyStudio__McpRead(action, arguments) }
            na_report_instance(result, ctx)
        end

        def self.Na__Handlers__EntityStudio__Edit(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_EDIT_ACTIONS, nil, required: true)
            operations = na_operations
            arguments = params.dup
            arguments['instance_object'] = na_instance(params, ctx) if Na__Params.Na__Params__Has(params, 'instance_id')
            if action == 'build'
                na_require_model_root(ctx)
                if Na__Params.Na__Params__Has(params, 'position')
                    arguments['position_point'] = Na__Units.Na__Units__Point(params['position'], ctx[:unit], 'position')
                end
            end
            ctx[:slow_reported] = true if %w[build update reload].include?(action)
            result = na_forward(ctx) { operations.Na__AssemblyStudio__McpEdit(action, arguments) }
            na_report_instance(result, ctx)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # The Element Assembly Studio seam, or a refusal that names the fix.
        def self.na_operations
            if defined?(::Na__AssemblyStudio::Na__McpOperations) &&
               ::Na__AssemblyStudio::Na__McpOperations.respond_to?(:Na__AssemblyStudio__McpRead)
                return ::Na__AssemblyStudio::Na__McpOperations
            end

            raise Na__McpError.new('unsupported',
                                   'The Entity Studio tools need Element Assembly Studio Pro 2.5.3 or newer, loaded in this SketchUp.',
                                   'Install or update Element Assembly Studio Pro, then use its Reload Scripts (or restart SketchUp).')
        end

        def self.na_instance(params, ctx)
            id = Na__Params.Na__Params__Integer(params, 'instance_id')
            instance = Na__EntityResolver.Na__EntityResolver__RequireInstance(ctx[:model], id, 'instance_id')
            return instance if instance.is_a?(Sketchup::ComponentInstance)

            raise Na__McpError.new('wrong_type', "Entity #{id} is a group, not an Element Assembly Studio element.",
                                   'Pass the id of its ADR component, e.g. from entity_query name_contains "ADR".')
        end

        # The door engines place into the active context in their own way, so
        # a build waits for the model root rather than guessing a transform.
        def self.na_require_model_root(ctx)
            path = ctx[:model].active_path
            return if path.nil? || path.empty?

            raise Na__McpError.new('context_error', 'A group or component is open for editing; the door engines place at the model root.',
                                   'Close it first with context_set {action: "close_all"}, then build.')
        end

        # Swaps the instance the seam returns for its id and world bounds.
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

    end # module Na__Handlers__EntityStudio
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
