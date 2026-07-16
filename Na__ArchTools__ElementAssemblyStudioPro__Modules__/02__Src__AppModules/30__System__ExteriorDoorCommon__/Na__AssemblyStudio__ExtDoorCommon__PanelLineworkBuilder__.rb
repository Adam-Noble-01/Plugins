# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOOR COMMON - PANEL LINEWORK BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtDoorCommon__PanelLineworkBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorDoorCommon
# MODULE     : Na__PanelLineworkBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Build the 2D linework alternative to 3D fielded panels: a solid
#              recessed insert box plus front/back outline rectangles.
#
# DESCRIPTION:
# - Extracted from the Exterior Double Door System, parameterized by a `naming`
#   hash (naming[:container]) so container / insert / outline group names carry
#   each system's prefix.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Box__'
require_relative 'Na__AssemblyStudio__ExtDoorCommon__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorDoorCommon
module Na__PanelLineworkBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    GeometryHelpers   = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__GeometryHelpers
    EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager
    Box               = Na__AssemblyStudio::Na__GeometryHelpers::Na__Box

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_FACE_OFFSET_MM = 0.5                                                     # <-- Outline stand-off from insert face

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Build Linework Panels Into a Container Group
    # ------------------------------------------------------------
    # @param naming [Hash] { :container => "Na__ExteriorDoubleDoor" }
    # @param edge_colour_id [String, nil] optional MTE id override
    # @return [Sketchup::Group, nil]
    def self.na_build(entities, leaf, panel_layout, material = nil, naming = {}, edge_colour_id: nil)
        return nil unless entities && panel_layout[:field_cells].any?

        container_prefix = na_container_prefix(naming)
        container = entities.add_group
        container.name = "#{container_prefix}__PanelLinework"
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
                index + 1,
                container_prefix
            )
            na_build_cell(container.entities, cell, front_y, index + 1, 'Front', container_prefix)
            na_build_cell(container.entities, cell, back_y, index + 1, 'Back', container_prefix)
        end

        colour_id = edge_colour_id.to_s
        if colour_id.empty?
            colour_id = if EdgeColourManager.const_defined?(:NA_DEFAULT_DARK_GREY_KEY)
                            EdgeColourManager::NA_DEFAULT_DARK_GREY_KEY
                        else
                            'MTE103__LineColour__DarkGrey__L40'
                        end
        end
        EdgeColourManager.na_apply_or_clear_edge_colour_on_group(container, colour_id)
        container
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Cell Geometry
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Resolve Container Name Prefix From Naming Hash
    # ------------------------------------------------------------
    def self.na_container_prefix(naming)
        prefix = naming.is_a?(Hash) ? naming[:container] : nil
        (prefix && !prefix.to_s.empty?) ? prefix.to_s : 'Na__ExteriorDoor'
    end
    private_class_method :na_container_prefix
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Recessed Panel Insert Box for One Cell
    # ------------------------------------------------------------
    def self.na_build_panel_insert(entities, cell, y_mm, depth_mm, material, index, container_prefix)
        Box.na_create_grouped_box(
            entities,
            format("#{container_prefix}__LineworkPanelInsert__%03d", index),
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
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Front or Back Outline Rectangle for One Cell
    # ------------------------------------------------------------
    def self.na_build_cell(entities, cell, y_mm, index, face_name, container_prefix)
        group = entities.add_group
        group.name = format("#{container_prefix}__PanelLinework__%s__%03d", face_name, index)
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

end # module Na__PanelLineworkBuilder
end # module Na__ExteriorDoorCommon
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
