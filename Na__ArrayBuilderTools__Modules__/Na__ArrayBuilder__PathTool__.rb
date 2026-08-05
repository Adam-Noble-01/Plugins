# =============================================================================
# NA ARRAY BUILDER TOOLS - PATH TOOL
# =============================================================================
#
# FILE       : Na__ArrayBuilder__PathTool__.rb
# NAMESPACE  : Na__ArrayBuilderTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Interactive 3D tool for defining array paths with preview
# CREATED    : 2026
# VERSION    : 0.1.0
#
# DESCRIPTION:
# - Crosshair-based tool for defining multi-segment paths
# - Click to add waypoints, Enter / right-click / double-click to finish
# - Live wireframe preview of array units along the path
# - Displays count, spacing, and total length info overlay
# - Unit dimensions / distribution maths / preview rendering live in
#   Na__ArrayBuilder__PreviewRenderMixin (shared with the selection
#   review tool) which delegates to Na__ArrayBuilder__Distribution.
# - Includes Na__ArrayBuilder__AxisLockMixin: arrow keys lock the next
#   segment to the X / Y / Z axis or parallel to the previous segment
#   via SketchUp's native View#lock_inference so projection AND visual
#   feedback are handled by SketchUp itself (no custom drawing).
# - Delegates geometry creation to GeometryBuilder on commit
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__ArrayBuilder__ObjectRegistry__'
require_relative 'Na__ArrayBuilder__Distribution__'
require_relative 'Na__ArrayBuilder__PreviewRenderMixin__'
require_relative 'Na__ArrayBuilder__AxisLockMixin__'

module Na__ArrayBuilderTools

# =============================================================================
# REGION | Path Tool Class
# =============================================================================

    class Na__ArrayBuilder__PathTool

        include Na__ArrayBuilder__AxisLockMixin
        include Na__ArrayBuilder__PreviewRenderMixin

        # CONSTANTS
        # ------------------------------------------------------------
        NA_CROSSHAIR_SIZE    = 200.mm
        NA_GRID_SIZE         = 1.mm
        NA_INCH_TO_MM        = 25.4
        NA_PATH_COLOR        = Sketchup::Color.new(255, 165, 0, 200)
        NA_WAYPOINT_COLOR    = Sketchup::Color.new(255, 220, 0)

        # Backspace has no VK_* constant in the SketchUp Ruby API; key
        # code 8 is the cross-platform value the Tool callback receives.
        NA_VK_BACKSPACE       = 8

        # FUNCTION | Initialize Path Tool
        # ------------------------------------------------------------
        # @param config [Hash] Array configuration from dialog
        # @param dialog_manager [Module] Reference for status updates
        def initialize(config, dialog_manager)
            @config = config
            @dialog_manager = dialog_manager
            @ip = Sketchup::InputPoint.new
            @ip_prev = Sketchup::InputPoint.new
            @cursor_pos = nil
            @waypoints = []
            @state = :picking_start

            na_init_unit_config_state(config)
            na_reset_preview_cache
        end
        # ---------------------------------------------------------------

        # FUNCTION | Reset Per-Frame Preview Cache
        # ------------------------------------------------------------
        # Cache populated in onMouseMove and consumed by both draw and
        # na_update_status_text, so per-mouse-move preview positions
        # are computed once instead of three times.
        def na_reset_preview_cache
            @na_cache_path        = nil
            @na_cache_positions   = nil
            @na_cache_total_mm    = nil
            @na_cache_actual_mm   = nil
            @na_last_status_text  = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Tool Activated
        # ------------------------------------------------------------
        def activate
            @state = :picking_start
            @waypoints = []
            @cursor_pos = nil
            na_reset_preview_cache
            Na__ArrayBuilder__DialogManager.na_reset_preview_info_memo if defined?(Na__ArrayBuilder__DialogManager)
            Na__AxisLock__InitState()
            na_update_status_text
            Sketchup.active_model.active_view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Tool Deactivated
        # ------------------------------------------------------------
        def deactivate(view)
            Na__AxisLock__ClearOnDeactivate(view)
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Mouse Move Handler
        # ------------------------------------------------------------
        # When an arrow-key axis lock is active, the 3-arg pick form is
        # used so view.lock_inference is the dominant inference. The
        # 4-arg form is only used when picking along the path with no
        # lock active - it gives "additional inferences" relative to
        # the previous InputPoint, which can shadow view.lock_inference
        # and was the reason arrow-key locking appeared to do nothing.
        def onMouseMove(flags, x, y, view)
            if @state == :picking_path && !@waypoints.empty? && !Na__AxisLock__Active?
                @ip.pick(view, x, y, @ip_prev)
            else
                @ip.pick(view, x, y)
            end
            return unless @ip.valid?

            @cursor_pos = na_round_to_grid(@ip.position)
            na_rebuild_preview_cache
            na_update_status_text
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rebuild the Preview Cache (Single Compute Per Frame)
        # ------------------------------------------------------------
        # Called from onMouseMove and after each waypoint commit so the
        # status-bar formatter and the draw method can both read from
        # the cached values rather than each recomputing the per-segment
        # positions and lengths.
        def na_rebuild_preview_cache
            unless @cursor_pos && @state == :picking_path && !@waypoints.empty?
                na_reset_preview_cache
                return
            end

            @na_cache_path      = @waypoints + [@cursor_pos]
            @na_cache_positions = na_calculate_preview_positions(@na_cache_path)
            @na_cache_total_mm  = na_path_length_mm(@na_cache_path)
            @na_cache_actual_mm = na_calculate_actual_spacing_mm(@na_cache_path)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Left Mouse Button Down Handler
        # ------------------------------------------------------------
        # Profile-Builder-style: every click adds a waypoint. The first
        # click sets the start; subsequent clicks append. Finishing the
        # path is a separate gesture (Enter / right-click / double-click).
        def onLButtonDown(_flags, x, y, view)
            @ip.pick(view, x, y)
            return unless @ip.valid?

            clicked = na_round_to_grid(@ip.position)

            if @state == :picking_start
                @waypoints = [clicked]
                @state = :picking_path
            else
                @waypoints << clicked
            end

            @ip_prev.copy!(@ip)
            Na__AxisLock__ReanchorAfterCommit(view)
            na_rebuild_preview_cache
            na_update_status_text
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Return / Enter Key Finishes the Path
        # ------------------------------------------------------------
        def onReturn(view)
            na_finish_path_if_ready(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Right-Click Finishes the Path
        # ------------------------------------------------------------
        def onRButtonDown(_flags, _x, _y, view)
            na_finish_path_if_ready(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Double-Click Finishes the Path
        # ------------------------------------------------------------
        def onLButtonDoubleClick(_flags, _x, _y, view)
            na_finish_path_if_ready(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Suppress Default Right-Click Context Menu
        # ------------------------------------------------------------
        # Implementing getMenu (even with no items) replaces SketchUp's
        # default context menu so right-click can act as the "finish"
        # gesture without an unwanted menu popping up afterwards.
        def getMenu(_menu, *_args)
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Cancel Handler (ESC)
        # ------------------------------------------------------------
        def onCancel(reason, view)
            Na__AxisLock__ClearOnDeactivate(view)
            @dialog_manager.na_send_status_to_dialog("info", "Array placement cancelled")
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Key Down Handler (Backspace Undo + Axis Lock Delegate)
        # ------------------------------------------------------------
        # Backspace and Mac Forward Delete pop the most recent waypoint.
        # All other keys (specifically the arrow-key axis lock) fall
        # through to Na__ArrayBuilder__AxisLockMixin#onKeyDown via super.
        def onKeyDown(key, repeat, flags, view)
            if key == NA_VK_BACKSPACE || key == VK_DELETE
                na_undo_last_waypoint(view)
                return false
            end
            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw Handler
        # ------------------------------------------------------------
        def draw(view)
            return unless @cursor_pos

            na_draw_crosshair(view, @cursor_pos)

            if @state == :picking_path && !@waypoints.empty?
                na_draw_path(view)
                na_draw_waypoint_markers(view)

                positions    = @na_cache_positions || []
                preview_path = @na_cache_path      || (@waypoints + [@cursor_pos])

                na_draw_preview_units(view, positions)
                na_draw_array_info_text(view, positions, preview_path, @cursor_pos)

                @dialog_manager.na_send_preview_info(
                    positions.length,
                    @na_cache_total_mm  || 0.0,
                    @na_cache_actual_mm
                )
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Extents
        # ------------------------------------------------------------
        def getExtents
            bb = Geom::BoundingBox.new
            @waypoints.each { |wp| bb.add(wp) }
            bb.add(@cursor_pos) if @cursor_pos
            bb
        end
        # ---------------------------------------------------------------

        private

        # =============================================================
        # REGION | Crosshair Drawing
        # =============================================================

        # FUNCTION | Draw 3-axis Crosshair
        # ------------------------------------------------------------
        def na_draw_crosshair(view, point)
            size = NA_CROSSHAIR_SIZE * 0.5
            view.line_width = 2

            view.drawing_color = Sketchup::Color.new(255, 0, 0)
            view.draw_line(
                point.offset(X_AXIS, -size),
                point.offset(X_AXIS, size)
            )

            view.drawing_color = Sketchup::Color.new(0, 255, 0)
            view.draw_line(
                point.offset(Y_AXIS, -size),
                point.offset(Y_AXIS, size)
            )

            view.drawing_color = Sketchup::Color.new(0, 0, 255)
            view.draw_line(
                point.offset(Z_AXIS, -size),
                point.offset(Z_AXIS, size)
            )
        end
        # ---------------------------------------------------------------

        # endregion =====================================================

        # =============================================================
        # REGION | Path Drawing
        # =============================================================

        # FUNCTION | Draw Path Polyline
        # ------------------------------------------------------------
        def na_draw_path(view)
            path_pts = @waypoints + [@cursor_pos]
            return if path_pts.length < 2

            view.line_width = 3
            view.drawing_color = NA_PATH_COLOR
            view.draw_polyline(path_pts)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw Waypoint Markers
        # ------------------------------------------------------------
        def na_draw_waypoint_markers(view)
            @waypoints.each do |wp|
                marker_size = NA_CROSSHAIR_SIZE * 0.15
                view.line_width = 3
                view.drawing_color = NA_WAYPOINT_COLOR

                view.draw_line(
                    wp.offset(X_AXIS, -marker_size),
                    wp.offset(X_AXIS, marker_size)
                )
                view.draw_line(
                    wp.offset(Y_AXIS, -marker_size),
                    wp.offset(Y_AXIS, marker_size)
                )
                view.draw_line(
                    wp.offset(Z_AXIS, -marker_size),
                    wp.offset(Z_AXIS, marker_size)
                )
            end
        end
        # ---------------------------------------------------------------

        # endregion =====================================================

        # =============================================================
        # REGION | Commit
        # =============================================================

        # FUNCTION | Finish Path Gesture (Enter / Right-Click / Double-Click)
        # ------------------------------------------------------------
        # Guards na_commit_array so a stray Enter cannot kick the user
        # out of the tool when the path has fewer than two committed
        # waypoints. Stays active and shows a warning instead.
        def na_finish_path_if_ready(view)
            if @waypoints.length < 2
                @dialog_manager.na_send_status_to_dialog(
                    "warning",
                    "Add at least one more waypoint before finishing"
                )
                return
            end

            na_commit_array(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Undo the Most Recent Waypoint (Backspace)
        # ------------------------------------------------------------
        # Pops the last waypoint, transitions back to :picking_start
        # when the path collapses to empty, and re-anchors the axis
        # lock to the new last-waypoint so the dashed inference line
        # follows the rollback.
        def na_undo_last_waypoint(view)
            return if @waypoints.empty?

            @waypoints.pop

            if @waypoints.empty?
                @state    = :picking_start
                @ip_prev  = Sketchup::InputPoint.new
            else
                @ip_prev  = Sketchup::InputPoint.new(@waypoints.last)
            end

            Na__AxisLock__ReanchorAfterCommit(view)
            na_rebuild_preview_cache
            na_update_status_text
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Commit Array Geometry
        # ------------------------------------------------------------
        def na_commit_array(view)
            positions = na_calculate_preview_positions(@waypoints)

            if positions.empty?
                @dialog_manager.na_send_status_to_dialog("warning", "Path too short for any units")
                Sketchup.active_model.select_tool(nil)
                return
            end

            result = Na__ArrayBuilder__GeometryBuilder.na_create_array(
                @waypoints, @config, positions
            )

            if result
                count = positions.length
                @dialog_manager.na_send_status_to_dialog("success", "Created #{count} #{@array_type} units")
                @dialog_manager.na_send_array_complete(count)
            else
                @dialog_manager.na_send_status_to_dialog("error", "Failed to create array geometry")
            end

            Sketchup.active_model.select_tool(nil)
        end
        # ---------------------------------------------------------------

        # endregion =====================================================

        # =============================================================
        # REGION | Helpers
        # =============================================================

        # FUNCTION | Update Status Bar Text
        # ------------------------------------------------------------
        def na_update_status_text
            type_label =
                case @array_type
                when 'dogtooth' then 'Dog-Tooth'
                when 'object'   then 'Object'
                else                 'Dentil'
                end

            lock_suffix = Na__AxisLock__BuildStatusFragment()

            new_text =
                if @state == :picking_start
                    if @cursor_pos
                        pos_str = na_point_to_mm_string(@cursor_pos)
                        "Array Builder (#{type_label}): Click to set start point at #{pos_str} | ESC to cancel#{lock_suffix}"
                    else
                        "Array Builder (#{type_label}): Click to set start point | ESC to cancel#{lock_suffix}"
                    end
                elsif @state == :picking_path
                    if @cursor_pos && @na_cache_positions
                        count    = @na_cache_positions.length
                        total_mm = (@na_cache_total_mm || 0.0).round
                        "Array Builder: Click to add waypoint | Enter / Right-click / Double-click to finish | Backspace to undo | ESC to cancel | #{count} units | #{total_mm}mm#{lock_suffix}"
                    else
                        "Array Builder: Click to add waypoint | Enter / Right-click / Double-click to finish | Backspace to undo | ESC to cancel#{lock_suffix}"
                    end
                end

            return if new_text.nil?
            return if new_text == @na_last_status_text

            Sketchup.status_text = new_text
            @na_last_status_text = new_text
        end
        # ---------------------------------------------------------------

        # FUNCTION | Round Point to Grid
        # ------------------------------------------------------------
        def na_round_to_grid(point)
            Geom::Point3d.new(
                (point.x / NA_GRID_SIZE).round * NA_GRID_SIZE,
                (point.y / NA_GRID_SIZE).round * NA_GRID_SIZE,
                (point.z / NA_GRID_SIZE).round * NA_GRID_SIZE
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Format Point as Millimeter String
        # ------------------------------------------------------------
        def na_point_to_mm_string(point)
            x_mm = (point.x * NA_INCH_TO_MM).round
            y_mm = (point.y * NA_INCH_TO_MM).round
            z_mm = (point.z * NA_INCH_TO_MM).round
            "X:#{x_mm}mm Y:#{y_mm}mm Z:#{z_mm}mm"
        end
        # ---------------------------------------------------------------

        # endregion =====================================================

    end

# endregion ===================================================================

end # module Na__ArrayBuilderTools

# =============================================================================
# END OF FILE
# =============================================================================
