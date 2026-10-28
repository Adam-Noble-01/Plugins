# =============================================================================
# NA INSERT PRIMATIVES - CAMERA PARALLEL DRAWING GUARD
# =============================================================================
#
# FILE       : Na__InsertPrimatives__Camera__ParallelDrawingGuard__.rb
# NAMESPACE  : Na__InsertPrimatives
# MODULE     : ParallelDrawingGuard (prepended on DrawnPlaneTool and DrawnVolumeTool)
# CLASSES    : CameraGuardViewObserver < Sketchup::ViewObserver
#              CameraGuardAppObserver  < Sketchup::AppObserver
#              CameraGuardSceneWatch   (a Pages frame change observer)
# AUTHOR     : Noble Architecture
# PURPOSE    : Hold a parallel (2D) view square to the drawing while Drawn Plane
#              or Drawn Volume is in use, against SketchUp 2027's Ctrl+Alt
#              touchpad orbit, which AltGr sets off on Windows
# CREATED    : 2026 (5.2.12)
#
# THE PROBLEM (SKETCHUP 2027):
# - 2027 brought the Mac's touchpad navigation to Windows: hold Ctrl+Alt and
#   move the cursor (a one-finger gesture) to orbit, add Shift to pan. Windows
#   reports AltGr as Ctrl+Alt, so the AltGr shortcut that starts one of these
#   tools orbits the camera as soon as the hand moves with AltGr still down,
#   and a plan or elevation is no longer square to the plane being drawn on.
#
# WHAT IS HELD:
# - The camera's ORIENTATION: its direction and its screen-up, so it cannot
#   turn about any axis, roll included. Its position (pan) and its parallel
#   height (zoom) are followed and never undone, so X/Y panning in the plane
#   of the screen and the mouse wheel behave exactly as they did.
# - Only while one of the two tools is the model's tool (or is paused under one
#   of SketchUp's camera tools) AND the camera is parallel AND popup > 2D Orbit
#   Lock is on (the default). A perspective camera is never touched: going to
#   perspective forgets the held view, and coming back to parallel holds the
#   view as it is then, never a stale one.
#
# WHICH TURNS ARE UNDONE:
#   middle mouse button down   kept: the deliberate orbit, whatever else is held
#   a scene arriving           kept: its camera is the point of selecting it
#   a camera tool AltGr began  UNDONE until it hands the view back
#   Ctrl+Alt (AltGr) held      UNDONE: the 2027 touchpad orbit
#   anything else              kept: a standard view (Ctrl+1, Shift+arrows),
#                              Camera > Previous, the toolbar Orbit tool
#   A kept turn becomes the orientation held from then on, so after a
#   middle-mouse orbit the guard holds the view the orbit left.
#
# HOW, AND WHAT THE RUBY API ALLOWS:
# - Nothing in the Ruby API can veto a native orbit before it happens. A
#   tool's onMouseMove has no return value that stops navigation, and
#   implementing Tool#onMButtonDown REPLACES the middle-mouse orbit (the API
#   documents it as the way to make the middle button do something else), so
#   the guard implements neither.
# - PREVENTION (5.2.13, Windows): while this guard holds a view it switches
#   on the AltGr filter (Camera__AltGrFilter__), which shows SketchUp's mouse
#   handling Ctrl and Alt as up while the chord is held, and its keyboard
#   handling the truth. The 2027 orbit and pan never start; AltGr shortcuts
#   still fire. 5.2.12's correction alone was seen as a jerk.
# - CORRECTION, the backstop (a Mac, or a gesture the filter cannot hide): a
#   ViewObserver on the tool's own view hears every camera change, and an
#   unwanted turn is undone inside that callback by writing the held camera
#   back. A flag keeps the write from being judged again. No operation is
#   opened, so nothing reaches the undo stack (camera moves never do). One
#   deferred re-check follows each undo, in case SketchUp writes its camera
#   again after telling its observers.
# - The key that completes Ctrl+Alt is also answered true from onKeyDown ("do
#   not process"), in case 2027 arms its navigation from key events. Key-ups
#   are never swallowed, so SketchUp cannot miss the end of a gesture.
#
# TELLING THE MIDDLE BUTTON FROM ALTGR:
# - Windows: the key and button state itself, read through user32 with Fiddle
#   (GetKeyState, which moves with the input SketchUp is handling, or
#   GetAsyncKeyState, the hardware this instant). Read only: nothing is hooked,
#   remapped or written, and no Windows setting is touched. Fiddle ships with
#   SketchUp's own Ruby (2027: Ruby 3.4.9 with fiddle 1.1.6).
# - Elsewhere, or if user32 cannot be read: what the tool's own key and mouse
#   events last said, plus the modifier masks in a key event's flags from 2027
#   (until 2027 they carried the Windows scan code). A pause under a camera
#   tool with no Ctrl+Alt seen counts as deliberate.
#
# MODELS AND RELOADS:
# - Each engaged tool has its own session, observing ITS model's view only, so
#   another model in a tab or a floating window (2027) is never touched.
#   AppObserver#onCloseModel (2027) lets go of a closed model without touching
#   it. Engaging first releases any session left on the same model, so starting
#   a tool again never adds a second observer.
# - Sessions live in a module variable that survives Reload Plugin Data. The
#   reloader drops our running tool first, which releases its session, and the
#   load-time sweep below releases any session whose tool is no longer running.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../02__AppData/Na__InsertPrimatives__AppData__ConfigLoader__'
require_relative '../02__AppData/Na__InsertPrimatives__AppData__ToolOptions__'
require_relative 'Na__InsertPrimatives__Camera__AltGrFilter__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Guard Constants and State
    # -----------------------------------------------------------------------------

    NA_CAMERA_GUARD_MODE_KEYS   = [:drawn_plane, :drawn_volume].freeze          # <-- A subclass with a key of its own (Staircase) is not guarded
    NA_CAMERA_GUARD_OPTION      = 'drawn_orbit_lock'.freeze                     # <-- Popup > 2D Orbit Lock, declared in ToolOptions
    NA_CAMERA_GUARD_TURN_SIN    = 1.0e-7                                        # <-- Sine of the smallest turn counted (about 0.00001 deg); a pan or a zoom turns no axis
    NA_CAMERA_GUARD_SCENE_S     = 0.35                                          # <-- A turn this soon after a scene frame is that scene arriving
    NA_CAMERA_GUARD_GRACE_S     = 0.25                                          # <-- Without user32: Ctrl+Alt counts as held this long after it was last seen
    NA_CAMERA_GUARD_ALT_FRESH_S = 2.0                                           # <-- Without user32: an ALT whose key-up never came is forgotten (a held key repeats)

    NA_CAMERA_GUARD_WINDOWS     = (RUBY_PLATFORM =~ /mswin|mingw|cygwin/) ? true : false

    # Windows virtual-key codes, read through user32.
    NA_CAMERA_GUARD_VK_MBUTTON  = 0x04
    NA_CAMERA_GUARD_VK_CONTROL  = 0x11
    NA_CAMERA_GUARD_VK_MENU     = 0x12                                          # <-- ALT. AltGr sets this AND VK_CONTROL

    # The chord as the tool's own events name it. ALT_MODIFIER_KEY is ALT on
    # Windows and Command on a Mac, which is the 2027 gesture's second key on
    # each ("Control+Alt", "CMD on MacOS"). Ctrl has a mouse bit on Windows
    # only (MK_CONTROL); a Mac reports it through key events alone.
    NA_CAMERA_GUARD_CTRL_KEY    = defined?(VK_CONTROL)        ? VK_CONTROL        : 17
    NA_CAMERA_GUARD_ALT_KEY     = defined?(ALT_MODIFIER_KEY)  ? ALT_MODIFIER_KEY  : 18
    NA_CAMERA_GUARD_ALT_MASK    = defined?(ALT_MODIFIER_MASK) ? ALT_MODIFIER_MASK : 32
    NA_CAMERA_GUARD_CTRL_MASK   = NA_CAMERA_GUARD_WINDOWS ? (defined?(COPY_MODIFIER_MASK) ? COPY_MODIFIER_MASK : 8) : nil

    # Kept across Reload Plugin Data, so a session already on a view is found
    # and released rather than doubled. The write flag is cleared on every
    # load: a load is never part of a camera write.
    @na_camera_guard_sessions     = []  unless defined?(@na_camera_guard_sessions)
    @na_camera_guard_readers      = nil unless defined?(@na_camera_guard_readers)
    @na_camera_guard_app_observer = nil unless defined?(@na_camera_guard_app_observer)
    @na_camera_guard_scene_watch  = nil unless defined?(@na_camera_guard_scene_watch)
    @na_camera_guard_scene_id     = nil unless defined?(@na_camera_guard_scene_id)
    @na_camera_guard_scene_at     = nil unless defined?(@na_camera_guard_scene_at)
    @na_camera_guard_writing      = false

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Sessions — One per Engaged Tool, on That Tool's Own View
    # -----------------------------------------------------------------------------

    # FUNCTION | Start Guarding the Active Model's View for a Tool; Returns the Session
    # ------------------------------------------------------------
    # Called from the tool's activate, when Sketchup.active_model is the model
    # the tool was selected into. The session is a plain hash, as the tools'
    # own records are; the observer holds it, so a callback needs no lookup.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__Engage(tool)
        model = Sketchup.active_model
        view  = model ? model.active_view : nil
        return nil unless view

        Na__InsertPrimatives.Na__CameraGuard__Sweep(model)                     # <-- Whatever a missed deactivate or a closed model left goes first

        session = {
            :tool      => tool,
            :model     => model,
            :view      => view,
            :observer  => nil,
            :live      => true,
            :held      => nil,                                                # <-- The camera held: eye, target, up, axes, parallel height
            :paused_by => nil,                                                # <-- :middle, :chord or :other while a camera tool has the view
            :ctrl      => false,                                              # <-- The chord as the tool's own events saw it (no user32)
            :alt_at    => nil,
            :chord_at  => nil,
            :refused   => 0,                                                  # <-- Turns undone since the last report
            :undone    => nil,                                                # <-- The last turn undone, in case a scene turns out to own it
            :check_due => false,
            :swallowed => false
        }

        observer = CameraGuardViewObserver.new(session)
        view.add_observer(observer)
        session[:observer] = observer
        @na_camera_guard_sessions << session

        Na__InsertPrimatives.Na__CameraGuard__WatchApp
        Na__InsertPrimatives.Na__CameraGuard__WatchScenes

        camera = view.camera
        session[:held] = Na__InsertPrimatives.Na__CameraGuard__Capture(camera) if Na__InsertPrimatives.Na__CameraGuard__Holding?(camera)

        Na__InsertPrimatives.Na__Debug__Puts(
            "CAMERA GUARD: on for #{Na__InsertPrimatives.Na__CameraGuard__ToolName(tool)} — " \
            "#{session[:held] ? 'parallel view held' : 'standing by until the view is parallel'} " \
            "(keys read #{Na__InsertPrimatives.Na__CameraGuard__KeyReaders ? 'from user32' : 'from tool events'})"
        )
        Na__InsertPrimatives.Na__CameraGuard__RefreshFilter
        session
    rescue StandardError => error
        Na__InsertPrimatives.Na__CameraGuard__Release(session) if session    # <-- Never leave a half-made session watching a view
        Na__InsertPrimatives.Na__Debug__Puts "CAMERA GUARD: not engaged — #{error.message}"
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Stop Guarding: Take the Observer Off the View and Drop the Session
    # ------------------------------------------------------------
    def self.Na__CameraGuard__Release(session)
        return nil unless session

        if session[:live] && session[:view] && session[:observer]
            begin
                session[:view].remove_observer(session[:observer])
            rescue StandardError
                nil                                                           # <-- A closed model's view is gone with it
            end
        end

        Na__InsertPrimatives.Na__CameraGuard__Report(session, 'off')
        Na__InsertPrimatives.Na__CameraGuard__Forget(session)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Drop a Session Without Touching Its View (a Model Already Gone)
    # ------------------------------------------------------------
    def self.Na__CameraGuard__Forget(session)
        session[:live]     = false                                            # <-- An observer that somehow stayed on reads this and does nothing
        session[:observer] = nil
        @na_camera_guard_sessions.delete_if { |other| other.equal?(session) }
        Na__InsertPrimatives.Na__CameraGuard__UnwatchScenes if @na_camera_guard_sessions.empty?
        Na__InsertPrimatives.Na__CameraGuard__RefreshFilter
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Tell the AltGr Filter Whether a Guarded Tool Wants It Now
    # ------------------------------------------------------------
    # Wanted while the ACTIVE model has a guarded tool holding a parallel view
    # with the lock on. The filter's hook covers SketchUp's whole UI thread,
    # so another tab without a guarded tool switches it off (onActivateModel).
    # Called whenever one of those facts can change, never per mouse move.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__RefreshFilter
        return false unless Na__InsertPrimatives.respond_to?(:Na__AltGrFilter__SetToolScope)

        model   = Sketchup.active_model
        session = model && @na_camera_guard_sessions.find do |candidate|
            candidate[:live] && Na__InsertPrimatives.Na__CameraGuard__SameModel?(candidate[:model], model)
        end
        wanted = session ? Na__InsertPrimatives.Na__CameraGuard__Holding?(session[:view].camera) : false

        Na__InsertPrimatives.Na__AltGrFilter__SetToolScope(wanted)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | An Option Was Switched From the Popup: the Lock Takes Effect at Once
    # ------------------------------------------------------------
    # Switched off, nothing is held; switched on, the view as it is now is
    # held. Either way the filter follows straight away, not at the next
    # camera move.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__OptionToggled(session, option_id)
        return nil unless session && session[:live] && option_id.to_s == NA_CAMERA_GUARD_OPTION

        camera = session[:view].camera
        session[:held] = Na__InsertPrimatives.Na__CameraGuard__Holding?(camera) ? Na__InsertPrimatives.Na__CameraGuard__Capture(camera) : nil
        Na__InsertPrimatives.Na__CameraGuard__RefreshFilter
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Release the Sessions on a Model, and Forget Those on Dead Models
    # ------------------------------------------------------------
    def self.Na__CameraGuard__Sweep(model)
        @na_camera_guard_sessions.dup.each do |session|
            other = session[:model]

            if Na__InsertPrimatives.Na__CameraGuard__SameModel?(other, model)
                Na__InsertPrimatives.Na__CameraGuard__Release(session)
            elsif other.respond_to?(:valid?) && !other.valid?
                Na__InsertPrimatives.Na__CameraGuard__Forget(session)
            end
        end
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Model Was Closed (SketchUp 2027 Tabs): Forget Its Sessions
    # ------------------------------------------------------------
    def self.Na__CameraGuard__ModelClosed(model)
        @na_camera_guard_sessions.dup.each do |session|
            Na__InsertPrimatives.Na__CameraGuard__Forget(session) if Na__InsertPrimatives.Na__CameraGuard__SameModel?(session[:model], model)
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Are Two Model Handles the Same Open Model?
    # ------------------------------------------------------------
    # Identity first, which is what SketchUp hands back for one model. The
    # guid is the fallback, so a second Ruby wrapper for the same model can
    # never make the guard ignore its own view.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__SameModel?(a, b)
        return true  if a.equal?(b)
        return false unless a && b && a.respond_to?(:guid) && b.respond_to?(:guid)

        a.guid == b.guid
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Release Every Session Whose Tool Is No Longer Running (Load Time)
    # ------------------------------------------------------------
    # After Reload Plugin Data. Run from the menu, so no camera tool is paused
    # over a tool at that moment and Tools#active_tool is the honest answer.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__SweepStale
        @na_camera_guard_sessions.dup.each do |session|
            running = begin
                session[:model].tools.active_tool
            rescue StandardError
                nil
            end

            Na__InsertPrimatives.Na__CameraGuard__Release(session) unless running.equal?(session[:tool])
        end
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Live Sessions (for Checks)
    # ------------------------------------------------------------
    def self.Na__CameraGuard__Sessions
        @na_camera_guard_sessions.dup
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Held Camera
    # -----------------------------------------------------------------------------

    # FUNCTION | Is This a View the Guard Holds? (Parallel, With the Lock On)
    # ------------------------------------------------------------
    def self.Na__CameraGuard__Holding?(camera)
        return false unless camera
        return false if camera.perspective?

        Na__InsertPrimatives.Na__ToolOptions__Enabled?(NA_CAMERA_GUARD_OPTION)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Everything Needed to Put a Camera Back Exactly
    # ------------------------------------------------------------
    # The axes are kept to compare against: yaxis is the screen-up made square
    # to the direction, so a roll shows even where the stored up vector would
    # not. Eye, target and up are what Camera#set takes back.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__Capture(camera)
        {
            :eye    => camera.eye,
            :target => camera.target,
            :up     => camera.up,
            :zaxis  => camera.zaxis,
            :yaxis  => camera.yaxis,
            :height => camera.perspective? ? nil : camera.height
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Has the Camera Turned Away From the Held One, About Any Axis?
    # ------------------------------------------------------------
    # Direction covers a turn left, right, up or down; screen-up covers a roll.
    # A pan moves eye and target together and a parallel zoom changes the
    # height, so neither turns an axis, and neither is ever mistaken for one.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__Turned?(held, camera)
        Na__InsertPrimatives.Na__CameraGuard__AxisMoved?(held[:zaxis], camera.zaxis) ||
            Na__InsertPrimatives.Na__CameraGuard__AxisMoved?(held[:yaxis], camera.yaxis)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Do Two Axes Differ by More Than the Turn Tolerance?
    # ------------------------------------------------------------
    # The cross product's length is the sine of the angle between unit
    # vectors, which stays exact near zero where an arccosine does not; the
    # dot product catches a half turn, where the sine is back to zero.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__AxisMoved?(was, now)
        a = was.normalize
        b = now.normalize
        a.dot(b) <= 0.0 || a.cross(b).length.to_f > NA_CAMERA_GUARD_TURN_SIN
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Far the Camera Has Turned, in Degrees (for the Dev Mode Log)
    # ------------------------------------------------------------
    def self.Na__CameraGuard__TurnDegrees(held, camera)
        [[held[:zaxis], camera.zaxis], [held[:yaxis], camera.yaxis]].map do |was, now|
            cosine = [[was.normalize.dot(now.normalize), 1.0].min, -1.0].max
            Math.acos(cosine) * 180.0 / Math::PI
        end.max
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does a View's Camera Already Match a Held One?
    # ------------------------------------------------------------
    def self.Na__CameraGuard__Matches?(camera, held)
        return false if Na__InsertPrimatives.Na__CameraGuard__Turned?(held, camera)
        return false if camera.eye.distance(held[:eye]).to_f > 1.0e-6
        return true  unless held[:height] && !camera.perspective?

        (camera.height.to_f - held[:height].to_f).abs <= 1.0e-6
    end
    # ---------------------------------------------------------------

    # FUNCTION | Write a Held Camera Into a View, Without Judging the Echo
    # ------------------------------------------------------------
    # In place on the view's own camera, which is live in SketchUp, then by
    # assignment only if the view did not take it (a view handing out copies
    # would not). Every change this causes calls onViewChanged again, and the
    # flag makes those calls return at once: no recursion, no second write.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__Apply(view, held)
        @na_camera_guard_writing = true

        camera = view.camera
        camera.set(held[:eye], held[:target], held[:up])
        camera.height = held[:height] if held[:height] && !camera.perspective?
        view.camera   = camera unless Na__InsertPrimatives.Na__CameraGuard__Matches?(view.camera, held)
        true
    ensure
        @na_camera_guard_writing = false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Judging a Camera Change
    # -----------------------------------------------------------------------------

    # FUNCTION | The View Changed: Follow It, Keep It, or Put the Held View Back
    # ------------------------------------------------------------
    # Called from the observer on every camera change, so it is cheap: one
    # camera read and two vector comparisons, a few more only when it turned.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__ViewChanged(session, view)
        return if @na_camera_guard_writing                                    # <-- Our own write, echoing back
        return unless session && session[:live]
        return if view.respond_to?(:model) && !Na__InsertPrimatives.Na__CameraGuard__SameModel?(view.model, session[:model])  # <-- Never another model's view, whatever is notified

        camera = view.camera

        unless Na__InsertPrimatives.Na__CameraGuard__Holding?(camera)
            if session[:held]
                Na__InsertPrimatives.Na__Debug__Puts 'CAMERA GUARD: perspective view (or the lock is off) — standing by'
                session[:held] = nil                                          # <-- Nothing stale to come back to
                Na__InsertPrimatives.Na__CameraGuard__RefreshFilter           # <-- Perspective navigates as SketchUp ships it
            end
            return
        end

        held = session[:held]

        if held.nil? || !Na__InsertPrimatives.Na__CameraGuard__Turned?(held, camera)
            session[:held] = Na__InsertPrimatives.Na__CameraGuard__Capture(camera)   # <-- A pan, a zoom, a resize: followed, never undone
            if held.nil?
                Na__InsertPrimatives.Na__Debug__Puts 'CAMERA GUARD: parallel view — holding it'
                Na__InsertPrimatives.Na__CameraGuard__RefreshFilter
            end
            return
        end

        if Na__InsertPrimatives.Na__CameraGuard__TurnAllowed?(session)
            Na__InsertPrimatives.Na__CameraGuard__Report(session, 'turn kept')
            session[:held] = Na__InsertPrimatives.Na__CameraGuard__Capture(camera)   # <-- A deliberate turn: the new view is the one to hold
            return
        end

        Na__InsertPrimatives.Na__CameraGuard__Refuse(session, view, held, camera)
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "CAMERA GUARD: #{error.message}"
    end
    # ---------------------------------------------------------------

    # FUNCTION | May This Turn Stand?
    # ------------------------------------------------------------
    # The table in the header, top to bottom. The middle button wins over
    # everything, so a deliberate orbit made with AltGr down still orbits.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__TurnAllowed?(session)
        return true  if Na__InsertPrimatives.Na__CameraGuard__MiddleDown?
        return true  if Na__InsertPrimatives.Na__CameraGuard__SceneMoving?
        return false if session[:paused_by] == :chord

        !Na__InsertPrimatives.Na__CameraGuard__ChordHeld?(session)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Undo an Unwanted Turn: the Whole Held Camera Goes Back
    # ------------------------------------------------------------
    # The whole camera, not just its axes: an orbit swings the eye round its
    # pivot, so the eye it leaves is not a pan anybody made. The pan and zoom
    # put back are the ones followed up to the turn, so nothing deliberate is
    # lost. The turn undone is remembered for a moment, for a scene whose
    # frame report arrives just after its camera (SceneFrame).
    # ------------------------------------------------------------
    def self.Na__CameraGuard__Refuse(session, view, held, camera)
        if session[:refused].zero?
            Na__InsertPrimatives.Na__Debug__Puts format(
                'CAMERA GUARD: orbit refused (%.2f deg, Ctrl+Alt / AltGr, middle button up) — view held',
                Na__InsertPrimatives.Na__CameraGuard__TurnDegrees(held, camera)
            )
        end

        session[:undone]   = { :camera => Na__InsertPrimatives.Na__CameraGuard__Capture(camera), :at => Na__InsertPrimatives.Na__CameraGuard__Now }
        session[:refused] += 1

        Na__InsertPrimatives.Na__CameraGuard__Apply(view, held)
        Na__InsertPrimatives.Na__CameraGuard__ScheduleCheck(session, view)
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Look Again on the Next Tick, Once per Burst
    # ------------------------------------------------------------
    # If SketchUp writes its camera again after telling its observers, the
    # turn is back without a second notice; this catches it and judges it the
    # same way, middle button and all, so a held view never stays turned.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__ScheduleCheck(session, view)
        return false if session[:check_due]

        session[:check_due] = true
        UI.start_timer(0, false) do
            session[:check_due] = false
            Na__InsertPrimatives.Na__CameraGuard__ViewChanged(session, view) if session[:live]
        end
        true
    rescue StandardError
        session[:check_due] = false
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Log How Many Turns Were Undone, Then Start Counting Again
    # ------------------------------------------------------------
    def self.Na__CameraGuard__Report(session, moment)
        count = session[:refused].to_i
        return if count.zero?

        Na__InsertPrimatives.Na__Debug__Puts "CAMERA GUARD: #{moment} — held the view against #{count} orbit step#{count == 1 ? '' : 's'}"
        session[:refused] = 0
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Tool's Name, for the Log
    # ------------------------------------------------------------
    def self.Na__CameraGuard__ToolName(tool)
        return tool.na_drawn__tool_title if tool.respond_to?(:na_drawn__tool_title)

        tool.class.name.to_s.split('::').last
    rescue StandardError
        'a tool'
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | A Camera Tool Pausing the Drawing Tool (Middle Mouse, AltGr, Toolbar)
    # -----------------------------------------------------------------------------

    # FUNCTION | The Tool Was Paused: Say What Started It, While It Can Be Seen
    # ------------------------------------------------------------
    # At this moment the input that started the camera tool is still down: the
    # middle button for its orbit, Ctrl+Alt for the 2027 gesture. Anything else
    # (Orbit, Pan or Zoom from a toolbar) is a command and keeps its turns.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__Paused(session, view)
        return nil unless session && session[:live]

        session[:paused_by] =
            if Na__InsertPrimatives.Na__CameraGuard__MiddleDown?
                :middle
            elsif Na__InsertPrimatives.Na__CameraGuard__ChordHeld?(session)
                :chord
            else
                :other
            end

        Na__InsertPrimatives.Na__CameraGuard__LogPause(session)
        session[:paused_by]
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Tool Is Back: Undo What a Ctrl+Alt Pause Let Through, or Hold the New View
    # ------------------------------------------------------------
    # After a middle-mouse orbit the view it left is the one to hold, the
    # middle-button exception made good. After a pause AltGr began, any turn
    # still showing goes back, whatever the keys are doing now. The tracked
    # keys start again: a key-up the camera tool took must not stick.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__Resumed(session, view)
        return nil unless session && session[:live]

        paused_by           = session[:paused_by]
        session[:paused_by] = nil
        session[:ctrl]      = false
        session[:alt_at]    = nil
        session[:chord_at]  = nil

        camera = view.camera
        unless Na__InsertPrimatives.Na__CameraGuard__Holding?(camera)
            session[:held] = nil
            Na__InsertPrimatives.Na__CameraGuard__RefreshFilter
            return nil
        end

        held = session[:held]
        if held && paused_by == :chord && Na__InsertPrimatives.Na__CameraGuard__Turned?(held, camera) &&
           !Na__InsertPrimatives.Na__CameraGuard__SceneMoving?
            Na__InsertPrimatives.Na__CameraGuard__Refuse(session, view, held, camera)
        else
            session[:held] = Na__InsertPrimatives.Na__CameraGuard__Capture(camera)
        end

        Na__InsertPrimatives.Na__CameraGuard__RefreshFilter
        Na__InsertPrimatives.Na__CameraGuard__Report(session, "resumed after #{paused_by || 'a pause'}")
        paused_by
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Dev Mode: Name the Camera Tool That Paused Us, a Tick Later
    # ------------------------------------------------------------
    # suspend runs before the camera tool is made active, so its id is read on
    # the next tick. Only with Dev Mode on: it answers whether 2027's Ctrl+Alt
    # gesture runs through a camera tool at all, which nothing documents.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__LogPause(session)
        return unless Na__InsertPrimatives.respond_to?(:Na__Config__DevMode?) && Na__InsertPrimatives.Na__Config__DevMode?

        reason = { :middle => 'middle mouse: turns kept', :chord => 'Ctrl+Alt / AltGr: turns undone', :other => 'a command: turns kept' }[session[:paused_by]]
        UI.start_timer(0, false) do
            begin
                tools = session[:model].tools
                Na__InsertPrimatives.Na__Debug__Puts "CAMERA GUARD: paused under #{tools.active_tool_name} (#{tools.active_tool_id}) — #{reason}"
            rescue StandardError
                nil
            end
        end
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Keys and Buttons — Read From Windows, or Tracked From the Tool
    # -----------------------------------------------------------------------------

    # FUNCTION | A Monotonic Clock, in Seconds
    # ------------------------------------------------------------
    def self.Na__CameraGuard__Now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    # ---------------------------------------------------------------

    # FUNCTION | user32's Two Key-State Readers, Loaded Once; false Where There Are None
    # ------------------------------------------------------------
    def self.Na__CameraGuard__KeyReaders
        return @na_camera_guard_readers unless @na_camera_guard_readers.nil?

        @na_camera_guard_readers =
            if NA_CAMERA_GUARD_WINDOWS
                require 'fiddle'
                user32 = Fiddle::Handle.new('user32')
                [
                    Fiddle::Function.new(user32['GetKeyState'],      [Fiddle::TYPE_INT], Fiddle::TYPE_SHORT),
                    Fiddle::Function.new(user32['GetAsyncKeyState'], [Fiddle::TYPE_INT], Fiddle::TYPE_SHORT)
                ]
            else
                false
            end
    rescue LoadError, StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "CAMERA GUARD: user32 cannot be read (#{error.message}) — keys tracked from the tool's events"
        @na_camera_guard_readers = false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is a Key or Mouse Button Down? true / false, or nil When Nothing Can Say
    # ------------------------------------------------------------
    # Down if either reader says so: the event-synchronous one is right for
    # the input being handled, the hardware one if a message went elsewhere.
    # The high bit is the down bit, whichever way round the short is signed.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__KeyDown?(virtual_key)
        readers = Na__InsertPrimatives.Na__CameraGuard__KeyReaders
        return nil unless readers

        readers.any? { |reader| (reader.call(virtual_key).to_i & 0x8000) != 0 }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is the Middle Mouse Button Physically Down?
    # ------------------------------------------------------------
    # false where it cannot be read. A Mac's pause is then judged by the keys
    # alone (Paused), which is the safe side: no Ctrl+Alt, no refusal.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__MiddleDown?
        Na__InsertPrimatives.Na__CameraGuard__KeyDown?(NA_CAMERA_GUARD_VK_MBUTTON) == true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is the Gesture's Chord Held: Ctrl+Alt, Which Is What AltGr Is?
    # ------------------------------------------------------------
    def self.Na__CameraGuard__ChordHeld?(session)
        ctrl = Na__InsertPrimatives.Na__CameraGuard__KeyDown?(NA_CAMERA_GUARD_VK_CONTROL)
        alt  = Na__InsertPrimatives.Na__CameraGuard__KeyDown?(NA_CAMERA_GUARD_VK_MENU)
        return (ctrl && alt) ? true : false unless ctrl.nil? || alt.nil?

        Na__InsertPrimatives.Na__CameraGuard__TrackedChord?(session)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Chord as the Tool's Own Events Last Saw It (No user32)
    # ------------------------------------------------------------
    # Held a short grace past the last sighting: a camera tool that paused us
    # takes the key-ups, and an orbit step can be queued behind the release.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__TrackedChord?(session)
        return false unless session

        now = Na__InsertPrimatives.Na__CameraGuard__Now
        alt = session[:alt_at] && (now - session[:alt_at]) < NA_CAMERA_GUARD_ALT_FRESH_S

        if session[:ctrl] && alt
            session[:chord_at] = now
            return true
        end

        session[:chord_at] ? (now - session[:chord_at]) < NA_CAMERA_GUARD_GRACE_S : false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Are a Key Event's Flags the Modifier Masks? (SketchUp 2027 On)
    # ------------------------------------------------------------
    # 2027.0 fixed onKeyDown / onKeyUp flags "containing incorrect modifier
    # keys": before it, on Windows, they were the keystroke's lParam bits
    # (scan code, repeat and transition), so a mask test read noise.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__KeyFlagsTrusted?
        Sketchup.version.to_i >= 27
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Key Went Down in a Guarded Tool: Track the Chord; Swallow the Key That Completes It?
    # ------------------------------------------------------------
    # Returns true for the Ctrl or ALT that completes Ctrl+Alt while the view
    # is a held parallel one. The tool's own onKeyDown has already run, so its
    # CTRL vertex snap still hears the key; only SketchUp is told to leave it.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__KeyPressed(session, key, flags)
        return false unless session && session[:live]

        now              = Na__InsertPrimatives.Na__CameraGuard__Now
        session[:ctrl]   = true if key == NA_CAMERA_GUARD_CTRL_KEY
        session[:alt_at] = now  if key == NA_CAMERA_GUARD_ALT_KEY

        if Na__InsertPrimatives.Na__CameraGuard__KeyFlagsTrusted?
            bits             = flags.to_i
            session[:ctrl]   = true if NA_CAMERA_GUARD_CTRL_MASK && (bits & NA_CAMERA_GUARD_CTRL_MASK) != 0
            session[:alt_at] = now  if (bits & NA_CAMERA_GUARD_ALT_MASK) != 0
        end

        return false unless key == NA_CAMERA_GUARD_CTRL_KEY || key == NA_CAMERA_GUARD_ALT_KEY
        return false unless Na__InsertPrimatives.Na__CameraGuard__ChordHeld?(session)
        return false unless Na__InsertPrimatives.Na__CameraGuard__Holding?(session[:view].camera)

        Na__InsertPrimatives.Na__AltGrFilter__ChordPressed if Na__InsertPrimatives.respond_to?(:Na__AltGrFilter__ChordPressed)

        unless session[:swallowed]
            session[:swallowed] = true
            Na__InsertPrimatives.Na__Debug__Puts 'CAMERA GUARD: Ctrl+Alt reached the tool — answered true, so SketchUp is asked not to act on it'
        end
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Key Came Up in a Guarded Tool
    # ------------------------------------------------------------
    def self.Na__CameraGuard__KeyReleased(session, key)
        return unless session

        session[:ctrl]   = false if key == NA_CAMERA_GUARD_CTRL_KEY
        session[:alt_at] = nil   if key == NA_CAMERA_GUARD_ALT_KEY
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Mouse Event's Flags: Ctrl Set and Cleared, ALT Only Ever Set
    # ------------------------------------------------------------
    # MK_CONTROL is a genuine Windows mouse bit, so its absence means Ctrl is
    # up. ALT has no such bit; a missing one is no evidence (DrawnToolShared's
    # SHIFT note tells how a missing ALT bit wiped a key event's news).
    # ------------------------------------------------------------
    def self.Na__CameraGuard__MouseFlags(session, flags)
        return unless session

        Na__InsertPrimatives.Na__AltGrFilter__RetireIfDue if Na__InsertPrimatives.respond_to?(:Na__AltGrFilter__RetireIfDue)
        bits             = flags.to_i
        session[:ctrl]   = (bits & NA_CAMERA_GUARD_CTRL_MASK) != 0 if NA_CAMERA_GUARD_CTRL_MASK
        session[:alt_at] = Na__InsertPrimatives.Na__CameraGuard__Now if (bits & NA_CAMERA_GUARD_ALT_MASK) != 0
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Scenes and Closed Models
    # -----------------------------------------------------------------------------

    # FUNCTION | Is a Scene Arriving Right Now?
    # ------------------------------------------------------------
    def self.Na__CameraGuard__SceneMoving?
        at = @na_camera_guard_scene_at
        return false unless at

        elapsed = Na__InsertPrimatives.Na__CameraGuard__Now - at
        elapsed >= 0.0 && elapsed < NA_CAMERA_GUARD_SCENE_S
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Scene Frame Was Set Up: Its Turns Are Deliberate
    # ------------------------------------------------------------
    # frameChange is called after a frame's camera is set and before it is
    # shown, so a scene chosen with AltGr down (a NaKeys scene, say) has had
    # its first or only camera undone already. That turn goes back now, still
    # before the frame is drawn, and the scene's camera becomes the one held.
    # ------------------------------------------------------------
    def self.Na__CameraGuard__SceneFrame
        now = Na__InsertPrimatives.Na__CameraGuard__Now
        @na_camera_guard_scene_at = now

        @na_camera_guard_sessions.each do |session|
            undone = session[:undone]
            next unless session[:live] && undone && (now - undone[:at]) < NA_CAMERA_GUARD_SCENE_S

            session[:undone] = nil
            Na__InsertPrimatives.Na__CameraGuard__Apply(session[:view], undone[:camera])
            session[:held]    = undone[:camera]
            session[:refused] = [session[:refused].to_i - 1, 0].max
            Na__InsertPrimatives.Na__Debug__Puts 'CAMERA GUARD: that turn was a scene arriving — the scene keeps it'
        end
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "CAMERA GUARD: scene frame — #{error.message}"
    end
    # ---------------------------------------------------------------

    # FUNCTION | Listen for Scene Frames While Any Session Is Live
    # ------------------------------------------------------------
    def self.Na__CameraGuard__WatchScenes
        return true if @na_camera_guard_scene_id
        return false unless defined?(Sketchup::Pages) && Sketchup::Pages.respond_to?(:add_frame_change_observer)

        @na_camera_guard_scene_watch ||= CameraGuardSceneWatch.new
        @na_camera_guard_scene_id = Sketchup::Pages.add_frame_change_observer(@na_camera_guard_scene_watch)
        true
    rescue StandardError => error
        @na_camera_guard_scene_id = nil
        Na__InsertPrimatives.Na__Debug__Puts "CAMERA GUARD: scene frames not watched — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Stop Listening for Scene Frames
    # ------------------------------------------------------------
    def self.Na__CameraGuard__UnwatchScenes
        id = @na_camera_guard_scene_id
        @na_camera_guard_scene_id = nil
        Sketchup::Pages.remove_frame_change_observer(id) if id
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Hear About Closed Models (Installed Once, Kept Across Reloads)
    # ------------------------------------------------------------
    def self.Na__CameraGuard__WatchApp
        return true if @na_camera_guard_app_observer

        observer = CameraGuardAppObserver.new
        Sketchup.add_observer(observer)
        @na_camera_guard_app_observer = observer
        true
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "CAMERA GUARD: closed models not watched — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # =============================================================================
    # REGION | Observer Classes
    # =============================================================================
    # Every callback forwards and never raises: an exception inside an observer
    # is swallowed by SketchUp and can silence the observer from then on.

    # CLASS | The Guarded View's Camera Changed
    # ------------------------------------------------------------
    class CameraGuardViewObserver < Sketchup::ViewObserver
        def initialize(session)
            @na_session = session
        end

        def onViewChanged(view)
            Na__InsertPrimatives.Na__CameraGuard__ViewChanged(@na_session, view)
        rescue StandardError
            nil
        end
    end
    # ---------------------------------------------------------------

    # CLASS | A Model Was Closed (SketchUp 2027 Tabs and Floating Windows)
    # ------------------------------------------------------------
    class CameraGuardAppObserver < Sketchup::AppObserver
        def onCloseModel(model)
            Na__InsertPrimatives.Na__CameraGuard__ModelClosed(model)
        rescue StandardError
            nil
        end

        def onActivateModel(_model)                                           # <-- Another tab: the AltGr filter follows the model in front
            Na__InsertPrimatives.Na__CameraGuard__RefreshFilter
        rescue StandardError
            nil
        end
    end
    # ---------------------------------------------------------------

    # CLASS | A Scene Frame Is About to Be Shown
    # ------------------------------------------------------------
    class CameraGuardSceneWatch
        def frameChange(_from_scene, _to_scene, _percent_done)
            Na__InsertPrimatives.Na__CameraGuard__SceneFrame
        rescue StandardError
            nil
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # =============================================================================
    # MODULE | Parallel Drawing Guard — Prepended on the Two Guarded Tools
    # =============================================================================
    # Prepended rather than included so it runs ahead of whatever activate,
    # suspend, resume and key handlers the tool takes from its mixins, the way
    # RightClickPopupPersist is. A subclass that names its own mode key
    # (DrawnStairTool < DrawnVolumeTool) passes straight through to the tool.

    module ParallelDrawingGuard

        # ACTIVATE | Start the Tool, Then Hold Its View
        # ------------------------------------------------------------
        def activate
            result = defined?(super) ? super : nil
            na_camera_guard__engage
            result
        end
        # ---------------------------------------------------------------

        # DEACTIVATE | Let Go of the View, Then Close the Tool
        # ------------------------------------------------------------
        def deactivate(view)
            na_camera_guard__release
            defined?(super) ? super : nil
        end
        # ---------------------------------------------------------------

        # SUSPEND | A Camera Tool Has the View: Note What Started It
        # ------------------------------------------------------------
        # A pause is not a deactivation: the guard stays on through it, which
        # is the whole point when AltGr is what started the camera tool.
        # ------------------------------------------------------------
        def suspend(view)
            Na__InsertPrimatives.Na__CameraGuard__Paused(@na_camera_guard, view) if @na_camera_guard
            defined?(super) ? super : nil
        end
        # ---------------------------------------------------------------

        # RESUME | The View Is Back: Settle It Before the Tool Redraws
        # ------------------------------------------------------------
        def resume(view)
            Na__InsertPrimatives.Na__CameraGuard__Resumed(@na_camera_guard, view) if @na_camera_guard
            defined?(super) ? super : nil
        end
        # ---------------------------------------------------------------

        # ON KEY DOWN | The Tool First; True Only for the Key That Completes Ctrl+Alt
        # ------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            handled = defined?(super) ? super : false
            return handled unless @na_camera_guard

            Na__InsertPrimatives.Na__CameraGuard__KeyPressed(@na_camera_guard, key, flags) ? true : handled
        end
        # ---------------------------------------------------------------

        # ON KEY UP | The Tool First; Never Swallowed
        # ------------------------------------------------------------
        def onKeyUp(key, repeat, flags, view)
            handled = defined?(super) ? super : false
            Na__InsertPrimatives.Na__CameraGuard__KeyReleased(@na_camera_guard, key) if @na_camera_guard
            handled
        end
        # ---------------------------------------------------------------

        # ON MOUSE MOVE | Note the Modifier Flags, Then the Tool
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            Na__InsertPrimatives.Na__CameraGuard__MouseFlags(@na_camera_guard, flags) if @na_camera_guard
            defined?(super) ? super : nil
        end
        # ---------------------------------------------------------------

        # TOGGLE TOOL OPTION | The Tool's Own Toggle, Then the Lock Follows at Once
        # ------------------------------------------------------------
        def Na__DrawnMode__ToggleToolOption(option_id)
            result = defined?(super) ? super : nil
            Na__InsertPrimatives.Na__CameraGuard__OptionToggled(@na_camera_guard, option_id) if @na_camera_guard
            result
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This One of the Tools the Guard Is For?
        # ------------------------------------------------------------
        def na_camera_guard__wanted?
            respond_to?(:na_drawn__mode_key) && NA_CAMERA_GUARD_MODE_KEYS.include?(na_drawn__mode_key)
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Engage the Guard for This Tool (Releasing Any It Still Holds)
        # ------------------------------------------------------------
        def na_camera_guard__engage
            na_camera_guard__release
            return nil unless na_camera_guard__wanted?

            @na_camera_guard = Na__InsertPrimatives.Na__CameraGuard__Engage(self)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Release the Guard This Tool Holds
        # ------------------------------------------------------------
        def na_camera_guard__release
            Na__InsertPrimatives.Na__CameraGuard__Release(@na_camera_guard) if @na_camera_guard
            @na_camera_guard = nil
        end
        # ---------------------------------------------------------------

    end # End ParallelDrawingGuard module

    # endregion -------------------------------------------------------------------


    # SECTION | Load-Time Sweep (Reload Plugin Data)
    # ------------------------------------------------------------
    Na__InsertPrimatives.Na__CameraGuard__SweepStale unless @na_camera_guard_sessions.empty?
    # ---------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF CAMERA PARALLEL DRAWING GUARD
# =============================================================================
