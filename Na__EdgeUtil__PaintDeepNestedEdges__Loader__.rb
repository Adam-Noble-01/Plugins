# =============================================================================
# NA EDGE UTIL - PAINT DEEP NESTED EDGES - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__EdgeUtil__PaintDeepNestedEdges__Loader__.rb
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Loads the standalone Paint Deep Nested Edges plugin
# CREATED    : 2026
#
# DESCRIPTION:
# - This loader script registers the standalone Paint Deep Nested Edges plugin.
# - Loads the main tool from the Na__EdgeUtil__PaintDeepNestedEdges__Modules__ folder.
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
        plugin_folder = File.join(plugin_root, 'Na__EdgeUtil__PaintDeepNestedEdges__Modules__')
        main_file     = File.join(plugin_folder, 'Na__EdgeUtil__PaintDeepNestedEdges__Main__.rb')

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Script Loading and Menu Registration
    # -----------------------------------------------------------------------------

        if File.exist?(main_file)
            begin
                require main_file
                puts "[OK] Na Edge Util Paint Deep Nested Edges loaded successfully"

                if defined?(Na__EdgeUtil__PaintDeepNestedEdges) &&
                   Na__EdgeUtil__PaintDeepNestedEdges.respond_to?(:na_register_hotkey_and_menu)
                    Na__EdgeUtil__PaintDeepNestedEdges.na_register_hotkey_and_menu
                else
                    puts "[WARN] Na__EdgeUtil__PaintDeepNestedEdges.na_register_hotkey_and_menu not available"
                end
            rescue => error
                puts "[ERROR] Error loading Na Edge Util Paint Deep Nested Edges: #{error.message}"
                puts error.backtrace.join("\n")
            end
        else
            puts "[ERROR] Na Edge Util Paint Deep Nested Edges main file not found at: #{main_file}"
        end

    # endregion -------------------------------------------------------------------

    file_loaded(__FILE__)
end

# =============================================================================
# END OF LOADER
# =============================================================================
