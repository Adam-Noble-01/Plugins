# =============================================================================
# NA ARRAY BUILDER TOOLS - SELECTION ARRAY TOOL
# =============================================================================
#
# FILE       : Na__ArrayBuilder__SelectionArrayTool__.rb
# NAMESPACE  : Na__ArrayBuilderTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Review-and-confirm tool for the 'Use Selection' path
#              source. The path is already fixed (built from the user's
#              selected edges / curve by Na__ArrayBuilder__PathFromSelection),
#              so this tool only previews the array along it, offers a
#              live Reverse toggle (dialog button or R key), and commits
#              on Enter / click.
# CREATED    : 2026
# VERSION    : 0.1.0
#
# DESCRIPTION:
# - Shares the preview engine with the draw-path tool via
#   Na__ArrayBuilder__PreviewRenderMixin so what is previewed here is
#   exactly what GeometryBuilder places.
# - Direction arrow at the path start shows which way the array runs -
#   the thing the Reverse toggle flips.
# - Controls: Enter / Left-click / Right-click / Double-click = build,
#   R = reverse direction, ESC = cancel. The dialog's Reverse button
#   drives the same na_set_reverse entry point through DialogManager.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__ArrayBuilder__Distribution__'
require_relative 'Na__ArrayBuilder__PreviewRenderMixin__'
require_relative 'Na__ArrayBuilder__PathFromSelection__'
require_relative 'Na__ArrayBuilder__GeometryBuilder__'

module Na__ArrayBuilderTools

# =============================================================================
# REGION | Selection Array Tool Class
# =============================================================================

    class Na__ArrayBuilder__SelectionArrayTool

        include Na__ArrayBuilder__PreviewRenderMixin

        # CONSTANTS
        # ------------------------------------------------------------
        NA_PATH_COLOR      = Sketchup::Color.new(255, 165, 0, 220)
        NA_ARROW_COLOR     = Sketchup::Color.new(255, 220, 0)
        NA_ARROW_LENGTH    = 400.mm
        NA_ARROW_WING      = 120.mm
        NA_VK_REVERSE      = 82   # 'R' key (Windows virtual key code)

        # FUNCTION | Initialize Selection Array Tool
        # ------------------------------------------------------------
        # @param config [Hash] Array configuration from dialog
        # @param dialog_manager [Module] Reference for status updates
        # @param base_points [Array<Geom::Point3d>] Ordered path points
        #        in canonical (un-reversed) direction
        # @param closed_loop [Boolean] Whether the path closes on itself
        def initialize(config, dialog_manager, base_points, closed_loop)
            @config          = config
            @dialog_manager  = dialog_manager
            @na_base_points  = Array(base_points)
            @na_closed_loop  = closed_loop == true
            @na_reverse      = config['reverse_path'] == true

            @na_path_points  = []
            @na_positions    = []
            @na_total_mm     = 0.0
            @na_actual_mm    = nil
            @na_last_status_text = nil

            na_init_unit_config_state(config)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Tool Activated
        # ------------------------------------------------------------
        def activate
            @dialog_manager.na_register_selection_tool(self)
            @dialog_manager.na_reset_preview_info_memo
            na_rebuild_selection_preview
            na_update_status_text
            Sketchup.active_model.active_view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Tool Deactivated
        # ------------------------------------------------------------
        def deactivate(view)
            @dialog_manager.na_register_selection_tool(nil)
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Set Reverse State (Dialog Toggle Entry Point)
        # ------------------------------------------------------------
        # Called by DialogManager when the dialog's Reverse button flips
        # while this tool is active. Also used by the R key handler.
        def na_set_reverse(state)
            @na_reverse = state == true
            na_rebuild_selection_preview
            na_update_status_text
            Sketchup.active_model.active_view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Current Reverse State
        # ------------------------------------------------------------
        def na_reverse_state
            @na_reverse
        end
        # ---------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Input Handlers (Commit / Reverse / Cancel)
# -----------------------------------------------------------------------------

        # FUNCTION | Left-Click Commits the Array
        # ------------------------------------------------------------
        def onLButtonDown(_flags, _x, _y, view)
            na_commit_array(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Enter / Return Commits the Array
        # ------------------------------------------------------------
        def onReturn(view)
            na_commit_array(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Right-Click Commits the Array
        # ------------------------------------------------------------
        def onRButtonDown(_flags, _x, _y, view)
            na_commit_array(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Suppress Default Right-Click Context Menu
        # ------------------------------------------------------------
        def getMenu(_menu, *_args)
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Key Down Handler (R Toggles Reverse)
        # ------------------------------------------------------------
        # Mirrors the new state back to the dialog so the Reverse button
        # stays in sync with the viewport.
        def onKeyDown(key, repeat, _flags, _view)
            return false unless key == NA_VK_REVERSE && repeat == 1

            na_set_reverse(!@na_reverse)
            @dialog_manager.na_send_reverse_state(@na_reverse)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Cancel Handler (ESC)
        # ------------------------------------------------------------
        def onCancel(_reason, _view)
            @dialog_manager.na_send_status_to_dialog("info", "Selection array cancelled")
            Sketchup.active_model.select_tool(nil)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Drawing
# -----------------------------------------------------------------------------

        # FUNCTION | Draw Handler
        # ------------------------------------------------------------
        def draw(view)
            return if @na_path_points.length < 2

            view.line_width = 3
            view.drawing_color = NA_PATH_COLOR
            view.draw_polyline(@na_path_points)

            na_draw_direction_arrow(view, @na_path_points)
            na_draw_preview_units(view, @na_positions)
            na_draw_array_info_text(view, @na_positions, @na_path_points, @na_path_points.first)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Extents
        # ------------------------------------------------------------
        def getExtents
            bb = Geom::BoundingBox.new
            @na_path_points.each { |pt| bb.add(pt) }
            bb
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw Direction Arrow at the Path Start
        # ------------------------------------------------------------
        # Shows which way the array runs so the Reverse toggle has an
        # obvious visual anchor.
        def na_draw_direction_arrow(view, points)
            p0  = points[0]
            p1  = points[1]
            dir = p1 - p0
            return if dir.length < 0.001

            dir.length = 1.0
            shaft_len = NA_ARROW_LENGTH
            seg_len   = p0.distance(p1)
            shaft_len = seg_len if seg_len < shaft_len

            tip = p0.offset(dir, shaft_len)

            side = dir.cross(Z_AXIS)
            side = dir.cross(Y_AXIS) if side.length < 0.001
            side.length = 1.0

            back = tip.offset(dir, -NA_ARROW_WING)

            view.line_width    = 4
            view.drawing_color = NA_ARROW_COLOR
            view.draw_line(p0, tip)
            view.draw_line(tip, back.offset(side, NA_ARROW_WING * 0.6))
            view.draw_line(tip, back.offset(side, -NA_ARROW_WING * 0.6))
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        private

# -----------------------------------------------------------------------------
# REGION | Preview Rebuild / Status
# -----------------------------------------------------------------------------

        # FUNCTION | Resolve the Effective (Possibly Reversed) Path Points
        # ------------------------------------------------------------
        def na_effective_points
            return @na_base_points unless @na_reverse

            Na__ArrayBuilder__PathFromSelection.Na__PathFromSelection__ReversePoints(
                @na_base_points, @na_closed_loop
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rebuild Positions / Lengths for the Current Direction
        # ------------------------------------------------------------
        def na_rebuild_selection_preview
            @na_path_points = na_effective_points
            @na_positions   = na_calculate_preview_positions(@na_path_points)
            @na_total_mm    = na_path_length_mm(@na_path_points)
            @na_actual_mm   = na_calculate_actual_spacing_mm(@na_path_points)

            @dialog_manager.na_send_preview_info(
                @na_positions.length, @na_total_mm, @na_actual_mm
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Update Status Bar Text
        # ------------------------------------------------------------
        def na_update_status_text
            count    = @na_positions.length
            total_mm = @na_total_mm.round
            loop_tag = @na_closed_loop ? ' | Closed loop' : ''
            rev_tag  = @na_reverse ? ' | Reversed' : ''

            new_text = "Array Builder (Selection): #{count} units | #{total_mm}mm#{loop_tag}#{rev_tag} | Enter / Click to build | R to reverse | ESC to cancel"
            return if new_text == @na_last_status_text

            Sketchup.status_text = new_text
            @na_last_status_text = new_text
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Commit
# -----------------------------------------------------------------------------

        # FUNCTION | Commit Array Geometry Along the Selected Path
        # ------------------------------------------------------------
        def na_commit_array(_view)
            if @na_positions.empty?
                @dialog_manager.na_send_status_to_dialog("warning", "Selected path too short for any units")
                Sketchup.active_model.select_tool(nil)
                return
            end

            result = Na__ArrayBuilder__GeometryBuilder.na_create_array(
                @na_path_points, @config, @na_positions
            )

            if result
                count = @na_positions.length
                @dialog_manager.na_send_status_to_dialog("success", "Created #{count} #{@array_type} units along selection")
                @dialog_manager.na_send_array_complete(count)
            else
                @dialog_manager.na_send_status_to_dialog("error", "Failed to create array geometry")
            end

            Sketchup.active_model.select_tool(nil)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end

# endregion ===================================================================

end # module Na__ArrayBuilderTools

# =============================================================================
# END OF FILE
# =============================================================================
