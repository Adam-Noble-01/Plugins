# =============================================================================
# NA POINT CLOUD VIEWER - SCENES - FOLLOW SKETCHUP'S SCENE TABS
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Scenes__Follow__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__SceneFollow
# PURPOSE    : Pressing a SketchUp scene tab does what Go To Scene does: when
#              that SketchUp scene has point cloud settings, every cloud takes
#              them back. A SketchUp scene without settings changes nothing.
#
# HOW SKETCHUP SAYS A SCENE WAS PRESSED: Sketchup::Pages.add_frame_change_observer,
#   the documented hook (SketchUp 6 onwards) that Trimble's own Dynamic
#   Components use for scene changes. SketchUp calls it for every frame of
#   every scene transition. Measured on SketchUp 2026 (26-Oct-2026, in a scratch
#   SketchUp, with a real click on a scene tab; ARCHITECTURE 23.7):
#   - a transition calls it from 0.0 to 1.0, about 25 times a second; 0.0 and
#     the next frame come INSIDE the click, before Pages#selected_page names the
#     new scene; 1.0 sometimes comes twice;
#   - with transitions off it is ONE call at 1.0, also inside the click;
#   - pressing the tab already shown runs it again, a scene that saves no
#     camera runs it too, a transition cut short by another press never reaches
#     1.0, and a slideshow runs it for every scene;
#   - from_page is nil on Windows (a known SketchUp bug), so it is never used;
#   - opening a model runs nothing, so nothing here can happen on open.
#
# THE RULES (each one answers a way this kind of observer hangs SketchUp or
#   damages a model):
#   1. The callback only notes the scene and books a timer, one at a time. It
#      never touches the model, never raises, and does nothing for the frames
#      in between, so a transition costs nothing.
#   2. The work runs from that timer, after SketchUp's notification has
#      returned. A newer press cancels a booked one, so only the scene the user
#      ends on is applied. The end of the transition books one more look, which
#      writes nothing when the first already applied the scene.
#   3. It NEVER selects a scene. An observer that selects the scene it was told
#      about starts the transition again, for ever (proven on SketchUp 2026),
#      and it would stop a playing slideshow. Go To Scene still selects the
#      scene itself and tells this module first, so its own transition is not
#      applied twice.
#   4. It changes things only through Go To Scene's own code
#      (Na__SceneRecall.Na__Scenes__Apply): nothing on any Page; a clip box that
#      changes is ONE named undoable operation; when nothing differs nothing at
#      all is written. Never a transparent operation: selecting a scene is not
#      an operation, so a transparent one would merge into the user's own last
#      edit.
#   5. Nothing is guessed: the SketchUp scene is matched by its persistent id,
#      as everywhere in the Scenes tab. No settings for it, no longer the scene
#      shown, not the active model, an import or export running: nothing
#      happens.
#   6. Installed when a model gets its overlay (the model registry's startup
#      notification, after SketchUp has loaded every extension), never while
#      extensions load. Once per SketchUp session: Reload Plugin keeps the same
#      observer and reopens its class.
#   7. The Scenes tab's Follow Tabs switch (per computer, user config) turns it
#      off: a booked look then does nothing, and switching off cancels one.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__SceneFollow

    # -------------------------------------------------------------------------
    # REGION | Constants and State
    # -------------------------------------------------------------------------

        # The booked look runs this long after the press: the click has
        # returned and SketchUp names the new scene.
        NA_DELAY_SECONDS = 0.1

        # Frames of one transition come about every 40 ms. A frame for the same
        # scene after a longer gap is a new press (transitions off, or the tab
        # pressed again).
        NA_SAME_PRESS_SECONDS = 0.3

        @na_observer    = nil unless defined?(@na_observer)
        @na_observer_id = nil unless defined?(@na_observer_id)
        @na_last_frame  = nil unless defined?(@na_last_frame)    # [pid, time]
        @na_press       = nil unless defined?(@na_press)         # { 'pid', 'goTo', 'ended' } of the transition running
        @na_booked      = nil unless defined?(@na_booked)        # { 'model' =>, 'pid' => }
        @na_timer       = nil unless defined?(@na_timer)
        @na_expected    = nil unless defined?(@na_expected)      # pid Go To Scene is selecting

        # SketchUp calls frameChange on any object given to
        # add_frame_change_observer; there is no base class to inherit.
        class Na__FrameObserver

            def frameChange(_from_page, to_page, percent_done)
                Na__SceneFollow.na_frame(to_page, percent_done)
            rescue StandardError
                nil
            end

        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Install and Switch
    # -------------------------------------------------------------------------

        # Once per SketchUp session (see rule 6). Returns true when installed.
        def self.Na__Follow__InstallOnce
            return true if @na_observer
            observer = Na__FrameObserver.new
            @na_observer_id = Sketchup::Pages.add_frame_change_observer(observer)
            @na_observer = observer
            true
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('SketchUp scene tabs cannot be followed in this session.', error)
            false
        end

        def self.Na__Follow__Installed?
            !@na_observer.nil?
        end

        # On unless the user switched it off on this computer.
        def self.Na__Follow__Enabled?
            Na__UserConfigStore.Na__UserConfig__Get('scenes', 'followSceneTabs', true) != false
        end

        def self.Na__Follow__SetEnabled(is_on)
            Na__UserConfigStore.Na__UserConfig__Set('scenes', 'followSceneTabs', is_on ? true : false)
            self.na_cancel_booked unless is_on
            is_on ? true : false
        end

        # Go To Scene is about to select this SketchUp scene itself (pid), or
        # has finished doing so (nil). Its transition starts inside that call,
        # so the press it makes is not booked a second time.
        def self.Na__Follow__Expect(pid)
            @na_expected = pid ? pid.to_i : nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Callback (every frame of every transition)
    # -------------------------------------------------------------------------

        # Books a look when a NEW press begins, and one more when its
        # transition ends: SketchUp may name the new scene only by then (the
        # first scene of a slideshow did, on SketchUp 2026), and when the first
        # look already applied it, the second finds nothing different and
        # writes nothing. A 1.0 that comes twice books once. Go To Scene's own
        # press books nothing. Memory only: even the switch is read by the
        # look, not here.
        def self.na_frame(page, percent_done)
            return unless page
            pid = page.persistent_id.to_i
            now = Time.now.to_f
            last = @na_last_frame
            @na_last_frame = [pid, now]
            if percent_done.to_f <= 0.0 || last.nil? || last[0] != pid || (now - last[1]) > NA_SAME_PRESS_SECONDS
                @na_press = { 'pid' => pid, 'goTo' => @na_expected == pid, 'ended' => false }
                self.na_book(page.model, pid) unless @na_press['goTo']
            end
            press = @na_press
            return unless percent_done.to_f >= 1.0 && press && press['pid'] == pid && !press['ended']
            press['ended'] = true
            self.na_book(page.model, pid) unless press['goTo']
        end

        # One look, booked; a newer press replaces it.
        def self.na_book(model, pid)
            self.na_cancel_booked
            @na_booked = { 'model' => model, 'pid' => pid }
            ran = false
            @na_timer = UI.start_timer(NA_DELAY_SECONDS, false) do
                # Before SketchUp 2023.1 a one shot timer could fire again while
                # a modal window was open; this one runs once whatever happens.
                next if ran
                ran = true
                Na__PointCloudViewer::Na__SceneFollow.na_run_booked
            end
        end

        def self.na_cancel_booked
            UI.stop_timer(@na_timer) if @na_timer
            @na_timer  = nil
            @na_booked = nil
        end

        def self.na_run_booked
            booked = @na_booked
            @na_booked = nil
            @na_timer  = nil
            return unless booked && self.Na__Follow__Enabled?
            self.Na__Follow__Apply(booked['model'], booked['pid'])
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('A SketchUp scene tab could not be followed.', error)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Look (from the timer, outside SketchUp's notification)
    # -------------------------------------------------------------------------

        # Gives every cloud the settings of the SketchUp scene with this
        # persistent id, when it is still the scene shown and has settings.
        # Returns what happened: :applied, :problem, :same, :no_settings,
        # :not_shown, :not_active, :no_session or :busy.
        def self.Na__Follow__Apply(model, pid)
            return :not_active unless model && model.valid? && model == Sketchup.active_model
            page = model.pages.selected_page
            return :not_shown unless page && Na__SceneStore.Na__Scenes__PagePid(page) == pid.to_i
            overlay = Na__ModelRegistry.Na__Registry__FindOverlay(model)
            session = overlay && overlay.respond_to?(:na_session) ? overlay.na_session : nil
            return :no_session unless session && session.model == model
            scene = Na__SceneStore.Na__Scenes__ForPid(session, pid)
            return :no_settings unless scene
            if Na__AsyncJobs.Na__Jobs__Busy?
                self.na_tell("The point clouds did not follow #{page.name} while #{Na__AsyncJobs.Na__Jobs__ActiveTitle || 'a task'} runs. " \
                             'Press Go To Scene when it has finished.', 'info')
                return :busy
            end
            view = model.active_view
            return :same unless Na__SceneStore.Na__Scenes__Differs?(session, scene, view)
            problem = Na__SceneRecall.Na__Scenes__Apply(session, scene, page, view)
            view.invalidate
            if problem
                self.na_tell(problem, 'warn')
                Na__DebugTools.Na__Debug__Warn("Following the SketchUp scene #{page.name}: #{problem}")
            end
            Na__DialogManager.Na__Dialog__PushState if Na__DialogManager.Na__Dialog__Visible?
            problem ? :problem : :applied
        end

        # The status line, when the dialog is open. Never a message box: one
        # would stop SketchUp until it was answered.
        def self.na_tell(message, level)
            return unless Na__DialogManager.Na__Dialog__Visible?
            Na__DialogManager.Na__Dialog__PushStatus(message, level)
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
