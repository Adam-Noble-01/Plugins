# =============================================================================
# NA INSERT PRIMATIVES - PROFILE SWEEP GEOMETRY
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnProfileSweep__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Sweep any edge profile along an edge — the corner frame, the
#              plan, the build and the corner mitres shared by every profile
#              tool (Deep Ogee, Deep Fillet)
# CREATED    : 2026
#
# DESCRIPTION:
# - A chamfer replaces the corner of an edge with one straight chord from a
#   (on face A) to b (on face B). A profile tool replaces it with a curve
#   between two such points, swept along the edge as a run of narrow facets
#   whose shared edges are softened and smoothed, so the curve shades as one.
# - Each profile tool owns only its curve and its solve. Everything here is
#   the same for all of them: reading the corner, packing a solve the chamfer
#   tool can drive, capturing every touched face as a loop of positions,
#   substituting the corner, erasing, rebuilding, and mitring where two
#   banked edges meet. The construction is the chamfer's own (see
#   Na__InsertPrimatives__DrawnChamfer__Geometry__.rb) with one change: an
#   end face the chamfer clips with the pair [a, b] is clipped here by the
#   whole profile [a, ..., b].
# - Where the arris carries straight on past an end — an edge split into
#   sections — the cut STOPS there instead of clipping anything (see the
#   Stops region). Deep Chamfer sends every stopped cut through here too,
#   as the two-point profile [a, b], so all three tools stop the same way.
#
# THE SOLVE A PROFILE TOOL HANDS BACK (Na__ProfileSweep__SolveHash builds it):
#   every key the chamfer tool reads — :cos_half, :v0/:v1, :a0/:a1/:b0/:b1,
#   :bisector_local, :world, :width_world, :edge_len_world, :face_angle_deg
#   — plus :profile0 / :profile1, the local points a -> b at each end, and
#   :convex, which side of the profile is air. A tool adds its own keys:
#   :symmetric (a profile that reads the same from either face, which any
#   mitre accepts) or :roll_on_a (which face an asymmetric profile starts
#   from, which a mitre must find matching on both edges).
#
# CONVEX AND CONCAVE CORNERS:
# - On a convex edge the profile cuts material away, and air is on the
#   corner's side of the curve. On a concave (internal) edge the same plan
#   fills the corner up to the curve instead, and air is on the far side.
#   The facets are oriented to face the air either way.
#
# COORDINATES:
# - Everything is in the space the edge REPORTS, exactly as the chamfer
#   solver works; target[:transformation] carries it to world for the
#   preview, and the caller's build_transform carries plans into the space
#   the collection ACCEPTS. See the open-context rule in the chamfer tool.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamfer__Geometry__'
require_relative '../31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamfer__Mitre__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Corner and Solve
    # -----------------------------------------------------------------------------

    # FUNCTION | Read the Corner an Edge Makes
    # The chamfer solver's own corner analysis: the inward direction along
    # each face, the bisector between them, the half-angle and the instance
    # scale along each direction. nil when the edge cannot carry a profile —
    # the same refusals as the chamfer.
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__CornerFrame(target)
        edge  = target[:edge]
        xform = target[:transformation]
        return nil unless edge && edge.valid? && target[:faces] && target[:faces].length == 2

        face_a, face_b = target[:faces]
        v0 = edge.start.position
        v1 = edge.end.position

        edge_vector = v1 - v0
        return nil if edge_vector.length == 0
        edge_unit = edge_vector.normalize

        dir_a = Na__InsertPrimatives.Na__DrawnChamfer__InwardDir(face_a, edge_unit)
        dir_b = Na__InsertPrimatives.Na__DrawnChamfer__InwardDir(face_b, edge_unit)
        return nil unless dir_a && dir_b

        midpoint = Geom::Point3d.new(
            (v0.x.to_f + v1.x.to_f) * 0.5,
            (v0.y.to_f + v1.y.to_f) * 0.5,
            (v0.z.to_f + v1.z.to_f) * 0.5
        )
        dir_a = Na__InsertPrimatives.Na__DrawnChamfer__SignToward(dir_a, midpoint, face_a)
        dir_b = Na__InsertPrimatives.Na__DrawnChamfer__SignToward(dir_b, midpoint, face_b)

        bisector = Geom::Vector3d.new(
            dir_a.x.to_f + dir_b.x.to_f,
            dir_a.y.to_f + dir_b.y.to_f,
            dir_a.z.to_f + dir_b.z.to_f
        )
        return nil if bisector.length == 0
        bisector.normalize!

        cos_half = bisector.dot(dir_a).to_f
        return nil if cos_half.abs < NA_CHAMFER_MIN_COS_HALF

        scale_a = dir_a.transform(xform).length.to_f
        scale_b = dir_b.transform(xform).length.to_f
        scale_a = 1.0 if scale_a <= 0.0
        scale_b = 1.0 if scale_b <= 0.0

        {
            :v0        => v0,
            :v1        => v1,
            :edge_unit => edge_unit,
            :dir_a     => dir_a,
            :dir_b     => dir_b,
            :bisector  => bisector,
            :cos_half  => cos_half,
            :scale_a   => scale_a,
            :scale_b   => scale_b,
            :convex    => bisector.dot(face_a.normal) < 0.0                   # <-- The bisector runs behind face A: material in the wedge
        }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Pack a Profile Into the Solve the Chamfer Tool Drives
    # profile0 / profile1 are local points a -> b at v0 / v1. World copies are
    # made through target[:transformation] unless the caller already has them
    # (a tool that solves in world space passes its own, saving a round trip).
    # extras carries the tool's own keys and wins over nothing here.
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__SolveHash(frame, target, profile0, profile1, extras = {}, world0 = nil, world1 = nil)
        xform  = target[:transformation]
        world0 ||= profile0.map { |point| point.transform(xform) }
        world1 ||= profile1.map { |point| point.transform(xform) }
        v0w    = frame[:v0].transform(xform)
        v1w    = frame[:v1].transform(xform)

        half_angle_deg = Math.acos([[frame[:cos_half].to_f, 1.0].min, -1.0].max) * 180.0 / Math::PI

        {
            :cos_half       => frame[:cos_half],
            :convex         => frame[:convex],
            :v0 => frame[:v0], :v1 => frame[:v1],
            :a0 => profile0.first, :a1 => profile1.first,
            :b0 => profile0.last,  :b1 => profile1.last,
            :profile0       => profile0,
            :profile1       => profile1,
            :bisector_local => frame[:bisector],
            :world => {
                :v0 => v0w, :v1 => v1w,
                :a0 => world0.first, :a1 => world1.first,
                :b0 => world0.last,  :b1 => world1.last,
                :profile0 => world0, :profile1 => world1
            },
            :width_world    => world0.first.distance(world0.last),
            :edge_len_world => v0w.distance(v1w),
            :face_angle_deg => 90.0 - half_angle_deg
        }.merge(extras)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Stops — Where the Arris Carries On Past an End
    # -----------------------------------------------------------------------------
    #
    # An edge split into SECTIONS (lines drawn across its two faces, dividing
    # the arris into pieces) is asking for a cut along one piece that stops
    # short of the next. At an end where the arris runs straight on, the cut
    # must not touch the next section, so instead of clipping end faces it
    # STOPS: the full-width cut begins a stop-length in from the end, and a
    # stop closes it down to a point on the arris at the section line itself —
    # the classic pyramid stop, one sloping triangle for a chamfer, a fan for a
    # curve. The stop is as long as the cut is wide, the proportion of a
    # traditional stop, shortened if the section is too short to hold it.
    #
    # When the next piece of the same arris is banked in the same batch there
    # is no stop at all: the joint is THROUGH, and the two cuts meet full width
    # on the section line.
    # -----------------------------------------------------------------------------

    NA_SWEEP_STOP_COLLINEAR  = 0.99996                                        # <-- cos 0.5 deg: an edge this straight on carries the arris on
    NA_SWEEP_STOP_SHARE_BOTH = 0.4                                            # <-- Of the piece's length, per stop, with a stop at each end
    NA_SWEEP_STOP_SHARE_ONE  = 0.8                                            # <-- With a stop at one end only

    # FUNCTION | The Edge That Carries the Arris On Past This End, or nil
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__Continuation(edge, vertex)
        toward = edge.other_vertex(vertex).position - vertex.position
        return nil unless toward.length > 0
        toward.normalize!

        vertex.edges.find do |other|
            next false if other == edge || !other.valid?

            beyond = other.other_vertex(vertex).position - vertex.position
            next false unless beyond.length > 0

            beyond.normalize.dot(toward) < -NA_SWEEP_STOP_COLLINEAR
        end
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Give a Chamfer Solve the Profile Keys the Sweep Reads
    # A chamfer is the two-point profile [a, b]. It reads the same from either
    # face, and whether its corner is convex comes from the bisector against
    # face A, as the corner frame decides it.
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__EnsureProfile(target, solve)
        unless solve[:profile0] && solve[:profile1]
            solve[:profile0]          = [solve[:a0], solve[:b0]]
            solve[:profile1]          = [solve[:a1], solve[:b1]]
            solve[:world][:profile0]  = [solve[:world][:a0], solve[:world][:b0]]
            solve[:world][:profile1]  = [solve[:world][:a1], solve[:world][:b1]]
            solve[:symmetric]         = true unless solve.key?(:symmetric)
        end

        if solve[:convex].nil?
            face_a = target[:faces] ? target[:faces][0] : nil
            solve[:convex] = face_a ? solve[:bisector_local].dot(face_a.normal) < 0.0 : true
        end

        solve
    end
    # ---------------------------------------------------------------

    # FUNCTION | Stop the Cut at Each End Where the Arris Carries On
    # Mutates and returns the solve. At an end whose arris runs straight on:
    #   * into another edge in batch_edges — :through0/1, the cuts meet full width
    #   * into anything else — :stop0/1, and that end's profile moves a stop's
    #     length in along the edge, so the cut begins there and the corner vertex
    #     is left behind as the stop's apex
    # :stop_length_world records how long the stops came out. A solve with
    # neither end continuing is returned unchanged but for its profile keys.
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__ApplyStops(target, solve, batch_edges = nil)
        return solve unless solve

        edge = target[:edge]
        return solve unless edge && edge.valid?

        Na__InsertPrimatives.Na__ProfileSweep__EnsureProfile(target, solve)

        heading = solve[:v1] - solve[:v0]
        span    = heading.length.to_f
        return solve unless span > 0.0
        along = heading.normalize

        stop_ends = []

        [[0, edge.start], [1, edge.end]].each do |end_index, vertex|
            continuation = Na__InsertPrimatives.Na__ProfileSweep__Continuation(edge, vertex)
            next unless continuation

            if batch_edges && batch_edges.include?(continuation)
                solve[end_index.zero? ? :through0 : :through1] = true
            else
                stop_ends << end_index
            end
        end

        return solve if stop_ends.empty?

        xform      = target[:transformation]
        edge_scale = along.transform(xform).length.to_f
        edge_scale = 1.0 unless edge_scale > 0.0

        stop_local = solve[:width_world].to_f / edge_scale                    # <-- As long as the cut is wide
        limit      = span * (stop_ends.length == 2 ? NA_SWEEP_STOP_SHARE_BOTH : NA_SWEEP_STOP_SHARE_ONE)
        stop_local = limit if stop_local > limit
        return solve unless stop_local > 0.0

        stop_ends.each do |end_index|
            inward  = end_index.zero? ? along : along.reverse
            key     = end_index.zero? ? :profile0 : :profile1
            shifted = solve[key].map { |point| Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, inward, stop_local) }

            Na__InsertPrimatives.Na__ProfileSweep__SetEnd(solve, end_index, shifted, xform)
            solve[end_index.zero? ? :stop0 : :stop1] = true
        end

        solve[:stop_length_world] = stop_local * edge_scale
        solve
    rescue StandardError
        solve
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does This Solve Stop, or Run Through, at Either End?
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__Stopped?(solve)
        return false unless solve

        (solve[:stop0] || solve[:stop1] || solve[:through0] || solve[:through1]) ? true : false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Plan
    # -----------------------------------------------------------------------------

    # FUNCTION | Capture a Face as an Ordered Rebuild Plan
    # The chamfer's planner with a profile where it has a pair: single_subs
    # replace one loop position with one point (the faces the profile runs
    # along), run_subs replace one loop position with the whole profile (the
    # end faces, whose corner the profile clips). The run is laid in whichever
    # direction starts nearer the previous loop position, which keeps the
    # rebuilt winding sane — the same test the chamfer uses for its pair.
    #
    # stop_subs are [corner, partner, point]: at a STOPPED end the corner
    # stays where it is — it is the stop's apex — and the point where the
    # full-width cut begins is inserted beside it, on the side the arris runs
    # toward its partner. Which side that is comes from the original loop, so
    # it cannot be fooled the way a nearest-point test can on a long face.
    # Raises before anything is touched when a face cannot be planned.
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__RebuildPlan(face, single_subs, run_subs, stop_subs = [])
        raise 'a profile beside an opening is not supported yet' if face.loops.length > 1

        original = face.outer_loop.vertices.map { |vertex| vertex.position }
        raise 'a face around this corner has no usable boundary' if original.length < 3

        points = []

        original.each_with_index do |position, index|
            single = single_subs.find { |corner, _| Na__InsertPrimatives.Na__DrawnChamfer__SamePoint?(position, corner) }
            if single
                points << single[1]
                next
            end

            stop = stop_subs.find { |corner, _, _| Na__InsertPrimatives.Na__DrawnChamfer__SamePoint?(position, corner) }
            if stop
                following = original[(index + 1) % original.length]

                if Na__InsertPrimatives.Na__DrawnChamfer__SamePoint?(following, stop[1])
                    points << position << stop[2]                             # <-- The arris runs on from here: the cut starts after the apex
                else
                    points << stop[2] << position                             # <-- The arris arrived from the partner: the cut ends before it
                end
                next
            end

            run = run_subs.find { |corner, _| Na__InsertPrimatives.Na__DrawnChamfer__SamePoint?(position, corner) }
            unless run
                points << position
                next
            end

            profile  = run[1]
            previous = original[index - 1]                                    # <-- index 0 wraps to the last point, which is correct
            ordered  = previous.distance(profile.first) <= previous.distance(profile.last) ? profile : profile.reverse
            points.concat(ordered)
        end

        {
            :face          => face,
            :points        => points,
            :normal        => face.normal,
            :material      => face.material,
            :back_material => face.back_material,
            :layer         => face.layer
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Plan Every Face a Single-Edge Profile Touches
    # An ordinary end clips its end faces with the profile. A STOPPED end
    # touches nothing past its apex: the faces beyond it (the next section)
    # are left exactly as they are, and only faces A and B learn where the
    # full-width cut begins. Raises on anything it cannot plan — a refusal
    # before anything is erased costs the model nothing.
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__BuildPlans(target, solve)
        edge           = target[:edge]
        face_a, face_b = target[:faces]

        a_singles = []
        b_singles = []
        a_stops   = []
        b_stops   = []
        runs      = []
        end_faces = []

        [[edge.start, solve[:v0], solve[:v1], :profile0, :stop0],
         [edge.end,   solve[:v1], solve[:v0], :profile1, :stop1]].each do |vertex, corner, partner, profile_key, stop_key|
            profile = solve[profile_key]

            if solve[stop_key]
                a_stops << [corner, partner, profile.first]
                b_stops << [corner, partner, profile.last]
                next
            end

            a_singles << [corner, profile.first]
            b_singles << [corner, profile.last]
            runs      << [corner, profile]
            end_faces.concat(vertex.faces.to_a - [face_a, face_b])
        end

        plans = []
        plans << Na__InsertPrimatives.Na__ProfileSweep__RebuildPlan(face_a, a_singles, [], a_stops)
        plans << Na__InsertPrimatives.Na__ProfileSweep__RebuildPlan(face_b, b_singles, [], b_stops)
        end_faces.uniq.each do |end_face|
            plans << Na__InsertPrimatives.Na__ProfileSweep__RebuildPlan(end_face, [], runs)
        end

        plans
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Build
    # -----------------------------------------------------------------------------

    # FUNCTION | Add the Profile Surface Along One Edge
    # One facet per profile segment, running v0 -> v1, each facing the air.
    # Walking the profile from a to b, air is always on the same side, so one
    # sign — taken from the a-b chord — orients every facet, concave runs
    # included. On a convex corner the chord's air side is opposite the
    # bisector, exactly as a chamfer plane faces; on a concave corner it is
    # the bisector's side. The seams between facets are the curve's own
    # segmentation, not corners, so they are softened and smoothed; the two
    # boundary edges onto face A and face B stay hard.
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__AddMoulding(entities, solve, dress, build_transform)
        near = solve[:profile0].map { |point| point.transform(build_transform) }
        far  = solve[:profile1].map { |point| point.transform(build_transform) }
        raise 'the profile is incomplete' unless near.length == far.length && near.length >= 2

        heading  = (solve[:v1] - solve[:v0]).transform(build_transform)
        bisector = solve[:bisector_local].transform(build_transform)
        convex   = solve[:convex] != false                                    # <-- An older solve without the key was always treated as convex

        chord_normal = heading.cross(near.last - near.first)
        leaning      = (chord_normal.valid? && bisector.valid?) ? chord_normal.dot(bisector) : 0.0
        reverse_all  = convex ? (leaning > 0.0) : (leaning < 0.0)

        facets = []

        (0...(near.length - 1)).each do |index|
            facet = entities.add_face(near[index], far[index], far[index + 1], near[index + 1])
            raise 'a profile facet could not be created here' unless facet

            outward = heading.cross(near[index + 1] - near[index])
            outward.reverse! if reverse_all
            facet.reverse! if outward.valid? && facet.normal.dot(outward) < 0.0

            if dress
                facet.material      = dress[:material]      if dress[:material]
                facet.back_material = dress[:back_material] if dress[:back_material]
                facet.layer         = dress[:layer]         if dress[:layer]
            end

            facets << facet
        end

        facets.each_cons(2) do |left, right|
            left.edges.each do |seam|
                next unless seam.used_by?(right)

                seam.soft   = true
                seam.smooth = true
            end
        end

        facets
    end
    # ---------------------------------------------------------------

    # FUNCTION | Close Each Stopped End With Its Stop
    # A fan of triangles from the apex (the corner vertex, left on the
    # arris) to the profile where the full-width cut begins: one sloping
    # triangle for a chamfer — the classic pyramid stop — and a fan for a
    # curve, its seams softened so it reads as one run-out. Each triangle
    # faces the air by the same rule as the facets: on a convex corner the
    # material lies along the bisector from the apex, on a concave one the
    # air does.
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__AddStops(entities, solve, dress, build_transform)
        bisector = solve[:bisector_local].transform(build_transform)
        convex   = solve[:convex] != false
        facets   = []

        [[:stop0, :v0, :profile0], [:stop1, :v1, :profile1]].each do |stop_key, corner_key, profile_key|
            next unless solve[stop_key]

            apex    = solve[corner_key].transform(build_transform)
            profile = solve[profile_key].map { |point| point.transform(build_transform) }
            fan     = []

            (0...(profile.length - 1)).each do |index|
                facet = entities.add_face(apex, profile[index], profile[index + 1])
                raise 'a stop could not be created at the end of this cut' unless facet

                leaning = bisector.valid? ? facet.normal.dot(bisector) : 0.0
                facet.reverse! if convex ? (leaning > 0.0) : (leaning < 0.0)

                if dress
                    facet.material      = dress[:material]      if dress[:material]
                    facet.back_material = dress[:back_material] if dress[:back_material]
                    facet.layer         = dress[:layer]         if dress[:layer]
                end

                fan << facet
            end

            fan.each_cons(2) do |left, right|
                left.edges.each do |seam|
                    next unless seam.used_by?(right)

                    seam.soft   = true
                    seam.smooth = true
                end
            end

            facets.concat(fan)
        end

        facets
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build a Single-Edge Profile Into an Entities Collection
    # Runs inside the operation ExecuteInContext opens, with the plans already
    # made. Erases are coordinate-free; every ADD goes through build_transform.
    # Any raise aborts the operation and the model is untouched.
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__Build(entities, target, solve, plans, build_transform)
        edge            = target[:edge]
        corner_vertices = [edge.start, edge.end]

        # Erase phase. Shared edges survive their faces; edges left bounding
        # nothing are swept so the old corner disappears completely.
        plans.each { |plan| plan[:face].erase! if plan[:face] && plan[:face].valid? }
        edge.erase! if edge.valid?

        corner_vertices.each do |vertex|
            next unless vertex.valid?

            vertex.edges.to_a.each do |stray|
                stray.erase! if stray.valid? && stray.faces.empty?
            end
        end

        # Rebuild phase. The profile dresses like face A, as the chamfer's
        # plane does, so a painted board keeps its paint round the moulding.
        plans.each { |plan| Na__InsertPrimatives.Na__DrawnChamfer__RebuildFace(entities, plan, build_transform) }
        Na__InsertPrimatives.Na__ProfileSweep__AddMoulding(entities, solve, plans[0], build_transform)
        Na__InsertPrimatives.Na__ProfileSweep__AddStops(entities, solve, plans[0], build_transform)

        true
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Corner Mitres
    # -----------------------------------------------------------------------------
    #
    # The chamfer mitre moves two points per edge end: P, where the offset lines
    # cross on the shared face, and the lower point M both edges agree on. A
    # profile has a whole run of points at each end, so EVERY point is mitred
    # the same way: point i swept along edge 1 and point i swept along edge 2 are
    # two lines, and where they cross is that point's place on the mitre. P is
    # i = 0 and M the last i. On a square corner every pair lies at the same
    # depth below the shared face, so every pair crosses and the crossings run
    # down the diagonal mitre plane, as in a picture frame; each facet ends on
    # the mitre line between two consecutive crossings and the matching facet of
    # the other edge ends on the same line.
    #
    # Refused, with a message: a corner not square in the third direction (a
    # pair of lines does not cross), two asymmetric profiles starting from
    # different kinds of face (they would not meet), and three or more profiled
    # edges at one corner (the curved three-way junction is not built).
    # -----------------------------------------------------------------------------

    # FUNCTION | Overwrite One End's Profile, Local and World
    # profile_ab is in a -> b order like every stored profile; its ends are the
    # solve's a and b at that end, so they move with it.
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__SetEnd(solve, end_index, profile_ab, xform)
        profile_key  = end_index.zero? ? :profile0 : :profile1
        a_key, b_key = end_index.zero? ? [:a0, :b0] : [:a1, :b1]
        world        = profile_ab.map { |point| point.transform(xform) }

        solve[profile_key]         = profile_ab
        solve[a_key]               = profile_ab.first
        solve[b_key]               = profile_ab.last
        solve[:world][profile_key] = world
        solve[:world][a_key]       = world.first
        solve[:world][b_key]       = world.last
        solve
    end
    # ---------------------------------------------------------------

    # FUNCTION | Overwrite One End's Profile With Its Mitred Points
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__PatchEnd(solve, end_index, profile_ab, xform)
        Na__InsertPrimatives.Na__ProfileSweep__SetEnd(solve, end_index, profile_ab, xform)
        solve[end_index.zero? ? :mitre0 : :mitre1] = true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Find and Apply Every Corner Mitre in a Batch
    # Mutates the solves: each mitred end's profile moves onto the mitre and
    # its mitre flag is set. Returns nil on success or an honest refusal —
    # the caller decides whether that aborts (commit) or just previews
    # unmitred (drag). Every point is computed from the unpatched solves
    # before any is written.
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__MitreBatch(targets, solves)
        ends = {}

        targets.each_with_index do |target, index|
            solve = solves[index]
            next unless solve

            edge = target[:edge]
            next unless edge && edge.valid?

            # A stopped end ends on its own apex and a through end carries on
            # into the next banked piece of the same arris: neither is a corner
            # another edge can mitre to.
            (ends[edge.start] ||= []) << [index, 0] unless solve[:stop0] || solve[:through0]
            (ends[edge.end]   ||= []) << [index, 1] unless solve[:stop1] || solve[:through1]
        end

        patches = []

        ends.each do |vertex, members|
            next if members.length < 2
            return 'three profiled edges meet at one corner — the curved three-way mitre is not built yet' if members.length > 2

            index_a, end_a = members[0]
            index_b, end_b = members[1]
            target_a = targets[index_a]
            target_b = targets[index_b]
            solve_a  = solves[index_a]
            solve_b  = solves[index_b]

            shared_faces = target_a[:faces] & target_b[:faces]
            return 'edges meeting at a corner must share exactly one face' unless shared_faces.length == 1
            shared_face = shared_faces[0]

            extra_faces = vertex.faces - target_a[:faces] - target_b[:faces]
            return 'the corner where these edges meet carries extra faces — profile those edges separately' unless extra_faces.empty?

            # Does each profile start on the shared face (is it that edge's face
            # A)? For an asymmetric profile, does each edge start it from the
            # SAME kind of face? If not, one arrives rolling where the other
            # arrives on its lip and nothing about them meets.
            shared_is_a_a = target_a[:faces][0] == shared_face
            shared_is_a_b = target_b[:faces][0] == shared_face

            unless solve_a[:symmetric] && solve_b[:symmetric]
                rolls_a = shared_is_a_a == solve_a[:roll_on_a]
                rolls_b = shared_is_a_b == solve_b[:roll_on_a]
                return 'the profile runs opposite ways round this corner — do these edges separately' unless rolls_a == rolls_b
            end

            # Both sequences start on the shared face, so index i is the same
            # point of the same profile on both edges.
            profile_a = end_a.zero? ? solve_a[:profile0] : solve_a[:profile1]
            profile_b = end_b.zero? ? solve_b[:profile0] : solve_b[:profile1]
            return 'the two profiles at this corner do not match' unless profile_a && profile_b && profile_a.length == profile_b.length

            sequence_a = shared_is_a_a ? profile_a : profile_a.reverse
            sequence_b = shared_is_a_b ? profile_b : profile_b.reverse

            heading_a = solve_a[:v1] - solve_a[:v0]
            heading_b = solve_b[:v1] - solve_b[:v0]
            return 'a shared-corner edge has no length' if heading_a.length == 0 || heading_b.length == 0

            joints = sequence_a.each_index.map do |index|
                line_a = [sequence_a[index], heading_a]
                line_b = [sequence_b[index], heading_b]
                joint  = Geom.intersect_line_line(line_a, line_b)
                return 'edges are parallel where they meet — no mitre exists there' unless joint

                if joint.distance_to_line(line_a) > NA_CHAMFER_MITRE_TOL || joint.distance_to_line(line_b) > NA_CHAMFER_MITRE_TOL
                    return 'this corner is not square enough to mitre a profile — do these edges separately'
                end

                joint
            end

            patches << [solve_a, end_a, shared_is_a_a ? joints : joints.reverse, target_a[:transformation]]
            patches << [solve_b, end_b, shared_is_a_b ? joints : joints.reverse, target_b[:transformation]]
        end

        patches.each do |solve, end_index, profile_ab, xform|
            Na__InsertPrimatives.Na__ProfileSweep__PatchEnd(solve, end_index, profile_ab, xform)
        end

        nil
    rescue StandardError => error
        "mitre solving failed: #{error.message}"
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Batch Plan and Build
    # -----------------------------------------------------------------------------

    # FUNCTION | Plan Every Face a Whole Batch Group Touches, Exactly Once
    # Substitutions accumulate per face and are merged (a shared face collects
    # the same mitred corner from both its edges). Which ends clip their end
    # faces: only the ordinary ones. A mitred end's ending IS the mitre; a
    # through end hands over to the next banked piece of the same arris,
    # whose own faces take the same corner point; a stopped end leaves every
    # face past its apex alone and only tells faces A and B where the cut
    # begins.
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__BuildGroupPlans(targets, solves)
        accumulators = {}
        fetch        = lambda { |face| accumulators[face] ||= { :singles => [], :runs => [], :stops => [] } }

        targets.each_with_index do |target, index|
            solve          = solves[index]
            edge           = target[:edge]
            face_a, face_b = target[:faces]

            [[edge.start, solve[:v0], solve[:v1], :profile0, 0],
             [edge.end,   solve[:v1], solve[:v0], :profile1, 1]].each do |vertex, corner, partner, profile_key, end_index|
                profile = solve[profile_key]

                if solve[end_index.zero? ? :stop0 : :stop1]
                    fetch.call(face_a)[:stops] << [corner, partner, profile.first]
                    fetch.call(face_b)[:stops] << [corner, partner, profile.last]
                    next
                end

                fetch.call(face_a)[:singles] << [corner, profile.first]
                fetch.call(face_b)[:singles] << [corner, profile.last]
                next if solve[end_index.zero? ? :mitre0 : :mitre1] || solve[end_index.zero? ? :through0 : :through1]

                (vertex.faces - [face_a, face_b]).each do |end_face|
                    fetch.call(end_face)[:runs] << [corner, profile]
                end
            end
        end

        accumulators.map do |face, subs|
            subs[:stops].each do |corner, _, _|
                clash = subs[:singles].any? { |other, _| Na__InsertPrimatives.Na__DrawnChamfer__SamePoint?(other, corner) }
                raise 'a stopped end meets another cut at the same corner — do these edges separately' if clash
            end

            plan = Na__InsertPrimatives.Na__ProfileSweep__RebuildPlan(
                face,
                Na__InsertPrimatives.Na__DrawnChamfer__MergeSingles(subs[:singles]),
                subs[:runs],
                subs[:stops]
            )
            plan[:entities] = face.parent.respond_to?(:entities) ? face.parent.entities : nil
            plan
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Erase and Rebuild a Whole Batch Group in One Pass
    # Everything is planned before this runs; a raise aborts the operation and
    # the group is untouched. Each profile dresses from its own face A.
    # ------------------------------------------------------------
    def self.Na__ProfileSweep__BuildGroup(model, targets, solves, plans, build_transform)
        dress_by_face = {}
        plans.each { |plan| dress_by_face[plan[:face]] = plan }

        dress      = targets.map { |target| dress_by_face[target[:faces][0]] || plans[0] }
        entity_set = targets.map do |target|
            parent = target[:edge].parent
            parent.respond_to?(:entities) ? parent.entities : model.active_entities
        end

        corner_vertices = []
        targets.each { |target| corner_vertices << target[:edge].start << target[:edge].end }

        plans.each { |plan| plan[:face].erase! if plan[:face] && plan[:face].valid? }
        targets.each { |target| target[:edge].erase! if target[:edge].valid? }

        corner_vertices.each do |vertex|
            next unless vertex.valid?

            vertex.edges.to_a.each do |stray|
                stray.erase! if stray.valid? && stray.faces.empty?
            end
        end

        plans.each do |plan|
            entities = plan[:entities] || entity_set[0]
            Na__InsertPrimatives.Na__DrawnChamfer__RebuildFace(entities, plan, build_transform)
        end

        targets.each_index do |index|
            Na__InsertPrimatives.Na__ProfileSweep__AddMoulding(entity_set[index], solves[index], dress[index], build_transform)
            Na__InsertPrimatives.Na__ProfileSweep__AddStops(entity_set[index], solves[index], dress[index], build_transform)
        end

        true
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF PROFILE SWEEP GEOMETRY
# =============================================================================
