# =============================================================================
# NA INSERT PRIMATIVES - DEEP SCALE KEYS
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnScale__Keys__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnScaleKeys
# AUTHOR     : Noble Architecture
# PURPOSE    : SHIFT+TAB for Stretch Planes, shortcut-assignable commands for
#              every Deep Scale switch, and the measurements-box mirror
# CREATED    : 2026
#
# DESCRIPTION:
# - The ways to reach the switches without the mouse all end in the one
#   dispatcher na_scale__hotkey, so they can never disagree with the bar,
#   the popup or each other:
#
#   KEYS while Deep Scale runs:
#     TAB          About Centre on / off
#     SHIFT+TAB    Stretch Planes on / off (the plugin's pattern for a second
#                  switch: Drawn Volume's Subtraction, 5.1.24)
#     ARROWS       one axis's grips for a moment
#     CTRL (held)  a stretch plane offered under the cursor; click to add it
#
#   COMMANDS — Extensions > Na__InsertPrimitives > Deep Scale Options, so
#   each switch can be given its own key in Preferences > Shortcuts. Pressed
#   with Deep Scale not running, a command starts it first.
#
# WHY NO LETTERS (5.2.6):
# - 5.2.0 took A F C X Y Z P D typed on their own. They never got the chance:
#   SketchUp's own shortcuts (P Push/Pull, D Dimension, C Circle, Z Zoom...)
#   are handled by the application before a tool sees the key, and nothing
#   a tool returns from onKeyDown stops them. So every switch is now either
#   a key SketchUp leaves to the tool or a command the user binds themselves.
#
# HOST CONTRACT — included by DrawnScaleTool after DrawnToolShared, so its
# key handlers sit in front of the shared ones and fall back to them with
# super.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Hotkey Actions
    # -----------------------------------------------------------------------------

    # Each action names what it does to which option. The handle sets store
    # the choice, like the bar's buttons; the arrows are the passing glance.
    NA_SCALE_HOTKEY_ACTIONS = {
        :handles_all     => [:value,  'scale_handles', 'all'],
        :handles_faces   => [:value,  'scale_handles', 'faces'],
        :handles_corners => [:value,  'scale_handles', 'corners'],
        :handles_x       => [:value,  'scale_handles', 'x'],
        :handles_y       => [:value,  'scale_handles', 'y'],
        :handles_z       => [:value,  'scale_handles', 'z'],
        :handles_next    => [:toggle, 'scale_handles', nil],
        :planes          => [:toggle, 'scale_planes', nil],
        :centre          => [:toggle, 'scale_about_centre', nil],
        :dims            => [:toggle, 'scale_dimensions', nil],
        :clear_planes    => [:action, 'scale_clear_planes', nil]
    }.freeze

    # FUNCTION | Remember Which Deep Scale Is Running (nil When None)
    # ------------------------------------------------------------
    def self.Na__Scale__SetActiveTool(tool)
        @na_scale_active_tool = tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Deep Scale Running Now, or nil
    # ------------------------------------------------------------
    def self.Na__Scale__ActiveTool
        tool = @na_scale_active_tool
        tool.is_a?(Na__InsertPrimatives::DrawnScaleTool) ? tool : nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Run a Hotkey Action — the Shortcut Commands' Entry Point
    # ------------------------------------------------------------
    # With Deep Scale not running the command starts it (it takes the
    # selection as ever) and then applies the switch, so a key bound to
    # "Stretch Planes" is also a way into the tool with planes on.
    # ------------------------------------------------------------
    def self.Na__Scale__Hotkey(action)
        return false unless NA_SCALE_HOTKEY_ACTIONS.key?(action.to_s.to_sym)

        tool = Na__InsertPrimatives.Na__Scale__ActiveTool
        tool ||= Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnScaleTool
        return false unless tool

        tool.na_scale__hotkey(action.to_s.to_sym)
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "NA DEEP SCALE: hotkey #{action} failed — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Should a Shortcut Command Show a Tick?
    # ------------------------------------------------------------
    def self.Na__Scale__HotkeyChecked?(action)
        kind, option, value = NA_SCALE_HOTKEY_ACTIONS[action.to_s.to_sym]

        case kind
        when :value  then Na__InsertPrimatives.Na__ToolOptions__Value(option).to_s == value
        when :toggle then option != 'scale_handles' && Na__InsertPrimatives.Na__ToolOptions__Enabled?(option)
        else              false
        end
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # =============================================================================
    # MODULE | Deep Scale Keys
    # =============================================================================

    module DrawnScaleKeys

        NA_SCALE_TAB_KEY = 9                                                  # <-- No VK_TAB constant in the SketchUp API

        # What each key puts in the measurements box, so the dimension being
        # typed can show it as it grows. Windows virtual-key codes; SHIFT
        # turns = into + and 8 into *.
        NA_SCALE_ECHO_KEYS = {
            106 => '*', 107 => '+', 109 => '-', 110 => '.', 111 => '/',
            187 => '=', 188 => ',', 189 => '-', 190 => '.', 191 => '/', 32 => ' '
        }.freeze
        NA_SCALE_ECHO_SHIFTED = { 187 => '+', 56 => '*' }.freeze
        NA_SCALE_BACKSPACE    = 8

        # -----------------------------------------------------------------------------
        # REGION | Keys
        # -----------------------------------------------------------------------------

        # ON KEY DOWN | SHIFT+TAB Switches Stretch Planes; a Typed Character Is Echoed
        # ------------------------------------------------------------
        # SHIFT comes from the mouse flags, the one modifier they are always
        # right about; the key flags are not read (on Windows they carry the
        # scan code). One switch per press of TAB, through TAB's own held
        # guard, which the shared key-up clears: a held TAB's repeats neither
        # switch it back nor fall through to About Centre. Not with CTRL down,
        # which is the hand on the plane offer.
        # ------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            if key == NA_SCALE_TAB_KEY && @na_shift_held && !@na_ctrl_held
                unless @na_tab_held
                    @na_tab_held = true
                    na_scale__hotkey(:planes)
                    na_scale__after_mouse(view)
                end

                return true
            end

            na_scale__echo_key(key, view)
            super
        end
        # ---------------------------------------------------------------

        # ON KEY UP | Left to the Shared Handler
        # ------------------------------------------------------------
        # Stated rather than deleted: Reload Plugin Data loads this file again
        # without removing anything, so 5.2.0's ALT-tracking key-up would
        # otherwise live on in a running SketchUp until a restart.
        # ------------------------------------------------------------
        def onKeyUp(key, repeat, flags, view)
            super
        end
        # ---------------------------------------------------------------

        # ON USER TEXT | Every Entry Ends the Echo: SketchUp Has the Real Text Now
        # ------------------------------------------------------------
        def onUserText(text, view)
            @na_sc_typed = nil
            super
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Echoing the Measurements Box
        # -----------------------------------------------------------------------------
        #
        # SketchUp tells a tool what was typed only when Enter is pressed. So
        # the tool keeps its own copy, a key at a time, from the same key
        # events the box is fed by: the dimension being typed into shows the
        # text as it grows and the preview shows what Enter would do. It is a
        # MIRROR — the value applied is always the box's own text, handed over
        # by SketchUp with the Enter, so a key the echo misreads can only make
        # the mirror wrong for a moment, never the model.

        # FUNCTION | The Character a Key Puts in the Box, or nil
        # ------------------------------------------------------------
        def na_scale__key_char(key)
            return NA_SCALE_ECHO_SHIFTED[key] if @na_shift_held && NA_SCALE_ECHO_SHIFTED.key?(key)
            return (key - 48).to_s if key >= 48 && key <= 57
            return (key - 96).to_s if key >= 96 && key <= 105
            return NA_SCALE_ECHO_KEYS[key] if NA_SCALE_ECHO_KEYS.key?(key)
            return nil unless key >= 65 && key <= 90

            letter = key.chr
            @na_shift_held ? letter : letter.downcase
        end
        # ---------------------------------------------------------------

        # FUNCTION | Add One Key to the Echo, or Take One Back
        # ------------------------------------------------------------
        # A letter only joins an entry already started ("1.2m", "1.5x"); on
        # its own it is SketchUp's shortcut and never reaches the box. BKSP
        # takes the last character back while there is one.
        # ------------------------------------------------------------
        def na_scale__echo_key(key, view)
            typed = @na_sc_typed.to_s

            if key == NA_SCALE_BACKSPACE
                return false if typed.empty?

                @na_sc_typed = typed[0...-1]
            else
                char = na_scale__key_char(key)
                return false unless char
                return false if typed.empty? && char =~ /[a-z]/i

                @na_sc_typed = typed + char
            end

            na_drawn__update_status_text
            view.invalidate if view
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is Anything Being Typed?
        # ------------------------------------------------------------
        def na_scale__typing?
            !@na_sc_typed.to_s.empty?
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The One Dispatcher
        # -----------------------------------------------------------------------------

        # FUNCTION | Apply a Hotkey Action, Whichever Key or Command Asked
        # ------------------------------------------------------------
        # Goes through the popup's own option path, so the drag in hand, the
        # status line and an open popup all follow, exactly as a click would.
        # A handle set chosen here is the stored one, so an arrow glance is let go.
        # ------------------------------------------------------------
        def na_scale__hotkey(action)
            kind, option, value = Na__InsertPrimatives::NA_SCALE_HOTKEY_ACTIONS[action]
            return false unless kind

            case kind
            when :value
                Na__InsertPrimatives.Na__ToolOptions__SetValue(option, value)
                @na_axis_lock = nil
                na_scale__after_option_changed(option)
            else
                self.Na__DrawnMode__ToggleToolOption(option)                  # <-- Toggles, steps a cycle, or clears the planes
            end

            Na__InsertPrimatives.Na__RightClickPopup__RefreshOption(option) unless kind == :action
            na_scale__say(na_scale__switch_caption(option)) unless kind == :action
            na_drawn__update_status_text
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | What a Switch Says When It Changes
        # Stretch Planes switched on says how to place one: the switch on its
        # own does nothing visible until there is a plane.
        # ------------------------------------------------------------
        def na_scale__switch_caption(option)
            caption = Na__InsertPrimatives.Na__ToolOptions__CaptionFor(option)
            return caption unless option.to_s == NA_SCALE_OPTION_PLANES

            if @na_sc_frame && @na_sc_frame[:loose]
                return "#{caption} — not for loose geometry: planes are saved on a group or component"
            end

            return caption unless na_scale__planes_on?

            "#{caption} — click a coloured centre line, or hold CTRL over the object, to add a plane"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnScaleKeys module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP SCALE KEYS
# =============================================================================
