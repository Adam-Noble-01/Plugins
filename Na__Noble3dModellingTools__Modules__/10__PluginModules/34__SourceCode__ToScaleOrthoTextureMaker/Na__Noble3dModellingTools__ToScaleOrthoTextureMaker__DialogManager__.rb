# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TO SCALE ORTHO TEXTURE MAKER - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ToScaleOrthoTextureMaker__DialogManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ToScaleOrthoTextureMaker__DialogManager
# PURPOSE    : HtmlDialog for viewport capture and texture export
# CREATED    : 2026
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__ToScaleOrthoTextureMaker__DialogManager

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIALOG_TITLE = 'Na Noble3d Tools : To Scale Ortho Texture Maker'.freeze unless const_defined?(:NA_DIALOG_TITLE)
        NA_DIALOG_PREFERENCES_KEY = 'Na__Noble3dModellingTools__ToScaleOrthoTextureMaker'.freeze unless const_defined?(:NA_DIALOG_PREFERENCES_KEY)
        NA_DIALOG_WIDTH = 480 unless const_defined?(:NA_DIALOG_WIDTH)
        NA_DIALOG_HEIGHT = 720 unless const_defined?(:NA_DIALOG_HEIGHT)
        NA_READY_STATUS = 'Set up an ortho camera (Parallel Projection + a standard view or scene), then click Capture Viewport.'.freeze unless const_defined?(:NA_READY_STATUS)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Show or Focus the Ortho Texture Maker Dialog
        # ------------------------------------------------------------
        def self.Na__ToScaleOrthoTextureMaker__DialogManager__ShowDialog
            if @na_dialog && @na_dialog.visible?
                @na_dialog.bring_to_front if @na_dialog.respond_to?(:bring_to_front)
                na_push_scene_list
                return @na_dialog
            end

            @na_dialog = na_create_dialog
            na_register_callbacks
            @na_dialog.show
            na_push_scene_list
            na_push_status('info', NA_READY_STATUS)
            @na_dialog
        rescue StandardError => error
            UI.messagebox("To Scale Ortho Texture Maker dialog error:\n#{error.message}")
            puts "[Na__ToScaleOrthoTextureMaker] #{error.class}: #{error.message}"
            puts error.backtrace.first(10).join("\n") if error.backtrace
            nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Close the Dialog After a Full Plugin Reload
        # ------------------------------------------------------------
        def self.Na__ToScaleOrthoTextureMaker__DialogManager__ResetDialog
            return unless @na_dialog

            @na_dialog.close if @na_dialog.visible?
            @na_dialog = nil
            true
        rescue StandardError => error
            puts "[Na__ToScaleOrthoTextureMaker] reset dialog warning: #{error.class}: #{error.message}"
            @na_dialog = nil
            false
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Construction and Callbacks
# -----------------------------------------------------------------------------

        def self.na_create_dialog
            dialog = UI::HtmlDialog.new(
                dialog_title: NA_DIALOG_TITLE,
                preferences_key: NA_DIALOG_PREFERENCES_KEY,
                scrollable: true,
                resizable: true,
                width: NA_DIALOG_WIDTH,
                height: NA_DIALOG_HEIGHT,
                left: 120,
                top: 120,
                style: UI::HtmlDialog::STYLE_DIALOG
            )
            html_file_path = File.join(File.dirname(__FILE__), 'Na__Noble3dModellingTools__ToScaleOrthoTextureMaker__UiLayout__.html')
            if File.exist?(html_file_path)
                dialog.set_file(html_file_path)
            else
                dialog.set_html('<html><body><h2>To Scale Ortho Texture Maker</h2><p>UI layout file missing.</p></body></html>')
            end
            dialog
        end

        def self.na_register_callbacks
            @na_dialog.add_action_callback('na_requestScenes') { |_context| na_push_scene_list }
            @na_dialog.add_action_callback('na_runProjection') { |_context, payload_json| na_handle_projection(payload_json) }
            @na_dialog.add_action_callback('na_exportTexture') { |_context, payload_json| na_handle_export(payload_json) }
            @na_dialog.add_action_callback('na_refreshScripts') { |_context| na_handle_refresh_scripts }
            @na_dialog.add_action_callback('na_jsLog') { |_context, message| puts "[Na__ToScaleOrthoTextureMaker__UI] #{message}" }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Handlers
# -----------------------------------------------------------------------------

        def self.na_handle_projection(payload_json)
            result = Na__ToScaleOrthoTextureMaker__Projection.Na__ToScaleOrthoTextureMaker__Projection__Run(na_parse_payload(payload_json))
            na_push_status(result[:success] ? 'success' : 'error', na_message_with_warnings(result))
        rescue StandardError => error
            na_push_status('error', "Capture request failed: #{error.message}")
        end

        def self.na_handle_export(payload_json)
            result = Na__ToScaleOrthoTextureMaker__Projection.Na__ToScaleOrthoTextureMaker__Projection__Export(na_parse_payload(payload_json))
            na_push_export_status(result[:success] ? 'success' : 'error', result[:message].to_s)
        rescue StandardError => error
            na_push_export_status('error', "Export request failed: #{error.message}")
        end

        def self.na_handle_refresh_scripts
            current_dialog = @na_dialog
            na_push_settings_status_to(current_dialog, 'info', 'Refreshing scripts...')
            reload_result = na_reload_feature_scripts
            status_text = "Reloaded #{reload_result[:reload_count]} files with #{reload_result[:error_count]} errors."
            status_type = reload_result[:error_count] > 0 ? 'error' : 'success'
            na_push_settings_status_to(current_dialog, status_type, status_text)
            puts "[Na__ToScaleOrthoTextureMaker] #{status_text}"
            na_push_scene_list
        rescue StandardError => error
            na_push_settings_status_to(current_dialog, 'error', "Refresh failed: #{error.message}")
            puts "[Na__ToScaleOrthoTextureMaker] Refresh failed: #{error.message}"
        end

        def self.na_parse_payload(payload_json)
            return {} if payload_json.nil? || payload_json.to_s.empty?

            JSON.parse(payload_json)
        end

        def self.na_message_with_warnings(result)
            base_message = result[:message].to_s
            warnings = result[:warnings]
            return base_message unless warnings.is_a?(Array) && !warnings.empty?

            warning_text = warnings.map { |entry| "Warning: #{entry}" }.join(' | ')
            "#{base_message} #{warning_text}"
        end

        def self.na_reload_feature_scripts
            files_to_reload = Dir.glob(File.join(File.dirname(__FILE__), '*.rb')).sort
            reload_count = 0
            error_count = 0
            files_to_reload.each do |file_path|
                load file_path
                reload_count += 1
            rescue StandardError => error
                error_count += 1
                puts "[Na__ToScaleOrthoTextureMaker] Error in #{File.basename(file_path)}: #{error.message}"
            end
            { reload_count: reload_count, error_count: error_count }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Messaging
# -----------------------------------------------------------------------------

        def self.na_push_scene_list
            return unless @na_dialog

            model = Sketchup.active_model
            scene_names = ['Current View']
            scene_names.concat(model.pages.map(&:name)) if model && model.pages
            @na_dialog.execute_script("window.na_setSceneOptions(#{JSON.generate(scene_names)});")
        end

        def self.na_push_status(status_type, message)
            na_call_dialog(@na_dialog, 'na_setStatus', status_type, message)
        end

        def self.na_push_export_status(status_type, message)
            na_call_dialog(@na_dialog, 'na_setExportStatus', status_type, message)
        end

        def self.na_push_settings_status_to(dialog, status_type, message)
            na_call_dialog(dialog, 'na_setSettingsStatus', status_type, message)
        end

        def self.na_call_dialog(dialog, function_name, status_type, message)
            return unless dialog

            dialog.execute_script("window.#{function_name}(#{JSON.generate(status_type)}, #{JSON.generate(message.to_s)});")
        end

# endregion -------------------------------------------------------------------

    end # module Na__ToScaleOrthoTextureMaker__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
