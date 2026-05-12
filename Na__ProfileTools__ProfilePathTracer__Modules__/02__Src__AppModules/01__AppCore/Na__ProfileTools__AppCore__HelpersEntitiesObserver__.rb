# =============================================================================
# NA PROFILE TOOLS - APP CORE - HELPERS ENTITIES OBSERVER
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__HelpersEntitiesObserver__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer
# PURPOSE    : Sketchup::EntitiesObserver attached to each Helpers sub-group's
#              entities. When the user modifies the path-rail edges (add, remove,
#              move), a debounced timer fires Na__RegenEngine to rebuild the
#              SweptSolid sub-group.
#
#              Na__ObserverRegistry is the lifecycle manager — it keeps a keyed
#              hash of all active observer instances and provides
#              attach/detach/detach-all operations.
#
# DESIGN NOTES
#   - Re-entrancy guard: observer bails immediately if Na__RegenEngine is
#     already regenerating (avoids observer-inside-model-commit recursion).
#   - Debounce: 150 ms timer via UI.start_timer. The latest event cancels any
#     pending timer before scheduling a new one.
#   - Stale group guard: if helpers_group.valid? is false (group deleted or
#     undone) the pending timer callback self-detaches.
#   - DynamicRegenEnabled flag: regen is only triggered when the parent
#     assembly has this set to "true" in its AttributeDictionary.
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer

# =============================================================================
# SECTION | Na__HelpersEntitiesObserver
# =============================================================================

    class Na__HelpersEntitiesObserver < Sketchup::EntitiesObserver

    # -------------------------------------------------------------------------
    # REGION | Initialisation
    # -------------------------------------------------------------------------

        DEBOUNCE_SECONDS = 0.15

        def initialize(helpers_group)
            @na_helpers_group  = helpers_group
            @na_pending_timer  = nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Observer Callbacks
    # -------------------------------------------------------------------------

        def onElementAdded(_entities, _element)
            Na__HelpersEntitiesObserver__Schedule
        end

        def onElementRemoved(_entities, _element)
            Na__HelpersEntitiesObserver__Schedule
        end

        def onElementModified(_entities, _element)
            Na__HelpersEntitiesObserver__Schedule
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Debounced Schedule
    # -------------------------------------------------------------------------

        private

        def Na__HelpersEntitiesObserver__Schedule
            return if Na__RegenEngine.Na__RegenEngine__InProgress?

            Na__HelpersEntitiesObserver__CancelPendingTimer
            @na_pending_timer = UI.start_timer(DEBOUNCE_SECONDS, false) do
                @na_pending_timer = nil
                Na__HelpersEntitiesObserver__FireRegen
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("HelpersObserver: schedule failed: #{error.message}")
        end

        def Na__HelpersEntitiesObserver__CancelPendingTimer
            return unless @na_pending_timer
            UI.stop_timer(@na_pending_timer) rescue nil
            @na_pending_timer = nil
        end

        def Na__HelpersEntitiesObserver__FireRegen
            unless @na_helpers_group && @na_helpers_group.respond_to?(:valid?) && @na_helpers_group.valid?
                Na__ObserverRegistry.Na__ObserverRegistry__HandleStaleHelpers(@na_helpers_group)
                return
            end

            parent_group = Na__DataSerializer.Na__DataSerializer__FindParentFromHelpers(@na_helpers_group)
            unless parent_group
                Na__DebugTools.Na__Debug__Warn("HelpersObserver: parent group not found — skipping regen.")
                return
            end

            unless Na__DataSerializer.Na__DataSerializer__DynamicRegenEnabled?(parent_group)
                Na__DebugTools.Na__Debug__Info("HelpersObserver: DynRegen disabled on #{parent_group.name} — skipping.")
                return
            end
            return if Na__RegenEngine.Na__RegenEngine__InProgress?

            Na__DebugTools.Na__Debug__Info("HelpersObserver: firing regen for #{parent_group.name}.")
            Na__RegenEngine.Na__RegenEngine__RegenerateFromHelpers(parent_group)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("HelpersObserver: fire regen failed: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    end

# =============================================================================
# SECTION | Na__ObserverRegistry
# =============================================================================

    module Na__ObserverRegistry

    # -------------------------------------------------------------------------
    # REGION | Module State
    # -------------------------------------------------------------------------

        @na_registry = {}

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Attach / Detach
    # -------------------------------------------------------------------------

        def self.Na__ObserverRegistry__AttachToHelpers(helpers_group)
            return unless helpers_group && helpers_group.respond_to?(:valid?) && helpers_group.valid?

            group_id = self.Na__ObserverRegistry__SafePersistentId(helpers_group)
            return unless group_id

            self.Na__ObserverRegistry__DetachById(group_id)

            observer = Na__HelpersEntitiesObserver.new(helpers_group)
            helpers_group.entities.add_observer(observer)
            @na_registry[group_id] = { observer: observer, helpers_group: helpers_group }

            Na__DebugTools.Na__Debug__Info("ObserverRegistry: attached to helpers group #{group_id}.")
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ObserverRegistry: attach failed: #{error.message}")
        end

        def self.Na__ObserverRegistry__DetachFromHelpers(helpers_group)
            return unless helpers_group
            group_id = self.Na__ObserverRegistry__SafePersistentId(helpers_group)
            return unless group_id
            self.Na__ObserverRegistry__DetachById(group_id)
        end

        def self.Na__ObserverRegistry__DetachAll
            @na_registry.keys.each { |group_id| self.Na__ObserverRegistry__DetachById(group_id) }
            @na_registry.clear
        end

        def self.Na__ObserverRegistry__HandleStaleHelpers(helpers_group)
            group_id = self.Na__ObserverRegistry__SafePersistentId(helpers_group)
            return unless group_id
            self.Na__ObserverRegistry__DetachById(group_id)
        end

        def self.Na__ObserverRegistry__Count
            @na_registry.length
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private
    # -------------------------------------------------------------------------

        def self.Na__ObserverRegistry__DetachById(group_id)
            entry = @na_registry.delete(group_id)
            return unless entry

            helpers_group = entry[:helpers_group]
            observer      = entry[:observer]
            if helpers_group && helpers_group.respond_to?(:valid?) && helpers_group.valid?
                helpers_group.entities.remove_observer(observer) rescue nil
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ObserverRegistry: detach failed for #{group_id}: #{error.message}")
        end

        def self.Na__ObserverRegistry__SafePersistentId(group)
            return nil unless group && group.respond_to?(:persistent_id)
            group.persistent_id
        rescue
            nil
        end

    # endregion ----------------------------------------------------------------

    end

end

# =============================================================================
# END OF FILE
# =============================================================================
