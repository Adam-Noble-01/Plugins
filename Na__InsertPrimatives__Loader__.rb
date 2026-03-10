# =============================================================================
# NA INSERT PRIMATIVES - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__InsertPrimatives__Loader__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Loads the Na Insert Primatives plugin and registers UI
# CREATED    : 2026
#
# DESCRIPTION:
# - Loads the main tool from the Na__InsertPrimatives__Modules__ subfolder
# - Creates menu item in the Plugins menu
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)

    # PATH SETUP | Define Paths
    # ------------------------------------------------------------
    plugin_root   = File.dirname(__FILE__)                                                      # <-- Plugins folder
    plugin_folder = File.join(plugin_root, 'Na__InsertPrimatives__Modules__')                  # <-- Modules subfolder
    main_file     = File.join(plugin_folder, 'Na__InsertPrimatives__Main__.rb')                # <-- Main script
    # ---------------------------------------------------------------

    # SCRIPT LOADING | Load the main plugin file
    # ------------------------------------------------------------
    if File.exist?(main_file)
        begin
            require main_file
            puts "✓ Na Insert Primatives loaded successfully"
        rescue => e
            puts "✗ Error loading Na Insert Primatives: #{e.message}"
            puts e.backtrace.join("\n")
        end
    else
        puts "✗ Na Insert Primatives main file not found at: #{main_file}"
    end
    # ---------------------------------------------------------------

    # COMMAND SETUP | Create UI Command
    # ------------------------------------------------------------
    cmd = UI::Command.new('NA_InsertPrimitiveCube') {
        Na__InsertPrimatives.Na__InsertPrimatives__InsertCube               # <-- Activate the placement tool
    }
    cmd.tooltip         = "Insert Primitive Cube"                           # <-- Tooltip text
    cmd.status_bar_text = "Activate primitive cube placement tool"          # <-- Status bar text
    cmd.menu_text       = "Na__InsertPrimitives"                      # <-- Menu display text (namespaced)
    # ---------------------------------------------------------------

    # MENU INTEGRATION | Add to Plugins Menu
    # ------------------------------------------------------------
    UI.menu('Plugins').add_item(cmd)                                        # <-- Add command to Plugins menu
    # ---------------------------------------------------------------

    file_loaded(__FILE__)                                                   # <-- Mark file as loaded
end

# =============================================================================
# END OF LOADER
# =============================================================================
