# =============================================================================
# NA INSERT PRIMATIVES - DEEP SCALE MODES
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnScale__Mode__.rb
# NAMESPACE  : Na__InsertPrimatives, Na__InsertPrimatives::DrawnScaleMode
# AUTHOR     : Noble Architecture
# PURPOSE    : Which thing a grip or a typed size is about to do to the object,
#              and the words and colours that say so before it happens
# CREATED    : 2026
#
# DESCRIPTION:
# - A grip can do four quite different things, one key apart, and until 5.2.21
#   they all looked the same in amber:
#     :uniform   every axis by one factor: the object keeps its proportions
#     :scale     NON-UNIFORM: some axes and not others, so everything inside is
#                squashed, circles to ovals, frames to odd thicknesses
#     :stretch   every axis changing has planes and comes apart at them: the
#                details keep their size
#     :mixed     a stretch on one axis and a scale on another
# - The mistake this is here to stop is reaching for a stretch and getting a
#   non-uniform scale. Since 5.2.22 SHIFT+TAB gives every axis a centre plane, so
#   switching Planes on is enough and every grip stretches. What is left of it:
#     Planes saved on the object, but the switch off. Every axis scales.
#     Planes on, but an axis too thin to hold one. That axis scales (the rule in
#     the Field file: an axis with planes stretches, one without scales). Only
#     a part scaled up a long way from next to nothing, and also the one way
#     left to get a stretch and a scale at once.
#   Either way the title says NOT A STRETCH and the line under it says why.
#
# ONE ANSWER, FROM THE SAME RULES AS THE COMMIT:
# - A grip is named from the two questions na_scale__update_drag and
#   Na__ScaleField__Build ask of it: which axes does it pull, and which of those
#   have planes? Its name is therefore known before it is touched, and holds
#   steady through a drag rather than changing for the frame in which two free
#   axes happen to match.
# - A typed size has no grip, so it is read from the field Enter will commit.
#
# CHOOSING ONE (5.2.23):
# - The strip's three pills are clicked as well as read:
#     UNIFORM      every grip scales uniform, face and edge grips too
#     NON-UNIFORM  every grip scales on its own axes, corner grips too
#     STRETCH      Stretch Planes, exactly as SHIFT+TAB switches it
# - Until one is chosen the grips go by their kind, as SketchUp's do: corners
#   uniform, faces and edges non-uniform. Clicking the lit one goes back to that.
# - SHIFT still swaps a single pull, so it is the exception under any of them.
# - The first two are one stored option (scale_grip_mode), which only asks a
#   question when Stretch Planes is off. So they switch Planes off when clicked,
#   SHIFT+TAB can go to a stretch and back to the mode it left, and nothing below
#   the one question na_scale__uniform? asks has to know: a mode here reaches
#   the model by the same uniform and free pulls SHIFT has always made.
# - A typed size follows too: under UNIFORM one size scales everything.
#
# WHERE IT SHOWS (the drawing is in the Preview file):
# - Every grip wears the colour of what it would do, so the answer is there
#   before the mouse gets to it, and SHIFT or SHIFT+TAB recolours them all.
# - The mode strip under the bar lights the mode in force, at a place that does
#   not move, with a sentence saying what it means for this object.
# - A card beside the grip names it where the eye already is.
# - The new box, the ghost and the live dimensions wear it through the drag.
#
# HOST CONTRACT (DrawnScaleTool):
#   @na_sc_frame, @na_sc_planes, @na_sc_drag, @na_sc_hover, @na_sc_focus,
#   @na_sc_active_dim, @na_shift_held
#   na_scale__uniform?, na_scale__planes_on?, na_scale__typed_state,
#   na_scale__ctrl_offer?, na_scale__after_option_changed, na_scale__say
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | The Modes in Words
    # -----------------------------------------------------------------------------

    NA_SCALE_MODE_WORDS = {
        :uniform => 'uniform',
        :scale   => 'non-uniform',
        :stretch => 'stretch at planes',
        :mixed   => 'stretch + scale'
    }.freeze

    NA_SCALE_MODE_VERBS = {
        :uniform => 'Scaled uniform',
        :scale   => 'Scaled non-uniform',
        :stretch => 'Stretched',
        :mixed   => 'Stretched and scaled'
    }.freeze

    # The strip's three pills, left to right. A mixed pull lights two of them,
    # which is the plainest way of saying it is doing both.
    NA_SCALE_MODE_PILLS = [
        [:uniform, 'UNIFORM'],
        [:scale,   'NON-UNIFORM'],
        [:stretch, 'STRETCH']
    ].freeze

    NA_SCALE_MODE_LIT = {
        :uniform => [:uniform],
        :scale   => [:scale],
        :stretch => [:stretch],
        :mixed   => [:scale, :stretch]
    }.freeze

    # The two pills that are a stored choice, and the value each stores.
    # Stretch is the Stretch Planes switch, which has its own option.
    NA_SCALE_GRIP_MODE_VALUES = {
        :uniform => 'uniform',
        :scale   => 'non_uniform'
    }.freeze

    NA_SCALE_GRIP_MODE_BY_GRIP = 'by_grip'.freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Naming a Change
    # -----------------------------------------------------------------------------

    # FUNCTION | Name a Set of Axis Rules
    # ------------------------------------------------------------
    # rules    { axis => :scale | :stretch }, only the axes changing
    # uniform  they are changing together, by one factor
    #
    # An object with one axis to its name cannot be distorted, so scaling it
    # is uniform whichever grip does it. nil when nothing is changing.
    # ------------------------------------------------------------
    def self.Na__ScaleMode__Classify(frame, rules, uniform)
        stretching = rules.values.include?(:stretch)
        scaling    = rules.values.include?(:scale)

        return nil unless stretching || scaling
        return scaling ? :mixed : :stretch if stretching

        uniform || frame[:usable].count(true) == 1 ? :uniform : :scale
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Rule Each Changing Axis of a Field Is Under
    # ------------------------------------------------------------
    def self.Na__ScaleMode__FieldRules(field)
        rules = {}

        NA_SCALE_AXES.each do |axis|
            rule = field[axis] ? field[axis][:mode] : nil
            rules[axis] = rule if rule == :scale || rule == :stretch
        end

        rules
    end
    # ---------------------------------------------------------------

    # FUNCTION | The One Factor Every Axis of a Field Changes By, or nil
    # ------------------------------------------------------------
    def self.Na__ScaleMode__EvenFactor(field, frame)
        factors = []

        NA_SCALE_AXES.each_with_index do |axis, n|
            next unless frame[:usable][n]

            factor = field[axis] ? field[axis][:factor] : nil
            return nil unless factor

            factors << factor.to_f
        end

        return nil if factors.empty? || factors.max - factors.min > 1e-6

        factors.first
    end
    # ---------------------------------------------------------------

    # FUNCTION | Name a Field: What a Commit of It Will Do
    # ------------------------------------------------------------
    def self.Na__ScaleMode__OfField(field, frame)
        Na__InsertPrimatives.Na__ScaleMode__Classify(
            frame,
            Na__InsertPrimatives.Na__ScaleMode__FieldRules(field),
            !Na__InsertPrimatives.Na__ScaleMode__EvenFactor(field, frame).nil?
        )
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # =============================================================================
    # MODULE | Deep Scale Modes
    # =============================================================================

    module DrawnScaleMode

        # -----------------------------------------------------------------------------
        # REGION | What the Grips Would Do
        # -----------------------------------------------------------------------------

        # FUNCTION | The Axes With Planes in Force: { axis => how many }
        # ------------------------------------------------------------
        # Empty with Stretch Planes off, however many are saved on the object:
        # planes that are switched off stretch nothing.
        # ------------------------------------------------------------
        def na_scale__stretching_axes
            frame = @na_sc_frame
            found = {}
            return found unless frame && na_scale__planes_on?

            NA_SCALE_AXES.each do |axis|
                count = na_scale__saved_planes(axis)
                found[axis] = count if count > 0
            end

            found
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Many Planes Are Saved Inside One Axis, Switched On or Not
        # ------------------------------------------------------------
        def na_scale__saved_planes(axis)
            Na__InsertPrimatives.Na__ScalePlanes__Inside(@na_sc_frame, axis, (@na_sc_planes || {})[axis]).length
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Axes the Object Has
        # ------------------------------------------------------------
        def na_scale__usable_axes
            NA_SCALE_AXES.select { |axis| @na_sc_frame[:usable][NA_SCALE_AXIS_INDEX[axis]] }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Rule Each Axis Would Be Under if This Grip Were Pulled
        # ------------------------------------------------------------
        # Which axes it reaches is na_scale__update_drag's answer: all of them
        # for a uniform pull, its own for a free one.
        # ------------------------------------------------------------
        def na_scale__grip_rules(grip, uniform, stretching)
            axes = uniform ? na_scale__usable_axes : grip[:axes]

            axes.each_with_object({}) do |axis, rules|
                rules[axis] = stretching.key?(axis) ? :stretch : :scale
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | What This Grip Would Do Right Now
        # ------------------------------------------------------------
        def na_scale__grip_mode(grip, stretching = na_scale__stretching_axes)
            uniform = na_scale__uniform?(grip)

            Na__InsertPrimatives.Na__ScaleMode__Classify(
                @na_sc_frame, na_scale__grip_rules(grip, uniform, stretching), uniform
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | What SHIFT Would Turn a Pull Into, in a Few Words; nil if Nothing
        # ------------------------------------------------------------
        # Often a different mode. On a grip SHIFT cannot change the mode of (a
        # stretch on all three axes, say) it still changes how the axes move.
        # ------------------------------------------------------------
        def na_scale__shift_words(grip, uniform)
            frame = @na_sc_frame
            return nil if frame[:usable].count(true) == 1

            stretching = na_scale__stretching_axes
            now        = Na__InsertPrimatives.Na__ScaleMode__Classify(frame, na_scale__grip_rules(grip, uniform, stretching), uniform)
            flipped    = Na__InsertPrimatives.Na__ScaleMode__Classify(frame, na_scale__grip_rules(grip, !uniform, stretching), !uniform)
            return NA_SCALE_MODE_WORDS[flipped] unless now == flipped

            uniform ? 'each axis on its own' : 'all axes together'
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Line on a Card That Says What SHIFT Would Do; nil if Nothing
        # ------------------------------------------------------------
        def na_scale__shift_line(grip, uniform)
            words = na_scale__shift_words(grip, uniform)
            return nil unless words

            "#{@na_shift_held ? 'let go of SHIFT' : 'SHIFT'}: #{words}"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Choosing a Mode on the Strip
        # -----------------------------------------------------------------------------

        # FUNCTION | The Mode the Grips Were Told to Take: :uniform, :scale or nil
        # ------------------------------------------------------------
        # nil while they go by their kind, and while Stretch Planes is on: it
        # is kept through a stretch, but is not what a grip does then.
        # ------------------------------------------------------------
        def na_scale__grip_choice
            return nil if na_scale__planes_on?

            stored = Na__InsertPrimatives.Na__ToolOptions__Value(NA_SCALE_OPTION_GRIP_MODE).to_s
            NA_SCALE_GRIP_MODE_VALUES.key(stored)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Pill Under the Cursor, or nil
        # ------------------------------------------------------------
        # Reaches across the gaps and the panel around the pills: the strip
        # stands over the model, and a click just off a pill should not take
        # the object behind it.
        # ------------------------------------------------------------
        def na_scale__pill_at(view, x, y)
            pills = NA_SCALE_MODE_PILLS.map { |mode, text| { :mode => mode, :text => text } }

            Na__InsertPrimatives.Na__ScalePreview__ModeStripLayout(view, pills).find do |pill|
                rect = pill[:rect]
                Na__InsertPrimatives.Na__ScalePreview__InRect?([rect[0] - 2, rect[1] - 4, rect[2] + 2, rect[3] + 4], x, y)
            end
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Pill Was Clicked
        # ------------------------------------------------------------
        def na_scale__pill_click(_view, pill)
            return na_scale__hotkey(:planes) if pill[:mode] == :stretch

            na_scale__choose_grip_mode(NA_SCALE_GRIP_MODE_VALUES[pill[:mode]])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Choose UNIFORM or NON-UNIFORM, or Let Go of the One in Force
        # ------------------------------------------------------------
        # A pill lit only because Stretch Planes hid it is not the one in force,
        # so clicking it takes it up rather than letting go of it.
        # ------------------------------------------------------------
        def na_scale__choose_grip_mode(value)
            planes  = na_scale__planes_on?
            current = Na__InsertPrimatives.Na__ToolOptions__Value(NA_SCALE_OPTION_GRIP_MODE).to_s
            stored  = !planes && current == value ? NA_SCALE_GRIP_MODE_BY_GRIP : value

            Na__InsertPrimatives.Na__ToolOptions__SetValue(NA_SCALE_OPTION_GRIP_MODE, stored)
            Na__InsertPrimatives.Na__RightClickPopup__RefreshOption(NA_SCALE_OPTION_GRIP_MODE)
            na_scale__planes_give_way
            na_scale__after_option_changed(NA_SCALE_OPTION_GRIP_MODE)

            na_scale__say(Na__InsertPrimatives.Na__ToolOptions__CaptionFor(NA_SCALE_OPTION_GRIP_MODE))
            na_drawn__update_status_text
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch Stretch Planes Off for a Mode That Has Just Been Chosen
        # ------------------------------------------------------------
        def na_scale__planes_give_way
            return false unless na_scale__planes_on?

            Na__InsertPrimatives.Na__ToolOptions__SetValue(NA_SCALE_OPTION_PLANES, false)
            Na__InsertPrimatives.Na__RightClickPopup__RefreshOption(NA_SCALE_OPTION_PLANES)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Make a Typed Size Do What the Mode Clicked Says: [factors, sides]
        # ------------------------------------------------------------
        # Under UNIFORM one size sets the factor and every axis follows it, each
        # holding the end it would have held on its own. Two sizes cannot both
        # be met by one factor, so that is refused with the way out named.
        # ------------------------------------------------------------
        def na_scale__typed_as_chosen(factors, sides)
            return [factors, sides] unless na_scale__grip_choice == :uniform
            raise ArgumentError, 'UNIFORM takes one size: click NON-UNIFORM to set the axes apart' if factors.length > 1

            factor = factors.values.first
            axes   = na_scale__usable_axes

            [
                axes.each_with_object({}) { |axis, found| found[axis] = factor },
                axes.each_with_object({}) { |axis, found| found[axis] = na_scale__typed_side(axis) }
            ]
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Sentence Under the Strip With a Mode Chosen and Nothing in Focus
        # ------------------------------------------------------------
        def na_scale__choice_sentence(choice)
            return 'Every grip scales uniform, keeping its proportions. SHIFT frees a pull, SHIFT+TAB stretches instead' if choice == :uniform

            'Every grip scales on its own axes, and what is inside distorts. SHIFT makes a pull uniform, SHIFT+TAB stretches instead'
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Clicking a Pill Would Do
        # ------------------------------------------------------------
        def na_scale__pill_tip(mode)
            if mode == :stretch
                return 'Click, or SHIFT+TAB: back to scaling' if na_scale__planes_on?

                return 'Click, or SHIFT+TAB: every grip stretches, at a plane through the centre of each axis until you place your own'
            end

            return 'Click to let go: corners scale uniform, faces and edges non-uniform, as SketchUp does it' if na_scale__grip_choice == mode
            return 'Click: every grip scales uniform, keeping its proportions. SHIFT frees a pull' if mode == :uniform

            'Click: every grip scales on its own axes, and what is inside distorts. SHIFT makes a pull uniform'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | What Is in Focus Right Now
        # -----------------------------------------------------------------------------

        # FUNCTION | A Grip Described: Its Mode, Its Rules, the Planes It Would Use
        # ------------------------------------------------------------
        def na_scale__grip_focus(grip, uniform)
            stretching = na_scale__stretching_axes
            rules      = na_scale__grip_rules(grip, uniform, stretching)

            {
                :kind   => @na_sc_drag ? :drag : :grip,
                :mode   => Na__InsertPrimatives.Na__ScaleMode__Classify(@na_sc_frame, rules, uniform),
                :rules  => rules,
                :planes => stretching
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Typed Size Described, From the Field Enter Will Commit
        # ------------------------------------------------------------
        def na_scale__field_focus(field)
            frame  = @na_sc_frame
            rules  = Na__InsertPrimatives.Na__ScaleMode__FieldRules(field)
            factor = Na__InsertPrimatives.Na__ScaleMode__EvenFactor(field, frame)
            planes = {}
            rules.each { |axis, rule| planes[axis] = field[axis][:planes].length if rule == :stretch }

            {
                :kind   => :typed,
                :mode   => Na__InsertPrimatives.Na__ScaleMode__Classify(frame, rules, !factor.nil?),
                :rules  => rules,
                :planes => planes,
                :factor => factor
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | What a Size Typed for One Axis Would Do
        # ------------------------------------------------------------
        # Under UNIFORM it takes every axis with it (na_scale__typed_as_chosen).
        # ------------------------------------------------------------
        def na_scale__axis_focus(axis)
            stretching = na_scale__stretching_axes
            uniform    = na_scale__grip_choice == :uniform
            axes       = uniform ? na_scale__usable_axes : [axis]
            rules      = axes.each_with_object({}) { |each, found| found[each] = stretching.key?(each) ? :stretch : :scale }

            {
                :kind   => :dim,
                :mode   => Na__InsertPrimatives.Na__ScaleMode__Classify(@na_sc_frame, rules, uniform),
                :rules  => rules,
                :planes => stretching
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Change the Tool Is About to Make, or nil at Rest
        # ------------------------------------------------------------
        # In the order the draw pass gives them: an entry that already reads as
        # a size outranks the mouse, then a grip in hand, a grip under the
        # cursor, and a dimension under the cursor or taking the typing.
        # ------------------------------------------------------------
        def na_scale__mode_focus
            return nil unless @na_sc_frame

            typed = na_scale__typed_state
            return na_scale__field_focus(typed[:field]) if typed && typed[:field]

            drag = @na_sc_drag

            if drag
                uniform = drag[:field] ? drag[:uniform] : na_scale__uniform?(drag[:grip])
                focus   = na_scale__grip_focus(drag[:grip], uniform)
                focus[:factor] = drag[:factors].values.first.to_f if uniform && drag[:field] && !drag[:factors].empty?
                return focus
            end

            hover = @na_sc_hover
            return na_scale__grip_focus(hover[:grip], na_scale__uniform?(hover[:grip])) if hover && hover[:kind] == :grip

            axis   = hover[:axis] if hover && hover[:kind] == :dim
            axis ||= @na_sc_active_dim if @na_sc_focus == :dimension
            axis ? na_scale__axis_focus(axis) : nil
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Words
        # -----------------------------------------------------------------------------

        # FUNCTION | The Axes of a Focus Under One Rule
        # ------------------------------------------------------------
        def na_scale__axes_where(focus, rule)
            NA_SCALE_AXES.select { |axis| focus[:rules][axis] == rule }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Axes Named for a Sentence: "X" or "X + Z"
        # ------------------------------------------------------------
        def na_scale__axis_words(axes)
            axes.map { |axis| axis.to_s.upcase }.join(' + ')
        end
        # ---------------------------------------------------------------

        # FUNCTION | "1 plane" or "3 planes"
        # ------------------------------------------------------------
        def na_scale__planes_words(count)
            "#{count} plane#{count == 1 ? '' : 's'}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Many Planes the Stretching Axes of a Focus Have Between Them
        # ------------------------------------------------------------
        def na_scale__focus_plane_count(focus)
            na_scale__axes_where(focus, :stretch).inject(0) { |sum, axis| sum + focus[:planes][axis].to_i }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Did the User Set This Up to Stretch, and Is It About to Scale?
        # ------------------------------------------------------------
        # Planes switched on say so, and so do planes saved on the very axes
        # being pulled. Those are the two ways of getting the wrong one. Not
        # with NON-UNIFORM clicked: that is someone asking for a scale.
        # ------------------------------------------------------------
        def na_scale__wanted_stretch?(focus)
            return false unless focus[:mode] == :scale
            return true if na_scale__planes_on?
            return false if na_scale__grip_choice == :scale

            na_scale__axes_where(focus, :scale).any? { |axis| na_scale__saved_planes(axis) > 0 }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Title on the Card, and the Mode in the Status Line
        # ------------------------------------------------------------
        def na_scale__mode_title(focus)
            stretch = na_scale__axis_words(na_scale__axes_where(focus, :stretch))
            scale   = na_scale__axis_words(na_scale__axes_where(focus, :scale))

            case focus[:mode]
            when :uniform
                focus[:factor] ? "UNIFORM SCALE  #{format('%.3f', focus[:factor])}x" : 'UNIFORM SCALE'
            when :stretch
                "STRETCH AT #{na_scale__planes_words(na_scale__focus_plane_count(focus)).upcase}  #{stretch}"
            when :mixed
                "STRETCH #{stretch} + SCALE #{scale}"
            else
                title = "NON-UNIFORM SCALE  #{scale}"
                na_scale__wanted_stretch?(focus) ? "#{title}  —  NOT A STRETCH" : title
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Word on the Measurements Box's Label
        # ------------------------------------------------------------
        # Typing is the other way to make a change, and this label is where
        # the eye is when it happens.
        # ------------------------------------------------------------
        def na_scale__vcb_verb(focus)
            case focus ? focus[:mode] : nil
            when :uniform then 'Uniform'
            when :stretch then 'Stretch'
            when :mixed   then 'Stretch + Scale'
            else               'Scale'
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Would Make This Scale a Stretch
        # ------------------------------------------------------------
        # SHIFT+TAB, mid-drag as much as at rest. With Planes already on the
        # only scale left is an axis too thin to hold a plane, which nothing
        # can make a stretch, so that is what it says.
        # ------------------------------------------------------------
        def na_scale__stretch_advice(focus)
            axes = na_scale__axes_where(focus, :scale)

            if na_scale__planes_on?
                one = axes.length == 1
                return "#{na_scale__axis_words(axes)} #{one ? 'is' : 'are'} too thin to hold a plane, so #{one ? 'it scales' : 'they scale'}"
            end

            saved = axes.select { |axis| na_scale__saved_planes(axis) > 0 }

            unless saved.empty?
                count = saved.inject(0) { |sum, axis| sum + na_scale__saved_planes(axis) }
                return "Planes are OFF: SHIFT+TAB stretches #{na_scale__axis_words(saved)} at #{na_scale__planes_words(count)}"
            end

            'To keep details their size: SHIFT+TAB stretches instead'
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Lines on a Card That Say What a Mode Does to the Object
        # A plain string is ordinary text; [text, colour] stands out.
        # ------------------------------------------------------------
        def na_scale__focus_notes(focus)
            solid = Na__InsertPrimatives.Na__ScalePreview__ModeStyle(focus[:mode])[:solid]

            case focus[:mode]
            when :uniform
                ['keeps its proportions']
            when :stretch
                ['details keep their size']
            when :mixed
                axes = na_scale__axes_where(focus, :scale)
                one  = axes.length == 1
                [["#{na_scale__axis_words(axes)} #{one ? 'is' : 'are'} too thin to hold a plane: #{one ? 'it distorts' : 'they distort'}", solid]]
            else
                notes = [['distorts everything inside', solid]]
                notes << [na_scale__stretch_advice(focus), NA_DRAWN_REFUSED_TEXT_COLOR] if na_scale__wanted_stretch?(focus)
                notes
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Sentence Under the Strip While a Change Is in Focus
        # ------------------------------------------------------------
        def na_scale__focus_sentence(focus)
            stretch = na_scale__axes_where(focus, :stretch)
            scale   = na_scale__axes_where(focus, :scale)
            words   = na_scale__axis_words(stretch)
            count   = na_scale__planes_words(na_scale__focus_plane_count(focus))
            typed   = focus[:kind] == :dim

            case focus[:mode]
            when :uniform
                'Every axis changes by the same factor: it keeps its proportions'
            when :stretch
                return "A size typed here stretches #{words} at #{count}: details keep their size" if typed

                "#{words} #{stretch.length == 1 ? 'opens' : 'open'} at #{count}: details keep their size"
            when :mixed
                one = scale.length == 1
                "#{words} #{stretch.length == 1 ? 'stretches' : 'stretch'} at #{count}, but " \
                    "#{na_scale__axis_words(scale)} #{one ? 'is' : 'are'} too thin to hold a plane and #{one ? 'distorts' : 'distort'}"
            else
                return "A size typed here scales #{na_scale__axis_words(scale)}: everything inside distorts" if typed

                one = scale.length == 1
                "#{na_scale__axis_words(scale)} #{one ? 'changes' : 'change'} on #{one ? 'its' : 'their'} own: everything inside distorts"
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Sentence Under the Strip With Nothing in Focus
        # ------------------------------------------------------------
        # What the grips will do on this object as things stand, with planes
        # saved and switched off, a stretch waiting to go wrong, said as loudly
        # as the text can say anything.
        # ------------------------------------------------------------
        def na_scale__rest_sentence
            frame  = @na_sc_frame
            accent = NA_DRAWN_TEXT_ACCENT_COLOR
            warn   = NA_DRAWN_REFUSED_TEXT_COLOR

            unless na_scale__planes_on?
                saved  = NA_SCALE_AXES.inject(0) { |sum, axis| sum + na_scale__saved_planes(axis) }
                choice = na_scale__grip_choice

                if choice
                    rows = [[na_scale__choice_sentence(choice), Na__InsertPrimatives.Na__ScalePreview__ModeStyle(choice)[:solid]]]
                    rows << ["#{frame[:name]} has #{saved} stretch plane#{saved == 1 ? '' : 's'}, not in use while Planes are OFF. SHIFT+TAB switches them on", NA_DRAWN_TEXT_COLOR] unless saved.zero?
                    return rows
                end

                return [['Corners scale uniform, faces and edges are non-uniform and distort. SHIFT swaps them, SHIFT+TAB stretches instead', accent]] if saved.zero?

                return [["#{frame[:name]} has #{saved} stretch plane#{saved == 1 ? '' : 's'}, but Planes are OFF: grips scale and distort. SHIFT+TAB switches them on", warn]]
            end

            stretching = na_scale__stretching_axes
            return [['Planes are ON, but every axis is too thin to hold one: every grip still scales', warn]] if stretching.empty?

            violet  = Na__InsertPrimatives.Na__ScalePreview__ModeStyle(:stretch)[:solid]
            with    = na_scale__usable_axes.select { |axis| stretching.key?(axis) }
            without = na_scale__usable_axes - with
            count   = na_scale__planes_words(stretching.values.inject(0, :+))
            return [["Every grip stretches, at #{count}. SHIFT+TAB goes back to scaling", violet]] if without.empty?

            one = without.length == 1
            [["#{na_scale__axis_words(with)} #{with.length == 1 ? 'stretches' : 'stretch'} at #{count}, but " \
              "#{na_scale__axis_words(without)} #{one ? 'is' : 'are'} too thin to hold a plane and still #{one ? 'scales' : 'scale'}", violet]]
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Rows of Text Under the Strip, as [text, colour] Pairs
        # ------------------------------------------------------------
        # Nothing while a tip has that place, or while a plane is being placed:
        # the plane's own label and help are saying what matters.
        # ------------------------------------------------------------
        def na_scale__mode_sentence(focus)
            return [] if na_scale__over_controls?
            return [] if @na_sc_plane_drag || na_scale__ctrl_offer?
            return na_scale__rest_sentence unless focus && focus[:mode]

            rows = [[na_scale__focus_sentence(focus), Na__InsertPrimatives.Na__ScalePreview__ModeStyle(focus[:mode])[:solid]]]

            if focus[:mode] == :scale
                rows << [na_scale__stretch_advice(focus), na_scale__wanted_stretch?(focus) ? NA_DRAWN_REFUSED_TEXT_COLOR : NA_DRAWN_TEXT_COLOR]
            end

            rows
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Drawing
        # -----------------------------------------------------------------------------

        # FUNCTION | The Strip's Pills and the State Each Is In
        # ------------------------------------------------------------
        # In focus only the mode in force has any colour, so it can be read at
        # a glance. With every grip stretching, that is Stretch before one is
        # touched: SHIFT+TAB lights it the moment it is pressed. A mode clicked
        # is lit at rest the same way. Otherwise at rest the pills are the key
        # to the grips' colours, with Stretch greyed while no grip can stretch.
        # ------------------------------------------------------------
        def na_scale__mode_pills(focus)
            stretching = na_scale__stretching_axes
            every      = !stretching.empty? && na_scale__usable_axes.all? { |axis| stretching.key?(axis) }
            choice     = na_scale__grip_choice
            rest       = every ? [:stretch] : (choice ? [choice] : nil)
            lit        = focus && focus[:mode] ? NA_SCALE_MODE_LIT[focus[:mode]] : rest

            NA_SCALE_MODE_PILLS.map do |mode, text|
                state =
                    if lit                                    then lit.include?(mode) ? :lit : :off
                    elsif mode == :stretch && stretching.empty? then :off
                    else                                           :ready
                    end

                { :mode => mode, :text => text, :state => state }
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Strip and Its Sentence; Returns the y Below Them
        # ------------------------------------------------------------
        def na_scale__draw_mode_strip(view)
            focus = na_scale__mode_focus
            hot   = @na_sc_hover && @na_sc_hover[:kind] == :pill ? @na_sc_hover[:id] : nil
            below = Na__InsertPrimatives.Na__ScalePreview__DrawModeStrip(view, na_scale__mode_pills(focus), hot) + NA_SCALE_STRIP_TEXT_GAP
            step  = Na__InsertPrimatives.Na__ScalePreview__LineStep(view)

            na_scale__mode_sentence(focus).each do |text, colour|
                Na__InsertPrimatives.Na__DrawnPreview__DrawScreenText(view, NA_SCALE_BAR_ORIGIN[0], below, text, colour)
                below += step
            end

            below
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Colour Each Live Dimension Wears: { axis => colour }
        # ------------------------------------------------------------
        # By its own axis's rule, so on a mixed pull the axis stretching and the
        # axis being distorted read differently. Under a uniform scale they all
        # wear uniform's.
        # ------------------------------------------------------------
        def na_scale__live_colours(focus)
            rules = focus ? focus[:rules] : {}

            rules.each_with_object({}) do |(axis, rule), colours|
                mode = rule == :stretch ? :stretch : (focus[:mode] == :uniform ? :uniform : :scale)
                colours[axis] = Na__InsertPrimatives.Na__ScalePreview__ModeStyle(mode)[:solid]
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnScaleMode module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP SCALE MODES
# =============================================================================
