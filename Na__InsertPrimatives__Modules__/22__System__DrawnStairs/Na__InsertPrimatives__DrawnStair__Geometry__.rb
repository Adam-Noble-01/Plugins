# =============================================================================
# NA INSERT PRIMATIVES - DRAWN STAIR GEOMETRY
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnStair__Geometry__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Block frame, side picking, the even-step solve, the step profile,
#              the Part K check and the solid for the Drawn Staircase tool
# CREATED    : 2026
#
# DESCRIPTION:
# - The staircase is carved out of the block the Drawn Volume gestures leave
#   behind. That block is always square to the drawing axes, so it is read back
#   here as an axis-aligned box: a min corner plus its X, Y and Z extents. Z is
#   up, whichever plane the base rectangle was drawn on.
# - A SIDE is one of the block's four vertical faces, named by where it sits
#   (:y_min, :x_max, :y_max, :x_min). The flight rises FROM that side and
#   climbs INWARD, square to it, across the full width of the side.
# - ProfileLocal returns the step profile as (a, b) pairs: a runs inward from
#   the side, b runs up from the base. The preview and the builder both map
#   that same list to world space, so what is drawn is what is built.
#
# THE EVEN-STEP SOLVE (the UK count, Approved Document K):
#   N risers, N - 1 goings in the flight; the landing is the Nth tread.
#   rise  = height / N
#   going = run / (N - 1)      run = the inward drag; the first riser stands on the side
#   pitch = atan(rise / going)
#   Whatever of the block lies past the run stays full height: that is the landing.
#   A run of the whole block leaves no landing, and the top riser then meets
#   the floor beyond the block's far face.
#
# COORDINATES:
# - Everything here is global, like every other drawn shape in this plugin:
#   the InputPoint, the pick rays and the drawing axes all are. The builder
#   adds into a fresh group pinned to the world identity
#   (Na__DrawnGeom__PinGroupToWorld), so no edit_transform maths appears in
#   this file, and none should.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnGridSnap__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnGeometry__'
require_relative '../03__AppUtils/Na__InsertPrimatives__AppUtils__DrawnFormat__'
require_relative '../05__PreviewGraphics/Na__InsertPrimatives__DrawnPreviewGraphics__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Stair Constants
    # -----------------------------------------------------------------------------

    NA_DRAWN_STAIR_GROUP_NAME   = '01__DrawnStaircase'

    NA_DRAWN_STAIR_SIDE_KEYS    = [:y_min, :x_max, :y_max, :x_min].freeze
    NA_DRAWN_STAIR_SIDE_LABELS  = {
        :y_min => '-Y',
        :x_max => '+X',
        :y_max => '+Y',
        :x_min => '-X'
    }.freeze

    NA_DRAWN_STAIR_DEFAULT_RISE = 175.mm                                      # <-- The first stair's target rise; later ones follow the last built
    NA_DRAWN_STAIR_MIN_RISE     = 50.mm                                       # <-- Below this a riser is not a step
    NA_DRAWN_STAIR_MIN_STEPS    = 2                                           # <-- One tread and the landing
    NA_DRAWN_STAIR_MIN_GOING    = 1.mm                                        # <-- A build refuses goings thinner than this
    NA_DRAWN_STAIR_MERGE_TOL    = 0.5.mm                                      # <-- A landing shorter than this is no landing
    NA_DRAWN_STAIR_LOOP_TOL     = 0.000001                                    # <-- Internal inches; coincident profile points
    NA_DRAWN_STAIR_GRAZING      = 0.02                                        # <-- |cos| under which a drag plane is seen edge-on
    NA_DRAWN_STAIR_TOP_FACING   = 0.1                                         # <-- Looking down more steeply than ~6 degrees: drag on the top face

    # Approved Document K (2013), Table 1.1 plus the 42 degree pitch limit, for
    # a PRIVATE stair — the dwelling stair most of this plugin's work is about.
    # Held in one table so a utility or general access stair is one edit away.
    NA_DRAWN_STAIR_PARTK_RULES  = {
        :label       => 'Part K private stair',
        :short_label => 'Part K',
        :rise_min    => 150.0,
        :rise_max    => 220.0,
        :going_min   => 220.0,
        :going_max   => 300.0,
        :pitch_max   => 42.0,
        :two_r_g_min => 550.0,
        :two_r_g_max => 700.0
    }.freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Formatting
    # -----------------------------------------------------------------------------

    # FUNCTION | A Millimetre Value to One Decimal, Dropping a Trailing .0
    # A stair's rise and going are rarely whole millimetres (1690 / 10 is
    # 169), and rounding them the way the block's sizes are rounded would show
    # ten risers of 169 adding up to 1690 but ten goings of 167 adding up to
    # something else. One decimal keeps the arithmetic visible.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__FormatMmValue(millimetres)
        rounded = (millimetres.to_f * 10.0).round / 10.0
        rounded == rounded.round ? rounded.round.to_s : format('%.1f', rounded)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Internal Inches as Millimetres to One Decimal
    # ------------------------------------------------------------
    def self.Na__DrawnStair__FormatMm(value)
        Na__InsertPrimatives.Na__DrawnStair__FormatMmValue((value.to_f * NA_DRAWN_INCH_TO_MM).abs)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Block Frame
    # -----------------------------------------------------------------------------

    # FUNCTION | Read the Drawn Block Back as an Axis-Aligned Box
    # ------------------------------------------------------------
    # Takes the volume's own drag state — anchor, plane and signed sizes — and
    # measures its eight corners along the drawing axes. The signs and the base
    # plane both fall out of the min / max, so a block dragged backwards, or
    # drawn on an elevation plane and extruded sideways, reads the same as one
    # drawn on plan and pulled up.
    #
    # Returns { :corner => min corner (world), :axes => [ax, ay, az],
    #           :size => [x, y, z] }, or nil without an anchor.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__BoxFrame(origin, plane_key, u_len, v_len, d_len)
        return nil unless origin

        near       = Na__InsertPrimatives.Na__DrawnGrid__BuildRectPoints(origin, plane_key, u_len, v_len)
        far        = Na__InsertPrimatives.Na__DrawnGrid__OffsetPointsAlongNormal(near, plane_key, d_len)
        ax, ay, az = Na__InsertPrimatives.Na__DrawnGrid__AxisVectors

        xs = []
        ys = []
        zs = []

        (near + far).each do |point|
            travel = point - origin
            xs << travel.dot(ax).to_f
            ys << travel.dot(ay).to_f
            zs << travel.dot(az).to_f
        end

        corner = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(origin, ax, xs.min)
        corner = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(corner, ay, ys.min)
        corner = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(corner, az, zs.min)

        {
            :corner => corner,
            :axes   => [ax, ay, az],
            :size   => [xs.max - xs.min, ys.max - ys.min, zs.max - zs.min]
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does the Block Have Width, Depth and Height?
    # ------------------------------------------------------------
    def self.Na__DrawnStair__BoxUsable?(box)
        return false unless box && box[:size]

        box[:size].all? { |extent| Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(extent) }
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Point Given in the Block's Own (x, y, z) from Its Min Corner
    # ------------------------------------------------------------
    def self.Na__DrawnStair__BoxPoint(box, x, y, z)
        ax, ay, az = box[:axes]

        point = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(box[:corner], ax, x)
        point = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point,        ay, y)
        Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, az, z)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Block's Bottom and Top Rectangles, Corner for Corner
    # Returned as [bottom, top] so they drop straight into DrawFilledBox.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__BoxRects(box)
        size_x, size_y, size_z = box[:size]

        bottom = [
            Na__InsertPrimatives.Na__DrawnStair__BoxPoint(box, 0.0,    0.0,    0.0),
            Na__InsertPrimatives.Na__DrawnStair__BoxPoint(box, size_x, 0.0,    0.0),
            Na__InsertPrimatives.Na__DrawnStair__BoxPoint(box, size_x, size_y, 0.0),
            Na__InsertPrimatives.Na__DrawnStair__BoxPoint(box, 0.0,    size_y, 0.0)
        ]

        [bottom, Na__InsertPrimatives.Na__DrawnGrid__OffsetPointsAlongNormal(bottom, :xy, size_z)]
    end
    # ---------------------------------------------------------------

    # FUNCTION | All Eight Corners of the Block
    # ------------------------------------------------------------
    def self.Na__DrawnStair__BoxCorners(box)
        return [] unless box

        bottom, top = Na__InsertPrimatives.Na__DrawnStair__BoxRects(box)
        bottom + top
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Side Frames
    # -----------------------------------------------------------------------------

    # FUNCTION | Everything a Flight Rising From One Side Needs to Know
    # ------------------------------------------------------------
    # The frame is the side's own coordinate system:
    #   :corner   the bottom corner where the side's top edge STARTS (world)
    #   :along    runs the width of the stair, along the chosen edge
    #   :inward   runs the flight, square into the block
    #   :up       the drawing axes' Z
    #   :width    the edge length, the stair's width
    #   :depth    how far the block reaches inward, the most a run can be
    #   :height   the block's height, which the steps divide evenly
    # plus the top edge's ends and midpoint, which the drag and the highlight
    # both need. The four sides wind the same way round, so a flight from any
    # of them is the same shape turned.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__SideFrame(box, side)
        return nil unless box

        ax, ay, az             = box[:axes]
        size_x, size_y, size_z = box[:size]

        case side
        when :x_max
            start  = [size_x, 0.0, 0.0]
            along  = ay
            inward = ax.reverse
            width  = size_y
            depth  = size_x
        when :y_max
            start  = [size_x, size_y, 0.0]
            along  = ax.reverse
            inward = ay.reverse
            width  = size_x
            depth  = size_y
        when :x_min
            start  = [0.0, size_y, 0.0]
            along  = ay.reverse
            inward = ax
            width  = size_y
            depth  = size_x
        else
            side   = :y_min
            start  = [0.0, 0.0, 0.0]
            along  = ax
            inward = ay
            width  = size_x
            depth  = size_y
        end

        corner    = Na__InsertPrimatives.Na__DrawnStair__BoxPoint(box, start[0], start[1], start[2])
        top_start = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(corner,    az,    size_z)
        top_end   = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(top_start, along, width)
        top_mid   = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(top_start, along, width * 0.5)

        {
            :side      => side,
            :corner    => corner,
            :along     => along,
            :inward    => inward,
            :up        => az,
            :width     => width.to_f,
            :depth     => depth.to_f,
            :height    => size_z.to_f,
            :top_start => top_start,
            :top_end   => top_end,
            :top_mid   => top_mid
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Point in a Side's Frame: a Inward, b Up, e Along the Width
    # ------------------------------------------------------------
    def self.Na__DrawnStair__FramePoint(frame, a, b, e = 0.0)
        point = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(frame[:corner], frame[:inward], a)
        point = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point,          frame[:up],     b)
        Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, frame[:along], e)
    end
    # ---------------------------------------------------------------

    # FUNCTION | A List of (a, b) Pairs at One Station Along the Width
    # ------------------------------------------------------------
    def self.Na__DrawnStair__ToWorld(frame, pairs, e = 0.0)
        pairs.map { |a, b| Na__InsertPrimatives.Na__DrawnStair__FramePoint(frame, a, b, e) }
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Chosen Side's Face as a Quad (World)
    # ------------------------------------------------------------
    def self.Na__DrawnStair__SideFaceWorld(frame)
        [
            Na__InsertPrimatives.Na__DrawnStair__FramePoint(frame, 0.0, 0.0,             0.0),
            Na__InsertPrimatives.Na__DrawnStair__FramePoint(frame, 0.0, 0.0,             frame[:width]),
            Na__InsertPrimatives.Na__DrawnStair__FramePoint(frame, 0.0, frame[:height],  frame[:width]),
            Na__InsertPrimatives.Na__DrawnStair__FramePoint(frame, 0.0, frame[:height],  0.0)
        ]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Picking a Side on Screen
    # -----------------------------------------------------------------------------
    #
    # The block is still only a preview, so there is nothing in the model to
    # pick. The four sides are projected with View#screen_coords and the cursor
    # is tested against them in screen space instead:
    #   1  a side facing the camera with the cursor on it
    #   2  otherwise, the side whose TOP edge is nearest the cursor
    # The first lets the side be pointed at anywhere on its face; the second is
    # what makes the top edge work from above, where no side faces the camera
    # at all, and it is the gesture the tool was specified with.
    # -----------------------------------------------------------------------------

    # FUNCTION | Which Side the Cursor Is Asking For
    # Returns a side key, or nil when nothing could be projected.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__PickSide(view, box, x, y)
        return nil unless view && box

        cursor = Geom::Point3d.new(x.to_f, y.to_f, 0.0)
        frames = NA_DRAWN_STAIR_SIDE_KEYS.map { |side| Na__InsertPrimatives.Na__DrawnStair__SideFrame(box, side) }

        frames.each do |frame|
            next unless Na__InsertPrimatives.Na__DrawnStair__SideFacesCamera?(view, frame)

            quad = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(
                view, Na__InsertPrimatives.Na__DrawnStair__SideFaceWorld(frame)
            )
            next unless quad

            return frame[:side] if Geom.point_in_polygon_2D(cursor, quad, true)
        end

        nearest      = nil
        nearest_dist = nil

        frames.each do |frame|
            ends = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, [frame[:top_start], frame[:top_end]])
            next unless ends

            distance = Na__InsertPrimatives.Na__DrawnStair__ScreenSegmentDistance(cursor, ends[0], ends[1])
            next if nearest_dist && distance >= nearest_dist

            nearest      = frame[:side]
            nearest_dist = distance
        end

        nearest
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is This Side Turned Towards the Camera?
    # A side's outward normal points away from the flight, so it is the
    # inward vector reversed.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__SideFacesCamera?(view, frame)
        camera  = view.camera
        outward = frame[:inward].reverse
        centre  = Na__InsertPrimatives.Na__DrawnStair__FramePoint(frame, 0.0, frame[:height] * 0.5, frame[:width] * 0.5)

        if camera.perspective?
            (centre - camera.eye).dot(outward) < 0.0
        else
            camera.direction.dot(outward) < 0.0
        end
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Screen Distance from a Point to a Segment
    # ------------------------------------------------------------
    def self.Na__DrawnStair__ScreenSegmentDistance(point, seg_a, seg_b)
        dx     = seg_b.x.to_f - seg_a.x.to_f
        dy     = seg_b.y.to_f - seg_a.y.to_f
        length = (dx * dx) + (dy * dy)

        t = length > 0.0 ? (((point.x.to_f - seg_a.x.to_f) * dx) + ((point.y.to_f - seg_a.y.to_f) * dy)) / length : 0.0
        t = 0.0 if t < 0.0
        t = 1.0 if t > 1.0

        off_x = point.x.to_f - (seg_a.x.to_f + (t * dx))
        off_y = point.y.to_f - (seg_a.y.to_f + (t * dy))
        Math.sqrt((off_x * off_x) + (off_y * off_y))
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Inward Drag
    # -----------------------------------------------------------------------------

    # FUNCTION | Where the Cursor Ray Meets the Flight's Drag Plane
    # ------------------------------------------------------------
    # Deep Chamfer's lesson, applied from the start: a ray projected onto a
    # LINE is ill-conditioned whenever the cursor is away from the line's
    # anchor, so grabbing a wide stair near one end would open with a phantom
    # run. A ray cut with a PLANE has no such regime, and motion along the
    # width contributes nothing to it. Two planes contain the inward direction:
    #   top      the block's top face. Whenever the camera is above it and
    #            looking down onto it, this is the one, because the landing
    #            edge then sits exactly under the cursor.
    #   profile  the side profile through the middle of the width. Used at eye
    #            level or below, where the top cannot be seen, and in a side
    #            elevation, where it is the drawing plane itself.
    # The choice is made from the CAMERA's direction rather than the ray's.
    # A perspective ray tilts as the cursor moves, and choosing per ray would
    # let the plane change mid-drag and the run jump with it.
    #
    # Returns the hit, or nil when there is nothing sensible to hit: both
    # planes edge-on (looking straight down the flight, where no run can be
    # seen) or the hit behind the eye. The caller then keeps the last good run.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__RunPlanePoint(view, x, y, frame)
        camera    = view.camera
        looking   = camera.direction
        up        = frame[:up]
        eye_above = (camera.eye - frame[:top_start]).dot(up) > 0.0
        downward  = looking.dot(up)

        top_plane     = [frame[:top_start], up]
        profile_plane = [frame[:top_mid], frame[:along]]

        plane =
            if eye_above && downward < -NA_DRAWN_STAIR_TOP_FACING
                top_plane
            elsif looking.dot(frame[:along]).abs >= NA_DRAWN_STAIR_GRAZING
                profile_plane
            elsif downward.abs >= NA_DRAWN_STAIR_GRAZING
                top_plane
            end
        return nil unless plane

        ray = view.pickray(x, y)
        hit = Geom.intersect_line_plane(ray, plane)
        return nil unless hit
        return nil unless (hit - ray[0]).dot(ray[1]) > 0.0                   # <-- Behind the eye is no answer at all

        hit
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Step Count
    # -----------------------------------------------------------------------------

    # FUNCTION | The Rise the Next Stair Aims For
    # The last stair built, or 175mm before there is one — a comfortable
    # dwelling rise. Held for the session only: a garden step built this
    # morning should not set every stair drawn next week.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__TargetRise
        remembered = @na_drawn_stair_target_rise.to_f
        remembered >= NA_DRAWN_STAIR_MIN_RISE.to_f ? remembered : NA_DRAWN_STAIR_DEFAULT_RISE.to_f
    end
    # ---------------------------------------------------------------

    # FUNCTION | Remember the Rise of the Stair Just Built
    # ------------------------------------------------------------
    def self.Na__DrawnStair__RememberRise(rise)
        return unless rise.to_f >= NA_DRAWN_STAIR_MIN_RISE.to_f

        @na_drawn_stair_target_rise = rise.to_f
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Most Risers a Height Can Be Divided Into
    # ------------------------------------------------------------
    def self.Na__DrawnStair__MaxSteps(height)
        most = (height.to_f.abs / NA_DRAWN_STAIR_MIN_RISE.to_f).floor
        most < NA_DRAWN_STAIR_MIN_STEPS ? NA_DRAWN_STAIR_MIN_STEPS : most
    end
    # ---------------------------------------------------------------

    # FUNCTION | Hold a Step Count Inside What a Height Can Take
    # ------------------------------------------------------------
    def self.Na__DrawnStair__ClampSteps(count, height)
        wanted = count.to_i
        wanted = NA_DRAWN_STAIR_MIN_STEPS if wanted < NA_DRAWN_STAIR_MIN_STEPS

        most = Na__InsertPrimatives.Na__DrawnStair__MaxSteps(height)
        wanted > most ? most : wanted
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Step Count a Fresh Block Opens With
    # ------------------------------------------------------------
    def self.Na__DrawnStair__DefaultSteps(height)
        count = (height.to_f.abs / Na__InsertPrimatives.Na__DrawnStair__TargetRise).round
        Na__InsertPrimatives.Na__DrawnStair__ClampSteps(count, height)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Even-Step Solve
    # -----------------------------------------------------------------------------

    # FUNCTION | Every Number the Flight Is Made Of
    # ------------------------------------------------------------
    # The run is held inside the block: never negative, never past the far
    # face, and snapped onto the far face when it falls within the merge
    # tolerance of it, so a landing a fraction of a millimetre deep never
    # reaches the builder.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__Solve(frame, steps, height, run)
        count  = steps.to_i
        count  = NA_DRAWN_STAIR_MIN_STEPS if count < NA_DRAWN_STAIR_MIN_STEPS
        depth  = frame[:depth].to_f
        rise_h = height.to_f.abs

        flight = run.to_f
        flight = 0.0   if flight < 0.0
        flight = depth if flight > depth - NA_DRAWN_STAIR_MERGE_TOL.to_f

        rise  = rise_h / count
        going = flight / (count - 1)
        pitch = going > NA_DRAWN_STAIR_LOOP_TOL ? Math.atan2(rise, going) * 180.0 / Math::PI : 90.0

        {
            :steps   => count,
            :rise    => rise,
            :going   => going,
            :height  => rise_h,
            :run     => flight,
            :depth   => depth,
            :landing => depth - flight,
            :width   => frame[:width].to_f,
            :pitch   => pitch
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Solve From a Stair State — Exact Values Where They Were Typed
    # ------------------------------------------------------------
    # The state is what the user has decided: a step count, a run from the
    # drag, and optionally an exact rise and an exact going. An exact rise
    # sets the height (risers x rise); an exact going sets the run
    # (goings x going). Everything else interpolates evenly between the
    # bottom and the top of the block.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__Derive(frame, state)
        steps  = state[:steps].to_i
        steps  = NA_DRAWN_STAIR_MIN_STEPS if steps < NA_DRAWN_STAIR_MIN_STEPS
        height = state[:rise_strict]  ? steps * state[:rise_strict].to_f        : frame[:height].to_f
        run    = state[:going_strict] ? (steps - 1) * state[:going_strict].to_f : state[:run].to_f

        Na__InsertPrimatives.Na__DrawnStair__Solve(frame, steps, height, run)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Why a Solve Cannot Be Built, or nil When It Can
    # ------------------------------------------------------------
    def self.Na__DrawnStair__BuildRefusal(solve)
        return 'Nothing to build yet' unless solve
        return 'The block has no width along that side' unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(solve[:width])
        return 'The block has no depth to climb into' unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(solve[:depth])

        if solve[:run] <= NA_DRAWN_STAIR_MERGE_TOL.to_f
            return 'Drag inward to give the flight a run — or type a pitch (35) or a going (250g)'
        end

        if solve[:going] < NA_DRAWN_STAIR_MIN_GOING.to_f
            return 'Each going would be under 1mm — drag further inward, or take a step away with DOWN'
        end

        return 'The steps have no rise' unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(solve[:rise])

        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Say So When an Exact Rise Moved the Top of the Block
    # ------------------------------------------------------------
    def self.Na__DrawnStair__HeightNote(frame, solve)
        return nil unless frame && solve

        difference = solve[:height].to_f - frame[:height].to_f
        return nil if difference.abs < NA_DRAWN_STAIR_MERGE_TOL.to_f

        "Flight rises #{Na__InsertPrimatives.Na__DrawnStair__FormatMm(solve[:height])} — " \
        "#{Na__InsertPrimatives.Na__DrawnStair__FormatMm(difference)} #{difference > 0.0 ? 'above' : 'below'} the block drawn. "
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Step Profile
    # -----------------------------------------------------------------------------

    # FUNCTION | The Closed Step Profile as (a, b) Pairs
    # ------------------------------------------------------------
    # From the foot of the chosen side: up the first riser, along the first
    # tread, and so on to the top of the last tread in the flight; then up the
    # top riser, across the landing, down the far face and back along the base.
    # With no landing the top riser would run straight back down the far face,
    # so it is left out and the far face closes the last tread instead.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__ProfileLocal(solve)
        count = solve[:steps]
        rise  = solve[:rise]
        going = solve[:going]

        points = [[0.0, 0.0]]

        (1...count).each do |index|
            points << [(index - 1) * going, index * rise]
            points << [index * going,       index * rise]
        end

        if solve[:landing] > NA_DRAWN_STAIR_MERGE_TOL.to_f
            points << [solve[:run],   solve[:height]]
            points << [solve[:depth], solve[:height]]
        end

        points << [solve[:depth], 0.0]

        Na__InsertPrimatives.Na__DrawnStair__CleanLoop(points)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Drop Repeated and Collinear Points from a Closed Profile
    # ------------------------------------------------------------
    # Every segment of a step profile is vertical or horizontal, so three
    # points in a line share an a or share a b. A run of zero stacks every
    # riser into one wall, and this is what folds them back into a single
    # edge before add_face ever sees them.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__CleanLoop(points)
        tolerance = NA_DRAWN_STAIR_LOOP_TOL
        cleaned   = []

        points.each do |point|
            previous = cleaned.last
            next if previous && (previous[0] - point[0]).abs < tolerance && (previous[1] - point[1]).abs < tolerance

            cleaned << point
        end

        if cleaned.length > 1 &&
           (cleaned.first[0] - cleaned.last[0]).abs < tolerance &&
           (cleaned.first[1] - cleaned.last[1]).abs < tolerance
            cleaned.pop
        end

        loop do
            count = cleaned.length
            break if count < 4

            index = (0...count).find do |i|
                before = cleaned[(i - 1) % count]
                here   = cleaned[i]
                after  = cleaned[(i + 1) % count]

                same_a = (before[0] - here[0]).abs < tolerance && (after[0] - here[0]).abs < tolerance
                same_b = (before[1] - here[1]).abs < tolerance && (after[1] - here[1]).abs < tolerance
                same_a || same_b
            end

            break unless index

            cleaned.delete_at(index)
        end

        cleaned
    end
    # ---------------------------------------------------------------

    # FUNCTION | The End Profile Cut into Rectangles, for Filling the Preview
    # ------------------------------------------------------------
    # The profile is concave, and a triangle fan over it would fill the air
    # above the steps. One rectangle per step, plus the landing, covers it
    # exactly and never overlaps, so the translucent fill does not stack.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__ColumnsLocal(solve)
        columns = []

        (1...solve[:steps]).each do |index|
            left  = (index - 1) * solve[:going]
            right = index * solve[:going]
            next if right - left < NA_DRAWN_STAIR_LOOP_TOL

            top = index * solve[:rise]
            columns << [[left, 0.0], [right, 0.0], [right, top], [left, top]]
        end

        if solve[:landing] > NA_DRAWN_STAIR_MERGE_TOL.to_f
            columns << [
                [solve[:run],   0.0],
                [solve[:depth], 0.0],
                [solve[:depth], solve[:height]],
                [solve[:run],   solve[:height]]
            ]
        end

        columns
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Pitch Line Through the Nosings, at One Station
    # From the first nosing (the top of the first riser) to the last (the edge
    # of the landing), which is exactly the line the pitch is measured along.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__NosingLine(frame, solve, e = 0.0)
        [
            Na__InsertPrimatives.Na__DrawnStair__FramePoint(frame, 0.0,         solve[:rise],   e),
            Na__InsertPrimatives.Na__DrawnStair__FramePoint(frame, solve[:run], solve[:height], e)
        ]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Part K Check
    # -----------------------------------------------------------------------------

    # FUNCTION | Check a Solve Against the Part K Private Stair Limits
    # ------------------------------------------------------------
    # A readout, not a gate: garden steps and loft ladders are drawn with this
    # tool too, and neither is a Part K private stair. The failures are listed
    # worst-first in the order a building control officer would read them.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__PartK(solve)
        rules    = NA_DRAWN_STAIR_PARTK_RULES
        rise_mm  = solve[:rise].to_f  * NA_DRAWN_INCH_TO_MM
        going_mm = solve[:going].to_f * NA_DRAWN_INCH_TO_MM
        two_r_g  = (2.0 * rise_mm) + going_mm
        slack    = 0.05
        failures = []
        fmt      = lambda { |value| Na__InsertPrimatives.Na__DrawnStair__FormatMmValue(value) }

        failures << "rise #{fmt.call(rise_mm)} over #{fmt.call(rules[:rise_max])}"     if rise_mm  > rules[:rise_max]  + slack
        failures << "going #{fmt.call(going_mm)} under #{fmt.call(rules[:going_min])}" if going_mm < rules[:going_min] - slack
        failures << "pitch #{Na__InsertPrimatives.Na__DrawnFormat__Degrees(solve[:pitch])}° over #{fmt.call(rules[:pitch_max])}°" if solve[:pitch].to_f > rules[:pitch_max] + slack
        failures << "2R+G #{fmt.call(two_r_g)} under #{fmt.call(rules[:two_r_g_min])}" if two_r_g  < rules[:two_r_g_min] - slack
        failures << "2R+G #{fmt.call(two_r_g)} over #{fmt.call(rules[:two_r_g_max])}"  if two_r_g  > rules[:two_r_g_max] + slack
        failures << "rise #{fmt.call(rise_mm)} under #{fmt.call(rules[:rise_min])}"    if rise_mm  < rules[:rise_min]  - slack
        failures << "going #{fmt.call(going_mm)} over #{fmt.call(rules[:going_max])}"  if going_mm > rules[:going_max] + slack

        { :ok => failures.empty?, :failures => failures, :two_r_g => two_r_g }
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Line Describing a Part K Result
    # ------------------------------------------------------------
    def self.Na__DrawnStair__PartKText(partk, short = false)
        rules = NA_DRAWN_STAIR_PARTK_RULES
        label = short ? rules[:short_label] : rules[:label]

        return "#{label} OK · 2R+G #{Na__InsertPrimatives.Na__DrawnStair__FormatMmValue(partk[:two_r_g])}" if partk[:ok]

        shown = partk[:failures].first(2).join(' · ')
        extra = partk[:failures].length > 2 ? " (+#{partk[:failures].length - 2} more)" : ''
        "#{label}: #{shown}#{extra}"
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Solid Construction
    # -----------------------------------------------------------------------------

    # FUNCTION | Add the Step Profile and Push It Across the Width
    # ------------------------------------------------------------
    # The profile is laid on the plane of one end of the stair and pushed the
    # width of the chosen side, which is exactly how the volume builds its
    # box. The pushpull sign comes from the normal SketchUp actually gave the
    # face, so the solid always grows along the edge that was picked.
    # Returns true once the solid is in.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__AddSolid(entities, frame, solve)
        profile = Na__InsertPrimatives.Na__DrawnStair__ToWorld(
            frame, Na__InsertPrimatives.Na__DrawnStair__ProfileLocal(solve), 0.0
        )
        return false if profile.length < 3

        face = entities.add_face(profile)
        return false unless face

        width = frame[:width].to_f
        push  = face.normal.dot(frame[:along]) >= 0.0 ? width : -width

        face.pushpull(push)
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create a Drawn Staircase Group
    # ------------------------------------------------------------
    # One operation, so one Ctrl+Z takes the whole stair back to nothing. A
    # failure anywhere inside aborts the operation rather than leaving a half
    # built group behind.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__CreateStair(frame, solve)
        return nil unless frame && solve
        return nil if Na__InsertPrimatives.Na__DrawnStair__BuildRefusal(solve)

        model = Sketchup.active_model
        return nil unless model

        entities = model.active_entities
        model.start_operation('Draw Staircase Primitive', true)

        begin
            group      = entities.add_group
            group.name = NA_DRAWN_STAIR_GROUP_NAME
            Na__InsertPrimatives.Na__DrawnGeom__PinGroupToWorld(group)       # <-- Global points into a closed group: see DrawnGeometry

            unless Na__InsertPrimatives.Na__DrawnStair__AddSolid(group.entities, frame, solve)
                model.abort_operation
                return nil
            end

            model.commit_operation
            group
        rescue StandardError => error
            model.abort_operation
            Na__InsertPrimatives.Na__Debug__Puts "STAIRCASE BUILD FAILED: #{error.class}: #{error.message}"
            nil
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Rebuild an Existing Drawn Staircase Group in Place
    # ------------------------------------------------------------
    def self.Na__DrawnStair__RebuildStair(group, frame, solve)
        return false unless group && group.valid? && frame && solve
        return false if Na__InsertPrimatives.Na__DrawnStair__BuildRefusal(solve)

        model = Sketchup.active_model
        return false unless model

        model.start_operation('Adjust Drawn Staircase', true)

        begin
            group.transformation = Geom::Transformation.new
            group.entities.clear!

            unless Na__InsertPrimatives.Na__DrawnStair__AddSolid(group.entities, frame, solve)
                model.abort_operation
                return false
            end

            model.commit_operation
            true
        rescue StandardError => error
            model.abort_operation
            Na__InsertPrimatives.Na__Debug__Puts "STAIRCASE REBUILD FAILED: #{error.class}: #{error.message}"
            false
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN STAIR GEOMETRY MODULE
# =============================================================================
