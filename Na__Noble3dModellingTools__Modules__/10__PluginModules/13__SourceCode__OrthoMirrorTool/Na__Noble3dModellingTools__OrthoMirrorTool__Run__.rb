# =============================================================================
# NA NOBLE3D MODELLING TOOLS - ORTHO MIRROR TOOL - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__OrthoMirrorTool__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__OrthoMirrorTool
# PURPOSE    : Public execution entrypoint for activating the Ortho Mirror Tool
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__OrthoMirrorTool

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Run Ortho Mirror Tool
        # ------------------------------------------------------------
        def self.Na__OrthoMirrorTool__Run
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            model.select_tool(OrthoMirrorTool.new)
            na_result(true, 'Ortho Mirror Tool activated.')
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helper
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

    end # module Na__OrthoMirrorTool
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
