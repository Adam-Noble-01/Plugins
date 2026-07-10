# frozen_string_literal: true

require 'sketchup.rb'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__GeometryHelpers

    NA_MM_TO_INCH = 1.0 / 25.4
    NA_MIN_LEAF_WIDTH_MM = 300.0
    NA_SWING_SEGMENTS = 32

    def self.na_mm_to_inch(value_mm)
        value_mm.to_f * NA_MM_TO_INCH
    end

    def self.na_clamp(value, minimum, maximum)
        [[value.to_f, minimum.to_f].max, maximum.to_f].min
    end

    def self.na_boolean(config, key, fallback = false)
        value = config[key]
        return fallback if value.nil?
        value == true || value.to_s.casecmp('true').zero?
    end

    def self.na_number(config, key, fallback)
        value = config[key]
        return fallback.to_f if value.nil?
        Float(value)
    rescue ArgumentError, TypeError
        fallback.to_f
    end

    def self.na_resolve_opening_dimensions(config)
        width = [na_number(config, 'width_mm', 1900), 0.0].max
        height = [na_number(config, 'height_mm', 2100), 0.0].max
        uniform = [na_number(config, 'frame_thickness_mm', 50), 0.0].max
        advanced = na_boolean(config, 'advanced_frame_controls', false)

        edge = lambda do |key|
            advanced ? [na_number(config, key, uniform), 0.0].max : uniform
        end

        top = edge.call('frame_top_thickness_mm')
        bottom = edge.call('frame_bottom_thickness_mm')
        left = edge.call('frame_left_thickness_mm')
        right = edge.call('frame_right_thickness_mm')
        depth = [na_number(config, 'frame_depth_mm', 70), 1.0].max
        inset = na_number(config, 'frame_wall_inset_mm', 0)

        {
            :width_mm => width,
            :height_mm => height,
            :frame_top_mm => top,
            :frame_bottom_mm => bottom,
            :frame_left_mm => left,
            :frame_right_mm => right,
            :frame_depth_mm => depth,
            :frame_wall_inset_mm => inset,
            :inner_x_mm => left,
            :inner_z_mm => bottom,
            :inner_w_mm => [width - left - right, 0.0].max,
            :inner_h_mm => [height - top - bottom, 0.0].max
        }
    end

    def self.na_resolve_leaf_widths(config, dimensions)
        clear_width = dimensions[:inner_w_mm]
        minimum = [NA_MIN_LEAF_WIDTH_MM, clear_width / 2.0].min
        maximum = [clear_width - minimum, minimum].max
        requested = na_number(config, 'double_door_active_leaf_width_mm', clear_width / 2.0)
        active_width = na_clamp(requested, minimum, maximum)
        active_side = config['double_door_active_leaf'].to_s.casecmp('Right').zero? ? :right : :left

        left_width = active_side == :left ? active_width : clear_width - active_width
        {
            :active_side => active_side,
            :active_width_mm => active_width,
            :left_width_mm => left_width,
            :right_width_mm => clear_width - left_width
        }
    end

    def self.na_panel_y_origin_mm(config, dimensions)
        thickness = na_number(config, 'double_door_leaf_thickness_mm', 50)
        direction = config['double_door_swing_direction'].to_s.downcase
        near_face = dimensions[:frame_wall_inset_mm]
        far_face = near_face + dimensions[:frame_depth_mm]
        return near_face if direction == 'inward'
        return far_face - thickness if direction == 'outward'
        near_face + (dimensions[:frame_depth_mm] - thickness) / 2.0
    end

    def self.na_hinge_pivot_y_mm(config, dimensions, projection_mm)
        direction = config['double_door_swing_direction'].to_s.downcase
        near_face = dimensions[:frame_wall_inset_mm]
        far_face = near_face + dimensions[:frame_depth_mm]
        direction == 'outward' ? far_face + projection_mm.to_f : near_face - projection_mm.to_f
    end

    def self.na_signed_angle_deg(hinge_side, swing_direction, positive_angle_deg)
        base_sign = hinge_side.to_s.downcase == 'left' ? 1.0 : -1.0
        direction_sign = swing_direction.to_s.downcase == 'inward' ? -1.0 : 1.0
        (base_sign * direction_sign * na_clamp(positive_angle_deg, 0, 180)).round
    end

    def self.na_rotation_transform(descriptor)
        pivot = Geom::Point3d.new(
            na_mm_to_inch(descriptor[:hinge_x_mm]),
            na_mm_to_inch(descriptor[:pivot_y_mm]),
            na_mm_to_inch(descriptor[:origin_z_mm])
        )
        Geom::Transformation.rotation(pivot, Z_AXIS, descriptor[:signed_angle_deg].degrees)
    end

    def self.na_rotate_xy(point_x, point_y, pivot_x, pivot_y, angle_deg)
        radians = angle_deg.to_f * Math::PI / 180.0
        dx = point_x.to_f - pivot_x.to_f
        dy = point_y.to_f - pivot_y.to_f
        {
            :x => pivot_x.to_f + dx * Math.cos(radians) - dy * Math.sin(radians),
            :y => pivot_y.to_f + dx * Math.sin(radians) + dy * Math.cos(radians)
        }
    end

    def self.na_arc_points_mm(pivot_x, pivot_y, radius, start_deg, sweep_deg, segments = NA_SWING_SEGMENTS)
        count = [[segments.to_i, 2].max, 128].min
        (0..count).map do |index|
            angle = (start_deg.to_f + sweep_deg.to_f * index.to_f / count) * Math::PI / 180.0
            {
                :x => pivot_x.to_f + radius.to_f * Math.cos(angle),
                :y => pivot_y.to_f + radius.to_f * Math.sin(angle)
            }
        end
    end

end
end
end
