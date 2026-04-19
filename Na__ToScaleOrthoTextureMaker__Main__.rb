# =============================================================================
# NA TO SCALE ORTHO TEXTURE MAKER - ROOT ENTRY SHIM
# =============================================================================
#
# FILE       : Na__ToScaleOrthoTextureMaker__Main__.rb
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Backwards-compatible entry point that delegates to loader
# CREATED    : 2026
#
# DESCRIPTION:
# - Preserves compatibility for environments still loading this legacy entry file.
# - Delegates all bootstrapping to Na__ToScaleOrthoTextureMaker__Loader__.rb.
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)
    loader_file_path = File.join(File.dirname(__FILE__), 'Na__ToScaleOrthoTextureMaker__Loader__.rb')
    require loader_file_path if File.exist?(loader_file_path)
    file_loaded(__FILE__)
end

# -----------------------------------------------------------------------------
# REGION | Legacy Compatibility Bridge
# -----------------------------------------------------------------------------

module Na_ToScaleOrthoTextureMaker

    # FUNCTION | Legacy Run Command Bridge
    # ------------------------------------------------------------
    def self.Na__ToScaleOrthoTextureMaker__Run
        if defined?(Na__ToScaleOrthoTextureMaker) &&
           Na__ToScaleOrthoTextureMaker.respond_to?(:Na__Ui__ShowMainDialog)
            Na__ToScaleOrthoTextureMaker.Na__Ui__ShowMainDialog
        else
            UI.messagebox('Na__ToScaleOrthoTextureMaker is not fully loaded. Please restart SketchUp.')
        end
    rescue => error
        UI.messagebox("Na__ToScaleOrthoTextureMaker bridge error:\n#{error.message}")
    end
    # ---------------------------------------------------------------

end

# endregion -------------------------------------------------------------------

# =============================================================================
# END OF FILE
# =============================================================================
