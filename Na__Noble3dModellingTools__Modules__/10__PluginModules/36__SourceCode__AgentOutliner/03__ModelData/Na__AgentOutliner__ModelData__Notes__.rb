# =============================================================================
# NA AGENT OUTLINER - MODEL DATA - NOTES (FLAGS AND COMMENT THREADS)
# =============================================================================
#
# FILE       : Na__AgentOutliner__ModelData__Notes__.rb
# NAMESPACE  : Na__AgentOutliner::Na__Notes
# MODULE     : Na__Notes (module functions)
# AUTHOR     : Noble Architecture
# PURPOSE    : Read and write the flag and the two way comment thread an
#              object (or the model itself) carries, for Adam in the dialog
#              and for agents through the MCP seam
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - STORAGE: the dictionary Na__AgentOutliner__Notes on the group, component
#   instance, image or section plane (the instance, so each placed copy has
#   its own notes), or on the model for the model's own thread.
#     schema   1
#     owner    the persistent id it was written on (a copied object carries
#              its source's notes; owner tells the copy it inherited them)
#     flag, flag_by, flag_author, flag_at
#     thread   JSON {status, entries[]} (chunked into thread_000, thread_001
#              ... with thread_chunks once it passes 15,000 characters: long
#              attribute strings are a known risk)
# - AN ENTRY: {id, by ('user' or 'agent'), author, at, kind, text}, and on a
#   comment images: [{file, w, h, bytes, name}] (0.1.6: names of pictures in
#   Na__ChatCache's folder; the text may then be empty), and effort (0.1.14:
#   the reasoning effort Adam picked beside Send: low, medium, high, xhigh or
#   max; none for Auto). Kinds:
#   comment, flag, unflag, resolve, reopen. Flag and status changes are
#   written into the thread too, so an agent reads the whole story in order.
# - UNDO: every write is one named operation through
#   Na__AgentOutliner.Na__Model__WithOperation. Validation happens before it
#   starts, so a refused write leaves no step behind.
# - WHAT IS SEEN is NOT stored here: reading a reply is not a model change.
#   The tracker keeps it per model on this PC (Na__HistoryStore).
# - THE REVISION (0.1.9): a number in memory that moves with every write here
#   and every acknowledge, undo, redo or aborted step (Na__Tracker). The MCP's
#   waiting notice, on every tool result, is cached against it.
#
# =============================================================================

module Na__AgentOutliner
    module Na__Notes

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_CHUNK_CHARS = 15_000 unless defined?(NA_CHUNK_CHARS)                         # <-- Below the ~20,000 character comfort limit for one attribute value
        NA_SNIPPET     = 140    unless defined?(NA_SNIPPET)
        NA_STATUSES    = %w[open resolved].freeze unless defined?(NA_STATUSES)
        NA_AUTHORS     = %w[user agent].freeze unless defined?(NA_AUTHORS)
        NA_EFFORTS     = %w[low medium high xhigh max].freeze unless defined?(NA_EFFORTS)  # <-- The Claude app's effort levels (0.1.14)

        @na_revision = 0 unless defined?(@na_revision)                                   # <-- Kept across Reload Plugin Data, like the tracker's states

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reading
# -----------------------------------------------------------------------------

        # FUNCTION | Everything an Object (or the Model) Carries
        # ------------------------------------------------------------
        # Returns { 'flag' => {...} or nil, 'thread' => {'status', 'entries'},
        #           'copied_from' => pid or nil }
        def self.Na__Notes__Read(target)
            dictionary = self.na_dictionary(target)
            empty = { 'flag' => nil, 'thread' => { 'status' => '', 'entries' => [] }, 'copied_from' => nil }
            return empty unless dictionary

            flag_id = dictionary['flag'].to_s
            flag = flag_id.empty? ? nil : {
                'id'     => flag_id,
                'by'     => dictionary['flag_by'].to_s,
                'author' => dictionary['flag_author'].to_s,
                'at'     => dictionary['flag_at'].to_s
            }

            owner = dictionary['owner'].to_i
            own   = self.na_owner_id(target)
            {
                'flag'        => flag,
                'thread'      => self.na_read_thread(target, dictionary),
                'copied_from' => owner > 0 && own > 0 && owner != own ? owner : nil
            }
        rescue StandardError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Error('Reading notes failed.', error)
            { 'flag' => nil, 'thread' => { 'status' => '', 'entries' => [] }, 'copied_from' => nil }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does It Carry Any Notes? (cheap: no JSON parsing)
        # ------------------------------------------------------------
        def self.Na__Notes__Any?(target)
            self.na_dictionary(target) ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Short Summary a Table Row Carries
        # ------------------------------------------------------------
        # seen = { 'user' => Set of entry ids Adam has read,
        #          'agent' => Set of entry ids (and flag keys) agents have read }
        # Keys: nf flag id, nfb flag by, nc comment count, ns thread status,
        #       nl last text, nlb last by, nla last at, nu unread by Adam,
        #       nw waiting for an agent, cp copied from.
        def self.Na__Notes__RowSummary(target, seen = nil)
            return {} unless self.Na__Notes__Any?(target)

            notes   = self.Na__Notes__Read(target)
            entries = notes['thread']['entries']
            comments = entries.select { |entry| entry['kind'] == 'comment' }
            last    = entries.last
            summary = {}
            if notes['flag']
                summary['nf']  = notes['flag']['id']
                summary['nfb'] = notes['flag']['by']
            end
            unless entries.empty?
                summary['nc']  = comments.length
                summary['ns']  = notes['thread']['status']
                summary['nl']  = last['text'].to_s.empty? && last['images'] ? '[picture]' : last['text'].to_s[0, NA_SNIPPET]
                summary['nlb'] = last['by']
                summary['nla'] = last['at']
            end
            summary['nu'] = self.Na__Notes__UnreadByUser(notes, seen).length
            summary['nw'] = self.Na__Notes__WaitingForAgent(target, notes, seen).length
            summary['cp'] = notes['copied_from'] if notes['copied_from']
            summary.delete('nu') if summary['nu'].zero?
            summary.delete('nw') if summary['nw'].zero?
            summary
        end
        # ---------------------------------------------------------------

        # FUNCTION | Agent Entries Adam Has Not Read Yet
        # ------------------------------------------------------------
        def self.Na__Notes__UnreadByUser(notes, seen)
            read = seen && seen['user'] ? seen['user'] : {}
            notes['thread']['entries'].select { |entry| entry['by'] == 'agent' && !read.include?(entry['id']) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Waits for an Agent on One Object
        # ------------------------------------------------------------
        # Adam's comments no agent has acknowledged, and his flag when its type
        # goes to the inbox (For Agent, Question, Check This) and the thread is
        # not resolved. A flag set here also writes a 'flag' entry, and that
        # entry is what waits; a flag with no entry (written by another tool)
        # waits under its own key until acknowledged.
        def self.Na__Notes__WaitingForAgent(target, notes, seen)
            read = seen && seen['agent'] ? seen['agent'] : {}
            entries = notes['thread']['entries']
            waiting = entries.select do |entry|
                next false unless entry['by'] == 'user' && %w[comment flag reopen].include?(entry['kind']) && !read.include?(entry['id'])

                self.na_flag_entry_waits?(entry)
            end

            flag = notes['flag']
            if flag && flag['by'] == 'user' && notes['thread']['status'] != 'resolved'
                type = Na__AgentOutliner::Na__ConfigStore.Na__Standards__Flag(flag['id'])
                key  = self.Na__Notes__FlagSeenKey(target, flag)
                has_entry = entries.any? { |entry| entry['kind'] == 'flag' && entry['flag'] == flag['id'] }
                if type && type['inbox'] && !has_entry && !read.include?(key)
                    waiting << { 'id' => key, 'by' => 'user', 'kind' => 'flag', 'at' => flag['at'], 'text' => "Flagged #{type['label']}" }
                end
            end
            waiting
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Key That Marks One Setting of a Flag as Read by an Agent
        # ------------------------------------------------------------
        def self.Na__Notes__FlagSeenKey(target, flag)
            "flag:#{self.na_owner_id(target)}:#{flag['id']}:#{flag['at']}"
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Revision (0.1.9: what the MCP's waiting notice is cached against)
# -----------------------------------------------------------------------------

        # FUNCTION | A Number That Moves Whenever What Waits for an Agent May Have Changed
        # ------------------------------------------------------------
        # Moved by every thread or flag written here (na_update_thread), an
        # agent's acknowledge (Na__Tracker__MarkRead), undo, redo and an
        # aborted step (Na__Tracker), and the standards saved (which flag
        # types wait). In memory only: it means nothing after a restart.
        def self.Na__Notes__Revision
            @na_revision.to_i
        end

        def self.Na__Notes__Touch
            @na_revision = @na_revision.to_i + 1
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Writing (each call is ONE undo step)
# -----------------------------------------------------------------------------

        # FUNCTION | A Reasoning Effort, Checked: low ... max, or nil for Auto (0.1.14)
        # ------------------------------------------------------------
        def self.Na__Notes__Effort(value)
            text = value.to_s.strip.downcase
            return nil if text.empty? || text == 'auto'
            raise ArgumentError, "Reasoning effort is auto, #{NA_EFFORTS.join(', ')}; not '#{value.to_s[0, 20]}'." unless NA_EFFORTS.include?(text)

            text
        end
        # ---------------------------------------------------------------

        # FUNCTION | Add a Comment to Each Target's Thread
        # ------------------------------------------------------------
        # A new comment on a resolved thread opens it again. Returns the new
        # entries, one per target, in target order. effort: the reasoning
        # effort Adam asks agents to work at (0.1.14; nil for Auto).
        def self.Na__Notes__Comment(model, targets, text, by:, author:, operation_name:, images: nil, effort: nil)
            pictures = Array(images)
            effort = self.Na__Notes__Effort(effort)
            text = self.na_clean_text(text, allow_empty: !pictures.empty?)
            self.na_check_targets(targets)
            self.na_check_author(by)

            Na__AgentOutliner.Na__Model__WithOperation(model, operation_name) do
                targets.map do |target|
                    entry = self.na_entry('comment', by, author, text)
                    entry['images'] = pictures.map(&:dup) unless pictures.empty?          # <-- Names only: the files stay in the chat folder
                    entry['effort'] = effort if effort
                    self.na_update_thread(target) do |thread|
                        thread['status'] = 'open'
                        thread['entries'] << entry
                    end
                    entry
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Set a Flag on Each Target
        # ------------------------------------------------------------
        def self.Na__Notes__SetFlag(model, targets, flag_id, by:, author:, operation_name:, text: nil)
            type = Na__AgentOutliner::Na__ConfigStore.Na__Standards__Flag(flag_id)
            raise ArgumentError, "There is no flag type '#{flag_id}'. Add it in the Configure tab first." unless type

            self.na_check_targets(targets)
            self.na_check_author(by)
            targets.each { |target| raise ArgumentError, 'The model itself cannot carry a flag; flag an object.' if target.is_a?(Sketchup::Model) }
            note = text.to_s.strip.empty? ? "Flagged #{type['label']}" : self.na_clean_text(text)
            at   = Na__AgentOutliner.Na__Time__Now

            Na__AgentOutliner.Na__Model__WithOperation(model, operation_name) do
                targets.map do |target|
                    target.set_attribute(Na__AgentOutliner::NA_DICT_NOTES, 'flag', type['id'])
                    target.set_attribute(Na__AgentOutliner::NA_DICT_NOTES, 'flag_by', by)
                    target.set_attribute(Na__AgentOutliner::NA_DICT_NOTES, 'flag_author', author.to_s[0, 80])
                    target.set_attribute(Na__AgentOutliner::NA_DICT_NOTES, 'flag_at', at)
                    entry = self.na_entry('flag', by, author, note)
                    entry['flag'] = type['id']
                    self.na_update_thread(target) do |thread|
                        thread['status'] = 'open' if type['inbox']
                        thread['entries'] << entry
                    end
                    entry
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Clear the Flag on Each Target
        # ------------------------------------------------------------
        def self.Na__Notes__ClearFlag(model, targets, by:, author:, operation_name:)
            self.na_check_targets(targets)
            self.na_check_author(by)
            flagged = targets.select { |target| !target.is_a?(Sketchup::Model) && self.Na__Notes__Read(target)['flag'] }
            return [] if flagged.empty?

            Na__AgentOutliner.Na__Model__WithOperation(model, operation_name) do
                flagged.map do |target|
                    old = self.Na__Notes__Read(target)['flag']
                    %w[flag flag_by flag_author flag_at].each { |key| target.delete_attribute(Na__AgentOutliner::NA_DICT_NOTES, key) }
                    type  = Na__AgentOutliner::Na__ConfigStore.Na__Standards__Flag(old['id'])
                    entry = self.na_entry('unflag', by, author, "Cleared the flag #{type ? type['label'] : old['id']}")
                    self.na_update_thread(target) { |thread| thread['entries'] << entry }
                    entry
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve or Reopen Each Target's Thread
        # ------------------------------------------------------------
        def self.Na__Notes__SetStatus(model, targets, status, by:, author:, operation_name:, text: nil)
            raise ArgumentError, "A thread is open or resolved, not '#{status}'." unless NA_STATUSES.include?(status.to_s)

            self.na_check_targets(targets)
            self.na_check_author(by)
            kind = status.to_s == 'resolved' ? 'resolve' : 'reopen'
            note = text.to_s.strip.empty? ? (kind == 'resolve' ? 'Resolved' : 'Reopened') : self.na_clean_text(text)

            Na__AgentOutliner.Na__Model__WithOperation(model, operation_name) do
                targets.map do |target|
                    entry = self.na_entry(kind, by, author, note)
                    self.na_update_thread(target) do |thread|
                        thread['status'] = status.to_s
                        thread['entries'] << entry
                    end
                    entry
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Delete One Entry From a Thread
        # ------------------------------------------------------------
        def self.Na__Notes__DeleteEntry(model, target, entry_id, operation_name:)
            self.na_check_targets([target])
            thread = self.Na__Notes__Read(target)['thread']
            raise ArgumentError, 'That entry is not in this thread any more.' unless thread['entries'].any? { |entry| entry['id'] == entry_id.to_s }

            Na__AgentOutliner.Na__Model__WithOperation(model, operation_name) do
                self.na_update_thread(target) do |current|
                    current['entries'].reject! { |entry| entry['id'] == entry_id.to_s }
                    current['status'] = '' if current['entries'].empty?
                end
                true
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers - Threads
# -----------------------------------------------------------------------------

        def self.na_dictionary(target)
            return nil unless target && target.respond_to?(:attribute_dictionary)
            return nil if target.respond_to?(:valid?) && !target.is_a?(Sketchup::Model) && !target.valid?

            target.attribute_dictionary(Na__AgentOutliner::NA_DICT_NOTES)
        end

        def self.na_owner_id(target)
            return 0 if target.is_a?(Sketchup::Model)

            target.respond_to?(:persistent_id) ? target.persistent_id.to_i : 0
        end

        def self.na_read_thread(target, dictionary)
            chunks = dictionary['thread_chunks'].to_i
            text = if chunks > 0
                       (0...chunks).map { |index| dictionary[format('thread_%03d', index)].to_s }.join
                   else
                       dictionary['thread'].to_s
                   end
            return { 'status' => '', 'entries' => [] } if text.strip.empty?

            text = text.dup.force_encoding('UTF-8')
            parsed = JSON.parse(text)
            entries = Array(parsed['entries']).select { |entry| entry.is_a?(Hash) && entry['id'] }
            status  = NA_STATUSES.include?(parsed['status'].to_s) ? parsed['status'].to_s : (entries.empty? ? '' : 'open')
            { 'status' => status, 'entries' => entries }
        rescue JSON::ParserError, EncodingError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("A comment thread on #{self.na_owner_id(target)} could not be read: #{error.message}")
            { 'status' => '', 'entries' => [] }
        end

        # Reads the thread, lets the block change it, writes it back (chunked
        # when long), stamps the owner, and removes the whole dictionary once
        # nothing is left in it.
        def self.na_update_thread(target)
            thread = self.Na__Notes__Read(target)['thread']
            thread = { 'status' => thread['status'], 'entries' => thread['entries'].dup }
            yield thread

            max = Na__AgentOutliner::Na__ConfigStore.Na__Config__GetOr(200, 'notes', 'max_entries').to_i
            if thread['entries'].length > max
                raise ArgumentError, "This thread already holds #{max} entries. Resolve it and start the next on the model's thread."
            end

            dict = Na__AgentOutliner::NA_DICT_NOTES
            target.set_attribute(dict, 'schema', 1)
            target.set_attribute(dict, 'owner', self.na_owner_id(target))
            self.na_write_thread_text(target, thread['entries'].empty? ? '' : JSON.generate(thread))
            self.na_drop_if_empty(target)
            self.Na__Notes__Touch
        end

        def self.na_write_thread_text(target, text)
            dict = Na__AgentOutliner::NA_DICT_NOTES
            dictionary = target.attribute_dictionary(dict)
            old_chunks = dictionary ? dictionary['thread_chunks'].to_i : 0
            (0...old_chunks).each { |index| target.delete_attribute(dict, format('thread_%03d', index)) }
            target.delete_attribute(dict, 'thread_chunks') if old_chunks > 0

            if text.empty?
                target.delete_attribute(dict, 'thread')
            elsif text.length <= NA_CHUNK_CHARS
                target.set_attribute(dict, 'thread', text)
            else
                target.delete_attribute(dict, 'thread')
                pieces = (0...text.length).step(NA_CHUNK_CHARS).map { |start| text[start, NA_CHUNK_CHARS] }
                pieces.each_with_index { |piece, index| target.set_attribute(dict, format('thread_%03d', index), piece) }
                target.set_attribute(dict, 'thread_chunks', pieces.length)
            end
        end

        def self.na_drop_if_empty(target)
            dictionary = target.attribute_dictionary(Na__AgentOutliner::NA_DICT_NOTES)
            return unless dictionary

            keys = dictionary.keys - %w[schema owner]
            return unless keys.empty?

            target.attribute_dictionaries.delete(Na__AgentOutliner::NA_DICT_NOTES)
        end

        # 0.1.1: a flag entry waits for an agent only when its type is ticked
        # "waits for an agent" in Configure (For Agent, Question, Check This),
        # or when Adam typed a note with it. A plain Reference, Do Not Touch
        # or Done flag is shown by agent_outliner flags, not put in the inbox.
        # Comments and reopens always wait.
        def self.na_flag_entry_waits?(entry)
            return true unless entry['kind'] == 'flag'

            type = Na__AgentOutliner::Na__ConfigStore.Na__Standards__Flag(entry['flag'])
            return true if type && type['inbox']

            label = type ? type['label'] : entry['flag']
            entry['text'].to_s.strip != "Flagged #{label}"                              # <-- His own note with the flag is something to read
        end

        def self.na_entry(kind, by, author, text)
            {
                'id'     => self.na_new_id,
                'by'     => by.to_s,
                'author' => author.to_s.strip.empty? ? (by.to_s == 'agent' ? 'Agent' : Na__AgentOutliner.Na__AgentOutliner__UserName) : author.to_s.strip[0, 80],
                'at'     => Na__AgentOutliner.Na__Time__Now,
                'kind'   => kind,
                'text'   => text.to_s
            }
        end

        # Sortable, unique and short: time to the millisecond plus four random
        # hex digits (two comments in the same millisecond still differ).
        def self.na_new_id
            "c#{Time.now.strftime('%Y%m%d%H%M%S%L')}#{format('%04x', rand(65_536))}"
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers - Checks (all run BEFORE any undo step opens)
# -----------------------------------------------------------------------------

        def self.na_clean_text(text, allow_empty: false)
            clean = text.to_s.dup.force_encoding('UTF-8')
            clean = clean.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?') unless clean.valid_encoding?
            clean = clean.gsub("\r\n", "\n").strip
            raise ArgumentError, 'Write something first: the comment is empty.' if clean.empty? && !allow_empty

            max = Na__AgentOutliner::Na__ConfigStore.Na__Config__GetOr(4000, 'notes', 'max_text_chars').to_i
            raise ArgumentError, "A comment can be up to #{max} characters; this one is #{clean.length}." if clean.length > max

            clean
        end

        def self.na_check_targets(targets)
            raise ArgumentError, 'Choose at least one object (or the model).' if targets.nil? || targets.empty?

            targets.each do |target|
                next if target.is_a?(Sketchup::Model)
                raise ArgumentError, 'One of the objects no longer exists (it was erased or undone).' unless target.respond_to?(:valid?) && target.valid?
                raise ArgumentError, "A #{target.typename} cannot carry notes; choose a group, component, image or section plane." unless Na__AgentOutliner::Na__Walker.Na__Walker__Kind(target)
            end
        end

        def self.na_check_author(by)
            raise ArgumentError, "A note is written by 'user' or 'agent', not '#{by}'." unless NA_AUTHORS.include?(by.to_s)
        end

# endregion -------------------------------------------------------------------

    end # module Na__Notes
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
