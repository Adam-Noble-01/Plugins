# =============================================================================
# NA INSERT PRIMATIVES - DEEP SCALE PREVIEW GRAPHICS
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnScale__Preview__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Stateless drawing for Deep Scale — grips, dimensions you can
#              click, the handle bar, stretch planes and the live ghost
# CREATED    : 2026
#
# DESCRIPTION:
# - Built on the plugin's established preview system (DrawnPreviewGraphics):
#   the same palette and the same rules. Blue is the object being acted on,
#   amber is what it is about to become, green is a handle, orange is a value
#   that is pinned or about to be typed, and the axis colours are SketchUp's.
# - Everything here is drawn in SCREEN space with View#draw2d, after the
#   model, the way the subtract cutter and every label already are. A grip,
#   a dimension or a plane hidden by the object it belongs to is no use, and
#   the ghost of a stretch is mostly INSIDE the object until it is placed.
#   Points are projected through Na__DrawnPreview__ScreenPoints, which
#   refuses a point behind a perspective camera rather than mirroring it.
# - Every function is stateless and takes everything it needs as arguments.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../05__PreviewGraphics/Na__InsertPrimatives__DrawnPreviewGraphics__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Deep Scale Palette and Metrics
    # -----------------------------------------------------------------------------

    NA_SCALE_BOX_COLOR          = NA_DRAWN_TARGET_BORDER_COLOR                # <-- The object you are about to act on
    NA_SCALE_OLD_BOX_COLOR      = Sketchup::Color.new(  0, 110, 235, 120)     # <-- Where it was, faded, while the drag runs
    NA_SCALE_NEW_FILL_COLOR     = Sketchup::Color.new(255, 150,  30,  24)     # <-- Thin: six faces blend over each other on top
    NA_SCALE_NEW_BORDER_COLOR   = NA_DRAWN_VOLUME_BORDER_COLOR
    NA_SCALE_GHOST_COLOR        = Sketchup::Color.new(226, 118,   0, 200)

    NA_SCALE_GRIP_COLOR         = Sketchup::Color.new(  0, 175,  70)
    NA_SCALE_GRIP_BACK_COLOR    = Sketchup::Color.new(  0, 140,  55, 170)
    NA_SCALE_GRIP_EDGE_COLOR    = Sketchup::Color.new(255, 255, 255)
    NA_SCALE_GRIP_HOT_COLOR     = NA_DRAWN_TEXT_LOCKED_COLOR
    NA_SCALE_GRIP_PIXELS        = 9.0
    NA_SCALE_GRIP_BACK_PIXELS   = 7.0
    NA_SCALE_GRIP_HOT_PIXELS    = 13.0

    NA_SCALE_PILL_FILL_COLOR    = Sketchup::Color.new(255, 255, 255, 235)
    NA_SCALE_PILL_HOVER_COLOR   = Sketchup::Color.new(231, 240, 255, 245)
    NA_SCALE_PILL_ACTIVE_COLOR  = Sketchup::Color.new(255, 236, 214, 245)
    NA_SCALE_PILL_PAD_X         = 7.0
    NA_SCALE_PILL_PAD_Y         = 3.0
    NA_SCALE_ARROW_PIXELS       = 8.0
    NA_SCALE_MIN_EDGE_PIXELS    = 4.0                                         # <-- Shorter on screen than this, an axis is seen end-on (an elevation's depth)
    NA_SCALE_SCREEN_REACH       = 100_000.0                                   # <-- Pixels; anything projected further out is not drawn
    NA_SCALE_DIM_END_ON         = 0.94                                        # <-- |axis . sight| past this, the eye looks along the axis: no dimension, no stand-off that way

    NA_SCALE_PLANE_FILL_ALPHA   = 55
    NA_SCALE_PLANE_HOT_ALPHA    = 95
    NA_SCALE_PLANE_EDGE_ALPHA   = 225
    NA_SCALE_HANDLE_PIXELS      = 10.0
    NA_SCALE_HANDLE_HOT_PIXELS  = 14.0

    # The handle bar wears the right-click popup's own colours, so the two
    # read as one control: blue is the choice in force, green a switch that
    # is on, white everything else.
    NA_SCALE_BAR_ORIGIN         = [14, 14].freeze
    NA_SCALE_BAR_HEIGHT         = 22
    NA_SCALE_BAR_GAP            = 4
    NA_SCALE_BAR_GROUP_GAP      = 12
    NA_SCALE_BAR_TEXT_SIZE      = 9
    NA_SCALE_BAR_PANEL_COLOR    = Sketchup::Color.new(243, 243, 243, 215)
    NA_SCALE_BAR_PANEL_EDGE     = Sketchup::Color.new(190, 190, 190, 230)
    NA_SCALE_BAR_STYLES         = {
        :plain => [Sketchup::Color.new(255, 255, 255), Sketchup::Color.new(187, 187, 187), Sketchup::Color.new( 34,  34,  34)],
        :hover => [Sketchup::Color.new(231, 240, 255), Sketchup::Color.new(122, 167, 224), Sketchup::Color.new( 34,  34,  34)],
        :mode  => [Sketchup::Color.new(220, 233, 251), Sketchup::Color.new( 75, 131, 200), Sketchup::Color.new( 20,  60, 120)],
        :on    => [Sketchup::Color.new(227, 242, 229), Sketchup::Color.new(106, 168, 111), Sketchup::Color.new( 29,  94,  38)]
    }.freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Screen Helpers
    # -----------------------------------------------------------------------------

    # FUNCTION | One World Point on Screen, or nil Behind the Camera
    # ------------------------------------------------------------
    def self.Na__ScalePreview__Screen(view, point)
        projected = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, [point])
        projected && Na__InsertPrimatives.Na__ScalePreview__Sane?(projected) ? projected.first : nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Are Screen Coordinates Ones Worth Handing to draw2d?
    # ------------------------------------------------------------
    # A point a hair in front of the eye projects thousands of screens away,
    # and a bad number projects to NaN. Neither is drawn: draw2d and
    # draw_text are only ever given finite positions within a sane reach of
    # the viewport (5.2.6).
    # ------------------------------------------------------------
    def self.Na__ScalePreview__Sane?(points)
        points.all? do |point|
            [point.x, point.y].all? { |value| value.to_f.finite? && value.to_f.abs < NA_SCALE_SCREEN_REACH }
        end
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Label Pinned to a World Point, Only Where the Point Is Drawable
    # ------------------------------------------------------------
    def self.Na__ScalePreview__DrawWorldLabel(view, point, lines, *rest)
        return false unless Na__InsertPrimatives.Na__ScalePreview__Screen(view, point)

        Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, point, lines, *rest)
    end
    # ---------------------------------------------------------------

    # FUNCTION | An Axis Colour, Optionally See-Through
    # ------------------------------------------------------------
    def self.Na__ScalePreview__AxisColor(axis, alpha = nil)
        base = Na__InsertPrimatives.Na__DrawnPreview__AxisColor(axis)
        return base unless alpha

        Sketchup::Color.new(base.red, base.green, base.blue, alpha)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is a Screen Position Inside a Rect [x0, y0, x1, y1]?
    # ------------------------------------------------------------
    def self.Na__ScalePreview__InRect?(rect, x, y)
        return false unless rect

        x >= rect[0] && x <= rect[2] && y >= rect[1] && y <= rect[3]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Distance in Pixels From a Screen Position to a Screen Segment
    # ------------------------------------------------------------
    def self.Na__ScalePreview__SegmentDistance(x, y, from, to)
        dx     = to.x - from.x
        dy     = to.y - from.y
        length = (dx * dx) + (dy * dy)
        t      = length > 0.0 ? (((x - from.x) * dx) + ((y - from.y) * dy)) / length : 0.0
        t      = 0.0 if t < 0.0
        t      = 1.0 if t > 1.0

        px = from.x + (t * dx) - x
        py = from.y + (t * dy) - y
        Math.sqrt((px * px) + (py * py))
    end
    # ---------------------------------------------------------------

    # FUNCTION | Width and Height of a Line of Text on Screen
    # ------------------------------------------------------------
    # View#text_bounds when SketchUp has it (2020+), because a click target
    # sized from a guess is a click target that misses. The character
    # estimate is the fallback, at the same ratio the shared labels use.
    # ------------------------------------------------------------
    def self.Na__ScalePreview__TextSize(view, text, size, bold = true)
        if view.respond_to?(:text_bounds)
            bounds = view.text_bounds(Geom::Point3d.new(0, 0, 0), text.to_s, { :size => size, :bold => bold })
            return [bounds.width.to_f, bounds.height.to_f] if bounds && bounds.width.to_f > 0.0
        end

        [text.to_s.length * size * (bold ? 0.62 : 0.56), size * 1.35]
    rescue StandardError
        [text.to_s.length * size * 0.62, size * 1.35]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw One Line of Text Centred on a Screen Position
    # ------------------------------------------------------------
    def self.Na__ScalePreview__DrawText(view, x, y, text, size, color, bold = true)
        return nil unless Na__InsertPrimatives.Na__ScalePreview__Sane?([Geom::Point3d.new(x.to_f, y.to_f, 0)])

        view.draw_text(
            Geom::Point3d.new(x, y, 0), text.to_s,
            {
                :size           => size,
                :bold           => bold,
                :color          => color,
                :align          => TextAlignCenter,
                :vertical_align => TextVerticalAlignCenter
            }
        )
    rescue StandardError
        nil                                                                   # <-- Never let a label kill the whole draw pass
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Shapes on Screen
    # -----------------------------------------------------------------------------

    # FUNCTION | A Filled, Bordered Screen Rect [x0, y0, x1, y1]
    # ------------------------------------------------------------
    def self.Na__ScalePreview__DrawRect(view, rect, fill, border, width = 1)
        corners = [
            Geom::Point3d.new(rect[0], rect[1], 0),
            Geom::Point3d.new(rect[2], rect[1], 0),
            Geom::Point3d.new(rect[2], rect[3], 0),
            Geom::Point3d.new(rect[0], rect[3], 0)
        ]
        return unless Na__InsertPrimatives.Na__ScalePreview__Sane?(corners)

        if fill
            view.drawing_color = fill
            view.draw2d(GL_QUADS, corners)
        end

        return unless border

        view.line_stipple  = ''
        view.line_width    = width
        view.drawing_color = border
        view.draw2d(GL_LINE_LOOP, corners)
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Square Grip Centred on a Screen Point
    # hollow draws the border only, for a grip on the far side of the box.
    # ------------------------------------------------------------
    def self.Na__ScalePreview__DrawGrip(view, centre, pixels, fill, hollow = false)
        half = pixels * 0.5
        rect = [centre.x - half, centre.y - half, centre.x + half, centre.y + half]

        if hollow
            Na__InsertPrimatives.Na__ScalePreview__DrawRect(view, rect, nil, fill, 2)
        else
            Na__InsertPrimatives.Na__ScalePreview__DrawRect(view, rect, fill, NA_SCALE_GRIP_EDGE_COLOR, 1)
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Diamond Centred on a Screen Point — a Plane's Handle
    # ------------------------------------------------------------
    def self.Na__ScalePreview__DrawDiamond(view, centre, pixels, fill)
        half    = pixels * 0.5
        corners = [
            Geom::Point3d.new(centre.x,        centre.y - half, 0),
            Geom::Point3d.new(centre.x + half, centre.y,        0),
            Geom::Point3d.new(centre.x,        centre.y + half, 0),
            Geom::Point3d.new(centre.x - half, centre.y,        0)
        ]
        return unless Na__InsertPrimatives.Na__ScalePreview__Sane?(corners)

        view.drawing_color = fill
        view.draw2d(GL_QUADS, corners)

        view.line_stipple  = ''
        view.line_width    = 1
        view.drawing_color = NA_SCALE_GRIP_EDGE_COLOR
        view.draw2d(GL_LINE_LOOP, corners)
    end
    # ---------------------------------------------------------------

    # FUNCTION | World Segments Drawn on Top of the Model
    # pairs is a flat list: from, to, from, to … Returns false when it could
    # not be projected honestly, so nothing half-drawn is left on screen.
    # ------------------------------------------------------------
    def self.Na__ScalePreview__DrawSegmentsOnTop(view, pairs, color, width = 1, stipple = '')
        projected = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, pairs)
        return false unless projected && Na__InsertPrimatives.Na__ScalePreview__Sane?(projected)

        view.line_stipple  = stipple
        view.line_width    = width
        view.drawing_color = color
        view.draw2d(GL_LINES, projected)
        view.line_stipple  = ''
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Twelve Edges of a Box, on Top
    # ------------------------------------------------------------
    def self.Na__ScalePreview__DrawBoxOutline(view, edges, color, width = 2, stipple = '')
        Na__InsertPrimatives.Na__ScalePreview__DrawSegmentsOnTop(view, edges.flatten, color, width, stipple)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Ghost — Every Edge of the Object Where the Field Puts It
    # ------------------------------------------------------------
    # world_points are the ghost's points already mapped and placed;
    # segments are index pairs into them. One draw2d call for the lot.
    # ------------------------------------------------------------
    def self.Na__ScalePreview__DrawGhost(view, world_points, segments, color = NA_SCALE_GHOST_COLOR)
        return false if world_points.nil? || world_points.empty? || segments.nil? || segments.empty?

        projected = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, world_points)
        return false unless projected && Na__InsertPrimatives.Na__ScalePreview__Sane?(projected)

        view.line_stipple  = ''
        view.line_width    = 1
        view.drawing_color = color
        view.draw2d(GL_LINES, segments.map { |index| projected[index] })
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Stretch Planes on Screen
    # -----------------------------------------------------------------------------

    # FUNCTION | One Stretch Plane, See-Through, Over Everything
    # ------------------------------------------------------------
    def self.Na__ScalePreview__DrawPlane(view, quad, axis, hot = false)
        fill   = Na__InsertPrimatives.Na__ScalePreview__AxisColor(axis, hot ? NA_SCALE_PLANE_HOT_ALPHA : NA_SCALE_PLANE_FILL_ALPHA)
        border = Na__InsertPrimatives.Na__ScalePreview__AxisColor(axis, NA_SCALE_PLANE_EDGE_ALPHA)

        drawn = Na__InsertPrimatives.Na__DrawnPreview__DrawFilledQuadOnTop(view, quad, fill, border)
        Na__InsertPrimatives.Na__DrawnPreview__DrawFilledQuad(view, quad, fill, border) unless drawn
    end
    # ---------------------------------------------------------------

    # FUNCTION | An Axis's Centre Line — Where a Click Drops a Plane
    # Two pixels dashed, so it reads as something to click rather than a
    # construction line; solid and heavier under the cursor.
    # ------------------------------------------------------------
    def self.Na__ScalePreview__DrawCentreLine(view, from, to, axis, hot = false)
        Na__InsertPrimatives.Na__ScalePreview__DrawSegmentsOnTop(
            view, [from, to],
            Na__InsertPrimatives.Na__ScalePreview__AxisColor(axis, hot ? 255 : 210),
            hot ? 4 : 2,
            hot ? '' : '-'
        )
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Dimensions You Can Click
    # -----------------------------------------------------------------------------

    # FUNCTION | Where One Axis's Dimension Goes — Flat in One of the Box's Own Planes
    # ------------------------------------------------------------
    # 5.2.9: a dimension is built in 3D, the way a drawn SketchUp dimension
    # is. It runs along one box edge and stands off it along ANOTHER of the
    # object's own axes, so the dimension line, its extension lines and its
    # arrows all lie in one face plane of the box and foreshorten with it.
    # Until 5.2.6 it stood off at right angles on the screen, which tied it
    # to the camera rather than to the object. Which edge, and which way off,
    # is Na__ScalePreview__DimensionPlan.
    #
    # The stand-off is chosen so it reads offset_px on screen at that depth,
    # whatever the zoom.
    #
    # Returns nil when the axis is seen end-on or cannot be projected;
    # otherwise the edge ends (s0, s1), the dimension line ends (e0, e1), the
    # line's unit direction on screen (dir), the stand-off's direction on
    # screen at each end (o0, o1) and on the whole (out), and the middle.
    # ------------------------------------------------------------
    def self.Na__ScalePreview__DimensionLayout(view, frame, mins, maxs, axis, offset_px)
        n    = NA_SCALE_AXIS_INDEX[axis]
        plan = Na__InsertPrimatives.Na__ScalePreview__DimensionPlan(view, frame, mins, maxs, n)
        return nil unless plan

        k      = plan[:k]
        values = [0.0, 0.0, 0.0]
        plan[:ends].each { |m, value| values[m] = value }

        values[n] = mins[n]
        world0    = Geom::Point3d.new(values[0], values[1], values[2]).transform(frame[:world])
        values[n] = maxs[n]
        world1    = Geom::Point3d.new(values[0], values[1], values[2]).transform(frame[:world])

        away = frame[:dirs][k].clone
        away.length = 1.0
        away.reverse! if plan[:sign] < 0
        reach = Na__InsertPrimatives.Na__ScalePreview__StandOff(view, world0, world1, away, offset_px)
        return nil unless reach

        shift  = Geom::Vector3d.new(away.x * reach, away.y * reach, away.z * reach)
        screen = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, [world0, world1, world0.offset(shift), world1.offset(shift)])
        return nil unless screen && Na__InsertPrimatives.Na__ScalePreview__Sane?(screen)

        s0, s1, e0, e1 = screen
        along = Na__InsertPrimatives.Na__ScalePreview__Unit(e1.x - e0.x, e1.y - e0.y)
        return nil unless along && Math.hypot(e1.x - e0.x, e1.y - e0.y) >= NA_SCALE_MIN_EDGE_PIXELS

        o0  = Na__InsertPrimatives.Na__ScalePreview__Unit(e0.x - s0.x, e0.y - s0.y)
        o1  = Na__InsertPrimatives.Na__ScalePreview__Unit(e1.x - s1.x, e1.y - s1.y)
        out = Na__InsertPrimatives.Na__ScalePreview__Unit((e0.x - s0.x) + (e1.x - s1.x), (e0.y - s0.y) + (e1.y - s1.y))
        return nil unless o0 && o1 && out

        {
            :axis  => axis,
            :s0    => s0,
            :s1    => s1,
            :e0    => e0,
            :e1    => e1,
            :dir   => along,
            :out   => out,
            :o0    => o0,
            :o1    => o1,
            :mid   => Geom::Point3d.new((e0.x + e1.x) * 0.5, (e0.y + e1.y) * 0.5, 0),
            :plane => [n, k]
        }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Which Edge a Dimension Runs Along, and Which Way It Stands Off
    # ------------------------------------------------------------
    # The convention of a hand-drawn 3D view, with "up" the object's axis
    # nearest the model's blue:
    #   a level axis   along the bottom edge on the side facing the camera,
    #                  standing off level, towards the camera: in the plane
    #                  the object stands on
    #   the up axis    up the vertical edge at the left of the outline,
    #                  standing off level towards the camera, along whichever
    #                  side faces it most
    # A stand-off that would point straight at the eye (an elevation, where
    # the camera looks square at a face) cannot be seen, so it turns: a level
    # axis's dimension drops below the bottom edge, the up axis's goes out to
    # the left. And it always stands OUTSIDE the outline: if the way it
    # stands off would carry it into the object on screen, it moves to the
    # opposite edge and stands off the other way.
    #
    # Returns { :ends => { axis index => local value }, :k => the stand-off
    # axis, :sign => +1 or -1 } or nil when the axis itself is end-on.
    # ------------------------------------------------------------
    def self.Na__ScalePreview__DimensionPlan(view, frame, mins, maxs, n)
        dirs  = frame[:dirs]
        sight = Na__InsertPrimatives.Na__ScalePreview__SightLine(view, frame, mins, maxs)
        return nil unless sight
        return nil if dirs[n].dot(sight).abs > NA_SCALE_DIM_END_ON

        up     = (0..2).max_by { |m| dirs[m].z.abs }
        bottom = dirs[up].z >= 0.0 ? mins[up] : maxs[up]
        level  = (0..2).reject { |m| m == up }

        if n != up
            side = level.find { |m| m != n }
            near = Na__InsertPrimatives.Na__ScalePreview__FacingEnd(frame, mins, maxs, side, sight) ||
                   Na__InsertPrimatives.Na__ScalePreview__LowerEnd(view, frame, mins, maxs, n, side, up, bottom)
            ends = { up => bottom, side => near }

            if dirs[side].dot(sight).abs > NA_SCALE_DIM_END_ON
                k, sign = up, (bottom == maxs[up] ? 1.0 : -1.0)                # <-- Looking square at that side: drop below the bottom instead
            else
                k, sign = side, (near == maxs[side] ? 1.0 : -1.0)
            end
        else
            front, other = level.sort_by { |m| -dirs[m].dot(sight).abs }
            near = Na__InsertPrimatives.Na__ScalePreview__FacingEnd(frame, mins, maxs, front, sight) || mins[front]
            left = Na__InsertPrimatives.Na__ScalePreview__LeftEnd(view, frame, mins, maxs, n, other, front, near)
            ends = { front => near, other => left }

            if dirs[front].dot(sight).abs > NA_SCALE_DIM_END_ON
                k, sign = other, (left == maxs[other] ? 1.0 : -1.0)            # <-- Looking square at the front: out to the left instead
            else
                k, sign = front, (near == maxs[front] ? 1.0 : -1.0)
            end
        end

        Na__InsertPrimatives.Na__ScalePreview__KeepOutside(view, frame, mins, maxs, n, ends, k, sign)
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Way the Eye Looks at the Box, as a Unit World Vector
    # The camera's own direction in a parallel view; from the eye to the
    # middle of the box in perspective, where the two differ off-centre.
    # ------------------------------------------------------------
    def self.Na__ScalePreview__SightLine(view, frame, mins, maxs)
        camera = view.camera
        middle = Geom::Point3d.new((mins[0] + maxs[0]) * 0.5, (mins[1] + maxs[1]) * 0.5, (mins[2] + maxs[2]) * 0.5).transform(frame[:world])
        sight  = camera.perspective? ? (middle - camera.eye) : camera.direction.clone
        return nil unless sight.length > 0.0

        sight.length = 1.0
        sight
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The End of an Axis Whose Face Looks Towards the Camera, or nil
    # nil when both faces are seen edge-on: neither faces the camera.
    # ------------------------------------------------------------
    def self.Na__ScalePreview__FacingEnd(frame, mins, maxs, m, sight)
        dot = frame[:dirs][m].dot(sight)
        return nil if dot.abs < 0.05

        dot < 0.0 ? maxs[m] : mins[m]
    end
    # ---------------------------------------------------------------

    # FUNCTION | The End of an Axis Whose Edge Sits Lower on the Screen
    # For a level axis's dimension when neither of its sides faces the
    # camera (a plan view): the edge drawn lower, as a drawing would.
    # ------------------------------------------------------------
    def self.Na__ScalePreview__LowerEnd(view, frame, mins, maxs, n, side, up, bottom)
        [mins[side], maxs[side]].max_by do |value|
            point = Na__InsertPrimatives.Na__ScalePreview__EdgeMiddle(view, frame, mins, maxs, n, { up => bottom, side => value })
            point ? point.y : -1.0e9
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | The End of an Axis Whose Edge Sits Further Left on the Screen
    # ------------------------------------------------------------
    def self.Na__ScalePreview__LeftEnd(view, frame, mins, maxs, n, other, front, near)
        [mins[other], maxs[other]].min_by do |value|
            point = Na__InsertPrimatives.Na__ScalePreview__EdgeMiddle(view, frame, mins, maxs, n, { front => near, other => value })
            point ? point.x : 1.0e9
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Turn a Plan That Would Stand Off Into the Object
    # ------------------------------------------------------------
    def self.Na__ScalePreview__KeepOutside(view, frame, mins, maxs, n, ends, k, sign)
        plan    = { :ends => ends, :k => k, :sign => sign }
        corners = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, Na__InsertPrimatives.Na__ScaleFrame__BoxQuads(frame, mins, maxs).flatten)
        middle  = Na__InsertPrimatives.Na__ScalePreview__EdgeMiddle(view, frame, mins, maxs, n, ends)
        return plan unless corners && middle

        cx = corners.inject(0.0) { |sum, point| sum + point.x } / corners.length
        cy = corners.inject(0.0) { |sum, point| sum + point.y } / corners.length

        step = frame[:dirs][k].clone
        step.length = [frame[:world_lengths][k].to_f * 0.25, 1.0].max
        step.reverse! if sign < 0
        moved = Na__InsertPrimatives.Na__ScalePreview__Screen(
            view, Na__InsertPrimatives.Na__ScalePreview__EdgeMiddleWorld(frame, mins, maxs, n, ends).offset(step)
        )
        return plan unless moved

        outwards = ((moved.x - middle.x) * (middle.x - cx)) + ((moved.y - middle.y) * (middle.y - cy))
        return plan if outwards >= 0.0

        flipped    = ends.dup
        flipped[k] = ends[k] == maxs[k] ? mins[k] : maxs[k]
        { :ends => flipped, :k => k, :sign => -sign }
    rescue StandardError
        plan
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Middle of a Box Edge, in World Space
    # ends fixes the other two axes; n runs from its min to its max.
    # ------------------------------------------------------------
    def self.Na__ScalePreview__EdgeMiddleWorld(frame, mins, maxs, n, ends)
        values    = [0.0, 0.0, 0.0]
        ends.each { |m, value| values[m] = value }
        values[n] = (mins[n] + maxs[n]) * 0.5
        Geom::Point3d.new(values[0], values[1], values[2]).transform(frame[:world])
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Middle of a Box Edge on Screen, or nil Behind the Eye
    # ------------------------------------------------------------
    def self.Na__ScalePreview__EdgeMiddle(view, frame, mins, maxs, n, ends)
        Na__InsertPrimatives.Na__ScalePreview__Screen(view, Na__InsertPrimatives.Na__ScalePreview__EdgeMiddleWorld(frame, mins, maxs, n, ends))
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Far, in the Model, to Stand Off So It Reads offset_px on Screen
    # ------------------------------------------------------------
    # Measured at the middle of the edge with a short probe along the
    # stand-off — a hundredth of the edge, short enough for perspective to
    # stay straight — and scaled up to offset_px. A direction the eye sees at
    # a slant is foreshortened and so lengthened to make up; one seen end-on
    # never gets here (Na__ScalePreview__DimensionPlan turns it), and the
    # answer is capped at three times the box so nothing can fly off.
    # ------------------------------------------------------------
    def self.Na__ScalePreview__StandOff(view, world0, world1, away, offset_px)
        middle = Geom::Point3d.new((world0.x + world1.x) * 0.5, (world0.y + world1.y) * 0.5, (world0.z + world1.z) * 0.5)
        span   = world0.distance(world1).to_f
        length = [span * 0.01, 0.01].max
        probe  = Geom::Vector3d.new(away.x * length, away.y * length, away.z * length)
        pair   = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, [middle, middle.offset(probe)])
        return nil unless pair

        seen = Math.hypot(pair[1].x - pair[0].x, pair[1].y - pair[0].y)
        return nil unless seen > 1.0e-6

        reach = length * (offset_px.to_f / seen)
        reach > span * 3.0 + length * 100.0 ? nil : reach
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Screen Direction as [x, y] of Length One, or nil
    # ------------------------------------------------------------
    def self.Na__ScalePreview__Unit(dx, dy)
        length = Math.hypot(dx.to_f, dy.to_f)
        length > 1.0e-6 ? [dx / length, dy / length] : nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Clickable Rect a Dimension's Text Sits In
    # ------------------------------------------------------------
    def self.Na__ScalePreview__PillRect(view, layout, text, size)
        width, height = Na__InsertPrimatives.Na__ScalePreview__TextSize(view, text, size, true)
        half_w = (width * 0.5) + NA_SCALE_PILL_PAD_X
        half_h = (height * 0.5) + NA_SCALE_PILL_PAD_Y
        mid    = layout[:mid]

        [mid.x - half_w, mid.y - half_h, mid.x + half_w, mid.y + half_h]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw One Dimension: Extension Lines, Arrows and Its Pill
    # ------------------------------------------------------------
    # state picks the pill: :plain, :hover (the cursor is on it), :active
    # (clicked — the next typed value goes here), :typing (it is showing
    # what is being typed, brackets and caret already in the text) or :live
    # (the drag is changing it right now). An active value gains brackets as
    # well as orange, the two signals the plugin always gives a pinned value.
    # ------------------------------------------------------------
    def self.Na__ScalePreview__DrawDimension(view, layout, rect, text, size, state = :plain)
        axis   = layout[:axis]
        colour = Na__InsertPrimatives.Na__ScalePreview__AxisColor(axis)
        ux, uy = layout[:dir]
        s0, s1 = layout[:s0], layout[:s1]
        e0, e1 = layout[:e0], layout[:e1]

        # Each extension line runs the way the stand-off runs at its own end:
        # in perspective the two are not quite parallel on screen, as they are
        # not on a drawn dimension either. A small gap at the object, a little
        # overshoot past the line.
        a0x, a0y = layout[:o0] || layout[:out]
        a1x, a1y = layout[:o1] || layout[:out]

        view.line_stipple  = ''
        view.line_width    = 1
        view.drawing_color = colour
        view.draw2d(GL_LINES, [
            Geom::Point3d.new(s0.x + (a0x * 3.0), s0.y + (a0y * 3.0), 0), Geom::Point3d.new(e0.x + (a0x * 5.0), e0.y + (a0y * 5.0), 0),
            Geom::Point3d.new(s1.x + (a1x * 3.0), s1.y + (a1y * 3.0), 0), Geom::Point3d.new(e1.x + (a1x * 5.0), e1.y + (a1y * 5.0), 0)
        ])

        view.line_width = [:active, :typing, :live].include?(state) ? 2 : 1
        view.draw2d(GL_LINES, [e0, e1])

        # The barbs spread along the stand-off, so the arrows lie in the same
        # plane as the rest; square on screen only where that plane is seen so
        # nearly edge-on that a flat arrow would close up.
        wx, wy = layout[:out]
        wx, wy = -uy, ux if ((ux * wy) - (uy * wx)).abs < 0.3

        barb = NA_SCALE_ARROW_PIXELS
        view.draw2d(GL_TRIANGLES, [
            e0,
            Geom::Point3d.new(e0.x + (ux * barb) + (wx * barb * 0.38), e0.y + (uy * barb) + (wy * barb * 0.38), 0),
            Geom::Point3d.new(e0.x + (ux * barb) - (wx * barb * 0.38), e0.y + (uy * barb) - (wy * barb * 0.38), 0),
            e1,
            Geom::Point3d.new(e1.x - (ux * barb) + (wx * barb * 0.38), e1.y - (uy * barb) + (wy * barb * 0.38), 0),
            Geom::Point3d.new(e1.x - (ux * barb) - (wx * barb * 0.38), e1.y - (uy * barb) - (wy * barb * 0.38), 0)
        ])
        view.line_width = 1

        fill, border, ink, label =
            case state
            when :active then [NA_SCALE_PILL_ACTIVE_COLOR, NA_DRAWN_TEXT_LOCKED_COLOR, NA_DRAWN_TEXT_LOCKED_COLOR, "[#{text}]"]
            when :typing then [NA_SCALE_PILL_ACTIVE_COLOR, NA_DRAWN_TEXT_LOCKED_COLOR, NA_DRAWN_TEXT_LOCKED_COLOR, text]
            when :live   then [NA_SCALE_PILL_FILL_COLOR,   NA_SCALE_NEW_BORDER_COLOR,  NA_SCALE_NEW_BORDER_COLOR,  text]
            when :hover  then [NA_SCALE_PILL_HOVER_COLOR,  colour,                     colour,                     text]
            else              [NA_SCALE_PILL_FILL_COLOR,   colour,                     colour,                     text]
            end

        Na__InsertPrimatives.Na__ScalePreview__DrawRect(view, rect, fill, border, state == :plain ? 1 : 2)
        Na__InsertPrimatives.Na__ScalePreview__DrawText(
            view, (rect[0] + rect[2]) * 0.5, (rect[1] + rect[3]) * 0.5, label, size, ink, true
        )
    rescue StandardError
        nil                                                                   # <-- Never let a decoration kill the whole draw pass
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Handle Bar
    # -----------------------------------------------------------------------------

    # FUNCTION | Lay the Bar's Buttons Out Left to Right
    # ------------------------------------------------------------
    # entries are { :id, :text, :state, :tip } and { :gap => true } between
    # groups. It stands at a fixed place on screen, for the reason the popup
    # is anchored: a control that moves with the object cannot be learned.
    # ------------------------------------------------------------
    def self.Na__ScalePreview__BarLayout(view, entries, origin = NA_SCALE_BAR_ORIGIN)
        x = origin[0].to_f
        y = origin[1].to_f

        entries.map do |entry|
            if entry[:gap]
                x += NA_SCALE_BAR_GROUP_GAP
                next nil
            end

            width, _height = Na__InsertPrimatives.Na__ScalePreview__TextSize(view, entry[:text], NA_SCALE_BAR_TEXT_SIZE, entry[:state] == :mode)
            span           = width + 14.0
            rect           = [x, y, x + span, y + NA_SCALE_BAR_HEIGHT]
            x             += span + NA_SCALE_BAR_GAP

            entry.merge(:rect => rect)
        end.compact
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw the Bar, With the Hovered Button Lit
    # ------------------------------------------------------------
    def self.Na__ScalePreview__DrawBar(view, buttons, hover_id = nil)
        return if buttons.nil? || buttons.empty?

        panel = [
            buttons.first[:rect][0] - 4, buttons.first[:rect][1] - 4,
            buttons.last[:rect][2] + 4,  buttons.last[:rect][3] + 4
        ]
        Na__InsertPrimatives.Na__ScalePreview__DrawRect(view, panel, NA_SCALE_BAR_PANEL_COLOR, NA_SCALE_BAR_PANEL_EDGE, 1)

        buttons.each do |button|
            style = (button[:id] == hover_id && button[:state] == :plain) ? :hover : button[:state]
            fill, border, ink = NA_SCALE_BAR_STYLES[style] || NA_SCALE_BAR_STYLES[:plain]
            rect = button[:rect]

            Na__InsertPrimatives.Na__ScalePreview__DrawRect(view, rect, fill, border, button[:id] == hover_id ? 2 : 1)
            Na__InsertPrimatives.Na__ScalePreview__DrawText(
                view, (rect[0] + rect[2]) * 0.5, (rect[1] + rect[3]) * 0.5,
                button[:text], NA_SCALE_BAR_TEXT_SIZE, ink, button[:state] == :mode
            )
        end
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP SCALE PREVIEW GRAPHICS
# =============================================================================
