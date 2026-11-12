# =============================================================================
# NA AGENT OUTLINER - CHANGE TRACKING - HISTORY STORE
# =============================================================================
#
# FILE       : Na__AgentOutliner__ChangeTracking__HistoryStore__.rb
# NAMESPACE  : Na__AgentOutliner::Na__HistoryStore
# MODULE     : Na__HistoryStore (module functions)
# AUTHOR     : Noble Architecture
# PURPOSE    : Keep each model's change history and "what has been seen"
#              beside the model, on this PC, in one small JSON file per model
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - WHY NOT IN THE MODEL: every attribute write is an undoable change that
#   marks the model modified. Tracking writes after every operation would put
#   a phantom step behind each of Adam's own, and would ask him to save a
#   model he only looked at. So history lives in
#   91__UserConfig__LocalOnly/ModelHistory (git-ignored, this PC only).
# - THE KEY is the model's file path (a short readable stem plus a CRC32 of
#   the full lower-case path). Model#guid cannot be used: it changes on every
#   save. An untitled model is tracked in memory and written the first time
#   it is saved; Save As carries the history to the new file name, so an
#   incremental save (0.1.16 -> 0.1.17) keeps the day's history.
# - THE FILE NAME IS SHORT ON PURPOSE (0.1.1): the ModelHistory folder is
#   already about 195 characters deep, and SketchUp's Ruby cannot open a path
#   of 260 or more on Windows (Errno::ENOENT). 0.1.0's names
#   (Na__AgentOutliner__History__<48 character stem>__<crc>__.json) reached
#   274 to 292 characters, so no history was ever saved. Now
#   History__<20 character stem>__<crc>.json: about 243 with ".tmp".
# - THE FILE:
#     events  newest last, capped (tracking.max_events)
#     status  per persistent id: created / updated / removed, when and by whom
#     seen    entry ids Adam has read, ids agents have acknowledged, and the
#             change numbers each has seen up to
#   Old entries are pruned after tracking.keep_days.
#
# =============================================================================

module Na__AgentOutliner
    module Na__HistoryStore

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_FOLDER        = 'ModelHistory'.freeze unless defined?(NA_FOLDER)
        NA_STEM_CHARS    = 20 unless defined?(NA_STEM_CHARS)                            # <-- Keeps the whole path under Windows' 260 characters (see above)
        NA_SEEN_LIMIT    = 5000 unless defined?(NA_SEEN_LIMIT)
        NA_SCHEMA        = 1 unless defined?(NA_SCHEMA)
        NA_WATCH_FRESH_S = 30 unless defined?(NA_WATCH_FRESH_S)                          # <-- A watcher's heartbeat older than this is a dead watcher (0.1.10)
        NA_DISPATCH_FRESH_S = 180 unless defined?(NA_DISPATCH_FRESH_S)                   # <-- A dispatcher stops beating while it works a request; give it three minutes (0.1.14)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Keys and Paths
# -----------------------------------------------------------------------------

        # FUNCTION | The History Key of a Model (nil until it has a file)
        # ------------------------------------------------------------
        def self.Na__History__KeyFor(model)
            path = model.path.to_s
            return nil if path.empty?

            stem = File.basename(path, '.*').gsub(/[^A-Za-z0-9_\-]+/, '_')[0, NA_STEM_CHARS]
            crc  = format('%08x', Zlib.crc32(path.tr('\\', '/').downcase))
            "#{stem}__#{crc}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Folder Every History File Lives In
        # ------------------------------------------------------------
        def self.Na__History__Folder
            File.join(Na__AgentOutliner::NA_LOCAL_ROOT, NA_FOLDER)
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Model's History File
        # ------------------------------------------------------------
        def self.Na__History__Path(key)
            File.join(self.Na__History__Folder, "History__#{self.na_file_key(key)}.json")
        end

        # FUNCTION | One Model's Inbox Signal (0.1.9), Beside Its History
        # ------------------------------------------------------------
        def self.Na__History__InboxPath(key)
            File.join(self.Na__History__Folder, "Inbox__#{self.na_file_key(key)}.json")
        end

        # A key made by 0.1.0 (a 48 character stem), still held by a window
        # that reloaded rather than restarted, is cut to the same short form.
        def self.na_file_key(key)
            text  = key.to_s
            match = text.match(/\A(.*)__([0-9a-f]{8})\z/)
            return text[0, NA_STEM_CHARS + 10] unless match

            "#{match[1][0, NA_STEM_CHARS]}__#{match[2]}"
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Load and Save
# -----------------------------------------------------------------------------

        # FUNCTION | A New, Empty History
        # ------------------------------------------------------------
        def self.Na__History__Fresh(model)
            {
                'schema' => NA_SCHEMA,
                'model'  => { 'title' => model.title.to_s, 'path' => model.path.to_s },
                'seq'    => 0,
                'events' => [],
                'status' => {},
                'seen'   => { 'user' => {}, 'agent' => {}, 'user_seq' => 0, 'agent_seq' => 0 }
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Model's History From Disk (a fresh one when none or unreadable)
        # ------------------------------------------------------------
        def self.Na__History__Load(model, key)
            fresh = self.Na__History__Fresh(model)
            return fresh unless key

            path = self.Na__History__Path(key)
            return fresh unless File.exist?(path)

            data = JSON.parse(File.read(path, mode: 'rb').force_encoding('UTF-8'))
            return fresh unless data.is_a?(Hash) && data['schema'].to_i == NA_SCHEMA

            self.na_normalise(data, fresh)
        rescue JSON::ParserError, EncodingError, SystemCallError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("History for #{key} could not be read (#{error.message}); starting a fresh one.")
            fresh
        end
        # ---------------------------------------------------------------

        # FUNCTION | Write a Model's History (pruned first)
        # ------------------------------------------------------------
        def self.Na__History__Write(model, key, data)
            return false unless key

            self.Na__History__Prune!(data)
            data['model']    = { 'title' => model.title.to_s, 'path' => model.path.to_s }
            data['saved_at'] = Na__AgentOutliner.Na__Time__Now
            path = self.Na__History__Path(key)
            FileUtils.mkdir_p(File.dirname(path))
            temp = "#{path}.tmp"
            File.open(temp, 'wb') { |file| file.write(JSON.generate(data)) }
            File.delete(path) if File.exist?(path)
            File.rename(temp, path)
            true
        rescue SystemCallError, IOError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Error("Saving the history for #{key} failed.", error)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Tell an Idle Agent's Watcher That Adam Has Sent (0.1.9)
        # ------------------------------------------------------------
        # The MCP cannot wake a Claude session that is not calling it. A
        # session can run the 3D skill's scripts/outliner_watch.py in the
        # background, which polls these small files and ends (waking the
        # session) when one is rewritten. Written each time Adam sends a
        # comment or an inbox flag: the model, when he sent, and the waiting
        # notice an agent's next MCP call carries. Nothing for an unsaved
        # model (no key).
        def self.Na__History__WriteInbox(model, notice)
            key = self.Na__History__KeyFor(model)
            return false unless key

            data = {
                'schema'  => NA_SCHEMA,
                'model'   => { 'title' => model.title.to_s, 'path' => model.path.to_s },
                'sent_at' => Na__AgentOutliner.Na__Time__Now,
                'notice'  => notice
            }
            path = self.Na__History__InboxPath(key)
            FileUtils.mkdir_p(File.dirname(path))
            temp = "#{path}.tmp"
            File.open(temp, 'wb') { |file| file.write(JSON.generate(data)) }
            File.delete(path) if File.exist?(path)
            File.rename(temp, path)
            true
        rescue SystemCallError, IOError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("The inbox signal for #{key} could not be written (#{error.message}).")
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Idle Agents Watching a Model (0.1.10)
        # ------------------------------------------------------------
        # scripts/outliner_watch.py (3D skill) keeps Watch__<pid>.json here,
        # its heartbeat ('beat', Unix seconds) renewed every few seconds, and
        # deletes it when it ends. A file not renewed for NA_WATCH_FRESH_S is a
        # watcher that was killed. Its 'model' (text in the model's title or
        # path; empty for any model) says which models it wakes for. Returns
        # [{ 'who', 'pid' }], newest first.
        def self.Na__History__Watchers(model, now = Time.now.to_f)
            folder = self.Na__History__Folder
            return [] unless File.directory?(folder)

            text = "#{model.title} #{model.path}".downcase
            found = Dir.children(folder).grep(/\AWatch__\d+\.json\z/).filter_map do |name|
                data = JSON.parse(File.read(File.join(folder, name), mode: 'rb').force_encoding('UTF-8'))
                next unless data.is_a?(Hash) && now - data['beat'].to_f <= NA_WATCH_FRESH_S

                wanted = data['model'].to_s.strip.downcase
                next unless wanted.empty? || text.include?(wanted)

                { 'who' => data['who'].to_s, 'pid' => data['pid'], 'beat' => data['beat'].to_f }
            rescue JSON::ParserError, EncodingError, SystemCallError
                nil                                                                     # <-- Being rewritten: counted next time
            end
            found.sort_by { |item| -item['beat'] }.map { |item| item.reject { |key, _| key == 'beat' } }
        rescue SystemCallError
            []
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Effort Dispatchers Running on This PC (0.1.14)
        # ------------------------------------------------------------
        # A Claude session can't change its own reasoning effort (the Claude
        # app refuses it). A dispatcher session runs the 3D skill's
        # outliner_watch.py --dispatch, which keeps Dispatch__<pid>.json here,
        # and sets each waking agent's effort to the one Adam picked. Its
        # heartbeat may pause while it works, so NA_DISPATCH_FRESH_S is longer
        # than a watcher's. Returns [{ 'who', 'pid' }].
        def self.Na__History__Dispatchers(now = Time.now.to_f)
            folder = self.Na__History__Folder
            return [] unless File.directory?(folder)

            Dir.children(folder).grep(/\ADispatch__\d+\.json\z/).filter_map do |name|
                data = JSON.parse(File.read(File.join(folder, name), mode: 'rb').force_encoding('UTF-8'))
                next unless data.is_a?(Hash) && now - data['beat'].to_f <= NA_DISPATCH_FRESH_S

                { 'who' => data['who'].to_s, 'pid' => data['pid'] }
            rescue JSON::ParserError, EncodingError, SystemCallError
                nil
            end
        rescue SystemCallError
            []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Drop Old Events, Old Statuses and Old Seen Ids
        # ------------------------------------------------------------
        def self.Na__History__Prune!(data)
            max_events = Na__AgentOutliner::Na__ConfigStore.Na__Config__Setting('tracking', 'max_events').to_i
            max_events = 4000 if max_events <= 0
            keep_days  = Na__AgentOutliner::Na__ConfigStore.Na__Config__Setting('tracking', 'keep_days').to_f
            keep_days  = 30.0 if keep_days <= 0
            cutoff     = Time.now.to_f - keep_days * 86_400.0

            events = data['events']
            events.shift(events.length - max_events) if events.length > max_events
            events.reject! { |event| event['t'].to_f < cutoff }

            data['status'].delete_if do |_pid, status|
                [status['c'], status['u'], status['r']].compact.map(&:to_f).max.to_f < cutoff
            end

            %w[user agent].each do |who|
                seen = data['seen'][who]
                next unless seen.length > NA_SEEN_LIMIT

                seen.keys.first(seen.length - NA_SEEN_LIMIT).each { |id| seen.delete(id) }
            end
            data
        end
        # ---------------------------------------------------------------

        # FUNCTION | Forget One Model's History (Settings: Clear History)
        # ------------------------------------------------------------
        def self.Na__History__Delete(key)
            return false unless key

            path = self.Na__History__Path(key)
            File.delete(path) if File.exist?(path)
            true
        rescue SystemCallError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Error("Deleting the history for #{key} failed.", error)
            false
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # Fills in anything an older or hand-edited file lacks, with the right
        # types, so the tracker never meets a nil.
        def self.na_normalise(data, fresh)
            data['seq']    = data['seq'].to_i
            data['events'] = Array(data['events']).select { |event| event.is_a?(Hash) }
            data['status'] = data['status'].is_a?(Hash) ? data['status'] : {}
            seen = data['seen'].is_a?(Hash) ? data['seen'] : {}
            data['seen'] = {
                'user'      => seen['user'].is_a?(Hash) ? seen['user'] : {},
                'agent'     => seen['agent'].is_a?(Hash) ? seen['agent'] : {},
                'user_seq'  => seen['user_seq'].to_i,
                'agent_seq' => seen['agent_seq'].to_i
            }
            data['model'] ||= fresh['model']
            data
        end

# endregion -------------------------------------------------------------------

    end # module Na__HistoryStore
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
