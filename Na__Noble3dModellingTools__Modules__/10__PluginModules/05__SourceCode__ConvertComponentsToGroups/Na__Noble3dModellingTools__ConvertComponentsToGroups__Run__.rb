# =============================================================================
# NA NOBLE3D MODELLING TOOLS - CONVERT COMPONENTS TO GROUPS - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ConvertComponentsToGroups__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ConvertComponentsToGroups
# PURPOSE    : Public execution entrypoint for converting selected components to groups
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ConvertComponentsToGroups

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Convert Selected Component Instances to Groups
        # ------------------------------------------------------------
        def self.Na__ConvertComponentsToGroups__Run
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            selected_components = Na__ConvertComponentsToGroups__Converter.Na__ConvertComponentsToGroups__Converter__CollectSelectedComponents(model)
            return na_result(false, 'Select one or more unlocked component instances, then run the command again.') if selected_components.empty?

            converted_groups = []
            operation_started = false

            Sketchup.status_text = 'Converting selected components to groups...'
            model.start_operation('Convert Components To Groups', true)
            operation_started = true

            selected_components.each do |component_instance|
                group = Na__ConvertComponentsToGroups__Converter.Na__ConvertComponentsToGroups__Converter__ConvertInstance(component_instance, 0)
                converted_groups << group if group&.valid?
            end

            model.selection.clear
            converted_groups.each { |group| model.selection.add(group) if group&.valid? }

            model.commit_operation
            Sketchup.status_text = ''
            na_result(true, "Converted #{converted_groups.length} component instance(s) to group(s).")
        rescue => error
            model.abort_operation if model && operation_started
            Sketchup.status_text = ''
            na_result(false, "Convert Components To Groups failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text)
            {
                success: !!success_flag,
                message: message_text.to_s
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ConvertComponentsToGroups
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
