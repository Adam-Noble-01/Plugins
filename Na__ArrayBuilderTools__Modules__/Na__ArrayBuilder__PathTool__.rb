# =============================================================================
# NA ARRAY BUILDER TOOLS - PATH TOOL
# =============================================================================
#
# FILE       : Na__ArrayBuilder__PathTool__.rb
# NAMESPACE  : Na__ArrayBuilderTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Interactive 3D tool for defining array paths with preview
# CREATED    : 2026
# VERSION    : 0.0.4
#
# DESCRIPTION:
# - Crosshair-based tool for defining multi-segment paths
# - Click to set start point, Ctrl+Click to add waypoints, Click to finish
# - Live wireframe preview of array units along the path
# - Displays count, spacing, and total length info overlay
# - Supports the 'object' array type by reading the picked definition's
#   bounding-box dimensions from Na__ArrayBuilder__ObjectRegistry, so the
#   existing spacing / normalisation maths is fully reused.
# - Includes Na__ArrayBuilder__AxisLockMixin: arrow keys lock the next
#   segment to the X / Y / Z axis or parallel to the previous segment
#   via SketchUp's native View#lock_inference so projection AND visual
#   feedback are handled by SketchUp itself (no custom drawing).
# - Delegates geometry creation to GeometryBuilder on commit
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__ArrayBuilder__ObjectRegistry__'
require_relative 'Na__ArrayBuilder__AxisLockMixin__'

module Na__ArrayBuilderTools

# =============================================================================
# REGION | Path Tool Class
# =============================================================================

    class Na__ArrayBuilder__PathTool

        include Na__ArrayBuilder__AxisLockMixin

        # CONSTANTS
        # ------------------------------------------------------------
        NA_CROSSHAIR_SIZE    = 200.mm
        NA_GRID_SIZE         = 1.mm
        NA_INCH_TO_MM        = 25.4
        NA_PATH_COLOR        = Sketchup::Color.new(255, 165, 0, 200)
        NA_PREVIEW_COLOR     = Sketchup::Color.new(0, 200, 180, 160)
        NA_PREVIEW_FILL      = Sketchup::Color.new(0, 200, 180, 40)
        NA_WAYPOINT_COLOR    = Sketchup::Color.new(255, 220, 0)
        NA_TEXT_COLOR         = Sketchup::Color.new(255, 255, 255)
        NA_TEXT_BG_COLOR      = Sketchup::Color.new(40, 40, 40, 200)

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

            @array_type  = config['type'] || 'dentil'
            @anchor_mode = config['anchor_mode'] || 'local_axis'
            @spacing     = (config['spacing_mm'] || 115).to_f.mm
            @normalise   = config['normalise_distance'] == true

            na_resolve_unit_dimensions(config)
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

        # FUNCTION | Resolve Unit Dimensions for Current Array Type
        # ------------------------------------------------------------
        # In 'object' mode the per-step unit width and the preview-box
        # dimensions are derived from the picked definition's bounding
        # box. For dentil / dogtooth they come straight from the dialog
        # config. Falls back to the dialog-provided values if no object
        # has been picked yet (validation in DialogManager prevents this
        # in practice).
        def na_resolve_unit_dimensions(config)
            if @array_type == 'object'
                bounds = Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetBoundsMm
                if bounds
                    @unit_width  = bounds[:unit_width_mm].to_f.mm
                    @unit_depth  = bounds[:unit_depth_mm].to_f.mm
                    @unit_height = bounds[:unit_height_mm].to_f.mm
                    return
                end
            end

            @unit_width  = (config['unit_width_mm']  || 110).to_f.mm
            @unit_depth  = (config['unit_depth_mm']   || 30).to_f.mm
            @unit_height = (config['unit_height_mm']  || 75).to_f.mm
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
                na_draw_info_text(view, positions, preview_path)

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
        # REGION | Preview Calculation (Router)
        # =============================================================

        # FUNCTION | Calculate Preview Unit Positions Along Path
        # ------------------------------------------------------------
        # Delegates to fixed or normalised algorithm based on config.
        def na_calculate_preview_positions(path_points)
            if @normalise
                na_calculate_normalised_positions(path_points)
            else
                na_calculate_fixed_positions(path_points)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Calculate Total Path Length in mm
        # ------------------------------------------------------------
        def na_path_length_mm(path_points)
            total = 0.0
            (0...path_points.length - 1).each do |i|
                total += path_points[i].distance(path_points[i + 1])
            end
            total * NA_INCH_TO_MM
        end
        # ---------------------------------------------------------------

        # endregion =====================================================

        # =============================================================
        # REGION | Fixed Distance Calculation
        # =============================================================

        # FUNCTION | Calculate Positions with Fixed Step
        # ------------------------------------------------------------
        # Original algorithm: walks the entire path with a constant
        # step of (unit_width + spacing). Units may not land at
        # segment endpoints.
        def na_calculate_fixed_positions(path_points)
            return [] if path_points.length < 2

            step = @unit_width + @spacing
            return [] if step <= 0

            positions = []
            remaining = 0.0
            first_unit = true

            (0...path_points.length - 1).each do |i|
                seg_start = path_points[i]
                seg_end   = path_points[i + 1]
                seg_vec   = seg_end - seg_start
                seg_len   = seg_vec.length
                next if seg_len < 0.001

                direction = seg_vec.clone
                direction.length = 1.0

                cursor = remaining

                if first_unit && cursor <= 0
                    positions << { point: seg_start, direction: direction }
                    first_unit = false
                    cursor = step
                end

                while cursor <= seg_len
                    pt = seg_start.offset(direction, cursor)
                    positions << { point: pt, direction: direction }
                    cursor += step
                end

                remaining = cursor - seg_len
            end

            positions
        end
        # ---------------------------------------------------------------

        # endregion =====================================================

        # =============================================================
        # REGION | Normalised Distance Calculation
        # =============================================================

        # FUNCTION | Calculate Positions with Normalised Per-Segment Spacing
        # ------------------------------------------------------------
        # For each segment independently:
        # 1. Places a unit at the segment start and end.
        # 2. Calculates how many units fit between, adjusting spacing
        #    to be as close to the target as possible.
        # 3. Every segment gets a brick at both endpoints. At corners
        #    this means two bricks meet at the waypoint, each oriented
        #    along its own segment direction -- matching real brickwork.
        #
        # Result: every wall corner gets a unit, with even distribution
        # between them.
        def na_calculate_normalised_positions(path_points)
            return [] if path_points.length < 2

            target_step = @unit_width + @spacing
            return [] if target_step <= 0

            positions = []

            (0...path_points.length - 1).each do |seg_idx|
                seg_start = path_points[seg_idx]
                seg_end   = path_points[seg_idx + 1]
                seg_vec   = seg_end - seg_start
                seg_len   = seg_vec.length
                next if seg_len < 0.001

                direction = seg_vec.clone
                direction.length = 1.0

                span = seg_len - @unit_width

                if span <= 0
                    positions << { point: seg_start, direction: direction }
                    next
                end

                n_gaps = [1, (span / target_step).round].max
                actual_step = span.to_f / n_gaps
                n_bricks = n_gaps + 1

                (0...n_bricks).each do |i|
                    pt = seg_start.offset(direction, i * actual_step)
                    positions << { point: pt, direction: direction }
                end
            end

            positions
        end
        # ---------------------------------------------------------------

        # FUNCTION | Calculate Average Actual Spacing in mm (Normalised Mode)
        # ------------------------------------------------------------
        # Returns the average actual spacing across all segments, or nil
        # if not enough data. Used for the info text overlay.
        def na_calculate_actual_spacing_mm(path_points)
            return nil unless @normalise
            return nil if path_points.length < 2

            target_step = @unit_width + @spacing
            return nil if target_step <= 0

            total_spacing = 0.0
            segment_count = 0

            (0...path_points.length - 1).each do |seg_idx|
                seg_len = path_points[seg_idx].distance(path_points[seg_idx + 1])
                next if seg_len < 0.001

                span = seg_len - @unit_width
                next if span <= 0

                n_gaps = [1, (span / target_step).round].max
                actual_step = span.to_f / n_gaps
                actual_spacing = actual_step - @unit_width

                total_spacing += actual_spacing
                segment_count += 1
            end

            return nil if segment_count == 0
            avg_spacing_inches = total_spacing / segment_count
            (avg_spacing_inches * NA_INCH_TO_MM).round
        end
        # ---------------------------------------------------------------

        # endregion =====================================================

        # =============================================================
        # REGION | Preview Unit Drawing
        # =============================================================

        # FUNCTION | Draw All Preview Units (Batched)
        # ------------------------------------------------------------
        # Collects every preview-unit wireframe segment into one flat
        # array, then issues a single view.draw(GL_LINES, ...) call.
        # Replaces the previous per-unit 12-call pattern, so N units =
        # 1 GL call instead of 12*N. Big win for long paths.
        def na_draw_preview_units(view, positions)
            return if positions.empty?

            segments = []
            positions.each do |pos|
                na_collect_preview_unit_segments(pos[:point], pos[:direction], segments)
            end

            return if segments.empty?

            view.line_width    = 1
            view.drawing_color = NA_PREVIEW_COLOR
            view.draw(GL_LINES, segments)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Collect Wireframe Segments for One Preview Unit
        # ------------------------------------------------------------
        # Computes the 8 oriented corners of one preview box and pushes
        # 24 points (12 line segments) onto the shared segments array.
        # No drawing is performed here; the single batched draw call
        # happens in na_draw_preview_units.
        def na_collect_preview_unit_segments(origin, direction, segments)
            w = @unit_width
            d = @unit_depth
            h = @unit_height

            forward = direction.clone
            forward.length = 1.0 if forward.length > 0

            up = Z_AXIS.clone

            lateral = forward.cross(up)
            if lateral.length < 0.001
                lateral = Y_AXIS.clone
            else
                lateral.length = 1.0
            end

            actual_up = lateral.cross(forward)
            actual_up.length = 1.0 if actual_up.length > 0

            if @array_type == 'dogtooth'
                rot = Geom::Transformation.rotation(origin, forward, 45.degrees)
                lateral   = lateral.transform(rot)
                actual_up = actual_up.transform(rot)
            end

            preview_origin = na_apply_preview_anchor_offset(
                origin, forward, actual_up, w, h
            )

            half_d  = d * 0.5
            corners = na_compute_box_corners(preview_origin, forward, lateral, actual_up, w, half_d, h)
            na_collect_wireframe_box_segments(corners, segments)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Append the 12 Edges of an Oriented Box to a Segments Array
        # ------------------------------------------------------------
        # Each segment is two consecutive points. SketchUp's GL_LINES
        # treats every pair of points as one segment.
        def na_collect_wireframe_box_segments(c, segments)
            # Bottom face
            segments << c[0] << c[1]
            segments << c[1] << c[2]
            segments << c[2] << c[3]
            segments << c[3] << c[0]

            # Top face
            segments << c[4] << c[5]
            segments << c[5] << c[6]
            segments << c[6] << c[7]
            segments << c[7] << c[4]

            # Verticals
            segments << c[0] << c[4]
            segments << c[1] << c[5]
            segments << c[2] << c[6]
            segments << c[3] << c[7]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Apply Anchor-Mode Offset to Preview Box Origin
        # ------------------------------------------------------------
        # In 'centre' mode the bbox should be centred on the path point,
        # so we shift the box origin back by -width/2 along forward and
        # -height/2 along up. Lateral is already centred via half_d.
        # All other modes leave the origin untouched.
        def na_apply_preview_anchor_offset(origin, forward, up, width, height)
            return origin unless @array_type == 'object' && @anchor_mode == 'centre'

            origin
                .offset(forward, -width * 0.5)
                .offset(up,      -height * 0.5)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Compute 8 Corners of an Oriented Box
        # ------------------------------------------------------------
        def na_compute_box_corners(origin, fwd, lat, up, width, half_depth, height)
            p0 = origin
            p1 = p0.offset(fwd, width)
            p2 = p0.offset(lat, half_depth)
            p3 = p0.offset(lat, -half_depth)

            [
                p0.offset(lat, -half_depth),
                p1.offset(lat, -half_depth),
                p1.offset(lat, half_depth),
                p0.offset(lat, half_depth),
                p0.offset(lat, -half_depth).offset(up, height),
                p1.offset(lat, -half_depth).offset(up, height),
                p1.offset(lat, half_depth).offset(up, height),
                p0.offset(lat, half_depth).offset(up, height)
            ]
        end
        # ---------------------------------------------------------------

        # endregion =====================================================

        # =============================================================
        # REGION | Info Text Overlay
        # =============================================================

        # FUNCTION | Draw Info Text at Cursor
        # ------------------------------------------------------------
        def na_draw_info_text(view, positions, path_points)
            total_mm = na_path_length_mm(path_points)
            count = positions.length
            target_spacing_mm = (@spacing * NA_INCH_TO_MM).round

            if @normalise
                actual_mm = na_calculate_actual_spacing_mm(path_points)
                if actual_mm
                    label = "#{count} units | Actual: #{actual_mm}mm (target: #{target_spacing_mm}mm) | Length: #{total_mm.round}mm"
                else
                    label = "#{count} units | Normalised | Length: #{total_mm.round}mm"
                end
            else
                label = "#{count} units | Spacing: #{target_spacing_mm}mm | Length: #{total_mm.round}mm"
            end

            screen_pt = view.screen_coords(@cursor_pos)
            text_point = Geom::Point3d.new(screen_pt.x + 20, screen_pt.y - 30, 0)

            view.drawing_color = NA_TEXT_COLOR
            view.draw_text(text_point, label)
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
