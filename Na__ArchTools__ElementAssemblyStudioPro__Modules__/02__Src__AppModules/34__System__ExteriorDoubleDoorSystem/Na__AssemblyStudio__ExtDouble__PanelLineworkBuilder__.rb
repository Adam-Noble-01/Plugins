# frozen_string_literal: true

require 'sketchup.rb'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Box__'
require_relative 'Na__AssemblyStudio__ExtDouble__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__PanelLineworkBuilder

    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__GeometryHelpers
    EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager
    Box = Na__AssemblyStudio::Na__GeometryHelpers::Na__Box
    NA_FACE_OFFSET_MM = 0.5

    def self.na_build(entities, leaf, panel_layout, material = nil)
        return nil unless entities && panel_layout[:field_cells].any?

        container = entities.add_group
        container.name = 'Na__ExteriorDoubleDoor__PanelLinework'
        inset_depth = GeometryHelpers.na_clamp(
            panel_layout[:panel_depth_mm],
            1,
            leaf[:thickness_mm] / 2.0 - 0.5
        )
        insert_depth = [leaf[:thickness_mm] - 2.0 * inset_depth, 1.0].max
        insert_y = leaf[:origin_y_mm] + inset_depth
        front_y = insert_y - NA_FACE_OFFSET_MM
        back_y = insert_y + insert_depth + NA_FACE_OFFSET_MM

        panel_layout[:field_cells].each_with_index do |cell, index|
            na_build_panel_insert(
                container.entities,
                cell,
                insert_y,
                insert_depth,
                material,
                index + 1
            )
            na_build_cell(container.entities, cell, front_y, index + 1, 'Front')
            na_build_cell(container.entities, cell, back_y, index + 1, 'Back')
        end

        colour_id = if EdgeColourManager.const_defined?(:NA_DEFAULT_DARK_GREY_KEY)
                        EdgeColourManager::NA_DEFAULT_DARK_GREY_KEY
                    else
                        'MTE103__LineColour__DarkGrey__L40'
                    end
        EdgeColourManager.na_apply_edge_colour_to_group(container, colour_id)
        container
    end

    def self.na_build_panel_insert(entities, cell, y_mm, depth_mm, material, index)
        Box.na_create_grouped_box(
            entities,
            format('Na__ExteriorDoubleDoor__LineworkPanelInsert__%03d', index),
            GeometryHelpers.na_mm_to_inch(cell[:x_mm]),
            GeometryHelpers.na_mm_to_inch(y_mm),
            GeometryHelpers.na_mm_to_inch(cell[:z_mm]),
            GeometryHelpers.na_mm_to_inch(cell[:width_mm]),
            GeometryHelpers.na_mm_to_inch(depth_mm),
            GeometryHelpers.na_mm_to_inch(cell[:height_mm]),
            material
        )
    end
    private_class_method :na_build_panel_insert

    def self.na_build_cell(entities, cell, y_mm, index, face_name)
        group = entities.add_group
        group.name = format('Na__ExteriorDoubleDoor__PanelLinework__%s__%03d', face_name, index)
        x0 = cell[:x_mm]
        x1 = x0 + cell[:width_mm]
        z0 = cell[:z_mm]
        z1 = z0 + cell[:height_mm]
        points = [
            na_point(x0, y_mm, z0),
            na_point(x1, y_mm, z0),
            na_point(x1, y_mm, z1),
            na_point(x0, y_mm, z1)
        ]
        4.times { |i| group.entities.add_line(points[i], points[(i + 1) % 4]) }
        group
    end
    private_class_method :na_build_cell

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
