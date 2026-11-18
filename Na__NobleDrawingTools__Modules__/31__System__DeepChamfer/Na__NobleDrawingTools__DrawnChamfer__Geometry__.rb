# =============================================================================
# NA NOBLE DRAWING TOOLS - DEEP CHAMFER GEOMETRY
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnChamfer__Geometry__.rb
# NAMESPACE  : Na__NobleDrawingTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Capture / substitute / rebuild solvers for a single-edge chamfer
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'

module Na__NobleDrawingTools

    # -----------------------------------------------------------------------------
    # REGION | Chamfer Geometry (Module Functions)
    # -----------------------------------------------------------------------------

    NA_CHAMFER_MERGE_TOL      = 0.001                                         # <-- Internal inches; vertex identity when cleaning up
    NA_CHAMFER_MIN_COS_HALF   = 0.0872                                        # <-- cos 85 deg; below this the corner is too flat to chamfer
    NA_CHAMFER_MITRE_TOL      = 0.001                                         # <-- The two lower mitre points must agree to SketchUp's own merge tolerance

    # FUNCTION | In-Plane Direction Perpendicular to an Edge, Unsigned
    # Lies in the face plane; SignInto settles which way is into the material.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__InwardDir(face, edge_vector_unit)
        direction = face.normal.cross(edge_vector_unit)
        return nil if direction.length == 0

        direction.normalize
    end
    # ---------------------------------------------------------------

    # FUNCTION | Sign an In-Plane Direction Toward the Face Centroid
    # The FALLBACK only (5.2.45), for a face whose own outline cannot answer
    # SignInto below. The average of the outer loop's corners lies inside
    # every convex face, but on a concave one it can sit across an edge's
    # line from the material (the McKay slab: 306 mm past the side of its
    # south projection), and for an edge ON an opening it usually sits in
    # the opening itself (wrong on 263 of 332 such edges in that model).
    # Either way the cut came out of the material, inside out.
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

    # FUNCTION | The Normal a Face's Own Outline Winds Round (Newell)
    # From the positions the outer loop REPORTS, so it always agrees with the
    # winding those same positions show: closed, open, and open inside a
    # MIRRORED instance, where Face#normal keeps the front side while the
    # reported winding turns over. Summed from the loop's first point, which
    # keeps it exact far from the origin. nil for a degenerate loop.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__LoopNormal(face)
        positions = face.outer_loop.vertices.map { |vertex| vertex.position }
        return nil if positions.length < 3

        origin = positions.first
        nx     = 0.0
        ny     = 0.0
        nz     = 0.0

        positions.each_with_index do |position, index|
            here  = position - origin
            ahead = positions[(index + 1) % positions.length] - origin
            nx += (here.y.to_f - ahead.y.to_f) * (here.z.to_f + ahead.z.to_f)
            ny += (here.z.to_f - ahead.z.to_f) * (here.x.to_f + ahead.x.to_f)
            nz += (here.x.to_f - ahead.x.to_f) * (here.y.to_f + ahead.y.to_f)
        end

        normal = Geom::Vector3d.new(nx, ny, nz)
        normal.length.to_f > 0.0 ? normal : nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Sign an In-Plane Direction INTO the Face, From Its Own Winding
    # SketchUp runs every loop of a face with the face on its LEFT, looking
    # down the loop's normal: the outer loop anticlockwise, each opening
    # clockwise. So the loop's normal crossed with the edge, the way this
    # face's loop runs it, points into the material on ANY face: convex,
    # L-shaped, notched, stepped, holed, and for an edge on an opening. No
    # centroid, no probe, no tolerance. Measured read-only in SketchUp 2027
    # (13-Nov-2026): right on 1,006 of 1,006 edge uses, 332 of them on
    # openings. The centroid answers only when the outline cannot.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__SignInto(direction, edge, face, from_point)
        loop_normal = Na__NobleDrawingTools.Na__DrawnChamfer__LoopNormal(face)
        reversed    = edge.reversed_in?(face)                                 # <-- nil when the face does not use this edge
        along       = edge.end.position - edge.start.position

        if loop_normal && !reversed.nil? && along.length.to_f > 0.0
            along = along.reverse if reversed                                 # <-- The edge as this face's loop runs it
            into  = loop_normal.cross(along)

            if into.length.to_f > 0.0
                return direction.dot(into) < 0.0 ? direction.reverse : direction
            end
        end

        Na__NobleDrawingTools.Na__DrawnChamfer__SignToward(direction, from_point, face)
    rescue StandardError
        Na__NobleDrawingTools.Na__DrawnChamfer__SignToward(direction, from_point, face)
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

        dir_a = Na__NobleDrawingTools.Na__DrawnChamfer__InwardDir(face_a, edge_unit)
        dir_b = Na__NobleDrawingTools.Na__DrawnChamfer__InwardDir(face_b, edge_unit)
        return nil unless dir_a && dir_b

        midpoint = Geom::Point3d.new(
            (v0.x.to_f + v1.x.to_f) * 0.5,
            (v0.y.to_f + v1.y.to_f) * 0.5,
            (v0.z.to_f + v1.z.to_f) * 0.5
        )
        # Into the material by each face's own winding (5.2.45), never by a
        # centroid, which cut one side of the McKay slab inside out.
        dir_a = Na__NobleDrawingTools.Na__DrawnChamfer__SignInto(dir_a, edge, face_a, midpoint)
        dir_b = Na__NobleDrawingTools.Na__DrawnChamfer__SignInto(dir_b, edge, face_b, midpoint)

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

        a0 = Na__NobleDrawingTools.Na__DrawnGrid__OffsetPoint(v0, dir_a, local_a)
        a1 = Na__NobleDrawingTools.Na__DrawnGrid__OffsetPoint(v1, dir_a, local_a)
        b0 = Na__NobleDrawingTools.Na__DrawnGrid__OffsetPoint(v0, dir_b, local_b)
        b1 = Na__NobleDrawingTools.Na__DrawnGrid__OffsetPoint(v1, dir_b, local_b)

        half_angle_deg = Math.acos([[cos_half, 1.0].min, -1.0].max) * 180.0 / Math::PI

        {
            :cos_half => cos_half,
            :v0 => v0, :v1 => v1,
            :a0 => a0, :a1 => a1, :b0 => b0, :b1 => b1,
            :bisector_local => bisector,
            :convex         => bisector.dot(face_a.normal).to_f < 0.0,        # <-- 5.2.46: false on an internal (concave) edge
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
    # faces, whose corners get clipped). Pair order is settled by the line the
    # loop arrives along (ArrivesAlong?, 5.2.46), keeping the winding sane.
    # Raises before anything is touched when the face cannot be planned.
    #
    # OPENINGS: a face with holes (the top of a plinth a column stands on, a
    # board with a slot) is planned loop by loop. The same substitutions run on
    # every inner loop, so an edge ON an opening is cut too, and the rebuild
    # puts each opening back (Na__DrawnChamfer__RebuildFace).
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__RebuildPlan(face, single_subs, pair_subs)
        original = face.outer_loop.vertices.map { |vertex| vertex.position }
        raise 'a face around this corner has no usable boundary' if original.length < 3

        holes = face.loops.reject { |loop| loop.outer? }.map do |loop|
            Na__NobleDrawingTools.Na__DrawnChamfer__SubstituteLoop(
                loop.vertices.map { |vertex| vertex.position }, single_subs, pair_subs
            )
        end

        {
            :face          => face,
            :points        => Na__NobleDrawingTools.Na__DrawnChamfer__SubstituteLoop(original, single_subs, pair_subs),
            :holes         => holes,
            :normal        => face.normal,
            :material      => face.material,
            :back_material => face.back_material,
            :layer         => face.layer
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does the Loop Arrive at a Clipped Corner Along the First Point's Line?
    # A clipped corner's two new points each lie on the line of one of the end
    # face's own edges at that corner: a on the edge it shares with face A, b
    # on the one it shares with face B. The loop arrives from `previous` along
    # one of those lines, so the point ON that line comes first. Right at a
    # convex end, where both points lie between the corner and its neighbours,
    # AND at a re-entrant one, where the new point lies beyond the corner:
    # there the old nearest-point test picked the far point whenever the loop
    # came along a long edge, and a single cut ending in an inside corner left
    # the end face's top running diagonally and the solid open (5.2.46).
    # Neither point on that line (a corner of four or more faces, an end not
    # slid onto a raked face): the nearer, as before.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__ArrivesAlong?(previous, corner, first, second)
        on_first  = Na__NobleDrawingTools.Na__DrawnChamfer__OnLine?(first, corner, previous)
        on_second = Na__NobleDrawingTools.Na__DrawnChamfer__OnLine?(second, corner, previous)
        return true  if on_first && !on_second
        return false if on_second && !on_first

        previous.distance(first).to_f <= previous.distance(second).to_f
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does a Point Lie on the Line Through Two Others?
    # A plain float distance from the line: Length comparisons are
    # tolerance-based and would call a far point near.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__OnLine?(point, from, through)
        along = through - from
        off   = point - from
        span  = along.length.to_f
        return false if span <= 0.0 || off.length.to_f <= 0.0

        along.cross(off).length.to_f / span <= NA_CHAMFER_MITRE_TOL
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Loop's Positions With the Cut's Corners Substituted
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__SubstituteLoop(original, single_subs, pair_subs)
        points = []

        original.each_with_index do |position, index|
            single = single_subs.find { |corner, _| Na__NobleDrawingTools.Na__DrawnChamfer__SamePoint?(position, corner) }
            if single
                points << single[1]
                next
            end

            pair = pair_subs.find { |corner, _, _| Na__NobleDrawingTools.Na__DrawnChamfer__SamePoint?(position, corner) }
            unless pair
                points << position
                next
            end

            previous = original[index - 1]                                    # <-- index 0 wraps to the last point, which is correct
            if Na__NobleDrawingTools.Na__DrawnChamfer__ArrivesAlong?(previous, position, pair[1], pair[2])
                points << pair[1] << pair[2]
            else
                points << pair[2] << pair[1]
            end
        end

        points
    end
    # ---------------------------------------------------------------

    # FUNCTION | Plan Every Face the Chamfer Touches
    # Every position read is in the space the faces REPORT at the moment of
    # the call — the definition's local space for a closed group, global for a
    # group that is open — and the caller's build_transform must carry the
    # plan into the space the collection ACCEPTS when the plan is built. Read
    # before entering and built after: edit_transform. Read and built on the
    # same side of the open: the identity. Raises on anything it cannot plan —
    # a refusal before anything is erased costs the model nothing.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__BuildPlans(target, solve)
        edge           = target[:edge]
        face_a, face_b = target[:faces]

        # Every face touching either corner vertex is affected: the two being
        # chamfered plus the end faces whose corners the cut clips.
        end_faces = (edge.start.faces.to_a + edge.end.faces.to_a).uniq - [face_a, face_b]

        plans = []
        plans << Na__NobleDrawingTools.Na__DrawnChamfer__RebuildPlan(
            face_a, [[solve[:v0], solve[:a0]], [solve[:v1], solve[:a1]]], []
        )
        plans << Na__NobleDrawingTools.Na__DrawnChamfer__RebuildPlan(
            face_b, [[solve[:v0], solve[:b0]], [solve[:v1], solve[:b1]]], []
        )
        end_faces.each do |end_face|
            plans << Na__NobleDrawingTools.Na__DrawnChamfer__RebuildPlan(
                end_face, [],
                [[solve[:v0], solve[:a0], solve[:b0]], [solve[:v1], solve[:a1], solve[:b1]]]
            )
        end

        plans
    end
    # ---------------------------------------------------------------

    # FUNCTION | Tidy a Rebuilt Loop: Repeated Points and Folds Come Out
    # ------------------------------------------------------------
    # A cut as deep as the face is wide lands its offset points ON the face's
    # far corners. The substituted loop then repeats points, or runs out along
    # a line and straight back (a fold), and add_face refuses both. Taking them
    # out leaves exactly the face that is left: the end face keeps its clipped
    # corner, the far part of an L-shaped top keeps its own outline, and a
    # strip the cut consumed whole drops below three points and is not
    # rebuilt at all. A loop with neither is returned unchanged.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__CleanLoop(points)
        loop_points = points.dup
        changed     = true

        while changed && loop_points.length >= 3
            changed = false
            count   = loop_points.length

            count.times do |index|
                here  = loop_points[index]
                ahead = loop_points[(index + 1) % count]

                if Na__NobleDrawingTools.Na__DrawnChamfer__SamePoint?(here, ahead)
                    loop_points.delete_at((index + 1) % count)
                    changed = true
                    break
                end

                incoming = here - loop_points[index - 1]
                outgoing = ahead - here
                next if incoming.length == 0 || outgoing.length == 0

                if incoming.parallel?(outgoing) && incoming.dot(outgoing) < 0.0
                    loop_points.delete_at(index)
                    changed = true
                    break
                end
            end
        end

        loop_points
    end
    # ---------------------------------------------------------------

    # FUNCTION | Are Two Loops the Same Outline, Whatever Point They Start At?
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__SameLoop?(loop_a, loop_b)
        return false unless loop_a.length == loop_b.length

        loop_a.all? do |point|
            loop_b.any? { |other| Na__NobleDrawingTools.Na__DrawnChamfer__SamePoint?(point, other) }
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Put a Rebuilt Face's Openings Back
    # ------------------------------------------------------------
    # Measured in SketchUp (30-Sep-2026) rather than assumed: re-adding a
    # face's outer loop does NOT reopen an opening whose edges are still
    # standing (a column rising through a plinth top), but it DOES cut round
    # a face still filling one (an inset panel). So an opening the new face
    # already has is left alone, and a missing one is made the native way:
    # add the loop as a face, which splits the new face, then erase that fill.
    # The fill is only erased when add_face created it; a face that was
    # already there is never touched.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__RestoreOpenings(entities, face, holes, build_transform)
        holes.each do |hole|
            already = face.loops.any? do |loop|
                !loop.outer? &&
                    Na__NobleDrawingTools.Na__DrawnChamfer__SameLoop?(
                        loop.vertices.map { |vertex| vertex.position }, hole.map { |point| point.transform(build_transform) }
                    )
            end
            next if already

            before = entities.grep(Sketchup::Face)
            fill   = entities.add_face(hole.map { |point| point.transform(build_transform) })
            next unless fill && fill.valid? && fill != face

            fill.erase! unless before.include?(fill)
        end

        face
    end
    # ---------------------------------------------------------------

    # FUNCTION | Re-Add a Planned Face and Restore Its Dress
    # Every point goes through build_transform — the open editing session's
    # coordinate system per the header rule, the identity at root. add_face
    # reuses surviving coincident edges, which is what knits the rebuilt faces
    # back onto the untouched neighbours. Winding is restored against the
    # captured normal (transformed the same way) so materials stay put.
    # A face the cut consumed whole (a full-depth cut) has already been erased
    # with the others, and is simply not re-added: nil. So is a face with an
    # opening whose outline the cut has brought right in to the opening: the
    # frame round a column, chamfered to the full width of the frame.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__RebuildFace(entities, plan, build_transform)
        points = Na__NobleDrawingTools.Na__DrawnChamfer__CleanLoop(plan[:points])
        return nil if points.length < 3

        holes = (plan[:holes] || []).map { |hole| Na__NobleDrawingTools.Na__DrawnChamfer__CleanLoop(hole) }
        holes = holes.select { |hole| hole.length >= 3 }
        return nil if holes.any? { |hole| Na__NobleDrawingTools.Na__DrawnChamfer__SameLoop?(points, hole) }

        face = entities.add_face(points.map { |point| point.transform(build_transform) })
        raise 'a face could not be rebuilt around the chamfer' unless face

        Na__NobleDrawingTools.Na__DrawnChamfer__RestoreOpenings(entities, face, holes, build_transform)

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

    # FUNCTION | Turn a Chamfer Face to Face the Air
    # Away from the material: opposite the bisector on a convex edge, where
    # the bisector runs into the solid, and WITH it on an internal (concave)
    # edge, where the chamfer fills the corner and the bisector runs into the
    # air. Until 5.2.46 every chamfer face was turned against the bisector, so
    # a chamfer on an internal edge faced into its own fill, inside out.
    # ------------------------------------------------------------
    def self.Na__DrawnChamfer__FaceTheAir(chamfer_face, solve, build_transform)
        session_bisector = solve[:bisector_local].transform(build_transform)
        return chamfer_face unless session_bisector.valid?

        leaning = chamfer_face.normal.dot(session_bisector).to_f
        chamfer_face.reverse! if solve[:convex] == false ? leaning < 0.0 : leaning > 0.0
        chamfer_face
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
        plans.each { |plan| Na__NobleDrawingTools.Na__DrawnChamfer__RebuildFace(entities, plan, build_transform) }

        chamfer_face = entities.add_face(
            solve[:a0].transform(build_transform),
            solve[:a1].transform(build_transform),
            solve[:b1].transform(build_transform),
            solve[:b0].transform(build_transform)
        )
        raise 'the chamfer plane could not be created here' unless chamfer_face

        # Facing the air, convex or internal (FaceTheAir), and dressed like the
        # first chamfered face for continuity.
        Na__NobleDrawingTools.Na__DrawnChamfer__FaceTheAir(chamfer_face, solve, build_transform)
        chamfer_face.material      = plans[0][:material]      if plans[0][:material]
        chamfer_face.back_material = plans[0][:back_material] if plans[0][:back_material]
        chamfer_face.layer         = plans[0][:layer]         if plans[0][:layer]

        true
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF DEEP CHAMFER GEOMETRY
# =============================================================================
