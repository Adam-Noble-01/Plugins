# =============================================================================
# NA PROFILE TOOLS - APP CORE - HELPERS ENTITIES OBSERVER
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__HelpersEntitiesObserver__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer
# PURPOSE    : Sketchup::EntitiesObserver attached to each Helpers sub-group's
#              entities, plus Na__ObserverRegistry, the lifecycle manager that
#              keeps a keyed hash of active observer instances.
#
# ROLE IN THE SYSTEM (deliberately small)
#   This observer is only an ACCELERATOR. SketchUp's onElementModified does not
#   fire when an edge is moved or stretched (vertices change, not the edge),
#   and redo fires no entity events at all — so granular events cannot be the
#   source of truth. The Na__RegenSweep fingerprint pass is the source of
#   truth; this observer merely pokes it early when edges are drawn or erased
#   (the two events that ARE reliable).
#
# DESIGN NOTES
#   - All module state is guarded with `unless defined?` so the hot-reload
#     `load` cannot wipe the registry while observers are still attached
#     (this previously leaked observers and zeroed the Settings count).
#   - Registry entries record the helpers DEFINITION persistent_id. When
#     SketchUp auto-makes-unique a copied group on first edit, the instance
#     keeps its pid but swaps definitions — the recorded definition pid stops
#     matching, and Na__ObserverRegistry__AttachIfMissing re-attaches to the
#     fresh Entities collection.
#   - Every internal call uses an explicit `self.` receiver: these method
#     names start with a capital letter, so a bare reference parses as a
#     constant lookup and raises NameError inside the observer callback.
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer

# =============================================================================
# SECTION | Na__HelpersEntitiesObserver
# =============================================================================

    class Na__HelpersEntitiesObserver < Sketchup::EntitiesObserver

        def initialize(helpers_group)
            @na_helpers_group = helpers_group
        end

    # -------------------------------------------------------------------------
    # REGION | Observer Callbacks (queued by SketchUp until the operation ends)
    # -------------------------------------------------------------------------

        def onElementAdded(_entities, _element)
            self.Na__HelpersEntitiesObserver__Notify
        end

        def onElementRemoved(_entities, _element)
            self.Na__HelpersEntitiesObserver__Notify
        end

        def onElementModified(_entities, _element)
            self.Na__HelpersEntitiesObserver__Notify
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Sweep Hand-off
    # -------------------------------------------------------------------------

        private

        def Na__HelpersEntitiesObserver__Notify
            return if Na__RegenEngine.Na__RegenEngine__InProgress?

            unless @na_helpers_group && @na_helpers_group.respond_to?(:valid?) && @na_helpers_group.valid?
                Na__ObserverRegistry.Na__ObserverRegistry__HandleStaleObserver(self)
                return
            end

            Na__RegenSweep.Na__RegenSweep__ScheduleSweep('helpers-entities', full: false)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("HelpersObserver: notify failed: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    end

# =============================================================================
# SECTION | Na__ObserverRegistry
# =============================================================================

    module Na__ObserverRegistry

    # -------------------------------------------------------------------------
    # REGION | Module State (guarded so hot-reload `load` cannot wipe it)
    # -------------------------------------------------------------------------

        @na_registry = {} unless defined?(@na_registry)

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
            @na_registry[group_id] = {
                observer:       observer,
                helpers_group:  helpers_group,
                definition_pid: self.Na__ObserverRegistry__DefinitionPid(helpers_group)
            }

            Na__DebugTools.Na__Debug__Info("ObserverRegistry: attached to helpers group #{group_id}.")
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ObserverRegistry: attach failed: #{error.message}")
        end

        # No-op when a live observer is already bound to this exact group AND
        # its current definition. Re-attaches when the entry is missing, the
        # group died, or make-unique swapped the definition underneath it.
        def self.Na__ObserverRegistry__AttachIfMissing(helpers_group)
            return unless helpers_group && helpers_group.respond_to?(:valid?) && helpers_group.valid?

            group_id = self.Na__ObserverRegistry__SafePersistentId(helpers_group)
            return unless group_id

            entry = @na_registry[group_id]
            if entry
                recorded_group = entry[:helpers_group]
                same_group     = recorded_group && recorded_group.respond_to?(:valid?) &&
                                 recorded_group.valid? && self.Na__ObserverRegistry__SameEntity?(recorded_group, helpers_group)
                same_definition = entry[:definition_pid] &&
                                  entry[:definition_pid] == self.Na__ObserverRegistry__DefinitionPid(helpers_group)
                return if same_group && same_definition
            end

            self.Na__ObserverRegistry__AttachToHelpers(helpers_group)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ObserverRegistry: attach-if-missing failed: #{error.message}")
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

        # Called by an observer whose watched group has died (deleted/undone).
        # The pid is unreadable on a deleted entity, so look the entry up by
        # observer identity instead.
        def self.Na__ObserverRegistry__HandleStaleObserver(observer)
            stale_key = @na_registry.find { |_key, entry| entry[:observer].equal?(observer) }&.first
            self.Na__ObserverRegistry__DetachById(stale_key) if stale_key
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ObserverRegistry: stale cleanup failed: #{error.message}")
        end

        def self.Na__ObserverRegistry__PurgeInvalid
            @na_registry.keys.each do |group_id|
                entry = @na_registry[group_id]
                group = entry && entry[:helpers_group]
                next if group && group.respond_to?(:valid?) && group.valid?
                @na_registry.delete(group_id)
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ObserverRegistry: purge failed: #{error.message}")
        end

        def self.Na__ObserverRegistry__Count
            self.Na__ObserverRegistry__PurgeInvalid
            @na_registry.length
        end

        def self.Na__ObserverRegistry__HelpersGroups
            self.Na__ObserverRegistry__PurgeInvalid
            @na_registry.values.map { |entry| entry[:helpers_group] }.compact
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
            return nil if group.respond_to?(:valid?) && !group.valid?
            group.persistent_id
        rescue
            nil
        end

        def self.Na__ObserverRegistry__DefinitionPid(helpers_group)
            return nil unless helpers_group.respond_to?(:definition)
            definition = helpers_group.definition
            return nil unless definition && definition.respond_to?(:persistent_id)
            definition.persistent_id
        rescue
            nil
        end

        def self.Na__ObserverRegistry__SameEntity?(entity_a, entity_b)
            entity_a == entity_b
        rescue
            false
        end

    # endregion ----------------------------------------------------------------

    end

end

# =============================================================================
# END OF FILE
# =============================================================================
