# =============================================================================
# NA PAINTERLYNPR ASSETS - APP CORE - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__PainterlyAssets__AppCore__DialogManager__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__DialogManager
# PURPOSE    : HtmlDialog lifecycle and the two JS -> Ruby callbacks:
#                na_npr_dialog_ready()            - page loaded, send state
#                na_npr_action(actionId, json)    - everything else (ActionRouter)
#              Ruby -> JS is one entry point:
#                window.Na__PainterlyAssets__Receive(channel, payload)
#              channels: state | catalogue | selection | plan | authored |
#                        validation | busy | status
# CREATED    : 30-Oct-2026
#
# DESCRIPTION:
# - set_file, not set_html: the page is a file:// page beside its CSS and JS,
#   so the library's pictures load straight from their file:/// URIs and the
#   shared Noble logo from Na__Common__PluginDependencies by a relative path.
# - Native panels (choose a folder, choose python.exe, Explorer) are deferred
#   out of the callback with a one-shot timer: inside it they can be lost
#   behind the dialog on Windows.
#
# =============================================================================

module Na__PainterlyAssets
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
            dialog.set_file(Na__PainterlyAssets::NA_HTML_FILE)
            # Only clear the reference if it still points at THIS dialog - a
            # reload opens the replacement before the old close event lands.
            dialog.set_on_closed do
                manager = Na__PainterlyAssets::Na__DialogManager
                manager.na_forget(dialog)
            end
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
        # its own dialog is closed, and never close one dialog and build the
        # next in the same pass. The outcome shows once the new page is ready.
        def self.Na__Dialog__ReloadPlugin
            result = Na__PluginReloader.Na__Reload__Run
            notice = { 'message' => result['statusMessage'], 'level' => result['isSuccess'] ? 'success' : 'error' }
            return self.Na__Dialog__Send('status', notice) if result['isBlocked']

            @na_pending_notice = notice
            UI.start_timer(0.05, false) { Na__PainterlyAssets::Na__DialogManager.Na__Dialog__Close }
            UI.start_timer(0.25, false) { Na__PainterlyAssets::Na__DialogManager.Na__Dialog__Show }
        end

        # FUNCTION | Run a Block Once, Out of the Current Callback
        # ------------------------------------------------------------
        # A non-repeating timer can fire again while a modal is open, so the
        # block is guarded to run once.
        def self.Na__Dialog__Deferred(&block)
            fired = false
            UI.start_timer(0, false) do
                next if fired
                fired = true
                begin
                    block.call
                rescue StandardError => error
                    Na__PainterlyAssets::Na__DebugTools.Na__Debug__Error('A deferred dialog step failed.', error)
                    Na__PainterlyAssets::Na__DialogManager.Na__Dialog__PushStatus("That did not work: #{error.message}", 'error')
                end
            end
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Ruby -> JS
    # -------------------------------------------------------------------------

        def self.Na__Dialog__Send(channel, payload)
            return false unless self.Na__Dialog__Visible?
            script = "window.Na__PainterlyAssets__Receive && window.Na__PainterlyAssets__Receive(" \
                     "#{JSON.generate(channel.to_s)}, #{JSON.generate(payload)});"
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

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | JS -> Ruby
    # -------------------------------------------------------------------------

        def self.na_bind_callbacks(dialog)
            dialog.add_action_callback('na_npr_dialog_ready') do |_context|
                begin
                    Na__PainterlyAssets::Na__DialogManager.na_on_dialog_ready
                rescue StandardError => error
                    Na__PainterlyAssets::Na__DebugTools.Na__Debug__Error('The dialog could not be given its state.', error)
                end
            end

            dialog.add_action_callback('na_npr_action') do |_context, action_id, payload_json|
                payload = Na__PainterlyAssets::Na__DialogManager.na_parse_payload(payload_json)
                Na__PainterlyAssets::Na__ActionRouter.Na__Action__Dispatch(action_id.to_s, payload)
            end
        end

        def self.na_on_dialog_ready
            self.Na__Dialog__PushState
            return unless @na_pending_notice
            self.Na__Dialog__Send('status', @na_pending_notice)
            @na_pending_notice = nil
        end

        def self.na_forget(dialog)
            @na_dialog = nil if @na_dialog.equal?(dialog)
        end

        def self.na_parse_payload(payload_json)
            text = payload_json.to_s.strip
            return {} if text.empty?
            parsed = JSON.parse(text)
            parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError => error
            Na__DebugTools.Na__Debug__Warn("Ignored a malformed dialog payload: #{error.message}")
            {}
        end

        def self.na_options
            {
                dialog_title:    Na__ConfigLoader.Na__Config__GetOr('Na PainterlyNPR Assets', 'dialog', 'title'),
                preferences_key: Na__ConfigLoader.Na__Config__GetOr('Na__PainterlyNPR__AssetLibrary', 'dialog', 'preferencesKey'),
                scrollable:      false,
                resizable:       true,
                width:           Na__ConfigLoader.Na__Config__GetOr(820, 'dialog', 'width').to_i,
                height:          Na__ConfigLoader.Na__Config__GetOr(900, 'dialog', 'height').to_i,
                min_width:       560,
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
