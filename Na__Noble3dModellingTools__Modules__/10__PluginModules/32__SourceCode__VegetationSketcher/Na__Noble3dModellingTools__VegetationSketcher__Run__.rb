# =============================================================================
# NA NOBLE3D MODELLING TOOLS - VEGETATION SKETCHER - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__VegetationSketcher__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__VegetationSketcher
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Public execution entrypoint for Vegetation Sketcher
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__VegetationSketcher

# -----------------------------------------------------------------------------
# REGION | Public Entry Points
# -----------------------------------------------------------------------------

        # FUNCTION | Open the Vegetation Sketcher Dialog
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Run
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model.') unless model

            Na__VegetationSketcher__DialogManager.Na__VegetationSketcher__ShowDialog
            na_result(true, 'Vegetation Sketcher opened.')
        rescue => error
            na_result(false, "Vegetation Sketcher failed to open: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

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

    end # module Na__VegetationSketcher
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
