# =============================================================================
# NA PAINTERLYNPR ASSETS - NPR VIEWPORT - WINDOWS
# =============================================================================
#
# FILE       : Na__PainterlyAssets__NprViewport__Windows__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__NprWindows
# PURPOSE    : The two NPR windows: NPR Viewport (PainterlyNPR's drawing of the
#              model, nothing else) and NPR Parameters (the engine's own panel,
#              every parameter it has). Both are PainterlyNPR's own app page,
#              served by the local server with this plugin's host added.
#              JS -> Ruby:
#                na_npr_window_ready(json)          - the engine booted, the host is listening
#                na_npr_window_action(action, json) - toggleLive | refresh | reloadRemote |
#                                                     parameters | openViewport | openParameters | status
#                na_npr_waiting_ready()             - the waiting page can be told what is happening
#              Ruby -> JS:
#                window.Na__NprHost__Receive(kind, payload)   kinds: scene | camera | settings | live | status
# CREATED    : 01-Nov-2026
#
# DESCRIPTION:
# - A WINDOW OPENS AT ONCE on a small waiting page of this plugin's (set_file),
#   which says what is happening while the engine is fetched from GitHub (the
#   first time) and the server starts; then it loads the engine's page
#   (set_url). Nothing waits inside the toolbar command.
# - Reload Remote Plugin Files downloads the branch's latest commit again and
#   reloads both windows onto it.
# - Each window's messages wait for its ready call: one sent before the page
#   has parsed would be lost.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__NprWindows

    # -------------------------------------------------------------------------
    # REGION | Constants and State
    # -------------------------------------------------------------------------

        NA_ROLES        = %w[viewport parameters].freeze                                 unless defined?(NA_ROLES)
        NA_WAITING_PAGE = 'Na__PainterlyAssets__NprViewport__Waiting__.html'.freeze        unless defined?(NA_WAITING_PAGE)

        @na_dialogs = {} unless defined?(@na_dialogs)                                       # <-- role => UI::HtmlDialog
        @na_ready   = {} unless defined?(@na_ready)                                         # <-- role => the engine page's host has said ready
        @na_said    = {} unless defined?(@na_said)                                          # <-- role => the waiting page's last line

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Opening and Closing
    # -------------------------------------------------------------------------

        # FUNCTION | Open a Window (or bring it to the front)
        # ------------------------------------------------------------
        def self.Na__Windows__Open(role)
            role = role.to_s
            return @na_dialogs[role].bring_to_front if self.Na__Windows__Visible?(role)

            dialog = UI::HtmlDialog.new(self.na_options(role))
            self.na_bind(dialog, role)
            @na_ready[role] = false
            @na_said[role]  = ['Starting the PainterlyNPR engine...', 'busy']
            dialog.set_file(File.join(__dir__, NA_WAITING_PAGE))
            dialog.set_on_closed do
                Na__PainterlyAssets::Na__NprWindows.na_forget(role, dialog)
            end
            @na_dialogs[role] = dialog
            dialog.show
            UI.start_timer(0.05, false) { Na__PainterlyAssets::Na__NprWindows.na_prepare(role, 0) }   # <-- Out of the command: the download and the server do not hold it up
        end
        # ---------------------------------------------------------------

        def self.Na__Windows__Visible?(role)
            dialog = @na_dialogs[role.to_s]
            dialog && dialog.visible? ? true : false
        rescue StandardError
            false
        end

        def self.Na__Windows__Ready?(role)
            self.Na__Windows__Visible?(role) && @na_ready[role.to_s] ? true : false
        end

        def self.Na__Windows__Close(role)
            dialog = @na_dialogs[role.to_s]
            dialog.close if dialog && self.Na__Windows__Visible?(role)
        end

        # FUNCTION | Reload Remote Plugin Files: the latest commit downloaded, both windows reloaded onto it
        # ------------------------------------------------------------
        def self.Na__Windows__ReloadRemote
            open = NA_ROLES.select { |role| self.Na__Windows__Visible?(role) }
            self.Na__Windows__SendAll('status', { 'Text' => 'Downloading PainterlyNPR from GitHub...', 'Level' => 'busy' })
            Na__RemoteEngine.Na__Remote__Fetch(force: true) do |result|
                if result['ok']
                    open.each { |role| Na__PainterlyAssets::Na__NprWindows.na_prepare(role, 0) }
                    Na__PainterlyAssets::Na__NprWindows.na_tell_closed(result['message']) if open.empty?
                else
                    Na__PainterlyAssets::Na__NprWindows.Na__Windows__SendAll('status', { 'Text' => "Reload Remote Plugin Files failed: #{result['message']}", 'Level' => 'error' })
                    Na__PainterlyAssets::Na__NprWindows.na_tell_closed("Reload Remote Plugin Files failed: #{result['message']}") if open.empty?
                end
            end
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Ruby -> JS
    # -------------------------------------------------------------------------

        # FUNCTION | One Message to One Window's Host (only once it is ready)
        # ------------------------------------------------------------
        def self.Na__Windows__Send(role, kind, payload)
            role = role.to_s
            return false unless self.Na__Windows__Ready?(role)
            script = "window.Na__NprHost__Receive && window.Na__NprHost__Receive(#{JSON.generate(kind.to_s)}, #{JSON.generate(payload)});"
            @na_dialogs[role].execute_script(script)
            true
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error("Sending '#{kind}' to the NPR #{role} window failed.", error)
            false
        end
        # ---------------------------------------------------------------

        def self.Na__Windows__SendAll(kind, payload)
            NA_ROLES.each { |role| self.Na__Windows__Send(role, kind, payload) }
            NA_ROLES.each { |role| self.na_say(role, payload['Text'], payload['Level']) unless @na_ready[role] } if kind == 'status' && payload['Text']
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Getting a Window to the Engine
    # -------------------------------------------------------------------------

        # The engine cached (fetched the first time), the server up, then the
        # engine's page. tries stops a download that "succeeds" without a cache.
        def self.na_prepare(role, tries)
            return unless self.Na__Windows__Visible?(role)
            engine = Na__RemoteEngine.Na__Remote__Current
            if engine.nil?
                return self.na_say(role, 'PainterlyNPR could not be downloaded into the cache. Use Reload Remote Plugin Files to try again.', 'error') if tries > 0
                self.na_say(role, 'Downloading PainterlyNPR from GitHub (the first time only)...', 'busy')
                Na__RemoteEngine.Na__Remote__Fetch do |result|
                    if result['ok']
                        Na__PainterlyAssets::Na__NprWindows.na_prepare(role, tries + 1)
                    else
                        Na__PainterlyAssets::Na__NprWindows.na_say(role, "PainterlyNPR could not be downloaded: #{result['message']}", 'error')
                    end
                end
                return
            end

            self.na_say(role, "Starting PainterlyNPR #{engine['appVersion']} (#{engine['commit']})...", 'busy')
            Na__LocalServer.Na__Server__Ensure do |result|
                if result['ok']
                    Na__PainterlyAssets::Na__NprWindows.na_load(role, engine)
                else
                    Na__PainterlyAssets::Na__NprWindows.na_say(role, result['message'], 'error')
                end
            end
        end

        def self.na_load(role, engine)
            dialog = @na_dialogs[role]
            return unless dialog && self.Na__Windows__Visible?(role)
            @na_ready[role] = false
            dialog.set_url(Na__LocalServer.Na__Server__PageUrl(role, engine['commit']))
        end

        # A line on the waiting page (before the engine's page has loaded)
        def self.na_say(role, text, level = 'info')
            @na_said[role] = [text.to_s, level.to_s]
            dialog = @na_dialogs[role]
            return unless dialog && self.Na__Windows__Visible?(role) && !@na_ready[role]
            dialog.execute_script("window.Na__NprWaiting__Say && window.Na__NprWaiting__Say(#{JSON.generate(text.to_s)}, #{JSON.generate(level.to_s)});")
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The NPR #{role} window's waiting page could not be told: #{error.message}")
        end

        # No window open: the outcome goes to a message box, out of the callback
        def self.na_tell_closed(text)
            fired = false
            UI.start_timer(0, false) do
                next if fired
                fired = true
                UI.messagebox("Na PainterlyNPR Assets\n\n#{text}")
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | JS -> Ruby
    # -------------------------------------------------------------------------

        def self.na_bind(dialog, role)
            dialog.add_action_callback('na_npr_window_ready') do |_context, json|
                begin
                    info = Na__PainterlyAssets::Na__NprWindows.na_parse(json)
                    Na__PainterlyAssets::Na__NprWindows.na_on_ready(role, info)
                rescue StandardError => error
                    Na__PainterlyAssets::Na__DebugTools.Na__Debug__Error("The NPR #{role} window could not be given its state.", error)
                end
            end

            dialog.add_action_callback('na_npr_window_action') do |_context, action, json|
                begin
                    Na__PainterlyAssets::Na__NprWindows.na_action(role, action.to_s, Na__PainterlyAssets::Na__NprWindows.na_parse(json))
                rescue StandardError => error
                    Na__PainterlyAssets::Na__DebugTools.Na__Debug__Error("The NPR #{role} window's #{action} failed.", error)
                    Na__PainterlyAssets::Na__NprWindows.Na__Windows__Send(role, 'status', { 'Text' => "That did not work: #{error.message}", 'Level' => 'error' })
                end
            end

            dialog.add_action_callback('na_npr_waiting_ready') do |_context|
                said = Na__PainterlyAssets::Na__NprWindows.na_said_for(role)
                Na__PainterlyAssets::Na__NprWindows.na_say(role, said[0], said[1]) if said
            end
        end

        def self.na_on_ready(role, info)
            @na_ready[role] = true
            Na__DebugTools.Na__Debug__Info("NPR #{role} window ready: PainterlyNPR #{info['EngineVersion']}#{info['Booted'] ? '' : " (not booted: #{info['Error']})"}.")
            Na__LiveSync.Na__Live__WindowReady(role, info)
        end

        def self.na_action(role, action, payload)
            case action
            when 'toggleLive'      then Na__LiveSync.Na__Live__Toggle
            when 'setLive'         then Na__LiveSync.Na__Live__Set(payload['On'])
            when 'refresh'         then Na__LiveSync.Na__Live__Refresh
            when 'reloadRemote'    then self.Na__Windows__ReloadRemote
            when 'parameters'      then Na__LiveSync.Na__Live__ParametersChanged(payload)
            when 'openViewport'    then self.na_defer { self.Na__Windows__Open('viewport') }
            when 'openParameters'  then self.na_defer { self.Na__Windows__Open('parameters') }
            when 'status'          then self.Na__Windows__Send(role == 'viewport' ? 'parameters' : 'viewport', 'status', payload)
            else
                Na__DebugTools.Na__Debug__Warn("The NPR #{role} window asked for an unknown action: #{action}")
            end
        end

        def self.na_defer(&block)
            fired = false
            UI.start_timer(0.15, false) do                                               # <-- Never build a window inside another window's callback
                next if fired
                fired = true
                block.call
            end
        end

        def self.na_forget(role, dialog)
            return unless @na_dialogs[role].equal?(dialog)
            @na_dialogs.delete(role)
            @na_ready[role] = false
            Na__LiveSync.Na__Live__ViewportClosed if role == 'viewport'
        end

        def self.na_said_for(role)
            @na_said[role]
        end

        def self.na_parse(json)
            text = json.to_s.strip
            return {} if text.empty?
            parsed = JSON.parse(text)
            parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError => error
            Na__DebugTools.Na__Debug__Warn("Ignored a malformed NPR window payload: #{error.message}")
            {}
        end

        def self.na_options(role)
            spec = Na__ConfigLoader.Na__Config__Get('nprViewport', role) || {}
            {
                dialog_title:    spec['title'] || (role == 'viewport' ? 'NPR Viewport' : 'NPR Parameters'),
                preferences_key: spec['preferencesKey'] || "Na__PainterlyNPR__Npr#{role.capitalize}",
                scrollable:      false,
                resizable:       true,
                width:           (spec['width'] || 1000).to_i,
                height:          (spec['height'] || 720).to_i,
                min_width:       (spec['minWidth'] || 360).to_i,
                min_height:      (spec['minHeight'] || 300).to_i,
                style:           UI::HtmlDialog::STYLE_DIALOG
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
