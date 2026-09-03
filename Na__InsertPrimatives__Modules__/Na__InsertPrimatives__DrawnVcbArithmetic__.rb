# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PRIMITIVES VCB ARITHMETIC
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnVcbArithmetic__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Measurements-box parsing with relative (+/-) arithmetic for the
#              Drawn Plane and Drawn Volume tools
# CREATED    : 2026
#
# DESCRIPTION:
# - Splits a VCB entry into comma separated tokens and resolves each one against
#   the live dimension it is about to replace.
# - Absolute token : "2400"  "2.4m"  "240cm"        -> that exact size
# - Relative token : "+100"  "-50"   "+0.1m"        -> live size plus/minus
# - Empty token    : ""      (as in "1200,,300")    -> keep the live size
# - Bare numbers are millimetres, matching the rest of this plugin. Suffixes
#   mm / cm / m are accepted and share NA_UNIT_CONVERSIONS_TO_MM with the
#   original cube-mode parser so the two never drift apart.
#
# WHY NOT String#to_l:
# - to_l follows the model units, so a bare "2400" in an imperial model becomes
#   2400 inches. Every other input path in this plugin documents bare numbers as
#   millimetres, so that contract is kept here.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__UserInput__VcbFunctions__'
require_relative 'Na__InsertPrimatives__DrawnGridSnap__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Token Pattern
    # -----------------------------------------------------------------------------

    # Sign is captured separately from the magnitude so "+100" can be resolved
    # against a live value rather than parsed as the number +100.
    NA_DRAWN_VCB_TOKEN_PATTERN = /\A([+-])?\s*(\d+(?:\.\d+)?)\s*(mm|cm|m)?\z/i

    # A whole entry of "24s" sets the circle segment count, the way the native
    # Circle tool takes a sides count. "24seg", "24segs" and "24segments" all work
    # too. Matched before anything else so the trailing letters are never mistaken
    # for a unit suffix.
    #
    # Alternation is longest-first: with "s" leading, "24seg" would match the "s"
    # branch and then fail on the leftover "eg" rather than falling through.
    NA_DRAWN_VCB_SEGMENT_PATTERN = /\A(\d+)\s*(?:segments|segs|seg|s)\z/i

    # A leading d makes a token a diameter rather than a radius: "d600" is a
    # 600 diameter, and "d+100" widens the live diameter by 100.
    NA_DRAWN_VCB_DIAMETER_PREFIX = /\Ad/i

    # A trailing deg, d or the degree sign makes a token an angle: the roof tools
    # take "35deg" as a pitch instead of a rise. Checked before the dimension
    # pattern, which would reject the suffix rather than misread it.
    NA_DRAWN_VCB_ANGLE_PATTERN = /\A([+-])?\s*(\d+(?:\.\d+)?)\s*(?:deg|d|°)\z/i

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Token Parsing
    # -----------------------------------------------------------------------------

    # FUNCTION | Parse One VCB Token
    # Returns nil for an empty token (meaning "leave this dimension alone") or
    # [sign, magnitude_in_inches] where sign is nil, :plus or :minus.
    # Raises ArgumentError when the token cannot be read.
    # ------------------------------------------------------------
    def self.Na__DrawnVcb__ParseToken(token)
        text = token.to_s.strip
        return nil if text.empty?

        match = NA_DRAWN_VCB_TOKEN_PATTERN.match(text)
        raise ArgumentError, "cannot read '#{text}' as a dimension" unless match

        sign_text = match[1]
        magnitude = match[2].to_f
        unit      = (match[3] || 'mm').downcase
        mm_factor = NA_UNIT_CONVERSIONS_TO_MM[unit]

        raise ArgumentError, "unknown unit '#{unit}' in '#{text}'" unless mm_factor

        sign =
            case sign_text
            when '+' then :plus
            when '-' then :minus
            else          nil
            end

        [sign, (magnitude * mm_factor) / NA_DRAWN_INCH_TO_MM]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Parse a Whole VCB Entry into Tokens
    # A trailing separator is preserved (split limit -1) so "1200," and ",600"
    # both mean "set one dimension, keep the other".
    # ------------------------------------------------------------
    def self.Na__DrawnVcb__ParseEntry(text)
        parts = text.to_s.split(',', -1)
        raise ArgumentError, 'no value entered' if parts.empty?

        parts.map { |part| Na__InsertPrimatives.Na__DrawnVcb__ParseToken(part) }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Read a Whole Entry as a Circle Segment Count
    # Returns the count, or nil when the entry is an ordinary dimension.
    # ------------------------------------------------------------
    def self.Na__DrawnVcb__SegmentEntry(text)
        match = NA_DRAWN_VCB_SEGMENT_PATTERN.match(text.to_s.strip)
        return nil unless match

        match[1].to_i
    end
    # ---------------------------------------------------------------

    # FUNCTION | Read a Token as an Angle in Degrees
    # Returns nil when the token is an ordinary dimension, otherwise
    # [sign, degrees] with sign nil, :plus or :minus so "+5deg" can mean five
    # degrees steeper than whatever is on screen.
    # ------------------------------------------------------------
    def self.Na__DrawnVcb__ParseAngleToken(token)
        match = NA_DRAWN_VCB_ANGLE_PATTERN.match(token.to_s.strip)
        return nil unless match

        sign =
            case match[1]
            when '+' then :plus
            when '-' then :minus
            else          nil
            end

        [sign, match[2].to_f]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Split a Leading Diameter Flag off a Token
    # Returns [is_diameter, remaining_token_text].
    # ------------------------------------------------------------
    def self.Na__DrawnVcb__SplitDiameterPrefix(text)
        stripped = text.to_s.strip
        return [true, stripped[1..-1].to_s.strip] if NA_DRAWN_VCB_DIAMETER_PREFIX.match(stripped)

        [false, stripped]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Token Application
    # -----------------------------------------------------------------------------

    # FUNCTION | Is This Token an Absolute Size?
    # ------------------------------------------------------------
    def self.Na__DrawnVcb__AbsoluteToken?(token)
        !token.nil? && token[0].nil?
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve One Token Against the Live Dimension It Replaces
    # live_value is an unsigned magnitude in internal inches. The result is also
    # unsigned — direction stays with the drag, never with the typed number.
    # ------------------------------------------------------------
    def self.Na__DrawnVcb__ApplyToken(token, live_value)
        base = live_value.to_f.abs
        return base if token.nil?

        sign, magnitude = token

        case sign
        when :plus  then base + magnitude
        when :minus then base - magnitude
        else             magnitude
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve a Token List Against a List of Live Dimensions
    # Strictly positional: token 0 addresses dimension 0, token 1 dimension 1,
    # and a missing or empty token leaves that dimension alone.
    #
    # A single token used to be broadcast to every dimension, so "2400" produced
    # a square. That is gone — on the drag tools a typed value now names and locks
    # one axis and leaves the rest to the drag, which is the whole point of typing
    # a size you know while the one you do not stays under the mouse. The
    # click-to-place Cube and Plane modes keep their own broadcast parsers.
    # ------------------------------------------------------------
    def self.Na__DrawnVcb__ResolveAgainst(tokens, live_values)
        return [] if live_values.nil? || live_values.empty?

        live_values.each_with_index.map do |live, index|
            Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(tokens[index], live)
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Which Dimension Slots Did the Entry Actually Name?
    # Returns the indexes carrying a real token, which is what the drag tools
    # lock. An empty token (as in ",1200") names slot 1 and not slot 0.
    # ------------------------------------------------------------
    def self.Na__DrawnVcb__NamedSlots(tokens)
        named = []
        tokens.each_with_index { |token, index| named << index unless token.nil? }
        named
    end
    # ---------------------------------------------------------------

    # FUNCTION | Reject Non-Positive Results with a Readable Message
    # ------------------------------------------------------------
    def self.Na__DrawnVcb__ValidatePositive(values, labels)
        values.each_with_index do |value, index|
            next if value.to_f > NA_DRAWN_MIN_DIMENSION.to_f

            label = labels[index] || 'dimension'
            raise ArgumentError, "#{label} would be #{Na__InsertPrimatives.Na__DrawnFormat__Mm(value)}mm — must be positive"
        end

        values
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PRIMITIVES VCB ARITHMETIC MODULE
# =============================================================================
