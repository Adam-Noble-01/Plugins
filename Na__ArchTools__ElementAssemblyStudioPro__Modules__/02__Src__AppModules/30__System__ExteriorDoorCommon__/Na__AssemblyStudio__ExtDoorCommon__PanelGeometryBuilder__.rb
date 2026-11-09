# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOOR COMMON - PANEL GEOMETRY BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtDoorCommon__PanelGeometryBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorDoorCommon
# MODULE     : Na__PanelGeometryBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Build 3D raised-bevelled / recessed-shaker fielded panel cells
#              inside a MOD leaf group. Shared by every exterior door system.
#
# DESCRIPTION:
# - Extracted verbatim from the Exterior Double Door System, parameterized by a
#   `naming` hash so the container / field-cell group names carry each system's
#   prefix (naming[:container]).
# - V2.5.3 Each field cell is ONE closed solid, built in one pass from its
#   section profile and lofted round the cell. It was four ring boxes, eight
#   loose bevel faces and a centre box that nothing ever joined, so a panel was
#   never a solid and could not be fused, measured or cut cleanly. A Recessed
#   Shaker panel was only its inset centre, leaving a see-through gap the width
#   of the inset all round it.
#
# THE PROFILE:
# - A list of [inset_from_cell_edge_mm, y_mm] points, from the back face round
#   the panel's edge to the front face. Each point becomes a rectangle inset
#   from the cell by that much at that depth; neighbouring rectangles are
#   joined by four planar quads, and the first and last are capped.
# - Raised Bevelled: field flush with both leaf faces, bevel down to a flat
#   margin sunk by Panel Depth, margin out to the cell edge.
# - Recessed Shaker: margin flush with both leaf faces from the cell edge to
#   the Panel Inset, centre sunk by Panel Depth on both faces.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative 'Na__AssemblyStudio__ExtDoorCommon__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorDoorCommon
module Na__PanelGeometryBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    # Cell sides in ring-corner order (corner k to k + 1) with each side's
    # outward direction in the leaf plane.
    NA_SIDE_DIRECTIONS = [
        [0.0, 0.0, -1.0],                                                       # <-- Bottom
        [1.0, 0.0, 0.0],                                                        # <-- Right
        [0.0, 0.0, 1.0],                                                        # <-- Top
        [-1.0, 0.0, 0.0]                                                        # <-- Left
    ].freeze
    NA_PROFILE_TOLERANCE_MM = 0.001

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Build All Fielded Panel Cells Into a Container Group
    # ------------------------------------------------------------
    # @param naming [Hash] { :container => "Na__ExteriorDoubleDoor" }
    # @return [Sketchup::Group, nil]
    def self.na_build(entities, leaf, panel_layout, material = nil, naming = {})
        return nil unless entities && panel_layout[:field_cells].any?

        container_prefix = na_container_prefix(naming)
        container = entities.add_group
        container.name = "#{container_prefix}__PanelGeometry"
        panel_layout[:field_cells].each_with_index do |cell, index|
            na_build_cell(container.entities, leaf, panel_layout, cell, index + 1, material, container_prefix)
        end
        container
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Section Profile of One Field Cell (V2.5.3)
    # ------------------------------------------------------------
    # Public so the specs and the MCP inspection can check a profile without
    # building it.
    # @return [Array<Array(Float, Float)>, nil] [[inset_mm, y_mm], ...] back to front
    def self.na_profile(leaf, cell, layout)
        safe = na_safe_profile_dimensions(cell, leaf, layout)
        return nil unless safe

        front = leaf[:origin_y_mm].to_f
        back = front + leaf[:thickness_mm].to_f
        depth = safe[:depth]
        inset = safe[:inset]
        points = if layout[:profile] == 'RecessedShaker'
                     [
                         [inset, back - depth], [inset, back], [0.0, back],
                         [0.0, front], [inset, front], [inset, front + depth]
                     ]
                 else
                     margin = [inset - safe[:bevel], 0.0].max
                     [
                         [inset, back], [margin, back - depth], [0.0, back - depth],
                         [0.0, front + depth], [margin, front + depth], [inset, front]
                     ]
                 end
        na_dedupe_profile(points)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Cell Dispatch
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Resolve Container Name Prefix From Naming Hash
    # ------------------------------------------------------------
    def self.na_container_prefix(naming)
        prefix = naming.is_a?(Hash) ? naming[:container] : nil
        (prefix && !prefix.to_s.empty?) ? prefix.to_s : 'Na__ExteriorDoor'
    end
    private_class_method :na_container_prefix
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build One Fielded Panel Cell as One Solid Group
    # ------------------------------------------------------------
    def self.na_build_cell(entities, leaf, layout, cell, index, material, container_prefix)
        group = entities.add_group
        group.name = format("#{container_prefix}__Field__%03d", index)
        profile = na_profile(leaf, cell, layout)
        na_build_profile_solid(group.entities, cell, profile, material) if profile
        group
    end
    private_class_method :na_build_cell
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Clamp Profile Dimensions to Safe Cell Bounds
    # ------------------------------------------------------------
    def self.na_safe_profile_dimensions(cell, leaf, layout)
        inset = GeometryHelpers.na_clamp(
            layout[:panel_inset_mm], 2, [cell[:width_mm], cell[:height_mm]].min / 3.0
        )
        depth = GeometryHelpers.na_clamp(
            layout[:panel_depth_mm], 1, leaf[:thickness_mm] / 2.0 - 0.5
        )
        bevel = GeometryHelpers.na_clamp(
            layout[:panel_bevel_width_mm], 2, [cell[:width_mm], cell[:height_mm]].min / 4.0
        )
        return nil if cell[:width_mm] <= 2 * inset || cell[:height_mm] <= 2 * inset
        { :inset => inset.to_f, :depth => depth.to_f, :bevel => [bevel, inset].min.to_f }
    end
    private_class_method :na_safe_profile_dimensions
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Drop Repeated Profile Points
    # ------------------------------------------------------------
    # A bevel as wide as the inset leaves no flat margin, so its two margin
    # points land on the cell edge points.
    def self.na_dedupe_profile(points)
        points.each_with_object([]) do |point, kept|
            last = kept.last
            same = last &&
                   (last[0] - point[0]).abs < NA_PROFILE_TOLERANCE_MM &&
                   (last[1] - point[1]).abs < NA_PROFILE_TOLERANCE_MM
            kept << point unless same
        end
    end
    private_class_method :na_dedupe_profile
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Profile Solid
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Loft a Section Profile Round the Cell Into One Solid
    # ------------------------------------------------------------
    # Every face is oriented outward from the profile's own winding, so the
    # result is a closed, correctly faced solid without any boolean. Mitre
    # edges left between coplanar pieces of a flat margin are erased, which
    # merges each margin into one face.
    def self.na_build_profile_solid(entities, cell, profile, material)
        rings = profile.map { |inset, y| na_ring_points(cell, inset, y) }
        winding = na_profile_winding(cell, profile)
        y_mid = profile.sum { |point| point[1] } / profile.length.to_f

        na_add_oriented_face(entities, rings.first, [0.0, profile.first[1] <=> y_mid, 0.0], material)
        rings.each_cons(2).with_index do |(ring_a, ring_b), index|
            delta_inset = profile[index + 1][0] - profile[index][0]
            delta_y = profile[index + 1][1] - profile[index][1]
            normal_inset = winding * delta_y                                    # <-- Outward normal of the profile edge
            normal_y = -winding * delta_inset
            NA_SIDE_DIRECTIONS.each_with_index do |side, k|
                following = (k + 1) % 4
                expected = side.map { |component| -normal_inset * component }    # <-- Inset grows away from the side
                expected[1] += normal_y
                quad = [ring_a[k], ring_a[following], ring_b[following], ring_b[k]]
                na_add_oriented_face(entities, quad, expected, material)
            end
        end
        na_add_oriented_face(entities, rings.last, [0.0, profile.last[1] <=> y_mid, 0.0], material)
        na_merge_coplanar_faces(entities)
    end
    private_class_method :na_build_profile_solid
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Winding of the Profile Closed Through the Cell Centre
    # ------------------------------------------------------------
    # @return [Float] 1.0 counter-clockwise in (inset, y), -1.0 clockwise
    def self.na_profile_winding(cell, profile)
        centre = [cell[:width_mm], cell[:height_mm]].min / 2.0
        closed = profile + [[centre, profile.last[1]], [centre, profile.first[1]]]
        area = 0.0
        closed.each_with_index do |point, index|
            following = closed[(index + 1) % closed.length]
            area += point[0] * following[1] - following[0] * point[1]
        end
        area >= 0.0 ? 1.0 : -1.0
    end
    private_class_method :na_profile_winding
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Add One Face and Turn It to Face the Expected Way
    # ------------------------------------------------------------
    def self.na_add_oriented_face(entities, points, expected, material)
        face = entities.add_face(points)
        return nil unless face

        face.reverse! if face.normal.dot(Geom::Vector3d.new(*expected)) < 0
        if material
            face.material = material
            face.back_material = material
        end
        face
    end
    private_class_method :na_add_oriented_face
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Erase Edges That Only Split One Flat Surface
    # ------------------------------------------------------------
    # Two faces that share an edge and face the same way lie in one plane.
    def self.na_merge_coplanar_faces(entities)
        entities.grep(Sketchup::Edge).each do |edge|
            next unless edge.valid?
            faces = edge.faces
            next unless faces.length == 2
            next unless faces[0].normal.samedirection?(faces[1].normal)

            edge.erase!
        end
    end
    private_class_method :na_merge_coplanar_faces
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Geometry Primitives
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Four Corners of the Cell Inset by an Amount, at a Depth
    # ------------------------------------------------------------
    # Corner order matches NA_SIDE_DIRECTIONS: bottom-left, bottom-right,
    # top-right, top-left.
    def self.na_ring_points(cell, inset, y_mm)
        x0 = cell[:x_mm] + inset
        x1 = cell[:x_mm] + cell[:width_mm] - inset
        z0 = cell[:z_mm] + inset
        z1 = cell[:z_mm] + cell[:height_mm] - inset
        [
            na_point(x0, y_mm, z0),
            na_point(x1, y_mm, z0),
            na_point(x1, y_mm, z1),
            na_point(x0, y_mm, z1)
        ]
    end
    private_class_method :na_ring_points
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build a Geom::Point3d From Millimetre Coordinates
    # ------------------------------------------------------------
    def self.na_point(x_mm, y_mm, z_mm)
        Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(x_mm),
            GeometryHelpers.na_mm_to_inch(y_mm),
            GeometryHelpers.na_mm_to_inch(z_mm)
        )
    end
    private_class_method :na_point
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__PanelGeometryBuilder
end # module Na__ExteriorDoorCommon
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
