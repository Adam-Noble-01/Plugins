# =============================================================================
# NA AGENT OUTLINER - CHANGE TRACKING - OBSERVERS
# =============================================================================
#
# FILE       : Na__AgentOutliner__ChangeTracking__Observers__.rb
# NAMESPACE  : Na__AgentOutliner::Na__Observers
# MODULE     : Na__Observers (module functions and observer classes)
# AUTHOR     : Noble Architecture
# PURPOSE    : Attach the observers that feed the change tracker and the
#              dialog, once per model, and let go of a model when it closes
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - EVERY CALLBACK ONLY PASSES THE NEWS ON. The tracker records it and books
#   one timer; nothing here reads the model deeply or changes it ("never
#   modify the model inside an observer callback"). Every callback is wrapped
#   in a rescue that logs: observers swallow exceptions, and a bare NameError
#   inside one would make the whole feature look absent.
# - PER MODEL. SketchUp 2027 opens several models in tabs: each model gets its
#   own set, found by model, attached on new, open and activate, released on
#   AppObserver#onCloseModel (2027). On SketchUp 2026 (one model at a time)
#   attaching to a new model releases the old one, since onDeleteModel is
#   unreliable there.
# - ONE EntitiesObserver instance per model watches model.entities and every
#   definition's entities; a DefinitionsObserver adds each new definition.
# - THE DefinitionsObserver IS NEVER REMOVED: removing definition observers has
#   crashed SketchUp (api-issue-tracker #960). A released model's observer
#   finds no watch and does nothing.
# - WATCHES ON ERASED DEFINITIONS (0.1.11): a definition watched when it was
#   added can be erased later (an undone build, a rebuild, Purge). Its
#   Entities then raise on every call, remove_observer included, and have no
#   valid?. The tracker prunes them after each full pass; Detach skips them.
# - RELOAD SAFE: the classes are reopened by Reload Plugin Data, so observers
#   already attached run the new code; the watch list survives (guarded).
#
# =============================================================================

module Na__AgentOutliner
    module Na__Observers

# -----------------------------------------------------------------------------
# REGION | State
# -----------------------------------------------------------------------------

        @na_watches       = []    unless defined?(@na_watches)
        @na_app_observer  = nil   unless defined?(@na_app_observer)
        @na_install_timer = false unless defined?(@na_install_timer)
        @na_error_counts  = {}    unless defined?(@na_error_counts)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Install, Attach, Detach
# -----------------------------------------------------------------------------

        # FUNCTION | Book the Install (the app observer and the active model)
        # ------------------------------------------------------------
        def self.Na__Observers__InstallDeferred
            return true if @na_install_timer

            @na_install_timer = true
            UI.start_timer(0.5, false) do
                Na__AgentOutliner::Na__Observers.na_install_now
            end
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Watch a Model (idempotent: a second call finds the first)
        # ------------------------------------------------------------
        def self.Na__Observers__Attach(model)
            return nil unless model

            watch = self.na_watch_for(model)
            return watch if watch

            self.na_release_others(model)
            watch = {
                model:       model,
                model_obs:   ModelWatch.new,
                ents_obs:    EntitiesWatch.new,
                defs_obs:    DefinitionsWatch.new,
                sel_obs:     SelectionWatch.new,
                layers_obs:  LayersWatch.new,
                watched:     [],
                watched_ids: {}
            }
            @na_watches << watch                                                         # <-- Listed first, so WatchEntities finds it
            model.add_observer(watch[:model_obs])
            model.definitions.add_observer(watch[:defs_obs])
            model.selection.add_observer(watch[:sel_obs])
            model.layers.add_observer(watch[:layers_obs])
            self.Na__Observers__WatchEntities(model, model.entities)
            model.definitions.each do |definition|
                self.Na__Observers__WatchEntities(model, definition.entities) unless definition.image?
            end
            Na__AgentOutliner::Na__Tracker.Na__Tracker__Attach(model)
            watch
        rescue StandardError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Error('Watching the model failed; changes will not be tracked until it is reopened.', error)
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Stop Watching a Model
        # ------------------------------------------------------------
        def self.Na__Observers__Detach(model)
            watch = self.na_watch_for(model)
            return false unless watch

            watch[:watched].each do |entities|
                next unless self.na_entities_alive?(entities)                           # <-- An erased definition's: nothing to let go, and asking would raise (0.1.11)

                self.na_quietly { entities.remove_observer(watch[:ents_obs]) }
            end
            self.na_quietly { model.remove_observer(watch[:model_obs]) }
            self.na_quietly { model.selection.remove_observer(watch[:sel_obs]) }
            self.na_quietly { model.layers.remove_observer(watch[:layers_obs]) }
            @na_watches.delete(watch)
            Na__AgentOutliner::Na__Tracker.Na__Tracker__Detach(model)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Watch One More Entities Collection (a new definition's)
        # ------------------------------------------------------------
        def self.Na__Observers__WatchEntities(model, entities)
            watch = self.na_watch_for(model)
            return false unless watch
            return true if watch[:watched_ids][entities.object_id]                      # <-- A hash, not a list scan: thousands of definitions at attach

            entities.add_observer(watch[:ents_obs])
            watch[:watched] << entities
            watch[:watched_ids][entities.object_id] = true
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Forget the Watches on Erased Definitions (0.1.11)
        # ------------------------------------------------------------
        # A definition watched when it was added can be erased later (an undone
        # build, a rebuild, Purge): its Entities stay in the list, dead (179 of
        # 490 in the Assembly Studio testbed after a morning of builds and
        # undos). Run from the tracker's timer after a full pass, never inside a
        # callback. Returns how many were dropped.
        def self.Na__Observers__Prune(model)
            watch = self.na_watch_for(model)
            return 0 unless watch

            dropped = 0
            watch[:watched].select! do |entities|
                alive = self.na_entities_alive?(entities)
                unless alive
                    watch[:watched_ids].delete(entities.object_id)
                    dropped += 1
                end
                alive
            end
            dropped
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Model Watched?
        # ------------------------------------------------------------
        def self.Na__Observers__Watching?(model)
            self.na_watch_for(model) ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Release Every Model (tracking switched off with the dialog shut)
        # ------------------------------------------------------------
        def self.Na__Observers__DetachAll
            @na_watches.map { |watch| watch[:model] }.each { |model| self.Na__Observers__Detach(model) }
            true
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Observer Classes (each callback hands on and rescues)
# -----------------------------------------------------------------------------

        # CLASS | Models Opening, Switching and Closing
        # ------------------------------------------------------------
        class AppWatch < Sketchup::AppObserver
            def expectsStartupModelNotifications
                true
            end

            def onNewModel(model)
                Na__AgentOutliner::Na__Observers.na_on_model_shown(model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onNewModel', error)
            end

            def onOpenModel(model)
                Na__AgentOutliner::Na__Observers.na_on_model_shown(model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onOpenModel', error)
            end

            def onActivateModel(model)
                Na__AgentOutliner::Na__Observers.na_on_model_shown(model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onActivateModel', error)
            end

            # SketchUp 2027: fires just before a model closes, while it is valid.
            def onCloseModel(model)
                Na__AgentOutliner::Na__Observers.Na__Observers__Detach(model)
                Na__AgentOutliner::Na__DialogManager.Na__Dialog__ModelClosed(model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onCloseModel', error)
            end
        end
        # ---------------------------------------------------------------

        # CLASS | Operations, Undo, Redo, Open Groups, Saves
        # ------------------------------------------------------------
        class ModelWatch < Sketchup::ModelObserver
            def onTransactionStart(_model)
                Na__AgentOutliner::Na__ActorDetect.Na__Actor__TransactionStart
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onTransactionStart', error)
            end

            def onTransactionCommit(model)
                Na__AgentOutliner::Na__Tracker.Na__Tracker__OnCommit(model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onTransactionCommit', error)
            end

            def onTransactionAbort(model)
                Na__AgentOutliner::Na__Tracker.Na__Tracker__OnAbort(model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onTransactionAbort', error)
            end

            def onTransactionUndo(model)
                Na__AgentOutliner::Na__Tracker.Na__Tracker__OnUndoRedo(model, 'undo')
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onTransactionUndo', error)
            end

            def onTransactionRedo(model)
                Na__AgentOutliner::Na__Tracker.Na__Tracker__OnUndoRedo(model, 'redo')
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onTransactionRedo', error)
            end

            def onActivePathChanged(model)
                Na__AgentOutliner::Na__Tracker.Na__Tracker__OnActivePath(model)
                Na__AgentOutliner::Na__DialogManager.Na__Dialog__SelectionChanged(model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onActivePathChanged', error)
            end

            def onPostSaveModel(model)
                Na__AgentOutliner::Na__Tracker.Na__Tracker__OnSaved(model)
                Na__AgentOutliner::Na__DialogManager.Na__Dialog__ModelInfoChanged(model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onPostSaveModel', error)
            end

            # SketchUp renumbers persistent ids now and then (grouping, and a
            # definition copied in 2023.1): the next pass must be a full one.
            def onPidChanged(model, _old_pid, _new_pid)
                Na__AgentOutliner::Na__Tracker.Na__Tracker__OnFullNeeded(model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onPidChanged', error)
            end

            # SketchUp 2026 and earlier (deprecated from 2027.0).
            def onDeleteModel(model)
                Na__AgentOutliner::Na__Observers.Na__Observers__Detach(model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onDeleteModel', error)
            end
        end
        # ---------------------------------------------------------------

        # CLASS | Objects Added, Changed, Erased (in the model and every definition)
        # ------------------------------------------------------------
        class EntitiesWatch < Sketchup::EntitiesObserver
            def onElementAdded(entities, entity)
                Na__AgentOutliner::Na__Tracker.Na__Tracker__OnAdded(entities, entity)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onElementAdded', error)
            end

            def onElementModified(entities, entity)
                Na__AgentOutliner::Na__Tracker.Na__Tracker__OnModified(entities, entity)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onElementModified', error)
            end

            def onElementRemoved(entities, entity_id)
                Na__AgentOutliner::Na__Tracker.Na__Tracker__OnRemoved(entities, entity_id)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onElementRemoved', error)
            end
        end
        # ---------------------------------------------------------------

        # CLASS | New Definitions Get Watched Too
        # ------------------------------------------------------------
        class DefinitionsWatch < Sketchup::DefinitionsObserver
            def onComponentAdded(definitions, definition)
                # A definition added and erased in one operation (a rollback trial, a temporary make_unique copy)
                # arrives already deleted: any call on it raises. Nothing to watch (0.1.7).
                return unless definition.valid?
                return if definition.image?

                model = definitions.model
                return unless Na__AgentOutliner::Na__Observers.Na__Observers__Watching?(model)

                Na__AgentOutliner::Na__Observers.Na__Observers__WatchEntities(model, definition.entities)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onComponentAdded', error)
            end
        end
        # ---------------------------------------------------------------

        # CLASS | SketchUp's Selection (every callback, both spellings)
        # ------------------------------------------------------------
        class SelectionWatch < Sketchup::SelectionObserver
            def onSelectionBulkChange(selection)
                Na__AgentOutliner::Na__DialogManager.Na__Dialog__SelectionChanged(selection.model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onSelectionBulkChange', error)
            end

            def onSelectionCleared(selection)
                Na__AgentOutliner::Na__DialogManager.Na__Dialog__SelectionChanged(selection.model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onSelectionCleared', error)
            end

            def onSelectionAdded(selection, _entity)
                Na__AgentOutliner::Na__DialogManager.Na__Dialog__SelectionChanged(selection.model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onSelectionAdded', error)
            end

            def onSelectionRemoved(selection, _entity)
                Na__AgentOutliner::Na__DialogManager.Na__Dialog__SelectionChanged(selection.model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onSelectionRemoved', error)
            end

            def onSelectedRemoved(selection, _entity)
                Na__AgentOutliner::Na__DialogManager.Na__Dialog__SelectionChanged(selection.model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onSelectedRemoved', error)
            end
        end
        # ---------------------------------------------------------------

        # CLASS | Tags Shown, Hidden, Added, Removed (the dialog greys rows)
        # ------------------------------------------------------------
        class LayersWatch < Sketchup::LayersObserver
            def onLayerChanged(layers, _layer)
                Na__AgentOutliner::Na__Tracker.Na__Tracker__OnTagsChanged(layers.model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onLayerChanged', error)
            end

            def onLayerAdded(layers, _layer)
                Na__AgentOutliner::Na__Tracker.Na__Tracker__OnTagsChanged(layers.model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onLayerAdded', error)
            end

            def onLayerRemoved(layers, _layer)
                Na__AgentOutliner::Na__Tracker.Na__Tracker__OnTagsChanged(layers.model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onLayerRemoved', error)
            end

            def onLayerFolderChanged(layers, _folder)
                Na__AgentOutliner::Na__Tracker.Na__Tracker__OnTagsChanged(layers.model)
            rescue StandardError => error
                Na__AgentOutliner::Na__Observers.na_report('onLayerFolderChanged', error)
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        def self.na_install_now
            @na_install_timer = false
            unless @na_app_observer
                @na_app_observer = AppWatch.new
                Sketchup.add_observer(@na_app_observer)
            end
            return true unless Na__AgentOutliner::Na__Tracker.Na__Tracker__Enabled?

            model = Sketchup.active_model
            self.Na__Observers__Attach(model) if model
            true
        rescue StandardError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Error('Installing the Agent Outliner observers failed.', error)
            false
        end

        def self.na_on_model_shown(model)
            return unless model

            if Na__AgentOutliner::Na__Tracker.Na__Tracker__Enabled? || Na__AgentOutliner::Na__DialogManager.Na__Dialog__Visible?
                self.Na__Observers__Attach(model)
            end
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__ModelActivated(model)
        end

        # SketchUp before 2027 holds one model: a watch on any other is stale.
        def self.na_release_others(model)
            multiple = Sketchup.respond_to?(:mdi?) && Sketchup.mdi?
            @na_watches.dup.each do |watch|
                other = watch[:model]
                alive = begin
                    other.valid?
                rescue StandardError
                    false
                end
                next if alive && multiple
                next if self.na_same_model?(other, model)

                self.Na__Observers__Detach(other)
            end
        end

        def self.na_watch_for(model)
            @na_watches.find { |watch| self.na_same_model?(watch[:model], model) }
        end

        def self.na_same_model?(left, right)
            Na__AgentOutliner::Na__Tracker.na_same_model?(left, right)
        end

        def self.na_quietly
            yield
        rescue StandardError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("Releasing an observer: #{error.message}")
        end

        # An erased definition's Entities raise on every call and have no valid?:
        # asking for the parent is the cheapest test (0.1.11).
        def self.na_entities_alive?(entities)
            parent = entities.parent
            parent.respond_to?(:valid?) ? parent.valid? : true
        rescue StandardError
            false
        end

        # Logged every time; printed only the first few times per callback, so a
        # fault that fires on every edge never floods the Ruby Console.
        def self.na_report(callback, error)
            count = (@na_error_counts[callback] = @na_error_counts[callback].to_i + 1)
            if count <= 3
                Na__AgentOutliner::Na__DebugTools.Na__Debug__Error("Observer #{callback} failed.", error)
            else
                Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("Observer #{callback} failed again (#{count}): #{error.message}")
            end
        end

# endregion -------------------------------------------------------------------

    end # module Na__Observers
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
