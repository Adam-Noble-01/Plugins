# =============================================================================
# NA PAINTERLYNPR ASSETS - APP UTILS - UNITS AND AXES
# =============================================================================
#
# FILE       : Na__PainterlyAssets__AppUtils__Units__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__Units
# PURPOSE    : The one place the library's frame meets SketchUp's: metres to
#              inches, and the library's axes (+Y up, front +Z) to SketchUp's
#              (Z up, front -Y), both ways.
# CREATED    : 30-Oct-2026
#
# THE TWO FRAMES:
#   Library (glTF, three.js, every DAT and MOD): metres, +Y up, the asset's
#   front to +Z, its origin at the centre of its base on the ground.
#   SketchUp: inches inside, Z up, and the Front view looks along +Y, so an
#   asset's front faces -Y. Hence, for a library point (x, y, z):
#
#       SketchUp (x, y, z) = (x, -z, y) / 0.0254
#
#   A rotation of +90 degrees about X (determinant +1), never a reflection, so
#   triangle winding and face normals come through unchanged. The inverse is
#   library (x, y, z) = (x, z, -y) * 0.0254.
#
# COORDINATES:
#   Everything here is a pure conversion between those two frames. Which
#   SketchUp context a point lives in (a definition's local space, or the
#   world of an open group) is the caller's business: see Placement and
#   Author, and the coordinate rule in their headers.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__Units

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_METRES_PER_INCH = 0.0254                   unless defined?(NA_METRES_PER_INCH)
        NA_INCHES_PER_METRE = 1.0 / NA_METRES_PER_INCH unless defined?(NA_INCHES_PER_METRE)
        NA_MM_PER_INCH     = 25.4                     unless defined?(NA_MM_PER_INCH)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Lengths
    # -------------------------------------------------------------------------

        def self.Na__Units__MetresToInches(metres)
            metres.to_f * NA_INCHES_PER_METRE
        end

        def self.Na__Units__InchesToMetres(inches)
            inches.to_f * NA_METRES_PER_INCH
        end

        def self.Na__Units__InchesToMm(inches)
            inches.to_f * NA_MM_PER_INCH
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Points Between the Frames
    # -------------------------------------------------------------------------

        # FUNCTION | A Library Point (metres, +Y up) as a SketchUp Point (inches, Z up)
        # ------------------------------------------------------------
        # @param triple [Array<Numeric>] [x, y, z] in the library frame, metres
        # @return [Geom::Point3d]
        def self.Na__Units__LibraryToSketchUp(triple)
            k = NA_INCHES_PER_METRE
            Geom::Point3d.new(triple[0].to_f * k, -triple[2].to_f * k, triple[1].to_f * k)
        end
        # ---------------------------------------------------------------

        # FUNCTION | A SketchUp Point (inches, Z up) as a Library Triple (metres, +Y up)
        # ------------------------------------------------------------
        def self.Na__Units__SketchUpToLibrary(point)
            k = NA_METRES_PER_INCH
            [point.x.to_f * k, point.z.to_f * k, -point.y.to_f * k]
        end
        # ---------------------------------------------------------------

        # FUNCTION | SketchUp Bounds (inches) as the DAT's Bounds (metres, library frame)
        # ------------------------------------------------------------
        # Min and Max swap on the depth axis (library z is SketchUp -y), and
        # RadiusM is half the box's diagonal, as the factory measures it
        # (NPR_25_0001: size 0.85 x 0.82 x 0.42 gives 0.627).
        #
        # @param min_point [Geom::Point3d] the box's lowest corner, inches
        # @param max_point [Geom::Point3d] the box's highest corner, inches
        # @return [Hash] { 'Min', 'Max', 'Size', 'RadiusM' } rounded to the millimetre
        def self.Na__Units__BoundsToLibrary(min_point, max_point)
            k    = NA_METRES_PER_INCH
            low  = [min_point.x.to_f * k, min_point.z.to_f * k, -max_point.y.to_f * k]
            high = [max_point.x.to_f * k, max_point.z.to_f * k, -min_point.y.to_f * k]
            size = [high[0] - low[0], high[1] - low[1], high[2] - low[2]]
            radius = Math.sqrt(size.sum { |value| value * value }) / 2.0
            {
                'Min'     => low.map { |value| self.Na__Units__Round(value, 3) },
                'Max'     => high.map { |value| self.Na__Units__Round(value, 3) },
                'Size'    => size.map { |value| self.Na__Units__Round(value, 3) },
                'RadiusM' => self.Na__Units__Round(radius, 3)
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Round for a Record (never -0.0, which JSON writes as "-0.0")
        # ------------------------------------------------------------
        def self.Na__Units__Round(value, digits)
            rounded = value.to_f.round(digits)
            rounded.zero? ? 0.0 : rounded
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
