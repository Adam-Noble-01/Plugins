# =============================================================================
# NA POINT CLOUD VIEWER - APP CORE - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__PointCloudViewer__AppCore__DialogManager__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__DialogManager
# PURPOSE    : HtmlDialog lifecycle and the two JS -> Ruby callbacks:
#                na_pcv_dialog_ready()            - page loaded, send state
#                na_pcv_action(actionId, json)    - everything else (ActionRouter)
#              Ruby -> JS is one entry point:
#                window.Na__PointCloudViewer__Receive(channel, payload)
#              channels: state | stats | progress | jobFinished | status
#
# =============================================================================

module Na__PointCloudViewer
    module Na__DialogManager

    # -------------------------------------------------------------------------
    # REGION | State
    # -------------------------------------------------------------------------

        @na_dialog         = nil unless defined?(@na_dialog)
        @na_pending_notice = nil unless defined?(@na_pending_notice)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Lifecycle
    # -------------------------------------------------------------------------

        def self.Na__Dialog__Show
            return @na_dialog.bring_to_front if self.Na__Dialog__Visible?

            dialog = UI::HtmlDialog.new(self.na_options)
            self.na_bind_callbacks(dialog)
            dialog.set_file(Na__PointCloudViewer::NA_HTML_FILE)
            # Only clear the reference if it still points at THIS dialog - a
            # reload opens the replacement before the old close event lands.
            dialog.set_on_closed { @na_dialog = nil if @na_dialog.equal?(dialog) }
            @na_dialog = dialog
            dialog.show
        end

        def self.Na__Dialog__Close
            @na_dialog.close if self.Na__Dialog__Visible?
            @na_dialog = nil
        end

        def self.Na__Dialog__Visible?
            @na_dialog && @na_dialog.visible? ? true : false
        rescue StandardError
            false
        end

        # Reload, then reopen on the next tick so this callback returns before
        # its own dialog is closed. The outcome is shown once the new page
        # reports ready.
        def self.Na__Dialog__ReloadPlugin
            result = Na__PluginReloader.Na__Reload__Run
            notice = { 'message' => result['statusMessage'], 'level' => result['isSuccess'] ? 'success' : 'error' }
            return self.Na__Dialog__Send('status', notice) if result['isBlocked']

            @na_pending_notice = notice
            UI.start_timer(0.05, false) do
                manager = Na__PointCloudViewer::Na__DialogManager
                manager.Na__Dialog__Close
                manager.Na__Dialog__Show
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Ruby -> JS
    # -------------------------------------------------------------------------

        def self.Na__Dialog__Send(channel, payload)
            return false unless self.Na__Dialog__Visible?
            script = "window.Na__PointCloudViewer__Receive && window.Na__PointCloudViewer__Receive(" \
                     "#{JSON.generate(channel.to_s)}, #{JSON.generate(payload, allow_nan: true)});"
            @na_dialog.execute_script(script)
            true
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error("Sending '#{channel}' to the dialog failed.", error)
            false
        end

        def self.Na__Dialog__PushState
            self.Na__Dialog__Send('state', Na__StatePayload.Na__State__Build)
        end

        def self.Na__Dialog__PushStatus(message, level = 'info')
            self.Na__Dialog__Send('status', { 'message' => message.to_s, 'level' => level.to_s })
        end

        def self.Na__Dialog__SendProgress(title, status, percent, state)
            self.Na__Dialog__Send('progress', {
                'title' => title.to_s, 'status' => status.to_s,
                'percent' => percent.nil? ? nil : percent.to_f.round(1), 'state' => state.to_s
            })
        end

        def self.Na__Dialog__SendJobFinished(outcome, message, summary)
            self.Na__Dialog__Send('jobFinished', { 'outcome' => outcome.to_s, 'message' => message.to_s, 'summary' => summary || {} })
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | JS -> Ruby
    # -------------------------------------------------------------------------

        def self.na_bind_callbacks(dialog)
            dialog.add_action_callback('na_pcv_dialog_ready') do |_context|
                Na__PointCloudViewer::Na__DialogManager.na_on_dialog_ready
            end

            dialog.add_action_callback('na_pcv_action') do |_context, action_id, payload_json|
                payload = Na__PointCloudViewer::Na__DialogManager.na_parse_payload(payload_json)
                Na__PointCloudViewer::Na__ActionRouter.Na__Action__Dispatch(action_id.to_s, payload)
            end
        end

        def self.na_on_dialog_ready
            self.Na__Dialog__PushState
            return unless @na_pending_notice
            self.Na__Dialog__Send('status', @na_pending_notice)
            @na_pending_notice = nil
        end

        def self.na_parse_payload(payload_json)
            text = payload_json.to_s.strip
            return {} if text.empty?
            parsed = JSON.parse(text)
            parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError => error
            Na__DebugTools.Na__Debug__Warn("Ignored malformed dialog payload: #{error.message}")
            {}
        end

        def self.na_options
            {
                dialog_title:    Na__ConfigLoader.Na__Config__GetOr('Na Point Cloud Viewer', 'dialog', 'title'),
                preferences_key: Na__ConfigLoader.Na__Config__GetOr('Na__PointCloudTools__PointCloudViewer', 'dialog', 'preferencesKey'),
                scrollable:      false,
                resizable:       true,
                width:           Na__ConfigLoader.Na__Config__GetOr(600, 'dialog', 'width').to_i,
                height:          Na__ConfigLoader.Na__Config__GetOr(880, 'dialog', 'height').to_i,
                min_width:       480,
                min_height:      560,
                style:           UI::HtmlDialog::STYLE_DIALOG
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
