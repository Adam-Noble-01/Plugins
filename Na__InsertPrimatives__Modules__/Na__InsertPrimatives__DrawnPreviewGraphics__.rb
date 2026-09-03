# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PRIMITIVES PREVIEW GRAPHICS
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPreviewGraphics__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Shaded viewport previews and live dimension labels for the
#              click-and-drag Drawn Plane / Drawn Volume tools
# CREATED    : 2026
#
# DESCRIPTION:
# - Builds on the Element Assembly Studio Pro measurement overlays: a translucent
#   coloured face with a solid border, an axis crosshair on the anchor point and
#   dimension text sitting beside the shape.
# - Every function is stateless and takes everything it needs as arguments.
# - Labels are drawn with a one-pixel halo so they stay readable against both the
#   white sky and dark geometry.
#
# COLOUR ROLES:
#   Plane    blue   — the 2D rectangle being dragged out
#   Volume   amber  — the extruded prism, so the two stages read differently
#   Anchor   green  — the snapped corner the shape is growing from
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnGridSnap__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Preview Palette and Text Metrics
    # -----------------------------------------------------------------------------

    NA_DRAWN_PLANE_FILL_COLOR    = Sketchup::Color.new(  0, 120, 255,  70)
    NA_DRAWN_PLANE_BORDER_COLOR  = Sketchup::Color.new(  0, 110, 235, 230)
    NA_DRAWN_VOLUME_FILL_COLOR   = Sketchup::Color.new(255, 150,  30,  62)
    NA_DRAWN_VOLUME_BORDER_COLOR = Sketchup::Color.new(226, 118,   0, 235)
    NA_DRAWN_ANCHOR_COLOR        = Sketchup::Color.new(  0, 190,  70)
    NA_DRAWN_GUIDE_COLOR         = Sketchup::Color.new(120, 120, 120, 160)

    NA_DRAWN_TEXT_COLOR          = Sketchup::Color.new( 20,  20,  20)
    NA_DRAWN_TEXT_HALO_COLOR     = Sketchup::Color.new(255, 255, 255)
    NA_DRAWN_TEXT_ACCENT_COLOR   = Sketchup::Color.new(  0,  90, 190)
    NA_DRAWN_TEXT_LOCKED_COLOR   = Sketchup::Color.new(200,  70,   0)         # <-- A typed dimension the drag can no longer move

    NA_DRAWN_TEXT_SIZE           = 12
    NA_DRAWN_TEXT_LINE_HEIGHT    = 16
    NA_DRAWN_TEXT_CHAR_WIDTH     = 6.6                                        # <-- Estimated px per character at the size and weight above
    NA_DRAWN_TEXT_HALO_OFFSETS   = [[-1, 0], [1, 0], [0, -1], [0, 1]].freeze

    NA_DRAWN_CROSSHAIR_ARM       = 250.mm

    NA_DRAWN_ARROW_PIXELS        = 46.0                                       # <-- Shaft length of a direction arrow, on screen
    NA_DRAWN_ARROW_BARB_PIXELS   = 11.0
    NA_DRAWN_LABEL_MIN_GAP_PX    = 42.0                                       # <-- Below this two labels are the same label twice

    # SketchUp's own axis colours, so a locked ray reads instantly.
    NA_DRAWN_AXIS_COLORS         = {
        :x => Sketchup::Color.new(213,  40,  60),
        :y => Sketchup::Color.new( 30, 165,  70),
        :z => Sketchup::Color.new( 45,  90, 220)
    }.freeze

    NA_DRAWN_AXIS_RAY_FALLBACK   = 60.m                                       # <-- Used when pixels_to_model cannot answer

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | World to Draw Space
    # -----------------------------------------------------------------------------

    # THE THIRD COORDINATE RULE (the nested-preview fix):
    # - Two rules were already known and are documented in the chamfer tool:
    #   entity positions READ are definition-local, and geometry ADDED while an
    #   editing context is open is interpreted in the editing session's space.
    # - This is the third, and it is the same pipeline as the second: points
    #   handed to View#draw / View#draw_line / View#screen_coords while a
    #   context is open are ALSO read in the editing session's space. Feed those
    #   calls correct world coordinates with a group open and the whole preview
    #   renders at edit_transform * point — displaced by exactly the group's
    #   transform, right shape, right size, wrong place. Skewed as well if the
    #   group is rotated or scaled.
    # - Push/pull never met the ADD rule because pushpull takes a scalar, which
    #   is why the geometry it commits has always landed correctly while the
    #   preview drifted. The preview is the only half that draws positions.
    # - So every world point crossing into a view call is converted here, and
    #   the conversion happens at exactly ONE layer: the functions below that
    #   touch view.draw* directly. The composite overlays delegate to those and
    #   must NOT convert again.
    # - At the model root edit_transform is the identity and this is a no-op,
    #   which is why loose geometry was never affected.

    # FUNCTION | The World to Draw Space Transformation, or nil at the Root
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawSpace
        model = Sketchup.active_model
        return nil unless model && model.respond_to?(:edit_transform)

        edit = model.edit_transform
        return nil if edit.nil?
        return nil if edit.respond_to?(:identity?) && edit.identity?

        edit.inverse
    rescue StandardError
        nil                                                                   # <-- A failed conversion draws in world, as before
    end
    # ---------------------------------------------------------------

    # FUNCTION | One World Point into Draw Space
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__ToDrawPoint(point)
        space = Na__InsertPrimatives.Na__DrawnPreview__DrawSpace
        return point unless space && point

        point.transform(space)
    rescue StandardError
        point
    end
    # ---------------------------------------------------------------

    # FUNCTION | A List of World Points into Draw Space
    # The transform is resolved once and reused, so a 60-segment cylinder costs
    # one edit_transform read rather than sixty.
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__ToDrawSpace(points)
        space = Na__InsertPrimatives.Na__DrawnPreview__DrawSpace
        return points unless space && points

        points.map { |point| point ? point.transform(space) : point }
    rescue StandardError
        points
    end
    # ---------------------------------------------------------------

    # FUNCTION | A World Direction into Draw Space
    # ------------------------------------------------------------
    # Vectors, not points: an axis lock names a WORLD axis and a camera has a
    # WORLD direction, so both have to be re-expressed in the space the drawing
    # is going to be read in or the ray and the arrow barbs point off true
    # inside a rotated group.
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__ToDrawVector(vector)
        space = Na__InsertPrimatives.Na__DrawnPreview__DrawSpace
        return vector unless space && vector

        moved = vector.transform(space)
        moved.length > 0 ? moved.normalize : vector
    rescue StandardError
        vector
    end
    # ---------------------------------------------------------------

    # FUNCTION | A List of Triangle Point Triples into Draw Space
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__ToDrawTriangles(triangles)
        space = Na__InsertPrimatives.Na__DrawnPreview__DrawSpace
        return triangles unless space && triangles

        triangles.map { |points| points.map { |point| point.transform(space) } }
    rescue StandardError
        triangles
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Axis Lock Rendering
    # -----------------------------------------------------------------------------

    # FUNCTION | Draw a Full-Width Coloured Ray Along a Locked Axis
    # The span is derived from the viewport rather than being a fixed model
    # length, so the ray always crosses the screen at any zoom — a fixed length
    # would vanish to a dot on a site plan and shoot past the horizon on a detail.
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawAxisRay(view, origin, axis_key)
        return unless origin && axis_key

        vector = Na__InsertPrimatives.Na__DrawnGrid__AxisVector(axis_key)
        return unless vector

        origin = Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(origin)   # <-- Everything below is measured in draw space
        vector = Na__InsertPrimatives.Na__DrawnPreview__ToDrawVector(vector)

        span =
            begin
                pixels = view.vpwidth > view.vpheight ? view.vpwidth : view.vpheight
                view.pixels_to_model(pixels, origin).to_f * 1.2
            rescue StandardError
                NA_DRAWN_AXIS_RAY_FALLBACK.to_f
            end
        span = NA_DRAWN_AXIS_RAY_FALLBACK.to_f unless span > 0.0

        colour = NA_DRAWN_AXIS_COLORS[axis_key] || NA_DRAWN_TEXT_ACCENT_COLOR
        far_a  = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(origin, vector, -span)
        far_b  = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(origin, vector,  span)

        view.line_stipple  = ''
        view.drawing_color = colour
        view.line_width    = 1
        view.draw_line(far_a, far_b)

        view.line_width    = 4                                                # <-- Heavier core so the lock reads near the cursor
        view.draw_line(
            Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(origin, vector, -span * 0.06),
            Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(origin, vector,  span * 0.06)
        )
        view.line_width    = 2
    end
    # ---------------------------------------------------------------

    # FUNCTION | Colour for an Axis Key
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__AxisColor(axis_key)
        NA_DRAWN_AXIS_COLORS[axis_key] || NA_DRAWN_TEXT_ACCENT_COLOR
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw a Set of World-Space Triangles as a Shaded Face
    # Used for the push/pull highlight, where the face can be concave or have
    # holes and a triangle fan would fill straight over them.
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawTriangles(view, triangles, fill_color)
        return unless triangles && !triangles.empty?

        triangles = Na__InsertPrimatives.Na__DrawnPreview__ToDrawTriangles(triangles)

        view.drawing_color = fill_color
        triangles.each { |points| view.draw(GL_TRIANGLES, points) if points.length == 3 }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw a Closed Outline Through a Loop of Points
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawLoop(view, points, border_color, width = 2)
        return unless points && points.length >= 2

        points = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(points)

        view.line_stipple  = ''
        view.line_width    = width
        view.drawing_color = border_color
        view.draw(GL_LINE_LOOP, points)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Text Rendering
    # -----------------------------------------------------------------------------

    # FUNCTION | Draw One or More Text Lines at a Screen Position
    # @param lines [String, Array<String>] single line or ordered list of lines
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawScreenText(view, screen_x, screen_y, lines, color = nil)
        text_lines = lines.is_a?(Array) ? lines : [lines]
        text_color = color || NA_DRAWN_TEXT_COLOR

        halo_options = { :size => NA_DRAWN_TEXT_SIZE, :bold => true, :color => NA_DRAWN_TEXT_HALO_COLOR }
        main_options = { :size => NA_DRAWN_TEXT_SIZE, :bold => true, :color => text_color }

        text_lines.each_with_index do |line, index|
            content = line.to_s
            next if content.empty?

            line_y = screen_y + (index * NA_DRAWN_TEXT_LINE_HEIGHT)

            NA_DRAWN_TEXT_HALO_OFFSETS.each do |offset_x, offset_y|
                view.draw_text(Geom::Point3d.new(screen_x + offset_x, line_y + offset_y, 0), content, halo_options)
            end

            view.draw_text(Geom::Point3d.new(screen_x, line_y, 0), content, main_options)
        end
    rescue StandardError
        nil                                                                   # <-- Never let a label kill the whole draw pass
    end
    # ---------------------------------------------------------------

    # FUNCTION | Estimated Pixel Size of a Text Block
    # ------------------------------------------------------------
    # draw_text reports no metrics, so the width is estimated from the character
    # count at the one size and weight every label in this plugin uses. It only
    # ever feeds CENTRING, where a few pixels of error moves a label a few
    # pixels — nothing measures anything by it.
    #
    # Returns [width_px, height_px]. The height is exact.
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__TextBlockSize(lines)
        text_lines = (lines.is_a?(Array) ? lines : [lines]).reject { |line| line.to_s.empty? }
        return [0.0, 0.0] if text_lines.empty?

        widest = text_lines.map { |line| line.to_s.length }.max.to_f

        [widest * NA_DRAWN_TEXT_CHAR_WIDTH, text_lines.length * NA_DRAWN_TEXT_LINE_HEIGHT.to_f]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw a Text Block Centred on a Screen Position
    # draw_text anchors on the top-left corner, so the block's own size is what
    # converts a wanted centre into the corner it has to be drawn from.
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawCentredScreenText(view, centre_x, centre_y, lines, color = nil)
        width, height = Na__InsertPrimatives.Na__DrawnPreview__TextBlockSize(lines)

        Na__InsertPrimatives.Na__DrawnPreview__DrawScreenText(
            view,
            centre_x.to_f - (width  * 0.5),
            centre_y.to_f - (height * 0.5),
            lines, color
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw a Label Anchored to a World Point
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawWorldLabel(view, world_point, lines, offset_x = 14, offset_y = -26, color = nil)
        return unless world_point

        screen_pt = view.screen_coords(
            Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(world_point)
        )
        Na__InsertPrimatives.Na__DrawnPreview__DrawScreenText(
            view, screen_pt.x + offset_x, screen_pt.y + offset_y, lines, color
        )
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw a Dimension Label at the Midpoint of an Edge
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawEdgeLabel(view, point_a, point_b, text, color = nil)
        return unless point_a && point_b

        midpoint = Geom::Point3d.new(
            (point_a.x.to_f + point_b.x.to_f) * 0.5,
            (point_a.y.to_f + point_b.y.to_f) * 0.5,
            (point_a.z.to_f + point_b.z.to_f) * 0.5
        )

        Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, midpoint, text, 8, -8, color)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Shape Rendering
    # -----------------------------------------------------------------------------

    # FUNCTION | Draw a Three-Axis Crosshair at a Point
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawCrosshair(view, point, arm_length = nil, color = nil)
        return unless point

        arm            = (arm_length || NA_DRAWN_CROSSHAIR_ARM).to_f
        point          = Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(point)
        ax, ay, az     = Na__InsertPrimatives.Na__DrawnGrid__AxisVectors.map { |axis|
            Na__InsertPrimatives.Na__DrawnPreview__ToDrawVector(axis)
        }
        view.line_stipple = ''
        view.line_width   = 2

        [[ax, Sketchup::Color.new(220, 60, 60)],
         [ay, Sketchup::Color.new(60, 170, 60)],
         [az, Sketchup::Color.new(60, 90, 220)]].each do |axis, axis_color|
            view.drawing_color = color || axis_color
            view.draw_line(
                Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, axis, -arm),
                Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, axis,  arm)
            )
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw a Screen-Sized Direction Arrow From a World Point
    # ------------------------------------------------------------
    # Says which way a push is going to travel, at a size that reads the same at
    # any zoom because it is measured in pixels rather than model units.
    #
    # The barbs are laid out with the CAMERA direction, not with a model axis, so
    # they always open across the screen and the arrow reads as an arrow from
    # wherever it is being looked at. A direction pointing straight down the
    # camera has no such side, so the cross degenerates and an arbitrary
    # perpendicular from Vector3d#axes stands in — the arrow is foreshortened to
    # nothing in that view anyway.
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawDirectionArrow(view, origin, direction, color = nil)
        return unless view && origin && direction

        camera = view.camera ? view.camera.direction : nil
        return unless camera && camera.length > 0

        origin    = Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(origin)
        direction = Na__InsertPrimatives.Na__DrawnPreview__ToDrawVector(direction)
        camera    = Na__InsertPrimatives.Na__DrawnPreview__ToDrawVector(camera)

        shaft = view.pixels_to_model(NA_DRAWN_ARROW_PIXELS,      origin).to_f
        barb  = view.pixels_to_model(NA_DRAWN_ARROW_BARB_PIXELS, origin).to_f
        return unless shaft > 0.0

        tip  = origin.offset(direction, shaft)
        side = direction.cross(camera)
        side = direction.axes[0] if side.length == 0
        side.normalize!

        back = tip.offset(direction.reverse, barb * 1.8)

        view.line_stipple  = ''
        view.line_width    = 3
        view.drawing_color = color || NA_DRAWN_ANCHOR_COLOR
        view.draw_line(origin, tip)
        view.draw_line(tip, back.offset(side,         barb))
        view.draw_line(tip, back.offset(side.reverse, barb))
        view.line_width    = 2
    rescue StandardError
        nil                                                                   # <-- Never let a decoration kill the whole draw pass
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw a Filled, Bordered Quad
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawFilledQuad(view, points, fill_color, border_color)
        return unless points && points.length == 4

        points = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(points)

        view.drawing_color = fill_color
        view.draw(GL_QUADS, points)

        view.line_stipple  = ''
        view.line_width    = 2
        view.drawing_color = border_color
        view.draw(GL_LINE_LOOP, points)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw a Dashed Outline Only (Degenerate / Zero-Area State)
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawOutline(view, points, border_color)
        return unless points && points.length >= 2

        points = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(points)

        view.line_stipple  = '-'
        view.line_width    = 2
        view.drawing_color = border_color
        view.draw(GL_LINE_LOOP, points)
        view.line_stipple  = ''
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw a Filled, Bordered Box from Near and Far Rectangles
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawFilledBox(view, near_points, far_points, fill_color, border_color)
        return unless near_points && far_points

        near_points = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(near_points)
        far_points  = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(far_points)

        side_faces = [
            [near_points[0], near_points[1], far_points[1],  far_points[0]],
            [near_points[1], near_points[2], far_points[2],  far_points[1]],
            [near_points[2], near_points[3], far_points[3],  far_points[2]],
            [near_points[3], near_points[0], far_points[0],  far_points[3]]
        ]

        view.drawing_color = fill_color
        view.draw(GL_QUADS, near_points)
        view.draw(GL_QUADS, far_points)
        side_faces.each { |face_points| view.draw(GL_QUADS, face_points) }

        view.line_stipple  = ''
        view.line_width    = 2
        view.drawing_color = border_color
        view.draw(GL_LINE_LOOP, near_points)
        view.draw(GL_LINE_LOOP, far_points)
        4.times { |index| view.draw_line(near_points[index], far_points[index]) }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw a Filled, Bordered Convex Polygon
    # A triangle fan from the first vertex, which is valid for every loop the
    # roof builder produces (triangles and trapezoids only).
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawFilledPolygon(view, points, fill_color, border_color)
        return unless points && points.length >= 3

        points = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(points)

        view.drawing_color = fill_color
        view.draw(GL_TRIANGLE_FAN, points)

        view.line_stipple  = ''
        view.line_width    = 2
        view.drawing_color = border_color
        view.draw(GL_LINE_LOOP, points)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw a Highlighted Ridge Line
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawRidgeLine(view, point_a, point_b)
        return unless point_a && point_b
        return if point_a.distance(point_b) < 0.001

        point_a = Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(point_a)
        point_b = Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(point_b)

        view.line_stipple  = ''
        view.line_width    = 4
        view.drawing_color = NA_DRAWN_VOLUME_BORDER_COLOR
        view.draw_line(point_a, point_b)
        view.line_width    = 2
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw a Filled, Bordered Circle
    # A triangle fan from the centre is used rather than GL_POLYGON so the fill
    # is guaranteed correct for any segment count.
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawFilledCircle(view, centre, points, fill_color, border_color)
        return unless centre && points && points.length >= 3

        centre = Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(centre)
        points = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(points)

        view.drawing_color = fill_color
        view.draw(GL_TRIANGLE_FAN, [centre] + points + [points[0]])

        view.line_stipple  = ''
        view.line_width    = 2
        view.drawing_color = border_color
        view.draw(GL_LINE_LOOP, points)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw a Filled, Bordered Cylinder from Two Circles
    # Only the quarter-point verticals are drawn: one line per segment would be
    # a thicket of 24-plus edges over the live model for no extra information.
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawFilledCylinder(view, near_centre, near_points, far_centre, far_points, fill_color, border_color)
        return unless near_points && far_points && near_points.length >= 3
        return unless near_points.length == far_points.length

        near_centre = Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(near_centre)
        far_centre  = Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(far_centre)
        near_points = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(near_points)
        far_points  = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(far_points)

        view.drawing_color = fill_color
        view.draw(GL_TRIANGLE_FAN, [near_centre] + near_points + [near_points[0]])
        view.draw(GL_TRIANGLE_FAN, [far_centre]  + far_points  + [far_points[0]])

        wall_strip = []
        near_points.each_with_index do |near_point, index|
            wall_strip << near_point << far_points[index]
        end
        wall_strip << near_points[0] << far_points[0]
        view.draw(GL_QUAD_STRIP, wall_strip)

        view.line_stipple  = ''
        view.line_width    = 2
        view.drawing_color = border_color
        view.draw(GL_LINE_LOOP, near_points)
        view.draw(GL_LINE_LOOP, far_points)

        quarter = near_points.length / 4
        quarter = 1 if quarter < 1
        index   = 0
        while index < near_points.length
            view.draw_line(near_points[index], far_points[index])
            index += quarter
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw a Faint Guide Line Between Two Points
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DrawGuideLine(view, point_a, point_b)
        return unless point_a && point_b

        point_a = Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(point_a)
        point_b = Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(point_b)

        view.line_stipple  = '.'
        view.line_width    = 1
        view.drawing_color = NA_DRAWN_GUIDE_COLOR
        view.draw_line(point_a, point_b)
        view.line_stipple  = ''
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Composite Dimension Overlays
    # -----------------------------------------------------------------------------

    # FUNCTION | Render a Dimension, Bracketed and Recoloured When Locked
    # Colour alone would be easy to miss mid-drag, so a locked value also gains
    # brackets — two signals for the same fact.
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DimensionText(value, locked)
        millimetres = Na__InsertPrimatives.Na__DrawnFormat__Mm(value).abs
        locked ? "[#{millimetres}]" : millimetres.to_s
    end
    # ---------------------------------------------------------------

    # FUNCTION | Colour for a Dimension Label
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__DimensionColor(locked)
        locked ? NA_DRAWN_TEXT_LOCKED_COLOR : NA_DRAWN_TEXT_ACCENT_COLOR
    end
    # ---------------------------------------------------------------

    # FUNCTION | Label the Width and Height Edges of a Rectangle
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__LabelRectangle(view, points, u_len, v_len, u_locked = false, v_locked = false)
        return unless points && points.length == 4

        Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(
            view, points[0], points[1],
            Na__InsertPrimatives.Na__DrawnPreview__DimensionText(u_len, u_locked),
            Na__InsertPrimatives.Na__DrawnPreview__DimensionColor(u_locked)
        )
        Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(
            view, points[1], points[2],
            Na__InsertPrimatives.Na__DrawnPreview__DimensionText(v_len, v_locked),
            Na__InsertPrimatives.Na__DrawnPreview__DimensionColor(v_locked)
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | Summary Card Beside the Cursor for a Rectangle
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__SummarisePlane(view, anchor_point, u_len, v_len)
        width_mm  = Na__InsertPrimatives.Na__DrawnFormat__Mm(u_len).abs
        height_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(v_len).abs

        lines = [
            "W #{width_mm} x H #{height_mm} mm",
            "Area #{Na__InsertPrimatives.Na__DrawnFormat__AreaM2(u_len, v_len)} m2"
        ]

        Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, anchor_point, lines)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Summary Card Beside the Cursor for a Circle
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__SummariseCircle(view, anchor_point, radius, segments)
        radius_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(radius).abs

        lines = [
            "R #{radius_mm} / dia #{radius_mm * 2} mm",
            "Area #{Na__InsertPrimatives.Na__DrawnFormat__CircleAreaM2(radius)} m2  ·  #{segments} sides"
        ]

        Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, anchor_point, lines)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Summary Card Beside the Cursor for a Cylinder
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__SummariseCylinder(view, anchor_point, radius, height, segments)
        radius_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(radius).abs
        height_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(height).abs

        lines = [
            "dia #{radius_mm * 2} x H #{height_mm} mm",
            "Volume #{Na__InsertPrimatives.Na__DrawnFormat__CylinderVolumeM3(radius, height)} m3  ·  #{segments} sides"
        ]

        Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, anchor_point, lines)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Summary Card Beside the Cursor for a Roof
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__SummariseRoof(view, anchor_point, plan_u, plan_v, height, pitch_degrees, volume_text)
        width_mm  = Na__InsertPrimatives.Na__DrawnFormat__Mm(plan_u).abs
        length_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(plan_v).abs
        height_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(height).abs

        lines = [
            "#{width_mm} x #{length_mm} plan, rise #{height_mm} mm",
            "Pitch #{Na__InsertPrimatives.Na__DrawnFormat__Degrees(pitch_degrees)} deg  ·  #{volume_text} m3"
        ]

        Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, anchor_point, lines)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Summary Card Beside the Cursor for a Volume
    # ------------------------------------------------------------
    def self.Na__DrawnPreview__SummariseVolume(view, anchor_point, u_len, v_len, d_len)
        width_mm  = Na__InsertPrimatives.Na__DrawnFormat__Mm(u_len).abs
        height_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(v_len).abs
        depth_mm  = Na__InsertPrimatives.Na__DrawnFormat__Mm(d_len).abs

        lines = [
            "W #{width_mm} x H #{height_mm} x D #{depth_mm} mm",
            "Volume #{Na__InsertPrimatives.Na__DrawnFormat__VolumeM3(u_len, v_len, d_len)} m3"
        ]

        Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, anchor_point, lines)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PRIMITIVES PREVIEW GRAPHICS MODULE
# =============================================================================
