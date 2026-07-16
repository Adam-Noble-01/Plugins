# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR - GEOMETRY HELPERS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSingleDoor__GeometryHelpers__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSingleDoorSystem
# MODULE     : Na__GeometryHelpers
# AUTHOR     : Noble Architecture
# PURPOSE    : Single-leaf opening/leaf/hinge maths for the standalone exterior
#              single door. Generic maths delegate to the shared ExtDoorCommon
#              helpers; only the single-door-specific (single_door_*) geometry
#              lives here.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorSingleDoorSystem
module Na__GeometryHelpers

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    Shared = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_MIN_LEAF_WIDTH_MM = 300.0

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Shared Maths Delegates
# -----------------------------------------------------------------------------

    # FUNCTION | Convert Millimetres to SketchUp Internal Inches
    # ------------------------------------------------------------
    def self.na_mm_to_inch(value_mm)
        Shared.na_mm_to_inch(value_mm)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Clamp a Value Between an Inclusive Minimum and Maximum
    # ------------------------------------------------------------
    def self.na_clamp(value, minimum, maximum)
        Shared.na_clamp(value, minimum, maximum)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Coerce a Config Value to a Boolean with Fallback
    # ------------------------------------------------------------
    def self.na_boolean(config, key, fallback = false)
        Shared.na_boolean(config, key, fallback)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Coerce a Config Value to a Float with Fallback
    # ------------------------------------------------------------
    def self.na_number(config, key, fallback)
        Shared.na_number(config, key, fallback)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve the Signed Rotation Angle for a Door Leaf
    # ------------------------------------------------------------
    def self.na_signed_angle_deg(hinge_side, swing_direction, positive_angle_deg)
        Shared.na_signed_angle_deg(hinge_side, swing_direction, positive_angle_deg)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build a Z-Axis Rotation Transform Around a Leaf Hinge Pivot
    # ------------------------------------------------------------
    def self.na_rotation_transform(descriptor)
        Shared.na_rotation_transform(descriptor)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Sample an Arc Into a Polyline of {x, y} Points (mm space)
    # ------------------------------------------------------------
    def self.na_arc_points_mm(pivot_x, pivot_y, radius, start_deg, sweep_deg, segments = 32)
        Shared.na_arc_points_mm(pivot_x, pivot_y, radius, start_deg, sweep_deg, segments)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Single-Door Geometry
# -----------------------------------------------------------------------------

    # FUNCTION | Resolve Inner Opening Dimensions from the Window-Shared Keys
    # ------------------------------------------------------------
    def self.na_resolve_opening_dimensions(config)
        width = [na_number(config, 'width_mm', 1000), 0.0].max
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
    # ---------------------------------------------------------------

    # FUNCTION | Resolve the Leaf Y Origin from the Swing Direction
    # ------------------------------------------------------------
    def self.na_panel_y_origin_mm(config, dimensions)
        thickness = na_number(config, 'single_door_leaf_thickness_mm', 50)
        direction = config['single_door_swing_direction'].to_s.downcase
        near_face = dimensions[:frame_wall_inset_mm]
        far_face = near_face + dimensions[:frame_depth_mm]
        return near_face if direction == 'inward'
        return far_face - thickness if direction == 'outward'
        near_face + (dimensions[:frame_depth_mm] - thickness) / 2.0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve the Hinge Pivot Y from the Swing Direction + Projection
    # ------------------------------------------------------------
    def self.na_hinge_pivot_y_mm(config, dimensions, projection_mm)
        direction = config['single_door_swing_direction'].to_s.downcase
        near_face = dimensions[:frame_wall_inset_mm]
        far_face = near_face + dimensions[:frame_depth_mm]
        direction == 'outward' ? far_face + projection_mm.to_f : near_face - projection_mm.to_f
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__GeometryHelpers
end # module Na__ExteriorSingleDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
