# =============================================================================
# NA INSERT PRIMATIVES - DEEP CHAMFER CORNER MITRES
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnChamfer__Mitre__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Batch mitre when several chamfered edges meet at a vertex
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnChamfer__Geometry__'

module Na__InsertPrimatives

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

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP CHAMFER MITRES
# =============================================================================
