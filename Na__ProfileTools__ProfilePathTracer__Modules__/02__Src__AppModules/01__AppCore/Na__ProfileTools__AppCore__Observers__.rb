# =============================================================================
# NA PROFILE TOOLS - APP CORE - OBSERVERS
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__Observers__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__Observers
# PURPOSE    : Application-level observer lifecycle.
#
# OBSERVERS INSTALLED
#   Na__AppObserver          (Sketchup)          model switch / open / new
#   Na__DefinitionsObserver  (model.definitions) scene-profile registry hygiene
#   Na__ModelObserver        (model)             Edit Path triggers (Na__RegenSweep):
#       onActivePathChanged   -> full sweep (the user left the trace: THE
#                                moment an edited red line is read, since
#                                onElementModified never fires for a moved edge)
#       onTransactionUndo/Redo-> full, passive sweep (looks, never changes:
#                                redo fires no entity events at all, and a change
#                                made now would wipe the redo stack)
#       onTransactionCommit   -> light sweep (only red lines already watched)
#
#   No observer is attached to any trace (v1.6.16). Until v1.6.15 each trace's
#   Helpers linework carried an EntitiesObserver; a reload detaches any still
#   attached from the session that ran the older code.
#
# RELOAD SAFETY
#   All module ivars are `unless defined?` guarded: the Settings tab hot-reload
#   re-`load`s this file, and an unguarded assignment would orphan the live
#   observer references, making them impossible to remove.
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__Observers

    # -------------------------------------------------------------------------
    # REGION | Internal State (guarded so hot-reload `load` cannot wipe it)
    # -------------------------------------------------------------------------

        @na_app_observer         = nil unless defined?(@na_app_observer)
        @na_definitions_observer = nil unless defined?(@na_definitions_observer)
        @na_attached_definitions = nil unless defined?(@na_attached_definitions)
        @na_model_observer       = nil unless defined?(@na_model_observer)
        @na_observed_model       = nil unless defined?(@na_observed_model)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Installation Surface
    # -------------------------------------------------------------------------

        def self.Na__Observers__InstallOnce
            self.Na__Observers__UninstallExisting
            @na_app_observer = Na__AppObserver.new
            Sketchup.add_observer(@na_app_observer)

            active_model = Sketchup.active_model
            if active_model
                self.Na__Observers__AttachDefinitionsObserver(active_model)
                self.Na__Observers__AttachModelObserver(active_model)
            end

            # Re-arm the sweep and run a deferred, passive pass so a red line
            # saved in the model (a path edit left open) is watched again.
            if defined?(Na__RegenSweep)
                Na__RegenSweep.Na__RegenSweep__Resume!
                Na__RegenSweep.Na__RegenSweep__ScheduleSweep('install', full: true)
            end
        end

        def self.Na__Observers__Installed?
            !@na_app_observer.nil?
        end

        def self.Na__Observers__UninstallExisting
            if @na_app_observer
                Sketchup.remove_observer(@na_app_observer) rescue nil
                @na_app_observer = nil
            end

            self.Na__Observers__DetachDefinitionsObserver
            self.Na__Observers__DetachModelObserver
            # The Helpers EntitiesObservers v1.6.15 attached, if this session
            # loaded that code before a Reload Plugin Data.
            Na__ObserverRegistry.Na__ObserverRegistry__DetachAll if defined?(Na__ObserverRegistry)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Definitions Observer Attachment
    # -------------------------------------------------------------------------

        def self.Na__Observers__AttachDefinitionsObserver(model)
            return unless model
            self.Na__Observers__DetachDefinitionsObserver

            @na_definitions_observer = Na__DefinitionsObserver.new
            @na_attached_definitions = model.definitions
            @na_attached_definitions.add_observer(@na_definitions_observer)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Observers attach failed: #{error.message}")
        end

        def self.Na__Observers__DetachDefinitionsObserver
            return unless @na_definitions_observer && @na_attached_definitions

            @na_attached_definitions.remove_observer(@na_definitions_observer) rescue nil
            @na_definitions_observer = nil
            @na_attached_definitions = nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Model Observer Attachment (Dynamic Regeneration triggers)
    # -------------------------------------------------------------------------

        def self.Na__Observers__AttachModelObserver(model)
            return unless model
            self.Na__Observers__DetachModelObserver

            @na_model_observer = Na__ModelObserver.new
            @na_observed_model = model
            model.add_observer(@na_model_observer)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Observers: model observer attach failed: #{error.message}")
        end

        def self.Na__Observers__DetachModelObserver
            return unless @na_model_observer

            if @na_observed_model
                @na_observed_model.remove_observer(@na_model_observer) rescue nil
            end
            @na_model_observer = nil
            @na_observed_model = nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Registry Invalidation + UI Notification
    # -------------------------------------------------------------------------

        def self.Na__Observers__ClearSceneRegistryAndNotify
            Na__SceneProfileRegistry.Na__SceneProfileRegistry__Clear
            if defined?(Na__DialogManager)
                Na__DialogManager.Na__Dialog__PushSceneProfileStatus('Scene profile source cleared by model change.')
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Observer notify failed: #{error.message}")
        end

        def self.Na__Observers__ValidateRegistryDefinition(definition)
            stored_pid = Na__SceneProfileRegistry.Na__SceneProfileRegistry__DefinitionPersistentId
            return unless stored_pid
            definition_pid = self.Na__Observers__SafeDefinitionPersistentId(definition)
            return unless definition_pid
            return unless definition_pid == stored_pid

            self.Na__Observers__ClearSceneRegistryAndNotify
        end

        def self.Na__Observers__SafeDefinitionPersistentId(definition)
            return nil unless definition
            return nil if definition.respond_to?(:valid?) && definition.valid? == false
            return nil unless definition.respond_to?(:persistent_id)
            definition.persistent_id
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Observer definition pid lookup skipped: #{error.message}")
            nil
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# REGION | Observer Classes
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    class Na__AppObserver < Sketchup::AppObserver
        def expectsStartupModelNotifications
            true
        end

        def onNewModel(model)
            Na__Observers__HandleModelChange(model)
        end

        def onOpenModel(model)
            Na__Observers__HandleModelChange(model)
        end

        def onActivateModel(model)
            Na__Observers__HandleModelChange(model)
        end

        private

        def Na__Observers__HandleModelChange(model)
            Na__ProfileTools__ProfilePathTracer::Na__Observers.Na__Observers__AttachDefinitionsObserver(model)
            Na__ProfileTools__ProfilePathTracer::Na__Observers.Na__Observers__AttachModelObserver(model)
            Na__ProfileTools__ProfilePathTracer::Na__Observers.Na__Observers__ClearSceneRegistryAndNotify
            Na__ProfileTools__ProfilePathTracer::Na__RegenSweep.Na__RegenSweep__ScheduleSweep('model-changed', full: true) \
                if defined?(Na__ProfileTools__ProfilePathTracer::Na__RegenSweep)
        end
    end

    class Na__DefinitionsObserver < Sketchup::DefinitionsObserver
        def onComponentRemoved(_definitions, definition)
            return unless definition
            Na__ProfileTools__ProfilePathTracer::Na__Observers.Na__Observers__ValidateRegistryDefinition(definition)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Definitions observer callback failed: #{error.message}")
        end
    end

    # Edit Path triggers. Callbacks only ever SCHEDULE the deferred sweep —
    # never touch the model directly — because model edits inside observer
    # callbacks are the documented SketchUp crash vector.
    class Na__ModelObserver < Sketchup::ModelObserver
        def onActivePathChanged(_model)
            Na__ProfileTools__ProfilePathTracer::Na__RegenSweep.Na__RegenSweep__ScheduleSweep('active-path-changed', full: true)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ModelObserver: path-change handling failed: #{error.message}")
        end

        def onTransactionUndo(_model)
            Na__ProfileTools__ProfilePathTracer::Na__RegenSweep.Na__RegenSweep__ScheduleSweep('undo', full: true)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ModelObserver: undo handling failed: #{error.message}")
        end

        def onTransactionRedo(_model)
            Na__ProfileTools__ProfilePathTracer::Na__RegenSweep.Na__RegenSweep__ScheduleSweep('redo', full: true)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ModelObserver: redo handling failed: #{error.message}")
        end

        def onTransactionCommit(_model)
            Na__ProfileTools__ProfilePathTracer::Na__RegenSweep.Na__RegenSweep__ScheduleSweep('commit', full: false)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ModelObserver: commit handling failed: #{error.message}")
        end
    end
end

# =============================================================================
# REGION | Auto-install at load
# =============================================================================
# Edit Path must finish in every session — including ones where the dialog is
# never opened (the right-click Edit Path works without it). Guarded so the
# hot reload `load` does not stack duplicates; the reload path re-installs
# explicitly via Na__Observers__InstallOnce.

unless Na__ProfileTools__ProfilePathTracer::Na__Observers.Na__Observers__Installed?
    UI.start_timer(0.5, false) do
        begin
            Na__ProfileTools__ProfilePathTracer::Na__Observers.Na__Observers__InstallOnce \
                unless Na__ProfileTools__ProfilePathTracer::Na__Observers.Na__Observers__Installed?
        rescue => error
            puts "[Na__ProfilePathTracer][WARN] Observer auto-install failed: #{error.message}"
        end
    end
end

# =============================================================================
# END OF FILE
# =============================================================================
