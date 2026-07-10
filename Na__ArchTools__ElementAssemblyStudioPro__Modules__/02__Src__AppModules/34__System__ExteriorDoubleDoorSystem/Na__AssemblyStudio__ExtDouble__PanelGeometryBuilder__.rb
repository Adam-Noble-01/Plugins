# frozen_string_literal: true

require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Box__'
require_relative 'Na__AssemblyStudio__ExtDouble__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__PanelGeometryBuilder

    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__GeometryHelpers
    Box = Na__AssemblyStudio::Na__GeometryHelpers::Na__Box

    def self.na_build(entities, leaf, panel_layout, material = nil)
        return nil unless entities && panel_layout[:field_cells].any?

        container = entities.add_group
        container.name = 'Na__ExteriorDoubleDoor__PanelGeometry'
        panel_layout[:field_cells].each_with_index do |cell, index|
            na_build_cell(container.entities, leaf, panel_layout, cell, index + 1, material)
        end
        container
    end

    def self.na_build_cell(entities, leaf, layout, cell, index, material)
        group = entities.add_group
        group.name = format('Na__ExteriorDoubleDoor__Field__%03d', index)
        safe = na_safe_profile_dimensions(cell, leaf, layout)
        return group unless safe

        if layout[:profile] == 'RecessedShaker'
            na_build_recessed_shaker(group.entities, leaf, cell, safe, material, index)
        else
            na_build_raised_bevelled(group.entities, leaf, cell, safe, material, index)
        end
        group
    end
    private_class_method :na_build_cell

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
        { :inset => inset, :depth => depth, :bevel => [bevel, inset].min }
    end
    private_class_method :na_safe_profile_dimensions

    def self.na_build_recessed_shaker(entities, leaf, cell, safe, material, index)
        panel_depth = [leaf[:thickness_mm] - 2.0 * safe[:depth], 1.0].max
        inset_panel = na_inset_rect(cell, safe[:inset])
        na_box(
            entities, "Na__Field__#{index}__RecessedCentre",
            inset_panel[:x_mm], leaf[:origin_y_mm] + safe[:depth], inset_panel[:z_mm],
            inset_panel[:width_mm], panel_depth, inset_panel[:height_mm], material
        )
    end
    private_class_method :na_build_recessed_shaker

    def self.na_build_raised_bevelled(entities, leaf, cell, safe, material, index)
        bevel_start_inset = [safe[:inset] - safe[:bevel], 0.0].max
        bevel_rect = na_inset_rect(cell, bevel_start_inset)
        centre = na_inset_rect(cell, safe[:inset])
        edge_depth = [leaf[:thickness_mm] - 2.0 * safe[:depth], 1.0].max

        na_build_ring(
            entities,
            cell,
            bevel_rect,
            leaf[:origin_y_mm] + safe[:depth],
            edge_depth,
            material,
            "#{index}__RaisedEdge"
        )
        na_build_two_sided_bevel_faces(
            entities,
            leaf,
            bevel_rect,
            centre,
            safe[:depth],
            material
        )
        na_box(
            entities, "Na__Field__#{index}__RaisedCentre",
            centre[:x_mm], leaf[:origin_y_mm], centre[:z_mm],
            centre[:width_mm], leaf[:thickness_mm], centre[:height_mm], material
        )
    end
    private_class_method :na_build_raised_bevelled

    def self.na_build_two_sided_bevel_faces(entities, leaf, outer, inner, inset_depth, material)
        front_inner_y = leaf[:origin_y_mm]
        front_outer_y = front_inner_y + inset_depth
        back_outer_y = leaf[:origin_y_mm] + leaf[:thickness_mm]
        back_inner_y = back_outer_y
        back_outer_y -= inset_depth

        na_build_bevel_faces(entities, outer, inner, front_outer_y, front_inner_y, material, -1.0)
        na_build_bevel_faces(entities, outer, inner, back_outer_y, back_inner_y, material, 1.0)
    end
    private_class_method :na_build_two_sided_bevel_faces

    def self.na_build_bevel_faces(entities, outer, inner, outer_y, inner_y, material, desired_y_sign)
        outer_left = outer[:x_mm]
        outer_right = outer[:x_mm] + outer[:width_mm]
        outer_bottom = outer[:z_mm]
        outer_top = outer[:z_mm] + outer[:height_mm]
        inner_left = inner[:x_mm]
        inner_right = inner[:x_mm] + inner[:width_mm]
        inner_bottom = inner[:z_mm]
        inner_top = inner[:z_mm] + inner[:height_mm]

        quads = [
            [
                na_point(outer_left, outer_y, outer_bottom),
                na_point(inner_left, inner_y, inner_bottom),
                na_point(inner_left, inner_y, inner_top),
                na_point(outer_left, outer_y, outer_top)
            ],
            [
                na_point(inner_right, inner_y, inner_bottom),
                na_point(outer_right, outer_y, outer_bottom),
                na_point(outer_right, outer_y, outer_top),
                na_point(inner_right, inner_y, inner_top)
            ],
            [
                na_point(outer_left, outer_y, outer_bottom),
                na_point(outer_right, outer_y, outer_bottom),
                na_point(inner_right, inner_y, inner_bottom),
                na_point(inner_left, inner_y, inner_bottom)
            ],
            [
                na_point(inner_left, inner_y, inner_top),
                na_point(inner_right, inner_y, inner_top),
                na_point(outer_right, outer_y, outer_top),
                na_point(outer_left, outer_y, outer_top)
            ]
        ]

        target_normals = [
            Geom::Vector3d.new(-1.0, desired_y_sign, 0.0),
            Geom::Vector3d.new(1.0, desired_y_sign, 0.0),
            Geom::Vector3d.new(0.0, desired_y_sign, -1.0),
            Geom::Vector3d.new(0.0, desired_y_sign, 1.0)
        ]

        quads.each_with_index do |points, index|
            face = entities.add_face(points)
            next unless face
            face.reverse! if face.normal.dot(target_normals[index]) < 0
            face.material = material if material
            face.back_material = material if material
        end
    end
    private_class_method :na_build_bevel_faces

    def self.na_build_ring(entities, outer, inner, y_mm, depth, material, token)
        left_width = inner[:x_mm] - outer[:x_mm]
        bottom_height = inner[:z_mm] - outer[:z_mm]
        na_box(entities, "Na__FieldRing__#{token}__Left", outer[:x_mm], y_mm, outer[:z_mm],
               left_width, depth, outer[:height_mm], material)
        na_box(entities, "Na__FieldRing__#{token}__Right", inner[:x_mm] + inner[:width_mm], y_mm, outer[:z_mm],
               left_width, depth, outer[:height_mm], material)
        na_box(entities, "Na__FieldRing__#{token}__Bottom", inner[:x_mm], y_mm, outer[:z_mm],
               inner[:width_mm], depth, bottom_height, material)
        na_box(entities, "Na__FieldRing__#{token}__Top", inner[:x_mm], y_mm, inner[:z_mm] + inner[:height_mm],
               inner[:width_mm], depth, bottom_height, material)
    end
    private_class_method :na_build_ring

    def self.na_inset_rect(rect, inset)
        {
            :x_mm => rect[:x_mm] + inset,
            :z_mm => rect[:z_mm] + inset,
            :width_mm => rect[:width_mm] - 2.0 * inset,
            :height_mm => rect[:height_mm] - 2.0 * inset
        }
    end
    private_class_method :na_inset_rect

    def self.na_box(entities, name, x, y, z, width, depth, height, material)
        return nil if width <= 0 || depth <= 0 || height <= 0
        Box.na_create_grouped_box(
            entities, name,
            GeometryHelpers.na_mm_to_inch(x),
            GeometryHelpers.na_mm_to_inch(y),
            GeometryHelpers.na_mm_to_inch(z),
            GeometryHelpers.na_mm_to_inch(width),
            GeometryHelpers.na_mm_to_inch(depth),
            GeometryHelpers.na_mm_to_inch(height),
            material
        )
    end
    private_class_method :na_box

    def self.na_point(x_mm, y_mm, z_mm)
        Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(x_mm),
            GeometryHelpers.na_mm_to_inch(y_mm),
            GeometryHelpers.na_mm_to_inch(z_mm)
        )
    end
    private_class_method :na_point

end
end
end
