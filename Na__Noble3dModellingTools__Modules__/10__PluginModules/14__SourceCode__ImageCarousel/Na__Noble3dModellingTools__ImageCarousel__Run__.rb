# =============================================================================
# NA NOBLE3D MODELLING TOOLS - IMAGE CAROUSEL - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ImageCarousel__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ImageCarousel
# PURPOSE    : Public execution entrypoint for the Image Viewer
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ImageCarousel

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        def self.Na__ImageCarousel__Run
            Na__ImageCarousel__DialogManager.Na__ImageCarousel__DialogManager__ShowDialog
            na_result(true, 'Image Viewer opened.')
        rescue => error
            na_result(false, "Image Viewer failed to open: #{error.class}: #{error.message}")
        end

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

    end # module Na__ImageCarousel
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
