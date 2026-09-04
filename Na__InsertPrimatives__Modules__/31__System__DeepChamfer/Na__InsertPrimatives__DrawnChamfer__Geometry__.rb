# =============================================================================
# NA INSERT PRIMATIVES - DEEP CHAMFER GEOMETRY
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnChamfer__Geometry__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Capture / substitute / rebuild solvers for a single-edge chamfer
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'

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

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP CHAMFER GEOMETRY
# =============================================================================
