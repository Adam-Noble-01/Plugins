# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - RUN MEASURE TOOL
# =============================================================================
#
# FILE       : Na__AssemblyStudio__MeasurementTools__RunMeasureTool__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__MeasurementTools
# CLASS      : Na__RunMeasureTool
# AUTHOR     : Noble Architecture
# PURPOSE    : SketchUp Tool that measures a run of fitted units along a wall:
#              click the start of the run, the end of the run, then the room
#              side the units face. Hands the host a run frame (origin, axes,
#              length) that cabinets are then inserted along, one after another.
# CREATED    : 29-Oct-2026
#
# THE FRAME IT RETURNS (world, inches)
# - origin : the left end of the run as seen from the room, at the height of
#            the first click (pick it on the floor line).
# - xaxis  : along the wall, left to right seen from the room.
# - yaxis  : into the wall; zaxis: the drawing axes' up. Right-handed, so a
#            cabinet's unit frame (front facing -Y) faces into the room.
# - Picking right to left, or from the far side, is fine: the third click
#   decides which side is the room and the frame is turned to suit.
#
# COORDINATES
# - InputPoint positions are world in any context, and so is everything this
#   tool draws and returns (see the Coordinate Rule). The host passes the
#   frame to add_instance unchanged.
#
# KEYS
# - Esc cancels. No single-letter keys (SketchUp's shortcuts take them first).
#
# NAMING CONVENTION:
# - Class Na__RunMeasureTool; instance helpers prefixed na_*
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
    module Na__MeasurementTools

        class Na__RunMeasureTool

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

            NA_INCH_TO_MM        = 25.4
            NA_MIN_RUN_MM        = 50.0
            NA_PREVIEW_DEPTH     = 560.mm                                        # <-- Strip drawn on the room side (a base unit's depth)
            NA_CROSSHAIR_SIZE    = 60.mm
            NA_LINE_COLOR        = Sketchup::Color.new(0, 120, 255)
            NA_STRIP_FILL_COLOR  = Sketchup::Color.new(0, 120, 255, 70)
            NA_POINT_A_COLOR     = Sketchup::Color.new(0, 180, 0)
            NA_TEXT_COLOR        = Sketchup::Color.new(20, 20, 20)

            DEFAULT_CALLBACKS = {
                :complete     => :na_send_cabinet_run_to_dialog,
                :cancel       => :na_send_cabinet_measure_cancelled_to_dialog,
                :status_label => 'Measure Run'
            }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool API - Life Cycle
# -----------------------------------------------------------------------------

            # FUNCTION | Attach the Host and Start at Point A
            # ------------------------------------------------------------
            def initialize(dialog_host, callbacks: {})
                @dialog_host  = dialog_host
                merged        = DEFAULT_CALLBACKS.merge(callbacks)
                @cb_complete  = merged[:complete]
                @cb_cancel    = merged[:cancel]
                @status_label = merged[:status_label]
                @ip           = Sketchup::InputPoint.new
                @ip_start     = Sketchup::InputPoint.new
                @point_a      = nil
                @point_b      = nil
                @cursor       = nil
                @state        = :picking_a
            end
            # ---------------------------------------------------------------

            def activate
                @state = :picking_a
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
# REGION | SketchUp Tool API - Mouse and Cancel
# -----------------------------------------------------------------------------

            def onMouseMove(_flags, x, y, view)
                if @state == :picking_b
                    @ip.pick(view, x, y, @ip_start)                              # <-- Infer from Point A (on-axis, parallel to edges)
                else
                    @ip.pick(view, x, y)
                end
                return unless @ip.valid?
                @cursor = @ip.position
                view.tooltip = @ip.tooltip if @ip.respond_to?(:tooltip)
                na_update_status_text
                view.invalidate
            end

            def onLButtonDown(_flags, x, y, view)
                onMouseMove(_flags, x, y, view)
                return unless @ip.valid?
                clicked = @ip.position

                case @state
                when :picking_a
                    @point_a = clicked
                    @ip_start.copy!(@ip)
                    @state   = :picking_b
                when :picking_b
                    if na_run_length_mm(@point_a, clicked) < NA_MIN_RUN_MM
                        UI.beep
                        return
                    end
                    @point_b = clicked
                    @state   = :picking_side
                when :picking_side
                    na_complete(clicked)
                    Sketchup.active_model.select_tool(nil)
                    return
                end
                na_update_status_text
                view.invalidate
            end

            def onCancel(_reason, view)
                DebugTools.na_debug_measure("Run measure cancelled")
                @dialog_host.public_send(@cb_cancel) if @dialog_host.respond_to?(@cb_cancel)
                view.invalidate
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool API - Drawing
# -----------------------------------------------------------------------------

            def draw(view)
                @ip.draw(view) if @ip.valid? && @ip.display?
                case @state
                when :picking_a
                    na_draw_crosshair(view, @cursor, NA_LINE_COLOR) if @cursor
                when :picking_b
                    return unless @point_a && @cursor
                    na_draw_crosshair(view, @point_a, NA_POINT_A_COLOR)
                    na_draw_run_line(view, @point_a, na_level_point(@cursor))
                when :picking_side
                    return unless @point_a && @point_b
                    frame = Na__RunMeasureTool.na_frame(@point_a, @point_b, @cursor || @point_b, na_up)
                    na_draw_strip(view, frame) if frame
                    na_draw_crosshair(view, @point_a, NA_POINT_A_COLOR)
                end
            end

            def getExtents
                bounds = Geom::BoundingBox.new
                [@point_a, @point_b, @cursor].compact.each { |point| bounds.add(point) }
                bounds
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Run Frame (Pure Geometry, World)
# -----------------------------------------------------------------------------

            # FUNCTION | Build the Run Frame From the Three Picks
            # ------------------------------------------------------------
            # @param point_a [Geom::Point3d] first pick (sets the floor level)
            # @param point_b [Geom::Point3d] second pick (the other end)
            # @param side    [Geom::Point3d] third pick, on the room side
            # @param up      [Geom::Vector3d] the drawing axes' Z
            # @return [Hash, nil] { :origin, :xaxis, :yaxis, :zaxis, :length_mm }
            def self.na_frame(point_a, point_b, side, up)
                along = point_b - point_a
                along = along - Geom::Vector3d.new(up.x * along.dot(up), up.y * along.dot(up), up.z * along.dot(up))
                return nil if along.length < 0.001

                length = along.length
                xaxis  = along.normalize
                yaxis  = up.cross(xaxis).normalize                                # <-- z x x: into the wall when the room is on -y
                origin = point_a

                if (side - point_a).dot(yaxis) > 0                                # <-- Room on +y: turn round and start from B
                    origin = point_a.offset(xaxis, length)
                    xaxis  = xaxis.reverse
                    yaxis  = yaxis.reverse
                end
                { :origin => origin, :xaxis => xaxis, :yaxis => yaxis, :zaxis => up.normalize,
                  :length_mm => length.to_f * NA_INCH_TO_MM }
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

            private

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

            def na_up
                model = Sketchup.active_model
                model ? model.axes.zaxis : Z_AXIS
            end

            # Point B brought down (or up) to Point A's level.
            def na_level_point(point)
                return point unless @point_a
                up = na_up
                point.offset(up, -(point - @point_a).dot(up))
            end

            def na_run_length_mm(point_a, point_b)
                up    = na_up
                delta = point_b - point_a
                flat  = delta - Geom::Vector3d.new(up.x * delta.dot(up), up.y * delta.dot(up), up.z * delta.dot(up))
                flat.length.to_f * NA_INCH_TO_MM
            end

            def na_complete(side_point)
                frame = Na__RunMeasureTool.na_frame(@point_a, @point_b, side_point, na_up)
                return unless frame && @dialog_host.respond_to?(@cb_complete)
                DebugTools.na_debug_measure("Run measured: #{frame[:length_mm].round}mm")
                @dialog_host.public_send(@cb_complete, frame)
            end

            def na_update_status_text
                Sketchup.status_text =
                    case @state
                    when :picking_a
                        "#{@status_label}: click the start of the run, on the floor line by the wall | Esc to cancel"
                    when :picking_b
                        length = (@point_a && @cursor) ? " | #{na_run_length_mm(@point_a, @cursor).round}mm" : ""
                        "#{@status_label}: click the end of the run#{length} | Esc to cancel"
                    else
                        "#{@status_label}: click on the room side the units face | Esc to cancel"
                    end
            end

            def na_draw_crosshair(view, point, color)
                up = na_up
                view.line_width    = 2
                view.drawing_color = color
                view.draw(GL_LINES, [point.offset(X_AXIS, -NA_CROSSHAIR_SIZE), point.offset(X_AXIS, NA_CROSSHAIR_SIZE),
                                     point.offset(Y_AXIS, -NA_CROSSHAIR_SIZE), point.offset(Y_AXIS, NA_CROSSHAIR_SIZE),
                                     point, point.offset(up, NA_CROSSHAIR_SIZE)])
            end

            def na_draw_run_line(view, from, to)
                view.line_width    = 3
                view.drawing_color = NA_LINE_COLOR
                view.draw(GL_LINES, [from, to])
                na_draw_label(view, Geom.linear_combination(0.5, from, 0.5, to), "#{na_run_length_mm(from, to).round}mm")
            end

            # The run, with a strip one base unit deep on the room side and an
            # arrow showing which way the units will face.
            def na_draw_strip(view, frame)
                origin = frame[:origin]
                along  = frame[:xaxis]
                out    = frame[:yaxis].reverse
                length = frame[:length_mm] / NA_INCH_TO_MM
                p0 = origin
                p1 = origin.offset(along, length)
                p2 = p1.offset(out, NA_PREVIEW_DEPTH)
                p3 = p0.offset(out, NA_PREVIEW_DEPTH)
                view.drawing_color = NA_STRIP_FILL_COLOR
                view.draw(GL_QUADS, [p0, p1, p2, p3])
                view.line_width    = 2
                view.drawing_color = NA_LINE_COLOR
                view.draw(GL_LINE_LOOP, [p0, p1, p2, p3])
                mid  = Geom.linear_combination(0.5, p0, 0.5, p1)
                tip  = mid.offset(out, NA_PREVIEW_DEPTH * 0.6)
                view.draw(GL_LINES, [mid, tip])
                na_draw_label(view, mid, "#{frame[:length_mm].round}mm run - units face this way")
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
