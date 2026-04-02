# =============================================================================
# NA ARRAY BUILDER TOOLS - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__ArrayBuilderTools__Loader.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Loads the Na Array Builder Tools plugin with UI button
# CREATED    : 2026
#
# DESCRIPTION:
# - Registers the plugin with SketchUp
# - Loads the main tool from Na__ArrayBuilderTools__Modules__ subfolder
# - Creates menu item in the Plugins menu
# - Creates toolbar button
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)

    # PATH SETUP | Define Paths
    # ------------------------------------------------------------
    plugin_root = File.dirname(__FILE__)
    plugin_folder = File.join(plugin_root, 'Na__ArrayBuilderTools__Modules__')
    main_file = File.join(plugin_folder, 'Na__ArrayBuilder__Main__.rb')
    # ---------------------------------------------------------------

    # SCRIPT LOADING | Load the main plugin file
    # ------------------------------------------------------------
    if File.exist?(main_file)
        begin
            require main_file
            puts "✓ Na Array Builder Tools loaded successfully"
        rescue => e
            puts "✗ Error loading Na Array Builder Tools: #{e.message}"
            puts e.backtrace.join("\n")
        end
    else
        puts "✗ Na Array Builder Tools main file not found at: #{main_file}"
    end
    # ---------------------------------------------------------------

    # COMMAND SETUP | Create UI Command
    # ------------------------------------------------------------
    cmd = UI::Command.new("Na Array Builder") {
        Na__ArrayBuilderTools.na_init
    }

    cmd.tooltip = "Na Array Builder"
    cmd.status_bar_text = "Create parametric array courses (dentil, dog-tooth) along paths"
    cmd.menu_text = "Na Array Builder"

    begin
        if defined?(Na__ArrayBuilderTools::Na__ArrayBuilder__AssetResolver)
            na_icon_path = Na__ArrayBuilderTools::Na__ArrayBuilder__AssetResolver.Na__Assets__MainIconPath
            if na_icon_path && File.exist?(na_icon_path)
                cmd.small_icon = na_icon_path
                cmd.large_icon = na_icon_path
            end
        end
    rescue => na_icon_error
        puts "⚠ [Na__ArrayBuilder] Icon resolution warning: #{na_icon_error.message}"
    end
    # ---------------------------------------------------------------

    # MENU INTEGRATION | Add to Plugins Menu
    # ------------------------------------------------------------
    UI.menu("Plugins").add_item(cmd)
    # ---------------------------------------------------------------

    # TOOLBAR SETUP | Create Dedicated Toolbar
    # ------------------------------------------------------------
    toolbar = UI::Toolbar.new("NA Array Tools")
    toolbar.add_item(cmd)

    toolbar.show if toolbar.get_last_state != TB_HIDDEN
    # ---------------------------------------------------------------

    file_loaded(__FILE__)
end

# =============================================================================
# END OF LOADER
# =============================================================================
