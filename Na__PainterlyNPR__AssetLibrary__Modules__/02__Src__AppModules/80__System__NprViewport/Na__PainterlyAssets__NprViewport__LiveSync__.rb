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
# - THE LOOK (v0.3.0): the NPR Parameters window's settings are kept in the
#   MODEL (Na__NprSettings: its NPR settings record) and handed to the
#   viewport; a slider's move goes over at once as one control, the rest as the
#   engine's settings object. An Undo or Redo of a look change brings that look
#   back in both windows (Na__NprSettings watches the undo, and says whether it
#   was only the record that moved: then the geometry is not checked again).
# - AN EXPORT HOLDS THE VIEWPORT STILL (Na__Live__Hold): no camera and no new
#   scene reach it while NPR Export draws its pictures; afterwards SketchUp's
#   camera goes again, and a sync that waited runs.
# - THE VIEWPORT'S OWN MENUS (v0.4.0): what its Assets drawer changes is made in
#   the model (Na__ModelEdits) and synced like any edit, sooner, with the
#   definitions it painted forgotten; each scene says which of those edits it
#   shows (EditsThrough). Its art control points are kept in the model, one set
#   a scene: selecting a scene brings its set to the viewport with the camera.
# - State survives Reload Plugin Data (every module variable is guarded), and
#   the observers attached before a reload keep calling the reloaded methods.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__LiveSync

    # -------------------------------------------------------------------------
    # REGION | Observers (they only note and schedule)
    # -------------------------------------------------------------------------

        # Undo and Redo come through Na__NprSettings' watch (Na__Live__ModelUndone):
        # it alone can tell an undone look from an undone edit.
        class Na__LiveSync__ModelWatch < Sketchup::ModelObserver
            def onTransactionCommit(model);  Na__PainterlyAssets::Na__LiveSync.na_on_commit(model);    end
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
        @na_syncing      = false unless defined?(@na_syncing)
        @na_pending      = { 'full' => true, 'forget' => {}, 'waiting' => false } unless defined?(@na_pending)
        @na_placement    = {}    unless defined?(@na_placement)                          # <-- Project key => the scene's placement (the camera's frame)
        @na_last         = nil   unless defined?(@na_last)                               # <-- The last sync's answer, for the status line
        @na_scene_sent   = nil   unless defined?(@na_scene_sent)                         # <-- The project whose scene the viewport's page now has
        @na_hold         = false unless defined?(@na_hold)                               # <-- NPR Export is drawing: nothing moves the viewport
        @na_held_sync    = false unless defined?(@na_held_sync)                          # <-- A sync came due while held
        @na_edits_through = 0    unless defined?(@na_edits_through)                      # <-- The last batch of the viewport's edits made in the model
        @na_points_key   = nil   unless defined?(@na_points_key)                         # <-- The set of art control points the viewport was last given

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
            Na__NprWindows.Na__Windows__Send(role, 'live', self.na_live_payload)
            self.na_send_look(role, model)
            Na__NprWindows.Na__Windows__Send(role, 'record', Na__NprSettings.Na__Settings__Status(model))
            Na__NprWindows.Na__Windows__Send(role, 'status', { 'Text' => @na_last['message'], 'Level' => @na_last['ok'] ? 'info' : 'warn' }) if @na_last && role == 'parameters'
            return unless role == 'viewport'

            @na_scene_sent = nil                                                         # <-- A new page has no scene yet
            @na_edits_through = 0                                                        # <-- And it counts its edits from one again
            self.na_send_points(model)                                                   # <-- It holds them until the model has loaded
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
            @na_scene_sent = nil
            self.Na__Live__Hold(false) if @na_hold
            self.Na__Live__Set(false) if @na_live                                        # <-- Nothing to draw into: stop watching
        end

        # FUNCTION | The NPR Parameters Window Moved the Engine's Look
        # ------------------------------------------------------------
        # A control goes straight to the viewport; a settings object goes to the
        # viewport too, and is kept in the model (one undo step a run of changes;
        # Reset is a step of its own). The parameters window is told what the
        # record now says.
        def self.Na__Live__ParametersChanged(payload)
            if payload['Control'].is_a?(Hash)
                Na__NprWindows.Na__Windows__Send('viewport', 'settings', { 'Control' => payload['Control'] })
            end
            return unless payload['Settings'].is_a?(Hash)

            model = Sketchup.active_model
            Na__NprWindows.Na__Windows__Send('viewport', 'settings', { 'Settings' => payload['Settings'], 'Project' => Na__CacheStore.Na__Cache__Key(model) })
            problem = Na__NprSettings.Na__Settings__SaveLook(model, payload['Settings'], payload['Reset'] ? 'lookReset' : 'look')
            Na__NprWindows.Na__Windows__Send('parameters', 'record', Na__NprSettings.Na__Settings__Status(model))
            Na__NprWindows.Na__Windows__Send('parameters', 'status', { 'Text' => problem, 'Level' => 'warn' }) if problem
            Na__NprWindows.Na__Windows__Send('parameters', 'status', { 'Text' => 'The look is back to PainterlyNPR\'s defaults (the GitHub engine\'s own). Undo in SketchUp puts the last one back.', 'Level' => 'info' }) if payload['Reset'] && !problem
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Model's Look Changed Behind the Windows (an Undo, a Restore, a model brought to the front)
        # ------------------------------------------------------------
        def self.Na__Live__LookChanged(model)
            return unless model && model.equal?(Sketchup.active_model)
            Na__NprWindows::NA_ROLES.each { |role| self.na_send_look(role, model) }
            self.na_send_points(model)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Viewport's Art Control Points Changed: Kept in the Model
        # ------------------------------------------------------------
        def self.Na__Live__PointsChanged(payload)
            model   = Sketchup.active_model
            return unless model && payload['Project'].to_s == Na__CacheStore.Na__Cache__Key(model)   # <-- Another model came to the front as the page saved: these were not its points
            problem = Na__NprSettings.Na__Settings__SavePoints(model, payload['Key'], payload['Points'], payload['Sheet'])
            Na__NprWindows.Na__Windows__Send('parameters', 'record', Na__NprSettings.Na__Settings__Status(model))
            Na__NprWindows.Na__Windows__Send('viewport', 'status', { 'Text' => problem, 'Level' => 'warn' }) if problem
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Batch of the Viewport's Edits Has Been Made in the Model
        # ------------------------------------------------------------
        # Live or not, the next scene says it shows this batch. Live, the sync
        # comes sooner than for an edit in SketchUp (nobody is mid-gesture) and
        # forgets the definitions the batch painted: nothing was selected, so the
        # commit's own note cannot know them. Paused, the page draws its own
        # preview, and turning live back on checks everything.
        def self.Na__Live__ModelEdited(model, seq, touched)
            @na_edits_through = [@na_edits_through.to_i, seq.to_i].max
            return unless @na_live && model && self.na_watching?(model)
            Array(touched).each { |definition| @na_pending['forget'][definition.persistent_id] = definition }
            self.na_schedule_sync(Na__ConfigLoader.Na__Config__GetOr(0.25, 'nprViewport', 'live', 'editSeconds').to_f)
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Undo or Redo (from Na__NprSettings' watch): only the look moved, or the model
        # ------------------------------------------------------------
        def self.Na__Live__ModelUndone(model, only_the_record)
            return if only_the_record                                                    # <-- An undone look: the geometry is as it was
            self.na_on_full(model)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Hold the Viewport Still (NPR Export is drawing) or Let It Follow Again
        # ------------------------------------------------------------
        def self.Na__Live__Hold(on)
            @na_hold = on ? true : false
            return if @na_hold
            self.na_schedule_camera(force: true)                                         # <-- Back to SketchUp's view
            if @na_held_sync
                @na_held_sync = false
                self.na_schedule_sync(0.2)
            end
        end
        # ---------------------------------------------------------------

        def self.Na__Live__Held?
            @na_hold ? true : false
        end

        # FUNCTION | Has the Viewport's Page the Model's Scene? (an export draws nothing else)
        # ------------------------------------------------------------
        def self.Na__Live__SceneReady?(model)
            return false unless model && Na__NprWindows.Na__Windows__Ready?('viewport')
            key = Na__CacheStore.Na__Cache__Key(model)
            @na_scene_sent == key && @na_placement.key?(key)
        end
        # ---------------------------------------------------------------

        # The scene's placement (the frame every camera is sent in)
        def self.Na__Live__Placement(model)
            @na_placement[Na__CacheStore.Na__Cache__Key(model)] || {}
        end

        # FUNCTION | Make Sure the Viewport Has the Scene (an export asked, live or not)
        # ------------------------------------------------------------
        def self.Na__Live__EnsureScene(model)
            return if self.Na__Live__SceneReady?(model) || @na_syncing
            @na_pending['full'] = true if @na_scene_sent.nil?
            self.na_schedule_sync(0.05)
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
            return if Na__NprSettings.Na__Settings__Writing?                             # <-- Our own NPR settings record: nothing drawn has changed
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
            if @na_hold
                @na_held_sync = true                                                     # <-- NPR Export is drawing: this runs when it is done
                return
            end
            model = Sketchup.active_model
            return unless model
            if model.active_path
                unless @na_pending['waiting']
                    @na_pending['waiting'] = true
                    Na__NprWindows.Na__Windows__SendAll('status', { 'Text' => 'Changes reach the NPR view when the open group or component is closed.', 'Level' => 'info' })
                end
                return
            end

            mode    = @na_pending['full'] ? :full : :incremental
            forget  = @na_pending['forget'].values.select { |d| d.valid? rescue false }
            through = @na_edits_through                                                  # <-- Every batch made before this sync read the model
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
                @na_scene_sent = result['key'] if Na__NprWindows.Na__Windows__Send('viewport', 'scene', Na__CacheSync.Na__Sync__Payload(result).merge('EditsThrough' => through))
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
            return if @na_hold                                                           # <-- NPR Export sets each picture's camera itself
            model = Sketchup.active_model
            return unless model && Na__NprWindows.Na__Windows__Ready?('viewport')
            key = Na__CacheStore.Na__Cache__Key(model)
            return unless @na_placement.key?(key)                                          # <-- No scene yet: the first sync sends it, then the camera
            self.na_send_points(model) unless Na__NprSettings.Na__Settings__PointsKey(model) == @na_points_key   # <-- A scene selected: its art control points come with its camera
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

        # The model's look to one window (the record's, else this PC's 0.2.0
        # cache; nothing kept: the engine's own defaults stand)
        def self.na_send_look(role, model)
            return unless model
            look = Na__NprSettings.Na__Settings__Look(model)
            return unless look['settings']
            Na__NprWindows.Na__Windows__Send(role, 'settings', { 'Settings' => look['settings'], 'Project' => Na__CacheStore.Na__Cache__Key(model), 'Source' => look['source'] })
        end

        # The art control points of the scene the model's view is on, to the viewport
        def self.na_send_points(model)
            return unless model
            set = Na__NprSettings.Na__Settings__Points(model)
            @na_points_key = set['Key']
            Na__NprWindows.Na__Windows__Send('viewport', 'points', set.merge('Project' => Na__CacheStore.Na__Cache__Key(model)))
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
