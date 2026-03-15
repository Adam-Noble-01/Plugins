# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilderUtility__Loader.rb
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Loads the TrueVision3D GLB Builder Utility plugin
# CREATED    : 2025
#
# DESCRIPTION:
# - This loader script registers the plugin with SketchUp
# - Loads the main tool from the Na__TrueVision__WhitecardModel__GlbBuilderUtility__Modules__ subfolder
# - Creates menu item in the Extensions > TrueVision3D menu
# - NO BUSINESS LOGIC - only registration and loading
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)
    
    # -----------------------------------------------------------------------------
    # REGION | Path Setup and Configuration
    # -----------------------------------------------------------------------------
    
        plugin_root = File.dirname(__FILE__)                                                                    # <-- Plugins folder
        plugin_folder = File.join(plugin_root, 'Na__TrueVision__GlbBuilderUtility__Modules__')  # <-- Tool subfolder
        main_file = File.join(plugin_folder, 'Na__TrueVision__GlbBuilder__Main__.rb')                           # <-- Main script
    
    # endregion -------------------------------------------------------------------
    
    # -----------------------------------------------------------------------------
    # REGION | Script Loading and Menu Registration
    # -----------------------------------------------------------------------------
    
        if File.exist?(main_file)
            begin
                require main_file
                puts "✓ TrueVision3D GLB Builder Utility loaded successfully (EngineCore orchestrator + geometry/material modules)"
                
                # Delegate menu registration to the shared dynamic reloader utility
                if defined?(TrueVision3D::GlbBuilderUtility) &&
                   TrueVision3D::GlbBuilderUtility.respond_to?(:Na__PublicApi__RegisterMenu)
                    TrueVision3D::GlbBuilderUtility.Na__PublicApi__RegisterMenu
                else
                    puts "⚠ TrueVision3D::GlbBuilderUtility.Na__PublicApi__RegisterMenu not available"
                end
            rescue => e
                puts "✗ Error loading TrueVision3D GLB Builder Utility: #{e.message}"
                puts e.backtrace.first(5).join("\n")
            end
        else
            puts "✗ TrueVision3D GLB Builder Utility main file not found at: #{main_file}"
        end
    
    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Startup Data Preload and Status Report
    # -----------------------------------------------------------------------------

        begin
            if defined?(Na__DataLib__CacheData)
                Na__DataLib__CacheData.Na__Cache__LoadData(:tags)
                Na__DataLib__CacheData.Na__Cache__LoadData(:materials)
                Na__DataLib__CacheData.Na__Cache__PrintStartupReport([:tags, :materials])
            end
        rescue => error
            puts "⚠ [GlbBuilder] Data preload warning: #{error.message}"
        end

    # endregion -------------------------------------------------------------------
    
    file_loaded(__FILE__)
end

# =============================================================================
# END OF LOADER
# =============================================================================
