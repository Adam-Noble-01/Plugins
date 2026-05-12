# =============================================================================
# NA PROFILE TOOLS - APP CORE - OBSERVERS
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__Observers__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__Observers
# PURPOSE    : Scene-source lifecycle observers (model switch + definition removal)
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__Observers

    # -------------------------------------------------------------------------
    # REGION | Internal State
    # -------------------------------------------------------------------------

        @na_app_observer = nil
        @na_definitions_observer = nil
        @na_attached_definitions = nil

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
                self.Na__Observers__AttachToAllStampedHelpers(active_model)
            end
        end

        def self.Na__Observers__UninstallExisting
            if @na_app_observer
                Sketchup.remove_observer(@na_app_observer) rescue nil
                @na_app_observer = nil
            end

            self.Na__Observers__DetachDefinitionsObserver
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
    # REGION | Dynamic Regen — Stamped Helpers Walker
    # -------------------------------------------------------------------------

        def self.Na__Observers__AttachToAllStampedHelpers(model)
            return unless model
            return unless defined?(Na__DataSerializer) && defined?(Na__ObserverRegistry)

            parent_groups = Na__DataSerializer.Na__DataSerializer__FindAllParentGroups(model)
            parent_groups.each do |parent_group|
                next unless Na__DataSerializer.Na__DataSerializer__DynamicRegenEnabled?(parent_group)
                helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
                next unless helpers_group
                Na__ObserverRegistry.Na__ObserverRegistry__AttachToHelpers(helpers_group)
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Observers: AttachToAllStampedHelpers failed: #{error.message}")
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
            Na__ProfileTools__ProfilePathTracer::Na__ObserverRegistry.Na__ObserverRegistry__DetachAll \
                if defined?(Na__ProfileTools__ProfilePathTracer::Na__ObserverRegistry)
            Na__ProfileTools__ProfilePathTracer::Na__Observers.Na__Observers__AttachDefinitionsObserver(model)
            Na__ProfileTools__ProfilePathTracer::Na__Observers.Na__Observers__ClearSceneRegistryAndNotify
            Na__ProfileTools__ProfilePathTracer::Na__Observers.Na__Observers__AttachToAllStampedHelpers(model)
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
end

# =============================================================================
# END OF FILE
# =============================================================================
