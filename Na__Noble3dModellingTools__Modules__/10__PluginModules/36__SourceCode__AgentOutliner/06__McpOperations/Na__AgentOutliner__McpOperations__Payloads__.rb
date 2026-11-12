# =============================================================================
# NA AGENT OUTLINER - MCP OPERATIONS - PAYLOADS
# =============================================================================
#
# FILE       : Na__AgentOutliner__McpOperations__Payloads__.rb
# NAMESPACE  : Na__AgentOutliner::Na__Payloads
# MODULE     : Na__Payloads (module functions)
# AUTHOR     : Noble Architecture
# PURPOSE    : Build every shape this tool hands out: the dialog's snapshot
#              and deltas, and the agent's views (an object, the inbox, the
#              changes, the naming standards, a search), so Adam's table and
#              an agent's answer can never disagree
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - READ ONLY. Nothing here changes the model or the history.
# - THE SEARCH LANGUAGE is the dialog's, so Adam can hand an agent the query he
#   typed (agent_outliner {action: "find", query: "tag:06__Drawings is:new"}):
#     words          match name, definition, tag, prefix, id, flag, material,
#                    the last comment
#     field:value    name: def: tag: type: flag: by: is: has: prefix: id: mat: note:
#     -term          leaves matches out
#     "two words"    a phrase
#     /pattern/      a regular expression on the names
#     a | b          either side (OR); terms side by side must all match (AND)
#   is: new updated changed recent unseen hidden locked visible flagged
#       unread waiting unnamed resolved open
#   by: agent user (me)    type: group component image section
# - TIME WINDOWS come from Settings > Colour grading: the last band is "how
#   long a change stays coloured" (new, updated, changed); the second band is
#   "recent". The dialog uses the same numbers.
#
# =============================================================================

module Na__AgentOutliner
    module Na__Payloads

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_TYPE_WORDS = { 'group' => 'g', 'groups' => 'g', 'component' => 'c', 'components' => 'c', 'comp' => 'c',
                          'image' => 'i', 'images' => 'i', 'section' => 's', 'sections' => 's' }.freeze unless defined?(NA_TYPE_WORDS)
        NA_FIELDS     = %w[name def tag type flag by is has prefix id pid mat note].freeze unless defined?(NA_FIELDS)
        NA_LAST_TEXT  = 240 unless defined?(NA_LAST_TEXT)                                 # <-- The threads list quotes this much of each thread's last word

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Payloads
# -----------------------------------------------------------------------------

        # FUNCTION | The Whole Tree (dialog open, Refresh, model switched)
        # ------------------------------------------------------------
        def self.Na__Payload__Snapshot(model)
            Na__AgentOutliner::Na__Tracker.Na__Tracker__Ready(model)
            context = self.Na__Payload__Context(model)
            refs = Na__AgentOutliner::Na__Tracker.Na__Tracker__Refs(model)
            children, defs = Na__AgentOutliner::Na__Tracker.Na__Tracker__Structure(model)

            ents = {}
            refs.each { |pid, entity| ents[pid.to_s] = Na__AgentOutliner::Na__Walker.Na__Walker__Row(entity, context) }
            used = {}
            ents.each_value { |row| used[row['d']] = true if row['d'] }
            def_rows = {}
            used.each_key do |key|
                definition = defs[key]
                next unless definition && definition.valid?

                row = Na__AgentOutliner::Na__Walker.Na__Walker__DefRow(definition)
                row['ch'] = Array(children[key]).select { |pid| ents.key?(pid.to_s) }
                def_rows[key] = row
            end

            history = Na__AgentOutliner::Na__Tracker.Na__Tracker__StateFor(model)[:history]
            {
                'model'       => self.Na__Payload__ModelInfo(model),
                'ents'        => ents,
                'defs'        => def_rows,
                'roots'       => Array(children[Na__AgentOutliner::Na__Walker::NA_ROOT_KEY]).select { |pid| ents.key?(pid.to_s) },
                'tags'        => self.Na__Payload__Tags(model),
                'status'      => history['status'],
                'events'      => history['events'].last(400),
                'seq'         => history['seq'].to_i,
                'seen'        => { 'user_seq' => history['seen']['user_seq'].to_i, 'agent_seq' => history['seen']['agent_seq'].to_i },
                'tracking'    => Na__AgentOutliner::Na__Tracker.Na__Tracker__Info(model),
                'model_notes' => self.Na__Payload__Thread(model, model)
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Changed: Rows, Containers and Events
        # ------------------------------------------------------------
        def self.Na__Payload__Delta(model, pids, containers, events)
            context = self.Na__Payload__Context(model)
            refs = Na__AgentOutliner::Na__Tracker.Na__Tracker__Refs(model)
            children, defs = Na__AgentOutliner::Na__Tracker.Na__Tracker__Structure(model)
            event_pids = Array(events).map { |event| event['pid'] }
            rows = {}
            removed = []
            (Array(pids) | event_pids).uniq.each do |pid|
                entity = refs[pid.to_i]
                if entity
                    rows[pid.to_s] = Na__AgentOutliner::Na__Walker.Na__Walker__Row(entity, context)
                else
                    removed << pid.to_i
                end
            end

            def_rows = {}
            roots = nil
            Array(containers).uniq.each do |key|
                if key == Na__AgentOutliner::Na__Walker::NA_ROOT_KEY
                    roots = Array(children[key]).select { |pid| refs.key?(pid) }
                    next
                end
                definition = defs[key]
                next unless definition && definition.valid?

                row = Na__AgentOutliner::Na__Walker.Na__Walker__DefRow(definition)
                row['ch'] = Array(children[key]).select { |pid| refs.key?(pid) }
                def_rows[key] = row
            end
            rows.each_value do |row|
                key = row['d']
                next if key.nil? || def_rows.key?(key)

                definition = defs[key]
                next unless definition && definition.valid?

                def_row = Na__AgentOutliner::Na__Walker.Na__Walker__DefRow(definition)
                def_row['ch'] = Array(children[key]).select { |pid| refs.key?(pid) }
                def_rows[key] = def_row
            end

            status = Na__AgentOutliner::Na__Tracker.Na__Tracker__Status(model)
            delta = {
                'rows'    => rows,
                'removed' => removed,
                'defs'    => def_rows,
                'events'  => Array(events),
                'status'  => event_pids.each_with_object({}) { |pid, map| map[pid.to_s] = status[pid.to_s] if status[pid.to_s] },
                'seq'     => Na__AgentOutliner::Na__Tracker.Na__Tracker__Seq(model)
            }
            delta['roots'] = roots if roots
            delta
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Tag: Shown (with its folders), Colour, and Its Folders
        # ------------------------------------------------------------
        # 'f' and 'fs' (0.1.16, Tree by Tag): the tag's folders outermost first
        # and whether each is shown, only for a tag inside a folder. Folder
        # names need not be unique, so the page keys a folder by its path.
        def self.Na__Payload__Tags(model)
            layer0 = model.layers[0]
            tags = {}
            model.layers.each do |layer|
                next if layer.equal?(layer0) || layer == layer0

                name  = layer.respond_to?(:display_name) ? layer.display_name.to_s : layer.name.to_s
                entry = { 'v' => Na__AgentOutliner::Na__Walker.Na__Walker__TagShown?(layer), 'c' => self.na_colour_hex(layer) }
                folders = self.na_tag_folders(layer)
                unless folders.empty?
                    entry['f']  = folders.map { |folder| folder.name.to_s }
                    entry['fs'] = folders.map { |folder| folder.respond_to?(:visible?) ? (folder.visible? ? true : false) : true }
                end
                tags[name] = entry
            end
            tags
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Tag's Folders, Outermost First ([] at the top level)
        # ------------------------------------------------------------
        def self.na_tag_folders(layer)
            folders = []
            folder  = layer.respond_to?(:folder) ? layer.folder : nil
            guard   = 0
            while folder && guard < 32
                folders.unshift(folder)
                folder = folder.respond_to?(:folder) ? folder.folder : nil
                guard += 1
            end
            folders
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Tag for an Agent: name, colour, shown, folder, and how many objects (0.1.5)
        # ------------------------------------------------------------
        def self.Na__Payload__TagList(model)
            layer0 = model.layers[0]
            counts = Hash.new(0)
            Na__AgentOutliner::Na__Tracker.Na__Tracker__Refs(model).each_value do |entity|
                next unless entity.valid?

                counts[Na__AgentOutliner::Na__Walker.Na__Walker__TagName(entity.layer, layer0)] += 1
            end
            tags = []
            model.layers.each do |layer|
                next if layer.equal?(layer0) || layer == layer0

                name   = Na__AgentOutliner::Na__Walker.Na__Walker__TagName(layer, layer0)
                path   = self.na_tag_folders(layer).map { |folder| folder.name.to_s }
                tags << {
                    'name'    => name,
                    'colour'  => self.na_colour_hex(layer),
                    'shown'   => Na__AgentOutliner::Na__Walker.Na__Walker__TagShown?(layer),
                    'folder'  => path.empty? ? nil : path.join(' / '),
                    'objects' => counts[name]
                }
            end
            tags.sort_by! { |tag| tag['name'].downcase }
            {
                'tags'     => tags,
                'untagged' => counts[''],
                'how_to'   => 'Groups, components, images and section planes counted. find with "tag:NAME" lists the objects on a tag; ' \
                              'agent_outliner_edit tag (ids, tag; create: true to make a new one) moves objects onto a tag in one undo step.'
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Model's Title, File and Open Group
        # ------------------------------------------------------------
        def self.Na__Payload__ModelInfo(model)
            {
                'title'    => model.title.to_s.empty? ? 'Untitled' : model.title.to_s,
                'path'     => model.path.to_s,
                'key'      => Na__AgentOutliner::Na__HistoryStore.Na__History__KeyFor(model),
                'modified' => model.modified? ? true : false,
                'active'   => Array(model.active_path).map(&:persistent_id),
                'front_faces' => Na__AgentOutliner::Na__Naming.Na__Naming__FrontFaces(model)
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Every Row Needs to Know (built once per payload)
        # ------------------------------------------------------------
        def self.Na__Payload__Context(model)
            {
                layer0:   model.layers[0],
                prefixes: Na__AgentOutliner::Na__ConfigStore.Na__Standards__Prefixes,
                seen:     Na__AgentOutliner::Na__Tracker.Na__Tracker__Seen(model),
                front:    Na__AgentOutliner::Na__Naming.Na__Naming__FrontFaces(model)
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Agent Payloads
# -----------------------------------------------------------------------------

        # FUNCTION | One Object, Everything an Agent Needs to Act on It
        # ------------------------------------------------------------
        def self.Na__Payload__Object(model, entity, context = nil, include_thread: true)
            context ||= self.Na__Payload__Context(model)
            row    = Na__AgentOutliner::Na__Walker.Na__Walker__Row(entity, context)
            notes  = Na__AgentOutliner::Na__Notes.Na__Notes__Read(entity)
            prefix = Na__AgentOutliner::Na__Naming.Na__Naming__MatchPrefix(row['n'], context[:prefixes])
            status = Na__AgentOutliner::Na__Tracker.Na__Tracker__Status(model)[entity.persistent_id.to_s]
            item = {
                'id'         => entity.persistent_id,
                'type'       => Na__AgentOutliner::Na__Walker::NA_TYPE_NAMES[row['k']],
                'name'       => row['n'],
                'shown_as'   => row['dn'],
                'tag'        => row['t'].to_s.empty? ? 'Untagged' : row['t'],
                'hidden'     => row['h'],
                'locked'     => row['l'],
                'path'       => Na__AgentOutliner::Na__Walker.Na__Walker__PathSummary(Na__AgentOutliner::Na__Walker.Na__Walker__FirstPath(entity))
            }
            item['definition'] = entity.definition.name if entity.is_a?(Sketchup::ComponentInstance)
            item['copies']     = entity.definition.instances.length if entity.respond_to?(:definition) && !entity.is_a?(Sketchup::Image)
            item['material']   = row['m'] unless row['m'].to_s.empty?
            item['size_mm']    = row['sz'] if row['sz']
            item['prefix']     = { 'label' => prefix['label'], 'meaning' => prefix['meaning'] } if prefix
            item['flag']       = self.na_flag_payload(notes['flag']) if notes['flag']
            item['change']     = self.na_status_payload(status) if status
            item['copied_from'] = notes['copied_from'] if notes['copied_from']
            item['thread']     = self.na_thread_payload(entity, notes, context[:seen]) if include_thread && !notes['thread']['entries'].empty?
            item
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Thread (an object's or the model's), Entries Marked New
        # ------------------------------------------------------------
        def self.Na__Payload__Thread(model, target)
            notes = Na__AgentOutliner::Na__Notes.Na__Notes__Read(target)
            seen  = Na__AgentOutliner::Na__Tracker.Na__Tracker__Seen(model)
            self.na_thread_payload(target, notes, seen)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Everything Waiting for an Agent
        # ------------------------------------------------------------
        def self.Na__Payload__Inbox(model, include_seen: false, limit: 50)
            context = self.Na__Payload__Context(model)
            seen    = include_seen ? { 'user' => {}, 'agent' => {} } : context[:seen]
            items   = []
            waiting_total = 0
            Na__AgentOutliner::Na__Tracker.Na__Tracker__Refs(model).each_value do |entity|
                next unless Na__AgentOutliner::Na__Notes.Na__Notes__Any?(entity)

                notes   = Na__AgentOutliner::Na__Notes.Na__Notes__Read(entity)
                waiting = Na__AgentOutliner::Na__Notes.Na__Notes__WaitingForAgent(entity, notes, seen)
                next if waiting.empty?

                waiting_total += waiting.length
                item = self.Na__Payload__Object(model, entity, context)
                item['waiting'] = waiting.map { |entry| entry['id'] }
                items << item
            end
            items.sort_by! { |item| item['waiting'].length.zero? ? 1 : 0 }

            model_notes   = Na__AgentOutliner::Na__Notes.Na__Notes__Read(model)
            model_waiting = Na__AgentOutliner::Na__Notes.Na__Notes__WaitingForAgent(model, model_notes, seen)
            result = {
                'model'         => self.Na__Payload__ModelInfo(model),
                'waiting_count' => waiting_total + model_waiting.length,
                'object_count'  => items.length,
                'items'         => items.first(limit),
                'truncated'     => items.length > limit
            }
            unless model_waiting.empty?
                thread = self.na_thread_payload(model, model_notes, seen)
                thread['waiting'] = model_waiting.map { |entry| entry['id'] }
                result['model_thread'] = thread
            end
            result['next'] = if result['waiting_count'].zero?
                                 'Nothing is waiting. Adam flags objects or writes comments in the Agent Outliner; check again when he says so.'
                             else
                                 'Do what each thread asks, answer with agent_outliner_edit {action: "reply", ids: [...], text: "..."} ' \
                                     '(model: true for the model thread), then mark what you have read with {action: "acknowledge"}.'
                             end
            result
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Thread in the Model, One Line Each (0.1.1)
        # ------------------------------------------------------------
        # waiting_on: 'agent' when Adam's comments or flag wait for an agent;
        # 'user' when the thread is open and its last comment is an agent's
        # (Adam has not answered or resolved it); nil otherwise. Sorted: on
        # an agent, on Adam, other open threads, resolved; newest first.
        def self.Na__Payload__Threads(model, status: nil, waiting_on: nil, limit: 50)
            seen    = Na__AgentOutliner::Na__Tracker.Na__Tracker__Seen(model)
            targets = [model] + Na__AgentOutliner::Na__Tracker.Na__Tracker__Refs(model).values.select { |entity| Na__AgentOutliner::Na__Notes.Na__Notes__Any?(entity) }
            rows = []
            targets.each do |target|
                notes   = Na__AgentOutliner::Na__Notes.Na__Notes__Read(target)
                entries = notes['thread']['entries']
                next if entries.empty?

                rows << self.na_thread_line(target, notes, seen)
            end

            counts = {
                'threads'          => rows.length,
                'open'             => rows.count { |row| row['status'] == 'open' },
                'resolved'         => rows.count { |row| row['status'] == 'resolved' },
                'waiting_on_agent' => rows.count { |row| row['waiting_on'] == 'agent' },
                'waiting_on_user'  => rows.count { |row| row['waiting_on'] == 'user' }
            }
            rows.select! { |row| row['status'] == status } if status
            rows.select! { |row| row['waiting_on'] == waiting_on } if waiting_on
            rank = { 'agent' => 0, 'user' => 1 }
            rows.sort_by! { |row| [rank.fetch(row['waiting_on'], row['status'] == 'resolved' ? 3 : 2), -self.na_time_value(row['last']['at'])] }
            {
                'model'     => self.Na__Payload__ModelInfo(model),
                'counts'    => counts,
                'count'     => rows.length,
                'items'     => rows.first(limit),
                'truncated' => rows.length > limit,
                'next'      => 'Read a whole thread with {action: "thread", ids: [...]} (model: true for the model). ' \
                               'waiting_on agent: answer with agent_outliner_edit reply. waiting_on user: Adam has not answered yet.'
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Chat Tab's List: every thread, the model's first, and the agents in them (0.1.6)
        # ------------------------------------------------------------
        # The model's own chat is always listed, even before anyone wrote in it.
        # agents: every agent author, with when it last wrote and in how many
        # chats; an agent signs with author ('Claude (bay window session)').
        def self.Na__Payload__ChatList(model)
            seen    = Na__AgentOutliner::Na__Tracker.Na__Tracker__Seen(model)
            targets = Na__AgentOutliner::Na__Tracker.Na__Tracker__Refs(model).values.select { |entity| entity.valid? && Na__AgentOutliner::Na__Notes.Na__Notes__Any?(entity) }
            lines   = []
            agents  = {}
            ([model] + targets).each do |target|
                notes   = Na__AgentOutliner::Na__Notes.Na__Notes__Read(target)
                entries = notes['thread']['entries']
                if entries.empty?
                    lines << { 'target' => 'model', 'status' => '', 'entries' => 0, 'comments' => 0, 'agents' => [] } if target.equal?(model)
                    next
                end

                line = self.na_thread_line(target, notes, seen)
                line['kind'] = Na__AgentOutliner::Na__Walker.Na__Walker__Kind(target) unless target.is_a?(Sketchup::Model)
                lines << line
                entries.each do |entry|
                    next unless entry['by'] == 'agent'

                    name = entry['author'].to_s.strip.empty? ? 'Agent' : entry['author'].to_s
                    info = (agents[name] ||= { 'author' => name, 'messages' => 0, 'chats' => {}, 'last_at' => '' })
                    info['messages'] += 1
                    info['chats'][line['target'].to_s] = true
                    info['last_at'] = entry['at'].to_s if self.na_time_value(entry['at']) > self.na_time_value(info['last_at'])
                end
            end
            people = agents.values.map { |info| info.merge('chats' => info['chats'].length) }
            people.sort_by! { |info| -self.na_time_value(info['last_at']) }
            {
                'model'   => self.Na__Payload__ModelInfo(model),
                'threads' => lines,
                'agents'  => people,
                'unread'  => lines.sum { |line| line['unread_by_adam'].to_i },
                'cache'   => Na__AgentOutliner::Na__ChatCache.Na__Chat__Info
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Flagged Object, by Flag Type (0.1.1)
        # ------------------------------------------------------------
        # Every type in the standards is listed, with its meaning and count
        # (Do Not Touch with none says so), then any flag whose type has since
        # left the standards.
        def self.Na__Payload__Flags(model, flag_id: nil, by: nil, limit: 100)
            context = self.Na__Payload__Context(model)
            found   = Hash.new { |hash, key| hash[key] = [] }
            Na__AgentOutliner::Na__Tracker.Na__Tracker__Refs(model).each_value do |entity|
                next unless Na__AgentOutliner::Na__Notes.Na__Notes__Any?(entity)

                notes = Na__AgentOutliner::Na__Notes.Na__Notes__Read(entity)
                flag  = notes['flag']
                next unless flag
                next if flag_id && flag['id'] != flag_id
                next if by && flag['by'] != by

                found[flag['id']] << self.na_flag_line(model, entity, notes, context)
            end

            types = Na__AgentOutliner::Na__ConfigStore.Na__Standards__Flags
            types = types.select { |type| type['id'] == flag_id } if flag_id
            groups = types.map do |type|
                items = found.delete(type['id']) || []
                self.na_flag_group(type['id'], type['label'], type['meaning'], type['inbox'], items, limit)
            end
            found.each do |id, items|
                groups << self.na_flag_group(id, id, 'This flag type is no longer in the standards.', false, items, limit)
            end
            {
                'model'     => self.Na__Payload__ModelInfo(model),
                'count'     => groups.sum { |group| group['count'] },
                'flags'     => groups,
                'truncated' => groups.any? { |group| group['count'] > group['objects'].length },
                'next'      => 'Follow each flag\'s meaning: never change Do Not Touch or Reference objects. ' \
                               'Read a flagged object\'s thread with {action: "thread", ids: [...]}.'
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Recorded Changes, by Object or as Events
        # ------------------------------------------------------------
        def self.Na__Payload__Changes(model, since_seq: nil, since_time: nil, by: nil, limit: 200, group: 'object')
            seen = Na__AgentOutliner::Na__Tracker.Na__Tracker__Seen(model)
            since_seq = seen['agent_seq'].to_i if since_seq.nil? && since_time.nil?
            events = Na__AgentOutliner::Na__Tracker.Na__Tracker__Events(model, since_seq: since_seq, since_time: since_time, by: by, limit: 5000)
            cursor = Na__AgentOutliner::Na__Tracker.Na__Tracker__Seq(model)
            base = {
                'model'      => self.Na__Payload__ModelInfo(model),
                'since_seq'  => since_seq,
                'since_time' => since_time,
                'cursor'     => cursor,
                'event_count'=> events.length,
                'note'       => 'Pass cursor as since_seq next time, or acknowledge with agent_outliner_edit {action: "acknowledge", changes: true}.'
            }
            if group == 'event'
                base['events'] = events.last(limit)
                base['truncated'] = events.length > limit
                return base
            end

            refs    = Na__AgentOutliner::Na__Tracker.Na__Tracker__Refs(model)
            objects = {}
            events.each do |event|
                item = (objects[event['pid']] ||= {
                    'id' => event['pid'], 'name' => event['name'], 'type' => event['type'],
                    'kinds' => [], 'fields' => [], 'by' => [], 'tools' => [], 'first_at' => event['at'], 'last_at' => event['at']
                })
                item['kinds']  |= [event['kind']]
                item['fields'] |= Array(event['fields'])
                item['by']     |= [event['by']]
                item['tools']  |= [event['tool']] if event['tool']
                item['last_at'] = event['at']
                item['via']     = event['via'] if event['via']
            end
            objects.each_value do |item|
                item['exists'] = refs.key?(item['id'].to_i)
                item.delete('tools') if item['tools'].empty?
            end
            list = objects.values.sort_by { |item| item['last_at'].to_s }.reverse
            base['objects']   = list.first(limit)
            base['truncated'] = list.length > limit
            base['by_user']   = list.count { |item| item['by'].include?('user') }
            base['by_agent']  = list.count { |item| item['by'].include?('agent') }
            base
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Naming Standards, and Which Objects Carry Each Prefix
        # ------------------------------------------------------------
        def self.Na__Payload__Prefixes(model)
            standards = Na__AgentOutliner::Na__ConfigStore.Na__Standards__All
            carriers  = Hash.new { |hash, key| hash[key] = [] }
            Na__AgentOutliner::Na__Tracker.Na__Tracker__Refs(model).each_value do |entity|
                name  = Na__AgentOutliner::Na__Walker.Na__Walker__Name(entity)
                entry = Na__AgentOutliner::Na__Naming.Na__Naming__MatchPrefix(name, standards['prefixes'])
                next unless entry

                carriers[entry['id']] << { 'id' => entity.persistent_id, 'name' => name,
                                           'path' => Na__AgentOutliner::Na__Walker.Na__Walker__PathSummary(Na__AgentOutliner::Na__Walker.Na__Walker__FirstPath(entity)) }
            end
            {
                'prefixes' => standards['prefixes'].map do |entry|
                    found = carriers[entry['id']]
                    {
                        'label'    => entry['label'],
                        'category' => entry['category'],
                        'mode'     => entry['mode'],
                        'meaning'  => entry['meaning'],
                        'objects'  => found.first(50),
                        'count'    => found.length
                    }
                end,
                'flags' => standards['flags'].map do |flag|
                    { 'id' => flag['id'], 'label' => flag['label'], 'in_inbox' => flag['inbox'], 'meaning' => flag['meaning'] }
                end,
                'naming_rule' => 'replace: the name becomes exactly the label; prefix: label__ then the name it had. Quick Name only ever changes names, never tags.'
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Search the Outliner the Way the Dialog Does
        # ------------------------------------------------------------
        def self.Na__Payload__Find(model, query, limit: 50)
            groups  = self.Na__Query__Parse(query)
            context = self.Na__Payload__Context(model)
            status  = Na__AgentOutliner::Na__Tracker.Na__Tracker__Status(model)
            windows = self.Na__Query__Windows
            matches = []
            Na__AgentOutliner::Na__Tracker.Na__Tracker__Refs(model).each_value do |entity|
                row  = Na__AgentOutliner::Na__Walker.Na__Walker__Row(entity, context)
                fact = self.na_query_facts(entity, row, status[entity.persistent_id.to_s], context, windows)
                next unless groups.empty? || groups.any? { |terms| terms.all? { |term| self.na_term_matches?(term, fact) } }

                matches << entity
            end
            {
                'query'     => query.to_s,
                'count'     => matches.length,
                'items'     => matches.first(limit).map { |entity| self.Na__Payload__Object(model, entity, context, include_thread: false) },
                'truncated' => matches.length > limit
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Short Account of the Model for an Agent's First Call
        # ------------------------------------------------------------
        def self.Na__Payload__Summary(model)
            context = self.Na__Payload__Context(model)
            refs    = Na__AgentOutliner::Na__Tracker.Na__Tracker__Refs(model)
            counts  = Hash.new(0)
            flags   = Hash.new(0)
            waiting = 0
            unread  = 0
            refs.each_value do |entity|
                counts[Na__AgentOutliner::Na__Walker::NA_TYPE_NAMES[Na__AgentOutliner::Na__Walker.Na__Walker__Kind(entity)]] += 1
                next unless Na__AgentOutliner::Na__Notes.Na__Notes__Any?(entity)

                notes = Na__AgentOutliner::Na__Notes.Na__Notes__Read(entity)
                flags[notes['flag']['id']] += 1 if notes['flag']
                waiting += Na__AgentOutliner::Na__Notes.Na__Notes__WaitingForAgent(entity, notes, context[:seen]).length
                unread  += Na__AgentOutliner::Na__Notes.Na__Notes__UnreadByUser(notes, context[:seen]).length
            end
            model_notes = Na__AgentOutliner::Na__Notes.Na__Notes__Read(model)
            waiting += Na__AgentOutliner::Na__Notes.Na__Notes__WaitingForAgent(model, model_notes, context[:seen]).length
            changes = self.Na__Payload__Changes(model, limit: 0)
            {
                'model'         => self.Na__Payload__ModelInfo(model),
                'objects'       => counts,
                'flagged'       => flags,
                'waiting_for_agent' => waiting,
                'unread_by_adam'    => unread,
                'changes_since_you_last_acknowledged' => {
                    'objects'  => changes['by_user'].to_i + changes['by_agent'].to_i,
                    'by_adam'  => changes['by_user'].to_i,
                    'by_agent' => changes['by_agent'].to_i,
                    'cursor'   => changes['cursor']
                },
                'tracking'      => Na__AgentOutliner::Na__Tracker.Na__Tracker__Info(model),
                'version'       => Na__AgentOutliner.Na__AgentOutliner__Version,
                'log_tail'      => Na__AgentOutliner::Na__DebugTools.Na__Debug__Lines.last(5),
                'next'          => waiting > 0 ? 'Read the inbox: agent_outliner {action: "inbox"}.' : 'Nothing waits. Read what Adam changed with {action: "changes", by: "user"}.'
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Search Language
# -----------------------------------------------------------------------------

        # FUNCTION | Parse a Query Into OR Groups of AND Terms
        # ------------------------------------------------------------
        # Returns [[{neg:, field:, value:, regexp:}, ...], ...].
        def self.Na__Query__Parse(text)
            source = text.to_s.strip
            return [] if source.empty?

            source.split(/\s+(?:\||OR)\s+/).map do |part|
                tokens = part.scan(/-?"[^"]*"|-?\/(?:[^\/\\]|\\.)+\/i?|\S+/)
                tokens.map { |token| self.na_term(token) }.compact
            end.reject(&:empty?)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Time Windows (seconds): coloured and recent
        # ------------------------------------------------------------
        def self.Na__Query__Windows
            bands = Array(Na__AgentOutliner::Na__ConfigStore.Na__Config__Setting('grading', 'band_minutes')).map(&:to_f).select(&:positive?)
            bands = [5.0, 30.0, 120.0, 1440.0] if bands.empty?
            { coloured: bands.last * 60.0, recent: (bands[1] || bands.first) * 60.0 }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        def self.na_term(token)
            negative = token.start_with?('-') && token.length > 1
            token = token[1..-1] if negative
            if token.start_with?('/') && token.match?(/\A\/.+\/i?\z/)
                flags = token.end_with?('i') ? Regexp::IGNORECASE : 0
                body  = token.sub(/\A\//, '').sub(/\/i?\z/, '')
                regexp = begin
                    Regexp.new(body, flags)
                rescue RegexpError
                    nil
                end
                return regexp ? { neg: negative, field: 're', value: '', regexp: regexp } : nil
            end

            token = token[1..-2] if token.length >= 2 && token.start_with?('"') && token.end_with?('"')
            field = nil
            value = token
            if (match = token.match(/\A([a-z]+):(.*)\z/i)) && (NA_FIELDS + %w[face dir]).include?(match[1].downcase)
                field = match[1].downcase
                value = match[2]
                value = value[1..-2] if value.length >= 2 && value.start_with?('"') && value.end_with?('"')
            end
            return nil if value.to_s.empty? && field.nil?

            { neg: negative, field: field || 'any', value: value.to_s.downcase, regexp: nil }
        end

        # Everything a term can test, worked out once per object.
        def self.na_query_facts(entity, row, status, context, windows)
            now = Time.now.to_f
            created = status && status['c'] && !status['r'] ? now - status['c'].to_f : nil
            updated = status && status['u'] && !status['r'] ? now - status['u'].to_f : nil
            changed = [created, updated].compact.min
            face, cardinal = Na__AgentOutliner::Na__Naming.Na__Naming__ParseFace(row['n'])
            flag    = row['nf'] ? Na__AgentOutliner::Na__ConfigStore.Na__Standards__Flag(row['nf']) : nil
            seen_seq = context[:seen]['user_seq'].to_i
            last_by  = if status
                           (status['u'].to_f > status['c'].to_f ? status['ub'] : status['cb']).to_s
                       else
                           ''
                       end
            {
                row:      row,
                name:     "#{row['n']} #{row['dn']}".downcase,
                def:      entity.respond_to?(:definition) && !entity.is_a?(Sketchup::Image) ? entity.definition.name.to_s.downcase : '',
                tag:      row['t'].to_s.empty? ? 'untagged' : row['t'].to_s.downcase,
                type:     row['k'],
                flag:     flag ? "#{flag['id']} #{flag['label']}".downcase : '',
                by:       last_by,
                prefix:   row['pre'].to_s.downcase,
                id:       entity.persistent_id.to_s,
                mat:      row['m'].to_s.downcase,
                note:     row['nl'].to_s.downcase,
                face:     face.to_s.downcase,
                dir:      (cardinal || Na__AgentOutliner::Na__Naming.Na__Naming__CardinalFor(face, context[:front])).to_s.downcase,
                is: {
                    'new'      => created && created <= windows[:coloured],
                    'updated'  => updated && updated <= windows[:coloured],
                    'changed'  => changed && changed <= windows[:coloured],
                    'recent'   => changed && changed <= windows[:recent],
                    'unseen'   => status && self.na_status_seq_after?(status, seen_seq),
                    'hidden'   => row['h'],
                    'locked'   => row['l'],
                    'visible'  => !row['h'],
                    'flagged'  => !row['nf'].to_s.empty?,
                    'unread'   => row['nu'].to_i > 0,
                    'waiting'  => row['nw'].to_i > 0,
                    'unnamed'  => row['n'].to_s.strip.empty?,
                    'resolved' => row['ns'] == 'resolved',
                    'open'     => row['ns'] == 'open'
                }
            }
        end

        # Unseen: the object's last change came after the change number Adam
        # last marked as seen.
        def self.na_status_seq_after?(status, seen_seq)
            status['s'].to_i > seen_seq.to_i
        end

        def self.na_term_matches?(term, fact)
            value = term[:value]
            hit = case term[:field]
                  when 're'     then !!(fact[:name] =~ term[:regexp] || fact[:def] =~ term[:regexp])
                  when 'name'   then fact[:name].include?(value)
                  when 'def'    then fact[:def].include?(value)
                  when 'tag'    then fact[:tag].include?(value)
                  when 'type'   then fact[:type] == (NA_TYPE_WORDS[value] || value)
                  when 'flag'   then value == 'any' ? !fact[:flag].empty? : fact[:flag].include?(value)
                  when 'by'     then fact[:by] == (value == 'me' || value == 'adam' ? 'user' : value)
                  when 'is'     then fact[:is][value] ? true : false
                  when 'has'
                      case value
                      when 'flag'           then !fact[:flag].empty?
                      when 'notes', 'comment', 'comments', 'thread' then fact[:row]['nc'].to_i > 0
                      when 'prefix'         then !fact[:prefix].empty?
                      else false
                      end
                  when 'prefix' then fact[:prefix].start_with?(value)
                  when 'id', 'pid' then fact[:id] == value
                  when 'mat'    then fact[:mat].include?(value)
                  when 'note'   then fact[:note].include?(value)
                  when 'face'   then fact[:face] == value
                  when 'dir'    then !fact[:dir].empty? && fact[:dir].start_with?(value)
                  else
                      [fact[:name], fact[:def], fact[:tag], fact[:prefix], fact[:id], fact[:flag], fact[:mat], fact[:note]].any? { |text| text.include?(value) }
                  end
            term[:neg] ? !hit : hit
        end

        def self.na_flag_payload(flag)
            type = Na__AgentOutliner::Na__ConfigStore.Na__Standards__Flag(flag['id'])
            {
                'id'      => flag['id'],
                'label'   => type ? type['label'] : flag['id'],
                'meaning' => type ? type['meaning'] : 'This flag type is no longer in the standards.',
                'by'      => flag['by'],
                'author'  => flag['author'],
                'at'      => flag['at']
            }
        end

        def self.na_status_payload(status)
            item = {}
            item['created_at'] = Time.at(status['c'].to_f).iso8601 if status['c']
            item['created_by'] = status['cb'] if status['cb']
            item['updated_at'] = Time.at(status['u'].to_f).iso8601 if status['u']
            item['updated_by'] = status['ub'] if status['ub']
            item['fields']     = status['f'] if status['f']
            item['last_tool']  = status['tool'] if status['tool']
            item['changes']    = status['n'].to_i
            item
        end

        def self.na_thread_payload(target, notes, seen)
            read_user  = seen && seen['user'] ? seen['user'] : {}
            read_agent = seen && seen['agent'] ? seen['agent'] : {}
            {
                'status'  => notes['thread']['status'],
                'entries' => notes['thread']['entries'].map do |entry|
                    item = entry.dup
                    item['images'] = Array(entry['images']).map { |image| Na__AgentOutliner::Na__ChatCache.Na__Chat__Describe(image) } if entry['images']
                    item['new_for_agent'] = true if entry['by'] == 'user' && !read_agent.key?(entry['id'])
                    item['new_for_adam']  = true if entry['by'] == 'agent' && !read_user.key?(entry['id'])
                    item
                end,
                'flag'    => notes['flag'] ? self.na_flag_payload(notes['flag']) : nil,
                'target'  => target.is_a?(Sketchup::Model) ? 'model' : target.persistent_id
            }
        end

        # One line of the threads list.
        def self.na_thread_line(target, notes, seen)
            entries  = notes['thread']['entries']
            comments = entries.select { |entry| entry['kind'] == 'comment' }
            status   = notes['thread']['status'] == 'resolved' ? 'resolved' : 'open'
            waiting  = Na__AgentOutliner::Na__Notes.Na__Notes__WaitingForAgent(target, notes, seen).length
            unread   = Na__AgentOutliner::Na__Notes.Na__Notes__UnreadByUser(notes, seen).length
            last     = entries.last
            last_comment = comments.last
            waiting_on = if waiting > 0
                             'agent'
                         elsif status == 'open' && last_comment && last_comment['by'] == 'agent'
                             'user'
                         end

            line = { 'target' => target.is_a?(Sketchup::Model) ? 'model' : target.persistent_id }
            unless target.is_a?(Sketchup::Model)
                line['name'] = Na__AgentOutliner::Na__Walker.Na__Walker__Name(target)
                line['type'] = Na__AgentOutliner::Na__Walker::NA_TYPE_NAMES[Na__AgentOutliner::Na__Walker.Na__Walker__Kind(target)]
                line['path'] = Na__AgentOutliner::Na__Walker.Na__Walker__PathSummary(Na__AgentOutliner::Na__Walker.Na__Walker__FirstPath(target))
            end
            line['status']            = status
            line['waiting_on']        = waiting_on
            line['waiting_for_agent'] = waiting
            line['unread_by_adam']    = unread
            line['comments']          = comments.length
            line['entries']           = entries.length
            line['flag']              = notes['flag']['id'] if notes['flag']
            line['last'] = {
                'by'     => last['by'],
                'author' => last['author'],
                'at'     => last['at'],
                'kind'   => last['kind'],
                'text'   => last['text'].to_s[0, NA_LAST_TEXT]
            }
            line['last']['images'] = Array(last['images']).length if last['images']
            pictures = entries.sum { |entry| Array(entry['images']).length }
            line['images'] = pictures if pictures > 0
            line['agents'] = entries.select { |entry| entry['by'] == 'agent' }.map { |entry| entry['author'].to_s }.uniq
            line
        end

        # One object in the flags list.
        def self.na_flag_line(model, entity, notes, context)
            flag = notes['flag']
            line = {
                'id'   => entity.persistent_id,
                'type' => Na__AgentOutliner::Na__Walker::NA_TYPE_NAMES[Na__AgentOutliner::Na__Walker.Na__Walker__Kind(entity)],
                'name' => Na__AgentOutliner::Na__Walker.Na__Walker__Name(entity),
                'path' => Na__AgentOutliner::Na__Walker.Na__Walker__PathSummary(Na__AgentOutliner::Na__Walker.Na__Walker__FirstPath(entity)),
                'by'     => flag['by'],
                'author' => flag['author'],
                'at'     => flag['at']
            }
            entries = notes['thread']['entries']
            unless entries.empty?
                line['thread_status']     = notes['thread']['status'] == 'resolved' ? 'resolved' : 'open'
                line['comments']          = entries.count { |entry| entry['kind'] == 'comment' }
            end
            waiting = Na__AgentOutliner::Na__Notes.Na__Notes__WaitingForAgent(entity, notes, context[:seen]).length
            line['waiting_for_agent'] = waiting if waiting > 0
            line
        end

        # An entry's time as seconds (0 when it does not read: it sorts last).
        def self.na_time_value(text)
            Time.iso8601(text.to_s).to_f
        rescue ArgumentError
            0.0
        end

        def self.na_flag_group(id, label, meaning, inbox, items, limit)
            items = items.sort_by { |item| [item['name'].to_s.downcase, item['id']] }
            { 'id' => id, 'label' => label, 'meaning' => meaning, 'in_inbox' => inbox ? true : false,
              'count' => items.length, 'objects' => items.first(limit) }
        end

        def self.na_colour_hex(layer)
            return '' unless layer.respond_to?(:color)

            colour = layer.color
            format('#%02x%02x%02x', colour.red, colour.green, colour.blue)
        rescue StandardError
            ''
        end

# endregion -------------------------------------------------------------------

    end # module Na__Payloads
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
