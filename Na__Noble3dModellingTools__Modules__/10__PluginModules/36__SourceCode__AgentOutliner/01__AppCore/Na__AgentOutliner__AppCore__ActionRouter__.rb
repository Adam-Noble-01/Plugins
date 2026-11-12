# =============================================================================
# NA AGENT OUTLINER - APP CORE - ACTION ROUTER
# =============================================================================
#
# FILE       : Na__AgentOutliner__AppCore__ActionRouter__.rb
# NAMESPACE  : Na__AgentOutliner::Na__ActionRouter
# MODULE     : Na__ActionRouter (module functions)
# AUTHOR     : Noble Architecture
# PURPOSE    : Turn each dialog request (na_ao_action(actionId, json)) into the
#              model call it names, and answer with a status line and fresh rows
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - ONE TABLE OF ACTIONS (NA_ROUTES): the page's action id, then the method
#   here that runs it. An unknown id is refused with a status, never ignored.
# - IDS, NOT OBJECTS: the page sends persistent ids (pids) or, for a row,
#   the path of ids from the root down; every request resolves them again,
#   because undo can take an object away while the page still shows it.
# - REFUSALS: an ArgumentError from the model code is a refusal Adam should
#   read ("Write something first: the comment is empty."), shown as a warning;
#   anything else is a fault, logged and shown as an error by the DialogManager.
# - Native panels and shell calls are deferred out of the callback.
#
# =============================================================================

module Na__AgentOutliner
    module Na__ActionRouter

# -----------------------------------------------------------------------------
# REGION | Routes
# -----------------------------------------------------------------------------

        # The table is REPLACED on every load, never guarded: Reload Plugin Data
        # re-runs this file, and a guarded table kept its old routes, so every
        # action added since (setFrontFaces, setTag) answered "Unknown action"
        # until SketchUp restarted (fixed 0.1.6).
        remove_const(:NA_ROUTES) if const_defined?(:NA_ROUTES, false)
        NA_ROUTES = {
            'setPref'         => :na_set_pref,
            'refresh'         => :na_refresh,
            'select'          => :na_select,
            'zoom'            => :na_zoom,
            'setHidden'       => :na_set_hidden,
            'setLocked'       => :na_set_locked,
            'setTag'          => :na_set_tag,
            'rename'          => :na_rename,
            'replaceNames'    => :na_replace_names,
            'applyPrefix'     => :na_apply_prefix,
            'stripPrefix'     => :na_strip_prefix,
            'setFrontFaces'   => :na_set_front_faces,
            'flag'            => :na_flag,
            'unflag'          => :na_unflag,
            'comment'         => :na_comment,
            'setThreadStatus' => :na_set_thread_status,
            'deleteEntry'     => :na_delete_entry,
            'getThread'       => :na_get_thread,
            'markRead'        => :na_mark_read,
            'markChangesSeen' => :na_mark_changes_seen,
            'getHistory'      => :na_get_history,
            'clearHistory'    => :na_clear_history,
            'saveStandards'   => :na_save_standards,
            'saveSettings'    => :na_save_settings,
            'reloadPlugin'    => :na_reload_plugin,
            'reloadNoble3d'   => :na_reload_noble3d,
            'openFolder'      => :na_open_folder,
            'copyText'        => :na_copy_text,
            'getLog'          => :na_get_log,
            'getState'        => :na_get_state,
            'getChats'        => :na_get_chats,
            'chatUpload'      => :na_chat_upload,
            'openChatImage'   => :na_open_chat_image,
            'chatPick'        => :na_chat_pick,
            'chatPickCancel'  => :na_chat_pick_cancel
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dispatch
# -----------------------------------------------------------------------------

        # FUNCTION | Run One Dialog Action
        # ------------------------------------------------------------
        def self.Na__Action__Dispatch(action_id, payload)
            route = NA_ROUTES[action_id.to_s]
            unless route
                Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushStatus("Unknown action '#{action_id}'. Close and reopen the outliner after a reload.", 'error')
                return false
            end

            self.send(route, payload.is_a?(Hash) ? payload : {})
        rescue ArgumentError => error
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushStatus(error.message, 'warn')
            false
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Settings, Refresh, Reload
# -----------------------------------------------------------------------------

        def self.na_set_pref(payload)
            Na__AgentOutliner::Na__ConfigStore.Na__UserConfig__SetUi(payload['key'], payload['value'])
        end

        def self.na_refresh(_payload)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushState
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushSnapshot(refresh: true)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushTags
            self.na_status('Read the model again.', 'success')
        end

        def self.na_get_state(_payload)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushState
        end

        def self.na_get_log(_payload)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Send('log', Na__AgentOutliner::Na__DebugTools.Na__Debug__Lines)
        end

        def self.na_save_standards(payload)
            saved, issues = Na__AgentOutliner::Na__ConfigStore.Na__Standards__Save(payload['standards'])
            unless issues.empty?
                Na__AgentOutliner::Na__DialogManager.Na__Dialog__Send('standardsIssues', { 'issues' => issues })
                return self.na_status("Not saved: #{issues.first}#{issues.length > 1 ? " (and #{issues.length - 1} more)" : ''}", 'warn')
            end

            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushState
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushSnapshot
            self.na_status("Naming standards saved: #{saved['prefixes'].length} prefixes and #{saved['flags'].length} flag types.", 'success')
        end

        def self.na_save_settings(payload)
            was_enabled = Na__AgentOutliner::Na__Tracker.Na__Tracker__Enabled?
            Na__AgentOutliner::Na__ConfigStore.Na__Config__SaveSettings(payload['settings'])
            now_enabled = Na__AgentOutliner::Na__Tracker.Na__Tracker__Enabled?
            if now_enabled && !was_enabled
                model = self.na_model
                Na__AgentOutliner::Na__Observers.Na__Observers__Attach(model) if model
            end
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushState
            message = payload['message'].to_s.strip                                     # <-- A toolbar switch says what it switched (0.1.15)
            self.na_status(message.empty? ? 'Settings saved.' : message[0, 200], 'success')
        end

        def self.na_reload_plugin(_payload)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Deferred do
                Na__AgentOutliner::Na__DialogManager.Na__Dialog__ReloadPlugin
            end
            true
        end

        def self.na_reload_noble3d(_payload)
            unless defined?(::Na__Noble3dModellingTools) && ::Na__Noble3dModellingTools.respond_to?(:Na__Noble3dModellingTools__ReloadPluginData)
                return self.na_status('Na Noble3d Modelling Tools is not loaded, so only this tool can reload.', 'warn')
            end

            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Deferred do
                result = ::Na__Noble3dModellingTools.Na__Noble3dModellingTools__ReloadPluginData
                message = result.is_a?(Hash) ? result[:message] || result['message'] : 'Noble 3D Tools reloaded.'
                Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushStatus(message.to_s, 'success')
            end
            true
        end

        def self.na_open_folder(payload)
            paths = {
                'history'   => Na__AgentOutliner::Na__HistoryStore.Na__History__Folder,
                'chat'      => Na__AgentOutliner::Na__ChatCache.Na__Chat__Folder,
                'agent_chat' => Na__AgentOutliner::Na__ChatCache.Na__Chat__AgentFolder,
                'standards' => Na__AgentOutliner::NA_APPDATA_ROOT,
                'user'      => Na__AgentOutliner::NA_LOCAL_ROOT,
                'module'    => Na__AgentOutliner::NA_MODULE_ROOT
            }
            path = paths[payload['which'].to_s]
            raise ArgumentError, 'That folder is not one this tool knows.' unless path

            FileUtils.mkdir_p(path)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Deferred do
                UI.openURL("file:///#{path.tr('\\', '/').gsub(' ', '%20')}")
            end
            true
        end

        # Windows clipboard through clip.exe, for when the page's own copy is
        # refused. UTF-16LE with a byte order mark, so accents and symbols survive.
        def self.na_copy_text(payload)
            text = payload['text'].to_s
            raise ArgumentError, 'There is nothing to copy.' if text.empty?

            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Deferred do
                if RUBY_PLATFORM =~ /mswin|mingw|cygwin/
                    IO.popen(['clip'], 'wb') { |pipe| pipe.write("\xFF\xFE".b + text.encode('UTF-16LE').b) }
                else
                    IO.popen(['pbcopy'], 'w') { |pipe| pipe.write(text) }
                end
                message = payload['message'].to_s.strip.empty? ? "Copied #{text.lines.length} lines for the agent." : payload['message'].to_s
                Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushStatus(message, 'success')
                Na__AgentOutliner::Na__DialogManager.Na__Dialog__Send('toast', { 'message' => message, 'level' => 'success' })   # <-- 0.1.13: the page's toast
            end
            true
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Selecting, Hiding, Locking
# -----------------------------------------------------------------------------

        def self.na_select(payload)
            model = self.na_model!
            mode  = payload['mode'].to_s
            mode  = Na__AgentOutliner::Na__ConfigStore.Na__Config__Setting('selection', 'mode').to_s if mode.empty?
            result = Na__AgentOutliner::Na__EntityActions.Na__Actions__Select(model, self.na_paths(payload), mode: mode, zoom: payload['zoom'] == true)
            self.na_status(result['note'], 'info') if result['note']
            result
        end

        def self.na_zoom(payload)
            Na__AgentOutliner::Na__EntityActions.Na__Actions__Zoom(self.na_model!, self.na_paths(payload))
        end

        def self.na_set_hidden(payload)
            model = self.na_model!
            entities = self.na_entities(model, payload)
            count = Na__AgentOutliner::Na__EntityActions.Na__Actions__SetHidden(model, entities, payload['hidden'] == true)
            self.na_after_change(model, entities, count.zero? ? nil : "#{payload['hidden'] == true ? 'Hid' : 'Showed'} #{self.na_count(count)}.")
        end

        def self.na_set_locked(payload)
            model = self.na_model!
            entities = self.na_entities(model, payload)
            count = Na__AgentOutliner::Na__EntityActions.Na__Actions__SetLocked(model, entities, payload['locked'] == true)
            self.na_after_change(model, entities, count.zero? ? 'Nothing to change: images and section planes do not lock.' : "#{payload['locked'] == true ? 'Locked' : 'Unlocked'} #{self.na_count(count)}.")
        end

        # The Tag picker: every chosen object on one tag (create: a new tag), one undo step.
        def self.na_set_tag(payload)
            model = self.na_model!
            entities = self.na_entities(model, payload)
            result = Na__AgentOutliner::Na__EntityActions.Na__Actions__SetTag(model, entities, payload['tag'], create: payload['create'] == true)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushTags(model) if result['created']
            where = result['tag'].to_s.empty? ? 'Untagged' : result['tag']
            message = if result['count'].zero?
                          "Already on #{where}: nothing changed."
                      else
                          "#{result['created'] ? 'Made tag ' + where + ' and put ' : 'Put '}#{self.na_count(result['count'])} on #{where}."
                      end
            self.na_after_change(model, entities, message)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Names
# -----------------------------------------------------------------------------

        def self.na_rename(payload)
            model = self.na_model!
            entities = self.na_entities(model, payload)
            result = Na__AgentOutliner::Na__Naming.Na__Naming__Rename(model, entities, payload['name'])
            self.na_after_rename(model, entities, result, 'Renamed')
        end

        def self.na_replace_names(payload)
            model = self.na_model!
            entities = self.na_entities(model, payload)
            result = Na__AgentOutliner::Na__Naming.Na__Naming__Replace(model, entities, payload['find'], payload['replace'], use_pattern: payload['pattern'] == true)
            self.na_after_rename(model, entities, result, 'Renamed')
        end

        def self.na_apply_prefix(payload)
            model = self.na_model!
            entities = self.na_entities(model, payload)
            entry = Na__AgentOutliner::Na__ConfigStore.Na__Standards__Prefix(payload['prefix'])
            result = Na__AgentOutliner::Na__Naming.Na__Naming__Apply(model, entities, entry)
            self.na_after_rename(model, entities, result, "Named #{entry ? entry['label'] : ''}:")
        end

        # Which way the model's Front faces in the real world (Adam's orientation, 11-Nov-2026).
        def self.na_set_front_faces(payload)
            model = self.na_model!
            value = Na__AgentOutliner::Na__Naming.Na__Naming__SetFrontFaces(model, payload['cardinal'])
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushSnapshot
            self.na_status(value.empty? ? 'Orientation cleared: names use the model faces only.' : "Front faces #{value}: Quick Name faces now add the cardinal (Front__#{value}).", 'success')
        end

        def self.na_strip_prefix(payload)
            model = self.na_model!
            entities = self.na_entities(model, payload)
            result = Na__AgentOutliner::Na__Naming.Na__Naming__Strip(model, entities)
            self.na_after_rename(model, entities, result, 'Took the prefix off')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Flags and Comments
# -----------------------------------------------------------------------------

        def self.na_flag(payload)
            model = self.na_model!
            entities = self.na_entities(model, payload)
            type = Na__AgentOutliner::Na__ConfigStore.Na__Standards__Flag(payload['flag'])
            Na__AgentOutliner::Na__Notes.Na__Notes__SetFlag(model, entities, payload['flag'], by: 'user', author: Na__AgentOutliner.Na__AgentOutliner__UserName,
                                                          operation_name: "Agent Outliner: Flag #{type ? type['label'] : ''}".strip, text: payload['text'])
            flagged = "Flagged #{self.na_count(entities.length)} #{type ? type['label'] : ''}."
            return self.na_after_change(model, entities, flagged) unless type && type['inbox']

            sent, level = self.na_sent(model)                                           # <-- 0.1.9: an inbox flag is sent like a comment
            self.na_after_change(model, entities, "#{flagged} #{sent}")
            self.na_status("#{flagged} #{sent}", level) if level == 'warn'
        end

        def self.na_unflag(payload)
            model = self.na_model!
            entities = self.na_entities(model, payload)
            cleared = Na__AgentOutliner::Na__Notes.Na__Notes__ClearFlag(model, entities, by: 'user', author: Na__AgentOutliner.Na__AgentOutliner__UserName,
                                                                      operation_name: 'Agent Outliner: Clear Flag')
            self.na_after_change(model, entities, cleared.empty? ? 'No flag to clear.' : "Cleared #{cleared.length} flag#{cleared.length == 1 ? '' : 's'}.")
        end

        def self.na_comment(payload)
            model   = self.na_model!
            targets = self.na_targets(model, payload)
            images  = Na__AgentOutliner::Na__ChatCache.Na__Chat__Attachments(payload['images'])
            effort  = Na__AgentOutliner::Na__Notes.Na__Notes__Effort(payload['effort'])
            Na__AgentOutliner::Na__Notes.Na__Notes__Comment(model, targets, payload['text'], by: 'user', author: Na__AgentOutliner.Na__AgentOutliner__UserName,
                                                          operation_name: 'Agent Outliner: Comment', images: images, effort: effort)
            self.na_after_notes(model, targets)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Send('chats', Na__AgentOutliner::Na__Payloads.Na__Payload__ChatList(model)) if payload['chat'] == true
            sent, level = self.na_sent(model, effort)
            self.na_status(targets.length == 1 ? sent : "On #{targets.length} objects. #{sent}", level)
        end

        def self.na_set_thread_status(payload)
            model   = self.na_model!
            targets = self.na_targets(model, payload)
            status  = payload['status'].to_s
            Na__AgentOutliner::Na__Notes.Na__Notes__SetStatus(model, targets, status, by: 'user', author: Na__AgentOutliner.Na__AgentOutliner__UserName,
                                                            operation_name: status == 'resolved' ? 'Agent Outliner: Resolve' : 'Agent Outliner: Reopen',
                                                            text: payload['text'])
            self.na_after_notes(model, targets)
            self.na_status(status == 'resolved' ? 'Resolved.' : 'Reopened.', 'success')
        end

        def self.na_delete_entry(payload)
            model  = self.na_model!
            target = self.na_targets(model, payload).first
            Na__AgentOutliner::Na__Notes.Na__Notes__DeleteEntry(model, target, payload['entry'], operation_name: 'Agent Outliner: Delete Comment')
            self.na_after_notes(model, [target])
            self.na_status('Comment deleted (Ctrl+Z brings it back).', 'success')
        end

        # The Chat tab's list (0.1.6).
        def self.na_get_chats(_payload)
            model = self.na_model!
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Send('chats', Na__AgentOutliner::Na__Payloads.Na__Payload__ChatList(model))
        end

        # One piece of a pasted picture; the last piece writes it to the chat
        # folder. The answer always goes back on 'chatUpload', failures too, so
        # the composer can mark that one picture.
        def self.na_chat_upload(payload)
            result = Na__AgentOutliner::Na__ChatCache.Na__Chat__UploadPart(payload)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Send('chatUpload', result) if result['done']
            true
        rescue ArgumentError => error
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Send('chatUpload', { 'upload' => payload['upload'].to_s, 'done' => true, 'error' => error.message })
            false
        end

        # The composer's pick button (0.1.8): the next object clicked in the
        # viewport goes in the message. A refusal is answered on 'chatPicked' too,
        # so the button never stays pressed.
        def self.na_chat_pick(_payload)
            model = self.na_model!
            Na__AgentOutliner::Na__ChatPick.Na__Pick__Start(model)
        rescue ArgumentError => error
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Send('chatPicked', { 'items' => [], 'done' => true, 'cancelled' => true, 'error' => error.message })
            false
        end

        def self.na_chat_pick_cancel(_payload)
            model = self.na_model
            Na__AgentOutliner::Na__ChatPick.Na__Pick__Stop(model) if model
            true
        end

        # A chat picture in Windows' own viewer.
        def self.na_open_chat_image(payload)
            path = Na__AgentOutliner::Na__ChatCache.Na__Chat__Path(payload['file'])
            raise ArgumentError, 'That picture is not on this PC.' unless File.file?(path)

            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Deferred do
                UI.openURL("file:///#{path.tr('\\', '/').gsub(' ', '%20')}")
            end
            true
        end

        def self.na_get_thread(payload)
            model  = self.na_model!
            target = payload['model'] == true ? model : self.na_entities(model, payload).first
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushThread(model, target)
        end

        def self.na_mark_read(payload)
            model = self.na_model!
            marked = Na__AgentOutliner::Na__Tracker.Na__Tracker__MarkRead(model, 'user', payload['ids'])
            pids = Array(payload['pids']).map(&:to_i).select(&:positive?)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushRows(model, pids) if marked > 0 && !pids.empty?
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__ModelThreadChanged(model) if marked > 0 && payload['model'] == true
            marked
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Change History
# -----------------------------------------------------------------------------

        def self.na_mark_changes_seen(_payload)
            model = self.na_model!
            seq = Na__AgentOutliner::Na__Tracker.Na__Tracker__MarkChangesSeen(model, 'user')
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Send('seen', { 'user_seq' => seq })
            self.na_status('Every change so far is marked as seen.', 'success')
        end

        def self.na_get_history(payload)
            model = self.na_model!
            pid = payload['pid'].to_i
            events = Na__AgentOutliner::Na__Tracker.Na__Tracker__Events(model, limit: 4000).select { |event| event['pid'] == pid }
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Send('history', { 'pid' => pid, 'events' => events.last(200) })
        end

        def self.na_clear_history(_payload)
            model = self.na_model!
            Na__AgentOutliner::Na__Tracker.Na__Tracker__ClearHistory(model)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushSnapshot
            self.na_status('Change history cleared for this model. Comments and flags are untouched.', 'success')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        def self.na_model
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__Model
        end

        def self.na_model!
            model = self.na_model
            raise ArgumentError, 'No model is open.' unless model

            model
        end

        def self.na_paths(payload)
            paths = Array(payload['paths']).map { |path| Array(path).map(&:to_i) }.reject(&:empty?)
            raise ArgumentError, 'Choose a row first.' if paths.empty?

            paths
        end

        def self.na_entities(model, payload)
            pids = Array(payload['pids']).map(&:to_i).select(&:positive?).uniq
            raise ArgumentError, 'Choose a row first.' if pids.empty?

            entities = pids.map { |pid| Na__AgentOutliner::Na__EntityActions.Na__Actions__FindById(model, pid) }.compact
            raise ArgumentError, 'Those rows are out of date: press Refresh.' if entities.empty?

            entities
        end

        # Objects, or the model itself (payload model: true) for its own thread.
        def self.na_targets(model, payload)
            return [model] if payload['model'] == true

            self.na_entities(model, payload)
        end

        def self.na_after_change(model, entities, message)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushRows(model, entities.select(&:valid?).map(&:persistent_id))
            self.na_status(message, 'success') if message
            true
        end

        def self.na_after_rename(model, entities, result, verb)
            renamed = result['renamed'].length
            message = if renamed.zero? && result['refused'].empty?
                          'Already named so: nothing changed.'
                      elsif renamed.zero?
                          result['refused'].first
                      else
                          names = result['renamed'].first(3).map { |item| item['to'] }.join(', ')
                          more  = renamed > 3 ? " and #{renamed - 3} more" : ''
                          "#{verb} #{names}#{more}.#{result['refused'].empty? ? '' : " #{result['refused'].length} could not be named."}"
                      end
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushRows(model, entities.select(&:valid?).map(&:persistent_id))
            self.na_status(message, renamed.zero? && !result['refused'].empty? ? 'warn' : 'success')
        end

        def self.na_after_notes(model, targets)
            objects = targets.reject { |target| target.is_a?(Sketchup::Model) }
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushRows(model, objects.map(&:persistent_id)) unless objects.empty?
            targets.first(1).each { |target| Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushThread(model, target) }
        end

        def self.na_status(message, level)
            Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushStatus(message, level)
            true
        end

        # 0.1.9: after Adam sends (a comment, or a flag that waits for an
        # agent), say what will happen to it, and rewrite the inbox signal an
        # idle agent's watcher polls. Returns [status text, level]. Agents see
        # it on their next SketchUp call only through a running MCP of 1.0.28
        # or newer (its waiting notice); an older one shows it only when an
        # agent reads its inbox.
        # 0.1.10: say WHO will see it. An agent that called SketchUp in the last
        # NA_WORKING_S sees it on its next call; an idle session sees it now
        # only if it runs the inbox watcher (its heartbeat file). With neither,
        # nobody will, and the line says so (13:58 on Telfer: "Sent" while no
        # agent was working or watching).
        NA_WORKING_S = 180 unless defined?(NA_WORKING_S)
        NA_EFFORT_NAMES = { 'low' => 'Low', 'medium' => 'Medium', 'high' => 'High', 'xhigh' => 'Extra High', 'max' => 'Max' }.freeze unless defined?(NA_EFFORT_NAMES)

        # 0.1.14: with an effort, also say whether a dispatcher will apply it
        # (a Claude session can't change its own effort; a dispatcher session
        # sets it for each agent it wakes).
        def self.na_sent(model, effort = nil)
            notice = Na__AgentOutliner::Na__McpOperations.Na__AgentOutliner__McpNotice(model)
            Na__AgentOutliner::Na__HistoryStore.Na__History__WriteInbox(model, notice) if notice
            text, level = self.na_sent_line(model)
            return [text, level] unless effort

            name = NA_EFFORT_NAMES[effort] || effort
            if Na__AgentOutliner::Na__HistoryStore.Na__History__Dispatchers.empty?
                return ["#{text} #{name} effort is not applied: no dispatcher is running (ask Claude to run the Outliner dispatcher).", 'warn']
            end
            ["#{text} The dispatcher sets #{name} effort for each agent it wakes.", level]
        end

        def self.na_sent_line(model)
            mcp = Na__AgentOutliner::Na__ActorDetect.Na__Actor__McpStatus
            unless mcp['running']
                return ['Saved, but the Na SketchUp MCP is not running in this window: no agent will see it until it starts.', 'warn']
            end

            version = mcp['version'].to_s.split('.').map(&:to_i)
            if !version.empty? && (version <=> [1, 0, 28]) < 0
                return ["Saved. This window's Na SketchUp MCP (#{mcp['version']}) shows it only when an agent reads its inbox: " \
                        'Extensions > Na SketchUp MCP > Reload Plugin Data, and agents see it on their next SketchUp call.', 'warn']
            end

            last     = mcp['last'].is_a?(Hash) && !mcp['last']['time'].to_s.empty? ? mcp['last'] : nil
            age      = last ? Na__AgentOutliner::Na__ActorDetect.Na__Actor__SecondsAgo(last['time']) : nil
            watchers = Na__AgentOutliner::Na__HistoryStore.Na__History__Watchers(model)
            seen_by  = []
            seen_by << "the agent working here sees it on its next SketchUp call (last call #{last['time']})" if age && age <= NA_WORKING_S
            unless watchers.empty?
                names = watchers.map { |item| item['who'] }.reject(&:empty?).uniq
                named = names.empty? ? '' : " (#{names.first(2).join(', ')}#{names.length > 2 ? '...' : ''})"
                seen_by << "#{watchers.length} waiting agent#{watchers.length == 1 ? '' : 's'}#{named} #{watchers.length == 1 ? 'wakes' : 'wake'} now"
            end
            return ["Sent: #{seen_by.join('; ')}.", 'success'] unless seen_by.empty?

            when_last = last ? " (last SketchUp call #{last['time']})" : ''
            ["Saved, but no agent is working here#{when_last} or watching this model, so none will see it until one calls SketchUp. " \
             'Ask in Claude, or have agents leave the inbox watcher running.', 'warn']
        end

        def self.na_count(count)
            "#{count} object#{count == 1 ? '' : 's'}"
        end

# endregion -------------------------------------------------------------------

    end # module Na__ActionRouter
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
