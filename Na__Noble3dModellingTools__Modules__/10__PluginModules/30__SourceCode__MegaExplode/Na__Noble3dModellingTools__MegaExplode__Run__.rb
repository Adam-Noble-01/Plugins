# =============================================================================
# NA NOBLE3D MODELLING TOOLS - MEGA EXPLODE - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__MegaExplode__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__MegaExplode
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Public execution entrypoints for the Mega Explode tool
# CREATED    : 2026
#
# WORKFLOW:
# 1. Select any mix of groups, components, and loose geometry.
# 2. Mega Explode opens a dedicated HtmlDialog with live selection stats
#    and cleanup toggles (all off by default).
# 3. Confirm in the in-dialog modal. One undoable operation then explodes
#    every nested group and component in the selection.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__MegaExplode

# -----------------------------------------------------------------------------
# REGION | Public Entry Points
# -----------------------------------------------------------------------------

        # FUNCTION | Open the Mega Explode Dialog
        # ------------------------------------------------------------
        def self.Na__MegaExplode__Run
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model.') unless model

            Na__MegaExplode__DialogManager.Na__MegaExplode__ShowDialog
            na_result(true, 'Mega Explode opened.')
        rescue => error
            na_result(false, "Mega Explode failed to open: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

        # FUNCTION | Recursively Explode the Current Selection
        # ------------------------------------------------------------
        # @param options [Hash] Cleanup flags from the dialog
        # @return [Hash] { success:, message: }
        # ------------------------------------------------------------
        def self.Na__MegaExplode__ExplodeCurrentSelection(options = {})
            Na__MegaExplode__Exploder.Na__MegaExplode__Exploder__ExplodeSelection(options)
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

    end # module Na__MegaExplode
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
