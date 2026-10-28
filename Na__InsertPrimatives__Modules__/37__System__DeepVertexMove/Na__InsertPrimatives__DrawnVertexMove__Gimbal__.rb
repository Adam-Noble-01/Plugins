# =============================================================================
# NA INSERT PRIMATIVES - DEEP VERTEX MOVE - GIMBAL
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnVertexMove__Gimbal__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : The three-arrow move gimbal: where it is on screen, which handle
#              the cursor is over, and the ray maths a drag is measured with
# CREATED    : 2026
#
# DESCRIPTION:
# - The same gimbal as the Point Cloud Viewer's Move tool, so a hand that knows
#   one knows the other: red, green and blue arrows 90 px long whatever the
#   zoom, a triangle head on each, amber for the arrow under the cursor or in
#   the hand, a white square at the centre, and a dashed guide along the axis
#   while a drag is running.
# - One addition: the centre square is a handle too. Dragging it moves the
#   vertices freely, which is what CTRL's vertex snap needs to put a corner
#   exactly on another one.
# - Everything here is drawn in screen space (draw2d), so the model can never
#   hide the gimbal, and every hit test is in pixels.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnGridSnap__'
require_relative '../05__PreviewGraphics/Na__InsertPrimatives__DrawnPreviewGraphics__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Gimbal Constants
    # -----------------------------------------------------------------------------

    NA_VM_AXIS_KEYS       = [:x, :y, :z].freeze
    NA_VM_GIMBAL_PX       = 90.0                                              # <-- Arrow length on screen, as the point cloud gimbal
    NA_VM_HEAD_PX         = 14.0
    NA_VM_HEAD_HALF_PX    = 6.0
    NA_VM_PICK_PX         = 10.0                                              # <-- How near an arrow the cursor must be to take it
    NA_VM_CENTRE_HALF_PX  = 5.0                                               # <-- Half the side of the free-move square
    NA_VM_CENTRE_PICK_PX  = 8.0

    NA_VM_AXIS_COLOURS    = {
        :x => Sketchup::Color.new(220,  40,  40),
        :y => Sketchup::Color.new( 30, 160,  60),
        :z => Sketchup::Color.new( 40,  90, 235)
    }.freeze
    NA_VM_AXIS_LABELS     = { :x => 'red', :y => 'green', :z => 'blue' }.freeze
    NA_VM_HOT_COLOUR      = Sketchup::Color.new(255, 196,   0)
    NA_VM_WHITE_COLOUR    = Sketchup::Color.new(255, 255, 255)
    NA_VM_DARK_COLOUR     = Sketchup::Color.new( 30,  30,  30)

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Screen Geometry and Hit Testing
    # -----------------------------------------------------------------------------

    # FUNCTION | The Gimbal Laid Out on Screen, or nil Behind the Camera
    # ------------------------------------------------------------
    # Returns { :o => [x, y], :arrows => [{ :key, :o, :tip, :end, :length }] }.
    # The arrow is a fixed number of pixels long, so its model length is
    # asked of the view at the origin on every frame.
    # ------------------------------------------------------------
    def self.Na__VertexMove__GimbalScreen(view, origin, axes)
        return nil unless origin && axes
        return nil unless Na__InsertPrimatives.Na__DrawnPreview__InFrontOfCamera?(view, origin)

        centre = view.screen_coords(origin)
        length = view.pixels_to_model(NA_VM_GIMBAL_PX, origin).to_f
        return nil unless length > 0.0

        arrows = NA_VM_AXIS_KEYS.each_with_index.map do |key, index|
            tip = view.screen_coords(Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(origin, axes[index], length))
            dx  = tip.x.to_f - centre.x.to_f
            dy  = tip.y.to_f - centre.y.to_f
            run = Math.hypot(dx, dy)
            head = run > 1e-6 ? [tip.x.to_f + (dx / run * NA_VM_HEAD_PX), tip.y.to_f + (dy / run * NA_VM_HEAD_PX)] : [tip.x.to_f, tip.y.to_f]

            { :key => key, :o => [centre.x.to_f, centre.y.to_f], :tip => [tip.x.to_f, tip.y.to_f], :end => head, :length => run }
        end

        { :o => [centre.x.to_f, centre.y.to_f], :arrows => arrows }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Which Handle Is Under the Cursor — :x, :y, :z, :free or nil
    # ------------------------------------------------------------
    # The centre square is asked first: every shaft starts inside it.
    # ------------------------------------------------------------
    def self.Na__VertexMove__GimbalHit(view, origin, axes, x, y)
        screen = Na__InsertPrimatives.Na__VertexMove__GimbalScreen(view, origin, axes)
        return nil unless screen

        centre = screen[:o]
        return :free if (x.to_f - centre[0]).abs <= NA_VM_CENTRE_PICK_PX && (y.to_f - centre[1]).abs <= NA_VM_CENTRE_PICK_PX

        best    = nil
        best_px = NA_VM_PICK_PX

        screen[:arrows].each do |arrow|
            gap = Na__InsertPrimatives.Na__VertexMove__SegmentGap(x.to_f, y.to_f, arrow[:o], arrow[:end])
            next unless gap < best_px

            best    = arrow[:key]
            best_px = gap
        end

        best
    end
    # ---------------------------------------------------------------

    # FUNCTION | Pixel Distance From a Point to a Screen Segment
    # ------------------------------------------------------------
    def self.Na__VertexMove__SegmentGap(x, y, a, b)
        dx        = b[0] - a[0]
        dy        = b[1] - a[1]
        length_sq = (dx * dx) + (dy * dy)
        t         = length_sq < 1e-9 ? 0.0 : (((x - a[0]) * dx) + ((y - a[1]) * dy)) / length_sq
        t         = 0.0 if t < 0.0
        t         = 1.0 if t > 1.0

        Math.hypot(x - (a[0] + (t * dx)), y - (a[1] + (t * dy)))
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Drag Maths — Everything in World Space
    # -----------------------------------------------------------------------------

    # FUNCTION | Where Along an Axis Line the Cursor Is
    # ------------------------------------------------------------
    # The parameter s on origin + s * axis closest to the pick ray, so a
    # grabbed arrow follows the cursor from any view. nil when looking
    # straight down the axis, or when the closest point is behind the eye.
    # `axis` is a unit vector; s is in inches.
    # ------------------------------------------------------------
    def self.Na__VertexMove__AxisParam(view, origin, axis, x, y)
        ray       = view.pickray(x, y)
        start     = ray[0]
        direction = ray[1]
        w0        = origin - start

        b     = axis.dot(direction).to_f
        c     = direction.dot(direction).to_f
        d     = axis.dot(w0).to_f
        e     = direction.dot(w0).to_f
        denom = c - (b * b)
        return nil if denom.abs < 1e-9

        along_ray = (e - (b * d)) / denom
        return nil if along_ray <= 0.0 && view.camera.perspective?

        ((b * e) - (c * d)) / denom
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Where the Pick Ray Meets a Plane, in Front of the Eye, or nil
    # ------------------------------------------------------------
    def self.Na__VertexMove__PlaneHit(view, origin, normal, x, y)
        ray = view.pickray(x, y)
        hit = Geom.intersect_line_plane(ray, [origin, normal])
        return nil unless hit
        return nil unless (hit - ray[0]).dot(ray[1]) > 0.0

        hit
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Frame Axis That Looks Most Directly at the Camera
    # ------------------------------------------------------------
    # A free drag slides on the frame plane square to it: plan in a plan
    # view, the elevation in an elevation, and the plan again from a
    # typical three-quarter view looking down.
    # ------------------------------------------------------------
    def self.Na__VertexMove__FacingIndex(view, axes)
        sight = view.camera.direction
        best  = 2
        most  = -1.0

        axes.each_with_index do |axis, index|
            facing = axis.dot(sight).to_f.abs
            next unless facing > most

            most = facing
            best = index
        end

        best
    rescue StandardError
        2
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Drawing
    # -----------------------------------------------------------------------------

    # FUNCTION | A Filled Square With an Outline, in Screen Space
    # ------------------------------------------------------------
    def self.Na__VertexMove__Square2d(view, centre, half, fill, outline)
        corners = [[-half, -half], [half, -half], [half, half], [-half, half]].map do |dx, dy|
            Geom::Point3d.new(centre[0] + dx, centre[1] + dy, 0)
        end

        view.line_stipple  = ''
        view.drawing_color = fill
        view.draw2d(GL_QUADS, corners)
        view.line_width    = 1
        view.drawing_color = outline
        view.draw2d(GL_LINE_LOOP, corners)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw the Gimbal, Hot Handle in Amber
    # ------------------------------------------------------------
    def self.Na__VertexMove__DrawGimbal(view, origin, axes, hot)
        screen = Na__InsertPrimatives.Na__VertexMove__GimbalScreen(view, origin, axes)
        return false unless screen

        screen[:arrows].each do |arrow|
            key = arrow[:key]
            o   = arrow[:o]
            tip = arrow[:tip]

            view.line_stipple  = ''
            view.line_width    = key == hot ? 5 : 3
            view.drawing_color = key == hot ? NA_VM_HOT_COLOUR : NA_VM_AXIS_COLOURS[key]
            view.draw2d(GL_LINES, [Geom::Point3d.new(o[0], o[1], 0), Geom::Point3d.new(tip[0], tip[1], 0)])

            next unless arrow[:length] > 4.0                                  # <-- Seen end-on: no direction left to draw a head along

            ux = (tip[0] - o[0]) / arrow[:length]
            uy = (tip[1] - o[1]) / arrow[:length]
            view.draw2d(GL_TRIANGLES, [
                Geom::Point3d.new(arrow[:end][0], arrow[:end][1], 0),
                Geom::Point3d.new(tip[0] - (uy * NA_VM_HEAD_HALF_PX), tip[1] + (ux * NA_VM_HEAD_HALF_PX), 0),
                Geom::Point3d.new(tip[0] + (uy * NA_VM_HEAD_HALF_PX), tip[1] - (ux * NA_VM_HEAD_HALF_PX), 0)
            ])
        end

        free = hot == :free
        Na__InsertPrimatives.Na__VertexMove__Square2d(
            view, screen[:o], free ? NA_VM_CENTRE_HALF_PX + 2.0 : NA_VM_CENTRE_HALF_PX,
            free ? NA_VM_HOT_COLOUR : NA_VM_WHITE_COLOUR, NA_VM_DARK_COLOUR
        )
        view.line_width = 1
        true
    rescue StandardError
        false                                                                 # <-- Never let a decoration kill the whole draw pass
    end
    # ---------------------------------------------------------------

    # FUNCTION | Dashed Guide Along the Drag Axis, Hollow Mark at the Start
    # ------------------------------------------------------------
    # The point cloud gimbal's guide: it makes the size of the move readable.
    # The span is taken from the viewport so it crosses the screen at any zoom.
    # ------------------------------------------------------------
    def self.Na__VertexMove__DrawAxisGuide(view, start, axis, key)
        return false unless start && axis

        span =
            begin
                pixels = view.vpwidth > view.vpheight ? view.vpwidth : view.vpheight
                view.pixels_to_model(pixels, start).to_f * 1.2
            rescue StandardError
                0.0
            end
        span = NA_DRAWN_AXIS_RAY_FALLBACK.to_f unless span > 0.0

        view.line_stipple  = '-'
        view.line_width    = 1
        view.drawing_color = NA_VM_AXIS_COLOURS[key] || NA_VM_DARK_COLOUR
        view.draw(GL_LINES, [
            Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(start, axis, -span),
            Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(start, axis,  span)
        ])
        view.line_stipple = ''

        Na__InsertPrimatives.Na__VertexMove__DrawStartMark(view, start)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Hollow Square Where a Drag Started
    # ------------------------------------------------------------
    def self.Na__VertexMove__DrawStartMark(view, start)
        return false unless Na__InsertPrimatives.Na__DrawnPreview__InFrontOfCamera?(view, start)

        screen  = view.screen_coords(start)
        corners = [[-4, -4], [4, -4], [4, 4], [-4, 4]].map do |dx, dy|
            Geom::Point3d.new(screen.x.to_f + dx, screen.y.to_f + dy, 0)
        end

        view.line_stipple  = ''
        view.line_width    = 1
        view.drawing_color = NA_VM_DARK_COLOUR
        view.draw2d(GL_LINE_LOOP, corners)
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP VERTEX MOVE GIMBAL MODULE
# =============================================================================
