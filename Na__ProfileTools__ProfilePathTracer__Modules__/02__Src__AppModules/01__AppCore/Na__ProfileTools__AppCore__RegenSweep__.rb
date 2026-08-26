# =============================================================================
# NA PROFILE TOOLS - APP CORE - REGEN SWEEP
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__RegenSweep__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__RegenSweep
# PURPOSE    : State-based change detection for Dynamic Regeneration.
#
# WHY THIS EXISTS (API research, Aug 2026)
#   SketchUp's EntitiesObserver#onElementModified does NOT fire when an edge is
#   moved or stretched — the Move tool changes vertex positions, not edge
#   properties (confirmed by SketchUp staff on the official forums). Redo
#   delivers no entity-modified events at all. Group copies share definitions,
#   and the first UI edit silently swaps in a fresh definition (auto
#   make-unique), orphaning any observer attached to the old Entities
#   collection. Chasing granular events is therefore unwinnable.
#
#   This module implements the pattern the commercial tools use instead
#   (Profile Builder rebuilds when path editing finishes): a FINGERPRINT of the
#   helper linework is stored on the assembly, and at cheap trigger points the
#   current linework is re-fingerprinted and compared. A mismatch — however it
#   was caused — triggers a rebuild. Observer identity no longer matters.
#
# TRIGGERS (all funnelled through one debounced timer)
#   ModelObserver#onActivePathChanged  - user closed a group edit      [full]
#   ModelObserver#onTransactionUndo    - undo                          [full]
#   ModelObserver#onTransactionRedo    - redo                          [full]
#   ModelObserver#onTransactionCommit  - deep edits by other tools     [light]
#   EntitiesObserver add/remove        - drawing/erasing helper edges  [light]
#   Dialog stats / context menu build  - self-heal on inspection       [full]
#
#   full  = walk the whole model for stamped assemblies. Reconciles observer
#           attachment and repairs duplicate ProfileTraceIds left by copies.
#   light = only assemblies already known to the observer registry.
#
# SELF-HEALING PERFORMED DURING A FULL SWEEP
#   - Missing / stale EntitiesObservers are re-attached (undo, redo, reload,
#     make-unique and copy drift all heal here).
#   - A copied assembly (duplicate ProfileTraceId) is made unique and
#     re-stamped with a fresh id, so each copy regenerates independently.
#   - Assemblies stamped before fingerprints existed adopt the current
#     linework as their baseline without triggering a rebuild.
#
# =============================================================================

require 'digest'

module Na__ProfileTools__ProfilePathTracer
    module Na__RegenSweep

    # -------------------------------------------------------------------------
    # REGION | Module State (guarded so hot-reload `load` cannot wipe it)
    # -------------------------------------------------------------------------

        @na_pending_timer       = nil   unless defined?(@na_pending_timer)
        @na_pending_full        = false unless defined?(@na_pending_full)
        @na_suspended           = false unless defined?(@na_suspended)
        @na_failed_fingerprints = {}    unless defined?(@na_failed_fingerprints)

        NA_SWEEP_DEBOUNCE_SECONDS = 0.25
        NA_FINGERPRINT_KEY        = 'HelpersFingerprint'.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Suspension (kill-switch support)
    # -------------------------------------------------------------------------

        def self.Na__RegenSweep__Suspend!
            @na_suspended = true
            self.Na__RegenSweep__CancelPendingTimer
        end

        def self.Na__RegenSweep__Resume!
            @na_suspended = false
        end

        def self.Na__RegenSweep__Suspended?
            @na_suspended == true
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Scheduling
    # -------------------------------------------------------------------------

        # Coalesces any number of triggers into one deferred pass. Runs from a
        # UI timer so no model writes ever happen inside an observer callback
        # (the documented crash vector for SketchUp observers).
        def self.Na__RegenSweep__ScheduleSweep(_reason, full: true)
            return if @na_suspended
            return if defined?(Na__RegenEngine) && Na__RegenEngine.Na__RegenEngine__InProgress?

            @na_pending_full = true if full
            return if @na_pending_timer

            @na_pending_timer = UI.start_timer(NA_SWEEP_DEBOUNCE_SECONDS, false) do
                @na_pending_timer = nil
                run_full         = @na_pending_full
                @na_pending_full = false
                self.Na__RegenSweep__SweepNow(full: run_full)
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("RegenSweep: schedule failed: #{error.message}")
        end

        def self.Na__RegenSweep__CancelPendingTimer
            return unless @na_pending_timer
            UI.stop_timer(@na_pending_timer) rescue nil
            @na_pending_timer = nil
            @na_pending_full  = false
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Sweep Execution
    # -------------------------------------------------------------------------

        def self.Na__RegenSweep__SweepNow(full: true)
            return if @na_suspended
            model = Sketchup.active_model
            return unless model
            return if Na__RegenEngine.Na__RegenEngine__InProgress?

            parents = full ?
                Na__DataSerializer.Na__DataSerializer__FindAllParentGroups(model) :
                self.Na__RegenSweep__RegistryParents
            parents = self.Na__RegenSweep__DedupeByPid(parents)

            self.Na__RegenSweep__RepairDuplicateTraceIds(model, parents) if full

            parents.each do |parent_group|
                self.Na__RegenSweep__CheckAssembly(model, parent_group)
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("RegenSweep: sweep failed: #{error.message}")
        end

        # Attach-only pass used by the stats readout and menu building — heals
        # observer drift without touching geometry, so it is safe anywhere.
        def self.Na__RegenSweep__ReconcileOnly(model)
            return unless model
            parents = Na__DataSerializer.Na__DataSerializer__FindAllParentGroups(model)
            self.Na__RegenSweep__DedupeByPid(parents).each do |parent_group|
                next unless Na__DataSerializer.Na__DataSerializer__DynamicRegenEnabled?(parent_group)
                helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
                next unless helpers_group
                Na__ObserverRegistry.Na__ObserverRegistry__AttachIfMissing(helpers_group)
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("RegenSweep: reconcile failed: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Fingerprinting
    # -------------------------------------------------------------------------

        # Order-independent hash of the helper linework in parent space (the
        # group's own transformation is included, so scaling or moving the
        # Helpers group instance also reads as a change). Rounded to 1e-4" so
        # float noise cannot register as an edit.
        def self.Na__RegenSweep__ComputeFingerprint(helpers_group)
            return nil unless Na__DataSerializer.Na__DataSerializer__GroupValid?(helpers_group)

            transform = helpers_group.transformation
            segments  = helpers_group.entities.grep(Sketchup::Edge).select(&:valid?).map do |edge|
                a = self.Na__RegenSweep__FormatPoint(edge.start.position.transform(transform))
                b = self.Na__RegenSweep__FormatPoint(edge.end.position.transform(transform))
                a < b ? "#{a}>#{b}" : "#{b}>#{a}"
            end
            Digest::SHA1.hexdigest(segments.sort.join('|'))
        rescue => error
            Na__DebugTools.Na__Debug__Warn("RegenSweep: fingerprint failed: #{error.message}")
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Per-Assembly Check
    # -------------------------------------------------------------------------

        def self.Na__RegenSweep__CheckAssembly(model, parent_group)
            return unless Na__DataSerializer.Na__DataSerializer__GroupValid?(parent_group)
            return unless Na__DataSerializer.Na__DataSerializer__DynamicRegenEnabled?(parent_group)

            helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
            return unless helpers_group

            # Self-heal: re-attach whenever the observer is missing or bound to
            # a stale Entities collection (make-unique, undo/redo, reload).
            Na__ObserverRegistry.Na__ObserverRegistry__AttachIfMissing(helpers_group)

            # Never rebuild while the user is inside the assembly — the
            # active-path change on exit re-triggers this sweep.
            return if self.Na__RegenSweep__InsideEditContext?(model, parent_group, helpers_group)

            current_fingerprint = self.Na__RegenSweep__ComputeFingerprint(helpers_group)
            return unless current_fingerprint

            stored_fingerprint = Na__DataSerializer.Na__DataSerializer__ReadHelpersFingerprint(parent_group)
            if stored_fingerprint.to_s.empty?
                self.Na__RegenSweep__AdoptBaseline(model, parent_group, current_fingerprint)
                return
            end
            return if stored_fingerprint == current_fingerprint

            # A linework state that already failed to sweep is not retried until
            # it changes again — otherwise every later trigger replays the same
            # failing rebuild (status spam + an aborted operation each time).
            parent_pid = self.Na__RegenSweep__SafePersistentId(parent_group)
            return if parent_pid && @na_failed_fingerprints[parent_pid] == current_fingerprint

            Na__DebugTools.Na__Debug__Info("RegenSweep: #{parent_group.name} path changed — rebuilding.")
            rebuilt = Na__RegenEngine.Na__RegenEngine__RegenerateFromHelpers(parent_group)
            if parent_pid
                if rebuilt
                    @na_failed_fingerprints.delete(parent_pid)
                else
                    @na_failed_fingerprints[parent_pid] = current_fingerprint
                end
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("RegenSweep: assembly check failed: #{error.message}")
        end

        # Assemblies stamped before fingerprints existed adopt the current
        # linework silently, so the first sweep after upgrading never fires a
        # surprise rebuild of every legacy trace in the model.
        def self.Na__RegenSweep__AdoptBaseline(model, parent_group, fingerprint)
            model.start_operation('Na__ProfilePathTracer__AdoptFingerprint', true, false, true)
            Na__DataSerializer.Na__DataSerializer__WriteHelpersFingerprint(parent_group, fingerprint)
            model.commit_operation
        rescue => error
            model.abort_operation rescue nil
            Na__DebugTools.Na__Debug__Warn("RegenSweep: baseline adopt failed: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Copy Repair
    # -------------------------------------------------------------------------

        # Copying a trace duplicates its ProfileTraceId and (until first edit)
        # shares its definition, so the copies cross-wire every id lookup. Each
        # duplicate is made unique — exactly what SketchUp itself would do on
        # first edit — then re-stamped with a fresh id and back-reference.
        def self.Na__RegenSweep__RepairDuplicateTraceIds(model, parents)
            by_id = {}
            parents.each do |parent_group|
                next unless Na__DataSerializer.Na__DataSerializer__GroupValid?(parent_group)
                trace_id = Na__DataSerializer.Na__DataSerializer__ReadTraceId(parent_group)
                next if trace_id.empty?
                (by_id[trace_id] ||= []) << parent_group
            end

            duplicates = by_id.select { |_id, groups| groups.length > 1 }
            return if duplicates.empty?

            model.start_operation('Na__ProfilePathTracer__RepairTraceIds', true, false, true)
            duplicates.each do |_id, groups|
                groups.drop(1).each do |duplicate_group|
                    duplicate_group.make_unique if duplicate_group.respond_to?(:make_unique)
                    new_id = Na__DataSerializer.Na__DataSerializer__GenerateNextProfileTraceId(model)
                    Na__DataSerializer.Na__DataSerializer__RestampTraceId(duplicate_group, new_id)
                    Na__DebugTools.Na__Debug__Info(
                        "RegenSweep: copied trace re-stamped as #{new_id} (#{duplicate_group.name})."
                    )
                end
            end
            model.commit_operation
        rescue => error
            model.abort_operation rescue nil
            Na__DebugTools.Na__Debug__Warn("RegenSweep: duplicate id repair failed: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Support
    # -------------------------------------------------------------------------

        def self.Na__RegenSweep__RegistryParents
            return [] unless defined?(Na__ObserverRegistry)
            Na__ObserverRegistry.Na__ObserverRegistry__HelpersGroups.map do |helpers_group|
                Na__DataSerializer.Na__DataSerializer__FindParentFromHelpers(helpers_group)
            end.compact
        rescue
            []
        end

        def self.Na__RegenSweep__DedupeByPid(parents)
            seen = {}
            Array(parents).select do |parent_group|
                pid = self.Na__RegenSweep__SafePersistentId(parent_group)
                next false if pid && seen[pid]
                seen[pid] = true if pid
                true
            end
        end

        # True while model.active_path contains this assembly or its Helpers.
        # Being inside an ANCESTOR is fine — only editing the assembly itself
        # while the rebuild rewrites its children has to be deferred.
        def self.Na__RegenSweep__InsideEditContext?(model, parent_group, helpers_group)
            active_path = model.active_path
            return false if active_path.nil? || active_path.empty?

            watched = [parent_group, helpers_group].compact
            active_path.any? do |instance|
                watched.any? { |entity| self.Na__RegenSweep__SameEntity?(instance, entity) }
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("RegenSweep: edit-context probe failed: #{error.message}")
            true
        end

        def self.Na__RegenSweep__SameEntity?(entity_a, entity_b)
            entity_a == entity_b
        rescue
            false
        end

        def self.Na__RegenSweep__SafePersistentId(entity)
            return nil unless entity && entity.respond_to?(:persistent_id)
            return nil if entity.respond_to?(:valid?) && !entity.valid?
            entity.persistent_id
        rescue
            nil
        end

        def self.Na__RegenSweep__FormatPoint(point)
            [point.x, point.y, point.z].map do |value|
                rounded = value.to_f.round(4)
                rounded = 0.0 if rounded.zero?
                format('%.4f', rounded)
            end.join(',')
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
