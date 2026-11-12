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
    # @return [Hash] { frame:, thickness:, openings: [...] } (inches)
    def self.Na__AssemblyStudio__WallOpenings(wall, to_world, outside: nil, model_center: nil)
        faces = wall.definition.entities.grep(Sketchup::Face)
        na_refuse('wrong_type', "#{wall.name.to_s.empty? ? wall.definition.name : wall.name} holds no faces of its own.",
                  'Pass the group or component whose faces are the wall (not a container around it).') if faces.empty?

        world_faces = faces.map { |face| na_world_face(face, to_world) }
        main = world_faces.max_by { |row| row[:area] }
        normal = main[:normal]
        up = Geom::Vector3d.new(0, 0, 1)
        if normal.dot(up).abs > 0.5
            na_refuse('wrong_type', 'That object\'s biggest face is not vertical, so it is not a wall.',
                      'Pass a wall: a solid whose two biggest faces are its vertical sides.')
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
