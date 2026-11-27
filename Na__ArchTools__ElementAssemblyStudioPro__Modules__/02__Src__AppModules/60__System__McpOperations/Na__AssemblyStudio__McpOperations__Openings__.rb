# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - MCP OPERATIONS - OPENINGS (MEASURE WITHOUT CLICKING)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__McpOperations__Openings__.rb
# NAMESPACE  : Na__AssemblyStudio
# MODULE     : Na__McpOperations
# AUTHOR     : Noble Architecture
# CREATED    : 11-Nov-2026 (V2.6.0)
# PURPOSE    : What the Two Point and Three Point Opening tools measure, worked
#              out from a wall's own faces, so an agent can find every opening
#              in a wall and insert an element into it without clicking.
#
# HOW AN OPENING IS FOUND
#   A wall is a solid with two big parallel faces (its two sides). An opening
#   through it leaves REVEAL faces: square to the sides and spanning the full
#   thickness between them - jambs, a head and, for a window, a sill. A door
#   opening at floor level has no sill: it is a notch in the wall's outline.
#   Reveals that share edges belong to one opening. The wall's own ends, top
#   and bottom are square to the sides too, but they lie on the wall's outer
#   boundary, so they are left out.
#
# WHAT EACH OPENING GIVES (world coordinates, inches inside Ruby)
#   width, height, sill (its bottom, world Z), depth (the wall thickness
#   there), kind ('hole' with four reveals, 'notch' at the wall's foot), and
#   the points the opening tools would have picked:
#     A  the bottom corner at the LEFT seen from outside, on the outside face
#     B  the top corner at the right, on the outside face
#     D  A carried through the wall onto the inside face (the depth pick)
#   Na__InsertionFrame.na_build_measurement_frame_2pt(A, B) then gives the
#   same frame Adam's clicks give: origin A, X along the wall from left to
#   right seen from outside, Y into the wall, Z up.
#
# WHICH SIDE IS OUTSIDE
#   A wall does not know. By default the side facing away from the middle of
#   the model's contents is outside, which suits perimeter walls; pass an
#   'outside' direction (or a point outside) for any other wall.
#
# =============================================================================

module Na__AssemblyStudio
module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | Openings - Constants
# -----------------------------------------------------------------------------

    NA_OPENING_PARALLEL_TOLERANCE = 1.0e-3 unless defined?(NA_OPENING_PARALLEL_TOLERANCE)
    NA_OPENING_LENGTH_TOLERANCE   = 0.04 unless defined?(NA_OPENING_LENGTH_TOLERANCE) # inches, about 1 mm

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Openings - Detection
# -----------------------------------------------------------------------------

    # FUNCTION | Every Opening in One Wall Group or Component
    # ------------------------------------------------------------
    # @param wall      [Sketchup::Group, Sketchup::ComponentInstance]
    # @param to_world  [Geom::Transformation] the wall's definition -> world
    # @param outside   [Geom::Vector3d, Geom::Point3d, nil] which side is out
    # @param model_center [Geom::Point3d, nil] the default's reference point
    # @param plane     [Hash, nil] optional face_plane filter for multi-wing /
    #                  compound wall solids: { axis: 'x'|'y', value_in: Float,
    #                  normal: Vector3d, point: Point3d, outside: Vector3d,
    #                  tolerance_in: Float, thickness_in: Float } (V2.7.10)
    # @return [Hash] { frame:, thickness:, openings: [...] } (inches)
    def self.Na__AssemblyStudio__WallOpenings(wall, to_world, outside: nil, model_center: nil, plane: nil)
        faces = wall.definition.entities.grep(Sketchup::Face)
        na_refuse('wrong_type', "#{wall.name.to_s.empty? ? wall.definition.name : wall.name} holds no faces of its own.",
                  'Pass the group or component whose faces are the wall (not a container around it).') if faces.empty?

        world_faces = faces.map { |face| na_world_face(face, to_world) }
        return na_plane_openings(wall, world_faces, plane, outside, model_center) if plane.is_a?(Hash)

        main = world_faces.max_by { |row| row[:area] }
        normal = main[:normal]
        up = Geom::Vector3d.new(0, 0, 1)
        if normal.dot(up).abs > 0.5
            na_refuse('wrong_type', 'That object\'s biggest face is not vertical, so it is not a single-wall solid.',
                      'For a multi-wing compound wall solid (e.g. SUB__<Building>__Walls), pass plane: {axis: "x"|"y", value_mm: <coord>, outside: [nx, ny, nz]}.')
        end

        horizontal = Geom::Vector3d.new(normal.x, normal.y, 0).normalize
        along = up * horizontal
        along.normalize!
        out = na_outside_direction(horizontal, outside, model_center, world_faces)

        coords = lambda { |point| [point.to_a.zip(along.to_a).sum { |a, b| a * b },
                                   point.to_a.zip(horizontal.to_a).sum { |a, b| a * b },
                                   point.z] }
        all = world_faces.flat_map { |row| row[:points].map { |point| coords.call(point) } }
        u_min, u_max = all.map { |c| c[0] }.minmax
        v_min, v_max = all.map { |c| c[1] }.minmax
        w_min, w_max = all.map { |c| c[2] }.minmax
        thickness = v_max - v_min

        reveals = world_faces.select do |row|
            next false if row[:normal].dot(horizontal).abs > NA_OPENING_PARALLEL_TOLERANCE
            span = row[:points].map { |point| coords.call(point)[1] }.minmax
            next false if (span[1] - span[0] - thickness).abs > NA_OPENING_LENGTH_TOLERANCE * 2
            plane_u = row[:normal].dot(along).abs > 0.99
            plane_w = row[:normal].dot(up).abs > 0.99
            next false unless plane_u || plane_w
            position = plane_u ? coords.call(row[:points].first)[0] : coords.call(row[:points].first)[2]
            low, high = plane_u ? [u_min, u_max] : [w_min, w_max]
            position > low + NA_OPENING_LENGTH_TOLERANCE && position < high - NA_OPENING_LENGTH_TOLERANCE
        end

        openings = na_group_reveals(reveals).map do |group|
            points = group.flat_map { |row| row[:points] }.map { |point| coords.call(point) }
            ou_min, ou_max = points.map { |c| c[0] }.minmax
            ow_min, ow_max = points.map { |c| c[2] }.minmax
            sill = group.any? { |row| row[:normal].dot(up).abs > 0.99 && (coords.call(row[:points].first)[2] - ow_min).abs < NA_OPENING_LENGTH_TOLERANCE }
            na_opening_record(ou_min, ou_max, ow_min, ow_max, v_min, v_max, along, horizontal, out, sill ? 'hole' : 'notch')
        end
        # Left to right as seen from outside (the viewer's right is up x out).
        right = up * out
        openings.sort_by! { |row| [(row[:point_a] - ORIGIN).dot(right).round(3), row[:sill_z]] }
        {
            frame:     { along: along, normal: horizontal, outside: out, up: up },
            thickness: thickness,
            extent:    { along: [u_min, u_max], height: [w_min, w_max] },
            openings:  openings
        }
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Openings on One Vertical Plane of a Compound Wall Solid (V2.7.10)
    # ------------------------------------------------------------
    # Lets openings work directly on multi-wing SUB__<Building>__Walls solids
    # whose largest face is horizontal (roof/floor) or that carry several
    # perpendicular wall wings in one manifold shell.
    def self.na_plane_openings(wall, world_faces, plane, outside, model_center)
        up = Geom::Vector3d.new(0, 0, 1)
        horizontal, plane_v, plane_label = na_resolve_plane_frame(plane)
        tol = (plane[:tolerance_in] || (5.0 / 25.4)).to_f
        expected_depth = plane[:thickness_in] ? plane[:thickness_in].to_f : nil
        along = up * horizontal
        along.normalize!

        plane_faces = world_faces.select do |row|
            next false unless row[:normal].dot(horizontal).abs > 0.99

            row[:outer].all? { |point| ((point.x * horizontal.x + point.y * horizontal.y) - plane_v).abs <= tol }
        end
        if plane_faces.empty?
            wall_name = wall.name.to_s.empty? ? wall.definition.name : wall.name
            avail = na_describe_vertical_planes(world_faces)
            na_refuse('not_found', "No vertical wall face on #{wall_name} lies on #{plane_label} (±#{(tol * 25.4).round(1)}mm).",
                      avail.empty? ? 'Check the wall coordinates with geometry_measure bounds.' : "Largest vertical planes on this solid: #{avail}.")
        end

        chosen_outside = plane[:outside] || outside
        out = if chosen_outside
                  na_outside_direction(horizontal, chosen_outside, model_center, plane_faces)
              else
                  largest = plane_faces.max_by { |row| row[:area] }
                  largest[:normal].dot(horizontal) >= 0 ? horizontal.clone : horizontal.reverse
              end

        outer_faces = plane_faces.select { |row| row[:normal].dot(out) > 0.99 }
        outer_faces = plane_faces if outer_faces.empty?

        outer_face_edges = {}
        inner_loop_edges = {}
        outer_faces.each do |row|
            row[:edges].each { |edge| outer_face_edges[edge] = true }
            row[:face].loops.each do |loop|
                next if loop.outer?

                loop.edges.each { |edge| inner_loop_edges[edge] = true }
            end
        end

        coords = lambda do |point|
            [point.x * along.x + point.y * along.y,
             point.x * horizontal.x + point.y * horizontal.y,
             point.z]
        end
        outer_coords = outer_faces.flat_map { |row| row[:outer].map { |point| coords.call(point) } }
        u_min, u_max = outer_coords.map { |c| c[0] }.minmax
        w_min, w_max = outer_coords.map { |c| c[2] }.minmax
        plane_out_v  = out.dot(horizontal) >= 0 ? plane_v : -plane_v

        reveals = world_faces.select do |row|
            next false if row[:normal].dot(horizontal).abs > NA_OPENING_PARALLEL_TOLERANCE

            plane_u = row[:normal].dot(along).abs > 0.99
            plane_w = row[:normal].dot(up).abs > 0.99
            next false unless plane_u || plane_w
            next false unless row[:edges].any? { |edge| outer_face_edges[edge] }

            out_vals = row[:points].map { |point| point.x * out.x + point.y * out.y }
            o_min, o_max = out_vals.minmax
            next false unless (o_max - plane_out_v).abs <= tol

            local_depth = o_max - o_min
            next false unless local_depth > NA_OPENING_LENGTH_TOLERANCE * 2
            if expected_depth
                depth_tol = [tol, NA_OPENING_LENGTH_TOLERANCE * 2].max
                next false unless (local_depth - expected_depth).abs <= depth_tol
            end

            next true if row[:edges].any? { |edge| inner_loop_edges[edge] }

            position = plane_u ? coords.call(row[:points].first)[0] : coords.call(row[:points].first)[2]
            low, high = plane_u ? [u_min, u_max] : [w_min, w_max]
            position > low + NA_OPENING_LENGTH_TOLERANCE && position < high - NA_OPENING_LENGTH_TOLERANCE
        end

        openings = na_group_reveals(reveals).filter_map do |group|
            next nil if group.length < 3

            points = group.flat_map { |row| row[:points] }.map { |point| coords.call(point) }
            ou_min, ou_max = points.map { |c| c[0] }.minmax
            ov_min, ov_max = points.map { |c| c[1] }.minmax
            ow_min, ow_max = points.map { |c| c[2] }.minmax
            next nil if (ou_max - ou_min) < 2.0 || (ow_max - ow_min) < 2.0

            sill = group.any? { |row| row[:normal].dot(up).abs > 0.99 && (coords.call(row[:points].first)[2] - ow_min).abs < NA_OPENING_LENGTH_TOLERANCE }
            na_opening_record(ou_min, ou_max, ow_min, ow_max, ov_min, ov_max, along, horizontal, out, sill ? 'hole' : 'notch')
        end

        right = up * out
        openings.sort_by! { |row| [(row[:point_a] - ORIGIN).dot(right).round(3), row[:sill_z]] }
        thickness = if !openings.empty?
                        depths = openings.map { |row| row[:depth] }.sort
                        depths[depths.length / 2]
                    elsif expected_depth
                        expected_depth
                    else
                        0.0
                    end
        {
            frame:     { along: along, normal: horizontal, outside: out, up: up },
            thickness: thickness,
            extent:    { along: [u_min, u_max], height: [w_min, w_max] },
            openings:  openings,
            plane:     plane_label
        }
    end
    private_class_method :na_plane_openings
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Turn a Plane Filter Spec Into [horizontal_unit, offset_in, label]
    # ------------------------------------------------------------
    def self.na_resolve_plane_frame(plane)
        axis = plane[:axis].to_s.downcase
        if axis == 'x' || axis == 'y'
            na_refuse('invalid_params', 'plane with axis needs value (or value_mm).', 'e.g. plane: {axis: "x", value_mm: 9110, outside: [1, 0, 0]}.') if plane[:value_in].nil?
            horizontal = axis == 'x' ? Geom::Vector3d.new(1, 0, 0) : Geom::Vector3d.new(0, 1, 0)
            val_in = plane[:value_in].to_f
            return [horizontal, val_in, "#{axis.upcase} = #{(val_in * 25.4).round(1)}mm"]
        end

        if plane[:normal].is_a?(Geom::Vector3d) && plane[:point].is_a?(Geom::Point3d)
            flat = Geom::Vector3d.new(plane[:normal].x, plane[:normal].y, 0)
            na_refuse('invalid_params', 'plane.normal must be horizontal (a vertical wall plane).', 'e.g. normal: [1, 0, 0] or axis: "x".') if flat.length < 1.0e-6
            horizontal = flat.normalize
            val_in = plane[:point].x * horizontal.x + plane[:point].y * horizontal.y
            return [horizontal, val_in, "normal #{horizontal.to_a.map { |v| v.round(3) }} @ #{(val_in * 25.4).round(1)}mm"]
        end

        na_refuse('invalid_params', 'plane needs {axis: "x"|"y", value_mm: <number>} (or {normal, point}).',
                  'e.g. plane: {axis: "x", value_mm: 9110, outside: [1, 0, 0]}.')
    end
    private_class_method :na_resolve_plane_frame
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Summarise the Largest Vertical Face Planes on a Solid
    # ------------------------------------------------------------
    def self.na_describe_vertical_planes(world_faces)
        buckets = Hash.new(0.0)
        world_faces.each do |row|
            n = row[:normal]
            next if n.z.abs > 0.1

            if n.x.abs > 0.99
                x_mm = (row[:outer].first.x * 25.4).round
                dir  = n.x > 0 ? '+X' : '-X'
                buckets["X=#{x_mm}mm (#{dir})"] += row[:area]
            elsif n.y.abs > 0.99
                y_mm = (row[:outer].first.y * 25.4).round
                dir  = n.y > 0 ? '+Y' : '-Y'
                buckets["Y=#{y_mm}mm (#{dir})"] += row[:area]
            end
        end
        buckets.sort_by { |_label, area| -area }.first(6).map(&:first).join(', ')
    end
    private_class_method :na_describe_vertical_planes
    # ---------------------------------------------------------------

    # HELPER FUNCTION | A Face in World Space: Points, Normal, Area
    # ------------------------------------------------------------
    def self.na_world_face(face, to_world)
        points = face.outer_loop.vertices.map { |vertex| vertex.position.transform(to_world) }
        inner  = face.loops.reject(&:outer?).flat_map { |loop| loop.vertices.map { |vertex| vertex.position.transform(to_world) } }
        normal = face.normal.transform(to_world)
        normal.normalize! if normal.length > 0
        { face: face, points: points + inner, outer: points, normal: normal, area: face.area * na_area_scale(to_world),
          edges: face.edges }
    end
    private_class_method :na_world_face
    # ---------------------------------------------------------------

    # The area of a face grows with its group's scale; only the ranking
    # matters here, so the determinant's size is enough.
    def self.na_area_scale(to_world)
        x = to_world.xaxis
        y = to_world.yaxis
        z = to_world.zaxis
        volume = (x * y).dot(z).abs
        volume.positive? ? volume**(2.0 / 3.0) : 1.0
    end
    private_class_method :na_area_scale
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Which Way Is Outside (Horizontal Unit Vector)
    # ------------------------------------------------------------
    def self.na_outside_direction(horizontal, outside, model_center, world_faces)
        if outside.is_a?(Geom::Vector3d)
            flat = Geom::Vector3d.new(outside.x, outside.y, 0)
            na_refuse('invalid_params', 'outside must point across the wall, not up or down.', 'e.g. [0, -1, 0] for a wall whose outside faces -Y.') if flat.length < 1.0e-6
            return flat.dot(horizontal) >= 0 ? horizontal.clone : horizontal.reverse
        end
        reference = outside.is_a?(Geom::Point3d) ? outside : model_center
        return horizontal.clone unless reference

        wall_points = world_faces.flat_map { |row| row[:outer] }
        mid = Geom::Point3d.new(wall_points.sum(&:x) / wall_points.length, wall_points.sum(&:y) / wall_points.length, 0)
        to_reference = Geom::Vector3d.new(reference.x - mid.x, reference.y - mid.y, 0)
        return horizontal.clone if to_reference.length < 1.0e-6

        toward = to_reference.dot(horizontal) >= 0
        # A point given as 'outside' is outside; the model's centre is inside.
        if outside.is_a?(Geom::Point3d)
            toward ? horizontal.clone : horizontal.reverse
        else
            toward ? horizontal.reverse : horizontal.clone
        end
    end
    private_class_method :na_outside_direction
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Reveal Faces That Share Edges Are One Opening
    # ------------------------------------------------------------
    def self.na_group_reveals(reveals)
        parent = (0...reveals.length).to_a
        find = lambda do |index|
            index = parent[index] while parent[index] != index
            index
        end
        owner = {}
        reveals.each_with_index do |row, index|
            row[:edges].each do |edge|
                if owner.key?(edge)
                    a = find.call(owner[edge])
                    b = find.call(index)
                    parent[a] = b unless a == b
                else
                    owner[edge] = index
                end
            end
        end
        reveals.each_index.group_by { |index| find.call(index) }.values.map { |indices| indices.map { |index| reveals[index] } }
    end
    private_class_method :na_group_reveals
    # ---------------------------------------------------------------

    # HELPER FUNCTION | One Opening: Sizes and the Picks the Tools Would Make
    # ------------------------------------------------------------
    def self.na_opening_record(u_min, u_max, w_min, w_max, v_min, v_max, along, horizontal, out, kind)
        point_at = lambda do |u, v, w|
            Geom::Point3d.new(along.x * u + horizontal.x * v, along.y * u + horizontal.y * v, w)
        end
        outside_v, inside_v = out.dot(horizontal) >= 0 ? [v_max, v_min] : [v_min, v_max]
        # Seen from outside, left is where the along axis points against
        # up x out (the viewer's right hand).
        right = Geom::Vector3d.new(0, 0, 1) * out
        left_u, right_u = right.dot(along) >= 0 ? [u_min, u_max] : [u_max, u_min]
        a = point_at.call(left_u, outside_v, w_min)
        b = point_at.call(right_u, outside_v, w_max)
        d = point_at.call(left_u, inside_v, w_min)
        {
            kind:        kind,
            width:       u_max - u_min,
            height:      w_max - w_min,
            depth:       v_max - v_min,
            sill_z:      w_min,
            head_z:      w_max,
            point_a:     a,
            point_b:     b,
            point_d:     d,
            center:      Geom::Point3d.new((a.x + b.x) / 2.0, (a.y + b.y) / 2.0, (w_min + w_max) / 2.0)
        }
    end
    private_class_method :na_opening_record
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__McpOperations
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
