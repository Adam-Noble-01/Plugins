# =============================================================================
# NA AGENT OUTLINER - CHANGE TRACKING - TRACKER
# =============================================================================
#
# FILE       : Na__AgentOutliner__ChangeTracking__Tracker__.rb
# NAMESPACE  : Na__AgentOutliner::Na__Tracker
# MODULE     : Na__Tracker (module functions)
# AUTHOR     : Noble Architecture
# PURPOSE    : Keep, for every open model, a live map of its Outliner objects
#              and notice which are new, changed or gone after each operation,
#              and whether Adam or an agent did it
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - OBSERVERS ONLY TAKE NOTES. Every callback (Na__Observers) records what
#   it was told in the model's pending list and books ONE timer; the timer
#   runs Na__Tracker__Reconcile. Nothing is ever changed in the model here:
#   change history goes to the history file (Na__HistoryStore).
# - CALLBACKS ARE HINTS, STATE IS THE TRUTH. SketchUp's observers miss things
#   (no event for moved edges, none at all on redo), so a reconcile compares
#   fingerprints:
#     full pass     every object's fingerprint and every definition's cheap
#                   signature, against the last pass. Runs on: the first look
#                   at a model, undo and redo, an agent's operation (the MCP
#                   calls are discrete, so the whole model is checked after
#                   each), Refresh, and a persistent id change.
#     targeted pass after Adam's own operations: only what the events named,
#                   plus whatever is selected (a moved group may raise no
#                   event) and the group he has open (its precise signature
#                   catches vertex moves that change no count and no extent).
#   An agent's changes are always caught at their commit, so anything a later
#   full pass finds that no event explained is Adam's.
# - UNDO AND REDO are credited to whoever pressed them: the stack is read at
#   their own notice and held for the events they raise (0.1.11). After each
#   full pass the watches on erased definitions are pruned (Na__Observers).
# - BIG MODELS: when a full pass takes longer than engine.full_pass_budget_ms,
#   agent operations switch to the targeted pass for that model, so an agent
#   working in a huge model is not slowed by the tracker.
# - WHAT COUNTS: new objects, erased objects, and changes to name, tag,
#   material, transform (move, rotate, scale), definition (made unique or
#   swapped) and contents (the geometry inside). Hiding and locking count only
#   when switched on in Settings (Adam hides things all day).
# - ONE STATE PER MODEL (SketchUp 2027 opens several in tabs), found by model,
#   never by Sketchup.active_model, and dropped when the model closes.
#
# =============================================================================

module Na__AgentOutliner
    module Na__Tracker

# -----------------------------------------------------------------------------
# REGION | Constants and State
# -----------------------------------------------------------------------------

        NA_SUBTREE_DEPTH = 32 unless defined?(NA_SUBTREE_DEPTH)
        NA_USER          = { 'by' => 'user', 'tool' => nil }.freeze unless defined?(NA_USER)

        @na_states = [] unless defined?(@na_states)                                     # <-- Kept across Reload Plugin Data, so the live maps survive a reload

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | States (one per open model)
# -----------------------------------------------------------------------------

        # FUNCTION | The State of a Model (created on request)
        # ------------------------------------------------------------
        def self.Na__Tracker__StateFor(model, create: false)
            return nil unless model

            state = @na_states.find { |item| self.na_same_model?(item[:model], model) }
            return state if state || !create

            key   = Na__AgentOutliner::Na__HistoryStore.Na__History__KeyFor(model)
            state = {
                model:        model,
                key:          key,
                history:      Na__AgentOutliner::Na__HistoryStore.Na__History__Load(model, key),
                baseline:     false,
                fps:          {},
                refs:         {},
                labels:       {},
                notes:        {},
                eid_pid:      {},
                parent_of:    {},
                children:     {},
                defs:         {},
                def_sigs:     {},
                active_sig:   nil,
                pending:      self.na_new_pending,
                timer:        nil,
                save_timer:   nil,
                scanned:      false,
                capped:       false,
                agent_full:   true,
                last_pass:    nil
            }
            @na_states << state
            state
        end
        # ---------------------------------------------------------------

        # FUNCTION | Start Tracking a Model (the first look is booked, not run)
        # ------------------------------------------------------------
        def self.Na__Tracker__Attach(model)
            state = self.Na__Tracker__StateFor(model, create: true)
            unless state[:baseline]
                delay = Na__AgentOutliner::Na__ConfigStore.Na__Config__Engine('baseline_delay_s', 1.5).to_f
                self.na_schedule(state, delay)
            end
            state
        end
        # ---------------------------------------------------------------

        # FUNCTION | Stop Tracking a Model (its history is written first)
        # ------------------------------------------------------------
        def self.Na__Tracker__Detach(model)
            state = self.Na__Tracker__StateFor(model)
            return false unless state

            self.na_stop_timers(state)
            self.na_save_state(state)
            @na_states.delete(state)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Model Being Tracked
        # ------------------------------------------------------------
        def self.Na__Tracker__Models
            @na_states.map { |state| state[:model] }
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Object of a Model by Persistent Id (nil when unknown or gone)
        # ------------------------------------------------------------
        def self.Na__Tracker__EntityById(model, pid)
            state = self.Na__Tracker__StateFor(model)
            entity = state && state[:refs][pid.to_i]
            entity && entity.valid? ? entity : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Make Sure a Model Has Had Its First Look (runs it now if not)
        # ------------------------------------------------------------
        def self.Na__Tracker__Ready(model)
            state = self.Na__Tracker__StateFor(model, create: true)
            unless state[:baseline]
                self.na_full_pass(state, nil, scan: true)
                state[:baseline] = true
                self.na_sign_active(state)
            end
            state
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Observer Notes (called by Na__Observers; record and book, nothing more)
# -----------------------------------------------------------------------------

        def self.Na__Tracker__OnAdded(entities, entity)
            state = self.na_state_for_entities(entities)
            return unless state

            actor = Na__AgentOutliner::Na__ActorDetect.Na__Actor__Current
            if Na__AgentOutliner::Na__Walker.Na__Walker__Kind(entity)
                state[:pending][:added][entity] = actor
            else
                key = self.na_container_key(entities)
                state[:pending][:dirty_defs][key] ||= actor unless key == Na__AgentOutliner::Na__Walker::NA_ROOT_KEY
            end
            self.na_schedule(state)
        end

        def self.Na__Tracker__OnModified(entities, entity)
            state = self.na_state_for_entities(entities)
            return unless state

            actor = Na__AgentOutliner::Na__ActorDetect.Na__Actor__Current
            if Na__AgentOutliner::Na__Walker.Na__Walker__Kind(entity)
                state[:pending][:modified][entity] ||= actor
            else
                key = self.na_container_key(entities)
                state[:pending][:dirty_defs][key] ||= actor unless key == Na__AgentOutliner::Na__Walker::NA_ROOT_KEY
            end
            self.na_schedule(state)
        end

        def self.Na__Tracker__OnRemoved(entities, entity_id)
            state = self.na_state_for_entities(entities)
            return unless state

            actor = Na__AgentOutliner::Na__ActorDetect.Na__Actor__Current
            pid = state[:eid_pid][entity_id.to_i]
            if pid
                state[:pending][:removed][pid] ||= actor
            else
                key = self.na_container_key(entities)
                state[:pending][:dirty_defs][key] ||= actor unless key == Na__AgentOutliner::Na__Walker::NA_ROOT_KEY
            end
            self.na_schedule(state)
        end

        def self.Na__Tracker__OnCommit(model)
            actor = Na__AgentOutliner::Na__ActorDetect.Na__Actor__TransactionEnd
            state = self.Na__Tracker__StateFor(model)
            return unless state

            pending = state[:pending]
            pending[:commit_actor] = actor
            pending[:check_active] = true
            pending[:full] = true if actor['by'] == 'agent' && state[:agent_full]
            self.na_schedule(state)
        end

        def self.Na__Tracker__OnAbort(model)
            Na__AgentOutliner::Na__ActorDetect.Na__Actor__TransactionEnd
            Na__AgentOutliner::Na__Notes.Na__Notes__Touch                               # <-- 0.1.9: an aborted step may have taken a comment back
            state = self.Na__Tracker__StateFor(model)
            self.na_schedule(state) if state                                            # <-- Events an aborted step raised point at entities that are now gone
        end

        def self.Na__Tracker__OnUndoRedo(model, via)
            Na__AgentOutliner::Na__Notes.Na__Notes__Touch                               # <-- 0.1.9: undo and redo can take a comment or flag away, or bring it back
            state = self.Na__Tracker__StateFor(model)
            return unless state

            pending = state[:pending]
            pending[:commit_actor] = Na__AgentOutliner::Na__ActorDetect.Na__Actor__UndoRedo   # <-- 0.1.11: read here and held for the events this undo raises; a stale held answer is dropped
            pending[:full] = true
            pending[:scan] = true
            pending[:via]  = via
            pending[:check_active] = false
            self.na_schedule(state)
        end

        def self.Na__Tracker__OnFullNeeded(model)
            state = self.Na__Tracker__StateFor(model)
            return unless state

            state[:pending][:full] = true
            self.na_schedule(state)
        end

        def self.Na__Tracker__OnActivePath(model)
            state = self.Na__Tracker__StateFor(model)
            return unless state

            state[:pending][:sign_active] = true
            self.na_schedule(state)
        end

        def self.Na__Tracker__OnSaved(model)
            state = self.Na__Tracker__StateFor(model)
            return unless state

            key = Na__AgentOutliner::Na__HistoryStore.Na__History__KeyFor(model)
            state[:key] = key if key                                                    # <-- Save As keeps the history under the new file name
            self.na_save_state(state)
        end

        def self.Na__Tracker__OnTagsChanged(model)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__TagsChanged(model)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reconcile (run from the booked timer)
# -----------------------------------------------------------------------------

        # FUNCTION | Compare the Model With the Live Map and Record What Changed
        # ------------------------------------------------------------
        def self.Na__Tracker__Reconcile(model)
            state = self.Na__Tracker__StateFor(model)
            return unless state

            state[:timer] = nil
            return self.Na__Tracker__Detach(model) unless self.na_model_alive?(model)

            pending = state[:pending]
            state[:pending] = self.na_new_pending

            unless state[:baseline]
                self.na_full_pass(state, nil, scan: true)
                state[:baseline] = true
                self.na_sign_active(state)
                Na__AgentOutliner::Na__DialogManager.Na__Dialog__TrackerReady(model)
                return
            end

            started = self.na_clock
            changes = {}
            touched = {}
            if pending[:full]
                self.na_full_pass(state, pending, scan: pending[:scan], changes: changes, touched: touched)
                Na__AgentOutliner::Na__Observers.Na__Observers__Prune(model)              # <-- 0.1.11: watches on erased definitions go (an undone build, a rebuild, Purge)
            else
                self.na_targeted_pass(state, pending, changes, touched)
            end
            self.na_check_active_context(state, pending, changes) if pending[:check_active] || pending[:sign_active]

            records = self.Na__Tracker__Enabled? ? self.na_record(state, changes, pending[:via]) : []
            elapsed = ((self.na_clock - started) * 1000.0).round(1)
            state[:last_pass] = { 'kind' => pending[:full] ? 'full' : 'targeted', 'ms' => elapsed, 'at' => Na__AgentOutliner.Na__Time__Now }
            self.na_tune_agent_mode(state, pending, elapsed)

            changes.each_key { |pid| touched[pid] = true }
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__TrackerUpdated(model, touched.keys, records, pending[:containers].keys)
        rescue StandardError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Error('Change tracking could not reconcile the model.', error)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Run a Booked Reconcile Now (an agent asks before the timer fires)
        # ------------------------------------------------------------
        # The MCP answers requests from the same timer pump the reconcile waits
        # on, so an agent asking "what changed" straight after its own edit
        # would otherwise read the history one step behind.
        def self.Na__Tracker__Flush(model)
            state = self.Na__Tracker__Ready(model)
            return state unless state[:timer]

            UI.stop_timer(state[:timer])
            state[:timer] = nil
            self.Na__Tracker__Reconcile(model)
            state
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Full Pass on Request (dialog opened, Refresh pressed)
        # ------------------------------------------------------------
        # Anything found here that no event explained is Adam's: an agent's
        # changes are caught at their own commit.
        def self.Na__Tracker__Refresh(model, scan: true)
            state = self.Na__Tracker__Ready(model)
            changes = {}
            touched = {}
            pending = self.na_new_pending
            pending[:commit_actor] = NA_USER
            self.na_full_pass(state, pending, scan: scan, changes: changes, touched: touched)
            records = self.Na__Tracker__Enabled? ? self.na_record(state, changes, nil) : []
            records
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | What the Dialog and the MCP Seam Read
# -----------------------------------------------------------------------------

        # FUNCTION | Is Change Tracking Switched On? (Settings)
        # ------------------------------------------------------------
        def self.Na__Tracker__Enabled?
            Na__AgentOutliner::Na__ConfigStore.Na__Config__Setting('tracking', 'enabled') != false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Live Object of a Model: { pid => entity }
        # ------------------------------------------------------------
        def self.Na__Tracker__Refs(model)
            state = self.Na__Tracker__Ready(model)
            state[:refs].select { |_pid, entity| entity.valid? }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Containers: { container key => [pids] } and { key => definition }
        # ------------------------------------------------------------
        def self.Na__Tracker__Structure(model)
            state = self.Na__Tracker__Ready(model)
            [state[:children], state[:defs]]
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Change Status of Every Object Ever Recorded
        # ------------------------------------------------------------
        def self.Na__Tracker__Status(model)
            state = self.Na__Tracker__StateFor(model, create: true)
            state[:history]['status']
        end
        # ---------------------------------------------------------------

        # FUNCTION | Recorded Changes, Oldest First
        # ------------------------------------------------------------
        # since_seq  only changes after this number (an agent's cursor)
        # since_time only changes at or after this time (ISO 8601)
        # by         'user', 'agent' or nil for both
        def self.Na__Tracker__Events(model, since_seq: nil, since_time: nil, by: nil, limit: 200)
            state  = self.Na__Tracker__StateFor(model, create: true)
            events = state[:history]['events']
            events = events.select { |event| event['seq'].to_i > since_seq.to_i } if since_seq
            if since_time
                cutoff = since_time.is_a?(Time) ? since_time.to_f : Time.iso8601(since_time.to_s).to_f
                events = events.select { |event| event['t'].to_f >= cutoff }
            end
            events = events.select { |event| event['by'] == by } if by
            events.last([limit.to_i, 1].max)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Last Change Number of a Model (an agent's next cursor)
        # ------------------------------------------------------------
        def self.Na__Tracker__Seq(model)
            self.Na__Tracker__StateFor(model, create: true)[:history]['seq'].to_i
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Adam and the Agents Have Seen: { 'user' => {...}, 'agent' => {...} }
        # ------------------------------------------------------------
        def self.Na__Tracker__Seen(model)
            self.Na__Tracker__StateFor(model, create: true)[:history]['seen']
        end
        # ---------------------------------------------------------------

        # FUNCTION | Mark Thread Entries (or flag keys) as Read by 'user' or 'agent'
        # ------------------------------------------------------------
        def self.Na__Tracker__MarkRead(model, who, ids)
            state = self.Na__Tracker__StateFor(model, create: true)
            seen  = state[:history]['seen'][who.to_s]
            return 0 unless seen

            fresh = Array(ids).map(&:to_s).reject { |id| id.empty? || seen.key?(id) }
            fresh.each { |id| seen[id] = true }
            self.na_schedule_save(state) unless fresh.empty?
            Na__AgentOutliner::Na__Notes.Na__Notes__Touch unless fresh.empty?          # <-- 0.1.9: what waits has changed
            fresh.length
        end
        # ---------------------------------------------------------------

        # FUNCTION | Mark Every Recorded Change as Seen by 'user' or 'agent'
        # ------------------------------------------------------------
        def self.Na__Tracker__MarkChangesSeen(model, who, upto = nil)
            state = self.Na__Tracker__StateFor(model, create: true)
            seq   = upto ? [upto.to_i, state[:history]['seq'].to_i].min : state[:history]['seq'].to_i
            state[:history]['seen']["#{who}_seq"] = seq
            self.na_schedule_save(state)
            seq
        end
        # ---------------------------------------------------------------

        # FUNCTION | Forget a Model's History (Settings: Clear History)
        # ------------------------------------------------------------
        def self.Na__Tracker__ClearHistory(model)
            state = self.Na__Tracker__StateFor(model, create: true)
            seen  = state[:history]['seen']
            state[:history] = Na__AgentOutliner::Na__HistoryStore.Na__History__Fresh(model)
            state[:history]['seen']['user']  = seen['user']                             # <-- What was read stays read
            state[:history]['seen']['agent'] = seen['agent']
            self.na_save_state(state)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | How the Tracker Is Doing (Settings and agent_outliner summary)
        # ------------------------------------------------------------
        def self.Na__Tracker__Info(model)
            state = self.Na__Tracker__StateFor(model, create: true)
            {
                'enabled'     => self.Na__Tracker__Enabled?,
                'ready'       => state[:baseline],
                'objects'     => state[:refs].length,
                'scanned'     => state[:scanned],
                'capped'      => state[:capped],
                'agent_full'  => state[:agent_full],
                'last_pass'   => state[:last_pass],
                'history_key' => state[:key],
                'history_file'=> state[:key] ? Na__AgentOutliner::Na__HistoryStore.Na__History__Path(state[:key]) : nil,
                'seq'         => state[:history]['seq'].to_i,
                'events'      => state[:history]['events'].length
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Write a Model's History Now (dialog close, reload)
        # ------------------------------------------------------------
        def self.Na__Tracker__SaveAll
            @na_states.each { |state| self.na_save_state(state) }
            true
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Passes
# -----------------------------------------------------------------------------

        # The whole structure, compared with the last pass when pending is given.
        def self.na_full_pass(state, pending, scan:, changes: nil, touched: nil)
            model     = state[:model]
            started   = self.na_clock
            structure = Na__AgentOutliner::Na__Walker.Na__Walker__Structure(model, scan: scan ? true : false)
            children  = structure['children']
            self.na_carry_unscanned(state, children, pending) unless scan

            refs = {}; fps = {}; parent_of = {}; eid_pid = {}; labels = {}; notes = {}; new_children = {}
            children.each do |key, entities|
                new_children[key] = entities.map do |entity|
                    pid = entity.persistent_id
                    refs[pid]      = entity
                    fps[pid]       = Na__AgentOutliner::Na__Walker.Na__Walker__Fingerprint(entity)
                    parent_of[pid] = key
                    eid_pid[entity.entityID] = pid
                    labels[pid]    = self.na_label(entity)
                    digest         = self.na_notes_digest(entity)
                    notes[pid]     = digest if digest
                    pid
                end
            end

            # Notes are not changes to the object, but an undone or redone comment
            # must still reach the dialog's row.
            if touched
                before = state[:notes] || {}
                (notes.keys | before.keys).each do |pid|
                    touched[pid] = true unless notes[pid] == before[pid]
                end
            end
            state[:notes] = notes

            sigs = {}
            structure['defs'].each do |key, definition|
                sigs[key] = Na__AgentOutliner::Na__Walker.Na__Walker__DefSignature(definition) unless definition.instances.empty?
            end

            if pending && changes
                default = pending[:commit_actor] || NA_USER
                fps.each do |pid, fingerprint|
                    old = state[:fps][pid]
                    if old.nil?
                        self.na_change(changes, pid, 'new', [], self.na_actor_for(pending, refs[pid], pid, default))
                    else
                        fields = self.na_counted(Na__AgentOutliner::Na__Walker.Na__Walker__ChangedFields(old, fingerprint))
                        self.na_change(changes, pid, 'updated', fields, self.na_actor_for(pending, refs[pid], pid, default)) unless fields.empty?
                        touched[pid] = true if touched && old != fingerprint
                    end
                end
                state[:fps].each_key do |pid|
                    next if fps.key?(pid)

                    self.na_change(changes, pid, 'removed', [], pending[:removed][pid] || default)
                end

                instances = self.na_def_instances(fps)
                sigs.each do |key, signature|
                    old = state[:def_sigs][key]
                    next if old.nil? || old == signature

                    actor = pending[:dirty_defs][key] || default
                    Array(instances[key]).each { |pid| self.na_change(changes, pid, 'updated', ['contents'], actor) }
                end
                pending[:dirty_defs].each do |key, actor|
                    Array(instances[key]).each { |pid| self.na_change(changes, pid, 'updated', ['contents'], actor) }
                end
                self.na_mark_containers(pending, state[:children], new_children)
            end

            state[:refs] = refs; state[:fps] = fps; state[:parent_of] = parent_of; state[:eid_pid] = eid_pid
            state[:labels].merge!(labels)
            state[:children] = new_children
            state[:defs] = structure['defs']
            state[:def_sigs] = sigs
            if scan
                state[:scanned] = true
                state[:capped]  = structure['capped']
            end
            state[:full_ms] = ((self.na_clock - started) * 1000.0).round(1)
            changes
        end

        # Only what the events named, plus the selection.
        def self.na_targeted_pass(state, pending, changes, touched)
            default = pending[:commit_actor] || NA_USER

            pending[:removed].each do |pid, actor|
                entity = state[:refs][pid]
                next if entity && entity.valid?

                self.na_change(changes, pid, 'removed', [], actor)
                self.na_forget(state, pid, pending)
            end

            pending[:added].each do |entity, actor|
                next unless entity.valid?

                pid = entity.persistent_id
                if state[:fps].key?(pid)
                    pending[:modified][entity] ||= actor
                    next
                end
                self.na_learn(state, entity, pending)
                self.na_change(changes, pid, 'new', [], actor)
                self.na_learn_subtree(state, entity, actor, changes, pending, 0)
            end

            candidates = pending[:modified].dup
            self.na_selected_rows(state[:model]).each { |entity| candidates[entity] ||= default }
            candidates.each do |entity, actor|
                next unless entity.valid?

                pid = entity.persistent_id
                old = state[:fps][pid]
                next unless old

                fingerprint = Na__AgentOutliner::Na__Walker.Na__Walker__Fingerprint(entity)
                next if fingerprint == old

                touched[pid] = true
                fields = self.na_counted(Na__AgentOutliner::Na__Walker.Na__Walker__ChangedFields(old, fingerprint))
                state[:fps][pid] = fingerprint
                state[:labels][pid] = self.na_label(entity)
                self.na_relink_definition(state, entity, pid, pending) if fields.include?('definition')
                self.na_change(changes, pid, 'updated', fields, actor) unless fields.empty?
            end

            unless pending[:dirty_defs].empty?
                instances = self.na_def_instances(state[:fps])
                pending[:dirty_defs].each do |key, actor|
                    definition = state[:defs][key]
                    state[:def_sigs][key] = Na__AgentOutliner::Na__Walker.Na__Walker__DefSignature(definition) if definition && definition.valid?
                    Array(instances[key]).each { |pid| self.na_change(changes, pid, 'updated', ['contents'], actor) }
                end
            end
            changes
        end

        # The group Adam has open: its precise signature catches vertex moves.
        def self.na_check_active_context(state, pending, changes)
            path = Array(state[:model].active_path)
            if path.empty?
                state[:active_sig] = nil
                return
            end

            definition = path.last.definition
            key   = Na__AgentOutliner::Na__Walker.Na__Walker__DefKey(definition)
            limit = Na__AgentOutliner::Na__ConfigStore.Na__Config__Engine('precise_signature_limit', 20_000).to_i
            signature = Na__AgentOutliner::Na__Walker.Na__Walker__PreciseSignature(definition, limit)
            old = state[:active_sig]
            state[:active_sig] = [key, signature]
            return unless pending[:check_active] && old && old[0] == key && old[1] != signature

            actor = pending[:commit_actor] || NA_USER
            Array(self.na_def_instances(state[:fps])[key]).each { |pid| self.na_change(changes, pid, 'updated', ['contents'], actor) }
        end

        def self.na_sign_active(state)
            self.na_check_active_context(state, self.na_new_pending, {})
        rescue StandardError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("Signing the open group failed: #{error.message}")
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Recording
# -----------------------------------------------------------------------------

        # Turns this pass's changes into history events and per-object status.
        def self.na_record(state, changes, via)
            return [] if changes.empty?

            history = state[:history]
            now     = Time.now
            stamp   = now.to_f.round(3)
            at      = now.iso8601
            records = changes.map do |pid, change|
                history['seq'] = history['seq'].to_i + 1
                label = state[:labels][pid] || ['', '']
                event = {
                    'seq'    => history['seq'],
                    't'      => stamp,
                    'at'     => at,
                    'by'     => change[:actor]['by'],
                    'tool'   => change[:actor]['tool'],
                    'pid'    => pid,
                    'kind'   => change[:kind],
                    'fields' => change[:fields].uniq,
                    'name'   => label[0],
                    'type'   => label[1]
                }
                event['via'] = via if via
                history['events'] << event
                self.na_update_status(history['status'], pid, event)
                event
            end
            self.na_schedule_save(state)
            records
        end

        def self.na_update_status(status_map, pid, event)
            status = status_map[pid.to_s] ||= {}
            case event['kind']
            when 'new'
                status['c']  = event['t']
                status['cb'] = event['by']
                status.delete('r')
            when 'updated'
                status['u']  = event['t']
                status['ub'] = event['by']
                status['f']  = event['fields']
            when 'removed'
                status['r']  = event['t']
                status['rb'] = event['by']
            end
            status['tool'] = event['tool'] if event['tool']
            status['s'] = event['seq']                                                  # <-- The last change's number: "unseen" compares it with what was seen
            status['n'] = status['n'].to_i + 1
        end

        # One change per object per pass: new beats updated, removed beats both,
        # and the fields of several updates are merged.
        def self.na_change(changes, pid, kind, fields, actor)
            existing = changes[pid]
            rank = { 'updated' => 1, 'new' => 2, 'removed' => 3 }
            if existing.nil? || rank[kind] > rank[existing[:kind]]
                changes[pid] = { kind: kind, fields: fields.dup, actor: actor || NA_USER }
            elsif kind == existing[:kind]
                existing[:fields] |= fields
                existing[:actor] = actor if actor && actor['by'] == 'agent'                 # <-- An agent's hand on it is the more useful fact
            end
        end

        def self.na_counted(fields)
            fields = fields.dup
            fields.delete('visibility') unless Na__AgentOutliner::Na__ConfigStore.Na__Config__Setting('tracking', 'count_visibility') == true
            fields.delete('lock') unless Na__AgentOutliner::Na__ConfigStore.Na__Config__Setting('tracking', 'count_lock') == true
            fields
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers - Live Map Upkeep
# -----------------------------------------------------------------------------

        def self.na_learn(state, entity, pending)
            pid = entity.persistent_id
            key = Na__AgentOutliner::Na__Walker.Na__Walker__ContainerKey(entity.parent)
            state[:refs][pid]      = entity
            state[:fps][pid]       = Na__AgentOutliner::Na__Walker.Na__Walker__Fingerprint(entity)
            state[:parent_of][pid] = key
            state[:eid_pid][entity.entityID] = pid
            state[:labels][pid]    = self.na_label(entity)
            list = (state[:children][key] ||= [])
            list << pid unless list.include?(pid)
            pending[:containers][key] = true
            if entity.respond_to?(:definition) && !entity.is_a?(Sketchup::Image)
                definition = entity.definition
                def_key = Na__AgentOutliner::Na__Walker.Na__Walker__DefKey(definition)
                state[:defs][def_key] ||= definition
                state[:def_sigs][def_key] ||= Na__AgentOutliner::Na__Walker.Na__Walker__DefSignature(definition)
                pending[:containers][def_key] = true
            end
        end

        # A new object's own contents are new too, unless its definition was
        # already known (another copy of an existing component).
        def self.na_learn_subtree(state, entity, actor, changes, pending, depth)
            return if depth > NA_SUBTREE_DEPTH
            return unless entity.respond_to?(:definition) && !entity.is_a?(Sketchup::Image)

            definition = entity.definition
            key = Na__AgentOutliner::Na__Walker.Na__Walker__DefKey(definition)
            return if state[:children].key?(key) && !state[:children][key].empty?

            definition.entities.each do |child|
                next unless Na__AgentOutliner::Na__Walker.Na__Walker__Kind(child)

                pid = child.persistent_id
                next if state[:fps].key?(pid)

                self.na_learn(state, child, pending)
                self.na_change(changes, pid, 'new', [], actor)
                self.na_learn_subtree(state, child, actor, changes, pending, depth + 1)
            end
        end

        def self.na_forget(state, pid, pending)
            key = state[:parent_of].delete(pid)
            if key && state[:children][key]
                state[:children][key].delete(pid)
                pending[:containers][key] = true
            end
            state[:fps].delete(pid)
            state[:refs].delete(pid)
            state[:eid_pid].delete_if { |_eid, value| value == pid }
        end

        # Make Unique or Swap: the object now shows another definition's children.
        def self.na_relink_definition(state, entity, pid, pending)
            definition = entity.definition
            key = Na__AgentOutliner::Na__Walker.Na__Walker__DefKey(definition)
            state[:defs][key] ||= definition
            state[:def_sigs][key] ||= Na__AgentOutliner::Na__Walker.Na__Walker__DefSignature(definition)
            unless state[:children].key?(key)
                state[:children][key] = []
                definition.entities.each do |child|
                    next unless Na__AgentOutliner::Na__Walker.Na__Walker__Kind(child)

                    self.na_learn(state, child, pending)
                end
            end
            pending[:containers][key] = true
            pending[:relinked][pid] = true
        end

        # Images and section planes are scanned only on a full scan; between
        # scans they are carried over, plus any the events added.
        def self.na_carry_unscanned(state, children, pending)
            state[:children].each do |key, pids|
                pids.each do |pid|
                    entity = state[:refs][pid]
                    next unless entity && entity.valid?
                    next unless entity.is_a?(Sketchup::Image) || entity.is_a?(Sketchup::SectionPlane)

                    children[key] << entity unless children[key].include?(entity)
                end
            end
            return unless pending

            pending[:added].each_key do |entity|
                next unless entity.valid? && (entity.is_a?(Sketchup::Image) || entity.is_a?(Sketchup::SectionPlane))

                key = Na__AgentOutliner::Na__Walker.Na__Walker__ContainerKey(entity.parent)
                children[key] << entity unless children[key].include?(entity)
            end
        end

        def self.na_mark_containers(pending, before, after)
            (before.keys | after.keys).each do |key|
                pending[:containers][key] = true unless before[key] == after[key]
            end
        end

        # Which objects show each definition's contents: { def key => [pids] }.
        def self.na_def_instances(fps)
            index = Hash.new { |hash, key| hash[key] = [] }
            fps.each do |pid, fingerprint|
                key = fingerprint[6].to_s
                index[key] << pid unless key.empty?
            end
            index
        end

        def self.na_actor_for(pending, entity, pid, default)
            return default unless pending

            pending[:added][entity] || pending[:modified][entity] || pending[:removed][pid] || default
        end

        def self.na_selected_rows(model)
            selection = model.selection
            return [] if selection.length.zero? || selection.length > 500

            selection.to_a.select { |entity| Na__AgentOutliner::Na__Walker.Na__Walker__Kind(entity) }
        end

        def self.na_label(entity)
            kind = Na__AgentOutliner::Na__Walker.Na__Walker__Kind(entity)
            [Na__AgentOutliner::Na__Walker.Na__Walker__DisplayName(entity), Na__AgentOutliner::Na__Walker::NA_TYPE_NAMES[kind].to_s]
        end

        # A model where a full pass costs more than the budget gets targeted
        # passes for agent operations too; a later cheap full pass turns it back.
        def self.na_tune_agent_mode(state, pending, elapsed)
            return unless pending[:full]

            budget = Na__AgentOutliner::Na__ConfigStore.Na__Config__Engine('full_pass_budget_ms', 250).to_f
            state[:agent_full] = (state[:full_ms] || elapsed).to_f <= budget
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers - Timers, Models, Saving
# -----------------------------------------------------------------------------

        def self.na_new_pending
            {
                added:        {},
                modified:     {},
                removed:      {},
                dirty_defs:   {},
                containers:   {},
                relinked:     {},
                commit_actor: nil,
                full:         false,
                scan:         false,
                via:          nil,
                check_active: false,
                sign_active:  false
            }
        end

        # ONE timer per model, however many events arrive before it fires.
        def self.na_schedule(state, delay = nil)
            return if state[:timer]

            delay ||= Na__AgentOutliner::Na__ConfigStore.Na__Config__Engine('reconcile_delay_s', 0.25).to_f
            model = state[:model]
            state[:timer] = UI.start_timer(delay, false) do
                Na__AgentOutliner::Na__Tracker.Na__Tracker__Reconcile(model)
            end
        end

        def self.na_schedule_save(state)
            return if state[:save_timer]

            delay = Na__AgentOutliner::Na__ConfigStore.Na__Config__Engine('save_delay_s', 2.0).to_f
            model = state[:model]
            state[:save_timer] = UI.start_timer(delay, false) do
                live = Na__AgentOutliner::Na__Tracker.Na__Tracker__StateFor(model)
                if live
                    live[:save_timer] = nil
                    Na__AgentOutliner::Na__Tracker.na_save_state(live)
                end
            end
        end

        def self.na_save_state(state)
            if state[:save_timer]
                UI.stop_timer(state[:save_timer])
                state[:save_timer] = nil
            end
            return false unless state[:key]

            Na__AgentOutliner::Na__HistoryStore.Na__History__Write(state[:model], state[:key], state[:history])
        rescue StandardError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Error('Writing the change history failed.', error)
            false
        end

        # The reconcile timer only: na_save_state stops the save timer itself.
        def self.na_stop_timers(state)
            return unless state[:timer]

            UI.stop_timer(state[:timer])
            state[:timer] = nil
        end

        # A cheap digest of an object's notes, read without parsing the thread:
        # enough to notice that undo or redo changed them. nil when it has none.
        def self.na_notes_digest(entity)
            dictionary = entity.attribute_dictionary(Na__AgentOutliner::NA_DICT_NOTES)
            return nil unless dictionary

            "#{dictionary['flag']}|#{dictionary['flag_at']}|#{dictionary['thread'].to_s.length}|#{dictionary['thread_chunks']}"
        end

        def self.na_state_for_entities(entities)
            model = entities.model
            self.Na__Tracker__StateFor(model)
        rescue StandardError
            nil
        end

        def self.na_container_key(entities)
            Na__AgentOutliner::Na__Walker.Na__Walker__ContainerKey(entities.parent)
        end

        def self.na_model_alive?(model)
            model.valid?
        rescue StandardError
            false
        end

        # Models have more than one Ruby wrapper at times: compare by identity,
        # then by equality, then by the guid both report at this moment.
        def self.na_same_model?(left, right)
            return true if left.equal?(right) || left == right

            left.respond_to?(:guid) && right.respond_to?(:guid) && left.guid == right.guid && left.path == right.path
        rescue StandardError
            false
        end

        def self.na_clock
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

# endregion -------------------------------------------------------------------

    end # module Na__Tracker
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
