# =============================================================================
# NA INSERT PRIMATIVES - DEEP CHAMFER TOOL
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnChamferTool__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnChamferTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Chamfer any edge at any nesting depth, on the shared voxel grid
# CREATED    : 2026
#
# DESCRIPTION:
# - Hover to highlight the edge under the cursor, click to grab it, drag toward
#   the corner to open the chamfer, click (or Enter, or a typed value) to cut.
#   Reaches edges inside groups and components without opening them, exactly as
#   Deep Push/Pull reaches faces.
# - The chamfer is symmetric IN WORLD SPACE: the same setback along each face,
#   which under a non-uniformly scaled instance means the two local setbacks are
#   solved separately from the per-direction scale — the same trap the push
#   tool's normal_scale guards against, in two directions at once.
#
# WHAT THE DRAG MEASURES:
# - The cursor is projected onto the corner bisector (the diagonal running into
#   the material between the two faces) and converted to the per-face setback,
#   which is the number a joiner actually specifies — "a 50 chamfer" is 50 off
#   each face, not 50 along the diagonal. The setback snaps to the voxel step;
#   CTRL suspends that for vertex inference, so a chamfer can be dragged to stop
#   exactly at an existing corner.
#
# LESSONS CARRIED FROM THE PUSH/PULL SAGA (built in from the start, not found):
# - The edit runs inside the edge's own context via ExecuteInContext, so the
#   display refreshes instantly and undo is one Ctrl+Z.
# - Once an edge is grabbed nothing is picked again mid-drag — the distance is
#   pure ray maths, and an unsolvable frame keeps the last good value.
# - Two states only; any state this tool cannot service snaps back to idle.
#
# CONSTRUCTION (local space, one operation) — CAPTURE, SUBSTITUTE, REBUILD:
# - The first construction assumed that an edge added on a face splits it, the
#   way the UI Line tool does. The API documentation promises NO such thing
#   (checked, not guessed — Entities#add_face carries no splitting, merging or
#   intersection behaviour at all), so erasing the corner edge destroyed every
#   face it bounded whole. v0.4.22 shipped that bug.
# - The rebuild never relies on splitting. Every face touching the corner is
#   captured as an ordered loop of positions, the corner vertices are
#   substituted with the offset points (one point on the two chamfer faces,
#   the a/b PAIR on the end faces, clipping their corners), the old faces and
#   corner edge are erased, and the faces re-added with their materials and
#   tags restored. add_face reuses the surviving coincident edges, so the
#   rebuilt shell knits back onto the untouched neighbours.
# - Every plan is built and validated BEFORE anything is erased, and any
#   failure raises — the surrounding operation aborts and the model is left
#   exactly as it was. Failing loudly beats cutting wrongly.
#
# THE OPEN-CONTEXT COORDINATE RULE (docs-checked, the nested-failure fix):
# - "When changing the active entities in SketchUp, the coordinate system also
#   changes" — Model#active_path=. Entity positions READ are always in the
#   definition's local space, but geometry ADDED while an editing context is
#   open is interpreted in the EDITING SESSION's coordinates, which is what
#   Model#edit_transform reports. Push/pull never met this because pushpull
#   takes a scalar; this tool adds points, so every point is passed through
#   model.edit_transform at add time. With nothing open that transform is the
#   identity, which is why loose geometry worked all along. Plans are built
#   BEFORE the context is entered so every read stays unambiguous.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnToolShared__'
require_relative 'Na__InsertPrimatives__DrawnDeepPick__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Chamfer Geometry (Module Functions)
    # -----------------------------------------------------------------------------

    NA_CHAMFER_MERGE_TOL      = 0.001                                         # <-- Internal inches; vertex identity when cleaning up
    NA_CHAMFER_MIN_COS_HALF   = 0.0872                                        # <-- cos 85 deg; below this the corner is too flat to chamfer
    NA_CHAMFER_MITRE_TOL      = 0.001                                         # <-- The two lower mitre points must agree to SketchUp's own merge tolerance

    # FUNCTION | In-Plane Direction Perpendicular to an Edge, Unsigned
    # Lies in the face plane; SignToward settles which way is into the material.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__InwardDir(face, edge_vector_unit)
        direction = face.normal.cross(edge_vector_unit)
        return nil if direction.length == 0

        direction.normalize
    end
    # ---------------------------------------------------------------

    # FUNCTION | Sign an In-Plane Direction Toward the Face Centroid
    # A heuristic — exact for convex faces and right for practically every
    # architectural face; a pathological L-shape whose centroid falls outside
    # near this edge would flip it.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__SignToward(direction, from_point, face)
        positions = face.outer_loop.vertices.map { |vertex| vertex.position }
        return direction if positions.empty?

        centroid = Geom::Point3d.new(
            positions.map { |pt| pt.x.to_f }.inject(0.0) { |sum, value| sum + value } / positions.length,
            positions.map { |pt| pt.y.to_f }.inject(0.0) { |sum, value| sum + value } / positions.length,
            positions.map { |pt| pt.z.to_f }.inject(0.0) { |sum, value| sum + value } / positions.length
        )

        toward = centroid - from_point
        return direction unless toward.valid?

        direction.dot(toward) < 0.0 ? direction.reverse : direction
    end
    # ---------------------------------------------------------------

    # FUNCTION | Solve the Full Chamfer for a World Setback
    # Returns a hash of local construction points, world preview points and
    # display metrics — or nil when the edge cannot carry a chamfer (folded-flat
    # faces, zero-length edge, degenerate directions).
    #
    # The world setback is converted to a separate LOCAL setback per face using
    # the instance scale along each inward direction, so the cut is symmetric in
    # world space even inside a non-uniformly scaled component.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__Solve(target, offset_world)
        edge  = target[:edge]
        xform = target[:transformation]
        return nil unless edge && edge.valid? && target[:faces].length == 2

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

        local_a = offset_world.to_f / scale_a                                 # <-- Equal WORLD setback either side
        local_b = offset_world.to_f / scale_b

        a0 = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(v0, dir_a, local_a)
        a1 = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(v1, dir_a, local_a)
        b0 = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(v0, dir_b, local_b)
        b1 = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(v1, dir_b, local_b)

        half_angle_deg = Math.acos([[cos_half, 1.0].min, -1.0].max) * 180.0 / Math::PI

        {
            :cos_half => cos_half,
            :v0 => v0, :v1 => v1,
            :a0 => a0, :a1 => a1, :b0 => b0, :b1 => b1,
            :bisector_local => bisector,
            :world => {
                :v0 => v0.transform(xform), :v1 => v1.transform(xform),
                :a0 => a0.transform(xform), :a1 => a1.transform(xform),
                :b0 => b0.transform(xform), :b1 => b1.transform(xform)
            },
            :width_world     => a0.transform(xform).distance(b0.transform(xform)),
            :edge_len_world  => v0.transform(xform).distance(v1.transform(xform)),
            :face_angle_deg  => 90.0 - half_angle_deg                         # <-- Angle the cut makes with each face (45 on a square corner)
        }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Do Two Local Points Name the Same Vertex?
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__SamePoint?(point_a, point_b)
        point_a.distance(point_b) < NA_CHAMFER_MERGE_TOL
    end
    # ---------------------------------------------------------------

    # FUNCTION | Capture a Face as an Ordered Rebuild Plan
    # single_subs replaces one loop position with one point (the two chamfer
    # faces); pair_subs replaces one loop position with TWO points (the end
    # faces, whose corners get clipped). Pair order is settled by which offset
    # point sits nearer the previous loop position, keeping the winding sane.
    # Raises before anything is touched when the face cannot be planned.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__RebuildPlan(face, single_subs, pair_subs)
        raise 'chamfering beside an opening is not supported yet' if face.loops.length > 1

        original = face.outer_loop.vertices.map { |vertex| vertex.position }
        raise 'a face around this corner has no usable boundary' if original.length < 3

        points = []

        original.each_with_index do |position, index|
            single = single_subs.find { |corner, _| Na__InsertPrimatives.Na__DrawnChamfer__SamePoint?(position, corner) }
            if single
                points << single[1]
                next
            end

            pair = pair_subs.find { |corner, _, _| Na__InsertPrimatives.Na__DrawnChamfer__SamePoint?(position, corner) }
            unless pair
                points << position
                next
            end

            previous = original[index - 1]                                    # <-- index 0 wraps to the last point, which is correct
            if previous.distance(pair[1]) <= previous.distance(pair[2])
                points << pair[1] << pair[2]
            else
                points << pair[2] << pair[1]
            end
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

    # FUNCTION | Plan Every Face the Chamfer Touches
    # Called BEFORE the editing context is entered, so every position read is
    # unambiguously in the definition's local space. Raises on anything it
    # cannot plan — with nothing entered and nothing erased, a refusal here
    # costs the model nothing.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__BuildPlans(target, solve)
        edge           = target[:edge]
        face_a, face_b = target[:faces]

        # Every face touching either corner vertex is affected: the two being
        # chamfered plus the end faces whose corners the cut clips.
        end_faces = (edge.start.faces.to_a + edge.end.faces.to_a).uniq - [face_a, face_b]

        plans = []
        plans << Na__InsertPrimatives.Na__DrawnChamfer__RebuildPlan(
            face_a, [[solve[:v0], solve[:a0]], [solve[:v1], solve[:a1]]], []
        )
        plans << Na__InsertPrimatives.Na__DrawnChamfer__RebuildPlan(
            face_b, [[solve[:v0], solve[:b0]], [solve[:v1], solve[:b1]]], []
        )
        end_faces.each do |end_face|
            plans << Na__InsertPrimatives.Na__DrawnChamfer__RebuildPlan(
                end_face, [],
                [[solve[:v0], solve[:a0], solve[:b0]], [solve[:v1], solve[:a1], solve[:b1]]]
            )
        end

        plans
    end
    # ---------------------------------------------------------------

    # FUNCTION | Re-Add a Planned Face and Restore Its Dress
    # Every point goes through build_transform — the open editing session's
    # coordinate system per the header rule, the identity at root. add_face
    # reuses surviving coincident edges, which is what knits the rebuilt faces
    # back onto the untouched neighbours. Winding is restored against the
    # captured normal (transformed the same way) so materials stay put.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__RebuildFace(entities, plan, build_transform)
        face = entities.add_face(plan[:points].map { |point| point.transform(build_transform) })
        raise 'a face could not be rebuilt around the chamfer' unless face

        if plan[:normal]
            session_normal = plan[:normal].transform(build_transform)
            face.reverse! if session_normal.valid? && face.normal.dot(session_normal) < 0.0
        end

        face.material      = plan[:material]      if plan[:material]
        face.back_material = plan[:back_material] if plan[:back_material]
        face.layer         = plan[:layer]         if plan[:layer]
        face
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build the Chamfer Into an Entities Collection
    # Runs inside the operation ExecuteInContext opens, with the plans already
    # made. Erases are coordinate-free; every ADD goes through build_transform
    # per the open-context rule in the header. Any raise aborts the operation
    # and the model is untouched.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__Build(entities, target, solve, plans, build_transform)
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

        # Rebuild phase.
        plans.each { |plan| Na__InsertPrimatives.Na__DrawnChamfer__RebuildFace(entities, plan, build_transform) }

        chamfer_face = entities.add_face(
            solve[:a0].transform(build_transform),
            solve[:a1].transform(build_transform),
            solve[:b1].transform(build_transform),
            solve[:b0].transform(build_transform)
        )
        raise 'the chamfer plane could not be created here' unless chamfer_face

        # Outward means away from the material — opposite the bisector — and
        # the new face dresses like the first chamfered face for continuity.
        session_bisector = solve[:bisector_local].transform(build_transform)
        chamfer_face.reverse! if session_bisector.valid? && chamfer_face.normal.dot(session_bisector) > 0.0
        chamfer_face.material      = plans[0][:material]      if plans[0][:material]
        chamfer_face.back_material = plans[0][:back_material] if plans[0][:back_material]
        chamfer_face.layer         = plans[0][:layer]         if plans[0][:layer]

        true
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Corner Mitres — Batch Edges Meeting at a Vertex
    # -----------------------------------------------------------------------------
    #
    # Two banked edges sharing a vertex cannot be cut independently: the first
    # cut erases the shared face, at which moment the second edge bounds nothing
    # and the stray sweep erases IT. Worked through on a box corner, the correct
    # geometry is a MITRE, exactly as in a picture frame:
    #
    #   P — where the two offset lines cross on the SHARED face — becomes that
    #       face's new corner, replacing the old vertex outright.
    #   M — the lower offset point, which both edges place at the same spot on a
    #       square corner — terminates the mitre below.
    #   Each chamfer quad ends on the edge P—M instead of its own end cap, the
    #   two quads knit along it, and NO end triangles exist at that corner.
    #   Each edge's OTHER face keeps its plain single substitution; the partner
    #   contributes nothing to it (its would-be end clip is a subset of the
    #   strip already removed).
    #
    # Corners whose two lower offset points do NOT coincide (non-square in the
    # third direction) need extra facets this does not build — they refuse with
    # an honest message rather than cutting wrongly. So do three-way corners.
    # -----------------------------------------------------------------------------

    # FUNCTION | Read One End Point of a Solve (:a or :b Side)
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__EndPoint(solve, end_index, side)
        key = side == :a ? (end_index.zero? ? :a0 : :a1) : (end_index.zero? ? :b0 : :b1)
        solve[key]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Overwrite One End Point of a Solve, Local and World
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__PatchEnd(solve, end_index, side, point, xform)
        key = side == :a ? (end_index.zero? ? :a0 : :a1) : (end_index.zero? ? :b0 : :b1)
        solve[key]         = point
        solve[:world][key] = point.transform(xform)
        solve[end_index.zero? ? :mitre0 : :mitre1] = true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Give One End of a Solve Its Corner Apex Point
    # Only a three-way mitre sets this: the chamfer face's end becomes three
    # points — P, then this apex Q, then the other P — a pentagon end.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__PatchCorner(solve, end_index, point, xform)
        key                = end_index.zero? ? :corner0 : :corner1
        solve[key]         = point
        solve[:world][key] = point.transform(xform)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Chamfer Face's Boundary Loop, Local Space
    # A plain or two-way-mitred end contributes two points (the quad case); a
    # three-way end slots its apex between them, growing the face to a pentagon
    # — or a hexagon when both ends of the edge meet three-way corners.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__FaceLoopLocal(solve)
        loop_points = [solve[:a0], solve[:a1]]
        loop_points << solve[:corner1] if solve[:corner1]
        loop_points << solve[:b1] << solve[:b0]
        loop_points << solve[:corner0] if solve[:corner0]
        loop_points
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Chamfer Face's Boundary Loop, World Space
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__FaceLoopWorld(solve)
        world       = solve[:world]
        loop_points = [world[:a0], world[:a1]]
        loop_points << world[:corner1] if world[:corner1]
        loop_points << world[:b1] << world[:b0]
        loop_points << world[:corner0] if world[:corner0]
        loop_points
    end
    # ---------------------------------------------------------------

    # FUNCTION | Mitre a Corner Where THREE Chamfered Edges Meet
    # The X-Y-Z junction: a box corner with all three of its edges banked.
    #
    # Worked through and verified numerically: the three chamfer planes are
    # CONCURRENT — three planes in general position always meet at one point Q
    # (on a square corner with setback d, Q sits at (d/2, d/2, -d/2) from the
    # vertex). So no corner facet is ever needed. Each pair of edges gets its
    # ordinary shared-face mitre point P, each chamfer face's end becomes the
    # three points P–Q–P (a pentagon), the three pentagons pairwise share their
    # P–Q mitre edges, and the corner closes itself.
    #
    # The face substitutions need nothing new: every face at the vertex is the
    # shared face of exactly one pair and borders two of the three edges, so it
    # receives the SAME P from both — which MergeSingles already dedupes.
    #
    # Everything is computed from the ORIGINAL solve points first and patched
    # last, and any degenerate step refuses the group before anything is cut.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__MitreThreeWay(vertex, members, targets, solves)
        picks = members.map do |index, end_index|
            { :index => index, :end => end_index, :target => targets[index], :solve => solves[index] }
        end

        all_faces = picks[0][:target][:faces] | picks[1][:target][:faces] | picks[2][:target][:faces]
        extra     = vertex.faces - all_faces
        return 'the three-way corner carries extra faces — cut those edges separately' unless extra.empty?

        # Pairwise shared faces and their P points, from the unpatched solves.
        pair_info    = {}
        shared_seen  = []

        [[0, 1], [0, 2], [1, 2]].each do |m, n|
            shared = picks[m][:target][:faces] & picks[n][:target][:faces]
            return 'each pair of edges at a three-way corner must share exactly one face' unless shared.length == 1
            return 'the faces at this three-way corner are tangled — cut the edges separately' if shared_seen.include?(shared[0])
            shared_seen << shared[0]

            side_m = picks[m][:target][:faces][0] == shared[0] ? :a : :b
            side_n = picks[n][:target][:faces][0] == shared[0] ? :a : :b

            direction_m = picks[m][:solve][:v1] - picks[m][:solve][:v0]
            direction_n = picks[n][:solve][:v1] - picks[n][:solve][:v0]
            return 'a shared-corner edge has no length' if direction_m.length == 0 || direction_n.length == 0

            p_shared = Geom.intersect_line_line(
                [Na__InsertPrimatives.Na__DrawnChamfer__EndPoint(picks[m][:solve], picks[m][:end], side_m), direction_m],
                [Na__InsertPrimatives.Na__DrawnChamfer__EndPoint(picks[n][:solve], picks[n][:end], side_n), direction_n]
            )
            return 'edges are parallel where they meet — no mitre exists there' unless p_shared

            pair_info[[m, n]] = { :point => p_shared, :side_m => side_m, :side_n => side_n }
        end

        # The three chamfer planes, from the unpatched geometry.
        planes = picks.map do |pick|
            solve   = pick[:solve]
            a_end   = pick[:end].zero? ? solve[:a0] : solve[:a1]
            b_end   = pick[:end].zero? ? solve[:b0] : solve[:b1]
            chord   = b_end - a_end
            heading = solve[:v1] - solve[:v0]
            normal  = heading.cross(chord)
            return 'a chamfer plane at the corner is degenerate' if normal.length == 0

            [a_end, normal.normalize]
        end

        seam = planes[0][1].cross(planes[1][1])
        return 'two chamfer planes at the corner are parallel — no meeting point' if seam.length == 0

        apex = Geom.intersect_line_plane([pair_info[[0, 1]][:point], seam], planes[2])
        return 'the three chamfer planes do not meet at this corner' unless apex

        # Patch phase — every computation above used original points.
        [[0, 1], [0, 2], [1, 2]].each do |m, n|
            info = pair_info[[m, n]]
            Na__InsertPrimatives.Na__DrawnChamfer__PatchEnd(picks[m][:solve], picks[m][:end], info[:side_m], info[:point], picks[m][:target][:transformation])
            Na__InsertPrimatives.Na__DrawnChamfer__PatchEnd(picks[n][:solve], picks[n][:end], info[:side_n], info[:point], picks[n][:target][:transformation])
        end

        picks.each do |pick|
            Na__InsertPrimatives.Na__DrawnChamfer__PatchCorner(pick[:solve], pick[:end], apex, pick[:target][:transformation])
        end

        nil
    rescue StandardError => error
        "three-way mitre failed: #{error.message}"
    end
    # ---------------------------------------------------------------

    # FUNCTION | Find and Apply Every Corner Mitre in a Batch
    # Mutates the solves: shared-side end points move to P, mitre flags are set.
    # Returns nil on success or an honest refusal message — the caller decides
    # whether that aborts (commit) or just previews unmitred (drag).
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__MitreBatch(targets, solves)
        ends = {}

        targets.each_with_index do |target, index|
            next unless solves[index]

            edge = target[:edge]
            next unless edge && edge.valid?

            (ends[edge.start] ||= []) << [index, 0]
            (ends[edge.end]   ||= []) << [index, 1]
        end

        ends.each do |vertex, members|
            next if members.length < 2

            if members.length == 3
                error = Na__InsertPrimatives.Na__DrawnChamfer__MitreThreeWay(vertex, members, targets, solves)
                return error if error
                next
            end

            return 'more than three chamfered edges meet at one corner — cut them in stages' if members.length > 3

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
            return 'the corner where these edges meet carries extra faces — cut those edges separately' unless extra_faces.empty?

            side_a = target_a[:faces][0] == shared_face ? :a : :b               # <-- Which offset line of each solve rides the shared face
            side_b = target_b[:faces][0] == shared_face ? :a : :b
            other_a = side_a == :a ? :b : :a
            other_b = side_b == :a ? :b : :a

            lower_a = Na__InsertPrimatives.Na__DrawnChamfer__EndPoint(solve_a, end_a, other_a)
            lower_b = Na__InsertPrimatives.Na__DrawnChamfer__EndPoint(solve_b, end_b, other_b)
            if lower_a.distance(lower_b) > NA_CHAMFER_MITRE_TOL
                return 'this corner is not square enough to mitre — chamfer these edges separately'
            end

            direction_a = solve_a[:v1] - solve_a[:v0]
            direction_b = solve_b[:v1] - solve_b[:v0]
            return 'a shared-corner edge has no length' if direction_a.length == 0 || direction_b.length == 0

            joint = Geom.intersect_line_line(
                [Na__InsertPrimatives.Na__DrawnChamfer__EndPoint(solve_a, end_a, side_a), direction_a],
                [Na__InsertPrimatives.Na__DrawnChamfer__EndPoint(solve_b, end_b, side_b), direction_b]
            )
            return 'edges are parallel where they meet — no mitre exists there' unless joint

            Na__InsertPrimatives.Na__DrawnChamfer__PatchEnd(solve_a, end_a, side_a, joint, target_a[:transformation])
            Na__InsertPrimatives.Na__DrawnChamfer__PatchEnd(solve_b, end_b, side_b, joint, target_b[:transformation])
        end

        nil
    rescue StandardError => error
        "mitre solving failed: #{error.message}"
    end
    # ---------------------------------------------------------------

    # FUNCTION | Merge Accumulated Single Substitutions for One Face
    # A shared face collects the same corner from both its edges — identical
    # points dedupe, genuinely different points mean two cuts disagree and the
    # whole group must refuse rather than build either.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__MergeSingles(singles)
        merged = []

        singles.each do |corner, replacement|
            twin = merged.find { |existing_corner, _| Na__InsertPrimatives.Na__DrawnChamfer__SamePoint?(existing_corner, corner) }

            if twin.nil?
                merged << [corner, replacement]
            elsif !Na__InsertPrimatives.Na__DrawnChamfer__SamePoint?(twin[1], replacement)
                raise 'two chamfers disagree about the same corner — cut them separately'
            end
        end

        merged
    end
    # ---------------------------------------------------------------

    # FUNCTION | Plan Every Face a Whole Batch Group Touches, Exactly Once
    # The per-edge planner cannot serve a batch: parallel edges share a face
    # (one plan must carry BOTH strips) and mitred corners change what an end
    # contributes. Substitutions accumulate per face and are merged; mitred
    # ends contribute no end-face pairs at all — the mitre IS their ending.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__BuildGroupPlans(targets, solves)
        accumulators = {}
        fetch        = lambda { |face| accumulators[face] ||= { :singles => [], :pairs => [] } }

        targets.each_with_index do |target, index|
            solve          = solves[index]
            edge           = target[:edge]
            face_a, face_b = target[:faces]

            fetch.call(face_a)[:singles] << [solve[:v0], solve[:a0]] << [solve[:v1], solve[:a1]]
            fetch.call(face_b)[:singles] << [solve[:v0], solve[:b0]] << [solve[:v1], solve[:b1]]

            [[edge.start, solve[:v0], solve[:a0], solve[:b0], solve[:mitre0]],
             [edge.end,   solve[:v1], solve[:a1], solve[:b1], solve[:mitre1]]].each do |vertex, corner, point_a, point_b, mitred|
                next if mitred

                (vertex.faces - [face_a, face_b]).each do |end_face|
                    fetch.call(end_face)[:pairs] << [corner, point_a, point_b]
                end
            end
        end

        accumulators.map do |face, subs|
            plan = Na__InsertPrimatives.Na__DrawnChamfer__RebuildPlan(
                face,
                Na__InsertPrimatives.Na__DrawnChamfer__MergeSingles(subs[:singles]),
                subs[:pairs]
            )
            plan[:entities] = face.parent.respond_to?(:entities) ? face.parent.entities : nil
            plan
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Erase and Rebuild a Whole Batch Group in One Pass
    # Everything is planned before this runs; a raise aborts the operation and
    # the group is untouched. Quads dress from their own face_a's captured plan.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__BuildGroup(model, targets, solves, plans, build_transform)
        dress_by_face = {}
        plans.each { |plan| dress_by_face[plan[:face]] = plan }

        quad_dress = targets.map { |target| dress_by_face[target[:faces][0]] || plans[0] }
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

        targets.each_with_index do |_target, index|
            solve = solves[index]

            # The loop, not a fixed quad: a three-way-mitred end carries its
            # apex point, making the face a pentagon (or hexagon, both ends).
            chamfer_face = entity_set[index].add_face(
                Na__InsertPrimatives.Na__DrawnChamfer__FaceLoopLocal(solve).map { |point| point.transform(build_transform) }
            )
            raise 'a chamfer plane could not be created in the batch' unless chamfer_face

            session_bisector = solve[:bisector_local].transform(build_transform)
            chamfer_face.reverse! if session_bisector.valid? && chamfer_face.normal.dot(session_bisector) > 0.0

            source = quad_dress[index]
            chamfer_face.material      = source[:material]      if source[:material]
            chamfer_face.back_material = source[:back_material] if source[:back_material]
            chamfer_face.layer         = source[:layer]         if source[:layer]
        end

        true
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Deep Chamfer Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Chamfer Any Edge at Any Nesting Depth
    # ------------------------------------------------------------
    class DrawnChamferTool

        include Na__InsertPrimatives::DrawnToolShared

        NA_CH_HOVER_COLOR   = Sketchup::Color.new(  0, 110, 235, 235)
        NA_CH_SELECT_COLOR  = Sketchup::Color.new(226, 118,   0, 255)         # <-- Edges banked with SHIFT, waiting for the drag
        NA_CH_EDGE_WIDTH    = 5
        NA_CH_MK_SHIFT      = 4                                               # <-- Shift bit in the mouse-event flags (CTRL is 8)

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            na_drawn__init_shared_state
            na_drawn__clear_target
            @na_ch_multi        = []                                          # <-- SHIFT-banked edge targets, surviving hover and drag-cancel
            @na_ch_batch        = []                                          # <-- Driver + banked, fixed at grab time
            @na_ch_batch_solves = []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Forget the Currently Grabbed Edge
        # The SHIFT-banked selection deliberately lives OUTSIDE this reset: it
        # must survive hovering off an edge and cancelling a drag, and is only
        # emptied by a successful cut, ESC at idle, or a fresh tool.
        # ------------------------------------------------------------
        def na_drawn__clear_target
            @na_ch_target       = nil
            @na_ch_solve        = nil
            @na_ch_anchor       = nil                                         # <-- Grab point on the edge, world
            @na_ch_bisector     = nil                                         # <-- Unit world diagonal into the material
            @na_ch_edge_dir     = nil                                         # <-- Unit world direction along the edge
            @na_ch_plane_normal = nil                                         # <-- Normal of the corner measurement plane
            @na_ch_cos_half     = 1.0
            @na_ch_batch        = []
            @na_ch_batch_solves = []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Target Already Banked? (Index or nil)
        # Same edge through the same instance path counts as the same pick —
        # the identical definition edge seen through a DIFFERENT instance is a
        # different chamfer and stays distinct.
        # ------------------------------------------------------------
        def na_drawn__multi_index_of(target)
            @na_ch_multi.find_index do |banked|
                banked[:edge] == target[:edge] && banked[:path] == target[:path]
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | SHIFT+Click — Bank an Edge, or Un-Bank It Again
        # Each edge is validated on the way IN, so the drag never starts with a
        # passenger that cannot be cut.
        # ------------------------------------------------------------
        def na_drawn__toggle_multi_edge(view, x, y)
            target = Na__InsertPrimatives.Na__DeepPick__EdgeAt(view, x, y)

            unless target
                UI.beep
                Sketchup::set_status_text('No edge under the cursor to add', SB_PROMPT)
                return false
            end

            existing = na_drawn__multi_index_of(target)
            if existing
                @na_ch_multi.delete_at(existing)
                Sketchup::set_status_text("Edge removed — #{@na_ch_multi.length} banked", SB_PROMPT)
                return true
            end

            if target[:locked]
                UI.beep
                Sketchup::set_status_text('That edge is inside a locked group or component', SB_PROMPT)
                return false
            end

            unless target[:face_count] == 2
                UI.beep
                Sketchup::set_status_text("A chamfer needs an edge bordering exactly two faces (this one has #{target[:face_count]})", SB_PROMPT)
                return false
            end

            unless Na__InsertPrimatives.Na__DrawnChamfer__Solve(target, 1.0)
                UI.beep
                Sketchup::set_status_text('These faces are too close to flat for a chamfer', SB_PROMPT)
                return false
            end

            @na_ch_multi << target
            Sketchup::set_status_text("#{@na_ch_multi.length} edge#{@na_ch_multi.length == 1 ? '' : 's'} banked — SHIFT+click adds more, click one to drag them all", SB_PROMPT)
            true
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            'Deep Chamfer'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_chamfer
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'Hover an edge, click to grab it, drag into the corner, click to cut',
                'SHIFT+click banks edges, then one drag cuts them all — BKSP un-banks, ESC clears',
                'Reaches edges inside groups and components without opening them',
                "Setback snaps to the #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel} grid — hold CTRL for vertex snapping",
                'VCB: 50 | +5 | -5   (the typed setback pins and cuts)',
                'The edge must border exactly two faces'
            ]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | State Containment (Push/Pull Pattern)
        # -----------------------------------------------------------------------------

        # FUNCTION | This Tool Has Exactly Two States
        # ------------------------------------------------------------
        def na_drawn__ensure_known_state
            return true if @na_state == :idle || @na_state == :picking_depth

            na_drawn__reset_pick_state
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Backspace Releases the Edge, It Does Not Half-Retreat
        # At idle with a SHIFT bank, it un-banks the newest edge instead — the
        # same newest-first peel the dimension locks use.
        # ------------------------------------------------------------
        def na_drawn__step_back(view)
            released = na_drawn__release_last_lock

            unless released
                if @na_state == :idle && @na_ch_multi.any?
                    @na_ch_multi.pop
                    Sketchup::set_status_text("Edge un-banked — #{@na_ch_multi.length} remaining", SB_PROMPT)
                else
                    na_drawn__reset_pick_state
                end
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # FUNCTION | ESC Clears the Bank Before It Leaves the Tool
        # Mid-drag ESC drops the drag but KEEPS the banked edges — abandoning
        # one drag should not cost a carefully built selection. A second ESC at
        # idle empties the bank, and only an ESC with nothing held exits.
        # ------------------------------------------------------------
        def onCancel(reason, view)
            if @na_state == :idle && @na_ch_multi.any? && reason == 0
                @na_ch_multi.clear
                Sketchup::set_status_text('Banked edges cleared', SB_PROMPT)
                na_drawn__update_status_text
                view.invalidate if view
                return
            end

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Return to Hovering
        # ------------------------------------------------------------
        def na_drawn__reset_pick_state
            super
            na_drawn__clear_target
            @na_size_d = 0.0
            @na_sign_d = 1.0
        end
        # ---------------------------------------------------------------

        # FUNCTION | Enter Cuts the Chamfer
        # ------------------------------------------------------------
        def onReturn(view)
            return false unless na_drawn__ensure_known_state
            return false unless @na_state == :picking_depth

            na_drawn__commit_chamfer(view)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Double Click Cuts the Chamfer
        # ------------------------------------------------------------
        def onLButtonDoubleClick(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            return false unless na_drawn__ensure_known_state
            return false unless @na_state == :picking_depth

            na_drawn__update_cursor(view, x, y)
            na_drawn__commit_chamfer(view)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Arrow Keys Have No Meaning on a Chamfer
        # ------------------------------------------------------------
        def na_drawn__apply_axis_lock(axis, view)
            Sketchup::set_status_text('A chamfer follows its own corner — axis locks are not used here', SB_PROMPT)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | TAB Has Nothing to Cycle Here
        # ------------------------------------------------------------
        def na_drawn__cycle_plane_lock(view)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | What TAB Does in This Tool
        # ------------------------------------------------------------
        def na_drawn__tab_hint
            ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | Describe the Grabbed Edge Rather Than a Drawing Plane
        # ------------------------------------------------------------
        def na_drawn__plane_description
            return 'No edge grabbed' unless @na_ch_target

            "In #{Na__InsertPrimatives.Na__DeepPick__PathLabel(@na_ch_target)}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Nothing to Revise — a Cut Edge Is Gone
        # ------------------------------------------------------------
        def na_drawn__revise_available?
            false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Cursor Tracking — No Picking Mid-Drag
        # -----------------------------------------------------------------------------

        # FUNCTION | Measure the Drag Across the Corner Plane
        # The cursor ray is intersected with the CORNER PLANE — the plane
        # through the grab point spanned by the edge direction and the bisector
        # — and the hit's component along the bisector becomes the travel.
        # Because the bisector is exactly perpendicular to the edge, motion
        # parallel to the edge contributes nothing, and at the grab instant the
        # hit sits on the edge itself, so the chamfer starts from zero.
        #
        # The first build projected onto the bisector LINE with a closest-
        # points solve instead. That is ill-conditioned whenever the click
        # lands away from the line's anchor — grabbing near the end of a long
        # edge opened with a phantom setback of over a metre, only settling as
        # the cursor wandered toward the midpoint. A ray-plane intersection has
        # no such regime: it is stable anywhere along the edge.
        #
        # The chamfer chord crosses the bisector at t = d * cos_half, so the
        # WYSIWYG mapping — cut plane under the cursor — is d = t / cos_half.
        # The setback is what snaps to the grid. An unsolvable frame (view
        # grazing the corner plane) keeps the last good value; nothing is ever
        # re-picked unless CTRL asks for vertex inference.
        # ------------------------------------------------------------
        def na_drawn__update_cursor(view, x, y)
            @na_last_mouse_x = x
            @na_last_mouse_y = y

            return false unless @na_state == :picking_depth && @na_ch_anchor && @na_ch_bisector

            source =
                if @na_ctrl_held
                    na_drawn__input_point_position(view, x, y)                # <-- Deliberate vertex snapping only
                else
                    na_drawn__corner_plane_point(view, x, y)
                end

            return false unless source

            travel  = (source - @na_ch_anchor).dot(@na_ch_bisector).to_f
            setback = na_drawn__snap_distance(travel / @na_ch_cos_half).to_f
            setback = 0.0 if setback < 0.0                                    # <-- Dragging out of the corner closes the chamfer

            return false if na_drawn__locked?(:d)

            @na_size_d = setback
            @na_sign_d = 1.0
            na_drawn__refresh_solve
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Intersect the Pick Ray with the Corner Plane
        # ------------------------------------------------------------
        def na_drawn__corner_plane_point(view, x, y)
            return nil unless @na_ch_plane_normal

            ray = view.pickray(x, y)
            hit = Geom.intersect_line_plane(ray, [@na_ch_anchor, @na_ch_plane_normal])
            return nil unless hit

            na_drawn__point_in_front_of_ray?(ray, hit) ? hit : nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Re-Solve the Chamfer Geometry for the Live Setback
        # ------------------------------------------------------------
        def na_drawn__refresh_solve
            @na_ch_solve        = nil
            @na_ch_batch_solves = []
            @na_ch_mitre_note   = nil
            return unless @na_ch_target && @na_size_d.to_f > 0.0

            if @na_ch_batch.length <= 1
                @na_ch_solve = Na__InsertPrimatives.Na__DrawnChamfer__Solve(@na_ch_target, @na_size_d)
                return
            end

            # The whole batch solves ALIGNED with its targets so the mitre pass
            # can pair shared corners up, then the same patched solves feed the
            # preview — the mitred quads on screen are the quads that will land.
            # A refusal here does not kill the drag: the preview falls back to
            # the unmitred shapes and the note explains what commit will say.
            all_solves = @na_ch_batch.map do |member|
                Na__InsertPrimatives.Na__DrawnChamfer__Solve(member, @na_size_d)
            end

            @na_ch_solve = all_solves[0]
            return unless @na_ch_solve

            if all_solves.all?
                @na_ch_mitre_note = Na__InsertPrimatives.Na__DrawnChamfer__MitreBatch(@na_ch_batch, all_solves)
            end

            @na_ch_batch_solves = all_solves[1..-1].compact
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Mouse — Grab an Edge, Then Open the Chamfer
        # -----------------------------------------------------------------------------

        # ON MOUSE MOVE | Hover Highlight While Idle, Setback While Dragging
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            na_drawn__ensure_known_state
            @na_last_mouse_x = x
            @na_last_mouse_y = y

            if @na_state == :idle
                @na_ch_target = Na__InsertPrimatives.Na__DeepPick__EdgeAt(view, x, y)
            else
                na_drawn__update_cursor(view, x, y)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOWN | Grab an Edge, or Cut the Chamfer
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @na_vcb_typing_active = false
            na_drawn__sync_modifier(flags)
            na_drawn__ensure_known_state
            @na_last_mouse_x = x
            @na_last_mouse_y = y

            case @na_state
            when :idle
                if (flags.to_i & NA_CH_MK_SHIFT) != 0
                    na_drawn__toggle_multi_edge(view, x, y)                   # <-- SHIFT banks edges; the plain click drags them all
                else
                    na_drawn__grab_edge(view, x, y)
                end
            when :picking_depth
                @na_drag_press_active = false
                na_drawn__update_cursor(view, x, y)
                na_drawn__commit_chamfer(view)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take Hold of the Edge Under the Cursor
        # ------------------------------------------------------------
        def na_drawn__grab_edge(view, x, y)
            target = Na__InsertPrimatives.Na__DeepPick__EdgeAt(view, x, y)

            unless target
                UI.beep
                Sketchup::set_status_text('No edge under the cursor', SB_PROMPT)
                return false
            end

            if target[:locked]
                UI.beep
                Sketchup::set_status_text('That edge is inside a locked group or component', SB_PROMPT)
                return false
            end

            unless target[:face_count] == 2
                UI.beep
                Sketchup::set_status_text("A chamfer needs an edge bordering exactly two faces (this one has #{target[:face_count]})", SB_PROMPT)
                return false
            end

            probe = Na__InsertPrimatives.Na__DrawnChamfer__Solve(target, 1.0)
            unless probe
                UI.beep
                Sketchup::set_status_text('These faces are too close to flat for a chamfer', SB_PROMPT)
                return false
            end

            @na_ch_target = target

            # The interactive frame, all world space. The anchor is the point on
            # the edge actually clicked (not the midpoint), so the crosshair sits
            # under the cursor and the corner plane is anchored where the drag
            # begins — with the bisector perpendicular to the edge, the position
            # along the edge changes nothing about the measurement itself.
            xform     = target[:transformation]
            world_v0  = probe[:world][:v0]
            world_v1  = probe[:world][:v1]
            midpoint  = Geom::Point3d.new(
                (world_v0.x.to_f + world_v1.x.to_f) * 0.5,
                (world_v0.y.to_f + world_v1.y.to_f) * 0.5,
                (world_v0.z.to_f + world_v1.z.to_f) * 0.5
            )

            edge_vector = world_v1 - world_v0
            if edge_vector.length == 0
                UI.beep
                Sketchup::set_status_text('This edge has no length', SB_PROMPT)
                return false
            end
            @na_ch_edge_dir = edge_vector.normalize

            @na_ch_anchor =
                begin
                    grab_ray = view.pickray(x, y)
                    on_edge  = Geom.closest_points([world_v0, @na_ch_edge_dir], grab_ray)
                    on_edge && on_edge[0] ? on_edge[0] : midpoint
                rescue StandardError
                    midpoint
                end

            @na_ch_bisector = probe[:bisector_local].transform(xform).normalize
            @na_ch_cos_half = probe[:cos_half].to_f.abs
            @na_ch_cos_half = 1.0 if @na_ch_cos_half < NA_CHAMFER_MIN_COS_HALF

            # The corner measurement plane: spanned by the edge and the
            # bisector, so a ray-plane hit is stable anywhere along the edge.
            @na_ch_plane_normal = @na_ch_edge_dir.cross(@na_ch_bisector)
            if @na_ch_plane_normal.length == 0                                # <-- Cannot happen for a valid corner, but never divide by it
                UI.beep
                Sketchup::set_status_text('This corner cannot be measured', SB_PROMPT)
                return false
            end
            @na_ch_plane_normal.normalize!

            na_drawn__clear_locks
            @na_state             = :picking_depth
            @na_size_d            = 0.0
            @na_sign_d            = 1.0
            @na_ch_solve          = nil
            @na_drag_press_active = true                                      # <-- Arms press-drag-release
            @na_press_x           = @na_last_mouse_x
            @na_press_y           = @na_last_mouse_y

            # The batch this drag will cut: the clicked edge drives the
            # measurement, every banked edge rides along at the same world
            # setback. Clicking an edge already banked does not double it.
            @na_ch_batch        = [target] + @na_ch_multi.reject do |banked|
                banked[:edge] == target[:edge] && banked[:path] == target[:path]
            end
            @na_ch_batch_solves = []

            if @na_ch_batch.length > 1
                Sketchup::set_status_text("Dragging #{@na_ch_batch.length} edges together", SB_PROMPT)
            elsif target[:shared_count].to_i > 1
                Sketchup::set_status_text(
                    "Heads up: this definition has #{target[:shared_count]} instances — chamfering changes all of them",
                    SB_PROMPT
                )
            end

            true
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON UP | Press-Drag-Release Cuts Too
        # ------------------------------------------------------------
        def onLButtonUp(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            return unless @na_state == :picking_depth
            return unless @na_drag_press_active

            @na_drag_press_active = false
            travelled_px = (x.to_f - @na_press_x.to_f).abs + (y.to_f - @na_press_y.to_f).abs
            return if travelled_px < NA_DRAWN_DRAG_MIN_PX

            na_drawn__update_cursor(view, x, y)
            na_drawn__commit_chamfer(view)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Drag Completion
        # -----------------------------------------------------------------------------

        # FUNCTION | Never Reached — This Tool Has No Rectangle Stage
        # ------------------------------------------------------------
        def na_drawn__advance_from_b(view)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Setback Settled — Cut the Chamfer
        # ------------------------------------------------------------
        def na_drawn__advance_from_depth(view)
            na_drawn__commit_chamfer(view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Points the Preview Occupies, for the Draw Extents
        # ------------------------------------------------------------
        def na_drawn__preview_points
            points = []

            if @na_ch_target && @na_ch_target[:edge] && @na_ch_target[:edge].valid?
                xform = @na_ch_target[:transformation]
                points << @na_ch_target[:edge].start.position.transform(xform)
                points << @na_ch_target[:edge].end.position.transform(xform)
            end

            if @na_ch_solve
                world = @na_ch_solve[:world]
                points.concat([world[:a0], world[:a1], world[:b0], world[:b1]])
            end

            @na_ch_batch_solves.each do |rider|
                world = rider[:world]
                points.concat([world[:a0], world[:a1], world[:b0], world[:b1]])
            end

            @na_ch_multi.each do |banked|
                next unless banked[:edge] && banked[:edge].valid?

                xform = banked[:transformation]
                points << banked[:edge].start.position.transform(xform)
                points << banked[:edge].end.position.transform(xform)
            end

            points
        end
        # ---------------------------------------------------------------

        # DRAW | Edge Highlight While Idle, Chamfer Preview While Dragging
        # ------------------------------------------------------------
        def draw(view)
            @na_ip.draw(view) if @na_ctrl_held && @na_ip && @na_ip.valid?

            na_drawn__draw_banked_edges(view)

            if @na_state == :idle
                na_drawn__draw_edge_highlight(view)
                return
            end

            na_drawn__draw_preview(view)
            Na__InsertPrimatives.Na__DrawnPreview__DrawCrosshair(view, @na_ch_anchor, nil, NA_DRAWN_ANCHOR_COLOR)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw Every SHIFT-Banked Edge in the Selection Colour
        # Kept visible during the drag too, so the set being cut never has to be
        # held in the user's head. A banked edge that has died (undone away)
        # silently drops from the bank rather than drawing garbage.
        # ------------------------------------------------------------
        def na_drawn__draw_banked_edges(view)
            return if @na_ch_multi.empty?

            @na_ch_multi.delete_if { |banked| banked[:edge].nil? || !banked[:edge].valid? }

            view.line_stipple  = ''
            view.line_width    = NA_CH_EDGE_WIDTH
            view.drawing_color = NA_CH_SELECT_COLOR

            @na_ch_multi.each do |banked|
                xform = banked[:transformation]
                ends  = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace([
                    banked[:edge].start.position.transform(xform),
                    banked[:edge].end.position.transform(xform)
                ])
                view.draw_line(ends[0], ends[1])
            end

            view.line_width = 2
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw a Setback Dimension Nudged Clear of the Geometry
        # Anchored at the guide-line midpoint, then pushed further along the
        # screen direction AWAY from the cut plane's centre, so the number sits
        # beside the shape instead of on top of the corner — whatever the view.
        # ------------------------------------------------------------
        def na_drawn__draw_setback_label(view, from_point, to_point, quad_centre, locked)
            midpoint = Geom::Point3d.new(
                (from_point.x.to_f + to_point.x.to_f) * 0.5,
                (from_point.y.to_f + to_point.y.to_f) * 0.5,
                (from_point.z.to_f + to_point.z.to_f) * 0.5
            )

            screen_mid    = view.screen_coords(
                Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(midpoint)
            )
            screen_centre = view.screen_coords(
                Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(quad_centre)
            )
            push_x        = screen_mid.x.to_f - screen_centre.x.to_f
            push_y        = screen_mid.y.to_f - screen_centre.y.to_f
            push_length   = Math.sqrt((push_x * push_x) + (push_y * push_y))

            if push_length < 1.0                                              # <-- Edge-on view: fall back to a plain sideways nudge
                push_x = 1.0
                push_y = 0.0
                push_length = 1.0
            end

            offset_px = 34.0
            Na__InsertPrimatives.Na__DrawnPreview__DrawScreenText(
                view,
                screen_mid.x.to_f + (push_x / push_length * offset_px),
                screen_mid.y.to_f + (push_y / push_length * offset_px) - 6.0,
                Na__InsertPrimatives.Na__DrawnPreview__DimensionText(@na_size_d, locked),
                Na__InsertPrimatives.Na__DrawnPreview__DimensionColor(locked)
            )
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Highlight the Edge Under the Cursor
        # ------------------------------------------------------------
        def na_drawn__draw_edge_highlight(view)
            target = @na_ch_target
            return unless target && target[:edge] && target[:edge].valid?

            xform    = target[:transformation]
            world_v0 = target[:edge].start.position.transform(xform)
            world_v1 = target[:edge].end.position.transform(xform)

            hover_ends = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace([world_v0, world_v1])

            view.line_stipple  = ''
            view.line_width    = NA_CH_EDGE_WIDTH
            view.drawing_color = NA_CH_HOVER_COLOR
            view.draw_line(hover_ends[0], hover_ends[1])
            view.line_width    = 2

            length_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(world_v0.distance(world_v1)).abs
            usable    = target[:face_count] == 2
            second    = usable ? Na__InsertPrimatives.Na__DeepPick__PathLabel(target) : "#{target[:face_count]} faces — cannot chamfer"

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view, world_v1, ["#{length_mm} mm edge", second]
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw One Cut's Wedge and Chamfer Plane
        # The wedge being cut away, shaded in the plane blue — the two face
        # slivers plus the end triangles — so what disappears reads separately
        # from the amber cut plane that replaces it. Shared by the driver and
        # every SHIFT-banked rider; only the driver carries dimensions.
        # ------------------------------------------------------------
        def na_drawn__draw_cut_faces(view, solve)
            world = solve[:world]

            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledQuad(
                view, [world[:v0], world[:v1], world[:a1], world[:a0]],
                NA_DRAWN_PLANE_FILL_COLOR, NA_DRAWN_PLANE_BORDER_COLOR
            )
            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledQuad(
                view, [world[:v0], world[:v1], world[:b1], world[:b0]],
                NA_DRAWN_PLANE_FILL_COLOR, NA_DRAWN_PLANE_BORDER_COLOR
            )
            # A mitred end has no cap — the two chamfer planes meet along the
            # mitre line instead, so its triangle would just stab through the
            # partner's preview (exactly the artefact reported).
            unless solve[:mitre0]
                Na__InsertPrimatives.Na__DrawnPreview__DrawFilledPolygon(
                    view, [world[:v0], world[:a0], world[:b0]],
                    NA_DRAWN_PLANE_FILL_COLOR, NA_DRAWN_PLANE_BORDER_COLOR
                )
            end
            unless solve[:mitre1]
                Na__InsertPrimatives.Na__DrawnPreview__DrawFilledPolygon(
                    view, [world[:v1], world[:a1], world[:b1]],
                    NA_DRAWN_PLANE_FILL_COLOR, NA_DRAWN_PLANE_BORDER_COLOR
                )
            end

            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledPolygon(
                view, Na__InsertPrimatives.Na__DrawnChamfer__FaceLoopWorld(solve),
                NA_DRAWN_VOLUME_FILL_COLOR, NA_DRAWN_VOLUME_BORDER_COLOR
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Chamfer Cut Plane and Its Dimensions
        # The same solve feeds this preview and the commit, so the cut that
        # lands is exactly the one shown.
        # ------------------------------------------------------------
        def na_drawn__draw_preview(view)
            solve = @na_ch_solve

            unless solve
                na_drawn__draw_edge_highlight(view)
                return
            end

            world  = solve[:world]
            locked = na_drawn__locked?(:d)

            na_drawn__draw_cut_faces(view, solve)
            @na_ch_batch_solves.each { |rider| na_drawn__draw_cut_faces(view, rider) }

            Na__InsertPrimatives.Na__DrawnPreview__DrawGuideLine(view, world[:v0], world[:a0])
            Na__InsertPrimatives.Na__DrawnPreview__DrawGuideLine(view, world[:v0], world[:b0])

            quad_centre = Geom::Point3d.new(
                (world[:a0].x.to_f + world[:a1].x.to_f + world[:b0].x.to_f + world[:b1].x.to_f) * 0.25,
                (world[:a0].y.to_f + world[:a1].y.to_f + world[:b0].y.to_f + world[:b1].y.to_f) * 0.25,
                (world[:a0].z.to_f + world[:a1].z.to_f + world[:b0].z.to_f + world[:b1].z.to_f) * 0.25
            )
            na_drawn__draw_setback_label(view, world[:v0], world[:a0], quad_centre, locked)
            na_drawn__draw_setback_label(view, world[:v0], world[:b0], quad_centre, locked)

            width_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:width_world]).abs
            angle    = Na__InsertPrimatives.Na__DrawnFormat__Degrees(solve[:face_angle_deg])
            edge_mm  = Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:edge_len_world]).abs

            summary_lines = [
                "Chamfer #{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs} mm · face #{width_mm} wide",
                "#{angle} deg to each face · edge #{edge_mm} mm"
            ]
            if @na_ch_batch.length > 1
                summary_lines << "cutting #{@na_ch_batch_solves.length + 1} of #{@na_ch_batch.length} edges together"
            end

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, world[:a1], summary_lines)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Status and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Bar Line
        # ------------------------------------------------------------
        def na_drawn__status_detail
            if @na_state == :picking_depth
                setback = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs
                text    = na_drawn__locked?(:d) ? "[#{setback}]" : setback.to_s
                return "Chamfer #{text} mm — CORNER PROBLEM: #{@na_ch_mitre_note}" if @na_ch_mitre_note
                return "Chamfer #{text} mm — release or click to cut"
            end

            if @na_ch_target
                return 'Edge borders more than two faces — pick another' unless @na_ch_target[:face_count] == 2
                return "Click to grab this edge#{na_drawn__focus_hint}"
            end

            if @na_ch_multi.any?
                return "#{@na_ch_multi.length} edge#{@na_ch_multi.length == 1 ? '' : 's'} banked — SHIFT+click adds, click one to drag them all"
            end

            "Hover an edge to chamfer, at any nesting depth#{na_drawn__focus_hint}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            return ['Chamfer setback', ''] if @na_state != :picking_depth

            ['Chamfer setback', na_drawn__format_sizes([@na_size_d])]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Measurements Box Entry
        # -----------------------------------------------------------------------------

        # FUNCTION | A Typed Setback Pins and Cuts
        # ------------------------------------------------------------
        def na_drawn__handle_vcb_text(text, view)
            unless @na_state == :picking_depth
                UI.beep
                Sketchup::set_status_text('Grab an edge before typing a setback', SB_PROMPT)
                return false
            end

            tokens = Na__InsertPrimatives.Na__DrawnVcb__ParseEntry(text)
            raise ArgumentError, 'chamfer takes a single setback' if tokens.length > 1

            setbacks = Na__InsertPrimatives.Na__DrawnVcb__ResolveAgainst(tokens, [@na_size_d])
            Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive(setbacks, ['Setback'])

            @na_size_d = setbacks[0]
            na_drawn__lock_slot(:d)
            na_drawn__refresh_solve
            na_drawn__commit_chamfer(view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Geometry Commit
        # -----------------------------------------------------------------------------

        # FUNCTION | Cut the Chamfer
        # ------------------------------------------------------------
        def na_drawn__commit_chamfer(view)
            target = @na_ch_target

            unless target && target[:edge] && target[:edge].valid?
                UI.beep
                Sketchup::set_status_text('That edge is no longer available', SB_PROMPT)
                na_drawn__reset_pick_state
                return false
            end

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                UI.beep
                Sketchup::set_status_text('No setback — drag into the corner or type one', SB_PROMPT)
                return false
            end

            return na_drawn__commit_batch(view, @na_ch_batch) if @na_ch_batch.length > 1

            solve = Na__InsertPrimatives.Na__DrawnChamfer__Solve(target, @na_size_d)
            unless solve
                UI.beep
                Sketchup::set_status_text('This chamfer cannot be solved here', SB_PROMPT)
                return false
            end

            # Plans are made BEFORE the context is entered: reads stay in
            # unambiguous definition-local space, and a refusal here costs
            # nothing — no context change, no operation, no erase.
            begin
                plans = Na__InsertPrimatives.Na__DrawnChamfer__BuildPlans(target, solve)
            rescue StandardError => error
                UI.beep
                Sketchup::set_status_text("Chamfer refused: #{error.message}", SB_PROMPT)
                puts "NA CHAMFER refused: #{error.message}"
                return false
            end

            model  = Sketchup.active_model
            result = Na__InsertPrimatives.Na__DeepPick__ExecuteInContext(model, target[:path], 'Chamfer Edge') do
                parent   = target[:edge].parent
                entities = parent.respond_to?(:entities) ? parent.entities : model.active_entities

                # edit_transform IS the open session's coordinate system: the
                # entered path's accumulated transform once ExecuteInContext has
                # opened it, and the identity at root — read inside the block so
                # it reflects whatever actually happened.
                Na__InsertPrimatives.Na__DrawnChamfer__Build(entities, target, solve, plans, model.edit_transform)
            end

            unless result[:success]
                UI.beep
                Sketchup::set_status_text("Chamfer failed: #{result[:error]}", SB_PROMPT)
                na_drawn__reset_pick_state
                view.invalidate if view
                return false
            end

            na_drawn__log_chamfer(target, solve)
            @na_ch_multi.clear
            na_drawn__reset_pick_state
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Cut Every Edge in the Batch at the Same World Setback
        # Edges are grouped by their instance path, ONE operation per context —
        # so the common case of several edges on the same group undoes in a
        # single Ctrl+Z. Within a group each edge is re-validated, re-solved and
        # RE-PLANNED just before its own build: adjacent edges share faces, and
        # the first cut rebuilds the face the second one borders, so plans made
        # up front would hold erased references. Reads are definition-local
        # whether or not the context is open (the researched rule), so planning
        # while entered is sound. Any edge failing aborts its whole group —
        # all-or-nothing per context, never a half-cut group.
        # ------------------------------------------------------------
        def na_drawn__commit_batch(view, targets)
            model  = Sketchup.active_model
            groups = targets.group_by { |t| Na__InsertPrimatives.Na__DeepPick__Instances(t[:path]) }
            cut    = 0
            errors = []

            groups.each_value do |group_targets|
                result = Na__InsertPrimatives.Na__DeepPick__ExecuteInContext(
                    model, group_targets.first[:path], 'Chamfer Edges'
                ) do
                    # Validate and solve the whole group first, then mitre any
                    # shared corners, then plan every touched face exactly once,
                    # then erase-and-rebuild in a single pass. Independent
                    # sequential cuts cannot survive edges meeting at a vertex —
                    # the first cut's stray sweep erases the second edge — so
                    # the group is treated as one construction.
                    working      = []
                    group_solves = []

                    group_targets.each do |member|
                        edge = member[:edge]
                        raise 'an edge vanished mid-batch' unless edge && edge.valid?

                        faces = edge.faces
                        raise 'an edge no longer borders exactly two faces' unless faces.length == 2

                        fresh = member.merge(:faces => faces, :face_count => faces.length)
                        solve = Na__InsertPrimatives.Na__DrawnChamfer__Solve(fresh, @na_size_d)
                        raise 'an edge could not be solved at this setback' unless solve

                        working      << fresh
                        group_solves << solve
                    end

                    mitre_error = Na__InsertPrimatives.Na__DrawnChamfer__MitreBatch(working, group_solves)
                    raise mitre_error if mitre_error

                    plans = Na__InsertPrimatives.Na__DrawnChamfer__BuildGroupPlans(working, group_solves)
                    Na__InsertPrimatives.Na__DrawnChamfer__BuildGroup(model, working, group_solves, plans, model.edit_transform)
                end

                if result[:success]
                    cut += group_targets.length
                else
                    errors << result[:error]
                end
            end

            if cut.zero?
                UI.beep
                Sketchup::set_status_text("Chamfer failed: #{errors.first}", SB_PROMPT)
                puts "NA CHAMFER batch failed: #{errors.join(' | ')}"
                na_drawn__reset_pick_state
                view.invalidate if view
                return false
            end

            puts "\n"
            puts '----------------------------------------'
            puts 'DEEP CHAMFER BATCH CUT'
            puts "Edges  : #{cut} of #{targets.length} cut at #{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs}mm"
            puts "Groups : #{groups.length} context#{groups.length == 1 ? '' : 's'} (one undo step each)"
            errors.each { |message| puts "Refused: #{message}" }
            puts '----------------------------------------'

            if errors.any?
                Sketchup::set_status_text("#{cut} edges cut — #{errors.length} group(s) refused, see console", SB_PROMPT)
            end

            @na_ch_multi.clear
            na_drawn__reset_pick_state
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Completed Chamfer
        # ------------------------------------------------------------
        def na_drawn__log_chamfer(target, solve)
            puts "\n"
            puts '----------------------------------------'
            puts 'DEEP CHAMFER CUT'
            puts "Target : #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}"
            puts "Setback: #{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs}mm each face"
            puts "Face   : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:width_world]).abs}mm wide at #{Na__InsertPrimatives.Na__DrawnFormat__Degrees(solve[:face_angle_deg])} deg"
            puts "Edge   : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:edge_len_world]).abs}mm long"
            puts "Instances affected: #{target[:shared_count]}"
            puts "Grid   : #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
            puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnChamferTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Deep Chamfer Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind in Preferences -> Shortcuts against the Extensions menu item, or call
    # directly: Na__InsertPrimatives.Na__InsertPrimatives__DeepChamfer
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DeepChamfer
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnChamferTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP CHAMFER TOOL MODULE
# =============================================================================
