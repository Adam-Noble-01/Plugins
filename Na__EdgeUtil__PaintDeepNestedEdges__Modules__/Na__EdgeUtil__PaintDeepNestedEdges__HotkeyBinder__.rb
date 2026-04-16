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

    # FUNCTION | Register SketchUp Menu Items and Shortcut Commands
    # ------------------------------------------------------------
    def self.na_register_hotkey_and_menu
        return if @na_command_registered

        extensions_menu = UI.menu('Extensions')
        na_edge_submenu = extensions_menu.add_submenu('Na__EdgeUtil')

        na_edge_submenu.add_item(na_build_paint_dialog_command)
        na_edge_submenu.add_separator
        na_edge_submenu.add_item(na_build_edge_cleaner_command)
        na_edge_submenu.add_item(na_build_repair_corner_command)
        na_edge_submenu.add_item(na_build_insert_points_command)
        na_edge_submenu.add_item(na_build_chamfer_edge_corners_command)

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

    # HELPER FUNCTION | Build Paint Dialog Command
    # ---------------------------------------------------------------
    def self.na_build_paint_dialog_command
        na_build_command(
            Na__EdgeUtil__PaintDeepNestedEdges.na_command_name,
            Na__EdgeUtil__PaintDeepNestedEdges.na_command_tooltip,
            Na__EdgeUtil__PaintDeepNestedEdges.na_command_status_bar_text,
            Na__EdgeUtil__PaintDeepNestedEdges.na_menu_text
        ) do
            Na__EdgeUtil__PaintDeepNestedEdges.na_show_dialog
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Edge Cleaner Command
    # ---------------------------------------------------------------
    def self.na_build_edge_cleaner_command
        na_build_command(
            Na__EdgeUtil__PaintDeepNestedEdges.na_edge_cleaner_command_name,
            Na__EdgeUtil__PaintDeepNestedEdges.na_edge_cleaner_command_tooltip,
            Na__EdgeUtil__PaintDeepNestedEdges.na_edge_cleaner_command_status_bar_text,
            Na__EdgeUtil__PaintDeepNestedEdges.na_edge_cleaner_menu_text
        ) do
            Na__EdgeUtil__PaintDeepNestedEdges.na_run_edge_cleaner
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Repair Edge Corners Command
    # ---------------------------------------------------------------
    def self.na_build_repair_corner_command
        na_build_command(
            Na__EdgeUtil__PaintDeepNestedEdges.na_repair_corner_command_name,
            Na__EdgeUtil__PaintDeepNestedEdges.na_repair_corner_command_tooltip,
            Na__EdgeUtil__PaintDeepNestedEdges.na_repair_corner_command_status_bar_text,
            Na__EdgeUtil__PaintDeepNestedEdges.na_repair_corner_menu_text
        ) do
            Na__EdgeUtil__PaintDeepNestedEdges.na_run_repair_edge_corners
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Insert Points Along Paths Command
    # ---------------------------------------------------------------
    def self.na_build_insert_points_command
        na_build_command(
            Na__EdgeUtil__PaintDeepNestedEdges.na_insert_points_command_name,
            Na__EdgeUtil__PaintDeepNestedEdges.na_insert_points_command_tooltip,
            Na__EdgeUtil__PaintDeepNestedEdges.na_insert_points_command_status_bar_text,
            Na__EdgeUtil__PaintDeepNestedEdges.na_insert_points_menu_text
        ) do
            Na__EdgeUtil__PaintDeepNestedEdges.na_run_insert_points_along_paths
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Chamfer Edge Corners Command
    # ---------------------------------------------------------------
    def self.na_build_chamfer_edge_corners_command
        na_build_command(
            Na__EdgeUtil__PaintDeepNestedEdges.na_chamfer_edge_corners_command_name,
            Na__EdgeUtil__PaintDeepNestedEdges.na_chamfer_edge_corners_command_tooltip,
            Na__EdgeUtil__PaintDeepNestedEdges.na_chamfer_edge_corners_command_status_bar_text,
            Na__EdgeUtil__PaintDeepNestedEdges.na_chamfer_edge_corners_menu_text
        ) do
            Na__EdgeUtil__PaintDeepNestedEdges.na_run_chamfer_edge_corners
        end
    end
    # ---------------------------------------------------------------

    end # module Na__HotkeyBinder

# endregion -------------------------------------------------------------------

end # module Na__EdgeUtil__PaintDeepNestedEdges

# =============================================================================
# END OF FILE
# =============================================================================
