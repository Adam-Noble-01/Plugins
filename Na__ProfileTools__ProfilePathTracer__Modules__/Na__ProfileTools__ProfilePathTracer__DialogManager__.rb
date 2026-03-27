# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__DialogManager__.rb
# PURPOSE    : HtmlDialog lifecycle and JS <-> Ruby callbacks
# CREATED    : 2026
#
# =============================================================================

require 'json'

module Na__ProfileTools__ProfilePathTracer
    module Na__DialogManager

    # -------------------------------------------------------------------------
    # REGION | Dialog State
    # -------------------------------------------------------------------------

        @na_dialog = nil

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Options
    # -------------------------------------------------------------------------

        NA_DIALOG_TITLE           = 'Na Profile Path Tracer'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__ProfileTools__ProfilePathTracer'.freeze

        NA_DIALOG_WIDTH           = 980
        NA_DIALOG_HEIGHT          = 740

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__Dialog__Show
            return @na_dialog.bring_to_front if @na_dialog && @na_dialog.visible?

            @na_dialog = UI::HtmlDialog.new(self.Na__Dialog__Options)

            self.Na__Dialog__BindCallbacks(@na_dialog)
            @na_dialog.set_file(Na__ProfileTools__ProfilePathTracer::NA_HTML_FILE)
            @na_dialog.show
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Options Builder
    # -------------------------------------------------------------------------

        def self.Na__Dialog__Options
            {
                dialog_title:     NA_DIALOG_TITLE,
                preferences_key:  NA_DIALOG_PREFERENCES_KEY,
                scrollable:       true,
                resizable:        true,
                width:            NA_DIALOG_WIDTH,
                height:           NA_DIALOG_HEIGHT,
                style:            UI::HtmlDialog::STYLE_DIALOG
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Callback Binding (JS -> Ruby)
    # -------------------------------------------------------------------------

        def self.Na__Dialog__BindCallbacks(dialog)
            dialog.add_action_callback('na_profilepathtracer_request_bootstrap') do |_context|
                payload = self.Na__Dialog__BuildBootstrapPayload
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveBootstrap', payload)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Bootstrap callback failed.', error)
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveBootstrap',
                    {
                        'profileKey' => '',
                        'pathMode' => 'selection',
                        'isPreviewEnabled' => true,
                        'toggleDefinitions' => {},
                        'toggleStates' => {},
                        'profileOptions' => [],
                        'profilesByKey' => {},
                        'isBootstrapError' => true,
                        'statusMessage' => "Bootstrap failed: #{error.message}"
                    }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_run_headless') do |_context, json_payload|
                config = JSON.parse(json_payload.to_s)
                result = Na__HeadlessRunner.Na__Headless__Run(config)
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveHeadlessResult', result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Headless callback failed.', error)
            end

            dialog.add_action_callback('na_profilepathtracer_reload_plugin') do |_context|
                dialog_reference = dialog
                reload_result = Na__PluginReloader.Na__Reload__PluginFiles(Na__ProfileTools__ProfilePathTracer::NA_PLUGIN_ROOT)
                self.Na__Dialog__HandleReloadCompletion(dialog_reference, reload_result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Plugin reload callback failed.', error)
                self.Na__Dialog__HandleReloadCompletion(
                    dialog,
                    {
                        'isSuccess' => false,
                        'statusMessage' => "Reload failed: #{error.message}",
                        'issues' => [error.message]
                    }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_generate') do |_context, json_payload|
                generate_config = JSON.parse(json_payload.to_s)
                generate_result = self.Na__Dialog__HandleGenerateRequest(generate_config)
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveGenerateResult', generate_result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Generate callback failed.', error)
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveGenerateResult',
                    { 'isStarted' => false, 'statusMessage' => "Generate failed: #{error.message}" }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_validate_for_export') do |_context|
                validation = Na__ProfileExporter.Na__Exporter__ValidateSelection
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveExportValidation', validation)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Export validation callback failed.', error)
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveExportValidation',
                    { 'isValid' => false, 'reason' => "Validation failed: #{error.message}" }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_save_profile') do |_context, json_payload|
                meta_fields = JSON.parse(json_payload.to_s)
                save_result = self.Na__Dialog__HandleSaveProfileRequest(meta_fields)
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveSaveProfileResult', save_result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Save profile callback failed.', error)
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveSaveProfileResult',
                    { 'isSaved' => false, 'reason' => "Save failed: #{error.message}" }
                )
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Payload Builders / Request Handlers
    # -------------------------------------------------------------------------

        def self.Na__Dialog__BuildBootstrapPayload
            default_run_config = Na__ProfileTools__ProfilePathTracer.Na__State__DefaultRunConfig
            default_profile_key = Na__ProfileLibrary.Na__ProfileLibrary__DefaultProfileKey

            default_run_config.merge(
                'profileKey'      => default_run_config['profileKey'] || default_profile_key,
                'toggleDefinitions' => Na__ProfileTools__ProfilePathTracer.Na__Config__ToggleDefinitions,
                'profileOptions'  => Na__ProfileLibrary.Na__ProfileLibrary__UiProfileOptions,
                'profilesByKey'   => Na__ProfileLibrary.Na__ProfileLibrary__ProfilesByKey
            )
        end

        def self.Na__Dialog__HandleSaveProfileRequest(meta_fields)
            save_result = Na__ProfileExporter.Na__Exporter__RunExport(meta_fields)

            if save_result['isSaved']
                updated_bootstrap = self.Na__Dialog__BuildBootstrapPayload
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveBootstrap', updated_bootstrap)
            end

            {
                'isSaved'       => save_result['isSaved'],
                'reason'        => save_result['reason'],
                'filePath'      => save_result['filePath'],
                'statusMessage' => save_result['isSaved'] ? "Profile saved: #{save_result['filePath']}" : "Save failed: #{save_result['reason']}"
            }
        end

        def self.Na__Dialog__HandleGenerateRequest(generate_config)
            profile_key = generate_config['profileKey']
            validation = Na__ProfilePlacementEngine.Na__Engine__ValidateSelectionForPreview(profile_key)

            unless validation['isValid']
                return {
                    'isStarted' => false,
                    'statusMessage' => "Generate blocked: #{validation['reason']}"
                }
            end

            model = Sketchup.active_model
            path_data = validation['pathData']
            profile_data = validation['profileData']
            toggle_states = self.Na__Dialog__NormalizedToggleStates(generate_config)
            preview_tool = Na__PathSelectionTool.new(profile_key, profile_data, path_data, toggle_states)
            model.select_tool(preview_tool)

            {
                'isStarted' => true,
                'statusMessage' => 'Preview tool active. Click a path vertex to set start point, TAB to rotate.'
            }
        end

        def self.Na__Dialog__HandleReloadCompletion(previous_dialog, reload_result)
            status_payload = self.Na__Dialog__BuildReloadStatusPayload(reload_result)

            begin
                previous_dialog.close if previous_dialog && previous_dialog.visible?
            rescue => error
                Na__DebugTools.Na__Debug__Warn("Reload close warning: #{error.message}")
            end

            self.Na__Dialog__Show
            self.Na__Dialog__SendReloadStatus(status_payload)
        end

        def self.Na__Dialog__BuildReloadStatusPayload(reload_result)
            status_message = 'Reload complete.'
            is_success = true
            issues = []

            if reload_result.is_a?(Hash)
                status_message = reload_result['statusMessage'].to_s.strip
                status_message = 'Reload complete.' if status_message.empty?
                is_success = reload_result['isSuccess'] != false
                issues = reload_result['issues'].is_a?(Array) ? reload_result['issues'] : []
            else
                is_success = false
                status_message = 'Reload finished with unknown response.'
            end

            if !is_success && !issues.empty?
                status_message = "#{status_message} First issue: #{issues.first}"
            end

            {
                'statusMessage' => status_message,
                'isSuccess' => is_success
            }
        end

        def self.Na__Dialog__SendReloadStatus(status_payload)
            return unless @na_dialog

            status_message = status_payload['statusMessage'].to_s
            escaped_status = status_message.gsub('\\', '\\\\').gsub("'", "\\\\'")
            @na_dialog.execute_script("window.setTimeout(function(){ if (window.Na__ProfilePathTracer__Ui__SetStatusFromBridge) { window.Na__ProfilePathTracer__Ui__SetStatusFromBridge('#{escaped_status}'); } }, 700);")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Ruby -> JS Bridge
    # -------------------------------------------------------------------------

        def self.Na__Dialog__SendToJs(function_name, payload)
            return unless @na_dialog
            @na_dialog.execute_script("window.#{function_name}(#{payload.to_json});")
        end

        def self.Na__Dialog__NormalizedToggleStates(generate_config)
            incoming_toggle_states = generate_config['toggleStates']
            default_toggle_states = Na__ProfileTools__ProfilePathTracer.Na__Config__ToggleDefaults
            return default_toggle_states unless incoming_toggle_states.is_a?(Hash)

            default_toggle_states.each_with_object({}) do |(toggle_key, default_value), normalized|
                if incoming_toggle_states.key?(toggle_key)
                    normalized[toggle_key] = incoming_toggle_states[toggle_key] == true
                else
                    normalized[toggle_key] = default_value
                end
            end
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
