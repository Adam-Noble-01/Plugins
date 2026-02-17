# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__Loader.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Loads the Na Window Configurator Tool plugin with UI button
# CREATED    : 2026
#
# DESCRIPTION:
# - This loader script registers the plugin with SketchUp
# - Loads the main tool from the ProtoType__3dWindowConfigTool subfolder
# - Creates menu item in the Plugins menu
# - Creates toolbar button with custom icon
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)
    
    # PATH SETUP | Define Paths
    # ------------------------------------------------------------
    plugin_root = File.dirname(__FILE__)                                    	 	    # <-- Plugins folder
    plugin_folder = File.join(plugin_root, 'Na__ArchTools__3dWindowConfigTool__Modules__')  # <-- Tool subfolder
    main_file = File.join(plugin_folder, 'Na__WindowConfiguratorTool__Main__.rb')  	    # <-- Main script
    icon_folder = File.join(plugin_folder, '02__PluginImageAssets')        		    # <-- Icon folder
    icon_path = File.join(icon_folder, 'Na__CutomIcon__.png')              	            # <-- Icon file
    # ---------------------------------------------------------------
    
    # SCRIPT LOADING | Load the main plugin file
    # ------------------------------------------------------------
    if File.exist?(main_file)
        begin
            require main_file
            puts "✓ Na Window Configurator Tool loaded successfully"
        rescue => e
            puts "✗ Error loading Na Window Configurator Tool: #{e.message}"
            puts e.backtrace.join("\n")
        end
    else
        puts "✗ Na Window Configurator Tool main file not found at: #{main_file}"
    end
    # ---------------------------------------------------------------
    
    # COMMAND SETUP | Create UI Command with Icon
    # ------------------------------------------------------------
    cmd = UI::Command.new("Na Window Configurator") {
        Na__WindowConfiguratorTool.na_init                                  # <-- Execute tool function
    }
    
    # Set command properties
    cmd.tooltip = "Na Window Configurator"                                  # <-- Tooltip text
    cmd.status_bar_text = "Create and configure custom windows with interactive placement"  # <-- Status bar text
    cmd.menu_text = "Na Window Configurator"                                # <-- Menu display text
    
    # Set icons
    if File.exist?(icon_path)
        cmd.small_icon = icon_path                                          # <-- 16px icon for toolbar
        cmd.large_icon = icon_path                                          # <-- 32px icon for toolbar (will be scaled)
        puts "✓ Na Window Configurator icon loaded: #{icon_path}"
    else
        puts "⚠ Na Window Configurator icon not found at: #{icon_path}"
        puts "  Tool will work but toolbar button will have default icon"
    end
    # ---------------------------------------------------------------
    
    # MENU INTEGRATION | Add to Plugins Menu
    # ------------------------------------------------------------
    UI.menu("Plugins").add_item(cmd)                                        # <-- Add command to Plugins menu
    # ---------------------------------------------------------------
    
    # TOOLBAR SETUP | Create Dedicated Toolbar
    # ------------------------------------------------------------
    toolbar = UI::Toolbar.new("NA Window Tools")                            # <-- Create or get toolbar
    toolbar.add_item(cmd)                                                   # <-- Add command to toolbar
    
    # Auto-show toolbar (only if not explicitly hidden by user)
    toolbar.show if toolbar.get_last_state != TB_HIDDEN                     # <-- Show toolbar if not hidden
    # ---------------------------------------------------------------
    
    file_loaded(__FILE__)                                                   # <-- Mark file as loaded
end

# =============================================================================
# END OF LOADER
# =============================================================================
