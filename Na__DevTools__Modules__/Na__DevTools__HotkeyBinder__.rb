# =============================================================================
# NA DEV TOOLS - HOTKEY BINDER
# =============================================================================
#
# FILE       : Na__DevTools__HotkeyBinder__.rb
# NAMESPACE  : Na__DevTools::Na__HotkeyBinder
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Menu and shortcut registration for Dev Tools
# CREATED    : 2026
#
# DESCRIPTION:
# - Registers the standalone Dev Tools command with SketchUp.
# - Exposes a shortcut-discoverable command name in SketchUp preferences.
# - Keeps all UI command registration separate from the tool logic module.
#
# =============================================================================

module Na__DevTools

# -----------------------------------------------------------------------------
# REGION | Menu and Shortcut Registration
# -----------------------------------------------------------------------------

    module Na__HotkeyBinder

    # FUNCTION | Register SketchUp Menu Items and Shortcut Commands
    # ------------------------------------------------------------
    def self.na_register_hotkey_and_menu
        return if @na_command_registered

        extensions_menu = UI.menu('Extensions')
        na_devtools_submenu = extensions_menu.add_submenu('Na__DevTools')

        na_devtools_submenu.add_item(na_build_devtools_dialog_command)
        na_devtools_submenu.add_separator
        na_devtools_submenu.add_item(na_build_load_materials_command)

        @na_command_registered = true
        file_loaded(__FILE__) unless file_loaded?(__FILE__)
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build UI::Command With Shared Configuration
    # ---------------------------------------------------------------
    def self.na_build_command(command_name, tooltip, status_bar_text, menu_text, &command_block)
        command = UI::Command.new(command_name, &command_block)
        command.tooltip         = tooltip
        command.status_bar_text = status_bar_text
        command.menu_text       = menu_text
        command
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Dev Tools Dialog Command
    # ---------------------------------------------------------------
    def self.na_build_devtools_dialog_command
        na_build_command(
            Na__DevTools.na_command_name,
            Na__DevTools.na_command_tooltip,
            Na__DevTools.na_command_status_bar_text,
            Na__DevTools.na_menu_text
        ) do
            Na__DevTools.na_show_dialog
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Load Materials Command
    # ---------------------------------------------------------------
    def self.na_build_load_materials_command
        na_build_command(
            Na__DevTools.na_load_materials_command_name,
            Na__DevTools.na_load_materials_command_tooltip,
            Na__DevTools.na_load_materials_command_status_bar_text,
            Na__DevTools.na_load_materials_menu_text
        ) do
            Na__DevTools.na_run_load_materials
        end
    end
    # ---------------------------------------------------------------

    end

# endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Public API for Loader
    # -----------------------------------------------------------------------------

    # FUNCTION | Delegate Menu Registration to Binder
    # ------------------------------------------------------------
    def self.na_register_hotkey_and_menu
        Na__HotkeyBinder.na_register_hotkey_and_menu
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end
