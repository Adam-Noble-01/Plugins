# =============================================================================
# NA AGENT OUTLINER - MCP OPERATIONS - MAIN (THE SEAM AGENTS CALL)
# =============================================================================
#
# FILE       : Na__AgentOutliner__McpOperations__Main__.rb
# NAMESPACE  : Na__AgentOutliner::Na__McpOperations
# MODULE     : Na__McpOperations (module functions) and Na__McpOperationsError
# AUTHOR     : Noble Architecture
# PURPOSE    : What the Na SketchUp MCP tools agent_outliner (read) and
#              agent_outliner_edit (write) run. The MCP's handler stays thin:
#              it checks the action and forwards here, exactly as the
#              Component Editor Tools, Point Cloud Viewer and GLB Builder
#              seams work
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - READ (agent_outliner):
#     summary   start here: counts, what waits, what changed, tracker health
#     inbox     every object (and the model thread) waiting for an agent:
#               Adam's flags and unread comments, each with the object's path,
#               size, tag, naming prefix meaning and whole thread
#     changes   what changed since the agent last acknowledged (or since_seq /
#               since), by object or as events; by: user shows Adam's own
#               edits, the silent corrections an agent should learn from
#     thread    whole threads (ids, or model: true)
#     threads   every thread in the model on one line each: open or
#               resolved, who it waits on (agent or user), the last word
#               (0.1.1)
#     flags     every flagged object by flag type, Do Not Touch and
#               Reference included, with who set each flag (0.1.1)
#     prefixes  the naming standards with their meanings, and which objects
#               carry each (CAD__FrontElevation -> its id and path)
#     find      the dialog's search language
#     tags      every tag: colour, shown, folder, how many objects (0.1.5)
# - EDIT (agent_outliner_edit), each model change ONE undo step named
#   "MCP: Agent Outliner Edit":
#     comment, reply   write in a thread (reply also acknowledges what it
#                      answers); model: true writes in the model's thread;
#                      images: picture files on this PC to attach (0.1.6)
#     resolve, reopen  close or open a thread, with an optional note
#     flag, unflag     set or clear a flag (as the agent)
#     acknowledge      mark Adam's comments and flags as read, and/or the
#                      changes as seen (changes: true); this PC only, never a
#                      model change
#     name             give objects a standard name (Quick Name)
#     strip            take the standard prefix off again (the Strip
#                      button; 0.1.1)
#     tag              put objects on a tag; create: true makes a missing
#                      one in the same undo step (0.1.5)
# - NOTICE (0.1.9, Na__AgentOutliner__McpNotice): what waits for an agent in
#   a few words, which the MCP (1.0.28) puts on EVERY tool result while
#   anything waits, so an agent busy modelling hears Adam on its next call.
#   Cached per model against the notes revision: no scan per call.
# - REFUSALS raise Na__McpOperationsError(code, message, hint, details); the
#   MCP turns them into its own error with the same code and hint.
# - The dialog, when open, is refreshed after every edit.
#
# =============================================================================

module Na__AgentOutliner

# -----------------------------------------------------------------------------
# REGION | The Seam's Refusal
# -----------------------------------------------------------------------------

    # CLASS | A Refusal the MCP Shows the Agent As It Is
    # ------------------------------------------------------------
    class Na__McpOperationsError < StandardError
        attr_reader :na_code, :na_hint, :na_details

        def initialize(code, message, hint = nil, details = nil)
            super(message)
            @na_code    = code.to_s
            @na_hint    = hint
            @na_details = details
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        # The action lists are REPLACED on every load, never guarded: Reload
        # Plugin Data re-runs this file, and a guarded list would keep the old
        # actions until SketchUp restarts (the MCP compares its lists to these).
        remove_const(:NA_READ_ACTIONS) if const_defined?(:NA_READ_ACTIONS, false)
        remove_const(:NA_EDIT_ACTIONS) if const_defined?(:NA_EDIT_ACTIONS, false)
        NA_READ_ACTIONS = %w[summary inbox changes thread threads flags prefixes find tags].freeze
        NA_EDIT_ACTIONS = %w[comment reply resolve reopen flag unflag acknowledge name strip tag].freeze
        NA_OPERATION    = 'MCP: Agent Outliner Edit'.freeze unless defined?(NA_OPERATION)
        NA_MAX_IDS      = 500 unless defined?(NA_MAX_IDS)
        NA_NOTICE_TEXT  = 120 unless defined?(NA_NOTICE_TEXT)                           # <-- The notice quotes this much of the latest message
        NA_NOTICE_READ  = 'agent_outliner {action: "inbox"}'.freeze unless defined?(NA_NOTICE_READ)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Entry Points
# -----------------------------------------------------------------------------

        # FUNCTION | The Actions Each Tool Accepts (the MCP checks its lists match)
        # ------------------------------------------------------------
        def self.Na__AgentOutliner__McpActions
            { 'read' => NA_READ_ACTIONS.dup, 'edit' => NA_EDIT_ACTIONS.dup }
        end
        # ---------------------------------------------------------------

        # FUNCTION | agent_outliner (read only)
        # ------------------------------------------------------------
        def self.Na__AgentOutliner__McpRead(action, params)
            params = self.na_params(params)
            model  = self.na_model(params)
            Na__AgentOutliner::Na__Tracker.Na__Tracker__Flush(model)

            case action.to_s
            when 'summary'
                Na__AgentOutliner::Na__Payloads.Na__Payload__Summary(model)
            when 'inbox'
                Na__AgentOutliner::Na__Payloads.Na__Payload__Inbox(model, include_seen: params['include_seen'] == true, limit: self.na_limit(params, 50, 200))
            when 'changes'
                self.na_read_changes(model, params)
            when 'thread'
                self.na_read_threads(model, params)
            when 'threads'
                self.na_read_thread_list(model, params)
            when 'flags'
                self.na_read_flags(model, params)
            when 'prefixes'
                Na__AgentOutliner::Na__Payloads.Na__Payload__Prefixes(model)
            when 'find'
                query = params['query'].to_s
                raise Na__McpOperationsError.new('invalid_params', 'find needs a query.', 'Pass query, e.g. "tag:06__Drawings is:new" or "flag:for_agent".') if query.strip.empty?

                Na__AgentOutliner::Na__Payloads.Na__Payload__Find(model, query, limit: self.na_limit(params, 50, 500))
            when 'tags'
                Na__AgentOutliner::Na__Payloads.Na__Payload__TagList(model)
            else
                raise Na__McpOperationsError.new('invalid_params', "Unknown agent_outliner action '#{action}'.", "Use one of: #{NA_READ_ACTIONS.join(', ')}.")
            end
        rescue ArgumentError => error
            raise Na__McpOperationsError.new('invalid_params', error.message, 'Check the arguments named in the message.')
        end
        # ---------------------------------------------------------------

        # FUNCTION | agent_outliner_edit (changes notes, names, or what is seen)
        # ------------------------------------------------------------
        def self.Na__AgentOutliner__McpEdit(action, params)
            params = self.na_params(params)
            model  = self.na_model(params)
            Na__AgentOutliner::Na__Tracker.Na__Tracker__Flush(model)
            author = params['author'].to_s.strip.empty? ? 'Agent' : params['author'].to_s.strip[0, 80]

            result = case action.to_s
                     when 'comment', 'reply'
                         self.na_edit_comment(model, params, author, action.to_s == 'reply')
                     when 'resolve', 'reopen'
                         targets = self.na_targets(model, params, allow_model: true)
                         status  = action.to_s == 'resolve' ? 'resolved' : 'open'
                         entries = Na__AgentOutliner::Na__Notes.Na__Notes__SetStatus(model, targets, status, by: 'agent', author: author,
                                                                                    operation_name: NA_OPERATION, text: params['text'])
                         self.na_after_notes(model, targets)
                         { 'done' => action.to_s, 'entries' => entries, 'undo' => NA_OPERATION }
                     when 'flag'
                         self.na_edit_flag(model, params, author)
                     when 'unflag'
                         targets = self.na_targets(model, params, allow_model: false)
                         entries = Na__AgentOutliner::Na__Notes.Na__Notes__ClearFlag(model, targets, by: 'agent', author: author, operation_name: NA_OPERATION)
                         self.na_after_notes(model, targets)
                         { 'done' => 'unflag', 'cleared' => entries.length, 'undo' => entries.empty? ? nil : NA_OPERATION }
                     when 'acknowledge'
                         self.na_edit_acknowledge(model, params)
                     when 'name'
                         self.na_edit_name(model, params)
                     when 'strip'
                         self.na_edit_strip(model, params)
                     when 'tag'
                         self.na_edit_tag(model, params)
                     else
                         raise Na__McpOperationsError.new('invalid_params', "Unknown agent_outliner_edit action '#{action}'.", "Use one of: #{NA_EDIT_ACTIONS.join(', ')}.")
                     end
            result.delete('undo') if result.is_a?(Hash) && result['undo'].nil?
            result
        rescue ArgumentError => error
            raise Na__McpOperationsError.new('invalid_params', error.message, 'Nothing was changed. Fix what the message names and call again.')
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Waiting Notice (0.1.9: on every MCP result while Adam waits)
# -----------------------------------------------------------------------------

        # FUNCTION | What Waits for an Agent, in a Few Words (nil when nothing waits)
        # ------------------------------------------------------------
        # The MCP calls this after EVERY tool, so it must be cheap. The count
        # is worked out again (a pass over the objects that carry notes) only
        # when one of these moves:
        #   - the notes revision: any thread or flag written, by Adam or an
        #     agent; an agent's acknowledge; undo, redo or an aborted step;
        #     the standards saved (Na__Notes__Revision);
        #   - the tracker's notes digests (its full pass after an agent's
        #     commit or an undo: a note written by other means);
        #   - the history itself (Clear History);
        #   - an object it counted is gone.
        # Otherwise the last answer is reused and only 'ago' is worked out.
        def self.Na__AgentOutliner__McpNotice(model)
            return nil unless model && model.valid?

            state = Na__AgentOutliner::Na__Tracker.Na__Tracker__Ready(model)
            key   = [Na__AgentOutliner::Na__Notes.Na__Notes__Revision, state[:notes].hash, state[:history].object_id]
            cache = state[:notice]
            unless cache && cache[:key] == key && cache[:targets].all?(&:valid?)
                cache = self.na_build_notice(model, state)
                cache[:key] = key
                state[:notice] = cache
            end
            return nil unless cache[:notice]

            notice = cache[:notice].dup
            ago = self.na_ago(notice['at'])
            ago ? notice['ago'] = ago : notice.delete('ago')
            notice
        rescue StandardError => error
            text = "#{error.class}: #{error.message}"
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("The MCP waiting notice could not be worked out (#{text}).") unless text == @na_notice_error
            @na_notice_error = text                                                     # <-- Logged once, not on every call
            nil
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reads
# -----------------------------------------------------------------------------

        def self.na_read_changes(model, params)
            by = params['by'].to_s
            by = 'user' if %w[adam me].include?(by)
            unless by.empty? || %w[user agent].include?(by)
                raise Na__McpOperationsError.new('invalid_params', "by is 'user' (Adam) or 'agent', not '#{params['by']}'.", 'Leave by out for both.')
            end

            since_time = params['since'].to_s.strip
            unless since_time.empty?
                begin
                    Time.iso8601(since_time)
                rescue ArgumentError
                    raise Na__McpOperationsError.new('invalid_params', "since must be an ISO 8601 time such as 2026-11-10T14:05:00+00:00, not '#{since_time}'.",
                                                     'Or pass since_seq, the cursor a previous changes call returned.')
                end
            end
            group = params['group'].to_s
            group = 'object' unless group == 'event'
            Na__AgentOutliner::Na__Payloads.Na__Payload__Changes(
                model,
                since_seq:  params.key?('since_seq') ? params['since_seq'].to_i : nil,
                since_time: since_time.empty? ? nil : since_time,
                by:         by.empty? ? nil : by,
                limit:      self.na_limit(params, 200, 2000),
                group:      group
            )
        end

        def self.na_read_threads(model, params)
            threads = []
            threads << Na__AgentOutliner::Na__Payloads.Na__Payload__Thread(model, model) if params['model'] == true
            if params.key?('ids')
                self.na_targets(model, params, allow_model: false).each do |entity|
                    item = Na__AgentOutliner::Na__Payloads.Na__Payload__Object(model, entity)
                    item['thread'] ||= { 'status' => '', 'entries' => [] }
                    threads << item
                end
            end
            if threads.empty?
                raise Na__McpOperationsError.new('invalid_params', 'Say whose thread to read.', 'Pass ids (persistent ids) and/or model: true.')
            end

            { 'threads' => threads }
        end

        # Every thread on one line each; status and waiting_on narrow it.
        def self.na_read_thread_list(model, params)
            status = params['status'].to_s
            unless status.empty? || %w[open resolved].include?(status)
                raise Na__McpOperationsError.new('invalid_params', "status is 'open' or 'resolved', not '#{params['status']}'.", 'Leave status out for both.')
            end

            waiting_on = params['waiting_on'].to_s
            waiting_on = 'user' if %w[adam me].include?(waiting_on)
            unless waiting_on.empty? || %w[agent user].include?(waiting_on)
                raise Na__McpOperationsError.new('invalid_params', "waiting_on is 'agent' or 'user' (Adam), not '#{params['waiting_on']}'.", 'Leave waiting_on out for every thread.')
            end

            Na__AgentOutliner::Na__Payloads.Na__Payload__Threads(model, status: status.empty? ? nil : status,
                                                                       waiting_on: waiting_on.empty? ? nil : waiting_on,
                                                                       limit: self.na_limit(params, 50, 500))
        end

        # Every flagged object by flag type; flag (an id or label) and by narrow it.
        def self.na_read_flags(model, params)
            flag_id = nil
            wanted  = params['flag'].to_s.strip
            unless wanted.empty? || wanted.casecmp('any').zero?
                types = Na__AgentOutliner::Na__ConfigStore.Na__Standards__Flags
                type  = types.find { |flag| flag['id'] == wanted } || types.find { |flag| flag['label'].to_s.casecmp(wanted).zero? }
                unless type
                    raise Na__McpOperationsError.new('invalid_params', "There is no flag type '#{wanted}'.",
                                                     "Use one of: #{types.map { |flag| flag['id'] }.join(', ')}, or leave flag out for every flag.")
                end

                flag_id = type['id']
            end

            by = params['by'].to_s
            by = 'user' if %w[adam me].include?(by)
            unless by.empty? || %w[user agent].include?(by)
                raise Na__McpOperationsError.new('invalid_params', "by is 'user' (Adam) or 'agent', not '#{params['by']}'.", 'Leave by out for both.')
            end

            Na__AgentOutliner::Na__Payloads.Na__Payload__Flags(model, flag_id: flag_id, by: by.empty? ? nil : by, limit: self.na_limit(params, 100, 500))
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edits
# -----------------------------------------------------------------------------

        def self.na_edit_comment(model, params, author, reply)
            targets = self.na_targets(model, params, allow_model: true)
            text    = params['text']
            images  = self.na_import_images(params['images'])
            raise Na__McpOperationsError.new('invalid_params', 'Write the comment in text.', 'text is the message Adam will read.') if text.to_s.strip.empty? && images.empty?
            if reply
                silent = targets.select { |target| Na__AgentOutliner::Na__Notes.Na__Notes__Read(target)['thread']['entries'].empty? }
                unless silent.empty?
                    raise Na__McpOperationsError.new('invalid_params', 'reply answers an existing thread, and one of these has none.',
                                                     'Use action "comment" to start a thread.', { 'without_thread' => silent.map { |t| self.na_target_id(t) } })
                end
            end

            entries = Na__AgentOutliner::Na__Notes.Na__Notes__Comment(model, targets, text, by: 'agent', author: author, operation_name: NA_OPERATION, images: images)
            acknowledged = reply ? self.na_acknowledge_targets(model, targets) : 0
            self.na_after_notes(model, targets)
            {
                'done'         => reply ? 'reply' : 'comment',
                'entries'      => entries.each_with_index.map { |entry, index| entry.merge('target' => self.na_target_id(targets[index])) },
                'acknowledged' => acknowledged,
                'undo'         => NA_OPERATION
            }
        end

        def self.na_edit_flag(model, params, author)
            targets = self.na_targets(model, params, allow_model: false)
            flag_id = params['flag'].to_s
            unless Na__AgentOutliner::Na__ConfigStore.Na__Standards__Flag(flag_id)
                ids = Na__AgentOutliner::Na__ConfigStore.Na__Standards__Flags.map { |flag| flag['id'] }
                raise Na__McpOperationsError.new('invalid_params', "There is no flag type '#{flag_id}'.", "Use one of: #{ids.join(', ')} (agent_outliner prefixes lists their meanings).")
            end

            entries = Na__AgentOutliner::Na__Notes.Na__Notes__SetFlag(model, targets, flag_id, by: 'agent', author: author,
                                                                     operation_name: NA_OPERATION, text: params['text'])
            self.na_after_notes(model, targets)
            { 'done' => 'flag', 'flag' => flag_id, 'flagged' => entries.length, 'undo' => NA_OPERATION }
        end

        # ids / model: those threads. Neither, and no changes: true: everything
        # waiting. changes: true also (or only) moves the changes cursor.
        def self.na_edit_acknowledge(model, params)
            targets = []
            if params.key?('ids') || params['model'] == true
                targets = self.na_targets(model, params, allow_model: true)
            elsif params['changes'] != true
                noted = Na__AgentOutliner::Na__Tracker.Na__Tracker__Refs(model).values.select { |entity| Na__AgentOutliner::Na__Notes.Na__Notes__Any?(entity) }
                targets = [model] + noted
            end
            marked = targets.empty? ? 0 : self.na_acknowledge_targets(model, targets)

            seq = nil
            seq = Na__AgentOutliner::Na__Tracker.Na__Tracker__MarkChangesSeen(model, 'agent', params['upto']) if params['changes'] == true
            self.na_after_notes(model, targets) unless targets.empty?                    # <-- The "waiting for an agent" badges clear in the dialog
            result = { 'done' => 'acknowledge', 'marked_read' => marked }
            result['changes_seen_upto'] = seq if seq
            result
        end

        def self.na_edit_name(model, params)
            targets = self.na_targets(model, params, allow_model: false)
            entry = Na__AgentOutliner::Na__ConfigStore.Na__Standards__Prefix(params['prefix'])
            unless entry
                labels = Na__AgentOutliner::Na__ConfigStore.Na__Standards__Prefixes.map { |item| item['label'] }
                raise Na__McpOperationsError.new('invalid_params', "There is no naming prefix '#{params['prefix']}'.",
                                                 "Use one of: #{labels.join(', ')}. Adam adds new ones in the Configure tab.")
            end

            result = Na__AgentOutliner::Na__Naming.Na__Naming__Apply(model, targets, entry, operation_name: NA_OPERATION)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushRows(model, targets.map(&:persistent_id))
            result.merge('done' => 'name', 'prefix' => entry['label'], 'undo' => result['renamed'].empty? ? nil : NA_OPERATION)
        end

        # The Strip button: any standard prefix taken off. An object named
        # exactly a label (CAD__FrontElevation) is left with no name, as in
        # the dialog, and the agent is told so.
        def self.na_edit_strip(model, params)
            targets = self.na_targets(model, params, allow_model: false)
            result  = Na__AgentOutliner::Na__Naming.Na__Naming__Strip(model, targets, operation_name: NA_OPERATION)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushRows(model, targets.map(&:persistent_id))
            emptied = result['renamed'].select { |item| item['to'].to_s.empty? }
            unless emptied.empty?
                result['warnings'] = ["#{emptied.length} object(s) were named exactly a standard label and now have no name " \
                                      "(#{emptied.map { |item| item['id'] }.join(', ')}): name them with entity_set_properties or undo with model_undo."]
            end
            result.merge('done' => 'strip', 'undo' => result['renamed'].empty? ? nil : NA_OPERATION)
        end

        # Pictures an agent attaches: files on this PC, copied into the chat
        # folder before anything is written (0.1.6). Checked first, so a bad
        # file refuses the whole call and writes nothing to the model.
        def self.na_import_images(list)
            paths = Array(list)
            return [] if paths.empty?
            if paths.length > Na__AgentOutliner::Na__ChatCache::NA_MAX_IMAGES
                raise Na__McpOperationsError.new('invalid_params', "At most #{Na__AgentOutliner::Na__ChatCache::NA_MAX_IMAGES} pictures on one comment; this one has #{paths.length}.", 'Split them over two comments.')
            end

            paths.map do |path|
                Na__AgentOutliner::Na__ChatCache.Na__Chat__ImportFile(path)
            rescue ArgumentError => error
                raise Na__McpOperationsError.new('invalid_params', error.message, 'images are PNG, JPEG, GIF or WebP files on this PC, 15 MB each at most (a view_capture file works).')
            end
        end

        # Objects onto a tag (0.1.5). tag '' or "Untagged" untags; a missing tag
        # is refused with the model's tags named, unless create: true.
        def self.na_edit_tag(model, params)
            unless params.key?('tag')
                raise Na__McpOperationsError.new('invalid_params', 'tag needs the tag name.',
                                                 'Pass tag (a name from agent_outliner tags, "" or "Untagged" for none) and ids.')
            end

            targets = self.na_targets(model, params, allow_model: false)
            if targets.empty?
                raise Na__McpOperationsError.new('invalid_params', 'tag needs ids.', 'Pass the persistent ids of the objects to move.')
            end

            create = params['create'] == true
            if !create && Na__AgentOutliner::Na__EntityActions.Na__Actions__FindTag(model, params['tag']).nil?
                names = model.layers.to_a.drop(1).map { |layer| Na__AgentOutliner::Na__Walker.Na__Walker__TagName(layer, model.layers[0]) }
                raise Na__McpOperationsError.new('not_found', "There is no tag named '#{params['tag']}'.",
                                                 "Use one of: #{names.first(40).join(', ')}#{names.length > 40 ? ' ...' : ''}; or pass create: true to make it (ask Adam first).")
            end

            result = Na__AgentOutliner::Na__EntityActions.Na__Actions__SetTag(model, targets, params['tag'], create: create, operation_name: NA_OPERATION)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushTags(model) if result['created']
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushRows(model, targets.map(&:persistent_id))
            {
                'done'    => 'tag',
                'tag'     => result['tag'].to_s.empty? ? 'Untagged' : result['tag'],
                'moved'   => result['count'],
                'created' => result['created'],
                'undo'    => result['count'].zero? && !result['created'] ? nil : NA_OPERATION
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Notice Helpers
# -----------------------------------------------------------------------------

        # One pass: every object with notes, then the model's own thread.
        # Returns { targets: [objects with something waiting], notice: Hash or nil }.
        def self.na_build_notice(model, state)
            seen    = state[:history]['seen']
            notes   = Na__AgentOutliner::Na__Notes
            found   = []
            targets = []
            Na__AgentOutliner::Na__Tracker.Na__Tracker__Refs(model).each_value do |entity|
                next unless notes.Na__Notes__Any?(entity)

                waiting = notes.Na__Notes__WaitingForAgent(entity, notes.Na__Notes__Read(entity), seen)
                next if waiting.empty?

                targets << entity
                waiting.each { |entry| found << [entity, entry] }
            end
            on_model = notes.Na__Notes__WaitingForAgent(model, notes.Na__Notes__Read(model), seen)
            on_model.each { |entry| found << [model, entry] }
            return { targets: targets, notice: nil } if found.empty?

            target, entry = found.max_by { |pair| [Na__AgentOutliner::Na__Payloads.na_time_value(pair[1]['at']), pair[1]['id'].to_s] }   # <-- 0.1.14: ids carry milliseconds, so two in one second still order
            from     = entry['author'].to_s.strip.empty? ? Na__AgentOutliner.Na__AgentOutliner__UserName : entry['author'].to_s
            pictures = Array(entry['images']).length
            threads  = targets.length + (on_model.empty? ? 0 : 1)
            notice = {
                'waiting' => found.length,
                'from'    => from,
                'at'      => entry['at'].to_s,
                'ago'     => nil,
                'where'   => target.is_a?(Sketchup::Model) ? 'model chat' : "#{self.na_notice_name(target)} (id #{target.persistent_id})",
                'text'    => self.na_notice_text(entry['text'], pictures)
            }
            notice['kind']     = entry['kind'] unless entry['kind'] == 'comment'
            notice['effort']   = entry['effort'] if entry['effort']                     # <-- 0.1.14: the reasoning effort he picked; a dispatcher applies it
            notice['pictures'] = pictures if pictures > 0
            notice['threads']  = threads if threads > 1
            notice['read']     = NA_NOTICE_READ
            notice['note']     = "#{from} wrote to you in the Agent Outliner. Read it before your next change, then reply " \
                                 '(agent_outliner_edit reply; model: true for the model chat) or acknowledge it: this notice stops when nothing waits.'
            { targets: targets, notice: notice }
        end

        def self.na_notice_text(text, pictures)
            clean = text.to_s.gsub(/\s+/, ' ').strip
            clean = '[picture]' if clean.empty? && pictures > 0
            clean.length > NA_NOTICE_TEXT ? "#{clean[0, NA_NOTICE_TEXT - 1]}\u2026" : clean
        end

        def self.na_notice_name(entity)
            name = entity.name.to_s
            name = entity.definition.name.to_s if name.empty? && entity.respond_to?(:definition)
            name.empty? ? entity.typename : name
        end

        # '3 min', '2 h'; nil when the time cannot be read.
        def self.na_ago(at)
            seconds = Time.now - Time.iso8601(at.to_s)
            seconds = 0 if seconds.negative?
            return 'just now' if seconds < 60
            return "#{(seconds / 60).floor} min" if seconds < 3600
            return "#{(seconds / 3600).floor} h" if seconds < 86_400

            "#{(seconds / 86_400).floor} d"
        rescue ArgumentError, TypeError
            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # The MCP passes its open model; without one (a direct call) the active.
        def self.na_model(params)
            model = params['model_object'] || Sketchup.active_model
            raise Na__McpOperationsError.new('not_found', 'No model is open in SketchUp.', 'Open a model, then call again.') unless model

            model
        end

        def self.na_params(params)
            params.is_a?(Hash) ? params.each_with_object({}) { |(key, value), copy| copy[key.to_s] = value } : {}
        end

        # The objects named by ids (persistent ids) and/or the model itself.
        def self.na_targets(model, params, allow_model:)
            targets = []
            targets << model if allow_model && params['model'] == true
            ids = Array(params['ids'])
            if ids.length > NA_MAX_IDS
                raise Na__McpOperationsError.new('invalid_params', "At most #{NA_MAX_IDS} ids in one call; this one has #{ids.length}.", 'Split the call.')
            end

            missing = []
            refused = []
            ids.each do |raw|
                pid = raw.to_i
                entity = Na__AgentOutliner::Na__EntityActions.Na__Actions__FindById(model, pid)
                if entity
                    targets << entity
                elsif self.na_any_entity(model, pid)
                    refused << raw                                                       # <-- It exists, but is an edge, face or the like: say so
                else
                    missing << raw
                end
            end
            unless missing.empty?
                raise Na__McpOperationsError.new('not_found', "No group, component, image or section plane has the persistent id #{missing.join(', ')}.",
                                                 'Read ids with agent_outliner find, entity_query or outliner_tree.', { 'missing' => missing })
            end
            unless refused.empty?
                raise Na__McpOperationsError.new('wrong_type', "#{refused.join(', ')} cannot carry notes: only groups, components, images and section planes can.",
                                                 'Pass the id of the group or component that holds the geometry.', { 'refused' => refused })
            end
            if targets.empty?
                hint = allow_model ? 'Pass ids (persistent ids) and/or model: true.' : 'Pass ids (persistent ids).'
                raise Na__McpOperationsError.new('invalid_params', 'Say which objects.', hint)
            end
            targets.uniq
        end

        # Any live entity with this persistent id, whatever its kind (SketchUp
        # 2020.2+), so an edge's id can be refused for what it is.
        def self.na_any_entity(model, pid)
            return nil unless model.respond_to?(:find_entity_by_persistent_id)

            found = model.find_entity_by_persistent_id(pid)
            found = found.first if found.is_a?(Array)
            found && found.valid? ? found : nil
        end

        # Every entry Adam wrote on these targets (and their flags) marked read.
        def self.na_acknowledge_targets(model, targets)
            seen = Na__AgentOutliner::Na__Tracker.Na__Tracker__Seen(model)
            ids = targets.flat_map do |target|
                notes = Na__AgentOutliner::Na__Notes.Na__Notes__Read(target)
                Na__AgentOutliner::Na__Notes.Na__Notes__WaitingForAgent(target, notes, seen).map { |entry| entry['id'] }
            end
            Na__AgentOutliner::Na__Tracker.Na__Tracker__MarkRead(model, 'agent', ids)
        end

        def self.na_after_notes(model, targets)
            pids = targets.reject { |target| target.is_a?(Sketchup::Model) }.map(&:persistent_id)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushRows(model, pids)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__ModelThreadChanged(model) if targets.any? { |target| target.is_a?(Sketchup::Model) }
        end

        def self.na_target_id(target)
            target.is_a?(Sketchup::Model) ? 'model' : target.persistent_id
        end

        def self.na_limit(params, default, max)
            value = params.key?('limit') ? params['limit'].to_i : default
            [[value, 1].max, max].min
        end

# endregion -------------------------------------------------------------------

    end # module Na__McpOperations
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
