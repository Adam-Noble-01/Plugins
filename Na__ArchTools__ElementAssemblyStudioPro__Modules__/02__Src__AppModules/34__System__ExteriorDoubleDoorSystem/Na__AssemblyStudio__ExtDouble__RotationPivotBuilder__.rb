# frozen_string_literal: true

require 'sketchup.rb'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__DoorNamingContract__'
require_relative 'Na__AssemblyStudio__ExtDouble__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__RotationPivotBuilder

    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__GeometryHelpers
    NamingContract = Na__AssemblyStudio::Na__GeometryHelpers::Na__DoorNamingContract
    TagManager = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
    EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager

    NA_CROSSHAIR_HALF_MM = 25.0
    NA_ARROW_RADIUS_MM = 100.0
    NA_EDGE_COLOUR_ID = 'MTE201__LineColour__Red'.freeze

    def self.na_build(parent_entities, leaf)
        group = parent_entities.add_group
        group.name = NamingContract.na_format_rot_marker(leaf[:index], NA_ROT_SUFFIX)
        origin = Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(leaf[:hinge_x_mm]),
            GeometryHelpers.na_mm_to_inch(leaf[:pivot_y_mm]),
            GeometryHelpers.na_mm_to_inch(leaf[:origin_z_mm])
        )
        group.transform!(Geom::Transformation.translation(origin))

        na_build_axis(group.entities, leaf[:height_mm])
        na_build_crosshair(group.entities, 0)
        na_build_crosshair(group.entities, leaf[:height_mm])
        na_build_angle_arrow(group.entities, leaf)
        na_style(group)
        group
    end

    def self.na_build_axis(entities, height_mm)
        entities.add_line(na_point(0, 0, 0), na_point(0, 0, height_mm))
    end
    private_class_method :na_build_axis

    def self.na_build_crosshair(entities, z_mm)
        half = NA_CROSSHAIR_HALF_MM
        entities.add_line(na_point(-half, 0, z_mm), na_point(half, 0, z_mm))
        entities.add_line(na_point(0, -half, z_mm), na_point(0, half, z_mm))
    end
    private_class_method :na_build_crosshair

    def self.na_build_angle_arrow(entities, leaf)
        return if leaf[:signed_angle_deg].zero?

        points = GeometryHelpers.na_arc_points_mm(
            0, 0, NA_ARROW_RADIUS_MM,
            leaf[:closed_latch_angle_deg], leaf[:signed_angle_deg], 24
        ).map { |point| na_point(point[:x], point[:y], leaf[:height_mm]) }
        points.each_cons(2) { |first, second| entities.add_line(first, second) }
        na_build_arrowhead(entities, points)
    end
    private_class_method :na_build_angle_arrow

    def self.na_build_arrowhead(entities, points)
        return if points.length < 2
        tip = points[-1]
        prior = points[-2]
        vector = tip - prior
        return unless vector.valid?
        vector.length = GeometryHelpers.na_mm_to_inch(25)
        wing_a = vector.transform(Geom::Transformation.rotation(ORIGIN, Z_AXIS, 150.degrees))
        wing_b = vector.transform(Geom::Transformation.rotation(ORIGIN, Z_AXIS, -150.degrees))
        entities.add_line(tip, tip.offset(wing_a))
        entities.add_line(tip, tip.offset(wing_b))
    end
    private_class_method :na_build_arrowhead

    def self.na_style(group)
        group.entities.grep(Sketchup::Edge).each do |edge|
            TagManager.na_apply_tag_to_entity(edge, :door_helpers)
        end
        EdgeColourManager.na_apply_edge_colour_to_group(group, NA_EDGE_COLOUR_ID)
    end
    private_class_method :na_style

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
