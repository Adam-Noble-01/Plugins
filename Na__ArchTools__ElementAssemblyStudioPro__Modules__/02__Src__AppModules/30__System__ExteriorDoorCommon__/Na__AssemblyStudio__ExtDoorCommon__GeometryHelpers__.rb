# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOOR COMMON - GEOMETRY HELPERS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtDoorCommon__GeometryHelpers__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorDoorCommon
# MODULE     : Na__GeometryHelpers
# AUTHOR     : Noble Architecture
# PURPOSE    : Generic, system-agnostic maths shared by every exterior door
#              system (single, sliding, multifold, double). Unit conversion,
#              clamping, boolean/number coercion, signed-angle + rotation
#              transforms and swing-arc point sampling.
#
# DESCRIPTION:
# - Extracted from Na__AssemblyStudio__ExtDouble__GeometryHelpers__.rb so the
#   shared panel / handle / rotation builders never depend on a single system.
# - System-specific leaf-width / panel-Y / hinge-pivot maths that read
#   `double_door_*` keys remain in each system's own GeometryHelpers.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'

module Na__AssemblyStudio
module Na__ExteriorDoorCommon
module Na__GeometryHelpers

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_MM_TO_INCH     = 1.0 / 25.4                                              # <-- Inch conversion factor
    NA_SWING_SEGMENTS = 32                                                      # <-- Default arc sample count

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Unit Conversion + Value Coercion
# -----------------------------------------------------------------------------

    # FUNCTION | Convert Millimetres to SketchUp Internal Inches
    # ------------------------------------------------------------
    def self.na_mm_to_inch(value_mm)
        value_mm.to_f * NA_MM_TO_INCH
    end
    # ---------------------------------------------------------------

    # FUNCTION | Clamp a Value Between an Inclusive Minimum and Maximum
    # ------------------------------------------------------------
    def self.na_clamp(value, minimum, maximum)
        [[value.to_f, minimum.to_f].max, maximum.to_f].min
    end
    # ---------------------------------------------------------------

    # FUNCTION | Coerce a Config Value to a Boolean with Fallback
    # ------------------------------------------------------------
    def self.na_boolean(config, key, fallback = false)
        value = config[key]
        return fallback if value.nil?
        value == true || value.to_s.casecmp('true').zero?
    end
    # ---------------------------------------------------------------

    # FUNCTION | Coerce a Config Value to a Float with Fallback
    # ------------------------------------------------------------
    def self.na_number(config, key, fallback)
        value = config[key]
        return fallback.to_f if value.nil?
        Float(value)
    rescue ArgumentError, TypeError
        fallback.to_f
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Rotation + Swing Arc
# -----------------------------------------------------------------------------

    # FUNCTION | Resolve the Signed Rotation Angle for a Door Leaf
    # ------------------------------------------------------------
    # Left hinge + inward -> negative, right hinge + inward -> positive, etc.
    # Used by every door system so the TrueVision/ValeVision rotation sign is
    # consistent across single, double, and bifold leaves.
    def self.na_signed_angle_deg(hinge_side, swing_direction, positive_angle_deg)
        base_sign = hinge_side.to_s.downcase == 'left' ? 1.0 : -1.0
        direction_sign = swing_direction.to_s.downcase == 'inward' ? -1.0 : 1.0
        (base_sign * direction_sign * na_clamp(positive_angle_deg, 0, 180)).round
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build a Z-Axis Rotation Transform Around a Leaf Hinge Pivot
    # ------------------------------------------------------------
    def self.na_rotation_transform(descriptor)
        pivot = Geom::Point3d.new(
            na_mm_to_inch(descriptor[:hinge_x_mm]),
            na_mm_to_inch(descriptor[:pivot_y_mm]),
            na_mm_to_inch(descriptor[:origin_z_mm])
        )
        Geom::Transformation.rotation(pivot, Z_AXIS, descriptor[:signed_angle_deg].degrees)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Rotate a 2D Point Around a Pivot (mm space, for previews/DXF)
    # ------------------------------------------------------------
    def self.na_rotate_xy(point_x, point_y, pivot_x, pivot_y, angle_deg)
        radians = angle_deg.to_f * Math::PI / 180.0
        dx = point_x.to_f - pivot_x.to_f
        dy = point_y.to_f - pivot_y.to_f
        {
            :x => pivot_x.to_f + dx * Math.cos(radians) - dy * Math.sin(radians),
            :y => pivot_y.to_f + dx * Math.sin(radians) + dy * Math.cos(radians)
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Sample an Arc Into a Polyline of {x, y} Points (mm space)
    # ------------------------------------------------------------
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
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__GeometryHelpers
end # module Na__ExteriorDoorCommon
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
