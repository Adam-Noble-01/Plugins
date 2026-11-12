# =============================================================================
# NA AGENT OUTLINER - APP CORE - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__AgentOutliner__AppCore__DialogManager__.rb
# NAMESPACE  : Na__AgentOutliner::Na__DialogManager
# MODULE     : Na__DialogManager (module functions)
# AUTHOR     : Noble Architecture
# PURPOSE    : The HtmlDialog's life (open, close, reload), the two JS -> Ruby
#              callbacks, and every Ruby -> JS push through one entry point:
#                window.Na__AgentOutliner__Receive(channel, payload)
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - CALLBACKS (JS -> Ruby):
#     na_ao_ready()                  the page has loaded: send it everything
#     na_ao_action(actionId, json)   every other request (Na__ActionRouter)
# - CHANNELS (Ruby -> JS):
#     state      settings, naming standards, version, the MCP's status
#     snapshot   the whole tree for the model shown (sent in parts when big)
#     delta      rows, containers and change events after an operation
#     selection  SketchUp's selection and the open group, as ids
#     tags       which tags (with their folders) are shown
#     thread     one object's (or the model's) full comment thread
#     history    one object's change history
#     status     a line for the status bar
#     log        the Technical Log
#     toast      a short note that fades away (0.1.13: a copy made through Ruby)
#     icons      the dialog's SVG icons as text, once a page (0.1.15)
# - SELECTION BACKSTOP (0.1.15): while the page is up, a 0.5 s look sends
#   the selection when the observers missed a change (they can go quiet).
# - set_file, not set_html: the page sits beside its CSS and JS, and the
#   shared Noble logo loads by a relative path.
# - A BIG TREE goes in parts: JSON over engine.chunk_chars characters is sent
#   as numbered pieces the page joins before parsing (one huge execute_script
#   string is slow, and very large ones have failed in SketchUp).
# - Never close one dialog and build another in the same pass: a reload
#   closes on one timer and reopens on a later one.
#
# =============================================================================

module Na__AgentOutliner
    module Na__DialogManager

# -----------------------------------------------------------------------------
# REGION | State
# -----------------------------------------------------------------------------

        @na_dialog          = nil   unless defined?(@na_dialog)
        @na_model           = nil   unless defined?(@na_model)                          # <-- The model the page is showing
        @na_pending_notice  = nil   unless defined?(@na_pending_notice)
        @na_selection_timer = nil   unless defined?(@na_selection_timer)
        @na_tags_timer      = nil   unless defined?(@na_tags_timer)
        @na_page_ready      = false unless defined?(@na_page_ready)
        @na_echo_guard      = false unless defined?(@na_echo_guard)
        @na_selection_watch = nil   unless defined?(@na_selection_watch)                # <-- The backstop timer (0.1.15)
        @na_selection_sent  = nil   unless defined?(@na_selection_sent)                 # <-- The selection the page last heard of

        NA_SELECTION_WATCH_S = 0.5 unless defined?(NA_SELECTION_WATCH_S)                 # <-- How often the backstop looks (0.1.15)
        NA_ICON_PREFIX       = 'Icon__AgentOutliner__'.freeze unless defined?(NA_ICON_PREFIX)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Open the Dialog (or bring the open one to the front)
        # ------------------------------------------------------------
        def self.Na__Dialog__Show
            return @na_dialog.bring_to_front if self.Na__Dialog__Visible?

            model = Sketchup.active_model
            Na__AgentOutliner::Na__Observers.Na__Observers__Attach(model) if model
            @na_model      = model
            @na_page_ready = false

            dialog = UI::HtmlDialog.new(self.na_options)
            self.na_bind_callbacks(dialog)
            dialog.set_file(Na__AgentOutliner::NA_HTML_FILE)
            dialog.set_on_closed do
                Na__AgentOutliner::Na__DialogManager.na_on_closed(dialog)
            end
            @na_dialog = dialog
            dialog.show
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Close the Dialog
        # ------------------------------------------------------------
        def self.Na__Dialog__Close
            @na_dialog.close if self.Na__Dialog__Visible?
            @na_dialog = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Dialog Open?
        # ------------------------------------------------------------
        def self.Na__Dialog__Visible?
            @na_dialog && @na_dialog.visible? ? true : false
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Reload Plugin Data, Then Reopen on a Later Tick
        # ------------------------------------------------------------
        # The callback that asked returns before its own dialog closes, and the
        # new dialog is built on a later timer than the close.
        def self.Na__Dialog__ReloadPlugin
            result = Na__AgentOutliner::Na__PluginReloader.Na__Reload__Run
            @na_pending_notice = { 'message' => result['statusMessage'], 'level' => result['isSuccess'] ? 'success' : 'error' }
            was_open = self.Na__Dialog__Visible?
            UI.start_timer(0.05, false) { Na__AgentOutliner::Na__DialogManager.Na__Dialog__Close }
            UI.start_timer(0.30, false) { Na__AgentOutliner::Na__DialogManager.Na__Dialog__Show } if was_open
            result
        end
        # ---------------------------------------------------------------

        # FUNCTION | Close and Reopen if Open (after the Noble 3D Tools reload)
        # ------------------------------------------------------------
        def self.Na__Dialog__ReopenIfVisible
            return false unless self.Na__Dialog__Visible?

            UI.start_timer(0.05, false) { Na__AgentOutliner::Na__DialogManager.Na__Dialog__Close }
            UI.start_timer(0.30, false) { Na__AgentOutliner::Na__DialogManager.Na__Dialog__Show }
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Run a Block Once, Outside the Current Callback
        # ------------------------------------------------------------
        # Native panels and shell calls inside a dialog callback can be lost
        # behind the dialog on Windows; a non-repeating timer can fire again
        # while a modal is open, so the block is guarded to run once.
        def self.Na__Dialog__Deferred(&block)
            fired = false
            UI.start_timer(0, false) do
                next if fired

                fired = true
                begin
                    block.call
                rescue StandardError => error
                    Na__AgentOutliner::Na__DebugTools.Na__Debug__Error('A deferred dialog step failed.', error)
                    Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushStatus("That did not work: #{error.message}", 'error')
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Model the Page Shows (the active one when it was opened)
        # ------------------------------------------------------------
        def self.Na__Dialog__Model
            model = @na_model
            model = Sketchup.active_model unless model && self.na_alive?(model)
            model
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Ruby -> JS
# -----------------------------------------------------------------------------

        # FUNCTION | Send One Channel's Payload (false when the dialog is shut)
        # ------------------------------------------------------------
        def self.Na__Dialog__Send(channel, payload)
            return false unless self.Na__Dialog__Visible?

            json = JSON.generate(payload)
            limit = Na__AgentOutliner::Na__ConfigStore.Na__Config__Engine('chunk_chars', 900_000).to_i
            if json.length > limit && limit > 0
                pieces = (0...json.length).step(limit).map { |start| json[start, limit] }      # <-- Slices, not a regexp: Onigmo refuses repeat counts over 100,000
                pieces.each_with_index do |piece, index|
                    @na_dialog.execute_script("window.Na__AgentOutliner__ReceivePart && window.Na__AgentOutliner__ReceivePart(" \
                                              "#{JSON.generate(channel.to_s)}, #{index}, #{pieces.length}, #{JSON.generate(piece)});")
                end
            else
                @na_dialog.execute_script("window.Na__AgentOutliner__Receive && window.Na__AgentOutliner__Receive(" \
                                          "#{JSON.generate(channel.to_s)}, #{json});")
            end
            true
        rescue StandardError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Error("Sending '#{channel}' to the dialog failed.", error)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Line on the Status Bar
        # ------------------------------------------------------------
        def self.Na__Dialog__PushStatus(message, level = 'info')
            self.Na__Dialog__Send('status', { 'message' => message.to_s, 'level' => level.to_s })
        end
        # ---------------------------------------------------------------

        # FUNCTION | Settings, Standards, Version, MCP Status
        # ------------------------------------------------------------
        def self.Na__Dialog__PushState
            model = self.Na__Dialog__Model
            self.Na__Dialog__Send('state', {
                'version'   => Na__AgentOutliner.Na__AgentOutliner__Version,
                'settings'  => Na__AgentOutliner::Na__ConfigStore.Na__Config__Settings,
                'standards' => Na__AgentOutliner::Na__ConfigStore.Na__Standards__All,
                'ui'        => Na__AgentOutliner::Na__ConfigStore.Na__UserConfig__Ui,
                'user_name' => Na__AgentOutliner.Na__AgentOutliner__UserName,
                'mcp'       => Na__AgentOutliner::Na__ActorDetect.Na__Actor__McpStatus,
                'tracking'  => model ? Na__AgentOutliner::Na__Tracker.Na__Tracker__Info(model) : nil,
                'chat'      => { 'url' => Na__AgentOutliner::Na__ChatCache.Na__Chat__FolderUrl, 'folder' => Na__AgentOutliner::Na__ChatCache.Na__Chat__Folder,
                                 'agent_url' => Na__AgentOutliner::Na__ChatCache.Na__Chat__AgentFolderUrl, 'agent_folder' => Na__AgentOutliner::Na__ChatCache.Na__Chat__AgentFolder },
                'paths'     => {
                    'chat'      => Na__AgentOutliner::Na__ChatCache.Na__Chat__Folder,
                    'agent_chat' => Na__AgentOutliner::Na__ChatCache.Na__Chat__AgentFolder,
                    'standards' => Na__AgentOutliner::Na__ConfigStore.Na__Config__StandardsPath,
                    'user'      => Na__AgentOutliner::Na__ConfigStore.Na__Config__UserConfigPath,
                    'history'   => Na__AgentOutliner::Na__HistoryStore.Na__History__Folder,
                    'module'    => Na__AgentOutliner::NA_MODULE_ROOT
                },
                'sketchup'  => Sketchup.version.to_s
            })
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Whole Tree of the Model Shown
        # ------------------------------------------------------------
        def self.Na__Dialog__PushSnapshot(refresh: false)
            model = self.Na__Dialog__Model
            return self.Na__Dialog__Send('snapshot', { 'model' => nil }) unless model

            Na__AgentOutliner::Na__Observers.Na__Observers__Attach(model)
            Na__AgentOutliner::Na__Tracker.Na__Tracker__Refresh(model, scan: true) if refresh
            started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            payload = Na__AgentOutliner::Na__Payloads.Na__Payload__Snapshot(model)
            payload['build_ms'] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0).round
            self.Na__Dialog__Send('snapshot', payload)
            self.Na__Dialog__PushSelection(model)
        end
        # ---------------------------------------------------------------

        # FUNCTION | SketchUp's Selection and Open Group, as Persistent Ids
        # ------------------------------------------------------------
        def self.Na__Dialog__PushSelection(model = nil)
            model ||= self.Na__Dialog__Model
            return false unless model && self.na_showing?(model)

            selected = model.selection.to_a.first(2000).select { |entity| Na__AgentOutliner::Na__Walker.Na__Walker__Kind(entity) }
            @na_selection_sent = self.na_selection_signature(model)
            self.Na__Dialog__Send('selection', {
                'active' => Array(model.active_path).map(&:persistent_id),
                'ids'    => selected.map(&:persistent_id),
                'count'  => model.selection.length
            })
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Dialog's Icons, Once a Page (0.1.15)
        # ------------------------------------------------------------
        # The SVGs in UiIcons__DialogIcons__AgentOutliner, keyed by the part of
        # the name between Icon__AgentOutliner__ and the closing __ (Flag,
        # QuickName ...). Sent as text so the page can put them inline, where
        # CSS colours them: a set_file page cannot reach a file's markup any
        # other way. A missing folder costs the pictures only: every button
        # keeps its name and its tooltip.
        def self.Na__Dialog__PushIcons
            self.Na__Dialog__Send('icons', self.na_icon_set)
        end

        def self.na_icon_set
            folder = File.join(Na__AgentOutliner::NA_MODULE_ROOT, 'UiIcons__DialogIcons__AgentOutliner')
            icons = {}
            Dir.glob(File.join(folder, "#{NA_ICON_PREFIX}*.svg")).sort.each do |path|
                name = File.basename(path, '.svg').sub(NA_ICON_PREFIX, '').sub(/_+\z/, '')
                text = File.read(path, encoding: 'UTF-8')
                icons[name] = text if !name.empty? && text.include?('<svg')
            end
            icons
        rescue StandardError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("The dialog icons could not be read: #{error.message}")
            {}
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Selection Backstop: Start and Stop (0.1.15)
        # ------------------------------------------------------------
        # SketchUp's selection observers can go quiet (api-issue-tracker #603,
        # #1116), and then a click in the model never reached the page, so the
        # table could not follow it. While the page is up, a cheap look every
        # NA_SELECTION_WATCH_S compares the selection's count, its first few
        # entities and the open group with what the page last heard, and sends
        # the selection only when they differ. With the observers working it
        # never sends anything: they got there first.
        def self.Na__Dialog__StartSelectionWatch
            self.Na__Dialog__StopSelectionWatch
            @na_selection_watch = UI.start_timer(NA_SELECTION_WATCH_S, true) do
                Na__AgentOutliner::Na__DialogManager.na_check_selection
            end
            true
        end

        def self.Na__Dialog__StopSelectionWatch
            UI.stop_timer(@na_selection_watch) if @na_selection_watch
            @na_selection_watch = nil
        rescue StandardError
            @na_selection_watch = nil
        end

        def self.na_check_selection
            return self.Na__Dialog__StopSelectionWatch unless self.Na__Dialog__Visible?
            return unless @na_page_ready && @na_selection_timer.nil?

            model = self.Na__Dialog__Model
            return unless model && self.na_showing?(model)
            return if self.na_selection_signature(model) == @na_selection_sent

            self.Na__Dialog__PushSelection(model)
        rescue StandardError => error
            self.Na__Dialog__StopSelectionWatch                                          # <-- A backstop that fails stops, rather than logging twice a second
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("The selection backstop stopped: #{error.message}")
        end

        # The count, the first 16 entities and the open group: enough to see a
        # click in the model, without walking a selection of 100,000 edges.
        # (Selection#first takes no count, so the loop stops itself.)
        def self.na_selection_signature(model)
            selection = model.selection
            ids = []
            selection.each do |entity|
                ids << entity.entityID
                break if ids.length >= 16
            end
            [selection.length, ids, Array(model.active_path).map(&:entityID)]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Tags Are Shown
        # ------------------------------------------------------------
        def self.Na__Dialog__PushTags(model = nil)
            model ||= self.Na__Dialog__Model
            return false unless model && self.na_showing?(model)

            self.Na__Dialog__Send('tags', Na__AgentOutliner::Na__Payloads.Na__Payload__Tags(model))
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Thread in Full (an object's, or the model's with target 'model')
        # ------------------------------------------------------------
        def self.Na__Dialog__PushThread(model, target)
            return false unless model && self.na_showing?(model)

            self.Na__Dialog__Send('thread', Na__AgentOutliner::Na__Payloads.Na__Payload__Thread(model, target))
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Model's Own Thread Changed (an agent wrote in it)
        # ------------------------------------------------------------
        def self.Na__Dialog__ModelThreadChanged(model)
            self.Na__Dialog__PushThread(model, model)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Fresh Rows for Some Objects (after a comment, flag or rename)
        # ------------------------------------------------------------
        def self.Na__Dialog__PushRows(model, pids, containers = [], events = [])
            return false unless model && self.na_showing?(model)

            delta = Na__AgentOutliner::Na__Payloads.Na__Payload__Delta(model, pids, containers, events)
            self.Na__Dialog__Send('delta', delta)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | News From the Tracker and the Observers
# -----------------------------------------------------------------------------

        # FUNCTION | The Tracker Finished a Pass (send what changed)
        # ------------------------------------------------------------
        def self.Na__Dialog__TrackerUpdated(model, pids, records, containers)
            return false unless self.na_showing?(model)

            unless pids.empty? && records.empty? && containers.empty?
                self.Na__Dialog__PushRows(model, pids, containers, records)
            end
            self.Na__Dialog__PushSelection(model)                                       # <-- Selection observers can go quiet: re-sync after every operation
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Tracker's First Look at a Model Is Done
        # ------------------------------------------------------------
        def self.Na__Dialog__TrackerReady(model)
            return false unless @na_page_ready && self.na_showing?(model)

            self.Na__Dialog__PushSnapshot
        end
        # ---------------------------------------------------------------

        # FUNCTION | SketchUp's Selection Changed (one push per burst)
        # ------------------------------------------------------------
        def self.Na__Dialog__SelectionChanged(model)
            return false unless @na_page_ready && self.na_showing?(model)
            return true if @na_selection_timer

            @na_selection_timer = UI.start_timer(0.08, false) do
                Na__AgentOutliner::Na__DialogManager.na_flush_selection(model)
            end
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Tag Was Shown, Hidden, Added or Removed (one push per burst)
        # ------------------------------------------------------------
        def self.Na__Dialog__TagsChanged(model)
            return false unless @na_page_ready && self.na_showing?(model)
            return true if @na_tags_timer

            @na_tags_timer = UI.start_timer(0.15, false) do
                Na__AgentOutliner::Na__DialogManager.na_flush_tags(model)
            end
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Another Model Came to the Front (2027 tabs, File > Open)
        # ------------------------------------------------------------
        def self.Na__Dialog__ModelActivated(model)
            return false unless self.Na__Dialog__Visible?
            return true if @na_model && Na__AgentOutliner::Na__Tracker.na_same_model?(@na_model, model)

            @na_model = model
            return true unless @na_page_ready

            self.Na__Dialog__PushState
            self.Na__Dialog__PushSnapshot
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Model Shown Was Closed
        # ------------------------------------------------------------
        def self.Na__Dialog__ModelClosed(model)
            return false unless @na_model && Na__AgentOutliner::Na__Tracker.na_same_model?(@na_model, model)

            @na_model = nil
            UI.start_timer(0.2, false) do
                manager = Na__AgentOutliner::Na__DialogManager
                manager.Na__Dialog__ModelActivated(Sketchup.active_model) if Sketchup.active_model
            end
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Model Was Saved (title and path in the header)
        # ------------------------------------------------------------
        def self.Na__Dialog__ModelInfoChanged(model)
            return false unless @na_page_ready && self.na_showing?(model)

            self.Na__Dialog__Send('model', Na__AgentOutliner::Na__Payloads.Na__Payload__ModelInfo(model))
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | JS -> Ruby
# -----------------------------------------------------------------------------

        def self.na_bind_callbacks(dialog)
            dialog.add_action_callback('na_ao_ready') do |_context|
                begin
                    Na__AgentOutliner::Na__DialogManager.na_on_ready
                rescue StandardError => error
                    Na__AgentOutliner::Na__DebugTools.Na__Debug__Error('The dialog could not be given its data.', error)
                    Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushStatus("The outliner could not read the model: #{error.message}", 'error')
                end
            end

            dialog.add_action_callback('na_ao_action') do |_context, action_id, payload_json|
                begin
                    payload = Na__AgentOutliner::Na__DialogManager.na_parse_payload(payload_json)
                    Na__AgentOutliner::Na__ActionRouter.Na__Action__Dispatch(action_id.to_s, payload)
                rescue StandardError => error
                    Na__AgentOutliner::Na__DebugTools.Na__Debug__Error("Dialog action '#{action_id}' failed.", error)
                    Na__AgentOutliner::Na__DialogManager.Na__Dialog__PushStatus("That did not work: #{error.message}", 'error')
                end
            end
        end

        def self.na_on_ready
            @na_page_ready = true
            @na_selection_sent = nil
            self.Na__Dialog__PushIcons                                                   # <-- Before the state, so the first draw has its pictures (0.1.15)
            self.Na__Dialog__PushState
            self.Na__Dialog__PushSnapshot
            self.Na__Dialog__PushTags
            self.Na__Dialog__Send('log', Na__AgentOutliner::Na__DebugTools.Na__Debug__Lines)
            self.Na__Dialog__StartSelectionWatch
            return unless @na_pending_notice

            self.Na__Dialog__Send('status', @na_pending_notice)
            @na_pending_notice = nil
        end

        def self.na_on_closed(dialog)
            @na_dialog = nil if @na_dialog.equal?(dialog)
            @na_page_ready = false
            self.Na__Dialog__StopSelectionWatch unless self.Na__Dialog__Visible?             # <-- A reload's new dialog may already be up and watching
            Na__AgentOutliner::Na__Tracker.Na__Tracker__SaveAll
            Na__AgentOutliner::Na__Observers.Na__Observers__DetachAll unless Na__AgentOutliner::Na__Tracker.Na__Tracker__Enabled?
        rescue StandardError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Error('Closing the dialog did not finish cleanly.', error)
        end

        def self.na_flush_selection(model)
            @na_selection_timer = nil
            self.Na__Dialog__PushSelection(model)
        rescue StandardError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("Sending the selection failed: #{error.message}")
        end

        def self.na_flush_tags(model)
            @na_tags_timer = nil
            self.Na__Dialog__PushTags(model)
        rescue StandardError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("Sending the tags failed: #{error.message}")
        end

        def self.na_parse_payload(payload_json)
            text = payload_json.to_s.strip
            return {} if text.empty?

            parsed = JSON.parse(text)
            parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("Ignored a malformed dialog payload: #{error.message}")
            {}
        end

        def self.na_showing?(model)
            return false unless self.Na__Dialog__Visible?

            shown = self.Na__Dialog__Model
            shown && Na__AgentOutliner::Na__Tracker.na_same_model?(shown, model)
        end

        def self.na_alive?(model)
            model.valid?
        rescue StandardError
            false
        end

        def self.na_options
            config = Na__AgentOutliner::Na__ConfigStore
            {
                dialog_title:    config.Na__Config__GetOr('Na Agent Outliner', 'dialog', 'title'),
                preferences_key: config.Na__Config__GetOr('Na__AgentOutliner', 'dialog', 'preferences_key'),
                scrollable:      false,
                resizable:       true,
                width:           config.Na__Config__GetOr(1220, 'dialog', 'width').to_i,
                height:          config.Na__Config__GetOr(780, 'dialog', 'height').to_i,
                min_width:       config.Na__Config__GetOr(640, 'dialog', 'min_width').to_i,
                min_height:      config.Na__Config__GetOr(420, 'dialog', 'min_height').to_i,
                style:           UI::HtmlDialog::STYLE_DIALOG
            }
        end

# endregion -------------------------------------------------------------------

    end # module Na__DialogManager
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
