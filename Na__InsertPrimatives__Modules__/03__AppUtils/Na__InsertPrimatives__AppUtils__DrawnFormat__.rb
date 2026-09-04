# =============================================================================
# NA INSERT PRIMATIVES - DRAWN FORMAT HELPERS
# =============================================================================
#
# FILE       : Na__InsertPrimatives__AppUtils__DrawnFormat__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Format millimetres, area, volume and degrees for status / VCB
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnGridSnap__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Formatting Helpers
    # -----------------------------------------------------------------------------

    # FUNCTION | Format Internal Inches as a Rounded Millimetre Integer
    # ------------------------------------------------------------
    def self.Na__DrawnFormat__Mm(value)
        (value.to_f * NA_DRAWN_INCH_TO_MM).round
    end
    # ---------------------------------------------------------------

    # FUNCTION | Format an Area in Internal Units as Square Metres
    # ------------------------------------------------------------
    def self.Na__DrawnFormat__AreaM2(u_len, v_len)
        area_mm2 = (u_len.to_f * NA_DRAWN_INCH_TO_MM).abs * (v_len.to_f * NA_DRAWN_INCH_TO_MM).abs
        format('%.2f', area_mm2 / 1_000_000.0)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Format a Volume in Internal Units as Cubic Metres
    # ------------------------------------------------------------
    def self.Na__DrawnFormat__VolumeM3(u_len, v_len, d_len)
        volume_mm3 = (u_len.to_f * NA_DRAWN_INCH_TO_MM).abs *
                     (v_len.to_f * NA_DRAWN_INCH_TO_MM).abs *
                     (d_len.to_f * NA_DRAWN_INCH_TO_MM).abs
        format('%.3f', volume_mm3 / 1_000_000_000.0)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Format a Circle Area in Internal Units as Square Metres
    # ------------------------------------------------------------
    def self.Na__DrawnFormat__CircleAreaM2(radius)
        radius_mm = (radius.to_f * NA_DRAWN_INCH_TO_MM).abs
        format('%.2f', (Math::PI * radius_mm * radius_mm) / 1_000_000.0)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Format a Cylinder Volume in Internal Units as Cubic Metres
    # ------------------------------------------------------------
    def self.Na__DrawnFormat__CylinderVolumeM3(radius, height)
        radius_mm = (radius.to_f * NA_DRAWN_INCH_TO_MM).abs
        height_mm = (height.to_f * NA_DRAWN_INCH_TO_MM).abs
        format('%.3f', (Math::PI * radius_mm * radius_mm * height_mm) / 1_000_000_000.0)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Format an Angle in Degrees to One Decimal Place
    # ------------------------------------------------------------
    def self.Na__DrawnFormat__Degrees(value)
        format('%.1f', value.to_f)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Format a Snapped Point as an mm Coordinate String
    # ------------------------------------------------------------
    def self.Na__DrawnFormat__PointMm(point)
        return '' unless point

        "X#{Na__InsertPrimatives.Na__DrawnFormat__Mm(point.x)} " \
        "Y#{Na__InsertPrimatives.Na__DrawnFormat__Mm(point.y)} " \
        "Z#{Na__InsertPrimatives.Na__DrawnFormat__Mm(point.z)}"
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN FORMAT HELPERS
# =============================================================================
