# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SELECTED HIERARCHY TAG REPORTER - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SelectedHierarchyTagReporter__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SelectedHierarchyTagReporter
# PURPOSE    : Public execution entrypoint for entity hierarchy reporting
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SelectedHierarchyTagReporter

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        def self.Na__SelectedHierarchyTagReporter__Run
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            report_data = Na__SelectedHierarchyTagReporter__TreeData.Na__SelectedHierarchyTagReporter__TreeData__Build(false)
            Na__SelectedHierarchyTagReporter__DialogManager.Na__SelectedHierarchyTagReporter__DialogManager__ShowDialog(report_data)

            na_result(true, na_result_message(report_data))
        rescue => error
            na_result(false, "Entity Tree Reporter failed: #{error.class}: #{error.message}")
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helpers
# -----------------------------------------------------------------------------

        def self.na_result_message(report_data)
            selection_count = report_data.fetch(:selection_count, 0).to_i
            return 'Entity Tree Reporter opened. No current selection found.' if selection_count.zero?

            "Entity Tree Reporter opened for #{selection_count} selected item(s)."
        end

        def self.na_result(success_flag, message_text)
            {
                success: !!success_flag,
                message: message_text.to_s
            }
        end

# endregion -------------------------------------------------------------------

    end # module Na__SelectedHierarchyTagReporter
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
