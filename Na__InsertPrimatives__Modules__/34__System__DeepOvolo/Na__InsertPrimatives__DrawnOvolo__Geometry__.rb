# =============================================================================
# NA INSERT PRIMATIVES - DEEP OVOLO GEOMETRY
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnOvolo__Geometry__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : The ovolo and cavetto profiles (a quarter circle with a step),
#              their solve for one edge, their limits, and the reading of a
#              radius,step entry
# CREATED    : 2026
#
# DESCRIPTION:
# - The two quarter-circle mouldings of the classical set, each with the small
#   square STEP (the fillet, or quirk) a joiner leaves at each end of the arc.
#   Reading the corner, planning, building and mitring are shared with every
#   profile tool in 04__GeometryHelpers/Na__InsertPrimatives__DrawnProfileSweep__.rb.
# - Two values make one: the RADIUS of the quarter circle and the STEP. That is
#   what separates these from Deep Fillet, whose round-over and cove are the
#   same two arcs with no step.
#
# THE PROFILES — in the corner's own frame (u along face A into the material,
# w along face B), for a radius r and a step s, from face A to face B:
#
#   OVOLO (convex quarter round)      setback r + s on each face
#     (r+s, 0) -> (r+s, s)              the step, square off face A
#     quarter round, centre (r+s, r+s)  bulging toward the corner
#     (s, r+s) -> (0, r+s)              the step, square off face B
#
#   CAVETTO (concave quarter hollow)  setback r + 2s on each face
#     (r+2s, 0) -> (r+2s, s) -> (r+s, s)  the step: a riser, then a tread
#     quarter hollow, centre (s, s)        cut into the material
#     (s, r+s) -> (s, r+2s) -> (0, r+2s)   the step again
#
# - The ovolo's arc arrives parallel to each face, so one riser makes a
#   visible step (the OVOLO reference drawing). The cavetto's arc arrives
#   SQUARE to each face, where a lone riser would only carry the arc's own
#   line on to the face, so its step is a riser and a tread: the notch in the
#   college's cavetto joint template and on the cove router bit. With s = 0
#   the two reduce to Deep Fillet's round-over and cove.
#
# CORNERS THAT ARE NOT SQUARE:
# - Laid in the oblique frame of the two faces, as the ogee is, so every step
#   stays parallel to a face and the ends land on the faces at any angle.
#
# SHOULDERS STAY CRISP:
# - Every step corner is listed in :hard_seams, so the profile sweep softens
#   only the arc's own facets and the steps read as the sharp lines they are.
#
# A STEPPED PROFILE NEVER TAKES THE WHOLE FACE:
# - A chamfer or a fillet can be cut to the full thickness: the face it runs
#   across is consumed and dropped. A step at the full thickness would lie ON
#   the far face and cut into it, and the far face is not rebuilt, so a
#   stepped profile always leaves a 1 mm land on each face. With no step the
#   full thickness is allowed, exactly as Deep Fillet allows it.
#
# FACETS:
# - The quarter arc takes a quarter of the Circle Sides setting, as the ogee's
#   arcs do (24 -> 6 facets), never fewer than two; "48s" smooths it.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnProfileSweep__'
require_relative '../31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamfer__Limit__'
require_relative '../03__AppUtils/Na__InsertPrimatives__DrawnVcbArithmetic__'

module Na__InsertPrimatives

    # @delegate: ../04__GeometryHelpers/Na__InsertPrimatives__DrawnProfileSweep__.rb

    # -----------------------------------------------------------------------------
    # REGION | Ovolo Constants
    # -----------------------------------------------------------------------------

    NA_OVOLO_MIN_ARC_SEGMENTS = 2                                             # <-- Facets per quarter arc, at the least
    NA_OVOLO_POINT_TOL        = 1.0e-7                                        # <-- Inches; profile points this close are one point (a zero step)
    NA_OVOLO_LAND_MM          = 1.0                                           # <-- Of each face a stepped profile always leaves; see the header

    # "40r" or "r40": the radius, marked as the radius, so the next bare number
    # can be the step. Only ever reached after a digit has been typed — a bare
    # R on its own switches to Deep Fillet before the measurements box sees it.
    NA_OVOLO_RADIUS_SUFFIX    = /\A(.*\d.*?)\s*r\z/i
    NA_OVOLO_RADIUS_PREFIX    = /\Ar\s*(.*\d.*)\z/i

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Setbacks and Limits
    # -----------------------------------------------------------------------------

    # FUNCTION | How Many Steps' Worth of Setback a Kind Adds to Its Radius
    # ------------------------------------------------------------
    def self.Na__DrawnOvolo__StepCount(kind)
        kind == :cavetto ? 2 : 1
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Far Back Along Each Face a Radius and Step Reach
    # ------------------------------------------------------------
    def self.Na__DrawnOvolo__Setback(radius, step, kind)
        radius.to_f + (Na__InsertPrimatives.Na__DrawnOvolo__StepCount(kind) * [step.to_f, 0.0].max)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Land a Stepped Profile Leaves, in Inches
    # ------------------------------------------------------------
    def self.Na__DrawnOvolo__Land(step)
        step.to_f > NA_OVOLO_POINT_TOL ? NA_OVOLO_LAND_MM / NA_DRAWN_INCH_TO_MM : 0.0
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Largest Setback an Edge's Faces Allow, World Inches, or nil
    # The ovolo's reach does not grow in proportion to its radius — the step
    # is fixed — so the shared measure is asked about the SETBACK instead: a
    # profile reaching exactly one unit along each face, which is what
    # Na__DrawnChamfer__MaxSize reads as its rate.
    # ------------------------------------------------------------
    def self.Na__DrawnOvolo__MaxSetback(target)
        probe = Na__InsertPrimatives.Na__DrawnOvolo__Solve(target, 1.0, 0.0, :ovolo, NA_OVOLO_MIN_ARC_SEGMENTS)
        return nil unless probe

        Na__InsertPrimatives.Na__DrawnChamfer__MaxSize(target, probe)
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Largest Radius a Setback Leaves Room for Beside a Step
    # Zero or less when the step alone is more than the faces can take.
    # ------------------------------------------------------------
    def self.Na__DrawnOvolo__MaxRadius(max_setback, step, kind)
        return nil if max_setback.nil?

        max_setback.to_f - Na__InsertPrimatives.Na__DrawnOvolo__Land(step) -
            (Na__InsertPrimatives.Na__DrawnOvolo__StepCount(kind) * [step.to_f, 0.0].max)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Largest Step That Still Leaves Room for a Radius
    # ------------------------------------------------------------
    def self.Na__DrawnOvolo__MaxStep(max_setback, kind)
        return nil if max_setback.nil?

        room = max_setback.to_f - (NA_OVOLO_LAND_MM / NA_DRAWN_INCH_TO_MM)
        room > 0.0 ? room / Na__InsertPrimatives.Na__DrawnOvolo__StepCount(kind) : 0.0
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Radius Whose Arc Crosses the Bisector a Travel From the Corner
    # CTRL's vertex snap says how far along the bisector the inferred vertex
    # lies; the radius is the one whose quarter arc passes through that point.
    # In the oblique frame a point (p, p) sits 2p·cos(half) along the bisector.
    #   cavetto  the hollow crosses at (s + r/√2, s + r/√2)
    #   ovolo    the round crosses at (s + r(1 - 1/√2), ...)
    # ------------------------------------------------------------
    def self.Na__DrawnOvolo__RadiusFromTravel(travel, cos_half, step, kind)
        reach = 2.0 * cos_half.to_f.abs
        along = reach > 1.0e-9 ? travel.to_f / reach : travel.to_f
        rise  = along - [step.to_f, 0.0].max

        if kind == :cavetto
            rise * Math.sqrt(2.0)
        else
            rise / (1.0 - (1.0 / Math.sqrt(2.0)))
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Profile
    # -----------------------------------------------------------------------------

    # FUNCTION | The Profile in the Corner's Own Frame, With Its Shoulders
    # Returns [points, hard]: points are [u, w] from face A (setback, 0) to
    # face B (0, setback); hard lists the indices of points where the profile
    # turns a crisp corner — never the two ends, which sit on the faces. The
    # arc's own ends and the step corners are written exactly rather than
    # left to trigonometry, so the steps are square and the ends land on the
    # faces. A zero step collapses its points into the one they meet.
    # ------------------------------------------------------------
    def self.Na__DrawnOvolo__ProfileUW(radius, step, kind, arc_segments)
        r     = radius.to_f
        s     = [step.to_f, 0.0].max
        count = [arc_segments.to_i, NA_OVOLO_MIN_ARC_SEGMENTS].max
        quart = Math::PI * 0.5
        raw   = []                                                            # <-- [u, w, crisp]

        if kind == :cavetto
            t = r + (2.0 * s)
            raw << [t, 0.0, false] << [t, s, true] << [r + s, s, true]

            (1...count).each do |index|
                angle = quart * index / count                                 # <-- Centre (s, s): from (r+s, s) round to (s, r+s)
                raw << [s + (r * Math.cos(angle)), s + (r * Math.sin(angle)), false]
            end

            raw << [s, r + s, true] << [s, t, true] << [0.0, t, false]
        else
            t = r + s
            raw << [t, 0.0, false] << [t, s, true]

            (1...count).each do |index|
                angle = -quart - (quart * index / count)                      # <-- Centre (t, t): from (t, s) round to (s, t)
                raw << [t + (r * Math.cos(angle)), t + (r * Math.sin(angle)), false]
            end

            raw << [s, t, true] << [0.0, t, false]
        end

        points = []
        hard   = []

        raw.each do |u, w, crisp|
            last = points.last
            next if last && (last[0] - u).abs <= NA_OVOLO_POINT_TOL && (last[1] - w).abs <= NA_OVOLO_POINT_TOL

            hard << points.length if crisp
            points << [u, w]
        end

        hard.reject! { |index| index.zero? || index >= points.length - 1 }
        [points, hard]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Solve
    # -----------------------------------------------------------------------------

    # FUNCTION | Solve an Ovolo or Cavetto for One Edge at a World Radius and Step
    # Returns the shared profile solve (Na__ProfileSweep__SolveHash) plus
    #   :kind           :ovolo or :cavetto
    #   :symmetric      true — both profiles read the same from either face,
    #                   so any two meeting at a square corner mitre
    #   :hard_seams     the step shoulders, kept crisp by the sweep
    #   :facets         how many facets the whole profile has
    #   :radius_world   the radius it was solved at (also :size_world)
    #   :step_world     the step it was solved at
    #   :setback_world  how far back it reaches along each face
    # nil when the edge cannot carry a moulding — the chamfer's refusals.
    #
    # The world sizes become separate LOCAL distances along each face
    # direction, from the instance scale that way, so the moulding keeps its
    # proportions in world space inside a non-uniformly scaled component.
    # ------------------------------------------------------------
    def self.Na__DrawnOvolo__Solve(target, radius_world, step_world, kind = :ovolo, arc_segments = NA_OVOLO_MIN_ARC_SEGMENTS)
        frame = Na__InsertPrimatives.Na__ProfileSweep__CornerFrame(target)
        return nil unless frame

        radius = radius_world.to_f
        step   = [step_world.to_f, 0.0].max
        kind   = kind == :cavetto ? :cavetto : :ovolo
        return nil unless radius > 0.0

        profile_uw, hard = Na__InsertPrimatives.Na__DrawnOvolo__ProfileUW(radius, step, kind, arc_segments)

        lay = lambda do |corner|
            profile_uw.map do |u, w|
                along = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(corner, frame[:dir_a], u / frame[:scale_a])
                Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(along, frame[:dir_b], w / frame[:scale_b])
            end
        end

        Na__InsertPrimatives.Na__ProfileSweep__SolveHash(
            frame, target, lay.call(frame[:v0]), lay.call(frame[:v1]),
            {
                :kind          => kind,
                :symmetric     => true,
                :hard_seams    => hard,
                :facets        => profile_uw.length - 1,
                :radius_world  => radius,
                :size_world    => radius,
                :step_world    => step,
                :setback_world => Na__InsertPrimatives.Na__DrawnOvolo__Setback(radius, step, kind)
            }
        )
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Reading a Radius, Step Entry
    # -----------------------------------------------------------------------------

    # FUNCTION | Read an Ovolo Entry: a Radius, a Step, or Both
    # ------------------------------------------------------------
    #   "40,5"   radius 40 and step 5
    #   "40"     radius 40, the step as it is
    #   "40r"    radius 40, MARKED as the radius: the step is still to come
    #   ",5"     step 5, the radius as it is
    #   "40,"    radius 40
    # Signs work on either value, against the live one ("+5", ",-1"). Returns
    #   { :radius => token or nil, :step => token or nil, :marked => true/false }
    # where a token is the shared [sign, inches] pair. Raises ArgumentError
    # for anything it cannot read, naming the form it expects.
    # ------------------------------------------------------------
    def self.Na__DrawnOvolo__ParseEntry(text)
        parts = text.to_s.split(',', -1)
        raise ArgumentError, 'no value entered' if parts.empty?
        raise ArgumentError, 'type a radius and a step, e.g. 40,5 — or 40r then 5' if parts.length > 2

        radius_text = parts[0].to_s.strip
        marked      = false

        if (match = NA_OVOLO_RADIUS_SUFFIX.match(radius_text) || NA_OVOLO_RADIUS_PREFIX.match(radius_text))
            radius_text = match[1].to_s.strip
            marked      = true
        end

        radius = Na__InsertPrimatives.Na__DrawnVcb__ParseToken(radius_text)
        step   = parts.length > 1 ? Na__InsertPrimatives.Na__DrawnVcb__ParseToken(parts[1]) : nil
        raise ArgumentError, 'no value entered — type a radius and a step, e.g. 40,5' if radius.nil? && step.nil?

        { :radius => radius, :step => step, :marked => marked && parts.length == 1 }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP OVOLO GEOMETRY
# =============================================================================
