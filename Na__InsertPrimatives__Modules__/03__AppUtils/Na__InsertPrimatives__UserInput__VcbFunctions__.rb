# =============================================================================
# NA INSERT PRIMATIVES - VCB INPUT FUNCTIONS
# =============================================================================
#
# FILE       : Na__InsertPrimatives__UserInput__VcbFunctions__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : VCB (Value Control Box) parsing, unit conversion, and display
# CREATED    : 2026
#
# DESCRIPTION:
# - Unit conversion constants for mm, cm, m
# - Math helper functions for parsing dimension strings with unit suffixes
# - VCB display helper to update SketchUp status bar
#
# SUPPORTED INPUT FORMATS:
#   Single value : "1m"  → 1m x 1m x 1m (all sides equal)
#   Three values : "2m,4m,100mm"  or  "2000,4000,100"
#   Per-token    : 1000mm  100cm  1m
#   Bare numbers (no suffix) are treated as mm
#
# =============================================================================

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Unit Conversion Constants
    # -----------------------------------------------------------------------------

    NA_UNIT_CONVERSIONS_TO_MM = {
        'mm' => 1.0,
        'cm' => 10.0,
        'm'  => 1000.0
    }.freeze

    NA_UNIT_SUFFIX_PATTERN = /\A([+-]?\d+(?:\.\d+)?)\s*(mm|cm|m)?\z/i

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Math Helper Functions — Unit Parsing and Conversion
    # -----------------------------------------------------------------------------

    # FUNCTION | Parse a Single Dimension String to SketchUp Length
    # Returns value in SketchUp internal inches.
    # Supported suffixes: mm cm m (case-insensitive).
    # No suffix is treated as millimetres.
    # Raises ArgumentError if the string cannot be parsed.
    # ------------------------------------------------------------
    def self.Na__VcbInput__ParseSingleDimension(str)
        cleaned = str.strip
        match   = NA_UNIT_SUFFIX_PATTERN.match(cleaned)

        raise ArgumentError, "Cannot parse dimension: '#{str}'" unless match

        numeric_value = match[1].to_f
        unit_suffix   = (match[2] || 'mm').downcase
        mm_factor     = NA_UNIT_CONVERSIONS_TO_MM[unit_suffix]

        raise ArgumentError, "Unknown unit '#{unit_suffix}' in: '#{str}'" unless mm_factor

        value_in_mm = numeric_value * mm_factor
        value_in_mm.mm
    end
    # ---------------------------------------------------------------

    # FUNCTION | Parse a Dimension String to [x, y, z]
    # Accepts either:
    #   - 1 token  : single value broadcast to all three dimensions (e.g. "1m" → 1m x 1m x 1m)
    #   - 3 tokens : explicit X,Y,Z (e.g. "2000,4000,100" or "2m,4m,100mm")
    # Returns an array of three SketchUp length values [x_len, y_len, z_len].
    # Raises ArgumentError if the count is wrong or any token is invalid.
    # ------------------------------------------------------------
    def self.Na__VcbInput__ParseDimensions(text)
        parts = text.split(',').map(&:strip)

        case parts.length
        when 1
            val = Na__VcbInput__ParseSingleDimension(parts[0])
            [val, val, val]
        when 3
            parts.map { |part| Na__VcbInput__ParseSingleDimension(part) }
        else
            raise ArgumentError, "Enter 1 value (cube) or 3 values X,Y,Z — got #{parts.length}"
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | VCB Display Helpers
    # -----------------------------------------------------------------------------

    # FUNCTION | Update VCB Status Bar with Current Cube Dimensions
    # Accepts SketchUp length values (internal inches).
    # Displays in mm rounded to nearest integer.
    # ------------------------------------------------------------
    def self.Na__VcbInput__UpdateDisplay(x_val, y_val, z_val)
        x_mm = x_val.to_mm.round
        y_mm = y_val.to_mm.round
        z_mm = z_val.to_mm.round
        Sketchup::set_status_text("#{x_mm},#{y_mm},#{z_mm}", SB_VCB_VALUE)
        Sketchup::set_status_text("Cube: single value or X,Y,Z (mm | cm | m)", SB_VCB_LABEL)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF VCB FUNCTIONS MODULE
# =============================================================================
