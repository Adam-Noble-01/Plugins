# =============================================================================
# NA ARRAY BUILDER TOOLS - PATH TOOL
# =============================================================================
#
# FILE       : Na__ArrayBuilder__PathTool__.rb
# NAMESPACE  : Na__ArrayBuilderTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Interactive 3D tool for defining array paths with preview
# CREATED    : 2026
# VERSION    : 0.0.2
#
# DESCRIPTION:
# - Crosshair-based tool for defining multi-segment paths
# - Click to set start point, Ctrl+Click to add waypoints, Click to finish
# - Live wireframe preview of array units along the path
# - Displays count, spacing, and total length info overlay
# - Delegates geometry creation to GeometryBuilder on commit
#
# =============================================================================

require 'sketchup.rb'

module Na__ArrayBuilderTools

# =============================================================================
# REGION | Path Tool Class
# =============================================================================

    class Na__ArrayBuilder__PathTool

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

            @unit_width  = (config['unit_width_mm']  || 110).to_f.mm
            @unit_depth  = (config['unit_depth_mm']   || 30).to_f.mm
            @unit_height = (config['unit_height_mm']  || 75).to_f.mm
            @spacing     = (config['spacing_mm']      || 115).to_f.mm
            @array_type  = config['type'] || 'dentil'
            @normalise   = config['normalise_distance'] == true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Tool Activated
        # ------------------------------------------------------------
        def activate
            @state = :picking_start
            @waypoints = []
            @cursor_pos = nil
            na_update_status_text
            Sketchup.active_model.active_view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Tool Deactivated
        # ------------------------------------------------------------
        def deactivate(view)
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Mouse Move Handler
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            if @state == :picking_path && !@waypoints.empty?
                @ip.pick(view, x, y, @ip_prev)
            else
                @ip.pick(view, x, y)
            end
            return unless @ip.valid?

            @cursor_pos = na_round_to_grid(@ip.position)
            na_update_status_text
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Left Mouse Button Down Handler
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @ip.pick(view, x, y)
            return unless @ip.valid?

            clicked = na_round_to_grid(@ip.position)

            if @state == :picking_start
                @waypoints = [clicked]
                @ip_prev.copy!(@ip)
                @state = :picking_path
                na_update_status_text
                view.invalidate

            elsif @state == :picking_path
                ctrl_down = (flags & COPY_MODIFIER_MASK) != 0

                if ctrl_down
                    @waypoints << clicked
                    @ip_prev.copy!(@ip)
                    na_update_status_text
                    view.invalidate
                else
                    @waypoints << clicked
                    na_commit_array(view)
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Cancel Handler (ESC)
        # ------------------------------------------------------------
        def onCancel(reason, view)
            @dialog_manager.na_send_status_to_dialog("info", "Array placement cancelled")
            view.invalidate
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

                preview_path = @waypoints + [@cursor_pos]
                positions = na_calculate_preview_positions(preview_path)
                na_draw_preview_units(view, positions)
                na_draw_info_text(view, positions, preview_path)

                total_mm = na_path_length_mm(preview_path)
                actual_spacing_mm = na_calculate_actual_spacing_mm(preview_path)
                @dialog_manager.na_send_preview_info(positions.length, total_mm, actual_spacing_mm)
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
        # 3. Skips the start unit on segments after the first to avoid
        #    duplicates at shared waypoints.
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
                    if seg_idx == 0
                        positions << { point: seg_start, direction: direction }
                    end
                    next
                end

                n_gaps = [1, (span / target_step).round].max
                actual_step = span.to_f / n_gaps
                n_bricks = n_gaps + 1

                start_i = (seg_idx == 0) ? 0 : 1

                (start_i...n_bricks).each do |i|
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

        # FUNCTION | Draw All Preview Units
        # ------------------------------------------------------------
        def na_draw_preview_units(view, positions)
            view.line_width = 1
            view.drawing_color = NA_PREVIEW_COLOR

            positions.each do |pos|
                na_draw_preview_unit(view, pos[:point], pos[:direction])
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw Single Preview Unit Wireframe
        # ------------------------------------------------------------
        # Draws a wireframe box oriented along the path direction.
        # For dog-tooth, the box is rotated 45 degrees around the
        # path-perpendicular axis (Z axis relative to path).
        def na_draw_preview_unit(view, origin, direction)
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
                lateral  = lateral.transform(rot)
                actual_up = actual_up.transform(rot)
            end

            half_d = d * 0.5
            corners = na_compute_box_corners(origin, forward, lateral, actual_up, w, half_d, h)
            na_draw_wireframe_box(view, corners)
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

        # FUNCTION | Draw Wireframe Box from 8 Corners
        # ------------------------------------------------------------
        def na_draw_wireframe_box(view, c)
            view.drawing_color = NA_PREVIEW_COLOR
            view.line_width = 1

            # Bottom face
            view.draw_line(c[0], c[1])
            view.draw_line(c[1], c[2])
            view.draw_line(c[2], c[3])
            view.draw_line(c[3], c[0])

            # Top face
            view.draw_line(c[4], c[5])
            view.draw_line(c[5], c[6])
            view.draw_line(c[6], c[7])
            view.draw_line(c[7], c[4])

            # Verticals
            view.draw_line(c[0], c[4])
            view.draw_line(c[1], c[5])
            view.draw_line(c[2], c[6])
            view.draw_line(c[3], c[7])
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
            type_label = @array_type == 'dogtooth' ? 'Dog-Tooth' : 'Dentil'

            if @state == :picking_start
                if @cursor_pos
                    pos_str = na_point_to_mm_string(@cursor_pos)
                    Sketchup.status_text = "Array Builder (#{type_label}): Click to set start point at #{pos_str} | ESC to cancel"
                else
                    Sketchup.status_text = "Array Builder (#{type_label}): Click to set start point | ESC to cancel"
                end

            elsif @state == :picking_path
                if @cursor_pos
                    preview_path = @waypoints + [@cursor_pos]
                    positions = na_calculate_preview_positions(preview_path)
                    count = positions.length
                    total_mm = na_path_length_mm(preview_path).round
                    Sketchup.status_text = "Array Builder: Click to finish | Ctrl+Click to add waypoint | #{count} units | #{total_mm}mm | ESC to cancel"
                else
                    Sketchup.status_text = "Array Builder: Move cursor to define path | Ctrl+Click to add waypoint | ESC to cancel"
                end
            end
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
