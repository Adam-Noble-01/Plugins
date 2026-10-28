# =============================================================================
# NA INSERT PRIMATIVES - ALTGR NAVIGATION FILTER (WINDOWS)
# =============================================================================
#
# FILE       : Na__InsertPrimatives__Camera__AltGrFilter__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Stop SketchUp 2027's Ctrl+Alt touchpad orbit and Shift+Ctrl+Alt
#              pan from starting while AltGr is held, without touching the
#              AltGr shortcuts: SketchUp's mouse handling is shown Ctrl and Alt
#              up, its keyboard handling the keys as they really are
# CREATED    : 2026 (5.2.13)
#
# WHY (5.2.12 WAS NOT ENOUGH):
# - 5.2.12 undid an AltGr orbit after SketchUp had made it. In SketchUp 2027
#   the view still jerked for a moment: the orbit is drawn before a
#   ViewObserver can put it back, so the correction is seen. And it let the
#   Shift+Ctrl+Alt pan through on purpose, which every AltGr+Shift macro
#   sets off. The clean fix is that the gesture never starts.
#
# HOW:
# - SketchUp reads the modifiers on a MOUSE message to start the gesture, and
#   on a KEY message to match a shortcut. Windows keeps those modifiers per
#   thread (GetKeyState), and a thread hook on SketchUp's own UI thread
#   (SetWindowsHookEx WH_GETMESSAGE) sees each message as SketchUp takes it
#   from its queue, before SketchUp handles it:
#     mouse, pointer, hover and raw input, with the chord held:
#         Ctrl and Alt cleared from the thread's key state (SetKeyboardState),
#         and MK_CONTROL cleared from the message's own key flags
#     any key message, except a held Ctrl or Alt repeating:
#         Ctrl and Alt put back as the keyboard really has them
#   So AltGr + a mouse move reads as a plain move: no orbit, no pan. AltGr+P,
#   AltGr+[ and every other AltGr macro still arrive as Ctrl+Alt+key.
# - In-process and thread-scoped: not a system-wide hook, nothing injected
#   into another program, no key remapped, no Windows setting changed. It is
#   installed only while it has work to do, and removed on quit.
#
# TWO HOOKS, SO IT COSTS NOTHING UNTIL ALTGR GOES DOWN:
# - Every hook call is a kernel round trip: on this machine about 40 us a
#   message whatever the language (measured from Python and from Ruby alike),
#   which a hook seeing every message on SketchUp's UI thread would pay all
#   the time. So:
#     watcher  WH_KEYBOARD, called for key messages only (a few a second):
#              in while the filter is wanted; puts the cleaner in the moment
#              the chord goes down
#     cleaner  WH_GETMESSAGE, the work above: in only while the chord is
#              held, out on the next tick after it is let go (or, if the
#              key-up went to another window, the first message that finds
#              the chord up)
#
# WHEN IT IS ON:
#   Drawn Plane / Drawn Volume active, parallel view, 2D Orbit Lock on
#       (the guard sets this): any Ctrl+Alt chord, AltGr or left Ctrl+Alt
#   Extensions > Na__InsertPrimitives > AltGr Never Orbits or Pans (off by
#       default): everywhere in SketchUp, AltGr (right Alt) only, so a
#       deliberate left Ctrl+Alt still navigates
#
# WHAT IT CANNOT DO:
# - If SketchUp read the keyboard hardware (GetAsyncKeyState) instead of the
#   thread's key state, hiding the chord would not stop it. Dev Mode logs how
#   many mouse messages the filter cleaned, so a view that still moves with
#   that count rising says exactly this.
# - Windows only. A Mac has no AltGr; the guard's camera hold still runs there.
#
# HOOK SAFETY:
# - The hook procedure is a Fiddle closure kept for the life of SketchUp, so
#   nothing can free it while Windows may call it. Every call is wrapped so no
#   Ruby exception can unwind through user32, and it always hands the message
#   on with CallNextHookEx.
# - It reads module flags and calls user32 only, never the SketchUp API.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../02__AppData/Na__InsertPrimatives__AppData__ConfigLoader__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnGridSnap__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Filter Constants and State
    # -----------------------------------------------------------------------------

    NA_ALTGR_FILTER_WINDOWS        = (RUBY_PLATFORM =~ /mswin|mingw|cygwin/) ? true : false
    NA_ALTGR_FILTER_EVERYWHERE_KEY = 'AltGrNeverNavigates'.freeze               # <-- Registry key under NA_DRAWN_SETTINGS_SECTION

    NA_ALTGR_WH_KEYBOARD   = 2
    NA_ALTGR_WH_GETMESSAGE = 3
    NA_ALTGR_PM_REMOVE     = 1
    NA_ALTGR_HC_ACTION     = 0
    NA_ALTGR_MK_CONTROL    = 0x0008                                             # <-- Ctrl's bit in a client mouse message's wParam

    NA_ALTGR_VK_CONTROL    = 0x11
    NA_ALTGR_VK_MENU       = 0x12
    NA_ALTGR_VK_RMENU      = 0xA5                                               # <-- Right Alt: AltGr
    NA_ALTGR_CHORD_KEYS    = [0x11, 0x12, 0xA2, 0xA3, 0xA4, 0xA5].freeze         # <-- Ctrl, Alt, LCtrl, RCtrl, LAlt, RAlt

    # The messages a navigation gesture is read from, and the key messages a
    # shortcut is read from. Client mouse messages carry MK_* key flags in the
    # low word of wParam; the others are only ever given a clean key state.
    NA_ALTGR_CLIENT_MOUSE  = (0x0200..0x020E)                                   # <-- WM_MOUSEMOVE .. WM_MOUSEHWHEEL
    NA_ALTGR_OTHER_POINTER = [(0x00A0..0x00AD), (0x0245..0x024F)].freeze         # <-- Non-client mouse, WM_POINTER*
    NA_ALTGR_SINGLE_INPUT  = [0x00FF, 0x02A1, 0x02A3].freeze                     # <-- WM_INPUT, WM_MOUSEHOVER, WM_MOUSELEAVE
    NA_ALTGR_KEY_MESSAGES  = (0x0100..0x0109)                                   # <-- WM_KEYDOWN .. WM_UNICHAR
    NA_ALTGR_KEY_DOWNS     = [0x0100, 0x0104].freeze                             # <-- WM_KEYDOWN, WM_SYSKEYDOWN

    # Kept across Reload Plugin Data: the hook handle and its closure must
    # outlive any reload, or Windows would call freed memory.
    @na_altgr_api         = nil   unless defined?(@na_altgr_api)
    @na_altgr_hook        = nil   unless defined?(@na_altgr_hook)             # <-- The cleaner (WH_GETMESSAGE)
    @na_altgr_proc        = nil   unless defined?(@na_altgr_proc)
    @na_altgr_watch_hook  = nil   unless defined?(@na_altgr_watch_hook)       # <-- The watcher (WH_KEYBOARD)
    @na_altgr_watch_proc  = nil   unless defined?(@na_altgr_watch_proc)
    @na_altgr_state       = nil   unless defined?(@na_altgr_state)
    @na_altgr_tools       = false unless defined?(@na_altgr_tools)
    @na_altgr_everywhere  = nil   unless defined?(@na_altgr_everywhere)
    @na_altgr_masked      = false unless defined?(@na_altgr_masked)
    @na_altgr_cleaned     = 0     unless defined?(@na_altgr_cleaned)
    @na_altgr_quit_watch  = nil   unless defined?(@na_altgr_quit_watch)
    @na_altgr_retire_due  = false unless defined?(@na_altgr_retire_due)

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Scope — Who Wants the Filter
    # -----------------------------------------------------------------------------

    # FUNCTION | The Guard Says Whether a Guarded Tool Wants It Now
    # ------------------------------------------------------------
    # True while Drawn Plane or Drawn Volume holds a parallel view with the
    # lock on (Camera__ParallelDrawingGuard__ decides). Installs or removes
    # the hook to match.
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__SetToolScope(wanted)
        wanted = wanted ? true : false
        return @na_altgr_tools if wanted == @na_altgr_tools && Na__InsertPrimatives.Na__AltGrFilter__InstalledAsNeeded?

        @na_altgr_tools = wanted
        Na__InsertPrimatives.Na__AltGrFilter__Sync
        @na_altgr_tools
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is AltGr Kept From Navigating Everywhere? (Extensions Menu Switch)
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__Everywhere?
        if @na_altgr_everywhere.nil?
            stored = Sketchup.read_default(NA_DRAWN_SETTINGS_SECTION, NA_ALTGR_FILTER_EVERYWHERE_KEY, false)
            @na_altgr_everywhere = (stored == true || stored == 'true' || stored == 1)
        end
        @na_altgr_everywhere
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Switch AltGr Never Orbits or Pans On or Off (Extensions Menu, Shortcut)
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__ToggleAltGrFilter
        unless NA_ALTGR_FILTER_WINDOWS
            Sketchup::set_status_text('AltGr Never Orbits or Pans is for Windows: a Mac has no AltGr', SB_PROMPT)
            return false
        end

        on = !Na__InsertPrimatives.Na__AltGrFilter__Everywhere?
        Sketchup.write_default(NA_DRAWN_SETTINGS_SECTION, NA_ALTGR_FILTER_EVERYWHERE_KEY, on)
        @na_altgr_everywhere = on
        installed = Na__InsertPrimatives.Na__AltGrFilter__Sync

        message =
            if on && !installed
                'AltGr Never Orbits or Pans: could not hook the keyboard state — see the Ruby Console with Dev Mode on'
            elsif on
                'AltGr Never Orbits or Pans: on — AltGr + a mouse move no longer orbits or pans, anywhere in SketchUp'
            else
                'AltGr Never Orbits or Pans: off — only Drawn Plane and Drawn Volume keep AltGr from navigating a 2D view'
            end
        Sketchup::set_status_text(message, SB_PROMPT)
        on
    end
    # ---------------------------------------------------------------

    # FUNCTION | Which Chord the Filter Hides Right Now, or nil When It Is Idle
    # ------------------------------------------------------------
    #   :chord   a guarded tool: any Ctrl+Alt, AltGr or left Ctrl + left Alt
    #   :altgr   everywhere: AltGr only, so a deliberate left Ctrl+Alt still works
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__Mode
        return :chord if @na_altgr_tools
        return :altgr if @na_altgr_everywhere

        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Installing and Removing the Hook
    # -----------------------------------------------------------------------------

    # FUNCTION | user32 and kernel32, Loaded Once; false Where They Cannot Be
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__Api
        return @na_altgr_api unless @na_altgr_api.nil?

        @na_altgr_api =
            if NA_ALTGR_FILTER_WINDOWS
                require 'fiddle'
                user32   = Fiddle::Handle.new('user32')
                kernel32 = Fiddle::Handle.new('kernel32')
                pointer  = Fiddle::TYPE_VOIDP
                wparam   = Fiddle::TYPE_UINTPTR_T
                lparam   = Fiddle::TYPE_INTPTR_T
                dword    = -Fiddle::TYPE_INT

                {
                    :wparam    => wparam,
                    :lparam    => lparam,
                    :set_hook  => Fiddle::Function.new(user32['SetWindowsHookExW'],   [Fiddle::TYPE_INT, pointer, pointer, dword], pointer),
                    :unhook    => Fiddle::Function.new(user32['UnhookWindowsHookEx'], [pointer], Fiddle::TYPE_INT),
                    :next_hook => Fiddle::Function.new(user32['CallNextHookEx'],      [pointer, Fiddle::TYPE_INT, wparam, lparam], lparam),
                    :get_state => Fiddle::Function.new(user32['GetKeyboardState'],    [pointer], Fiddle::TYPE_INT),
                    :set_state => Fiddle::Function.new(user32['SetKeyboardState'],    [pointer], Fiddle::TYPE_INT),
                    :async     => Fiddle::Function.new(user32['GetAsyncKeyState'],    [Fiddle::TYPE_INT], Fiddle::TYPE_SHORT),
                    :thread_id => Fiddle::Function.new(kernel32['GetCurrentThreadId'], [], dword)
                }
            else
                false
            end
    rescue LoadError, StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "ALTGR FILTER: user32 cannot be reached (#{error.message})"
        @na_altgr_api = false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Put the Hooks In or Take Them Out to Match the Scope; Returns Whether It Is On
    # ------------------------------------------------------------
    # On means the watcher is in. The cleaner follows the chord: in at once
    # if AltGr is already down (the AltGr+P that started the tool), else
    # when the watcher sees it go down.
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__Sync
        Na__InsertPrimatives.Na__AltGrFilter__Everywhere?                        # <-- Read once, so no hook ever touches the registry
        mode = Na__InsertPrimatives.Na__AltGrFilter__Mode

        unless mode
            Na__InsertPrimatives.Na__AltGrFilter__Remove
            return false
        end

        return false unless Na__InsertPrimatives.Na__AltGrFilter__InstallWatcher

        Na__InsertPrimatives.Na__AltGrFilter__InstallCleaner if Na__InsertPrimatives.Na__AltGrFilter__ChordDown?(mode)
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Are the Hooks In Exactly When the Scope Wants Them?
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__InstalledAsNeeded?
        wanted = !Na__InsertPrimatives.Na__AltGrFilter__Mode.nil? && Na__InsertPrimatives.Na__AltGrFilter__Api
        wanted ? !@na_altgr_watch_hook.nil? : (@na_altgr_watch_hook.nil? && @na_altgr_hook.nil?)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is the Filter On (the Watcher In)? For Checks and the Menu
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__Installed?
        !@na_altgr_watch_hook.nil?
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is the Cleaner In Right Now (the Chord Held)?
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__Cleaning?
        !@na_altgr_hook.nil?
    end
    # ---------------------------------------------------------------

    # FUNCTION | Hook SketchUp's UI Thread (This Thread) Only; Returns the Handle or nil
    # ------------------------------------------------------------
    # dwThreadId is the calling thread, the one SketchUp runs Ruby and its
    # windows on, and hMod is null, which Windows requires for a thread of the
    # calling process: nothing global, nothing injected anywhere else.
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__ThreadHook(kind, procedure)
        api  = @na_altgr_api
        hook = api[:set_hook].call(kind, procedure, nil, api[:thread_id].call)
        return hook unless hook.null?

        Na__InsertPrimatives.Na__Debug__Puts "ALTGR FILTER: SetWindowsHookEx refused thread hook #{kind}"
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Put the Watcher In (WH_KEYBOARD: Key Messages Only)
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__InstallWatcher
        return true if @na_altgr_watch_hook

        api = Na__InsertPrimatives.Na__AltGrFilter__Api
        return false unless api

        @na_altgr_watch_proc ||= Fiddle::Closure::BlockCaller.new(api[:lparam], [Fiddle::TYPE_INT, api[:wparam], api[:lparam]]) do |code, wparam, lparam|
            Na__InsertPrimatives.Na__AltGrFilter__Watch(code, wparam, lparam)
        end

        @na_altgr_watch_hook = Na__InsertPrimatives.Na__AltGrFilter__ThreadHook(NA_ALTGR_WH_KEYBOARD, @na_altgr_watch_proc)
        return false unless @na_altgr_watch_hook

        Na__InsertPrimatives.Na__AltGrFilter__WatchQuit
        Na__InsertPrimatives.Na__Debug__Puts "ALTGR FILTER: on (#{Na__InsertPrimatives.Na__AltGrFilter__Mode == :chord ? 'Drawn Plane / Volume: any Ctrl+Alt' : 'everywhere: AltGr'})"
        true
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "ALTGR FILTER: not installed — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Put the Cleaner In (WH_GETMESSAGE), for as Long as the Chord Is Held
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__InstallCleaner
        return true if @na_altgr_hook

        api = Na__InsertPrimatives.Na__AltGrFilter__Api
        return false unless api

        @na_altgr_state ||= Fiddle::Pointer.malloc(256)
        @na_altgr_proc  ||= Fiddle::Closure::BlockCaller.new(api[:lparam], [Fiddle::TYPE_INT, api[:wparam], api[:lparam]]) do |code, wparam, lparam|
            Na__InsertPrimatives.Na__AltGrFilter__Hook(code, wparam, lparam)
        end

        @na_altgr_hook        = Na__InsertPrimatives.Na__AltGrFilter__ThreadHook(NA_ALTGR_WH_GETMESSAGE, @na_altgr_proc)
        @na_altgr_retire_due  = false
        !@na_altgr_hook.nil?
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "ALTGR FILTER: cleaner not installed — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Take the Cleaner Out, Handing the Real Ctrl and Alt Back First
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__RemoveCleaner
        hook = @na_altgr_hook
        return true unless hook

        Na__InsertPrimatives.Na__AltGrFilter__RestoreChord if @na_altgr_masked
        @na_altgr_hook       = nil
        @na_altgr_retire_due = false
        @na_altgr_api[:unhook].call(hook) if @na_altgr_api
        true
    rescue StandardError
        @na_altgr_hook = nil
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Take Both Hooks Out (Scope Gone, or SketchUp Quitting)
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__Remove
        had_watcher = !@na_altgr_watch_hook.nil?
        Na__InsertPrimatives.Na__AltGrFilter__RemoveCleaner

        hook = @na_altgr_watch_hook
        @na_altgr_watch_hook = nil
        @na_altgr_api[:unhook].call(hook) if hook && @na_altgr_api

        if had_watcher
            cleaned = @na_altgr_cleaned.to_i
            Na__InsertPrimatives.Na__Debug__Puts "ALTGR FILTER: off — #{cleaned} mouse message#{cleaned == 1 ? '' : 's'} cleaned of Ctrl+Alt"
            @na_altgr_cleaned = 0
        end
        true
    rescue StandardError
        @na_altgr_watch_hook = nil
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Cleaner Found the Chord Up: Take It Out at the Next Safe Moment
    # ------------------------------------------------------------
    # Never from inside the cleaner's own call. The watcher takes it out at the
    # next key message, and a guarded tool at its next mouse move; until then
    # it only costs time, it hides nothing (every message checks the hardware).
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__RetireLater
        @na_altgr_retire_due = true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Take the Cleaner Out Now If It Has Been Found Idle (Outside Any Hook)
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__RetireIfDue
        return false unless @na_altgr_retire_due && @na_altgr_hook

        mode = Na__InsertPrimatives.Na__AltGrFilter__Mode
        return false if mode && Na__InsertPrimatives.Na__AltGrFilter__ChordDown?(mode)

        Na__InsertPrimatives.Na__AltGrFilter__RemoveCleaner
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Guarded Tool Saw the Chord Complete (Belt to the Watcher's Braces)
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__ChordPressed
        mode = Na__InsertPrimatives.Na__AltGrFilter__Mode
        return false unless mode && @na_altgr_watch_hook && Na__InsertPrimatives.Na__AltGrFilter__ChordDown?(mode)

        Na__InsertPrimatives.Na__AltGrFilter__InstallCleaner
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Take the Hook Out When SketchUp Quits (and at Ruby's Exit)
    # ------------------------------------------------------------
    # So no message arriving during shutdown can call into a Ruby that is
    # already being torn down.
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__WatchQuit
        return if @na_altgr_quit_watch

        @na_altgr_quit_watch = AltGrFilterQuitWatch.new
        Sketchup.add_observer(@na_altgr_quit_watch)
        at_exit { Na__InsertPrimatives.Na__AltGrFilter__Remove rescue nil }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Hook Procedure
    # -----------------------------------------------------------------------------

    # FUNCTION | The Watcher: Called by Windows for Each Key Message the UI Thread Takes
    # ------------------------------------------------------------
    # Chord down: the cleaner goes in, before the next mouse message. Chord
    # up: the cleaner comes out (handing the real keys back as it goes).
    # Removing the cleaner from here is safe: it is a different hook.
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__Watch(code, wparam, lparam)
        begin
            Na__InsertPrimatives.Na__AltGrFilter__KeySeen if code == NA_ALTGR_HC_ACTION && @na_altgr_watch_hook
        rescue Exception
            nil                                                               # <-- Nothing may unwind through user32
        end

        api = @na_altgr_api
        api ? api[:next_hook].call(nil, code, wparam, lparam) : 0
    rescue Exception
        0
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Key Message: Is the Chord Down Now?
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__KeySeen
        mode = Na__InsertPrimatives.Na__AltGrFilter__Mode
        return unless mode

        if Na__InsertPrimatives.Na__AltGrFilter__ChordDown?(mode)
            Na__InsertPrimatives.Na__AltGrFilter__InstallCleaner
        elsif @na_altgr_hook
            Na__InsertPrimatives.Na__AltGrFilter__RemoveCleaner
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Cleaner: Called by Windows for Each Message the UI Thread Takes
    # ------------------------------------------------------------
    # Only messages being removed from the queue are touched (wParam is
    # PM_REMOVE); a peek leaves everything as it is. Whatever happens, the
    # message goes on to the next hook and to SketchUp.
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__Hook(code, wparam, lparam)
        begin
            Na__InsertPrimatives.Na__AltGrFilter__Message(lparam) if code >= 0 && wparam == NA_ALTGR_PM_REMOVE && @na_altgr_hook
        rescue Exception
            nil                                                               # <-- Nothing may unwind through user32
        end

        api = @na_altgr_api
        api ? api[:next_hook].call(nil, code, wparam, lparam) : 0
    rescue Exception
        0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Clean a Mouse Message of the Chord, or Put the Chord Back for a Key
    # ------------------------------------------------------------
    # The MSG layout on 64-bit Windows: hwnd at 0, message at 8, wParam at 16,
    # lParam at 24.
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__Message(msg_address)
        mode = Na__InsertPrimatives.Na__AltGrFilter__Mode
        return unless mode

        msg     = Fiddle::Pointer.new(msg_address)
        message = msg[8, 4].unpack1('L')

        if Na__InsertPrimatives.Na__AltGrFilter__InputMessage?(message)
            unless Na__InsertPrimatives.Na__AltGrFilter__ChordDown?(mode)
                Na__InsertPrimatives.Na__AltGrFilter__RetireLater              # <-- The key-up went to another window: nothing left to hide
                return
            end

            Na__InsertPrimatives.Na__AltGrFilter__HideChord
            Na__InsertPrimatives.Na__AltGrFilter__ClearControlFlag(msg) if NA_ALTGR_CLIENT_MOUSE.cover?(message)
        elsif NA_ALTGR_KEY_MESSAGES.cover?(message)
            return unless @na_altgr_masked
            return if Na__InsertPrimatives.Na__AltGrFilter__ChordRepeat?(msg, message)

            Na__InsertPrimatives.Na__AltGrFilter__RestoreChord
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is This a Message a Navigation Gesture Could Be Read From?
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__InputMessage?(message)
        NA_ALTGR_CLIENT_MOUSE.cover?(message) ||
            NA_ALTGR_SINGLE_INPUT.include?(message) ||
            NA_ALTGR_OTHER_POINTER.any? { |range| range.cover?(message) }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is the Chord Being Hidden Actually Held on the Keyboard?
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__ChordDown?(mode)
        return Na__InsertPrimatives.Na__AltGrFilter__Physical?(NA_ALTGR_VK_RMENU) if mode == :altgr

        Na__InsertPrimatives.Na__AltGrFilter__Physical?(NA_ALTGR_VK_CONTROL) &&
            Na__InsertPrimatives.Na__AltGrFilter__Physical?(NA_ALTGR_VK_MENU)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is a Key Down on the Hardware, Whatever the Thread Has Been Told?
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__Physical?(virtual_key)
        (@na_altgr_api[:async].call(virtual_key).to_i & 0x8000) != 0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Clear Ctrl and Alt From the Thread's Key State
    # ------------------------------------------------------------
    # Fiddle reads a byte as a signed char, so every byte is masked to 0..255
    # before its down bit (0x80) is tested. The toggle bit is left alone.
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__HideChord
        api   = @na_altgr_api
        state = @na_altgr_state
        api[:get_state].call(state)

        changed = false
        NA_ALTGR_CHORD_KEYS.each do |virtual_key|
            byte = state[virtual_key] & 0xFF
            next if (byte & 0x80).zero?

            state[virtual_key] = byte & 0x7F
            changed = true
        end

        api[:set_state].call(state) if changed
        @na_altgr_masked   = true
        @na_altgr_cleaned += 1
    end
    # ---------------------------------------------------------------

    # FUNCTION | Clear Ctrl's Bit From a Client Mouse Message's Key Flags
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__ClearControlFlag(msg)
        flags = msg[16] & 0xFF
        msg[16] = flags & ~NA_ALTGR_MK_CONTROL & 0xFF if (flags & NA_ALTGR_MK_CONTROL) != 0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Put Ctrl and Alt Back in the Thread's Key State as the Keyboard Has Them
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__RestoreChord
        api   = @na_altgr_api
        state = @na_altgr_state
        api[:get_state].call(state)

        NA_ALTGR_CHORD_KEYS.each do |virtual_key|
            byte = state[virtual_key] & 0xFF
            state[virtual_key] = Na__InsertPrimatives.Na__AltGrFilter__Physical?(virtual_key) ? (byte | 0x80) : (byte & 0x7F)
        end

        api[:set_state].call(state)
        @na_altgr_masked = false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is This a Held Ctrl or Alt Repeating? (Then It Stays Hidden)
    # ------------------------------------------------------------
    # A held AltGr repeats about thirty times a second. Putting the chord back
    # for each repeat would show it to the next mouse move's neighbours; a
    # repeat is never a shortcut, so it is left hidden. lParam bit 30 is the
    # key's previous state: set on a repeat.
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__ChordRepeat?(msg, message)
        return false unless NA_ALTGR_KEY_DOWNS.include?(message)
        return false unless NA_ALTGR_CHORD_KEYS.include?(msg[16] & 0xFF)

        (msg[24, 4].unpack1('L') & 0x40000000) != 0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Mouse Messages Cleaned Since the Hook Went In (Dev Mode, Checks)
    # ------------------------------------------------------------
    def self.Na__AltGrFilter__CleanedCount
        @na_altgr_cleaned.to_i
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # =============================================================================
    # REGION | Quit Observer
    # =============================================================================

    # CLASS | SketchUp Is Quitting: Take the Hook Out
    # ------------------------------------------------------------
    class AltGrFilterQuitWatch < Sketchup::AppObserver
        def onQuit
            Na__InsertPrimatives.Na__AltGrFilter__Remove
        rescue StandardError
            nil
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # SECTION | Startup: Everywhere Switched On Last Session
    # ------------------------------------------------------------
    # A timer, so the hook goes in once SketchUp's own startup has finished.
    # ------------------------------------------------------------
    if NA_ALTGR_FILTER_WINDOWS && Na__InsertPrimatives.Na__AltGrFilter__Everywhere? && !Na__InsertPrimatives.Na__AltGrFilter__Installed?
        UI.start_timer(0.5, false) { Na__InsertPrimatives.Na__AltGrFilter__Sync rescue nil }
    end
    # ---------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF ALTGR NAVIGATION FILTER
# =============================================================================
