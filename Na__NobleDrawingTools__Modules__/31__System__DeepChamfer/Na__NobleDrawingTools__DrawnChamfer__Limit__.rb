# =============================================================================
# NA NOBLE DRAWING TOOLS - DEEP CHAMFER SIZE LIMIT
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnChamfer__Limit__.rb
# NAMESPACE  : Na__NobleDrawingTools / Na__NobleDrawingTools::DrawnChamferLimit
# AUTHOR     : Noble Architecture
# PURPOSE    : The largest cut an edge's faces can take, and a typed size
#              refused above it
# CREATED    : 2026
#
# DESCRIPTION:
# - A chamfer, fillet or ogee eats back into both faces of its edge. The face
#   runs back from the edge only so far, the thickness of a board or a wall,
#   and a cut deeper than that has nowhere to land. The drag used to follow
#   the cursor without limit, so it was easy to overshoot, and a cut past the
#   face could not be built at all.
# - The REACH of each face is measured: from the edge, straight across the face
#   (perpendicular to the edge, in world units), to the nearest part of the
#   face's boundary that lies alongside the edge. Anything beyond either end of
#   the edge does not count, so an L-shaped top face is measured across its
#   own strip, not along its other leg. The largest size is the one whose cut
#   just reaches the nearer of the two faces' reach, read through the tool's
#   own solve so a chamfer, a round, a cove and an ogee each get their own
#   answer. A batch takes the smallest of its edges.
# - The band alongside the edge is the edge's own length, exactly (5.2.36).
#   It used to be padded by a hair past both ends, and a hip leaving the end
#   of a ridge at a shallow rake slipped a sliver into the padding that
#   counted as the face's nearest boundary: the Corrett roof's ridges
#   measured 0.17 mm, so the drag never opened and every typed size was
#   refused. Only an end edge square to the edge is still taken whole.
#
# THE MATERIAL BEHIND THE EDGE IS MEASURED TOO (5.2.36):
# - Faces A and B say nothing about how thick the material is behind them.
#   A roof modelled as a shell (an 85 mm thatch slab over an attic) has two
#   long slopes at its ridge and its underside a hand's width below, and a
#   round sized by the slopes alone runs straight through into the attic.
#   So rays are sounded into the material from three points along the edge,
#   toward every point of the profile, and the first face they meet caps the
#   size too. See the Material region below.
#
# THE DRAG RUNS UP TO THE LIMIT:
# - 5.1.18 eased the corner drag into it with a tanh curve. Since 5.1.22 the
#   drag is a vertical scrub that opens at 25% of this limit and eases onto
#   100% without passing it — see DrawnChamferScrub. CTRL's vertex snap is
#   left absolute (a vertex is a vertex) and only clamped.
#
# THE FULL SIZE BUILDS:
# - At 100% the face the cut runs across is consumed whole. The rebuild drops
#   such a face instead of trying to re-add a strip of no width; see
#   Na__DrawnChamfer__CleanLoop in the chamfer geometry.
#
# TYPED SIZES ARE REFUSED ABOVE IT, WITH THE LIMIT NAMED:
# - Mid-drag, and when retyping a cut already made. Never clamped silently.
#
# =============================================================================

require 'sketchup.rb'

module Na__NobleDrawingTools

    # -----------------------------------------------------------------------------
    # REGION | Limit Constants
    # -----------------------------------------------------------------------------

    NA_CHAMFER_REACH_TOL = 0.004                                              # <-- Inches (~0.1mm); boundary this close to the edge line is the edge itself
    NA_CHAMFER_LIMIT_TOL = 0.004                                              # <-- Inches; a typed size this far over the limit is still the limit

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Measuring a Face
    # -----------------------------------------------------------------------------

    # FUNCTION | How Far a Face Runs Back From an Edge, in World Inches, or nil
    # ------------------------------------------------------------
    # Every boundary segment of the face (holes included) is clipped to the
    # band alongside the edge (0 to the edge's length, measured along it). The
    # distance across the face is linear along a segment, so the nearest point
    # of what is left is one of its ends. Points on the edge's own line are the
    # edge and its end edges setting off, and are skipped.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__FaceReach(face, xform, origin, along, length, inward)
        nearest = nil

        face.loops.each do |loop|
            points = loop.vertices.map { |vertex| vertex.position.transform(xform) }
            count  = points.length

            points.each_with_index do |start, index|
                finish = points[(index + 1) % count]

                Na__NobleDrawingTools.Na__DrawnChamfer__ClipToBand(start, finish, origin, along, length).each do |point|
                    across = (point - origin).dot(inward).to_f
                    next if across <= NA_CHAMFER_REACH_TOL

                    nearest = across if nearest.nil? || across < nearest
                end
            end
        end

        nearest
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Ends of a Segment's Piece Lying Alongside the Edge
    # Returns zero or two points.
    #
    # Clipped to the edge's own length EXACTLY. The tolerance only decides
    # whether a segment is an end edge square to the edge (it lies wholly
    # within the tolerance of one end, float noise and all), which is taken
    # whole. Padding the band for every segment let a hip or valley raking
    # back past the end leave a sliver inside the padding whose distance
    # across the face is the tolerance times the cotangent of its rake: more
    # than the tolerance under 45 degrees, so it won as the face's reach.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__ClipToBand(start, finish, origin, along, length)
        s_start = (start - origin).dot(along).to_f
        s_end   = (finish - origin).dot(along).to_f
        span    = s_end - s_start
        low     = 0.0
        high    = length.to_f

        if span.abs < 1.0e-9
            return (s_start >= low - NA_CHAMFER_REACH_TOL && s_start <= high + NA_CHAMFER_REACH_TOL) ? [start, finish] : []
        end

        [low, high].each do |end_along|
            next unless (s_start - end_along).abs <= NA_CHAMFER_REACH_TOL && (s_end - end_along).abs <= NA_CHAMFER_REACH_TOL

            return [start, finish]                                            # <-- An end edge square to the edge: all of it lies alongside
        end

        t_low  = (low  - s_start) / span
        t_high = (high - s_start) / span
        t_min  = [[t_low, t_high].min, 0.0].max
        t_max  = [[t_low, t_high].max, 1.0].min
        return [] if t_min > t_max

        step = finish - start
        [
            Na__NobleDrawingTools.Na__DrawnGrid__OffsetPoint(start, step, t_min),
            Na__NobleDrawingTools.Na__DrawnGrid__OffsetPoint(start, step, t_max)
        ]
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Largest Size an Edge Can Take, in the Tool's Own Size Units
    # ------------------------------------------------------------
    # probe is the tool's solve at size 1 (without stops). Its a and b points
    # say how far the cut reaches across face A and face B per unit of size,
    # whatever the profile, and each face's reach divided by that rate is the
    # size that just consumes it. The material behind the edge caps it too
    # (Na__DrawnChamfer__DepthSize). nil when nothing could be measured.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__MaxSize(target, probe)
        return nil unless target && probe && probe[:world]

        world  = probe[:world]
        origin = world[:v0]
        edge   = world[:v1] - origin
        length = edge.length.to_f
        return nil if length <= 0.0

        along = edge.normalize
        xform = target[:transformation] || Geom::Transformation.new
        faces = target[:faces] || []
        sizes = []

        [[faces[0], world[:a0]], [faces[1], world[:b0]]].each do |face, cut_point|
            next unless face && face.valid? && cut_point

            offset = cut_point - origin
            across = Geom::Vector3d.new(
                offset.x.to_f - (along.x.to_f * offset.dot(along).to_f),
                offset.y.to_f - (along.y.to_f * offset.dot(along).to_f),
                offset.z.to_f - (along.z.to_f * offset.dot(along).to_f)
            )
            rate = across.length.to_f
            next if rate <= 1.0e-9

            reach = Na__NobleDrawingTools.Na__DrawnChamfer__FaceReach(face, xform, origin, along, length, across.normalize)
            sizes << (reach / rate) if reach
        end

        faces_allow = sizes.min
        depth_allow = Na__NobleDrawingTools.Na__DrawnChamfer__DepthSize(target, probe, faces_allow)

        [faces_allow, depth_allow].compact.min
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Measuring the Material Behind the Edge
    # -----------------------------------------------------------------------------
    #
    # The cut removes exactly what lies between the corner and its profile, so
    # it breaks through only if a face of the material lies in that region.
    # From three points along the edge a ray runs from the corner toward every
    # point of the profile at size 1, and toward the middle of every flat facet
    # between them (a chamfer is one facet, whose middle is the deepest point
    # it reaches). The first face of the edge's own context that a ray meets,
    # A and B aside, is the far side of the material in that direction, and the
    # size at which that profile point would reach it is the most that
    # direction allows. On a box this never says less than the faces do: a ray
    # running along face B meets the bottom face exactly where face B's reach
    # ends. On a shell roof the ray under the ridge meets the slab's underside.
    #
    # Everything is in the space the edge REPORTS, like the probe. Along one
    # ray every length scales by the same factor under any instance scale, so
    # the ratio is the size in world units whatever the nesting. Faces farther
    # off than the faces' own limit allows are skipped before any ray is cast,
    # and a context with more faces than NA_CHAMFER_DEPTH_MAX_FACES is not
    # sounded at all, so a grab never stalls on a huge mesh.
    # -----------------------------------------------------------------------------

    NA_CHAMFER_DEPTH_STATIONS  = [0.25, 0.5, 0.75].freeze                     # <-- Fractions along the edge the material is sounded at
    NA_CHAMFER_DEPTH_MIN_HIT   = 0.01                                         # <-- Inches (~0.25 mm); a face met this close to the arris is the arris
    NA_CHAMFER_DEPTH_MAX_FACES = 20000                                        # <-- More faces than this in the context: not sounded
    NA_CHAMFER_DEPTH_MARGIN    = 1.25                                         # <-- Look this far past the faces' own limit for the far side
    NA_CHAMFER_DEPTH_HITS      = [
        Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex
    ].freeze

    # FUNCTION | The Largest Size Before the Cut Breaks Through, or nil
    # ------------------------------------------------------------
    # probe is the tool's solve at size 1, in the space the edge reports.
    # bound is the size the faces allow, used only to skip faces too far away
    # to matter. nil when nothing behind the edge is met.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__DepthSize(target, probe, bound = nil)
        edge = target[:edge]
        return nil unless edge && edge.valid? && probe && probe[:v0] && probe[:v1]

        parent = edge.parent
        return nil unless parent.respond_to?(:entities)

        faces = parent.entities.grep(Sketchup::Face) - (target[:faces] || [])
        return nil if faces.empty? || faces.length > NA_CHAMFER_DEPTH_MAX_FACES

        corner  = probe[:v0]
        heading = probe[:v1] - corner
        return nil unless heading.length.to_f > 0.0

        rays = Na__NobleDrawingTools.Na__DrawnChamfer__DepthRays(probe, corner)
        return nil if rays.empty?

        stations = NA_CHAMFER_DEPTH_STATIONS.map do |share|
            Na__NobleDrawingTools.Na__DrawnGrid__OffsetPoint(corner, heading, share)
        end

        if bound && bound.to_f > 0.0
            look  = bound.to_f * rays.map { |_direction, rate| rate }.max * NA_CHAMFER_DEPTH_MARGIN
            faces = Na__NobleDrawingTools.Na__DrawnChamfer__FacesNear(faces, stations, look)
        end
        return nil if faces.empty?

        walls = faces.map { |face| [face, face.outer_loop.vertices.first.position, face.normal] }
        least = nil

        stations.each do |station|
            rays.each do |direction, rate|
                distance = Na__NobleDrawingTools.Na__DrawnChamfer__FirstHit(walls, station, direction)
                next unless distance

                size  = distance / rate
                least = size if least.nil? || size < least
            end
        end

        least
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Every Direction the Cut Reaches Into, With Its Reach per Unit Size
    # ------------------------------------------------------------
    # [unit direction, length at size 1] for each profile point and the middle
    # of each facet, seen from the corner. A chamfer solve carries no profile:
    # it is the two points a and b.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__DepthRays(probe, corner)
        profile = probe[:profile0] || [probe[:a0], probe[:b0]]
        return [] unless profile && profile.compact.length >= 2

        samples = []
        profile.each_with_index do |point, index|
            samples << point
            following = profile[index + 1]
            next unless following

            samples << Geom::Point3d.new(
                (point.x.to_f + following.x.to_f) * 0.5,
                (point.y.to_f + following.y.to_f) * 0.5,
                (point.z.to_f + following.z.to_f) * 0.5
            )
        end

        samples.map do |point|
            offset = point - corner
            rate   = offset.length.to_f
            rate > 1.0e-9 ? [offset.normalize, rate] : nil
        end.compact
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Faces Whose Outline Comes Within Reach of the Stations
    # A box test on each face's outer loop: cheap, and generous.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__FacesNear(faces, stations, reach)
        low  = [0, 1, 2].map { |axis| stations.map { |point| point.to_a[axis].to_f }.min - reach }
        high = [0, 1, 2].map { |axis| stations.map { |point| point.to_a[axis].to_f }.max + reach }

        faces.select do |face|
            corners = face.outer_loop.vertices.map { |vertex| vertex.position.to_a }

            [0, 1, 2].all? do |axis|
                values = corners.map { |corner| corner[axis].to_f }
                values.max >= low[axis] && values.min <= high[axis]
            end
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Far Along a Ray the First Face Is Met, or nil
    # ------------------------------------------------------------
    # walls holds [face, a point on its plane, its normal]. A ray running
    # along a face's plane never meets it; a meeting closer than
    # NA_CHAMFER_DEPTH_MIN_HIT is the arris the ray starts on.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__FirstHit(walls, origin, direction)
        nearest = nil

        walls.each do |face, on_plane, normal|
            facing = direction.dot(normal).to_f
            next if facing.abs < 1.0e-9

            distance = (on_plane - origin).dot(normal).to_f / facing
            next if distance <= NA_CHAMFER_DEPTH_MIN_HIT
            next if nearest && distance >= nearest

            point = Na__NobleDrawingTools.Na__DrawnGrid__OffsetPoint(origin, direction, distance)
            next unless NA_CHAMFER_DEPTH_HITS.include?(face.classify_point(point))

            nearest = distance
        end

        nearest
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Tool Side
    # -----------------------------------------------------------------------------

    module DrawnChamferLimit

        # FUNCTION | The Largest Size Every Edge of a Batch Can Take, or nil
        # ------------------------------------------------------------
        def na_lm__max_for(targets)
            sizes = (targets || []).map do |target|
                Na__NobleDrawingTools.Na__DrawnChamfer__MaxSize(target, na_drawn__solve_cut(target, 1.0))
            end.compact

            sizes.min
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Size More Than the Faces Allow?
        # ------------------------------------------------------------
        def na_lm__over?(size, max)
            return false if max.nil?

            size.to_f > max.to_f + NA_CHAMFER_LIMIT_TOL
        end
        # ---------------------------------------------------------------

        # FUNCTION | Refusal Wording That Names the Limit
        # ------------------------------------------------------------
        def na_lm__over_message(size, max)
            asked = Na__NobleDrawingTools.Na__DrawnFormat__Mm(size).abs
            most  = Na__NobleDrawingTools.Na__DrawnFormat__Mm(max).abs
            "#{asked} mm is more than this corner has — the faces allow #{na_drawn__cut_phrase} of #{most} mm at most"
        end
        # ---------------------------------------------------------------

        # FUNCTION | " · 75% of 100 mm max", or '' When There Is No Limit
        # ------------------------------------------------------------
        def na_lm__range_note(size, max)
            return '' if max.nil? || max.to_f <= 0.0

            percent = ((size.to_f / max.to_f) * 100.0).round
            percent = 100 if percent > 100
            " · #{percent}% of #{Na__NobleDrawingTools.Na__DrawnFormat__Mm(max).abs} mm max"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Record Remembers the Limit It Was Cut Under
        # A retype runs after the cut, when the faces it would be measured on
        # are already gone, so the limit read before the cut rides with it.
        # ------------------------------------------------------------
        def na_revise__capture(members, solves, ops)
            super

            @na_revise_record[:max_size] = @na_ch_commit_max if @na_revise_record && @na_ch_commit_max
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Retyped Size Over the Limit Is Refused Before Anything Is Undone
        # The host's own parse reads the entry (it raises for anything
        # unreadable), then the size is checked against the recorded limit.
        # ------------------------------------------------------------
        def na_revise__retype(text, view)
            record = @na_revise_record

            if record && record[:max_size]
                size = na_revise__parse_retype(text, record)
                raise ArgumentError, na_lm__over_message(size, record[:max_size]) if na_lm__over?(size, record[:max_size])
            end

            super
        end
        # ---------------------------------------------------------------

    end # End DrawnChamferLimit module

    # endregion -------------------------------------------------------------------

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF DEEP CHAMFER SIZE LIMIT
# =============================================================================
