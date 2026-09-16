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
        rescue => e
            puts "✗ Error loading Na Array Builder Tools: #{e.message}"
            puts e.backtrace.join("\n")
        end
    else
        puts "✗ Na Array Builder Tools main file not found at: #{main_file}"
    end
    # ---------------------------------------------------------------

    # OBSERVER REGISTRATION | Keep ObjectRegistry in Sync With Active Model
    # ------------------------------------------------------------
    begin
        observers_file = File.join(plugin_folder, 'Na__ArrayBuilder__ModelObservers__.rb')
        if File.exist?(observers_file)
            require observers_file
            Na__ArrayBuilderTools::Na__ArrayBuilder__ModelObservers
                .Na__Observers__InstallOnce
        end
    rescue => na_obs_error
        if defined?(Na__ArrayBuilderTools.na_debug_log)
            Na__ArrayBuilderTools.na_debug_log("Observer install warning: #{na_obs_error.message}")
        end
    end
    # ---------------------------------------------------------------

    # COMMAND SETUP | Create UI Command
    # ------------------------------------------------------------
    cmd = UI::Command.new("Na Array Builder") {
        Na__ArrayBuilderTools.na_init
    }

    cmd.tooltip = "Na Array Builder"
    cmd.status_bar_text = "Create and edit parametric arrays with live previews and a preset gallery"
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
        if defined?(Na__ArrayBuilderTools.na_debug_log)
            Na__ArrayBuilderTools.na_debug_log("Icon resolution warning: #{na_icon_error.message}")
        end
    end
    # ---------------------------------------------------------------

    # MENU INTEGRATION | Add to Plugins Menu
    # ------------------------------------------------------------
    UI.menu("Plugins").add_item(cmd)
    UI.add_context_menu_handler do |na_menu|
        na_selection = Sketchup.active_model.selection.to_a
        if na_selection.length == 1 && Na__ArrayBuilderTools::Na__ArrayBuilder__DataSerializer.Na__Data__HasData?(na_selection.first)
            na_menu.add_separator
            na_menu.add_item('Edit Noble Array...') do
                Na__ArrayBuilderTools::Na__ArrayBuilder__DialogManager.Na__Dialog__OpenEdit
            end
        end
    end
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
