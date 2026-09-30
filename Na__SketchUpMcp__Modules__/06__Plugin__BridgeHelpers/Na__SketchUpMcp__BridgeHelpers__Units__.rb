# =============================================================================
# NA SKETCHUP MCP - BRIDGE HELPERS - UNITS
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeHelpers__Units__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Units
# PURPOSE    : Convert every length, area, volume and angle crossing the wire
# CREATED    : 2026
#
# THE UNITS CONTRACT:
# - SketchUp stores every length in inches internally. Agents never see that.
# - Each call carries one unit (default mm, from AppConfig defaults.units).
#   Every length in that call's input AND output is in that unit.
# - Angles are degrees on the wire, radians inside SketchUp.
# - A bare number means the call's unit. A string may carry its own unit
#   ("2400mm", "2.4m", "8'6\"") so an agent can mix units safely.
# - Conversion is plain arithmetic on exact factors (25.4 mm per inch) so the
#   helpers behave identically inside SketchUp and in the offline test runner.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Units

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_INCHES_PER_UNIT = {
            'mm' => 1.0 / 25.4,
            'cm' => 1.0 / 2.54,
            'm'  => 1.0 / 0.0254,
            'in' => 1.0,
            'ft' => 12.0,
            'yd' => 36.0
        }.freeze

        NA_OUTPUT_DECIMALS = { 'mm' => 3, 'cm' => 4, 'm' => 6, 'in' => 4, 'ft' => 5, 'yd' => 6 }.freeze

        NA_UNIT_ALIASES = {
            'millimeter' => 'mm', 'millimeters' => 'mm', 'millimetre' => 'mm', 'millimetres' => 'mm',
            'centimeter' => 'cm', 'centimeters' => 'cm', 'centimetre' => 'cm', 'centimetres' => 'cm',
            'meter' => 'm', 'meters' => 'm', 'metre' => 'm', 'metres' => 'm',
            'inch' => 'in', 'inches' => 'in', '"' => 'in',
            'foot' => 'ft', 'feet' => 'ft', "'" => 'ft',
            'yard' => 'yd', 'yards' => 'yd'
        }.freeze

        NA_LENGTH_STRING = /\A\s*(-?\d+(?:\.\d+)?|-?\.\d+)\s*(mm|cm|m|in|inch|inches|"|ft|feet|foot|'|yd|yard|yards)?\s*\z/i.freeze
        NA_FEET_INCHES_STRING = /\A\s*(-?\d+(?:\.\d+)?)\s*(?:'|ft)\s*-?\s*(\d+(?:\.\d+)?)\s*(?:"|in)?\s*\z/i.freeze

        NA_DEGREES_PER_RADIAN = 180.0 / Math::PI

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Unit Resolution
# -----------------------------------------------------------------------------

        # unit_param: the call's "units" value (nil -> AppConfig default). Returns a key of NA_INCHES_PER_UNIT.
        def self.Na__Units__Resolve(unit_param, model)
            raw_unit = unit_param.nil? ? Na__ConfigLoader.Na__ConfigLoader__Get('defaults', 'units', 'mm') : unit_param
            unit = raw_unit.to_s.strip.downcase
            unit = NA_UNIT_ALIASES.fetch(unit, unit)
            return na_model_length_unit(model) if unit == 'model'
            return unit if NA_INCHES_PER_UNIT.key?(unit)

            raise Na__McpError.new('invalid_params', "Unknown units '#{raw_unit}'.",
                                   'Use one of: mm, cm, m, in, ft, yd, model.')
        end

        # The model's own display unit (Model Info > Units) as a wire unit key.
        def self.Na__Units__ModelLengthUnit(model)
            na_model_length_unit(model)
        end

        def self.na_model_length_unit(model)
            length_unit = model.options['UnitsOptions']['LengthUnit']
            {
                Length::Inches     => 'in',
                Length::Feet       => 'ft',
                Length::Millimeter => 'mm',
                Length::Centimeter => 'cm',
                Length::Meter      => 'm',
                Length::Yard       => 'yd'
            }.fetch(length_unit, 'in')
        rescue StandardError
            'in'
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Lengths In (wire -> inches)
# -----------------------------------------------------------------------------

        def self.Na__Units__ToInches(value, unit, label = 'length')
            case value
            when Numeric
                number = value.to_f
                unless number.finite?
                    raise Na__McpError.new('invalid_params', "#{label} is not a finite number.", 'Pass a real number.')
                end

                number * NA_INCHES_PER_UNIT.fetch(unit)
            when String
                na_parse_length_string(value, unit, label)
            else
                raise Na__McpError.new('invalid_params', "#{label} must be a number or a length string, got #{value.class}.",
                                       "Pass a number in #{unit}, or a string such as \"2400mm\" or \"8'6\\\"\".")
            end
        end

        def self.na_parse_length_string(text, unit, label)
            feet_inches = NA_FEET_INCHES_STRING.match(text)
            if feet_inches
                sign = feet_inches[1].start_with?('-') ? -1.0 : 1.0
                return (feet_inches[1].to_f * 12.0) + (sign * feet_inches[2].to_f)
            end

            simple = NA_LENGTH_STRING.match(text)
            unless simple
                raise Na__McpError.new('invalid_params', "#{label} '#{text}' is not a length I can read.",
                                       "Use a number in #{unit}, or a value with its unit: \"2400mm\", \"2.4m\", \"96in\", \"8'6\\\"\".")
            end

            suffix = simple[2].to_s.downcase
            value_unit = suffix.empty? ? unit : NA_UNIT_ALIASES.fetch(suffix, suffix)
            simple[1].to_f * NA_INCHES_PER_UNIT.fetch(value_unit)
        end

        def self.Na__Units__PositiveLength(value, unit, label)
            inches = self.Na__Units__ToInches(value, unit, label)
            return inches if inches > 0.0

            raise Na__McpError.new('invalid_params', "#{label} must be greater than zero (got #{value}).",
                                   "Pass a positive #{label} in #{unit}.")
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Lengths Out (inches -> wire)
# -----------------------------------------------------------------------------

        def self.Na__Units__FromInches(inches, unit)
            (inches.to_f / NA_INCHES_PER_UNIT.fetch(unit)).round(NA_OUTPUT_DECIMALS.fetch(unit))
        end

        def self.Na__Units__AreaFromSquareInches(square_inches, unit)
            factor = NA_INCHES_PER_UNIT.fetch(unit)
            (square_inches.to_f / (factor * factor)).round(NA_OUTPUT_DECIMALS.fetch(unit) + 2)
        end

        def self.Na__Units__VolumeFromCubicInches(cubic_inches, unit)
            factor = NA_INCHES_PER_UNIT.fetch(unit)
            (cubic_inches.to_f / (factor * factor * factor)).round(NA_OUTPUT_DECIMALS.fetch(unit) + 2)
        end

        def self.Na__Units__AreaUnitLabel(unit)
            "#{unit}2"
        end

        def self.Na__Units__VolumeUnitLabel(unit)
            "#{unit}3"
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Points and Vectors
# -----------------------------------------------------------------------------

        # [x, y] or [x, y, z] in the call's unit -> Geom::Point3d in inches. z defaults to 0.
        def self.Na__Units__Point(values, unit, label = 'point')
            coordinates = na_coordinate_triple(values, label)
            Geom::Point3d.new(*coordinates.each_with_index.map { |value, index| self.Na__Units__ToInches(value, unit, "#{label}[#{index}]") })
        end

        # A displacement: lengths in the call's unit, scaled to inches.
        def self.Na__Units__Offset(values, unit, label = 'vector')
            coordinates = na_coordinate_triple(values, label)
            Geom::Vector3d.new(*coordinates.each_with_index.map { |value, index| self.Na__Units__ToInches(value, unit, "#{label}[#{index}]") })
        end

        # A direction: unitless, must not be zero length. Returned normalised.
        def self.Na__Units__Direction(values, label = 'direction')
            coordinates = na_coordinate_triple(values, label).map(&:to_f)
            length = Math.sqrt(coordinates.map { |value| value * value }.sum)
            if length < 1.0e-12 || !length.finite?
                raise Na__McpError.new('invalid_params', "#{label} #{values.inspect} has zero length.",
                                       'Give a non-zero direction such as [0, 0, 1].')
            end

            Geom::Vector3d.new(*coordinates.map { |value| value / length })
        end

        def self.Na__Units__PointOut(point, unit)
            [self.Na__Units__FromInches(point.x, unit),
             self.Na__Units__FromInches(point.y, unit),
             self.Na__Units__FromInches(point.z, unit)]
        end

        def self.Na__Units__OffsetOut(vector, unit)
            [self.Na__Units__FromInches(vector.x, unit),
             self.Na__Units__FromInches(vector.y, unit),
             self.Na__Units__FromInches(vector.z, unit)]
        end

        def self.Na__Units__DirectionOut(vector)
            length = Math.sqrt((vector.x.to_f**2) + (vector.y.to_f**2) + (vector.z.to_f**2))
            return [0.0, 0.0, 0.0] if length < 1.0e-12

            [vector.x.to_f / length, vector.y.to_f / length, vector.z.to_f / length].map { |value| value.round(6) + 0.0 }
        end

        def self.na_coordinate_triple(values, label)
            unless values.is_a?(Array) && (values.length == 2 || values.length == 3)
                raise Na__McpError.new('invalid_params', "#{label} must be [x, y, z] (or [x, y]), got #{values.inspect}.",
                                       'Pass an array of 2 or 3 numbers.')
            end

            values.length == 2 ? values + [0] : values
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Angles
# -----------------------------------------------------------------------------

        def self.Na__Units__Radians(degrees)
            degrees.to_f / NA_DEGREES_PER_RADIAN
        end

        def self.Na__Units__Degrees(radians, decimals = 4)
            (radians.to_f * NA_DEGREES_PER_RADIAN).round(decimals) + 0.0
        end

# endregion -------------------------------------------------------------------

    end # module Na__Units
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
