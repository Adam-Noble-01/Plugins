# =============================================================================
# VALE LANTERN IMPORTER - UNIT CONVERSION HELPERS
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__Units__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__Units
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Millimetre to SketchUp-inch conversion for the whole importer.
#              Mirrors Na__AssemblyStudio::Na__GeometryHelpers::Na__Units so the
#              two Noble Architecture SketchUp tools convert identically.
#
# DESCRIPTION:
# - A Vale lantern payload is millimetres from end to end. SketchUp's internal
#   geometry is inches. This is the single place that gap is crossed.
# - na_point converts a three number array straight into a Geom::Point3d, which
#   is the only form the geometry builders ever ask for.
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

module Na__ValeLantern
    module Na__Importer
        module Na__Units

# -----------------------------------------------------------------------------
# REGION | Conversion Constants
# -----------------------------------------------------------------------------

            NA_MM_PER_INCH = 25.4
            NA_MM_TO_INCH  = 1.0 / NA_MM_PER_INCH                                                   # <-- factor for inch from mm

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Conversion — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Scale millimetres to SketchUp inches
            # ------------------------------------------------------------
            def self.na_mm_to_inch(value_mm)
                value_mm.to_f * NA_MM_TO_INCH
            end
            # ---------------------------------------------------------------

            # FUNCTION | Scale SketchUp inches to millimetres
            # ------------------------------------------------------------
            def self.na_inch_to_mm(value_in)
                value_in.to_f * NA_MM_PER_INCH
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Point Construction — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Build a Geom::Point3d from a millimetre triple
            # ------------------------------------------------------------
            # The payload writes every coordinate as [x, y, z] in millimetres,
            # in the lantern's own model space: origin at the footprint centre
            # on the builders upstand base, +Z up. SketchUp is Z-up too, so
            # there is no axis swap to make here — only a scale.
            #
            # @param triple [Array<Numeric>] Three millimetre values
            # @return [Geom::Point3d, nil] nil when the triple is malformed
            def self.na_point(triple)
                return nil unless triple.is_a?(Array) && triple.length >= 3

                Geom::Point3d.new(
                    na_mm_to_inch(triple[0]),
                    na_mm_to_inch(triple[1]),
                    na_mm_to_inch(triple[2])
                )
            end
            # ---------------------------------------------------------------

            # FUNCTION | Build a Geom::Vector3d from a millimetre triple
            # ------------------------------------------------------------
            # Used for the axis vectors of a component transform. Those arrive
            # unit length and unscaled, so the conversion is a pass through —
            # but it goes through here anyway rather than being constructed
            # inline, so no caller has to remember which triples are scaled.
            def self.na_vector(triple)
                return nil unless triple.is_a?(Array) && triple.length >= 3

                Geom::Vector3d.new(triple[0].to_f, triple[1].to_f, triple[2].to_f)
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        end
    end
end
