# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - MEASURE OPENING TOOL
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__MeasureOpeningTool__.rb
# NAMESPACE  : Na__WindowConfiguratorTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Interactive two-click tool for measuring wall openings
# CREATED    : 2026-02-16
# VERSION    : 0.7.0
#
# DESCRIPTION:
# - Two-click measurement tool for wall openings in the 3D viewport
# - Click Point A sets the base corner, Click Point B sets the opposite corner
# - Draws a semi-transparent blue overlay rectangle between the two points
# - Calculates width (dominant horizontal axis) and height (Z axis)
# - Sends measured dimensions back to the HTML dialog, adjusting height
#   by deducting the current cill height value from the UI config
# - Supports cancellation via ESC key
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__WindowConfiguratorTool__DebugTools__'

module Na__WindowConfiguratorTool

# =============================================================================
# REGION | Measure Opening Tool Class
# =============================================================================

    class Na__MeasureOpeningTool

        # CONSTANTS
        # ------------------------------------------------------------
        NA_MM_TO_INCH = 1.0 / 25.4
        NA_INCH_TO_MM = 25.4
        NA_OVERLAY_FILL_COLOR   = Sketchup::Color.new(0, 120, 255, 80)
        NA_OVERLAY_BORDER_COLOR = Sketchup::Color.new(0, 120, 255, 200)
        NA_POINT_A_COLOR        = Sketchup::Color.new(0, 200, 0)
        NA_DIMENSION_TEXT_COLOR = Sketchup::Color.new(255, 255, 255)
        NA_CROSSHAIR_SIZE       = 100.mm
        NA_GRID_SIZE            = 1.mm

        # FUNCTION | Initialize Measure Opening Tool
        # ------------------------------------------------------------
        # @param dialog_manager [Module] Reference to the DialogManager module
        # @param cill_height_mm [Numeric] Current cill height from UI config (in mm)
        def initialize(dialog_manager, cill_height_mm)
            @dialog_manager = dialog_manager
            @cill_height_mm = cill_height_mm || 50

            @ip = Sketchup::InputPoint.new
            @ip_start = Sketchup::InputPoint.new

            @point_a = nil
            @current_point = nil
            @state = :picking_point_a

            Na__DebugTools.na_debug_method("MeasureOpeningTool initialized (cill_height=#{@cill_height_mm}mm)")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Tool Activated
        # ------------------------------------------------------------
        def activate
            Na__DebugTools.na_debug_method("MeasureOpeningTool activated")
            @state = :picking_point_a
            na_update_status_text
            Sketchup.active_model.active_view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Tool Deactivated
        # ------------------------------------------------------------
        def deactivate(view)
            Na__DebugTools.na_debug_method("MeasureOpeningTool deactivated")
            view.invalidate
        end
        # ---------------------------------------------------------------

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

            if @state == :picking_point_a
                @point_a = clicked_point
                @ip_start.copy!(@ip)
                @state = :picking_point_b
                Na__DebugTools.na_debug_info("Point A set: #{na_point_to_mm_string(@point_a)}")
                na_update_status_text
                view.invalidate

            elsif @state == :picking_point_b
                @current_point = clicked_point
                Na__DebugTools.na_debug_info("Point B set: #{na_point_to_mm_string(@current_point)}")

                na_complete_measurement
                Sketchup.active_model.select_tool(nil)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Cancel Handler (ESC Key)
        # ------------------------------------------------------------
        def onCancel(reason, view)
            Na__DebugTools.na_debug_info("Measure Opening cancelled")
            
            # Notify dialog that measurement was cancelled
            @dialog_manager.na_send_measure_cancelled_to_dialog
            
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw Handler
        # ------------------------------------------------------------
        # Draws the semi-transparent blue overlay rectangle and dimension info
        def draw(view)
            if @state == :picking_point_a && @current_point
                na_draw_crosshair(view, @current_point)
            end

            return unless @point_a && @current_point && @state == :picking_point_b

            pts = na_calculate_rect_points(@point_a, @current_point)

            # Draw filled semi-transparent blue quad
            view.drawing_color = NA_OVERLAY_FILL_COLOR
            view.draw(GL_QUADS, pts)

            # Draw solid outline
            view.drawing_color = NA_OVERLAY_BORDER_COLOR
            view.line_width = 2
            view.draw(GL_LINE_LOOP, pts)

            # Draw Point A marker (green crosshair)
            na_draw_crosshair(view, @point_a, NA_POINT_A_COLOR)

            # Draw dimension text at the current mouse position
            na_draw_dimension_text(view, @point_a, @current_point)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Extents (prevents drawing from being clipped)
        # ------------------------------------------------------------
        def getExtents
            bb = Geom::BoundingBox.new
            bb.add(@point_a) if @point_a
            bb.add(@current_point) if @current_point
            bb
        end
        # ---------------------------------------------------------------

        private

        # FUNCTION | Calculate Rectangle Points for Overlay
        # ------------------------------------------------------------
        # Determines the 4 corners of the rectangle based on Point A and Point B.
        # Uses the dominant horizontal axis (X or Y) and the Z axis to form the plane.
        # @param pt_a [Geom::Point3d] First corner point
        # @param pt_b [Geom::Point3d] Second corner point
        # @return [Array<Geom::Point3d>] 4 corner points for the rectangle
        def na_calculate_rect_points(pt_a, pt_b)
            dx = (pt_b.x - pt_a.x).abs
            dy = (pt_b.y - pt_a.y).abs

            if dx >= dy
                # Rectangle lies in XZ plane (wall along X axis)
                [
                    Geom::Point3d.new(pt_a.x, pt_a.y, pt_a.z),
                    Geom::Point3d.new(pt_b.x, pt_a.y, pt_a.z),
                    Geom::Point3d.new(pt_b.x, pt_a.y, pt_b.z),
                    Geom::Point3d.new(pt_a.x, pt_a.y, pt_b.z)
                ]
            else
                # Rectangle lies in YZ plane (wall along Y axis)
                [
                    Geom::Point3d.new(pt_a.x, pt_a.y, pt_a.z),
                    Geom::Point3d.new(pt_a.x, pt_b.y, pt_a.z),
                    Geom::Point3d.new(pt_a.x, pt_b.y, pt_b.z),
                    Geom::Point3d.new(pt_a.x, pt_a.y, pt_b.z)
                ]
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw Crosshair at a Point
        # ------------------------------------------------------------
        def na_draw_crosshair(view, point, color = nil)
            size = NA_CROSSHAIR_SIZE * 0.5
            view.line_width = 1

            # X axis (red by default)
            view.drawing_color = color || Sketchup::Color.new(255, 0, 0)
            view.draw_line(
                point.offset(X_AXIS, -size),
                point.offset(X_AXIS, size)
            )

            # Y axis (green by default)
            view.drawing_color = color || Sketchup::Color.new(0, 255, 0)
            view.draw_line(
                point.offset(Y_AXIS, -size),
                point.offset(Y_AXIS, size)
            )

            # Z axis (blue by default)
            view.drawing_color = color || Sketchup::Color.new(0, 0, 255)
            view.draw_line(
                point.offset(Z_AXIS, -size),
                point.offset(Z_AXIS, size)
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw Dimension Text Overlay
        # ------------------------------------------------------------
        # Draws width and height dimension labels near the cursor in screen space
        def na_draw_dimension_text(view, pt_a, pt_b)
            width_mm, height_mm = na_calculate_dimensions_mm(pt_a, pt_b)
            adjusted_height_mm = [height_mm - @cill_height_mm, 0].max

            # Build label text
            label = "W: #{width_mm.round}mm  |  H: #{height_mm.round}mm"
            label += "  (Adj: #{adjusted_height_mm.round}mm)" if @cill_height_mm > 0

            # Convert Point B to screen coordinates for text placement
            screen_pt = view.screen_coords(pt_b)
            text_point = Geom::Point3d.new(screen_pt.x + 15, screen_pt.y - 25, 0)

            view.drawing_color = NA_DIMENSION_TEXT_COLOR
            view.draw_text(text_point, label)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Calculate Dimensions in Millimeters
        # ------------------------------------------------------------
        # @param pt_a [Geom::Point3d] First corner (in inches internally)
        # @param pt_b [Geom::Point3d] Second corner (in inches internally)
        # @return [Array<Float>] [width_mm, height_mm]
        def na_calculate_dimensions_mm(pt_a, pt_b)
            dx = (pt_b.x - pt_a.x).abs
            dy = (pt_b.y - pt_a.y).abs
            dz = (pt_b.z - pt_a.z).abs

            # Width is the dominant horizontal axis
            width_inches = [dx, dy].max
            height_inches = dz

            width_mm = (width_inches * NA_INCH_TO_MM).round
            height_mm = (height_inches * NA_INCH_TO_MM).round

            [width_mm, height_mm]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Complete Measurement and Send to Dialog
        # ------------------------------------------------------------
        def na_complete_measurement
            width_mm, height_mm = na_calculate_dimensions_mm(@point_a, @current_point)
            adjusted_height_mm = [height_mm - @cill_height_mm, 100].max

            Na__DebugTools.na_debug_success(
                "Measurement complete: Width=#{width_mm}mm, " \
                "Raw Height=#{height_mm}mm, Cill=#{@cill_height_mm}mm, " \
                "Adjusted Height=#{adjusted_height_mm}mm"
            )

            # Send measurement back to the HTML dialog
            @dialog_manager.na_send_measurement_to_dialog(width_mm, adjusted_height_mm)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Update Status Bar Text
        # ------------------------------------------------------------
        def na_update_status_text
            if @state == :picking_point_a
                if @current_point
                    pos_str = na_point_to_mm_string(@current_point)
                    Sketchup.status_text = "Measure Opening: Click to set Point A (base corner) at #{pos_str} | ESC to cancel"
                else
                    Sketchup.status_text = "Measure Opening: Click to set Point A (base corner) | ESC to cancel"
                end
            elsif @state == :picking_point_b
                if @current_point
                    width_mm, height_mm = na_calculate_dimensions_mm(@point_a, @current_point)
                    adjusted_height_mm = [height_mm - @cill_height_mm, 0].max
                    Sketchup.status_text = "Measure Opening: Click to set Point B | W:#{width_mm}mm H:#{adjusted_height_mm}mm | ESC to cancel"
                else
                    Sketchup.status_text = "Measure Opening: Move cursor to set Point B | ESC to cancel"
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Round Point to Grid (1mm precision)
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

    end

# endregion ===================================================================

end # module Na__WindowConfiguratorTool

# =============================================================================
# END OF FILE
# =============================================================================
