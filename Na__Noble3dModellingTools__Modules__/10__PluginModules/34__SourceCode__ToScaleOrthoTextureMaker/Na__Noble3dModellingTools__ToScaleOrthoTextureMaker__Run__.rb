# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TO SCALE ORTHO TEXTURE MAKER - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ToScaleOrthoTextureMaker__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ToScaleOrthoTextureMaker
# PURPOSE    : Open the To Scale Ortho Texture Maker dialog
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ToScaleOrthoTextureMaker

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Open the Ortho Texture Maker Dialog
        # ------------------------------------------------------------
        def self.Na__ToScaleOrthoTextureMaker__Run
            Na__ToScaleOrthoTextureMaker__DialogManager.Na__ToScaleOrthoTextureMaker__DialogManager__ShowDialog
            na_result(true, 'To Scale Ortho Texture Maker opened.')
        rescue StandardError => error
            na_result(false, "To Scale Ortho Texture Maker failed to open: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helper
# -----------------------------------------------------------------------------

        def self.na_result(success_flag, message_text)
            {
                success: !!success_flag,
                message: message_text.to_s
            }
        end

# endregion -------------------------------------------------------------------

    end # module Na__ToScaleOrthoTextureMaker
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
