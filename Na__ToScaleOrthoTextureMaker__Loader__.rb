# =============================================================================
# NA TO SCALE ORTHO TEXTURE MAKER - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__ToScaleOrthoTextureMaker__Loader__.rb
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Loads the modular Ortho Texture Maker plugin
# CREATED    : 2026
#
# DESCRIPTION:
# - Loads the modular main orchestrator from Na__ToScaleOrthoTextureMaker__Modules__.
# - Registers plugin menu command and hotkey through dedicated modules.
# - Contains no domain logic, only plugin bootstrapping.
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)

    # -----------------------------------------------------------------------------
    # REGION | Path Setup
    # -----------------------------------------------------------------------------

        plugin_root_path = File.dirname(__FILE__)
        modules_path     = File.join(plugin_root_path, 'Na__ToScaleOrthoTextureMaker__Modules__')
        main_file_path   = File.join(modules_path, 'Na__ToScaleOrthoTextureMaker__Main__.rb')

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Main Module Loading
    # -----------------------------------------------------------------------------

        if File.exist?(main_file_path)
            begin
                require main_file_path

                if defined?(Na__ToScaleOrthoTextureMaker) &&
                   Na__ToScaleOrthoTextureMaker.respond_to?(:Na__Bootstrap__RegisterPluginUi)
                    Na__ToScaleOrthoTextureMaker.Na__Bootstrap__RegisterPluginUi
                    puts "✓ [Na__Ortho] Na__ToScaleOrthoTextureMaker loaded"
                else
                    puts "⚠ [Na__Ortho] Module loaded, but UI registration method is missing"
                end
            rescue => error
                puts "✗ [Na__Ortho] Error loading plugin: #{error.message}"
                puts error.backtrace.first(8).join("\n")
            end
        else
            puts "✗ [Na__Ortho] Main file not found at: #{main_file_path}"
        end

    # endregion -------------------------------------------------------------------

    file_loaded(__FILE__)
end

# =============================================================================
# END OF FILE
# =============================================================================
