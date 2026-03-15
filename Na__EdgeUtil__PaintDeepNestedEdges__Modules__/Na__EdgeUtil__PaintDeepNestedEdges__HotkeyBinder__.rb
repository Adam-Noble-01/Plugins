# =============================================================================
# NA EDGE UTIL - PAINT DEEP NESTED EDGES - HOTKEY BINDER
# =============================================================================
#
# FILE       : Na__EdgeUtil__PaintDeepNestedEdges__HotkeyBinder__.rb
# NAMESPACE  : Na__EdgeUtil__PaintDeepNestedEdges::Na__HotkeyBinder
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Menu and shortcut registration for Paint Deep Nested Edges
# CREATED    : 2026
#
# DESCRIPTION:
# - Registers the standalone Paint Deep Nested Edges command with SketchUp.
# - Exposes a shortcut-discoverable command name in SketchUp preferences.
# - Keeps all UI command registration separate from the tool logic module.
#
# =============================================================================

module Na__EdgeUtil__PaintDeepNestedEdges

# -----------------------------------------------------------------------------
# REGION | Menu and Shortcut Registration
# -----------------------------------------------------------------------------

    module Na__HotkeyBinder

    # FUNCTION | Register SketchUp Menu Item and Shortcut Command
    # ------------------------------------------------------------
    def self.na_register_hotkey_and_menu
        return if @na_command_registered

        cmd = UI::Command.new(Na__EdgeUtil__PaintDeepNestedEdges.na_command_name) do
            Na__EdgeUtil__PaintDeepNestedEdges.na_show_dialog
        end

        cmd.tooltip         = Na__EdgeUtil__PaintDeepNestedEdges.na_command_tooltip
        cmd.status_bar_text = Na__EdgeUtil__PaintDeepNestedEdges.na_command_status_bar_text
        cmd.menu_text       = Na__EdgeUtil__PaintDeepNestedEdges.na_menu_text

        extensions_menu    = UI.menu("Extensions")
        na_edge_submenu    = extensions_menu.add_submenu("Na__PaintEdges")
        na_edge_submenu.add_item(cmd)

        @na_command_registered = true
        file_loaded(__FILE__) unless file_loaded?(__FILE__)
    end
    # ---------------------------------------------------------------

    end # module Na__HotkeyBinder

# endregion -------------------------------------------------------------------

end # module Na__EdgeUtil__PaintDeepNestedEdges

# =============================================================================
# END OF FILE
# =============================================================================
