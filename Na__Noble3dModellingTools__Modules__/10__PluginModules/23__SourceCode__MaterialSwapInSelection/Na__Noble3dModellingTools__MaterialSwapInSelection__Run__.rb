# =============================================================================
# NA NOBLE3D MODELLING TOOLS - MATERIAL SWAP IN SELECTION - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__MaterialSwapInSelection__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__MaterialSwapInSelection
# PURPOSE    : Public execution entrypoint for the Material Swap In Selection tool
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__MaterialSwapInSelection

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Run Material Swap In Selection
        # ------------------------------------------------------------
        # Validates the model and selection, collects materials recursively,
        # and opens the two-step wizard dialog. Returns an early na_result
        # with a clear message if preconditions are not met.
        # ------------------------------------------------------------
        def self.Na__MaterialSwapInSelection__Run
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            selection = model.selection
            return na_result(false, 'Select one or more entities, then run Material Swap In Selection again.') if selection.empty?

            materials_data = Na__MaterialSwapInSelection__MaterialCollector.Na__MaterialSwapInSelection__MaterialCollector__CollectMaterialsRecursive(
                selection,
                {}
            )

            return na_result(false, 'No materials found in the selection. All entities are unpainted.') if materials_data.empty?

            Na__MaterialSwapInSelection__DialogManager.Na__MaterialSwapInSelection__DialogManager__ShowDialog(
                materials_data,
                model
            )

            mat_count = materials_data.size
            na_result(true, "Material Swap In Selection dialog opened. Found #{mat_count} #{mat_count == 1 ? 'material' : 'materials'} in selection.")
        rescue => error
            na_result(false, "Material Swap In Selection failed: #{error.class}: #{error.message}")
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

    end # module Na__MaterialSwapInSelection
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
