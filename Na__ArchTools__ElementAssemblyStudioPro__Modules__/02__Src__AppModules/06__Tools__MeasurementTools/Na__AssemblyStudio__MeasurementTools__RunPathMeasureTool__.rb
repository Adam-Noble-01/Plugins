# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - RUN PATH MEASURE TOOL
# =============================================================================
#
# FILE       : Na__AssemblyStudio__MeasurementTools__RunPathMeasureTool__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__MeasurementTools
# CLASS      : Na__RunPathMeasureTool
# AUTHOR     : Noble Architecture
# PURPOSE    : SketchUp Tool that picks the path of an Assembly Run: click
#              each corner in turn, press Enter (or double click) at the last,
#              then click on the side the elements are seen from. Clicking
#              the first point again closes the path into a loop.
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# WHAT IT HANDS THE HOST (world, inches)
# - na_send_run_path_to_dialog(points, side_point, closed)
#     points     : the corners in the order clicked, levelled to the first
#     side_point : a point on the side the elements are seen from (the
#                  outside of a framework, the room for cabinets)
#     closed     : true when the path was closed onto its first point
#   The host turns these into the run's placement and its own path
#   (Na__RunPipelines.na_world_path_frame); the side decides which way the
#   path runs, so the corners may be clicked in either direction.
#
# COORDINATES
# - InputPoint positions are world in any context, and so is everything this
#   tool draws and returns (see the Coordinate Rule).
#
# KEYS
# - Enter finishes the corners. Esc cancels. No single-letter keys
#   (SketchUp's shortcuts take them first).
#
# NAMING CONVENTION:
# - Class Na__RunPathMeasureTool; instance helpers prefixed na_*
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
    module Na__MeasurementTools

        class Na__RunPathMeasureTool

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

            NA_INCH_TO_MM        = 25.4
            NA_MIN_LEG_MM        = 50.0
            NA_CLOSE_PIXELS      = 14                                            # <-- A click this near the first point closes the path
            NA_CROSSHAIR_SIZE    = 60.mm
            NA_SIDE_ARROW        = 400.mm
            NA_LINE_COLOR        = Sketchup::Color.new(0, 120, 255)
            NA_POINT_COLOR       = Sketchup::Color.new(0, 180, 0)
            NA_TEXT_COLOR        = Sketchup::Color.new(20, 20, 20)

            DEFAULT_CALLBACKS = {
                :complete     => :na_send_run_path_to_dialog,
                :cancel       => :na_send_run_path_cancelled_to_dialog,
                :status_label => 'Measure Run Path'
            }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool API - Life Cycle
# -----------------------------------------------------------------------------

            # FUNCTION | Attach the Host and Start at the First Corner
            # ------------------------------------------------------------
            # @param side_label [String] what the last click means, for the status line
            def initialize(dialog_host, side_label: 'the side the elements are seen from', callbacks: {})
                @dialog_host  = dialog_host
                merged        = DEFAULT_CALLBACKS.merge(callbacks)
                @cb_complete  = merged[:complete]
                @cb_cancel    = merged[:cancel]
                @status_label = merged[:status_label]
                @side_label   = side_label
                @ip           = Sketchup::InputPoint.new
                @ip_last      = Sketchup::InputPoint.new
                @points       = []
                @cursor       = nil
                @closed       = false
                @state        = :picking_corners
            end
            # ---------------------------------------------------------------

            def activate
                na_update_status_text
                Sketchup.active_model.active_view.invalidate
            end

            def deactivate(view)
                view.invalidate
            end

            def resume(view)
                na_update_status_text
                view.invalidate
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool API - Mouse and Keys
# -----------------------------------------------------------------------------

            def onMouseMove(_flags, x, y, view)
                if @state == :picking_corners && !@points.empty?
                    @ip.pick(view, x, y, @ip_last)                               # <-- Infer from the last corner (on-axis, parallel)
                else
                    @ip.pick(view, x, y)
                end
                return unless @ip.valid?
                @cursor = @ip.position
                view.tooltip = @ip.tooltip if @ip.respond_to?(:tooltip)
                na_update_status_text
                view.invalidate
            end

            def onLButtonDown(flags, x, y, view)
                onMouseMove(flags, x, y, view)
                return unless @ip.valid?

                if @state == :picking_side
                    na_complete(@ip.position)
                    Sketchup.active_model.select_tool(nil)
                    return
                end

                if @points.length >= 3 && na_near_first?(view, x, y)
                    @closed = true
                    @state  = :picking_side
                else
                    corner = na_level_point(@ip.position)
                    if !@points.empty? && na_length_mm(@points.last, corner) < NA_MIN_LEG_MM
                        UI.beep
                        return
                    end
                    @points << corner
                    @ip_last.copy!(@ip)
                end
                na_update_status_text
                view.invalidate
            end

            # A double click lands as two clicks; the second is too near the
            # first to be a corner, so it only ends the corners.
            def onLButtonDoubleClick(_flags, _x, _y, view)
                na_end_corners(view)
            end

            def onReturn(view)
                na_end_corners(view)
            end

            def onCancel(_reason, view)
                DebugTools.na_debug_measure("Run path measure cancelled")
                @dialog_host.public_send(@cb_cancel) if @dialog_host.respond_to?(@cb_cancel)
                view.invalidate
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool API - Drawing
# -----------------------------------------------------------------------------

            def draw(view)
                @ip.draw(view) if @ip.valid? && @ip.display?
                line = @points.dup
                line << na_level_point(@cursor) if @state == :picking_corners && @cursor && !@points.empty?
                line << @points.first if @closed

                view.line_width    = 3
                view.drawing_color = NA_LINE_COLOR
                view.draw(GL_LINE_STRIP, line) if line.length >= 2
                @points.each { |point| na_draw_crosshair(view, point) }
                line.each_cons(2) { |a, b| na_draw_label(view, Geom.linear_combination(0.5, a, 0.5, b), "#{na_length_mm(a, b).round}mm") }
                na_draw_side_arrow(view) if @state == :picking_side && @cursor
            end

            def getExtents
                bounds = Geom::BoundingBox.new
                (@points + [@cursor]).compact.each { |point| bounds.add(point) }
                bounds
            end

# endregion -------------------------------------------------------------------

            private

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

            def na_up
                model = Sketchup.active_model
                model ? model.axes.zaxis : Z_AXIS
            end

            # A corner brought to the first corner's level: a path lies flat.
            def na_level_point(point)
                return point if @points.empty?
                up = na_up
                point.offset(up, -(point - @points.first).dot(up))
            end

            def na_length_mm(point_a, point_b)
                (point_b - point_a).length.to_f * NA_INCH_TO_MM
            end

            def na_near_first?(view, x, y)
                screen = view.screen_coords(@points.first)
                Math.hypot(screen.x - x, screen.y - y) <= NA_CLOSE_PIXELS
            end

            def na_end_corners(view)
                return unless @state == :picking_corners
                if @points.length < 2
                    UI.beep
                    return
                end
                @state = :picking_side
                na_update_status_text
                view.invalidate
            end

            def na_complete(side_point)
                return unless @dialog_host.respond_to?(@cb_complete)
                DebugTools.na_debug_measure("Run path measured: #{@points.length} corners#{@closed ? ', closed' : ''}")
                @dialog_host.public_send(@cb_complete, @points.dup, side_point, @closed)
            end

            def na_update_status_text
                Sketchup.status_text =
                    if @state == :picking_side
                        "#{@status_label}: click on #{@side_label} | Esc to cancel"
                    elsif @points.empty?
                        "#{@status_label}: click the first corner of the path, at floor level | Esc to cancel"
                    else
                        close = @points.length >= 3 ? ", or the first corner again to close the path" : ""
                        "#{@status_label}: click the next corner#{close} | Enter or double click when done (#{@points.length} so far) | Esc to cancel"
                    end
            end

            def na_draw_crosshair(view, point)
                up = na_up
                view.line_width    = 2
                view.drawing_color = NA_POINT_COLOR
                view.draw(GL_LINES, [point.offset(X_AXIS, -NA_CROSSHAIR_SIZE), point.offset(X_AXIS, NA_CROSSHAIR_SIZE),
                                     point.offset(Y_AXIS, -NA_CROSSHAIR_SIZE), point.offset(Y_AXIS, NA_CROSSHAIR_SIZE),
                                     point, point.offset(up, NA_CROSSHAIR_SIZE)])
            end

            # An arrow from the middle of the first leg towards the cursor's
            # side: which way the elements will face.
            def na_draw_side_arrow(view)
                a, b  = @points[0], @points[1]
                along = b - a
                return if along.length < 0.001
                up    = na_up
                left  = up.cross(along).normalize
                mid   = Geom.linear_combination(0.5, a, 0.5, b)
                side  = (@cursor - mid).dot(left) > 0 ? left : left.reverse
                view.line_width    = 3
                view.drawing_color = NA_POINT_COLOR
                view.draw(GL_LINES, [mid, mid.offset(side, NA_SIDE_ARROW)])
                na_draw_label(view, mid.offset(side, NA_SIDE_ARROW), "seen from this side")
            end

            def na_draw_label(view, point, text)
                screen = view.screen_coords(point)
                view.drawing_color = NA_TEXT_COLOR
                view.draw_text(Geom::Point3d.new(screen.x + 12, screen.y - 22, 0), text)
            end

# endregion -------------------------------------------------------------------

        end

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
