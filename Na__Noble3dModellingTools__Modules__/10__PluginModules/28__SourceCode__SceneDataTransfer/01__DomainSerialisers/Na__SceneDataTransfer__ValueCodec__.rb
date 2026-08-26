# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - VALUE CODEC
# =============================================================================
#
# FILE       : Na__SceneDataTransfer__ValueCodec__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__ValueCodec
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Convert SketchUp value objects to and from JSON-safe primitives.
# CREATED    : 2026
#
# WHY THIS EXISTS:
# RenderingOptions and ShadowInfo hand back Ruby objects that JSON cannot
# represent - chiefly Sketchup::Color, and Time. Every value crossing the
# payload boundary passes through here so the encoding is defined in exactly
# one place and both ends agree.
#
# ENCODING SHAPE:
# A value that needs help is wrapped in a tagged Hash:
#
#   { "__na_type" => "Color",   "v" => [r, g, b, a] }     0-255 integers
#   { "__na_type" => "Point3d", "v" => [x, y, z] }        inches
#   { "__na_type" => "Vector3d","v" => [x, y, z] }        inches
#   { "__na_type" => "Time",    "v" => 1793558400 }       integer epoch seconds
#
# Booleans, Integers, Floats, Strings and nil pass straight through untouched.
#
# WHY TIME IS AN EPOCH INTEGER:
# JSON has no Time type, and any string produced by Time#to_s, #inspect or an
# unqualified strftime bakes the EXPORTING machine's OS time zone into the
# payload, which then drifts on import. The integer epoch is the only
# representation that round-trips exactly across machines and time zones.
#
# WHY LENGTHS ARE NEVER CONVERTED:
# SketchUp's internal unit is always inches regardless of the model's display
# units, and Length is a Float subclass. Raw inch Floats therefore transfer
# between models with different unit settings with no conversion at all. Never
# round-trip a length through Length#to_s.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__ValueCodec

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_TYPE_KEY   = '__na_type'.freeze
        NA_VALUE_KEY  = 'v'.freeze

        NA_TYPE_COLOR    = 'Color'.freeze
        NA_TYPE_POINT    = 'Point3d'.freeze
        NA_TYPE_VECTOR   = 'Vector3d'.freeze
        NA_TYPE_TIME     = 'Time'.freeze
        NA_TYPE_UNKNOWN  = 'Unknown'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Encoding
# -----------------------------------------------------------------------------

        # FUNCTION | Convert a SketchUp Value Into a JSON-Safe Primitive
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__Encode(value)
            return nil if value.nil?

            case value
            when TrueClass, FalseClass, String then value
            when Integer                       then value
            when Float                         then na_finite(value)
            when Sketchup::Color               then na_tag(NA_TYPE_COLOR,  na_colour_components(value))
            when Geom::Point3d                 then na_tag(NA_TYPE_POINT,  value.to_a.map(&:to_f))
            when Geom::Vector3d                then na_tag(NA_TYPE_VECTOR, value.to_a.map(&:to_f))
            when Time                          then na_tag(NA_TYPE_TIME,   value.to_i)
            when Array                         then value.map { |element| Na__SceneDataTransfer__Encode(element) }
            else
                na_encode_unknown(value)
            end
        rescue => error
            puts "[Na__SceneDataTransfer] Encode warning (#{value.class}): #{error.message}"
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Fall Back for a Class This Codec Does Not Model
        # ------------------------------------------------------------
        # Numeric subclasses such as Length arrive here on some releases. They
        # are Floats in inches, so to_f is correct and lossless.
        def self.na_encode_unknown(value)
            return na_finite(value.to_f) if value.is_a?(Numeric)

            na_tag(NA_TYPE_UNKNOWN, value.to_s)
        end
        private_class_method :na_encode_unknown
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read the Four Channels Off a Sketchup::Color
        # ------------------------------------------------------------
        def self.na_colour_components(colour)
            [colour.red.to_i, colour.green.to_i, colour.blue.to_i, colour.alpha.to_i]
        rescue
            [0, 0, 0, 255]
        end
        private_class_method :na_colour_components
        # ------------------------------------------------------------

        # HELPER FUNCTION | Wrap a Value in the Tagged Envelope
        # ------------------------------------------------------------
        def self.na_tag(type_name, encoded_value)
            { NA_TYPE_KEY => type_name, NA_VALUE_KEY => encoded_value }
        end
        private_class_method :na_tag
        # ------------------------------------------------------------

        # HELPER FUNCTION | Replace NaN and Infinity, Which JSON Cannot Encode
        # ------------------------------------------------------------
        def self.na_finite(float_value)
            return 0.0 if float_value.nil?
            return 0.0 if float_value.respond_to?(:nan?)      && float_value.nan?
            return 0.0 if float_value.respond_to?(:infinite?) && float_value.infinite?

            float_value.to_f
        end
        private_class_method :na_finite
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Decoding
# -----------------------------------------------------------------------------

        # FUNCTION | Convert a JSON-Safe Primitive Back Into a SketchUp Value
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__Decode(encoded_value)
            return nil if encoded_value.nil?

            unless encoded_value.is_a?(Hash) && encoded_value.key?(NA_TYPE_KEY)
                return encoded_value.map { |element| Na__SceneDataTransfer__Decode(element) } if encoded_value.is_a?(Array)

                return encoded_value
            end

            raw = encoded_value[NA_VALUE_KEY]

            case encoded_value[NA_TYPE_KEY].to_s
            when NA_TYPE_COLOR  then na_build_colour(raw)
            when NA_TYPE_POINT  then na_build_point(raw)
            when NA_TYPE_VECTOR then na_build_vector(raw)
            when NA_TYPE_TIME   then Time.at(raw.to_i)
            else                     raw
            end
        rescue => error
            puts "[Na__SceneDataTransfer] Decode warning: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Rebuild a Sketchup::Color From Four Channels
        # ------------------------------------------------------------
        def self.na_build_colour(components)
            return nil unless components.is_a?(Array) && components.length >= 3

            Sketchup::Color.new(
                components[0].to_i,
                components[1].to_i,
                components[2].to_i,
                components.length > 3 ? components[3].to_i : 255
            )
        end
        private_class_method :na_build_colour
        # ------------------------------------------------------------

        # HELPER FUNCTION | Rebuild a Geom::Point3d From Three Floats
        # ------------------------------------------------------------
        def self.na_build_point(components)
            return nil unless na_is_triple(components)

            Geom::Point3d.new(components[0].to_f, components[1].to_f, components[2].to_f)
        end
        private_class_method :na_build_point
        # ------------------------------------------------------------

        # HELPER FUNCTION | Rebuild a Geom::Vector3d From Three Floats
        # ------------------------------------------------------------
        def self.na_build_vector(components)
            return nil unless na_is_triple(components)

            Geom::Vector3d.new(components[0].to_f, components[1].to_f, components[2].to_f)
        end
        private_class_method :na_build_vector
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Shared Validation Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Validate a Three-Number Array
        # ------------------------------------------------------------
        def self.na_is_triple(candidate)
            candidate.is_a?(Array) && candidate.length == 3 &&
                candidate.all? { |component| component.is_a?(Numeric) }
        end
        # ------------------------------------------------------------

        # FUNCTION | Report Whether Two Encoded Values Are Equivalent
        # ------------------------------------------------------------
        # Used to skip no-op writes, which matters on SketchUp 2024+ where
        # RenderingOptions#[]= raises on an unacceptable value.
        def self.Na__SceneDataTransfer__ValuesMatch(first_value, second_value)
            return true if first_value == second_value

            if first_value.is_a?(Float) || second_value.is_a?(Float)
                return (first_value.to_f - second_value.to_f).abs < 1e-9
            end

            false
        rescue
            false
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__ValueCodec
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
