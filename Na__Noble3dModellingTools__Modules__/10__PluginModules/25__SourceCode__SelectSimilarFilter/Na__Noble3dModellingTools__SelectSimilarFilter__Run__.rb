# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SELECT SIMILAR FILTER - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SelectSimilarFilter__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SelectSimilarFilter
# PURPOSE    : Public execution entrypoint for the Select Similar Filter tool
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SelectSimilarFilter

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Run Select Similar Filter
        # ------------------------------------------------------------
        # Opens the Select Similar Filter dialog. The dialog itself reads the
        # live SketchUp selection as the reference set each time the user
        # clicks Select Similar, so no upfront selection check is required
        # here beyond having an active model.
        # ------------------------------------------------------------
        def self.Na__SelectSimilarFilter__Run
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            Na__SelectSimilarFilter__DialogManager.Na__SelectSimilarFilter__DialogManager__ShowDialog(model)
            na_result(true, 'Select Similar Filter dialog opened.')
        rescue => error
            na_result(false, "Select Similar Filter failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helpers
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

    end # module Na__SelectSimilarFilter
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
