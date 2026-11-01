# =============================================================================
# NA PAINTERLYNPR ASSETS - NPR VIEWPORT - LIVE SYNC
# =============================================================================
#
# FILE       : Na__PainterlyAssets__NprViewport__LiveSync__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__LiveSync
# PURPOSE    : Live NPR updates, on or off: while on, the NPR Viewport follows
#              SketchUp's camera and every committed change reaches its cache
#              (only the stale GLBs re-exported, only those fetched); while off,
#              nothing in the model is watched and the drawing holds still.
#              Turning it back on checks every part of the model again.
# CREATED    : 01-Nov-2026
#
# DESCRIPTION:
# - Adam, 01-Nov-2026: "We need a way to be able to toggle real-time rendering
#   on or off, so the viewport doesn't just continually update whilst you're
#   making edits. It should be live by default when you open it ... When that's
#   off, it doesn't look for what's changed in the model ... When you flip that
#   back on, it will go cycle through and say, Hey, this asset's changed."
# - OBSERVERS ONLY NOTE AND SCHEDULE (never change the model inside one): a
#   commit notes the definitions it can have touched (the open context's path,
#   or the selection's contents) and books one sync for when the model has
#   been still for idleSeconds; undo, redo and a material edit book a full
#   check; a camera move books one camera message (throttled).
# - THE SYNC WAITS FOR A CLOSED GROUP: the GLB builder exports the model, not
#   an open context, so changes made inside a group reach the drawing when it
#   is closed (the camera keeps following meanwhile).
# - THE LOOK: the NPR Parameters window's settings are kept per project (in
#   its cache folder) and handed to the viewport; a slider's move goes over at
#   once as one control, the rest as the engine's settings object.
# - State survives Reload Plugin Data (every module variable is guarded), and
#   the observers attached before a reload keep calling the reloaded methods.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__LiveSync

    # -------------------------------------------------------------------------
    # REGION | Observers (they only note and schedule)
    # -------------------------------------------------------------------------

        class Na__LiveSync__ModelWatch < Sketchup::ModelObserver
            def onTransactionCommit(model);  Na__PainterlyAssets::Na__LiveSync.na_on_commit(model);    end
            def onTransactionUndo(model);    Na__PainterlyAssets::Na__LiveSync.na_on_full(model);      end
            def onTransactionRedo(model);    Na__PainterlyAssets::Na__LiveSync.na_on_full(model);      end
            def onActivePathChanged(model);  Na__PainterlyAssets::Na__LiveSync.na_on_path(model);      end
        end

        class Na__LiveSync__ViewWatch < Sketchup::ViewObserver
            def onViewChanged(view);         Na__PainterlyAssets::Na__LiveSync.na_on_view(view);       end
        end

        class Na__LiveSync__MaterialsWatch < Sketchup::MaterialsObserver
            def onMaterialChange(_materials, _material); Na__PainterlyAssets::Na__LiveSync.na_on_full(Sketchup.active_model); end
        end

        class Na__LiveSync__AppWatch < Sketchup::AppObserver
            def onNewModel(model);           Na__PainterlyAssets::Na__LiveSync.na_on_model(model);     end
            def onOpenModel(model);          Na__PainterlyAssets::Na__LiveSync.na_on_model(model);     end
            def onActivateModel(model);      Na__PainterlyAssets::Na__LiveSync.na_on_model(model);     end
            def expectsStartupModelNotifications; false; end                          # <-- Attached when a window opens, never at start-up
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | State
    # -------------------------------------------------------------------------

        @na_live         = false unless defined?(@na_live)
        @na_watch        = nil   unless defined?(@na_watch)                              # <-- { model, model_watch, view_watch, materials_watch }
        @na_app_watch    = nil   unless defined?(@na_app_watch)
        @na_sync_timer   = nil   unless defined?(@na_sync_timer)
        @na_camera_timer = nil   unless defined?(@na_camera_timer)
        @na_save_timer   = nil   unless defined?(@na_save_timer)
        @na_syncing      = false unless defined?(@na_syncing)
        @na_pending      = { 'full' => true, 'forget' => {}, 'waiting' => false } unless defined?(@na_pending)
        @na_placement    = {}    unless defined?(@na_placement)                          # <-- Project key => the scene's placement (the camera's frame)
        @na_settings     = {}    unless defined?(@na_settings)                           # <-- Project key => the engine's look
        @na_last         = nil   unless defined?(@na_last)                               # <-- The last sync's answer, for the status line

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__Live__On?
            @na_live ? true : false
        end

        # FUNCTION | Turn Live Updates On or Off
        # ------------------------------------------------------------
        # On: watch the model and the view, and check every part of the model
        # now. Off: stop watching; the drawing stays as it is.
        def self.Na__Live__Set(on)
            on = on ? true : false
            changed = on != @na_live
            @na_live = on
            if on
                self.na_attach(Sketchup.active_model)
                @na_pending['full'] = true                                               # <-- Back on: cycle through every part, whatever happened while off
                self.na_schedule_sync(0.05)
                self.na_schedule_camera
            else
                self.na_detach
                self.na_stop(:@na_sync_timer)
                self.na_stop(:@na_camera_timer)
            end
            UI.refresh_toolbars if changed && Sketchup.version.to_i < 27                # <-- The toolbar button's pressed look (2027 refreshes itself)
            Na__NprWindows.Na__Windows__SendAll('live', self.na_live_payload)
            @na_live
        end
        # ---------------------------------------------------------------

        def self.Na__Live__Toggle
            self.Na__Live__Set(!@na_live)
        end

        # FUNCTION | Refresh Now: every part checked and the camera sent, live or not
        # ------------------------------------------------------------
        def self.Na__Live__Refresh
            @na_pending['full'] = true
            self.na_schedule_sync(0.05)
            self.na_schedule_camera(force: true)
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Window Has Loaded the Engine and Its Host
        # ------------------------------------------------------------
        def self.Na__Live__WindowReady(role, info)
            model = Sketchup.active_model
            key   = Na__CacheStore.Na__Cache__Key(model)
            Na__NprWindows.Na__Windows__Send(role, 'live', self.na_live_payload)
            settings = self.na_settings_for(model)
            Na__NprWindows.Na__Windows__Send(role, 'settings', { 'Settings' => settings, 'Project' => key }) if settings
            Na__NprWindows.Na__Windows__Send(role, 'status', { 'Text' => @na_last['message'], 'Level' => @na_last['ok'] ? 'info' : 'warn' }) if @na_last && role == 'parameters'
            return unless role == 'viewport'

            unless info['Booted']
                Na__NprWindows.Na__Windows__SendAll('status', { 'Text' => "PainterlyNPR could not start in SketchUp's browser: #{info['Error']}", 'Level' => 'error' })
                return
            end
            Na__CacheStore.Na__Cache__Touch(model)
            self.Na__Live__Set(true) if !@na_live && Na__ViewportConfig.Na__ViewportConfig__Get('live', 'onWhenOpened', true) != false
            @na_pending['full'] = true                                                   # <-- A new page has nothing: check everything, send everything
            self.na_schedule_sync(0.05)
            self.na_schedule_camera(force: true)
        end
        # ---------------------------------------------------------------

        def self.Na__Live__ViewportClosed
            self.Na__Live__Set(false) if @na_live                                        # <-- Nothing to draw into: stop watching
        end

        # FUNCTION | The NPR Parameters Window Moved the Engine's Look
        # ------------------------------------------------------------
        # A control goes straight to the viewport; a settings object is kept for
        # the project (written a moment after the last change) and handed on.
        def self.Na__Live__ParametersChanged(payload)
            if payload['Control'].is_a?(Hash)
                Na__NprWindows.Na__Windows__Send('viewport', 'settings', { 'Control' => payload['Control'] })
            end
            return unless payload['Settings'].is_a?(Hash)

            model = Sketchup.active_model
            key   = Na__CacheStore.Na__Cache__Key(model)
            @na_settings[key] = payload['Settings']
            Na__NprWindows.Na__Windows__Send('viewport', 'settings', { 'Settings' => payload['Settings'], 'Project' => key })
            self.na_stop(:@na_save_timer)
            folder = Na__CacheStore.Na__Cache__Folder(model)
            @na_save_timer = UI.start_timer(1.0, false) do
                @na_save_timer = nil
                begin
                    Na__CacheStore.Na__Cache__WriteSettings(folder, payload['Settings'])
                rescue StandardError => error
                    Na__DebugTools.Na__Debug__Warn("The NPR look could not be saved: #{error.message}")
                end
            end
        end
        # ---------------------------------------------------------------

        def self.Na__Live__LastSync
            @na_last
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Observer Callbacks (note, then schedule)
    # -------------------------------------------------------------------------

        def self.na_on_commit(model)
            return unless @na_live && self.na_watching?(model)
            path = model.active_path
            touched = if path && !path.empty?
                          path.map(&:definition)                                           # <-- The open contexts: an edit lands in the innermost
                      else
                          Na__Fingerprint.Na__Fp__Nested(model.selection.to_a)             # <-- At the root: a tool may have painted inside the selection
                      end
            touched.each { |definition| @na_pending['forget'][definition.persistent_id] = definition }
            self.na_schedule_sync
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The NPR live sync could not note a change.', error)
        end

        def self.na_on_full(model)
            return unless @na_live && self.na_watching?(model)
            @na_pending['full'] = true
            self.na_schedule_sync
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The NPR live sync could not note an undo.', error)
        end

        def self.na_on_path(model)
            return unless @na_live && self.na_watching?(model)
            self.na_schedule_sync(0.2) if @na_pending['waiting'] && model.active_path.nil?   # <-- The group closed: what waited goes now
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The NPR live sync could not follow the open context.', error)
        end

        def self.na_on_view(_view)
            self.na_schedule_camera if @na_live
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The NPR live sync could not follow the camera.', error)
        end

        # Another model came to the front (a new file, an opened one, a 2027 tab)
        def self.na_on_model(model)
            return unless @na_live
            self.na_attach(model)
            @na_pending['full'] = true
            self.na_schedule_sync(0.3)
            self.na_schedule_camera(force: true)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The NPR live sync could not follow the model change.', error)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Sync and the Camera
    # -------------------------------------------------------------------------

        def self.na_schedule_sync(delay = nil)
            delay ||= Na__ConfigLoader.Na__Config__GetOr(1.0, 'nprViewport', 'live', 'idleSeconds').to_f
            self.na_stop(:@na_sync_timer)
            fired = false
            @na_sync_timer = UI.start_timer(delay, false) do
                next if fired                                                            # <-- A modal pumps the event loop and can fire a one-shot timer again
                fired = true
                @na_sync_timer = nil
                Na__PainterlyAssets::Na__LiveSync.na_run_sync
            end
        end

        def self.na_run_sync
            return if @na_syncing
            return unless Na__NprWindows.Na__Windows__Ready?('viewport')
            model = Sketchup.active_model
            return unless model
            if model.active_path
                unless @na_pending['waiting']
                    @na_pending['waiting'] = true
                    Na__NprWindows.Na__Windows__SendAll('status', { 'Text' => 'Changes reach the NPR view when the open group or component is closed.', 'Level' => 'info' })
                end
                return
            end

            mode   = @na_pending['full'] ? :full : :incremental
            forget = @na_pending['forget'].values.select { |d| d.valid? rescue false }
            @na_pending = { 'full' => false, 'forget' => {}, 'waiting' => false }
            @na_syncing = true
            begin
                Na__NprWindows.Na__Windows__SendAll('status', { 'Text' => mode == :full ? 'Checking every part of the model...' : 'Updating the NPR cache...', 'Level' => 'busy' })
                result = Na__CacheSync.Na__Sync__Run(model, mode: mode, forget: forget)
            ensure
                @na_syncing = false
            end
            @na_last = result
            if result['state'] == 'waiting'
                @na_pending['waiting'] = true
                @na_pending['full'] ||= mode == :full
                return
            end
            if result['scene']
                @na_placement[result['key']] = result['scene']['NprScene__ModelPlacement'] || {}
                Na__NprWindows.Na__Windows__Send('viewport', 'scene', Na__CacheSync.Na__Sync__Payload(result))
                self.na_schedule_camera(force: true)
            end
            Na__NprWindows.Na__Windows__SendAll('status', { 'Text' => "#{result['message']} (#{result['seconds']} s)", 'Level' => result['ok'] ? 'info' : 'error' })
        rescue StandardError => error
            @na_syncing = false
            Na__DebugTools.Na__Debug__Error('The NPR live sync failed.', error)
            Na__NprWindows.Na__Windows__SendAll('status', { 'Text' => "The NPR update failed: #{error.message}", 'Level' => 'error' })
        end

        # A camera message at most every cameraSeconds; force sends the next one even when live is off
        def self.na_schedule_camera(force: false)
            return if @na_camera_timer
            return unless force || @na_live
            delay = Na__ConfigLoader.Na__Config__GetOr(0.08, 'nprViewport', 'live', 'cameraSeconds').to_f
            fired = false
            @na_camera_timer = UI.start_timer(delay, false) do
                next if fired
                fired = true
                @na_camera_timer = nil
                Na__PainterlyAssets::Na__LiveSync.na_send_camera
            end
        end

        def self.na_send_camera
            model = Sketchup.active_model
            return unless model && Na__NprWindows.Na__Windows__Ready?('viewport')
            key = Na__CacheStore.Na__Cache__Key(model)
            return unless @na_placement.key?(key)                                          # <-- No scene yet: the first sync sends it, then the camera
            Na__NprWindows.Na__Windows__Send('viewport', 'camera', Na__CameraSync.Na__Camera__Payload(model.active_view, @na_placement[key]))
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The NPR camera could not be sent.', error)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_attach(model)
            return unless model
            self.na_detach if @na_watch && !@na_watch['model'].equal?(model)
            unless @na_watch
                watch = { 'model' => model, 'model_watch' => Na__LiveSync__ModelWatch.new, 'view_watch' => Na__LiveSync__ViewWatch.new,
                          'materials_watch' => Na__LiveSync__MaterialsWatch.new, 'view' => model.active_view }
                model.add_observer(watch['model_watch'])
                model.active_view.add_observer(watch['view_watch'])
                model.materials.add_observer(watch['materials_watch'])
                @na_watch = watch
            end
            unless @na_app_watch
                @na_app_watch = Na__LiveSync__AppWatch.new
                Sketchup.add_observer(@na_app_watch)
            end
        end

        def self.na_detach
            watch = @na_watch
            @na_watch = nil
            if watch
                begin
                    watch['model'].remove_observer(watch['model_watch'])
                    watch['view'].remove_observer(watch['view_watch'])
                    watch['model'].materials.remove_observer(watch['materials_watch'])
                rescue StandardError
                    nil                                                                    # <-- A closed model takes its observers with it
                end
            end
            if @na_app_watch
                Sketchup.remove_observer(@na_app_watch) rescue nil
                @na_app_watch = nil
            end
        end

        def self.na_watching?(model)
            @na_watch && @na_watch['model'].equal?(model)
        end

        def self.na_stop(name)
            timer = instance_variable_get(name)
            UI.stop_timer(timer) if timer
            instance_variable_set(name, nil)
        end

        def self.na_settings_for(model)
            key = Na__CacheStore.Na__Cache__Key(model)
            @na_settings[key] ||= Na__CacheStore.Na__Cache__ReadSettings(Na__CacheStore.Na__Cache__Folder(model))
        end

        def self.na_live_payload
            model = Sketchup.active_model
            {
                'On'      => @na_live,
                'Model'   => model ? (model.title.to_s.empty? ? 'Untitled' : model.title.to_s) : '',
                'Project' => model ? Na__CacheStore.Na__Cache__Key(model) : '',
                'Engine'  => Na__RemoteEngine.Na__Remote__Current
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
