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

            dialog.add_action_callback('na_profilepathtracer_activate_preview_tool') do |_context, json_payload|
                tool_config = JSON.parse(json_payload.to_s)
                tool_result = self.Na__Dialog__HandleGenerateRequest(tool_config)
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveGenerateResult', tool_result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Preview tool activation failed.', error)
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveGenerateResult',
                    { 'isStarted' => false, 'statusMessage' => "Preview tool activation failed: #{error.message}" }
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
                'profileOptions'  => Na__ProfileLibrary.Na__ProfileLibrary__UiProfileOptions,
                'profilesByKey'   => Na__ProfileLibrary.Na__ProfileLibrary__ProfilesByKey
            )
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
            preview_tool = Na__PathSelectionTool.new(profile_key, profile_data, path_data)
            model.select_tool(preview_tool)

            {
                'isStarted' => true,
                'statusMessage' => 'Preview tool active. Click a path vertex to set start point, TAB to rotate.'
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Ruby -> JS Bridge
    # -------------------------------------------------------------------------

        def self.Na__Dialog__SendToJs(function_name, payload)
            return unless @na_dialog
            @na_dialog.execute_script("window.#{function_name}(#{payload.to_json});")
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
