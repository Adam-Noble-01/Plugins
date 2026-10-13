# =============================================================================
# NA PROFILE TOOLS - APP CORE - REGEN SWEEP
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__RegenSweep__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__RegenSweep
# PURPOSE    : Finishes Edit Path. A trace stores its path as data (PathRuns);
#              Edit Path draws it as a red line inside the trace and opens it.
#              When the user leaves the trace, this sweep rebuilds the trace
#              along the edited line, stores it as the path, and erases the
#              line. It also keeps copied traces' ids unique, and rebuilds a
#              pre-v1.6.16 trace whose Helpers linework was edited by hand.
#
# WHY A SWEEP (API research, Aug 2026)
#   SketchUp's EntitiesObserver#onElementModified does NOT fire when an edge is
#   moved or stretched (the Move tool changes vertex positions, not edge
#   properties: SketchUp staff on the official forums), and redo delivers no
#   entity events at all. So nothing watches the red line while it is edited.
#   It carries a FINGERPRINT of itself as drawn, and at cheap, reliable moments
#   (above all the user leaving the trace) its current edges are fingerprinted
#   again and compared. This is the finish-to-rebuild loop Profile Builder's
#   Edit Path tool uses.
#
# TRIGGERS (all funnelled through one debounced timer)
#   ModelObserver#onActivePathChanged  - the user left or entered a context   [full]
#   ModelObserver#onTransactionCommit  - any change to the model              [light]
#   ModelObserver#onTransactionUndo    - undo                                 [full, passive]
#   ModelObserver#onTransactionRedo    - redo                                 [full, passive]
#   model opened / switched, plugin install, Settings stats                  [full, passive]
#
#   full    = walk the model's traces: watch every Edit Path line, repair
#             copied ids, look for hand-edited legacy Helpers linework.
#   light   = only the Edit Path lines already watched (none, most of the time).
#   passive = look, never change. A change made after an undo wipes the redo
#             stack, and an undo can bring back an Edit Path line whose rebuild
#             it has just taken away: finishing that line at once would redo the
#             edit the user has just undone. A model just opened is not changed
#             either. What a passive sweep finds waits for the next change the
#             user makes, and joins it (a transparent operation), so one undo
#             takes both back.
#
# FINISHING AN EDIT (Na__RegenSweep__FinishIfLeft)
#   still inside the trace        -> wait for the next trigger
#   the red line was erased       -> the empty group goes; the trace keeps its path
#   unchanged since it was drawn  -> the group goes, no rebuild
#   changed                       -> Na__RegenEngine__RegenerateTrace: the trace is
#                                    rebuilt along it, it becomes the stored path,
#                                    and the group goes, in one undo step with the
#                                    last edit
#   the rebuild fails             -> the line stays and says why; Edit Path reopens
#                                    it, Ctrl+Z steps back. The same failing line is
#                                    not retried until it changes.
#
# COORDINATE SPACE
#   Fingerprints are taken in the assembly's own (parent) space, through the
#   line's own transformation, and only while the assembly is closed: the line
#   is drawn with the trace closed and finished only once the user has left it.
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
        @na_pending_passive     = false unless defined?(@na_pending_passive)
        @na_suspended           = false unless defined?(@na_suspended)
        @na_failed_fingerprints = {}    unless defined?(@na_failed_fingerprints)
        @na_watched_edit_groups = {}    unless defined?(@na_watched_edit_groups)

        NA_SWEEP_DEBOUNCE_SECONDS = 0.25
        NA_FINGERPRINT_KEY        = 'HelpersFingerprint'.freeze
        NA_PASSIVE_REASONS        = %w[undo redo model-changed install stats].freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Suspension
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
        # (the documented crash vector for SketchUp observers). One passive
        # trigger in the window makes the whole pass passive.
        def self.Na__RegenSweep__ScheduleSweep(reason, full: true)
            return if @na_suspended
            @na_pending_passive = true if NA_PASSIVE_REASONS.include?(reason.to_s)
            return if defined?(Na__RegenEngine) && Na__RegenEngine.Na__RegenEngine__InProgress?

            @na_pending_full = true if full
            return if @na_pending_timer

            @na_pending_timer = UI.start_timer(NA_SWEEP_DEBOUNCE_SECONDS, false) do
                @na_pending_timer   = nil
                run_full            = @na_pending_full
                run_passive         = @na_pending_passive
                @na_pending_full    = false
                @na_pending_passive = false
                self.Na__RegenSweep__SweepNow(full: run_full, passive: run_passive)
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("RegenSweep: schedule failed: #{error.message}")
        end

        def self.Na__RegenSweep__CancelPendingTimer
            return unless @na_pending_timer
            UI.stop_timer(@na_pending_timer) rescue nil
            @na_pending_timer   = nil
            @na_pending_full    = false
            @na_pending_passive = false
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Sweep Execution
    # -------------------------------------------------------------------------

        def self.Na__RegenSweep__SweepNow(full: true, passive: false)
            return if @na_suspended
            model = Sketchup.active_model
            return unless model
            return if Na__RegenEngine.Na__RegenEngine__InProgress?

            parents = full ?
                self.Na__RegenSweep__DedupeByPid(Na__DataSerializer.Na__DataSerializer__FindAllParentGroups(model)) :
                []

            self.Na__RegenSweep__RepairDuplicateTraceIds(model, parents) if full && !passive

            parents.each do |parent_group|
                Na__DataSerializer.Na__DataSerializer__FindEditPathGroups(parent_group).each do |edit_group|
                    self.Na__RegenSweep__WatchEditGroup(edit_group)
                end
            end
            return if passive

            self.Na__RegenSweep__WatchedEditGroups.each do |edit_group|
                next if edit_group.respond_to?(:model) && edit_group.model != model
                self.Na__RegenSweep__FinishIfLeft(model, edit_group)
            end

            parents.each { |parent_group| self.Na__RegenSweep__CheckLegacyHelpers(model, parent_group) } if full
        rescue => error
            Na__DebugTools.Na__Debug__Warn("RegenSweep: sweep failed: #{error.message}")
        end

        # Edit Path calls this as it opens a line, so the light pass after every
        # edit knows the line without walking the model.
        def self.Na__RegenSweep__WatchEditGroup(edit_group)
            return unless Na__DataSerializer.Na__DataSerializer__GroupValid?(edit_group)
            pid = self.Na__RegenSweep__SafePersistentId(edit_group)
            @na_watched_edit_groups[pid] = edit_group if pid
        end

        def self.Na__RegenSweep__WatchedEditGroups
            @na_watched_edit_groups.delete_if { |_pid, group| !self.Na__RegenSweep__Live?(group) }
            @na_watched_edit_groups.values
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Fingerprinting
    # -------------------------------------------------------------------------

        # Order-independent hash of a group's edges in parent space (the
        # group's own transformation is included, so moving or scaling the
        # group instance also reads as a change). Rounded to 1e-4" so float
        # noise cannot register as an edit. Parent space only while the
        # assembly is closed, which every caller guarantees. Used for the Edit
        # Path line and, on a legacy trace, its Helpers group.
        def self.Na__RegenSweep__ComputeFingerprint(group)
            return nil unless Na__DataSerializer.Na__DataSerializer__GroupValid?(group)

            transform = group.transformation
            segments  = group.entities.grep(Sketchup::Edge).select(&:valid?).map do |edge|
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
    # REGION | Private - Finishing an Edit Path
    # -------------------------------------------------------------------------

        def self.Na__RegenSweep__FinishIfLeft(model, edit_group)
            return self.Na__RegenSweep__Unwatch(edit_group) unless Na__DataSerializer.Na__DataSerializer__GroupValid?(edit_group)

            # A line whose trace was exploded or deleted is not ours to finish.
            parent_group = Na__DataSerializer.Na__DataSerializer__FindParentFromEditGroup(edit_group)
            return self.Na__RegenSweep__Unwatch(edit_group) unless parent_group

            # Still editing (in the line, or in the trace around it): the exit
            # from the trace re-triggers this sweep.
            return if self.Na__RegenSweep__InsideEditContext?(model, parent_group, edit_group)

            if edit_group.entities.grep(Sketchup::Edge).none?(&:valid?)
                return self.Na__RegenSweep__DiscardEditGroup(
                    model, parent_group, edit_group, "the red path was erased, so #{parent_group.name} keeps its path."
                )
            end

            fingerprint = self.Na__RegenSweep__ComputeFingerprint(edit_group)
            return unless fingerprint

            info = Na__DataSerializer.Na__DataSerializer__EditPathGroupInfo(edit_group)
            if fingerprint == info['baseline'] && !info['forceRebuild']
                return self.Na__RegenSweep__DiscardEditGroup(
                    model, parent_group, edit_group, "path unchanged — #{parent_group.name} closed."
                )
            end

            # A line that already failed to sweep is not retried until it
            # changes again, or every later trigger would replay the failure.
            parent_pid = self.Na__RegenSweep__SafePersistentId(parent_group)
            return if parent_pid && @na_failed_fingerprints[parent_pid] == fingerprint

            Na__DebugTools.Na__Debug__Info("RegenSweep: #{parent_group.name} path edited — rebuilding.")
            if Na__RegenEngine.Na__RegenEngine__RegenerateTrace(parent_group)
                @na_failed_fingerprints.delete(parent_pid) if parent_pid
                self.Na__RegenSweep__Unwatch(edit_group)
            else
                @na_failed_fingerprints[parent_pid] = fingerprint if parent_pid
                Sketchup.status_text =
                    "Profile Path Tracer: the edited path of #{parent_group.name} could not be swept " \
                    "(#{Na__RegenEngine.Na__RegenEngine__LastFailure}). Its red path is kept: " \
                    'Edit Path reopens it, Ctrl+Z steps back.'
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("RegenSweep: finishing an edit failed: #{error.message}")
        end

        # Transparent: it joins the operation before it (the spawn, or the
        # user's last edit), so closing an unchanged line leaves no undo step.
        def self.Na__RegenSweep__DiscardEditGroup(model, parent_group, edit_group, message)
            model.start_operation('Na__ProfilePathTracer__EditPathClose', true, false, true)
            parent_group.entities.erase_entities([edit_group]) if edit_group.valid?
            model.commit_operation
            self.Na__RegenSweep__Unwatch(edit_group)
            Sketchup.status_text = "Profile Path Tracer: #{message}"
        rescue => error
            model.commit_operation rescue nil
            Na__DebugTools.Na__Debug__Warn("RegenSweep: closing the path line failed: #{error.message}")
        end

        def self.Na__RegenSweep__Unwatch(edit_group)
            @na_watched_edit_groups.delete_if do |_pid, group|
                group.equal?(edit_group) || !self.Na__RegenSweep__Live?(group)
            end
            nil
        end

        def self.Na__RegenSweep__Live?(group)
            group.respond_to?(:valid?) && group.valid?
        rescue
            false
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Legacy Helpers Linework (traces built before v1.6.16)
    # -------------------------------------------------------------------------

        # A legacy trace keeps its path as edges in a Helpers group, which the
        # user can still double-click into and edit by hand. When that linework
        # no longer matches the fingerprint the solid was built from, the trace
        # is rebuilt along it, and the rebuild moves it onto stored data,
        # erasing the Helpers group. A legacy trace never fingerprinted, or one
        # whose regeneration was switched off, is left as it is.
        def self.Na__RegenSweep__CheckLegacyHelpers(model, parent_group)
            return unless Na__DataSerializer.Na__DataSerializer__GroupValid?(parent_group)
            helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
            return unless helpers_group
            return if Na__DataSerializer.Na__DataSerializer__LegacyRegenSwitchedOff?(parent_group)
            return if self.Na__RegenSweep__InsideEditContext?(model, parent_group, helpers_group)

            stored_fingerprint = Na__DataSerializer.Na__DataSerializer__ReadHelpersFingerprint(parent_group)
            return if stored_fingerprint.to_s.empty?

            current_fingerprint = self.Na__RegenSweep__ComputeFingerprint(helpers_group)
            return if current_fingerprint.nil? || current_fingerprint == stored_fingerprint

            parent_pid = self.Na__RegenSweep__SafePersistentId(parent_group)
            return if parent_pid && @na_failed_fingerprints[parent_pid] == current_fingerprint

            Na__DebugTools.Na__Debug__Info("RegenSweep: #{parent_group.name} legacy helper linework edited — rebuilding.")
            rebuilt = Na__RegenEngine.Na__RegenEngine__RegenerateTrace(parent_group)
            if parent_pid
                if rebuilt
                    @na_failed_fingerprints.delete(parent_pid)
                else
                    @na_failed_fingerprints[parent_pid] = current_fingerprint
                end
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("RegenSweep: legacy helpers check failed: #{error.message}")
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
            model.commit_operation rescue nil
            Na__DebugTools.Na__Debug__Warn("RegenSweep: duplicate id repair failed: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Support
    # -------------------------------------------------------------------------

        def self.Na__RegenSweep__DedupeByPid(parents)
            seen = {}
            Array(parents).select do |parent_group|
                pid = self.Na__RegenSweep__SafePersistentId(parent_group)
                next false if pid && seen[pid]
                seen[pid] = true if pid
                true
            end
        end

        # True while model.active_path contains this assembly or the group
        # inside it. Being inside an ANCESTOR is fine — only editing the
        # assembly itself while the rebuild rewrites its children has to wait.
        def self.Na__RegenSweep__InsideEditContext?(model, parent_group, child_group)
            active_path = model.active_path
            return false if active_path.nil? || active_path.empty?

            watched = [parent_group, child_group].compact
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
