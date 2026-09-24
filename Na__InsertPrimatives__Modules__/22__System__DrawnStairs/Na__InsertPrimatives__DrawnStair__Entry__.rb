# =============================================================================
# NA INSERT PRIMATIVES - DRAWN STAIR MEASUREMENTS BOX ENTRY
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnStair__Entry__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Read a typed pitch, rise, going or step count, and resolve it into
#              the stair's next state — or refuse it with the fix named
# CREATED    : 2026
#
# WHAT A TYPED VALUE MEANS (in the flight stage it builds; afterwards it corrects):
#   35            a PITCH in degrees. A bare number is a pitch, the way it is on
#                 a roof: a stair is specified by its steepness, not its run.
#                 35d, 35deg and 35° read the same.
#   175r          an exact RISE per step. The risers become the whole number
#                 nearest the block's height, and the height becomes
#                 risers x rise, so the top can move by up to half a rise. The
#                 status bar says by how much.
#   250g          an exact GOING per step. The run becomes goings x going, and
#                 the landing takes whatever of the block is left.
#   175r,250g     both, in either order. Part K work: the stair is exactly this.
#   9s            the STEP COUNT, nine risers (9st, 9steps, 9risers too).
#   +5 +10r -20g +1s   relative to the stair on screen.
#
# THE STATE AN ENTRY RESOLVES INTO:
#   { :steps, :run, :rise_strict, :going_strict }. An exact rise or going stays
#   exact through later entries on the same stair, so 9s after 175r is nine
#   rises of 175. A pitch releases an exact going, because both set the run.
#
# REFUSED, NEVER CLAMPED (the rule from 5.1.10: say what would fix it):
#   a pitch outside 0-90 · a run longer than the block · fewer than 2 risers ·
#   a rise under 50mm · a pitch and a going in the same entry
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__InsertPrimatives__DrawnVcbArithmetic__'
require_relative 'Na__InsertPrimatives__DrawnStair__Geometry__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Token Patterns
    # -----------------------------------------------------------------------------

    # Checked first, so the trailing letters are never taken for a unit, and so
    # "9risers" is a count rather than a 9mm rise followed by "isers".
    NA_DRAWN_STAIR_STEPS_PATTERN = /\A([+-])?\s*(\d+)\s*(?:steps|step|st|s|risers|riser)\z/i

    # A rise or going is an ordinary dimension token with r or g after it, so
    # the value in front goes through the same parser as every other size in
    # the plugin: bare mm, or mm | cm | m, and a leading + or - for relative.
    NA_DRAWN_STAIR_RISE_PATTERN  = /\A(.+?)\s*r\z/i
    NA_DRAWN_STAIR_GOING_PATTERN = /\A(.+?)\s*g\z/i

    NA_DRAWN_STAIR_KIND_LABELS   = {
        :pitch => 'pitch',
        :rise  => 'rise',
        :going => 'going',
        :steps => 'step count'
    }.freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Parsing
    # -----------------------------------------------------------------------------

    # FUNCTION | Read a Whole Entry into a Request
    # ------------------------------------------------------------
    # Returns a hash with any of :pitch, :rise, :going and :steps, each a
    # [sign, magnitude] pair where sign is nil, :plus or :minus. Rises and
    # goings are in internal inches, pitches in degrees, counts as Integers.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__ParseEntry(text)
        parts = text.to_s.split(',').map { |part| part.strip }.reject { |part| part.empty? }
        raise ArgumentError, 'no value entered' if parts.empty?
        raise ArgumentError, 'a stair takes up to three values, e.g. 9s,175r,250g' if parts.length > 3

        request = {}

        parts.each do |part|
            kind, token = Na__InsertPrimatives.Na__DrawnStair__ClassifyToken(part)
            raise ArgumentError, "the #{NA_DRAWN_STAIR_KIND_LABELS[kind]} is typed twice" if request.key?(kind)

            request[kind] = token
        end

        if request.key?(:pitch) && request.key?(:going)
            raise ArgumentError, 'a pitch and a going both set the run — type one or the other'
        end

        request
    end
    # ---------------------------------------------------------------

    # FUNCTION | Decide What One Token Is
    # Returns [kind, [sign, magnitude]], or raises with the forms that work.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__ClassifyToken(part)
        text = part.to_s.strip

        steps = NA_DRAWN_STAIR_STEPS_PATTERN.match(text)
        return [:steps, [Na__InsertPrimatives.Na__DrawnStair__SignOf(steps[1]), steps[2].to_i]] if steps

        rise = NA_DRAWN_STAIR_RISE_PATTERN.match(text)
        if rise && NA_DRAWN_VCB_TOKEN_PATTERN.match(rise[1].strip)
            return [:rise, Na__InsertPrimatives.Na__DrawnVcb__ParseToken(rise[1])]
        end

        going = NA_DRAWN_STAIR_GOING_PATTERN.match(text)
        if going && NA_DRAWN_VCB_TOKEN_PATTERN.match(going[1].strip)
            return [:going, Na__InsertPrimatives.Na__DrawnVcb__ParseToken(going[1])]
        end

        pitch = Na__InsertPrimatives.Na__DrawnVcb__ParseAngleToken(text, true)
        return [:pitch, pitch] if pitch

        raise ArgumentError, "cannot read '#{text}' — type a pitch (35), a rise (175r), a going (250g) or a step count (9s)"
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Typed + or - as the Sign Symbol the Plugin Uses
    # ------------------------------------------------------------
    def self.Na__DrawnStair__SignOf(sign_text)
        case sign_text
        when '+' then :plus
        when '-' then :minus
        else          nil
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve a [sign, magnitude] Token Against the Value on Screen
    # ------------------------------------------------------------
    def self.Na__DrawnStair__ApplyRelative(token, base)
        sign, magnitude = token

        case sign
        when :plus  then base.to_f + magnitude.to_f
        when :minus then base.to_f - magnitude.to_f
        else             magnitude.to_f
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Resolution
    # -----------------------------------------------------------------------------

    # FUNCTION | Turn a Request into the Stair's Next State, or Refuse It
    # ------------------------------------------------------------
    # The order matters and follows how the numbers depend on each other:
    #   1  the rise, because an exact rise can choose the step count
    #   2  the step count, typed or chosen by the rise
    #   3  the height and so the actual rise, which the minimum rise checks
    #   4  the run, from a pitch (which needs the rise) or an exact going
    #      (which needs the count), else left where the drag put it
    # Nothing is clamped. Every refusal is an ArgumentError, which the shared
    # onUserText turns into a beep and an "Invalid entry — ..." status line.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__ResolveEntry(frame, state, request)
        raise ArgumentError, 'pick the side the stair rises from first' unless frame

        fmt       = lambda { |value| Na__InsertPrimatives.Na__DrawnStair__FormatMm(value) }
        degrees   = lambda { |value| Na__InsertPrimatives.Na__DrawnFormat__Degrees(value) }
        current   = Na__InsertPrimatives.Na__DrawnStair__Derive(frame, state)
        block_h   = frame[:height].to_f
        depth     = frame[:depth].to_f
        tolerance = NA_DRAWN_STAIR_MERGE_TOL.to_f
        min_rise  = NA_DRAWN_STAIR_MIN_RISE.to_f
        min_steps = NA_DRAWN_STAIR_MIN_STEPS

        steps        = current[:steps]
        rise_strict  = state[:rise_strict]
        going_strict = state[:going_strict]
        run          = state[:run].to_f

        # 1 | An exact rise, which stays exact from here on.
        if request[:rise]
            rise_strict = Na__InsertPrimatives.Na__DrawnStair__ApplyRelative(request[:rise], current[:rise])

            if rise_strict < min_rise - tolerance
                raise ArgumentError,
                      "a #{fmt.call(rise_strict)} rise is not a step — a step rises at least #{fmt.call(min_rise)}. " \
                      "A count of steps takes an s, e.g. #{Na__InsertPrimatives.Na__DrawnStair__DefaultSteps(block_h)}s"
            end
        end

        # 2 | The step count: typed, or the whole number of exact rises nearest the block.
        if request[:steps]
            steps = Na__InsertPrimatives.Na__DrawnStair__ApplyRelative(request[:steps], current[:steps]).round
        elsif request[:rise]
            steps = (block_h / rise_strict.to_f).round
        end

        if steps < min_steps
            if request[:rise] && !request[:steps]
                raise ArgumentError,
                      "a #{fmt.call(rise_strict)} rise is over half the block's #{fmt.call(block_h)} height — " \
                      "a stair needs at least #{min_steps} risers"
            end

            raise ArgumentError, "#{steps} riser#{steps == 1 ? '' : 's'} is not a stair — it needs at least #{min_steps}"
        end

        # 3 | The height those risers reach, and so the rise each one really is.
        height = rise_strict ? steps * rise_strict.to_f : block_h
        rise   = height / steps

        if rise < min_rise - tolerance
            raise ArgumentError,
                  "#{steps} risers would each rise #{fmt.call(rise)} — a step rises at least #{fmt.call(min_rise)}, " \
                  "so #{Na__InsertPrimatives.Na__DrawnStair__MaxSteps(height)}s is the most this block takes"
        end

        # 4 | The run.
        if request[:pitch]
            pitch = Na__InsertPrimatives.Na__DrawnStair__ApplyRelative(request[:pitch], current[:pitch])

            unless pitch > 0.0 && pitch < 90.0
                raise ArgumentError,
                      "#{degrees.call(pitch)}° is not a stair pitch — a rise needs r (175r), a going needs g (250g)"
            end

            going_strict = nil
            run          = (steps - 1) * rise / Math.tan(pitch * Math::PI / 180.0)

            if run > depth + tolerance
                shallowest = (Math.atan2((steps - 1) * rise, depth) * 1800.0 / Math::PI).ceil / 10.0
                raise ArgumentError,
                      "#{degrees.call(pitch)}° needs a #{fmt.call(run)} run for #{steps} risers — the block is " \
                      "#{fmt.call(depth)} deep, and #{degrees.call(shallowest)}° is the shallowest that fits"
            end
        elsif request[:going]
            going_strict = Na__InsertPrimatives.Na__DrawnStair__ApplyRelative(request[:going], current[:going])

            if going_strict < NA_DRAWN_STAIR_MIN_GOING.to_f
                raise ArgumentError, "a #{fmt.call(going_strict)} going is not a tread — type the going per step, e.g. 250g"
            end
        end

        if going_strict
            run = (steps - 1) * going_strict.to_f

            if run > depth + tolerance
                most = (depth / going_strict.to_f).floor + 1

                if most < min_steps
                    raise ArgumentError,
                          "one #{fmt.call(going_strict)} going is longer than the whole #{fmt.call(depth)} block"
                end

                longest_mm = ((depth / (steps - 1)) * NA_DRAWN_INCH_TO_MM * 10.0).floor / 10.0
                raise ArgumentError,
                      "#{steps - 1} goings of #{fmt.call(going_strict)} need a #{fmt.call(run)} run — the block is " \
                      "#{fmt.call(depth)} deep; #{Na__InsertPrimatives.Na__DrawnStair__FormatMmValue(longest_mm)}g fits, " \
                      "or #{most}s at this going"
            end
        end

        if run <= tolerance
            raise ArgumentError, 'the flight has no run yet — drag inward first, or type a pitch (35) or a going (250g)'
        end

        {
            :steps        => steps,
            :run          => run > depth ? depth : run,
            :rise_strict  => rise_strict,
            :going_strict => going_strict
        }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN STAIR MEASUREMENTS BOX ENTRY
# =============================================================================
