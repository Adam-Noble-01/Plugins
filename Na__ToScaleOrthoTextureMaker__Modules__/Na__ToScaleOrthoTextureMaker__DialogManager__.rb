# =============================================================================
# NA TO SCALE ORTHO TEXTURE MAKER - DIALOG MANAGER
# =============================================================================

require 'json'

module Na__ToScaleOrthoTextureMaker
    module Na__DialogManager

# -----------------------------------------------------------------------------
# REGION | Module Variables
# -----------------------------------------------------------------------------

        @na_dialog = nil

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Show Dialog
        # ------------------------------------------------------------
        def self.Na__Ui__ShowDialog
            begin
                if @na_dialog && @na_dialog.visible?
                    @na_dialog.bring_to_front if @na_dialog.respond_to?(:bring_to_front)
                    self.Na__Ui__PushSceneList
                    return
                end

                @na_dialog = UI::HtmlDialog.new(
                    dialog_title: 'Na To Scale Ortho Texture Maker',
                    preferences_key: 'Na__ToScaleOrthoTextureMaker',
                    scrollable: true,
                    resizable: true,
                    width: 480,
                    height: 620,
                    left: 120,
                    top: 120,
                    style: UI::HtmlDialog::STYLE_DIALOG
                )

                html_file_path = File.join(File.dirname(__FILE__), 'Na__ToScaleOrthoTextureMaker__UiLayout__.html')

                if File.exist?(html_file_path)
                    @na_dialog.set_file(html_file_path)
                else
                    @na_dialog.set_html('<html><body><h2>Na__ToScaleOrthoTextureMaker</h2><p>UI layout file missing.</p></body></html>')
                end

                self.Na__Ui__SetupCallbacks
                @na_dialog.show

                self.Na__Ui__PushSceneList
                self.Na__Ui__PushStatus('info', 'Set up an ortho camera (Parallel Projection + a standard view or scene), then click Capture Viewport.')
            rescue => error
                UI.messagebox("Na__ToScaleOrthoTextureMaker dialog error:\n#{error.message}")
                puts "[Na__Ortho__Dialog] #{error.message}"
                puts error.backtrace.first(10).join("\n") if error.backtrace
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Setup Dialog Callbacks
        # ------------------------------------------------------------
        def self.Na__Ui__SetupCallbacks
            @na_dialog.add_action_callback('na_requestScenes') do |_context|
                self.Na__Ui__PushSceneList
            end

            @na_dialog.add_action_callback('na_runProjection') do |_context, payload_json|
                self.Na__Ui__HandleRunProjection(payload_json)
            end

            @na_dialog.add_action_callback('na_exportTexture') do |_context, payload_json|
                self.Na__Ui__HandleExportTexture(payload_json)
            end

            @na_dialog.add_action_callback('na_refreshScripts') do |_context|
                self.Na__Ui__HandleRefreshScripts
            end

            @na_dialog.add_action_callback('na_jsLog') do |_context, message|
                puts "[Na__Ortho__UI] #{message}"
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Callbacks
# -----------------------------------------------------------------------------

        # FUNCTION | Handle Run Projection Callback
        # ------------------------------------------------------------
        def self.Na__Ui__HandleRunProjection(payload_json)
            payload_hash = {}
            payload_hash = JSON.parse(payload_json) if payload_json && !payload_json.to_s.empty?

            result = Na__ToScaleOrthoTextureMaker.Na__Projection__RunFromUi(payload_hash)
            status_type = result[:success] ? 'success' : 'error'
            message_text = self.Na__Ui__BuildStatusMessageWithWarnings(result)
            self.Na__Ui__PushStatus(status_type, message_text)
        rescue => error
            self.Na__Ui__PushStatus('error', "Capture request failed: #{error.message}")
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build Status Message With Appended Warnings
        # ------------------------------------------------------------
        def self.Na__Ui__BuildStatusMessageWithWarnings(result)
            base_message = result[:message].to_s                                        # Primary outcome line
            warnings = result[:warnings]                                                # Optional warning list
            return base_message unless warnings.is_a?(Array) && !warnings.empty?

            warning_text = warnings.map { |entry| "Warning: #{entry}" }.join(' | ')
            "#{base_message} #{warning_text}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Handle Export Texture Callback
        # ------------------------------------------------------------
        def self.Na__Ui__HandleExportTexture(payload_json)
            payload_hash = {}
            payload_hash = JSON.parse(payload_json) if payload_json && !payload_json.to_s.empty?

            result       = Na__ToScaleOrthoTextureMaker.Na__Export__RunFromUi(payload_hash)
            status_type  = result[:success] ? 'success' : 'error'
            self.Na__Ui__PushExportStatus(status_type, result[:message].to_s)
        rescue => error
            self.Na__Ui__PushExportStatus('error', "Export request failed: #{error.message}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Handle Refresh Scripts Callback
        # ------------------------------------------------------------
        def self.Na__Ui__HandleRefreshScripts
            current_dialog = @na_dialog
            self.Na__Ui__PushSettingsStatusToDialog(
                current_dialog,
                'info',
                'Refreshing scripts...'
            )

            reload_result = self.Na__Dev__ReloadScripts
            status_text = "Reloaded #{reload_result[:reload_count]} files with #{reload_result[:error_count]} errors."
            status_type = reload_result[:error_count] > 0 ? 'error' : 'success'
            self.Na__Ui__PushSettingsStatusToDialog(current_dialog, status_type, status_text)
            puts "[Na__Ortho__Reload] #{status_text}"

            self.Na__Ui__PushSceneList
        rescue => error
            self.Na__Ui__PushSettingsStatusToDialog(
                current_dialog,
                'error',
                "Refresh failed: #{error.message}"
            )
            puts "[Na__Ortho__Reload] Refresh failed: #{error.message}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push Scene List to Dialog
        # ------------------------------------------------------------
        def self.Na__Ui__PushSceneList
            return unless @na_dialog

            model = Sketchup.active_model
            scene_names = ['Current View']
            scene_names.concat(model.pages.map(&:name)) if model && model.pages

            scene_json = JSON.generate(scene_names)
            @na_dialog.execute_script("window.na_setSceneOptions(#{scene_json});")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push Status to Dialog
        # ------------------------------------------------------------
        def self.Na__Ui__PushStatus(status_type, message)
            return unless @na_dialog

            escaped_message = message.to_s.gsub("\\", "\\\\").gsub("'", "\\\\'")
            @na_dialog.execute_script("window.na_setStatus('#{status_type}', '#{escaped_message}');")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push Settings Status to Dialog
        # ------------------------------------------------------------
        def self.Na__Ui__PushSettingsStatus(status_type, message)
            return unless @na_dialog

            escaped_message = message.to_s.gsub("\\", "\\\\").gsub("'", "\\\\'")
            @na_dialog.execute_script("window.na_setSettingsStatus('#{status_type}', '#{escaped_message}');")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push Export Status to Dialog
        # ------------------------------------------------------------
        def self.Na__Ui__PushExportStatus(status_type, message)
            return unless @na_dialog

            escaped_message = message.to_s.gsub("\\", "\\\\").gsub("'", "\\\\'")
            @na_dialog.execute_script("window.na_setExportStatus('#{status_type}', '#{escaped_message}');")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push Settings Status to Provided Dialog
        # ------------------------------------------------------------
        def self.Na__Ui__PushSettingsStatusToDialog(dialog, status_type, message)
            return unless dialog

            escaped_message = message.to_s.gsub("\\", "\\\\").gsub("'", "\\\\'")
            dialog.execute_script("window.na_setSettingsStatus('#{status_type}', '#{escaped_message}');")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Hot Reload Plugin Ruby Scripts
        # ------------------------------------------------------------
        def self.Na__Dev__ReloadScripts
            modules_root_path = File.dirname(__FILE__)
            plugin_root_path = File.dirname(modules_root_path)

            files_to_reload = []
            files_to_reload.concat(Dir.glob(File.join(modules_root_path, '*.rb')).sort)

            root_main_path = File.join(plugin_root_path, 'Na__ToScaleOrthoTextureMaker__Main__.rb')
            root_loader_path = File.join(plugin_root_path, 'Na__ToScaleOrthoTextureMaker__Loader__.rb')
            files_to_reload << root_loader_path if File.exist?(root_loader_path)
            files_to_reload << root_main_path if File.exist?(root_main_path)
            files_to_reload.uniq!

            reload_count = 0
            error_count = 0

            files_to_reload.each do |file_path|
                begin
                    load file_path
                    reload_count += 1
                rescue => error
                    error_count += 1
                    puts "[Na__Ortho__Reload] Error in #{File.basename(file_path)}: #{error.message}"
                end
            end

            {
                reload_count: reload_count,
                error_count: error_count
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
