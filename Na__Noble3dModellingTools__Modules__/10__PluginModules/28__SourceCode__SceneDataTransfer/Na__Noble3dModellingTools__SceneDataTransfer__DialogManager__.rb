# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SceneDataTransfer__DialogManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__DialogManager
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Own the Scene Data Transfer HtmlDialog, build its payload from
#              the model, and route JS callbacks to capture, read and rebuild.
# CREATED    : 2026
#
# DESIGN NOTES:
# - A new dialog is created fresh on each invocation; @na_dialog is nilled on
#   close so callbacks are always registered on the live instance.
# - All dialog assets are inlined via set_html (no external file base URL).
# - The decoded source payload is held in @na_source_payload for the life of
#   the dialog, so ticking scenes and pressing Import never re-runs the
#   expensive external model probe.
#
# RUBY -> JS : Na__SceneTransfer__ReceivePayload(payload)
#              Na__SceneTransfer__ReceiveStatus(message, variant)
#              Na__SceneTransfer__ReceiveBusy(is_busy, label)
# JS -> RUBY : sketchup.na_dialog_ready     / na_refresh
#              sketchup.na_capture_model    / na_clear_capture
#              sketchup.na_choose_source    / na_read_source
#              sketchup.na_save_settings    / na_import_scenes
#              sketchup.na_js_log
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__DialogManager

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIALOG_TITLE           = 'Na Noble3d Tools : Scene Data Transfer'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__Noble3dModellingTools__SceneDataTransfer'.freeze
        NA_DIALOG_WIDTH           = 1180
        NA_DIALOG_HEIGHT          = 840
        NA_DIALOG_MIN_WIDTH       = 900
        NA_DIALOG_MIN_HEIGHT      = 640

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Show the Scene Data Transfer Dialog
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__ShowDialog
            if @na_dialog && @na_dialog.visible?
                @na_dialog.close
                @na_dialog = nil
            end

            @na_source_payload = nil
            @na_source_path    = ''

            @na_dialog = na_create_dialog
            @na_dialog.set_html(na_render_html)
            na_register_callbacks(@na_dialog)
            @na_dialog.set_on_closed { na_forget_dialog_state }
            @na_dialog.show
            @na_dialog.bring_to_front
            @na_dialog
        end
        # ------------------------------------------------------------

        # FUNCTION | Close and Forget the Dialog (Called by the Reload Manager)
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__ResetDialog
            return unless @na_dialog

            @na_dialog.close if @na_dialog.visible?
            na_forget_dialog_state
            true
        rescue => error
            puts "[Na__SceneDataTransfer] Reset dialog warning: #{error.class}: #{error.message}"
            na_forget_dialog_state
            false
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Drop Every Cached Reference the Dialog Held
        # ------------------------------------------------------------
        def self.na_forget_dialog_state
            @na_dialog         = nil
            @na_source_payload = nil
            @na_source_path    = ''
            nil
        end
        private_class_method :na_forget_dialog_state
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Construction
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build the HtmlDialog Instance
        # ------------------------------------------------------------
        def self.na_create_dialog
            UI::HtmlDialog.new(
                dialog_title:    NA_DIALOG_TITLE,
                preferences_key: NA_DIALOG_PREFERENCES_KEY,
                style:           UI::HtmlDialog::STYLE_DIALOG,
                width:           NA_DIALOG_WIDTH,
                height:          NA_DIALOG_HEIGHT,
                min_width:       NA_DIALOG_MIN_WIDTH,
                min_height:      NA_DIALOG_MIN_HEIGHT,
                resizable:       true,
                scrollable:      false
            )
        end
        private_class_method :na_create_dialog
        # ------------------------------------------------------------

        # HELPER FUNCTION | Assemble the Dialog HTML With Inlined Assets
        # ------------------------------------------------------------
        def self.na_render_html
            layout_path = File.join(__dir__, 'Na__Noble3dModellingTools__SceneDataTransfer__UiLayout__.html')
            style_path  = File.join(__dir__, 'Na__Noble3dModellingTools__SceneDataTransfer__Styles__.css')
            script_path = File.join(__dir__, 'Na__Noble3dModellingTools__SceneDataTransfer__UiBridge__.js')

            File.read(layout_path)
                .gsub('{{STYLESHEET_CONTENT}}', File.read(style_path))
                .gsub('{{UI_BRIDGE_SCRIPT}}',   File.read(script_path))
        end
        private_class_method :na_render_html
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Payload Construction
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build the Full State Payload for the Dialog
        # ------------------------------------------------------------
        def self.na_build_payload
            model = Sketchup.active_model
            return na_empty_payload unless model

            settings = Na__SceneDataTransfer__ModelState.Na__SceneDataTransfer__ReadSettings(model)

            {
                'model'         => na_model_info(model),
                'local_capture' => Na__SceneDataTransfer__Capture.Na__SceneDataTransfer__ReadLocalCaptureHeader(model),
                'settings'      => settings,
                'choices'       => Na__SceneDataTransfer__Schema.Na__SceneDataTransfer__ChoiceLists,
                'source'        => na_source_block
            }
        rescue => error
            puts "[Na__SceneDataTransfer] Payload build error: #{error.class}: #{error.message}"
            puts error.backtrace.first(6).join("\n") if error.backtrace
            na_empty_payload
        end
        private_class_method :na_build_payload
        # ------------------------------------------------------------

        # HELPER FUNCTION | Summarise the Active Model for the Dialog Header
        # ------------------------------------------------------------
        def self.na_model_info(model)
            model_path = model.path.to_s
            model_name = if model_path.empty?
                             model.title.to_s.empty? ? 'Untitled' : model.title.to_s
                         else
                             File.basename(model_path, '.skp')
                         end

            {
                'name'        => model_name,
                'path'        => model_path,
                'is_saved'    => !model_path.empty?,
                'scene_count' => model.pages.count
            }
        rescue
            { 'name' => 'Untitled', 'path' => '', 'is_saved' => false, 'scene_count' => 0 }
        end
        private_class_method :na_model_info
        # ------------------------------------------------------------

        # HELPER FUNCTION | Describe the Source Model Currently Loaded Into the Dialog
        # ------------------------------------------------------------
        def self.na_source_block
            return { 'loaded' => false, 'path' => @na_source_path.to_s, 'scenes' => [] } unless @na_source_payload

            {
                'loaded' => true,
                'path'   => @na_source_path.to_s,
                'header' => na_header_for(@na_source_payload),
                'scenes' => na_scene_rows(@na_source_payload)
            }
        rescue => error
            puts "[Na__SceneDataTransfer] Source block warning: #{error.message}"
            { 'loaded' => false, 'path' => '', 'scenes' => [] }
        end
        private_class_method :na_source_block
        # ------------------------------------------------------------

        # HELPER FUNCTION | Flatten the Payload Scenes Into Tickable Rows
        # ------------------------------------------------------------
        def self.na_scene_rows(payload)
            Array(payload['scenes']).map do |scene_record|
                domains   = scene_record['domains']   || {}
                use_flags = scene_record['use_flags'] || {}

                {
                    'name'             => scene_record['name'].to_s,
                    'description'      => scene_record['description'].to_s,
                    'index'            => scene_record['index'].to_i,
                    'available'        => domains.keys,
                    'camera_is_active' => use_flags['camera'] != false,
                    'is_two_point'     => ((domains['camera'] || {})['is_2d'] == true)
                }
            end
        end
        private_class_method :na_scene_rows
        # ------------------------------------------------------------

        # HELPER FUNCTION | Derive the Header Summary From a Decoded Payload
        # ------------------------------------------------------------
        def self.na_header_for(payload)
            source = payload['source'] || {}

            {
                'schema_version'    => payload['schema_version'].to_s,
                'captured_at'       => payload['captured_at'].to_s,
                'source_model_name' => source['name'].to_s,
                'sketchup_version'  => source['sketchup_version'].to_s,
                'scene_count'       => Array(payload['scenes']).length,
                'domains_captured'  => Array(payload['domains_captured'])
            }
        end
        private_class_method :na_header_for
        # ------------------------------------------------------------

        # HELPER FUNCTION | Empty Payload Used When No Model Is Available
        # ------------------------------------------------------------
        def self.na_empty_payload
            {
                'model'         => { 'name' => 'Untitled', 'path' => '', 'is_saved' => false, 'scene_count' => 0 },
                'local_capture' => nil,
                'settings'      => Na__SceneDataTransfer__ModelState.Na__SceneDataTransfer__ReadSettings(nil),
                'choices'       => Na__SceneDataTransfer__Schema.Na__SceneDataTransfer__ChoiceLists,
                'source'        => { 'loaded' => false, 'path' => '', 'scenes' => [] }
            }
        end
        private_class_method :na_empty_payload
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Registration
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Register All JS-To-Ruby Action Callbacks
        # ------------------------------------------------------------
        def self.na_register_callbacks(dialog)
            dialog.add_action_callback('na_dialog_ready') do |_ctx, _payload|
                na_guard('na_dialog_ready') { na_push_payload(dialog) }
            end

            dialog.add_action_callback('na_refresh') do |_ctx, _payload|
                na_guard('na_refresh') do
                    na_push_payload(dialog)
                    na_push_status(dialog, 'Refreshed from the model.', 'info')
                end
            end

            dialog.add_action_callback('na_capture_model') do |_ctx, payload_json|
                na_guard('na_capture_model') { na_handle_capture(dialog, payload_json) }
            end

            dialog.add_action_callback('na_clear_capture') do |_ctx, _payload|
                na_guard('na_clear_capture') { na_handle_clear_capture(dialog) }
            end

            dialog.add_action_callback('na_choose_source') do |_ctx, _payload|
                na_guard('na_choose_source') { na_handle_choose_source(dialog) }
            end

            dialog.add_action_callback('na_read_source') do |_ctx, source_path|
                na_guard('na_read_source') { na_handle_read_source(dialog, source_path) }
            end

            dialog.add_action_callback('na_save_settings') do |_ctx, payload_json|
                na_guard('na_save_settings') { na_handle_save_settings(payload_json) }
            end

            dialog.add_action_callback('na_import_scenes') do |_ctx, payload_json|
                na_guard('na_import_scenes') { na_handle_import(dialog, payload_json) }
            end

            dialog.add_action_callback('na_js_log') do |_ctx, message|
                puts "[Na__SceneDataTransfer][JS] #{message}"
            end
        end
        private_class_method :na_register_callbacks
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Handlers - Capture Side
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Capture This Model's Scenes Into Its Embedded Payload
        # ------------------------------------------------------------
        def self.na_handle_capture(dialog, payload_json)
            model = Sketchup.active_model
            return na_push_status(dialog, 'No active SketchUp model.', 'error') unless model

            request = na_parse_json(payload_json)
            domains = Array(request['domains']).map(&:to_s)
            domains = nil if domains.empty?

            na_push_busy(dialog, true, 'Capturing scene data...')
            result = Na__SceneDataTransfer__Capture.Na__SceneDataTransfer__CaptureModel(model, domains)
            na_push_busy(dialog, false, '')

            if result['success']
                Na__SceneDataTransfer__ModelState.Na__SceneDataTransfer__WriteLastCapture(model, result['scene_count'])
            end

            na_push_payload(dialog)
            na_push_status(dialog, result['message'], result['success'] ? 'success' : 'error')
        end
        private_class_method :na_handle_capture
        # ------------------------------------------------------------

        # HELPER FUNCTION | Remove Any Captured Payload From This Model
        # ------------------------------------------------------------
        def self.na_handle_clear_capture(dialog)
            model = Sketchup.active_model
            return na_push_status(dialog, 'No active SketchUp model.', 'error') unless model

            result = Na__SceneDataTransfer__Capture.Na__SceneDataTransfer__ClearModelCapture(model)
            na_push_payload(dialog)
            na_push_status(dialog, result['message'], result['success'] ? 'success' : 'error')
        end
        private_class_method :na_handle_clear_capture
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Handlers - Import Side
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Open the OS File Picker for the Source Model
        # ------------------------------------------------------------
        def self.na_handle_choose_source(dialog)
            model      = Sketchup.active_model
            start_dir  = Na__SceneDataTransfer__ModelState.Na__SceneDataTransfer__RecallSourceFolder(model)
            chosen     = UI.openpanel('Choose the SketchUp model to pull scenes from', start_dir, 'SketchUp Models|*.skp||')

            return na_push_status(dialog, 'Source selection cancelled.', 'info') if chosen.nil?

            na_handle_read_source(dialog, chosen)
        end
        private_class_method :na_handle_choose_source
        # ------------------------------------------------------------

        # HELPER FUNCTION | Probe the Chosen Source Model and Cache Its Payload
        # ------------------------------------------------------------
        def self.na_handle_read_source(dialog, source_path)
            model = Sketchup.active_model
            return na_push_status(dialog, 'No active SketchUp model.', 'error') unless model

            clean_path = source_path.to_s.strip
            return na_push_status(dialog, 'Choose a source model first.', 'warn') if clean_path.empty?

            na_push_busy(dialog, true, "Reading #{File.basename(clean_path)}...")
            result = Na__SceneDataTransfer__Reader.Na__SceneDataTransfer__ReadExternalModel(model, clean_path)
            na_push_busy(dialog, false, '')

            if result['success']
                @na_source_payload = result['payload']
                @na_source_path    = clean_path
                na_persist_source_path(model, clean_path)
            else
                @na_source_payload = nil
                @na_source_path    = clean_path
            end

            na_push_payload(dialog)
            na_push_status(dialog, na_decorate_read_message(result), result['success'] ? 'success' : 'error')
        end
        private_class_method :na_handle_read_source
        # ------------------------------------------------------------

        # HELPER FUNCTION | Rebuild the Ticked Scenes Into This Model
        # ------------------------------------------------------------
        def self.na_handle_import(dialog, payload_json)
            model = Sketchup.active_model
            return na_push_status(dialog, 'No active SketchUp model.', 'error') unless model
            return na_push_status(dialog, 'Read a source model first.', 'warn')  unless @na_source_payload

            request     = na_parse_json(payload_json)
            scene_names = Array(request['scene_names']).map(&:to_s)
            domains     = Array(request['domains']).map(&:to_s)
            suffix      = request['name_suffix'].to_s

            na_push_busy(dialog, true, 'Importing scenes...')
            result = Na__SceneDataTransfer__Rebuilder.Na__SceneDataTransfer__RebuildScenes(
                model, @na_source_payload, scene_names, domains, suffix
            )
            na_push_busy(dialog, false, '')

            if result['success']
                Na__SceneDataTransfer__ModelState.Na__SceneDataTransfer__WriteLastImport(model, result['created'])
            end

            na_push_payload(dialog)
            na_push_status(dialog, result['message'], result['success'] ? 'success' : 'error')
            na_push_warnings(dialog, result['warnings'])
        end
        private_class_method :na_handle_import
        # ------------------------------------------------------------

        # HELPER FUNCTION | Persist the Dialog Settings Hash
        # ------------------------------------------------------------
        def self.na_handle_save_settings(payload_json)
            model = Sketchup.active_model
            return unless model

            settings = na_parse_json(payload_json)
            return if settings.empty?

            Na__SceneDataTransfer__ModelState.Na__SceneDataTransfer__WriteSettings(model, settings)
        end
        private_class_method :na_handle_save_settings
        # ------------------------------------------------------------

        # HELPER FUNCTION | Remember the Chosen Source Path Against This Model
        # ------------------------------------------------------------
        def self.na_persist_source_path(model, source_path)
            settings = Na__SceneDataTransfer__ModelState.Na__SceneDataTransfer__ReadSettings(model)
            settings['source_model_path'] = source_path
            Na__SceneDataTransfer__ModelState.Na__SceneDataTransfer__WriteSettings(model, settings)
        end
        private_class_method :na_persist_source_path
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Message Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Append Probe Diagnostics to the Read Message
        # ------------------------------------------------------------
        # The leaked-definition count is surfaced deliberately. If the probe ever
        # fails to unwind cleanly it must be visible, not silent.
        def self.na_decorate_read_message(result)
            message     = result['message'].to_s
            diagnostics = result['diagnostics']
            return message unless diagnostics.is_a?(Hash)

            leaked = diagnostics['definitions_leaked'].to_i
            return message unless leaked > 0

            "#{message} Note: the probe left #{leaked} component definition(s) behind - please report this."
        end
        private_class_method :na_decorate_read_message
        # ------------------------------------------------------------

        # HELPER FUNCTION | Print Import Warnings to the Ruby Console
        # ------------------------------------------------------------
        def self.na_push_warnings(dialog, warnings)
            entries = Array(warnings)
            return if entries.empty?

            puts "[Na__SceneDataTransfer] Import finished with #{entries.length} warning(s):"
            entries.each { |warning_text| puts "  - #{warning_text}" }

            na_execute_js(dialog, 'Na__SceneTransfer__ReceiveWarnings', entries)
        end
        private_class_method :na_push_warnings
        # ------------------------------------------------------------

        # HELPER FUNCTION | Parse an Incoming JSON Payload Safely
        # ------------------------------------------------------------
        def self.na_parse_json(payload_json)
            parsed = JSON.parse(payload_json.to_s)
            parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
            {}
        end
        private_class_method :na_parse_json
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Ruby To JavaScript Push Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Push the Full State Payload to the Dialog
        # ------------------------------------------------------------
        def self.na_push_payload(dialog)
            na_execute_js(dialog, 'Na__SceneTransfer__ReceivePayload', na_build_payload)
        end
        private_class_method :na_push_payload
        # ------------------------------------------------------------

        # HELPER FUNCTION | Toggle the Dialog's Busy Overlay
        # ------------------------------------------------------------
        def self.na_push_busy(dialog, is_busy, label_text)
            return unless dialog

            dialog.execute_script(
                "window.Na__SceneTransfer__ReceiveBusy(#{is_busy ? 'true' : 'false'}, #{label_text.to_s.to_json});"
            )
            nil
        rescue => error
            puts "[Na__SceneDataTransfer] Busy push warning: #{error.class}: #{error.message}"
            nil
        end
        private_class_method :na_push_busy
        # ------------------------------------------------------------

        # HELPER FUNCTION | Push a Status Bar Message to the Dialog
        # ------------------------------------------------------------
        def self.na_push_status(dialog, message_text, status_variant = 'info')
            return unless dialog

            dialog.execute_script(
                "window.Na__SceneTransfer__ReceiveStatus(#{message_text.to_s.to_json}, #{status_variant.to_s.to_json});"
            )
            nil
        rescue => error
            puts "[Na__SceneDataTransfer] Status push warning: #{error.class}: #{error.message}"
            nil
        end
        private_class_method :na_push_status
        # ------------------------------------------------------------

        # HELPER FUNCTION | Call a Named Dialog Function With a JSON Argument
        # ------------------------------------------------------------
        def self.na_execute_js(dialog, function_name, payload_object)
            return unless dialog

            dialog.execute_script("window.#{function_name}(#{payload_object.to_json});")
        rescue => error
            puts "[Na__SceneDataTransfer] JS push warning (#{function_name}): #{error.class}: #{error.message}"
        end
        private_class_method :na_execute_js
        # ------------------------------------------------------------

        # HELPER FUNCTION | Wrap a Callback Body With Consistent Error Reporting
        # ------------------------------------------------------------
        def self.na_guard(callback_name)
            yield
        rescue => error
            puts "[Na__SceneDataTransfer] #{callback_name} error: #{error.class}: #{error.message}"
            puts error.backtrace.first(6).join("\n") if error.backtrace
        end
        private_class_method :na_guard
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
