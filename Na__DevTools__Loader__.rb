# =============================================================================
# NA DEV TOOLS - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__DevTools__Loader__.rb
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Loads the standalone Dev Tools plugin
# CREATED    : 2026
#
# DESCRIPTION:
# - This loader script registers the standalone Dev Tools plugin.
# - Loads the main tool from the Na__DevTools__Modules__ folder.
# - Delegates SketchUp menu and shortcut registration to the Hotkey Binder module.
# - Contains no business logic, only plugin bootstrapping.
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)

    # -----------------------------------------------------------------------------
    # REGION | Path Setup and Configuration
    # -----------------------------------------------------------------------------

        plugin_root   = File.dirname(__FILE__)
        plugin_folder = File.join(plugin_root, 'Na__DevTools__Modules__')
        main_file     = File.join(plugin_folder, 'Na__DevTools__Main__.rb')

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Script Loading and Menu Registration
    # -----------------------------------------------------------------------------

        if File.exist?(main_file)
            begin
                require main_file
                puts "✓ [Na__DevTools] Dev Tools loaded successfully"

                if defined?(Na__DevTools) &&
                   Na__DevTools.respond_to?(:na_register_hotkey_and_menu)
                    Na__DevTools.na_register_hotkey_and_menu
                else
                    puts "⚠ [Na__DevTools] na_register_hotkey_and_menu not available"
                end
            rescue => error
                puts "✗ [Na__DevTools] Error loading Dev Tools: #{error.message}"
                puts error.backtrace.first(5).join("\n")
            end
        else
            puts "✗ [Na__DevTools] Main file not found at: #{main_file}"
        end

    # endregion -------------------------------------------------------------------

    file_loaded(__FILE__)
end

# =============================================================================
# END OF LOADER
# =============================================================================
