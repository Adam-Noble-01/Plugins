# =============================================================================
# NA NOBLE DRAWING TOOLS - DEEP SCALE KEYS
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnScale__Keys__.rb
# NAMESPACE  : Na__NobleDrawingTools::DrawnScaleKeys
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
#     SHIFT+TAB    Stretch Planes on / off: on, every grip stretches, at a plane
#                  through the centre of each axis until one is placed (5.2.22).
#                  The plugin's pattern for a second switch: Drawn Volume's
#                  Subtraction, 5.1.24
#     ARROWS       one axis's grips for a moment
#     CTRL (held)  a stretch plane offered under the cursor; click to add it
#     DEL          removes the plane under the cursor, or the one clicked, and
#                  nothing else (5.2.27). Never the object
#
#   COMMANDS — Extensions > Na__NobleDrawingTools > Deep Scale Options, so
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
# WHY THE SELECTION IS SET ASIDE (5.2.27):
# - DEL is one of those keys: it is SketchUp's own shortcut for Edit > Delete,
#   so pressing it to remove a plane deleted the selected object instead.
# - A tool has no way to take the shortcut away, so it is left nothing to act
#   on. While Deep Scale runs SketchUp's selection is kept empty, and what was
#   in it is held here. Nothing in the tool needs the selection: a part reached
#   by double-clicking down was never in it. Leaving the tool hands it back, so
#   the next tool, and a DEL meant for the object, find it selected as before.
# - The cost, stated: Copy, Hide and anything else that acts on the selection
#   have nothing to act on until the tool ends.
# - With the shortcut taking the key, a tool has been reported to see only the
#   key-up. SketchUp 2027 in the background sends both. So DEL is acted on at
#   whichever arrives first, once per press, and a held key removes one plane.
#
# HOST CONTRACT — included by DrawnScaleTool after DrawnToolShared, so its
# key handlers sit in front of the shared ones and fall back to them with
# super.
#
# =============================================================================

require 'sketchup.rb'

module Na__NobleDrawingTools

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
        :mode_uniform     => [:mode,   'scale_grip_mode', 'uniform'],
        :mode_non_uniform => [:mode,   'scale_grip_mode', 'non_uniform'],
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
        tool.is_a?(Na__NobleDrawingTools::DrawnScaleTool) ? tool : nil
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

        tool = Na__NobleDrawingTools.Na__Scale__ActiveTool
        tool ||= Na__NobleDrawingTools.Na__ModeSwitch__ActivateDrawnScaleTool
        return false unless tool

        tool.na_scale__hotkey(action.to_s.to_sym)
    rescue StandardError => error
        Na__NobleDrawingTools.Na__Debug__Puts "NA DEEP SCALE: hotkey #{action} failed — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Should a Shortcut Command Show a Tick?
    # ------------------------------------------------------------
    def self.Na__Scale__HotkeyChecked?(action)
        kind, option, value = NA_SCALE_HOTKEY_ACTIONS[action.to_s.to_sym]

        case kind
        when :value  then Na__NobleDrawingTools.Na__ToolOptions__Value(option).to_s == value
        when :mode   then Na__NobleDrawingTools.Na__ToolOptions__Value(option).to_s == value && !Na__NobleDrawingTools.Na__ToolOptions__Enabled?('scale_planes')
        when :toggle then option != 'scale_handles' && Na__NobleDrawingTools.Na__ToolOptions__Enabled?(option)
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
            na_scale__set_selection_aside
            return na_scale__delete_pressed(view) if key == VK_DELETE

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

        # ON KEY UP | DEL, If Its Key-Down Never Came; the Rest to the Shared Handler
        # ------------------------------------------------------------
        # Stated rather than deleted: Reload Plugin Data loads this file again
        # without removing anything, so 5.2.0's ALT-tracking key-up would
        # otherwise live on in a running SketchUp until a restart.
        # ------------------------------------------------------------
        def onKeyUp(key, repeat, flags, view)
            na_scale__set_selection_aside
            return na_scale__delete_released(view) if key == VK_DELETE

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
        # REGION | DEL: Planes Only
        # -----------------------------------------------------------------------------

        # FUNCTION | DEL Going Down: Acted On Once, However Long It Is Held
        # ------------------------------------------------------------
        def na_scale__delete_pressed(view)
            return false if na_scale__typing?                                  # <-- Mid-entry it is the measurements box's key

            na_scale__delete_key(view) unless @na_sc_delete_seen
            @na_sc_delete_seen = true
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | DEL Coming Up: Acted On Only If Its Key-Down Never Arrived
        # ------------------------------------------------------------
        def na_scale__delete_released(view)
            seen               = @na_sc_delete_seen
            @na_sc_delete_seen = false
            return false if na_scale__typing?

            na_scale__delete_key(view) unless seen
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | What DEL Does: Drops What Is Held, Removes the Chosen Plane, or Says Why Not
        # ------------------------------------------------------------
        # Unlike BKSP it never steps out to the object around this one: a key
        # that means delete should not change what the tool is holding.
        # ------------------------------------------------------------
        def na_scale__delete_key(view)
            if @na_sc_plane_drag
                na_scale__cancel_plane_drag
            elsif @na_sc_drag
                na_scale__cancel_drag
            elsif !na_scale__remove_chosen_plane
                na_scale__say(na_scale__delete_refusal)
            end

            @na_last_vcb_text = nil
            na_scale__after_mouse(view)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | What DEL Says When It Has No Plane to Remove
        # ------------------------------------------------------------
        def na_scale__delete_refusal
            leave = 'DEL only removes stretch planes in Deep Scale. To delete the object, leave the tool first'
            return leave unless @na_sc_frame && na_scale__planes_editable?

            "No plane selected: click a plane's diamond, then press DEL. #{leave}"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Selection, Set Aside While the Tool Runs
        # -----------------------------------------------------------------------------

        # FUNCTION | Empty SketchUp's Selection, Keeping What Was in It for Later
        # ------------------------------------------------------------
        # Asked on every mouse move, press and key, because other things can
        # select while the tool runs: Select All, the Outliner, an undo. Cheap
        # when there is nothing there, which is nearly always. What arrives is
        # the newest choice, so it replaces what was held.
        # ------------------------------------------------------------
        def na_scale__set_selection_aside
            model = Sketchup.active_model
            return false unless model && model.selection.length > 0

            na_scale__hold_aside(model.selection.to_a)
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Make These the Entities Handed Back When the Tool Ends
        # ------------------------------------------------------------
        def na_scale__hold_aside(entities)
            model = Sketchup.active_model
            return false unless model

            @na_sc_aside = { :entities => entities.to_a, :context => model.active_path }
            model.selection.clear
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Tool Is Ending: Put the Selection Back
        # ------------------------------------------------------------
        # Only what still exists. Not after a change of open group, which empties
        # the selection in SketchUp too: entities can only be selected from the
        # context they sit in.
        # ------------------------------------------------------------
        def na_scale__give_selection_back
            na_scale__set_selection_aside

            aside        = @na_sc_aside
            @na_sc_aside = nil
            model        = Sketchup.active_model
            return false unless model && aside
            return false unless Na__NobleDrawingTools.Na__DeepPick__SameContext?(model.active_path, aside[:context])

            live = aside[:entities].select(&:valid?)
            return false if live.empty?

            model.selection.add(live)
            true
        rescue StandardError
            false
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
            kind, option, value = Na__NobleDrawingTools::NA_SCALE_HOTKEY_ACTIONS[action]
            return false unless kind

            case kind
            when :mode
                return na_scale__choose_grip_mode(value)
            when :value
                Na__NobleDrawingTools.Na__ToolOptions__SetValue(option, value)
                @na_axis_lock = nil
                na_scale__after_option_changed(option)
            else
                self.Na__DrawnMode__ToggleToolOption(option)                  # <-- Toggles, steps a cycle, or clears the planes
            end

            Na__NobleDrawingTools.Na__RightClickPopup__RefreshOption(option) unless kind == :action
            na_scale__say(na_scale__switch_caption(option)) unless kind == :action
            na_drawn__update_status_text
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | What a Switch Says When It Changes
        # Stretch Planes switched on says what just happened to every grip.
        # ------------------------------------------------------------
        def na_scale__switch_caption(option)
            caption = Na__NobleDrawingTools.Na__ToolOptions__CaptionFor(option)
            return caption unless option.to_s == NA_SCALE_OPTION_PLANES && na_scale__planes_on?

            "#{caption} — every grip stretches, at a plane through the centre of each axis until you place your own"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnScaleKeys module

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF DEEP SCALE KEYS
# =============================================================================
