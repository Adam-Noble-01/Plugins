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
#   - Edit-context deferral: while model.active_path still contains the Helpers
#     group (or its parent assembly) the user has the group open. Rebuilding a
#     sibling sub-group from inside that context fails, so the timer re-arms at
#     350 ms and only regenerates once the group edit is closed.
#   - Every internal call MUST use an explicit `self.` receiver. These method
#     names start with a capital letter, so a bare reference parses as a
#     constant lookup and raises NameError inside the observer callback.
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

        DEBOUNCE_SECONDS         = 0.15
        EDIT_CONTEXT_POLL_SECONDS = 0.35

        def initialize(helpers_group)
            @na_helpers_group  = helpers_group
            @na_pending_timer  = nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Observer Callbacks
    # -------------------------------------------------------------------------

        def onElementAdded(_entities, _element)
            self.Na__HelpersEntitiesObserver__Schedule
        end

        def onElementRemoved(_entities, _element)
            self.Na__HelpersEntitiesObserver__Schedule
        end

        def onElementModified(_entities, _element)
            self.Na__HelpersEntitiesObserver__Schedule
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Debounced Schedule
    # -------------------------------------------------------------------------

        private

        def Na__HelpersEntitiesObserver__Schedule(delay_seconds = DEBOUNCE_SECONDS)
            return if Na__RegenEngine.Na__RegenEngine__InProgress?

            self.Na__HelpersEntitiesObserver__CancelPendingTimer
            @na_pending_timer = UI.start_timer(delay_seconds, false) do
                @na_pending_timer = nil
                self.Na__HelpersEntitiesObserver__FireRegen
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

            # The user is still inside the Helpers (or parent) edit context. Rebuilding
            # a sibling sub-group from in here fails silently, so wait for them to close
            # the group and re-check on the next tick.
            if self.Na__HelpersEntitiesObserver__InsideEditContext?
                self.Na__HelpersEntitiesObserver__Schedule(EDIT_CONTEXT_POLL_SECONDS)
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

        # True while model.active_path contains THIS observer's Helpers group or the
        # assembly that owns it. Scoped that tightly on purpose: matching any trace
        # assembly would set every attached observer polling whenever the user
        # opened an unrelated one. Being inside an ancestor is fine — the problem
        # is only editing a child while the rebuild writes to its parent.
        def Na__HelpersEntitiesObserver__InsideEditContext?
            model = Sketchup.active_model
            return false unless model

            active_path = model.active_path
            return false if active_path.nil? || active_path.empty?

            watched_ids = [
                self.Na__HelpersEntitiesObserver__SafePersistentId(@na_helpers_group),
                self.Na__HelpersEntitiesObserver__SafePersistentId(
                    Na__DataSerializer.Na__DataSerializer__ContainingInstance(@na_helpers_group)
                )
            ].compact
            return false if watched_ids.empty?

            active_path.any? do |instance|
                instance_id = self.Na__HelpersEntitiesObserver__SafePersistentId(instance)
                instance_id && watched_ids.include?(instance_id)
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("HelpersObserver: edit-context probe failed: #{error.message}")
            false
        end

        def Na__HelpersEntitiesObserver__SafePersistentId(entity)
            return nil unless entity && entity.respond_to?(:persistent_id)
            return nil if entity.respond_to?(:valid?) && !entity.valid?
            entity.persistent_id
        rescue
            nil
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
