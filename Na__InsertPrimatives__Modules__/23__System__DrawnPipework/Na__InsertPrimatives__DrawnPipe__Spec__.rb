# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PIPE SPEC
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPipe__Spec__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : The pipe's diameter, bend radius, sides and bore: remembered
#              between sessions, and read from the measurements box
# CREATED    : 2026
#
# THE SPEC:
#   diameter     the OUTSIDE diameter of the pipe
#   bend radius  the CENTRELINE radius of every bend. 110 round an 80 pipe is a
#                long-radius elbow; 0 mitres the corners instead of bending them
#   sides        facets round the pipe. This IS the plugin's Circle Sides
#                setting, so "24s" and the popup's Circle Sides button are one
#                value, shared with the Drawn Cylinder
#   inner        the INTERNAL diameter (the bore) of a true, hollow pipe; 0 is
#                solid. Only used while the popup's Internal Diameter option
#                is on (5.2.10), or on a pipe that was built hollow
#
# MEASUREMENTS BOX — one grammar at every stage:
#   80,110,24s,70  diameter, bend radius, sides, bore; positional, any slot
#                  may be empty
#   ,150         the bend radius only          ,,32s   the sides only
#   80d   d80    the diameter only             110r    r110   the bend radius only
#   24s          the sides only                0r      mitred elbows
#   70i   i70    the bore only                 5w      a 5 wall: the bore follows
#   0i           solid again
#   +20   -10    relative to the live value in that slot
#   2.4m  60cm   units; bare numbers are mm, as everywhere in this plugin
#
#   While a run is being drawn a BARE number is the length of the leg on the
#   cursor instead, as it is for the Line tool, and two forms place a point:
#   [x,y,z]      the next point at that model position, mm
#   <dx,dy,dz>   the next point that far from the last one, mm
#
# THE WALL IS WHAT IS KEPT:
#   A new diameter typed without a bore keeps the pipe's WALL, the way a
#   pipe of one material and schedule comes in many sizes: 80/70 typed to 100
#   becomes 100/90. The remembered bore for new pipes is stored as a wall for
#   the same reason, so it can never be left wider than the next pipe.
#
# FORGIVING, NOT SILENT:
#   A spec that cannot be built is refused with the entry that would work
#   named in the message — a bend tighter than the pipe, a bore wider than
#   it, a pipe too thin for its number of sides. Nothing is quietly clamped.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__InsertPrimatives__DrawnVcbArithmetic__'
require_relative '../02__AppData/Na__InsertPrimatives__AppData__DrawnSettings__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Spec Constants
    # -----------------------------------------------------------------------------

    NA_DRAWN_PIPE_DIAMETER_KEY        = 'PipeDiameterMm'
    NA_DRAWN_PIPE_BEND_KEY            = 'PipeBendRadiusMm'
    NA_DRAWN_PIPE_WALL_KEY            = 'PipeWallMm'
    NA_DRAWN_PIPE_DEFAULT_DIAMETER_MM = 80.0                                  # <-- Adam's own example: 80,110,24s
    NA_DRAWN_PIPE_DEFAULT_BEND_MM     = 110.0
    NA_DRAWN_PIPE_DEFAULT_WALL_MM     = 5.0                                   # <-- An 80 pipe with a 70 bore
    NA_DRAWN_PIPE_MIN_CHORD_MM        = 0.1                                   # <-- SketchUp merges points closer than ~0.03mm
    NA_DRAWN_PIPE_MIN_WALL_MM         = 0.1
    NA_DRAWN_PIPE_BORE_OPTION         = 'pipe_internal_diameter'.freeze       # <-- Declared in ToolOptions under :drawn_pipe
    NA_DRAWN_PIPE_SLOTS               = [:diameter, :bend, :sides, :inner].freeze

    # A token that names its own slot: a d, r, i or w before or after the
    # number. "80d", "d80", "110r", "r+20", "70i", "5w", "2.4md" all read;
    # "mm", "cm" and "m" are still units because the letter has to be one of
    # the four.
    NA_DRAWN_PIPE_KIND_PATTERN  = /\A([driw])?\s*([+-]?\s*\d+(?:\.\d+)?\s*(?:mm|cm|m)?)\s*([driw])?\z/i

    # Sides, with an optional sign so "+8s" adds eight facets.
    NA_DRAWN_PIPE_SIDES_PATTERN = /\A([+-])?\s*(\d+)\s*(?:segments|segs|seg|sides|side|s)\z/i

    NA_DRAWN_PIPE_SLOT_LETTERS  = { 'd' => :diameter, 'r' => :bend, 'i' => :inner, 'w' => :wall }.freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Remembered Spec
    # -----------------------------------------------------------------------------

    # FUNCTION | The Spec the Next Pipe Is Built With
    # Lengths in internal inches. Held in memory once read: the preview asks on
    # every mouse move, and Sketchup.read_default is a native call.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__CurrentSpec
        if @na_drawn_pipe_diameter_mm.nil?
            stored = Sketchup.read_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_PIPE_DIAMETER_KEY, NA_DRAWN_PIPE_DEFAULT_DIAMETER_MM).to_f
            @na_drawn_pipe_diameter_mm = stored > 0.0 ? stored : NA_DRAWN_PIPE_DEFAULT_DIAMETER_MM
        end

        if @na_drawn_pipe_bend_mm.nil?
            stored = Sketchup.read_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_PIPE_BEND_KEY, NA_DRAWN_PIPE_DEFAULT_BEND_MM).to_f
            @na_drawn_pipe_bend_mm = stored >= 0.0 ? stored : NA_DRAWN_PIPE_DEFAULT_BEND_MM
        end

        diameter = @na_drawn_pipe_diameter_mm / NA_DRAWN_INCH_TO_MM
        inner    = 0.0

        if Na__InsertPrimatives.Na__DrawnPipe__BoreOption?
            inner = diameter - 2.0 * Na__InsertPrimatives.Na__DrawnPipe__RememberedWallMm / NA_DRAWN_INCH_TO_MM
            inner = 0.0 unless inner > 0.0
        end

        {
            :diameter => diameter,
            :bend     => @na_drawn_pipe_bend_mm / NA_DRAWN_INCH_TO_MM,
            :sides    => Na__InsertPrimatives.Na__DrawnSettings__CircleSegments,
            :inner    => inner
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Wall New Hollow Pipes Are Built With, in mm
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__RememberedWallMm
        if @na_drawn_pipe_wall_mm.nil?
            stored = Sketchup.read_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_PIPE_WALL_KEY, NA_DRAWN_PIPE_DEFAULT_WALL_MM).to_f
            @na_drawn_pipe_wall_mm = stored > 0.0 ? stored : NA_DRAWN_PIPE_DEFAULT_WALL_MM
        end

        @na_drawn_pipe_wall_mm
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is the Internal Diameter Option On (New Pipes Are Hollow)?
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__BoreOption?
        return false unless Na__InsertPrimatives.respond_to?(:Na__ToolOptions__Enabled?)

        Na__InsertPrimatives.Na__ToolOptions__Enabled?(NA_DRAWN_PIPE_BORE_OPTION)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Remember a Spec for the Next Pipe and the Next Session
    # ------------------------------------------------------------
    # `named` is what the entry actually said. A bore typed (or a wall) is a
    # request for hollow pipe, so it switches the Internal Diameter option on;
    # 0i switches it off. Returns true when it changed that option, so the
    # caller can bring a standing popup button up to date.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__StoreSpec(spec, named = nil)
        @na_drawn_pipe_diameter_mm = spec[:diameter].to_f * NA_DRAWN_INCH_TO_MM
        @na_drawn_pipe_bend_mm     = spec[:bend].to_f * NA_DRAWN_INCH_TO_MM

        Sketchup.write_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_PIPE_DIAMETER_KEY, @na_drawn_pipe_diameter_mm)
        Sketchup.write_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_PIPE_BEND_KEY, @na_drawn_pipe_bend_mm)
        Na__InsertPrimatives.Na__DrawnSettings__SetCircleSegments(spec[:sides])

        inner = spec[:inner].to_f
        Na__InsertPrimatives.Na__DrawnPipe__RememberWall((spec[:diameter].to_f - inner) * 0.5) if inner > 0.0

        return false unless named && named.include?(:inner)
        return false unless Na__InsertPrimatives.respond_to?(:Na__ToolOptions__Set)

        wanted = inner > 0.0
        return false if Na__InsertPrimatives.Na__DrawnPipe__BoreOption? == wanted

        Na__InsertPrimatives.Na__ToolOptions__Set(NA_DRAWN_PIPE_BORE_OPTION, wanted)
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Remember a Wall (Internal Inches) for New Hollow Pipes
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__RememberWall(wall)
        millimetres = wall.to_f * NA_DRAWN_INCH_TO_MM
        return unless millimetres > 0.0

        @na_drawn_pipe_wall_mm = millimetres
        Sketchup.write_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_PIPE_WALL_KEY, millimetres)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Display
    # -----------------------------------------------------------------------------

    # FUNCTION | Format Internal Inches as Millimetres, Decimals Only When Needed
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__FormatMm(value)
        millimetres = (value.to_f * NA_DRAWN_INCH_TO_MM).round(1)
        millimetres == millimetres.round ? millimetres.round.to_s : millimetres.to_s
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Spec in Words, for the Status Line and the Summary Card
    # A hollow pipe reads Ø80/70: outside over bore, the way it is written on
    # a drawing.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__SpecLabel(spec)
        bend = spec[:bend].to_f > 0.0 ? "R#{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(spec[:bend])}" : 'mitred'
        bore = spec[:inner].to_f > 0.0 ? "/#{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(spec[:inner])}" : ''

        "Ø#{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(spec[:diameter])}#{bore} · #{bend} · #{spec[:sides]} sides"
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Spec as the Measurements Box Would Take It Back
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__SpecEntry(spec)
        entry = "#{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(spec[:diameter])}," \
                "#{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(spec[:bend])},#{spec[:sides]}s"
        spec[:inner].to_f > 0.0 ? "#{entry},#{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(spec[:inner])}" : entry
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Validation
    # -----------------------------------------------------------------------------

    # FUNCTION | Refuse a Spec That Cannot Be Built, Naming One That Can
    # ------------------------------------------------------------
    # A bend is a slice of a torus: its inner wall sits bend radius minus pipe
    # radius from the bend's centre, so a bend radius at or below the pipe's
    # own radius turns the inside of the bend inside out. 0 is not refused —
    # it is the way to ask for mitred elbows. A bore must leave a wall.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__ValidateSpec(spec)
        diameter = spec[:diameter].to_f
        bend     = spec[:bend].to_f
        sides    = spec[:sides].to_i
        inner    = spec[:inner].to_f
        dia_txt  = Na__InsertPrimatives.Na__DrawnPipe__FormatMm(diameter)

        raise ArgumentError, 'the diameter must be more than 0' unless diameter > NA_DRAWN_MIN_DIMENSION.to_f
        raise ArgumentError, 'the bend radius cannot be negative — type 0r for mitred elbows' if bend < 0.0
        raise ArgumentError, 'the bore cannot be negative — type 0i for a solid pipe' if inner < 0.0

        if sides < NA_DRAWN_MIN_SEGMENTS || sides > NA_DRAWN_MAX_SEGMENTS
            raise ArgumentError, "a pipe takes #{NA_DRAWN_MIN_SEGMENTS} to #{NA_DRAWN_MAX_SEGMENTS} sides — try 24s"
        end

        if bend > 0.0 && bend <= diameter * 0.5
            radius_txt = Na__InsertPrimatives.Na__DrawnPipe__FormatMm(diameter * 0.5)
            raise ArgumentError,
                  "a #{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(bend)} bend is tighter than the pipe itself " \
                  "(radius #{radius_txt}) — type #{dia_txt},0 for mitred elbows, or a bend radius over #{radius_txt}"
        end

        if inner > 0.0 && (diameter - inner) * 0.5 * NA_DRAWN_INCH_TO_MM < NA_DRAWN_PIPE_MIN_WALL_MM
            widest = Na__InsertPrimatives.Na__DrawnPipe__FormatMm(diameter - 2.0 * NA_DRAWN_PIPE_DEFAULT_WALL_MM / NA_DRAWN_INCH_TO_MM)
            hint   = (diameter * NA_DRAWN_INCH_TO_MM) > 2.0 * NA_DRAWN_PIPE_DEFAULT_WALL_MM ? "try #{widest}i, or 0i for solid" : 'type 0i for solid'
            raise ArgumentError, "a #{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(inner)} bore leaves no wall in a #{dia_txt} pipe — #{hint}"
        end

        narrowest = inner > 0.0 ? inner : diameter
        chord_mm  = Math::PI * narrowest * NA_DRAWN_INCH_TO_MM / sides
        if chord_mm < NA_DRAWN_PIPE_MIN_CHORD_MM
            most = (Math::PI * narrowest * NA_DRAWN_INCH_TO_MM / NA_DRAWN_PIPE_MIN_CHORD_MM).floor
            what = inner > 0.0 ? "a #{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(inner)} bore" : "a #{dia_txt} pipe"
            raise ArgumentError, "#{what} is too thin for #{sides} sides — SketchUp would merge them; try #{[most, NA_DRAWN_MIN_SEGMENTS].max}s"
        end

        spec
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Measurements Box Entry
    # -----------------------------------------------------------------------------

    # FUNCTION | Read a Measurements-Box Entry
    # ------------------------------------------------------------
    # `current` is the spec the entry is read against: the next pipe's, or a
    # selected pipe's own, so "+20" and a kept wall mean that pipe's. `bare`
    # says what a lone, unmarked number means where the entry was typed:
    # :length while a run is being drawn, :diameter everywhere else.
    # Returns one of
    #   { :kind => :spec,   :spec => {...}, :named => [:diameter, ...] }
    #   { :kind => :length, :token => [sign, inches] }
    #   { :kind => :point,  :mode => :absolute | :relative, :vector => [x, y, z] }
    # Raises ArgumentError, with what to type instead, when it cannot be read.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__ParseEntry(text, current, bare = :diameter)
        entry = text.to_s.strip
        raise ArgumentError, 'no value entered' if entry.empty?

        absolute = /\A\[(.*)\]\z/.match(entry)
        return { :kind => :point, :mode => :absolute, :vector => Na__InsertPrimatives.Na__DrawnPipe__ParseTriple(absolute[1]) } if absolute

        relative = /\A<(.*)>\z/.match(entry)
        return { :kind => :point, :mode => :relative, :vector => Na__InsertPrimatives.Na__DrawnPipe__ParseTriple(relative[1]) } if relative

        parts = entry.split(',', -1)
        raise ArgumentError, 'a pipe takes up to four values: diameter, bend radius, sides, bore (80,110,24s,70)' if parts.length > 4

        if parts.length == 1 && bare == :length && NA_DRAWN_VCB_TOKEN_PATTERN.match(parts[0].strip)
            return { :kind => :length, :token => Na__InsertPrimatives.Na__DrawnVcb__ParseToken(parts[0]) }
        end

        base  = { :inner => 0.0 }.merge(current)
        spec  = base.dup
        named = []
        wall  = nil

        parts.each_with_index do |part, index|
            slot, value = Na__InsertPrimatives.Na__DrawnPipe__ReadToken(part, NA_DRAWN_PIPE_SLOTS[index], spec)
            next unless slot

            if slot == :wall
                wall = value
                next
            end

            spec[slot] = value
            named << slot
        end

        if wall
            spec[:inner] = spec[:diameter].to_f - 2.0 * wall.to_f
            raise ArgumentError, "a #{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(wall)} wall fills a #{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(spec[:diameter])} pipe — type a thinner wall, or 0i for solid" unless spec[:inner] > 0.0
            named << :inner
        elsif named.include?(:diameter) && !named.include?(:inner) && base[:inner].to_f > 0.0
            # A new size keeps the pipe's wall.
            kept = base[:diameter].to_f - base[:inner].to_f
            spec[:inner] = spec[:diameter].to_f - kept

            unless spec[:inner] > 0.0
                raise ArgumentError,
                      "a #{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(spec[:diameter])} pipe cannot keep its " \
                      "#{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(kept * 0.5)} wall — type a bore with it (,,,20) or 0i for solid"
            end
        end

        raise ArgumentError, 'nothing to change — type a diameter, a bend radius, sides or a bore (80,110,24s,70)' if named.empty?

        Na__InsertPrimatives.Na__DrawnPipe__ValidateSpec(spec)
        { :kind => :spec, :spec => spec, :named => named.uniq }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Read One Comma-Separated Token Against the Slot It Sits In
    # Returns [slot, value] or [nil, nil] for an empty token. A d, r, i, w or
    # s on the token names its slot outright; otherwise the position does.
    # :wall is returned as a slot of its own; the caller turns it into a bore.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__ReadToken(part, positional_slot, live)
        text = part.to_s.strip
        return [nil, nil] if text.empty?

        sides = NA_DRAWN_PIPE_SIDES_PATTERN.match(text)
        if sides
            count = sides[2].to_i
            count = live[:sides].to_i + count if sides[1] == '+'
            count = live[:sides].to_i - count if sides[1] == '-'
            return [:sides, count]
        end

        marked = NA_DRAWN_PIPE_KIND_PATTERN.match(text)
        raise ArgumentError, "cannot read '#{text}' — type 80,110,24s,70, or 80d, 110r, 24s, 70i on their own" unless marked
        raise ArgumentError, "'#{text}' names two slots — use one letter" if marked[1] && marked[3]

        letter = (marked[1] || marked[3]).to_s.downcase
        slot   = NA_DRAWN_PIPE_SLOT_LETTERS[letter] || positional_slot

        if slot == :sides
            whole = /\A\d+\z/.match(marked[2].strip)
            raise ArgumentError, "the third value is the number of sides — type it as 24 or 24s, not '#{text}'" unless whole
            return [:sides, marked[2].strip.to_i]
        end

        token = Na__InsertPrimatives.Na__DrawnVcb__ParseToken(marked[2])
        live_value = slot == :wall ? (live[:diameter].to_f - live[:inner].to_f) * 0.5 : live[slot]
        [slot, Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(token, live_value)]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Read "x,y,z" Inside [ ] or < > as Three Signed Lengths in Inches
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__ParseTriple(body)
        parts = body.to_s.split(',', -1)
        raise ArgumentError, 'a point takes three values: [x,y,z] or <dx,dy,dz>' unless parts.length == 3

        parts.map do |part|
            text = part.strip
            next 0.0 if text.empty?

            token = Na__InsertPrimatives.Na__DrawnVcb__ParseToken(text)
            token[0] == :minus ? -token[1] : token[1]
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Make a Bare Number Name a Slot ("100" Becomes "100d")
    # ------------------------------------------------------------
    # For the bar's click-then-type: a plain value typed while a slot is armed
    # goes to that slot. Anything already marked, or with commas, is left as
    # it was typed.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__MarkForSlot(text, slot)
        entry = text.to_s.strip
        return entry unless slot && NA_DRAWN_VCB_TOKEN_PATTERN.match(entry)

        case slot
        when :diameter then "#{entry}d"
        when :bend     then "#{entry}r"
        when :inner    then "#{entry}i"
        when :sides    then /\A[+-]?\d+\z/.match(entry) ? "#{entry}s" : entry
        else                entry
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PIPE SPEC
# =============================================================================
