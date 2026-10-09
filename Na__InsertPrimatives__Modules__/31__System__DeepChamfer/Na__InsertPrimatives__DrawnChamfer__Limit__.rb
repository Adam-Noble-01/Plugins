# =============================================================================
# NA INSERT PRIMATIVES - DEEP CHAMFER SIZE LIMIT
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnChamfer__Limit__.rb
# NAMESPACE  : Na__InsertPrimatives / Na__InsertPrimatives::DrawnChamferLimit
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

module Na__InsertPrimatives

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

                Na__InsertPrimatives.Na__DrawnChamfer__ClipToBand(start, finish, origin, along, length).each do |point|
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
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__ClipToBand(start, finish, origin, along, length)
        s_start = (start - origin).dot(along).to_f
        s_end   = (finish - origin).dot(along).to_f
        span    = s_end - s_start
        low     = -NA_CHAMFER_REACH_TOL
        high    = length.to_f + NA_CHAMFER_REACH_TOL

        if span.abs < 1.0e-9
            return (s_start >= low && s_start <= high) ? [start, finish] : []
        end

        t_low  = (low  - s_start) / span
        t_high = (high - s_start) / span
        t_min  = [[t_low, t_high].min, 0.0].max
        t_max  = [[t_low, t_high].max, 1.0].min
        return [] if t_min > t_max

        step = finish - start
        [
            Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(start, step, t_min),
            Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(start, step, t_max)
        ]
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Largest Size an Edge Can Take, in the Tool's Own Size Units
    # ------------------------------------------------------------
    # probe is the tool's solve at size 1 (without stops). Its a and b points
    # say how far the cut reaches across face A and face B per unit of size,
    # whatever the profile, and each face's reach divided by that rate is the
    # size that just consumes it. nil when neither face could be measured.
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

            reach = Na__InsertPrimatives.Na__DrawnChamfer__FaceReach(face, xform, origin, along, length, across.normalize)
            sizes << (reach / rate) if reach
        end

        sizes.min
    rescue StandardError
        nil
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
                Na__InsertPrimatives.Na__DrawnChamfer__MaxSize(target, na_drawn__solve_cut(target, 1.0))
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
            asked = Na__InsertPrimatives.Na__DrawnFormat__Mm(size).abs
            most  = Na__InsertPrimatives.Na__DrawnFormat__Mm(max).abs
            "#{asked} mm is more than this corner has — the faces allow #{na_drawn__cut_phrase} of #{most} mm at most"
        end
        # ---------------------------------------------------------------

        # FUNCTION | " · 75% of 100 mm max", or '' When There Is No Limit
        # ------------------------------------------------------------
        def na_lm__range_note(size, max)
            return '' if max.nil? || max.to_f <= 0.0

            percent = ((size.to_f / max.to_f) * 100.0).round
            percent = 100 if percent > 100
            " · #{percent}% of #{Na__InsertPrimatives.Na__DrawnFormat__Mm(max).abs} mm max"
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

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP CHAMFER SIZE LIMIT
# =============================================================================
