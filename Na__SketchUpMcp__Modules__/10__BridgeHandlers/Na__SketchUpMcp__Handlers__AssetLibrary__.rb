# =============================================================================
# NA SKETCHUP MCP - HANDLERS - COMPONENT LIBRARY
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__AssetLibrary__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__AssetLibrary
# PURPOSE    : asset_library, asset_library_edit
# CREATED    : 2026
#
# A THIN SEAM:
# The library rules live in Adam's Component Editor Tools (Na Noble3d Modelling
# Tools: 10__PluginModules/21__SourceCode__ComponentEditorTools/12__McpOperations).
# These handlers only resolve the component to save from the open model, call
# Na__ComponentEditorTools::Na__McpOperations, and turn its refusals
# (Na__McpOperationsError: code, message, hint, details) into Na__McpError. If
# that plugin is not loaded, both tools refuse and name the fix.
#
# UNDO:
# Both tools run outside the router's operation (asset_library does not
# mutate; asset_library_edit has "operation": false), because the library code
# opens files inside its own operation that it always aborts, and SketchUp does
# not nest operations. That is also why neither is allowed in batch_execute.
# Only save with rename_in_model changes the model, as its own undo step.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__AssetLibrary

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_READ_ACTIONS = %w[overview browse get next_code check_name audit].freeze
        NA_EDIT_ACTIONS = %w[save rename move update archive create_folder apply_plan revert refresh].freeze
        NA_PARTNER_ERROR = 'Na__ComponentEditorTools::Na__McpOperationsError'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | asset_library / asset_library_edit
# -----------------------------------------------------------------------------

        def self.Na__Handlers__AssetLibrary__Read(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_READ_ACTIONS, nil, required: true)
            operations = na_operations
            ctx[:slow_reported] = true if action == 'audit'
            na_forward(ctx) { operations.Na__ComponentEditorTools__McpRead(action, params) }
        end

        def self.Na__Handlers__AssetLibrary__Edit(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_EDIT_ACTIONS, nil, required: true)
            operations = na_operations
            arguments = params.dup
            arguments['definition_object'] = na_definition_to_save(params, ctx) if action == 'save'
            # A plan stops itself after time_budget_s and says how to continue.
            ctx[:slow_reported] = true if action == 'apply_plan'
            na_forward(ctx) { operations.Na__ComponentEditorTools__McpEdit(action, arguments) }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # The Component Editor Tools seam, or a refusal that names the fix.
        def self.na_operations
            if defined?(::Na__ComponentEditorTools::Na__McpOperations) &&
               ::Na__ComponentEditorTools::Na__McpOperations.respond_to?(:Na__ComponentEditorTools__McpRead)
                return ::Na__ComponentEditorTools::Na__McpOperations
            end

            raise Na__McpError.new('unsupported',
                                   'The component library tools need Na Noble3d Modelling Tools with Component Editor Tools 0.6.4 or newer.',
                                   'Install or update Na Noble3d Modelling Tools, then use its Reload Plugin Data (or restart SketchUp).')
        end

        # save: the definition named, by id, or behind a placed instance.
        def self.na_definition_to_save(params, ctx)
            model = ctx[:model]
            if Na__Params.Na__Params__Has(params, 'instance_id')
                instance = Na__EntityResolver.Na__EntityResolver__RequireInstance(model, Na__Params.Na__Params__Integer(params, 'instance_id'), 'instance_id')
                unless instance.is_a?(Sketchup::ComponentInstance)
                    raise Na__McpError.new('wrong_type', 'instance_id is a group, not a component.',
                                           'Make it a component first (group_create as_component), then save it.')
                end

                return instance.definition
            end

            reference = if params.key?('definition_id')
                            Na__Params.Na__Params__Integer(params, 'definition_id')
                        else
                            Na__Params.Na__Params__String(params, 'definition', nil)
                        end
            unless reference
                raise Na__McpError.new('invalid_params', 'Say which component to save.', 'Pass definition (its name), definition_id, or instance_id.')
            end

            Na__EntityResolver.Na__EntityResolver__ResolveDefinition(model, reference, 'definition')
        end

        # Runs the library call, moves its warnings onto the response and turns
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

    end # module Na__Handlers__AssetLibrary
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
