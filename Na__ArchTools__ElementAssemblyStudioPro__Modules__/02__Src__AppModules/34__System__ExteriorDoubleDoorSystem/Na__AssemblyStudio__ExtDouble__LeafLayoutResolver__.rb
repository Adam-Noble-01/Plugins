# frozen_string_literal: true

require_relative 'Na__AssemblyStudio__ExtDouble__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__LeafLayoutResolver

    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__GeometryHelpers

    def self.na_resolve(config)
        return [] unless config.is_a?(Hash)

        dimensions = GeometryHelpers.na_resolve_opening_dimensions(config)
        return [] if dimensions[:inner_w_mm] <= 0 || dimensions[:inner_h_mm] <= 0

        widths = GeometryHelpers.na_resolve_leaf_widths(config, dimensions)
        panel_y = GeometryHelpers.na_panel_y_origin_mm(config, dimensions)
        left = na_build_leaf(config, dimensions, widths, :left, panel_y)
        right = na_build_leaf(config, dimensions, widths, :right, panel_y)
        [left.freeze, right.freeze].freeze
    end

    def self.na_build_leaf(config, dimensions, widths, side, panel_y)
        left_side = side == :left
        width = left_side ? widths[:left_width_mm] : widths[:right_width_mm]
        origin_x = left_side ? dimensions[:inner_x_mm] : dimensions[:inner_x_mm] + widths[:left_width_mm]
        hinge_x = left_side ? dimensions[:inner_x_mm] : dimensions[:inner_x_mm] + dimensions[:inner_w_mm]
        side_name = left_side ? 'Left' : 'Right'
        projection = GeometryHelpers.na_clamp(
            GeometryHelpers.na_number(config, "double_door_#{side}_hinge_projection_mm", 0),
            0,
            150
        )
        angle = GeometryHelpers.na_number(
            config, "double_door_#{side}_opening_angle_deg", 90
        )
        direction = config['double_door_swing_direction'] || 'Inward'

        {
            :index => left_side ? 1 : 2,
            :side => side,
            :side_name => side_name,
            :hinge_side => side,
            :is_active => widths[:active_side] == side,
            :origin_x_mm => origin_x,
            :origin_y_mm => panel_y,
            :origin_z_mm => dimensions[:inner_z_mm],
            :width_mm => width,
            :height_mm => dimensions[:inner_h_mm],
            :thickness_mm => [GeometryHelpers.na_number(config, 'double_door_leaf_thickness_mm', 50), 1.0].max,
            :hinge_x_mm => hinge_x,
            :pivot_y_mm => GeometryHelpers.na_hinge_pivot_y_mm(config, dimensions, projection),
            :hinge_projection_mm => projection,
            :opening_angle_deg => GeometryHelpers.na_clamp(angle, 0, 180).round,
            :signed_angle_deg => GeometryHelpers.na_signed_angle_deg(side, direction, angle),
            :closed_latch_angle_deg => left_side ? 0.0 : 180.0,
            :latch_x_mm => left_side ? origin_x + width : origin_x,
            :dimensions => dimensions.freeze
        }
    end
    private_class_method :na_build_leaf

end
end
end
