# =============================================================================
# NA MEASUREMENT TOOLS - THREE-POINT OPENING TOOL
# =============================================================================
#
# FILE       : Na__MeasurementTools__ThreePointOpeningTool__.rb
# NAMESPACE  : Na__MeasurementTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Tool-agnostic three-click measurement tool for door / wall
#              openings that captures width, height AND wall depth.
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Captures Point A (base corner), Point B (opposite top corner), and
#   Point D (wall-depth pick). The third pick is constrained to the axis
#   perpendicular to the wall so the user can drag along the wall depth
#   without slipping off the chosen direction.
# - State machine:
#     :picking_a      Move + click sets Point A.
#     :picking_b      Move shows blue overlay + W/H label; click sets B.
#     :picking_depth  Move shows RED overlay + W/H/D label; click sets D.
# - Sends back to the host module:
#     `host.na_send_door_measurement_to_dialog(width_mm, height_mm,
#                                              depth_mm, ax_in, ay_in, az_in)`
#   (host name kept for compatibility with the Interior Door Configurator
#   which is the only current consumer; future hosts can implement the
#   same method name).
# - ESC at any state cancels and notifies the host via
#   `host.na_send_door_measure_cancelled_to_dialog`.
#
# RELOCATION HISTORY:
# - 0.11.4 (01-May-2026) : Forked from
#       Na__InteriorDoorConfigurator__MeasureDoorOpeningTool__.rb
#       and re-namespaced under Na__MeasurementTools.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__MeasurementTools__TwoPointOpeningTool__'                 # <-- Loads the resolver Na__MeasurementTools.na_resolve_debug_tools

module Na__MeasurementTools

# =============================================================================
# REGION | Three-Point Opening Tool Class
# =============================================================================

    class Na__ThreePointOpeningTool

        # MODULE CONSTANTS | Conversion and Visual Style
        # ------------------------------------------------------------
        NA_MM_TO_INCH                = 1.0 / 25.4                              # <-- Millimetre to inch conversion
        NA_INCH_TO_MM                = 25.4                                    # <-- Inverse conversion

        NA_BLUE_FILL_COLOR           = Sketchup::Color.new(  0, 120, 255,  80) # <-- Blue overlay (W/H phase)
        NA_BLUE_BORDER_COLOR         = Sketchup::Color.new(  0, 120, 255, 200)
        NA_RED_FILL_COLOR            = Sketchup::Color.new(220,  40,  40, 100) # <-- Red overlay (depth phase)
        NA_RED_BORDER_COLOR          = Sketchup::Color.new(220,  40,  40, 220)

        NA_POINT_A_COLOR             = Sketchup::Color.new(  0, 200,   0)      # <-- Point A marker
        NA_DIMENSION_TEXT_COLOR      = Sketchup::Color.new(255, 255, 255)      # <-- Dimension label colour
        NA_CROSSHAIR_SIZE            = 100.mm                                  # <-- Crosshair span
        NA_GRID_SIZE                 = 1.mm                                    # <-- Snap grid resolution
        # ---------------------------------------------------------------

        # FUNCTION | Initialize the Three-Point Opening Tool
        # ------------------------------------------------------------
        # @param dialog_host [Module] Host exposing
        #        na_send_door_measurement_to_dialog and
        #        na_send_door_measure_cancelled_to_dialog
        def initialize(dialog_host)
            @dialog_host    = dialog_host
            @ip             = Sketchup::InputPoint.new

            @point_a        = nil                                              # <-- Origin (Point A)
            @point_b        = nil                                              # <-- Width / height corner
            @current_point  = nil                                              # <-- Live cursor (rounded to grid)
            @depth_point    = nil                                              # <-- Wall-depth pick

            @wall_axis      = nil                                              # <-- :x or :y dominant axis from A->B
            @state          = :picking_a

            @debug_tools    = Na__MeasurementTools.na_resolve_debug_tools
            @debug_tools.na_debug_method("Na__ThreePointOpeningTool initialized")
        end
        # ---------------------------------------------------------------

# endregion ===================================================================


# =============================================================================
# REGION | Sketchup::Tool Lifecycle Hooks
# =============================================================================

        # FUNCTION | Tool Activated
        # ------------------------------------------------------------
        def activate
            @state = :picking_a
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

# endregion ===================================================================


# =============================================================================
# REGION | Mouse and Cancel Handlers
# =============================================================================

        # FUNCTION | Mouse Move Handler
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            @ip.pick(view, x, y)
            return unless @ip.valid?

            @current_point = na_round_to_grid(@ip.position)
            na_update_status_text
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Left Mouse Button Down Handler
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @ip.pick(view, x, y)
            return unless @ip.valid?

            clicked_point = na_round_to_grid(@ip.position)

            case @state
            when :picking_a
                @point_a   = clicked_point
                @state     = :picking_b
                @debug_tools.na_debug_measure("Point A set: #{na_point_to_mm_string(@point_a)}")
            when :picking_b
                @point_b   = clicked_point
                @wall_axis = na_compute_wall_axis(@point_a, @point_b)
                @state     = :picking_depth
                @debug_tools.na_debug_measure("Point B set: #{na_point_to_mm_string(@point_b)} (wall_axis=#{@wall_axis})")
            when :picking_depth
                @depth_point = na_constrain_depth_point(clicked_point)
                @debug_tools.na_debug_measure("Depth point set: #{na_point_to_mm_string(@depth_point)}")
                na_complete_measurement
                Sketchup.active_model.select_tool(nil)
            end

            na_update_status_text
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | ESC Cancel Handler
        # ------------------------------------------------------------
        def onCancel(reason, view)
            @debug_tools.na_debug_measure("Three-point measure cancelled")
            if @dialog_host.respond_to?(:na_send_door_measure_cancelled_to_dialog)
                @dialog_host.na_send_door_measure_cancelled_to_dialog
            end
            view.invalidate
        end
        # ---------------------------------------------------------------

# endregion ===================================================================


# =============================================================================
# REGION | Draw Handler
# =============================================================================

        # FUNCTION | Draw the Active Overlay for the Current State
        # ------------------------------------------------------------
        def draw(view)
            if @state == :picking_a && @current_point
                na_draw_crosshair(view, @current_point)
                return
            end

            if @state == :picking_b && @point_a && @current_point
                rect_pts = na_calculate_rect_points(@point_a, @current_point)
                na_draw_filled_quad(view, rect_pts, NA_BLUE_FILL_COLOR, NA_BLUE_BORDER_COLOR)
                na_draw_crosshair(view, @point_a, NA_POINT_A_COLOR)
                na_draw_dimension_text_wh(view, @point_a, @current_point)
                return
            end

            if @state == :picking_depth && @point_a && @point_b && @current_point
                base_rect_pts = na_calculate_rect_points(@point_a, @point_b)
                depth_target  = na_constrain_depth_point(@current_point)
                box_pts_top   = na_offset_rect_to_depth(base_rect_pts, depth_target)

                na_draw_filled_box(view, base_rect_pts, box_pts_top, NA_RED_FILL_COLOR, NA_RED_BORDER_COLOR)
                na_draw_crosshair(view, @point_a, NA_POINT_A_COLOR)
                na_draw_dimension_text_whd(view, @point_a, @point_b, depth_target)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Extents (prevents draw clipping)
        # ------------------------------------------------------------
        def getExtents
            bb = Geom::BoundingBox.new
            bb.add(@point_a)       if @point_a
            bb.add(@point_b)       if @point_b
            bb.add(@current_point) if @current_point
            bb.add(@depth_point)   if @depth_point
            bb
        end
        # ---------------------------------------------------------------

# endregion ===================================================================


        private

# =============================================================================
# REGION | Geometry Helpers - Wall Axis and Constraints
# =============================================================================

        # HELPER FUNCTION | Determine Which Axis the Wall Lies Along
        # ------------------------------------------------------------
        # Returns :x if A->B has a larger X delta than Y delta (wall runs
        # along world X), :y otherwise. The depth pick is then snapped
        # along the perpendicular world axis.
        def na_compute_wall_axis(pt_a, pt_b)
            dx = (pt_b.x - pt_a.x).abs
            dy = (pt_b.y - pt_a.y).abs
            (dx >= dy) ? :x : :y
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Constrain a Cursor Point to the Depth Axis
        # ------------------------------------------------------------
        # During :picking_depth, the cursor's free position is projected
        # onto the axis perpendicular to the wall, preserving the X/Y of
        # Point A on the locked-out axis and the Z of Point A.
        def na_constrain_depth_point(cursor)
            return cursor unless @point_a && @wall_axis
            if @wall_axis == :x
                Geom::Point3d.new(@point_a.x, cursor.y, @point_a.z)
            else
                Geom::Point3d.new(cursor.x, @point_a.y, @point_a.z)
            end
        end
        # ---------------------------------------------------------------

# endregion ===================================================================


# =============================================================================
# REGION | Geometry Helpers - Rect / Box
# =============================================================================

        # HELPER FUNCTION | Build the Four Corners of the Width/Height Rectangle
        # ------------------------------------------------------------
        def na_calculate_rect_points(pt_a, pt_b)
            dx = (pt_b.x - pt_a.x).abs
            dy = (pt_b.y - pt_a.y).abs

            if dx >= dy
                [
                    Geom::Point3d.new(pt_a.x, pt_a.y, pt_a.z),
                    Geom::Point3d.new(pt_b.x, pt_a.y, pt_a.z),
                    Geom::Point3d.new(pt_b.x, pt_a.y, pt_b.z),
                    Geom::Point3d.new(pt_a.x, pt_a.y, pt_b.z)
                ]
            else
                [
                    Geom::Point3d.new(pt_a.x, pt_a.y, pt_a.z),
                    Geom::Point3d.new(pt_a.x, pt_b.y, pt_a.z),
                    Geom::Point3d.new(pt_a.x, pt_b.y, pt_b.z),
                    Geom::Point3d.new(pt_a.x, pt_a.y, pt_b.z)
                ]
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Offset a Rect by the Depth Vector
        # ------------------------------------------------------------
        def na_offset_rect_to_depth(rect_pts, depth_target)
            offset_vec = depth_target - @point_a
            rect_pts.map { |pt| pt.offset(offset_vec) }
        end
        # ---------------------------------------------------------------

# endregion ===================================================================


# =============================================================================
# REGION | Drawing Primitives
# =============================================================================

        # HELPER FUNCTION | Draw a Filled Quad with Outline
        # ------------------------------------------------------------
        def na_draw_filled_quad(view, pts, fill, border)
            view.drawing_color = fill
            view.draw(GL_QUADS, pts)
            view.drawing_color = border
            view.line_width    = 2
            view.draw(GL_LINE_LOOP, pts)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Draw a Filled Box with Six Faces and Outlined Edges
        # ------------------------------------------------------------
        # @param near [Array<Geom::Point3d>] 4 corners of the front rect
        # @param far  [Array<Geom::Point3d>] 4 corners of the back rect
        def na_draw_filled_box(view, near, far, fill, border)
            faces = [
                near,
                far,
                [near[0], near[1], far[1], far[0]],
                [near[1], near[2], far[2], far[1]],
                [near[2], near[3], far[3], far[2]],
                [near[3], near[0], far[0], far[3]]
            ]

            view.drawing_color = fill
            faces.each { |face_pts| view.draw(GL_QUADS, face_pts) }

            view.drawing_color = border
            view.line_width    = 2
            view.draw(GL_LINE_LOOP, near)
            view.draw(GL_LINE_LOOP, far)
            4.times { |i| view.draw_line(near[i], far[i]) }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Draw a Coloured Axis Crosshair at a World Point
        # ------------------------------------------------------------
        def na_draw_crosshair(view, point, color = nil)
            size              = NA_CROSSHAIR_SIZE * 0.5
            view.line_width   = 1

            view.drawing_color = color || Sketchup::Color.new(255, 0, 0)
            view.draw_line(point.offset(X_AXIS, -size), point.offset(X_AXIS, size))

            view.drawing_color = color || Sketchup::Color.new(0, 255, 0)
            view.draw_line(point.offset(Y_AXIS, -size), point.offset(Y_AXIS, size))

            view.drawing_color = color || Sketchup::Color.new(0, 0, 255)
            view.draw_line(point.offset(Z_AXIS, -size), point.offset(Z_AXIS, size))
        end
        # ---------------------------------------------------------------

# endregion ===================================================================


# =============================================================================
# REGION | Dimension Labels
# =============================================================================

        # HELPER FUNCTION | Draw the W/H Label (picking_b state)
        # ------------------------------------------------------------
        def na_draw_dimension_text_wh(view, pt_a, pt_b)
            width_mm, height_mm = na_calculate_wh_mm(pt_a, pt_b)
            label               = "W: #{width_mm}mm  |  H: #{height_mm}mm"
            screen_pt           = view.screen_coords(pt_b)
            view.drawing_color  = NA_DIMENSION_TEXT_COLOR
            view.draw_text(Geom::Point3d.new(screen_pt.x + 15, screen_pt.y - 25, 0), label)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Draw the W/H/D Label (picking_depth state)
        # ------------------------------------------------------------
        def na_draw_dimension_text_whd(view, pt_a, pt_b, pt_d)
            width_mm, height_mm = na_calculate_wh_mm(pt_a, pt_b)
            depth_mm            = na_calculate_depth_mm(pt_a, pt_d)
            label               = "W:#{width_mm}mm  H:#{height_mm}mm  D:#{depth_mm}mm"
            screen_pt           = view.screen_coords(pt_d)
            view.drawing_color  = NA_DIMENSION_TEXT_COLOR
            view.draw_text(Geom::Point3d.new(screen_pt.x + 15, screen_pt.y - 25, 0), label)
        end
        # ---------------------------------------------------------------

# endregion ===================================================================


# =============================================================================
# REGION | Dimension Math
# =============================================================================

        # HELPER FUNCTION | Calculate Width and Height in Millimetres
        # ------------------------------------------------------------
        def na_calculate_wh_mm(pt_a, pt_b)
            dx = (pt_b.x - pt_a.x).abs
            dy = (pt_b.y - pt_a.y).abs
            dz = (pt_b.z - pt_a.z).abs

            width_in  = [dx, dy].max
            height_in = dz

            [(width_in * NA_INCH_TO_MM).round, (height_in * NA_INCH_TO_MM).round]
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Calculate the Wall Depth in Millimetres
        # ------------------------------------------------------------
        def na_calculate_depth_mm(pt_a, pt_d)
            depth_in = if @wall_axis == :x
                           (pt_d.y - pt_a.y).abs
                       else
                           (pt_d.x - pt_a.x).abs
                       end
            (depth_in * NA_INCH_TO_MM).round
        end
        # ---------------------------------------------------------------

# endregion ===================================================================


# =============================================================================
# REGION | Status Text
# =============================================================================

        # HELPER FUNCTION | Update Status Bar Text Based on State
        # ------------------------------------------------------------
        def na_update_status_text
            case @state
            when :picking_a
                Sketchup.status_text = "Measure Door Opening: Click Point A (base corner) | ESC to cancel"
            when :picking_b
                if @current_point
                    w_mm, h_mm = na_calculate_wh_mm(@point_a, @current_point)
                    Sketchup.status_text = "Measure Door Opening: Click Point B | W:#{w_mm}mm H:#{h_mm}mm | ESC to cancel"
                else
                    Sketchup.status_text = "Measure Door Opening: Move cursor to set Point B | ESC to cancel"
                end
            when :picking_depth
                if @current_point
                    constrained = na_constrain_depth_point(@current_point)
                    w_mm, h_mm  = na_calculate_wh_mm(@point_a, @point_b)
                    d_mm        = na_calculate_depth_mm(@point_a, constrained)
                    Sketchup.status_text = "Measure Door Opening: Click for wall depth | W:#{w_mm}mm H:#{h_mm}mm D:#{d_mm}mm | ESC to cancel"
                else
                    Sketchup.status_text = "Measure Door Opening: Move cursor along wall depth axis | ESC to cancel"
                end
            end
        end
        # ---------------------------------------------------------------

# endregion ===================================================================


# =============================================================================
# REGION | Completion and Snap
# =============================================================================

        # HELPER FUNCTION | Round a Point to a 1mm Grid
        # ------------------------------------------------------------
        def na_round_to_grid(point)
            Geom::Point3d.new(
                (point.x / NA_GRID_SIZE).round * NA_GRID_SIZE,
                (point.y / NA_GRID_SIZE).round * NA_GRID_SIZE,
                (point.z / NA_GRID_SIZE).round * NA_GRID_SIZE
            )
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Format a Point as an mm Triplet String
        # ------------------------------------------------------------
        def na_point_to_mm_string(point)
            x_mm = (point.x * NA_INCH_TO_MM).round
            y_mm = (point.y * NA_INCH_TO_MM).round
            z_mm = (point.z * NA_INCH_TO_MM).round
            "X:#{x_mm}mm Y:#{y_mm}mm Z:#{z_mm}mm"
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Send Final Measurement to the Host Dialog
        # ------------------------------------------------------------
        def na_complete_measurement
            return unless @point_a && @point_b && @depth_point

            width_mm, height_mm = na_calculate_wh_mm(@point_a, @point_b)
            depth_mm            = na_calculate_depth_mm(@point_a, @depth_point)

            @debug_tools.na_debug_success(
                "Three-point measure complete: W=#{width_mm}mm H=#{height_mm}mm D=#{depth_mm}mm"
            )

            return unless @dialog_host.respond_to?(:na_send_door_measurement_to_dialog)
            @dialog_host.na_send_door_measurement_to_dialog(
                width_mm, height_mm, depth_mm,
                @point_a.x, @point_a.y, @point_a.z
            )
        end
        # ---------------------------------------------------------------

# endregion ===================================================================

    end # class Na__ThreePointOpeningTool

# endregion -------------------------------------------------------------------

end # module Na__MeasurementTools

# =============================================================================
# END OF FILE
# =============================================================================
