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

# PATH SETUP | Define Paths
# ------------------------------------------------------------
plugin_root   = File.dirname(__FILE__)                                      # <-- Plugins folder
plugin_folder = File.join(plugin_root, 'Na__InsertPrimatives__Modules__')    # <-- Modules subfolder
main_file     = File.join(plugin_folder, 'Na__InsertPrimatives__Main__.rb')  # <-- Main script
# ---------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Loader Helpers
# -----------------------------------------------------------------------------

    # FUNCTION | Forget Loaded Feature Path
    # ------------------------------------------------------------
    def Na__InsertPrimatives__ForgetLoadedFeature(file_path)
        target_path = File.expand_path(file_path).tr('\\', '/').downcase

        $LOADED_FEATURES.delete_if do |loaded_feature|
            File.expand_path(loaded_feature).tr('\\', '/').downcase == target_path
        end
    end
    # ---------------------------------------------------------------


    # FUNCTION | Load Main Primitive Tool Script
    # ------------------------------------------------------------
    def Na__InsertPrimatives__LoadMainScript(main_file)
        if File.exist?(main_file)
            begin
                module_folder = File.dirname(main_file)
                module_files = [
                    'Na__InsertPrimatives__UserInput__VcbFunctions__.rb',
                    'Na__InsertPrimatives__3dPreviewGraphics__.rb',
                    'Na__InsertPrimatives__PlaneMode__.rb',
                    'Na__InsertPrimatives__RightClickPopup__.rb',
                    'Na__InsertPrimatives__KeyboardHandlers__.rb',
                    'Na__InsertPrimatives__Main__.rb'
                ]

                module_files.each do |file_name|
                    Na__InsertPrimatives__ForgetLoadedFeature(File.join(module_folder, file_name))
                end

                require main_file
                puts "✓ Na Insert Primatives loaded successfully"
                true
            rescue => e
                puts "✗ Error loading Na Insert Primatives: #{e.message}"
                puts e.backtrace.join("\n")
                false
            end
        else
            puts "✗ Na Insert Primatives main file not found at: #{main_file}"
            false
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# SCRIPT LOADING | Load the main plugin file
# ------------------------------------------------------------
Na__InsertPrimatives__LoadMainScript(main_file)
# ---------------------------------------------------------------

unless file_loaded?(__FILE__)

    # COMMAND SETUP | Create UI Command
    # ------------------------------------------------------------
    cmd = UI::Command.new('NA_InsertPrimitiveCube') {
        Na__InsertPrimatives__LoadMainScript(main_file)
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
