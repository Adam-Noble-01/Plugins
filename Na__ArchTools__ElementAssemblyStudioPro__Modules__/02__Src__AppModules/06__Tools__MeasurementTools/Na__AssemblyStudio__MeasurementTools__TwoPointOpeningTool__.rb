# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - TWO-POINT OPENING TOOL
# =============================================================================
#
# FILE       : Na__AssemblyStudio__MeasurementTools__TwoPointOpeningTool__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__MeasurementTools
# CLASS      : Na__TwoPointOpeningTool
# AUTHOR     : Noble Architecture
# PURPOSE    : SketchUp Tool — two picks define a planar opening rectangle;
#              reports width / cill-adjusted height plus Point A inches to host.
#
# DESCRIPTION:
# - Point A anchors the façade corner; Point B completes W×H in model space.
# - Cill + bottom frame thickness drive adjusted height forwarded on complete.
# - DEFAULT_CALLBACKS may be overridden per host (window vs future systems).
#
# REFACTOR NOTES (v2 / EASP)
# - Uses Na__AssemblyStudio::Na__AppUtils::Na__DebugTools for tracing.
#
# NAMING CONVENTION:
# - Class Na__TwoPointOpeningTool; instance helpers prefixed na_*
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
    module Na__MeasurementTools

        class Na__TwoPointOpeningTool

# -----------------------------------------------------------------------------
# REGION | Module References — Constants — Default Callbacks
# -----------------------------------------------------------------------------

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

            NA_MM_TO_INCH           = 1.0 / 25.4
            NA_INCH_TO_MM           = 25.4
            NA_OVERLAY_FILL_COLOR   = Sketchup::Color.new(  0, 120, 255,  80)
            NA_OVERLAY_BORDER_COLOR = Sketchup::Color.new(  0, 120, 255, 200)
            NA_POINT_A_COLOR        = Sketchup::Color.new(  0, 200,   0)
            NA_DIMENSION_TEXT_COLOR = Sketchup::Color.new(255, 255, 255)
            NA_CROSSHAIR_SIZE       = 100.mm
            NA_GRID_SIZE            = 1.mm

            DEFAULT_CALLBACKS = {
                :complete      => :na_send_measurement_to_dialog,
                :cancel        => :na_send_measure_cancelled_to_dialog,
                :status_label  => 'Measure Opening'
            }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool API — Instantiate & Life Cycle
# -----------------------------------------------------------------------------

            # FUNCTION | Store host geometry inputs + overlay callback overrides
            # ------------------------------------------------------------
            def initialize(dialog_host, cill_height_mm, frame_bottom_thickness_mm = 50, callbacks: {})
                @dialog_host               = dialog_host
                @frame_bottom_thickness_mm = frame_bottom_thickness_mm || 50
                @is_bottom_frameless       = @frame_bottom_thickness_mm == 0
                @cill_height_mm            = @is_bottom_frameless ? 0 : (cill_height_mm || 50)

                merged           = DEFAULT_CALLBACKS.merge(callbacks)
                @cb_complete      = merged[:complete]
                @cb_cancel        = merged[:cancel]
                @status_label     = merged[:status_label]

                @ip               = Sketchup::InputPoint.new
                @ip_start         = Sketchup::InputPoint.new
                @point_a          = nil
                @current_point    = nil
                @state            = :picking_point_a

                DebugTools.na_debug_method(
                    "TwoPointOpeningTool initialized (cill=#{@cill_height_mm}mm, " \
                    "frame_bottom=#{@frame_bottom_thickness_mm}mm, " \
                    "frameless_bottom=#{@is_bottom_frameless}, " \
                    "complete_cb=#{@cb_complete})"
                )
            end
            # ---------------------------------------------------------------

            def activate
                @state = :picking_point_a
                na_update_status_text
                Sketchup.active_model.active_view.invalidate
            end

            def deactivate(view); view.invalidate; end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool API — Mouse & Cancel
# -----------------------------------------------------------------------------

            def onMouseMove(_flags, x, y, view)
                @ip.pick(view, x, y)
                return unless @ip.valid?
                @current_point = na_round_to_grid(@ip.position)
                na_update_status_text
                view.invalidate
            end

            def onLButtonDown(_flags, x, y, view)
                @ip.pick(view, x, y)
                return unless @ip.valid?
                clicked_point = na_round_to_grid(@ip.position)

                if @state == :picking_point_a
                    @point_a = clicked_point
                    @ip_start.copy!(@ip)
                    @state = :picking_point_b
                    DebugTools.na_debug_measure("Point A: #{na_point_to_mm_string(@point_a)}")
                    na_update_status_text
                    view.invalidate
                elsif @state == :picking_point_b
                    @current_point = clicked_point
                    DebugTools.na_debug_measure("Point B: #{na_point_to_mm_string(@current_point)}")
                    na_complete_measurement
                    Sketchup.active_model.select_tool(nil)
                end
            end

            def onCancel(_reason, view)
                DebugTools.na_debug_measure('Two-point measure cancelled')
                @dialog_host.public_send(@cb_cancel) if @dialog_host.respond_to?(@cb_cancel)
                view.invalidate
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool API — Draw & Selection Extents
# -----------------------------------------------------------------------------

            def draw(view)
                if @state == :picking_point_a && @current_point
                    na_draw_crosshair(view, @current_point)
                end
                return unless @point_a && @current_point && @state == :picking_point_b

                pts = na_calculate_rect_points(@point_a, @current_point)
                view.drawing_color = NA_OVERLAY_FILL_COLOR
                view.draw(GL_QUADS, pts)
                view.drawing_color = NA_OVERLAY_BORDER_COLOR
                view.line_width    = 2
                view.draw(GL_LINE_LOOP, pts)
                na_draw_crosshair(view, @point_a, NA_POINT_A_COLOR)
                na_draw_dimension_text(view, @point_a, @current_point)
            end

            def getExtents
                bb = Geom::BoundingBox.new
                bb.add(@point_a)       if @point_a
                bb.add(@current_point) if @current_point
                bb
            end

# endregion -------------------------------------------------------------------

            private

# -----------------------------------------------------------------------------
# REGION | Opening Rectangle — Overlay — Labels
# -----------------------------------------------------------------------------

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

            def na_draw_crosshair(view, point, color = nil)
                size            = NA_CROSSHAIR_SIZE * 0.5
                view.line_width = 1
                view.drawing_color = color || Sketchup::Color.new(255, 0, 0)
                view.draw_line(point.offset(X_AXIS, -size), point.offset(X_AXIS, size))
                view.drawing_color = color || Sketchup::Color.new(0, 255, 0)
                view.draw_line(point.offset(Y_AXIS, -size), point.offset(Y_AXIS, size))
                view.drawing_color = color || Sketchup::Color.new(0, 0, 255)
                view.draw_line(point.offset(Z_AXIS, -size), point.offset(Z_AXIS, size))
            end

            def na_draw_dimension_text(view, pt_a, pt_b)
                width_mm, height_mm = na_calculate_dimensions_mm(pt_a, pt_b)
                adjusted_height_mm  = [height_mm - @cill_height_mm, 0].max
                label               = "W: #{width_mm.round}mm  |  H: #{height_mm.round}mm"
                label += "  (Adj: #{adjusted_height_mm.round}mm)" if @cill_height_mm > 0
                screen_pt           = view.screen_coords(pt_b)
                view.drawing_color  = NA_DIMENSION_TEXT_COLOR
                view.draw_text(Geom::Point3d.new(screen_pt.x + 15, screen_pt.y - 25, 0), label)
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Derived Dimensions — Complete — Status — Snap
# -----------------------------------------------------------------------------

            def na_calculate_dimensions_mm(pt_a, pt_b)
                dx = (pt_b.x - pt_a.x).abs
                dy = (pt_b.y - pt_a.y).abs
                dz = (pt_b.z - pt_a.z).abs
                width_in  = [dx, dy].max
                height_in = dz
                [(width_in * NA_INCH_TO_MM).round, (height_in * NA_INCH_TO_MM).round]
            end

            def na_complete_measurement
                width_mm, height_mm = na_calculate_dimensions_mm(@point_a, @current_point)
                adjusted_height_mm  = [height_mm - @cill_height_mm, 100].max

                DebugTools.na_debug_success(
                    "Measurement complete: W=#{width_mm}mm, RawH=#{height_mm}mm, " \
                    "Cill=#{@cill_height_mm}mm, AdjH=#{adjusted_height_mm}mm"
                )

                return unless @dialog_host.respond_to?(@cb_complete)
                @dialog_host.public_send(@cb_complete,
                    width_mm, adjusted_height_mm,
                    @point_a.x, @point_a.y, @point_a.z
                )
            end

            def na_update_status_text
                if @state == :picking_point_a
                    if @current_point
                        Sketchup.status_text = "#{@status_label}: Click Point A (base corner) at #{na_point_to_mm_string(@current_point)} | ESC to cancel"
                    else
                        Sketchup.status_text = "#{@status_label}: Click Point A (base corner) | ESC to cancel"
                    end
                elsif @state == :picking_point_b
                    if @current_point
                        width_mm, height_mm = na_calculate_dimensions_mm(@point_a, @current_point)
                        adjusted             = [height_mm - @cill_height_mm, 0].max
                        Sketchup.status_text = "#{@status_label}: Click Point B | W:#{width_mm}mm H:#{adjusted}mm | ESC to cancel"
                    else
                        Sketchup.status_text = "#{@status_label}: Move cursor to set Point B | ESC to cancel"
                    end
                end
            end

            def na_round_to_grid(point)
                Geom::Point3d.new(
                    (point.x / NA_GRID_SIZE).round * NA_GRID_SIZE,
                    (point.y / NA_GRID_SIZE).round * NA_GRID_SIZE,
                    (point.z / NA_GRID_SIZE).round * NA_GRID_SIZE
                )
            end

            def na_point_to_mm_string(point)
                "X:#{(point.x * NA_INCH_TO_MM).round}mm Y:#{(point.y * NA_INCH_TO_MM).round}mm Z:#{(point.z * NA_INCH_TO_MM).round}mm"
            end

# endregion -------------------------------------------------------------------

        end

    end
end
