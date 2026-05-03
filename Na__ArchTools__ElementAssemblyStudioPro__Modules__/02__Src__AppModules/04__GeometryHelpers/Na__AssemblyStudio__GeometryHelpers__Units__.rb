# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - UNIT CONVERSION HELPERS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__GeometryHelpers__Units__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__GeometryHelpers
# MODULE     : Na__Units
# AUTHOR     : Noble Architecture
# PURPOSE    : Central millimetre <-> SketchUp-inch conversions used across
#              Element Assembly Studio. Replaces stray NA_MM_TO_INCH
#              duplicates embedded in legacy system modules.
#
# DESCRIPTION:
# - SketchUp’s internal geometry is inches; dialogs and payloads often expose mm.
# - na_mm_to_inch / na_inch_to_mm are thin wrappers via NA_MM_PER_INCH.
#
# NAMING CONVENTION:
# - Geometry helper namespace Na__GeometryHelpers / na_ prefixes.
#
# =============================================================================

module Na__AssemblyStudio
    module Na__GeometryHelpers
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

        end
    end
end
