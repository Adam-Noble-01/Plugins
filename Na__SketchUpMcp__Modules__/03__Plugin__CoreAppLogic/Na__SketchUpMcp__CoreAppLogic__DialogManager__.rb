# =============================================================================
# NA SKETCHUP MCP - CORE DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__CoreAppLogic__DialogManager__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__DialogManager
# PURPOSE    : The status dialog: bridge state, safety toggles, client setup
#              snippets, API self-test and the live activity log
# CREATED    : 2026
#
# RENDERING PATTERN (same as Na__Noble3dModellingTools):
# The HTML layout is a shell template; stylesheet and bridge script are
# inlined into its {{PLACEHOLDERS}} at open time. Once the page reports
# na_ready, Ruby pushes the whole state as one JSON object and then pushes each
# new activity entry as it happens. After Reload Plugin Data the dialog is
# closed so the next open picks up the new files.
#
# =============================================================================

require 'json'

module Na__SketchUpMcp
    module Na__DialogManager

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        def self.Na__DialogManager__Show
            if self.Na__DialogManager__Visible
                @na_dialog.bring_to_front
                return @na_dialog
            end

            @na_dialog = UI::HtmlDialog.new(
                dialog_title: Na__ConfigLoader.Na__ConfigLoader__Get('dialog', 'title', 'Na SketchUp MCP'),
                preferences_key: Na__ConfigLoader.Na__ConfigLoader__Get('dialog', 'preferences_key', 'Na__SketchUpMcp__StatusDialog'),
                scrollable: true,
                resizable: Na__ConfigLoader.Na__ConfigLoader__Get('dialog', 'resizable', true),
                width: Na__ConfigLoader.Na__ConfigLoader__Get('dialog', 'width', 560),
                height: Na__ConfigLoader.Na__ConfigLoader__Get('dialog', 'height', 760),
                style: UI::HtmlDialog::STYLE_DIALOG
            )
            @na_dialog.set_html(na_render_html)
            na_add_callbacks(@na_dialog)
            @na_dialog.set_on_closed { @na_dialog = nil }
            @na_dialog.show
            @na_dialog
        end

        def self.Na__DialogManager__Visible
            !!(@na_dialog && @na_dialog.visible?)
        end

        def self.Na__DialogManager__RefreshIfVisible
            return false unless self.Na__DialogManager__Visible

            na_push_state
            true
        end

        def self.Na__DialogManager__PushActivity(entry)
            return false unless self.Na__DialogManager__Visible

            @na_dialog.execute_script("Na__SketchUpMcp__AppendActivity(#{JSON.generate(entry)}, #{JSON.generate(na_bridge_state)});")
            true
        rescue StandardError
            false
        end

        def self.Na__DialogManager__ResetDialog
            @na_dialog.close if self.Na__DialogManager__Visible
            @na_dialog = nil
        rescue StandardError
            @na_dialog = nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | HTML Rendering
# -----------------------------------------------------------------------------

        def self.na_render_html
            File.read(Na__PathResolver.Na__PathResolver__UiLayoutFilePath, encoding: 'UTF-8')
                .gsub('{{DIALOG_TITLE}}', na_escape_html(Na__ConfigLoader.Na__ConfigLoader__Get('dialog', 'title', 'Na SketchUp MCP')))
                .gsub('{{LOGO_FILE_URI}}', na_logo_uri)
                .gsub('{{STYLESHEET_CONTENT}}') { File.read(Na__PathResolver.Na__PathResolver__UiStylesheetFilePath, encoding: 'UTF-8') }
                .gsub('{{UI_BRIDGE_SCRIPT}}') { File.read(Na__PathResolver.Na__PathResolver__UiBridgeFilePath, encoding: 'UTF-8') }
        end

        def self.na_logo_uri
            path = Na__PathResolver.Na__PathResolver__NaLogoFilePath
            return '' unless File.exist?(path)

            'file:///' + path.tr('\\', '/').sub(%r{\A/}, '').gsub(' ', '%20')
        end

        def self.na_escape_html(text)
            text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;').gsub("'", '&#39;')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | JS Bridge (callbacks in, state out)
# -----------------------------------------------------------------------------

        def self.na_add_callbacks(dialog)
            dialog.add_action_callback('na_ready') { |_context| na_push_state }
            dialog.add_action_callback('na_action') do |_context, action_name, _payload|
                na_handle_action(action_name.to_s)
                na_push_state
            end
        end

        def self.na_handle_action(action_name)
            case action_name
            when 'start'             then Na__SketchUpMcp.Na__SketchUpMcp__StartBridge
            when 'stop'              then Na__SketchUpMcp.Na__SketchUpMcp__StopBridge
            when 'restart'
                Na__SocketServer.Na__SocketServer__Stop
                Na__SocketServer.Na__SocketServer__Start
            when 'toggle_read_only'  then Na__SketchUpMcp.Na__SketchUpMcp__ToggleSetting('safety', 'read_only_mode')
            when 'toggle_eval'       then Na__SketchUpMcp.Na__SketchUpMcp__ToggleSetting('safety', 'allow_ruby_eval')
            when 'toggle_auto_start' then Na__SketchUpMcp.Na__SketchUpMcp__ToggleSetting('bridge', 'auto_start')
            when 'clear_log'         then Na__ActivityLog.Na__ActivityLog__Clear
            when 'self_test'         then Na__ApiSelfTest.Na__ApiSelfTest__Run
            end
        rescue StandardError => error
            puts "[Na__SketchUpMcp] Dialog action '#{action_name}' failed: #{error.class}: #{error.message}"
        end

        def self.na_push_state
            return unless self.Na__DialogManager__Visible

            @na_dialog.execute_script("Na__SketchUpMcp__Render(#{JSON.generate(na_full_state)});")
        end

        def self.na_bridge_state
            Na__SocketServer.Na__SocketServer__Status.merge(
                'version'         => Na__ConfigLoader.Na__ConfigLoader__BridgeVersion,
                'read_only_mode'  => Na__ConfigLoader.Na__ConfigLoader__ReadOnlyMode,
                'allow_ruby_eval' => Na__ConfigLoader.Na__ConfigLoader__AllowRubyEval,
                'auto_start'      => Na__ConfigLoader.Na__ConfigLoader__Get('bridge', 'auto_start', true) == true,
                'counters'        => Na__ActivityLog.Na__ActivityLog__Counters
            )
        end

        def self.na_full_state
            self_test = Na__ApiSelfTest.Na__ApiSelfTest__Report
            {
                'bridge'    => na_bridge_state,
                'sketchup'  => { 'version' => Sketchup.version.to_s, 'model' => Sketchup.active_model ? Sketchup.active_model.title.to_s : '' },
                'self_test' => { 'checked' => self_test['checked'], 'unavailable_tools' => self_test['unavailable_tools'],
                                 'tool_count' => Na__ConfigLoader.Na__ConfigLoader__Tools.length },
                'activity'  => Na__ActivityLog.Na__ActivityLog__Entries.first(100),
                'clients'   => na_client_snippets
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Client Setup Snippets
# -----------------------------------------------------------------------------

        def self.na_client_snippets
            server = Na__PathResolver.Na__PathResolver__PythonServerEntryFilePath.tr('/', '\\')
            server_forward = server.tr('\\', '/')
            json_entry = { 'command' => 'python', 'args' => [server], 'env' => { 'PYTHONUTF8' => '1' } }
            {
                'server_path'    => server,
                'claude_code'    => "claude mcp add sketchup --scope user --env PYTHONUTF8=1 -- python \"#{server}\"",
                'claude_desktop' => JSON.pretty_generate('mcpServers' => { 'sketchup' => json_entry }),
                'codex'          => "[mcp_servers.sketchup]\ncommand = 'python'\nargs = ['#{server}']\nenv = { PYTHONUTF8 = \"1\" }\n" \
                                    "startup_timeout_sec = 20\ntool_timeout_sec = 300",
                'cursor'         => JSON.pretty_generate('mcpServers' => { 'sketchup' => json_entry }),
                'vscode'         => JSON.pretty_generate('servers' => { 'sketchup' => { 'type' => 'stdio', 'command' => 'python', 'args' => [server_forward],
                                                                                        'env' => { 'PYTHONUTF8' => '1' } } })
            }
        end

# endregion -------------------------------------------------------------------

    end # module Na__DialogManager
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
