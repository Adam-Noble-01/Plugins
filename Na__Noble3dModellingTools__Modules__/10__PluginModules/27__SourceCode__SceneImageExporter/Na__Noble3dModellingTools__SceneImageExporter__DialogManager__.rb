# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE IMAGE EXPORTER - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SceneImageExporter__DialogManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneImageExporter__DialogManager
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Own the Scene Image Exporter HtmlDialog, build its payload from
#              the model, and route JS callbacks to the state and export modules.
# CREATED    : 2026
#
# DESIGN NOTES:
# - A new dialog is created fresh on each invocation; @na_dialog is nilled on
#   close so callbacks are always registered on the live instance.
# - All dialog assets are inlined via set_html (no external file base URL).
# - Scene ticks and export settings are written straight back to the model
#   dictionary on every change, so nothing is lost if SketchUp is closed
#   without pressing Export.
#
# RUBY -> JS : Na__SceneExporter__ReceivePayload(payload)
#              Na__SceneExporter__ReceiveProgress(status)
#              Na__SceneExporter__ReceiveStatus(message, variant)
# JS -> RUBY : sketchup.na_dialog_ready      / na_refresh_scenes
#              sketchup.na_save_selection    / na_save_settings
#              sketchup.na_choose_folder     / na_open_folder
#              sketchup.na_start_export      / na_cancel_export
#              sketchup.na_js_log
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__SceneImageExporter__DialogManager

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIALOG_TITLE           = 'Na Noble3d Tools : Scene Image Exporter'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__Noble3dModellingTools__SceneImageExporter'.freeze
        NA_DIALOG_WIDTH           = 1180
        NA_DIALOG_HEIGHT          = 820
        NA_DIALOG_MIN_WIDTH       = 900
        NA_DIALOG_MIN_HEIGHT      = 620
        NA_FALLBACK_FOLDER_KEY    = 'last_export_folder'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Show the Scene Image Exporter Dialog
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__ShowDialog
            if @na_dialog && @na_dialog.visible?
                @na_dialog.close
                @na_dialog = nil
            end

            @na_dialog = na_create_dialog
            @na_dialog.set_html(na_render_html)
            na_register_callbacks(@na_dialog)
            @na_dialog.set_on_closed { @na_dialog = nil }
            @na_dialog.show
            @na_dialog.bring_to_front
            @na_dialog
        end
        # ------------------------------------------------------------

        # FUNCTION | Close and Forget the Dialog (Called by the Reload Manager)
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__ResetDialog
            return unless @na_dialog

            @na_dialog.close if @na_dialog.visible?
            @na_dialog = nil
            true
        rescue => error
            puts "[Na__SceneImageExporter] Reset dialog warning: #{error.class}: #{error.message}"
            @na_dialog = nil
            false
        end
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
            layout_path = File.join(__dir__, 'Na__Noble3dModellingTools__SceneImageExporter__UiLayout__.html')
            style_path  = File.join(__dir__, 'Na__Noble3dModellingTools__SceneImageExporter__Styles__.css')
            script_path = File.join(__dir__, 'Na__Noble3dModellingTools__SceneImageExporter__UiBridge__.js')

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

            settings        = Na__SceneImageExporter__ModelState.Na__SceneImageExporter__ReadSettings(model)
            selected_scenes = Na__SceneImageExporter__ModelState.Na__SceneImageExporter__ReadSelectedScenes(model)
            last_export     = Na__SceneImageExporter__ModelState.Na__SceneImageExporter__ReadLastExportSummary(model)

            settings['export_folder'] = na_resolve_default_folder(model, settings['export_folder'])

            scene_rows = model.pages.map.with_index do |page, page_index|
                {
                    'name'        => page.name.to_s,
                    'description' => page.description.to_s,
                    'index'       => page_index,
                    'selected'    => selected_scenes.include?(page.name.to_s)
                }
            end

            width, height = Na__SceneImageExporter__Exporter.Na__SceneImageExporter__ResolveDimensions(
                model.active_view, settings
            )

            {
                'model'       => na_model_info(model),
                'scenes'      => scene_rows,
                'settings'    => settings,
                'choices'     => Na__SceneImageExporter__Presets.Na__SceneImageExporter__ChoiceLists,
                'last_export' => last_export,
                'resolved'    => {
                    'width'            => width,
                    'height'           => height,
                    'sample_file_name' => na_sample_file_name(model, settings)
                },
                'is_running'  => Na__SceneImageExporter__Exporter.Na__SceneImageExporter__IsRunning
            }
        rescue => error
            puts "[Na__SceneImageExporter] Payload build error: #{error.class}: #{error.message}"
            puts error.backtrace.first(6).join("\n") if error.backtrace
            na_empty_payload
        end
        private_class_method :na_build_payload
        # ------------------------------------------------------------

        # HELPER FUNCTION | Summarise the Active Model for the Dialog Header
        # ------------------------------------------------------------
        def self.na_model_info(model)
            model_path = model.path.to_s
            model_name = model_path.empty? ? (model.title.to_s.empty? ? 'Untitled' : model.title.to_s)
                                           : File.basename(model_path, '.skp')

            {
                'name'            => model_name,
                'path'            => model_path,
                'is_saved'        => !model_path.empty?,
                'scene_count'     => model.pages.count,
                'viewport_width'  => model.active_view.vpwidth,
                'viewport_height' => model.active_view.vpheight
            }
        rescue
            { 'name' => 'Untitled', 'path' => '', 'is_saved' => false, 'scene_count' => 0,
              'viewport_width' => 0, 'viewport_height' => 0 }
        end
        private_class_method :na_model_info
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build an Example Output Filename for the Preview Line
        # ------------------------------------------------------------
        def self.na_sample_file_name(model, settings)
            first_page  = model.pages.first
            scene_name  = first_page ? first_page.name.to_s : 'Scene 1'
            model_path  = model.path.to_s
            model_name  = model_path.empty? ? (model.title.to_s.empty? ? 'Untitled' : model.title.to_s)
                                            : File.basename(model_path, '.skp')
            extension   = Na__SceneImageExporter__Presets.Na__SceneImageExporter__ExtensionForFormat(settings['file_format'])

            Na__SceneImageExporter__Exporter.Na__SceneImageExporter__BuildFileName(
                settings['filename_pattern'], model_name, scene_name, 1, extension, Time.now
            )
        rescue => error
            puts "[Na__SceneImageExporter] Sample filename warning: #{error.message}"
            ''
        end
        private_class_method :na_sample_file_name
        # ------------------------------------------------------------

        # HELPER FUNCTION | Empty Payload Used When No Model Is Available
        # ------------------------------------------------------------
        def self.na_empty_payload
            {
                'model'       => { 'name' => 'Untitled', 'path' => '', 'is_saved' => false,
                                   'scene_count' => 0, 'viewport_width' => 0, 'viewport_height' => 0 },
                'scenes'      => [],
                'settings'    => Na__SceneImageExporter__Presets.Na__SceneImageExporter__DefaultSettings,
                'choices'     => Na__SceneImageExporter__Presets.Na__SceneImageExporter__ChoiceLists,
                'last_export' => { 'time' => '', 'count' => 0, 'folder' => '' },
                'resolved'    => { 'width' => 0, 'height' => 0, 'sample_file_name' => '' },
                'is_running'  => false
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

            dialog.add_action_callback('na_refresh_scenes') do |_ctx, _payload|
                na_guard('na_refresh_scenes') do
                    na_push_payload(dialog)
                    na_push_status(dialog, 'Scene list refreshed from the model.', 'info')
                end
            end

            dialog.add_action_callback('na_save_selection') do |_ctx, payload_json|
                na_guard('na_save_selection') { na_handle_save_selection(dialog, payload_json) }
            end

            dialog.add_action_callback('na_save_settings') do |_ctx, payload_json|
                na_guard('na_save_settings') { na_handle_save_settings(dialog, payload_json) }
            end

            dialog.add_action_callback('na_choose_folder') do |_ctx, _payload|
                na_guard('na_choose_folder') { na_handle_choose_folder(dialog) }
            end

            dialog.add_action_callback('na_open_folder') do |_ctx, folder_path|
                na_guard('na_open_folder') { na_open_folder_in_os(folder_path) }
            end

            dialog.add_action_callback('na_start_export') do |_ctx, payload_json|
                na_guard('na_start_export') { na_handle_start_export(dialog, payload_json) }
            end

            dialog.add_action_callback('na_cancel_export') do |_ctx, _payload|
                na_guard('na_cancel_export') do
                    if Na__SceneImageExporter__Exporter.Na__SceneImageExporter__RequestCancel
                        na_push_status(dialog, 'Cancelling after the current scene...', 'warn')
                    else
                        na_push_status(dialog, 'No export is running.', 'info')
                    end
                end
            end

            dialog.add_action_callback('na_js_log') do |_ctx, message|
                puts "[Na__SceneImageExporter][JS] #{message}"
            end
        end
        private_class_method :na_register_callbacks
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Handlers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Persist the Ticked Scene Names to the Model Dictionary
        # ------------------------------------------------------------
        def self.na_handle_save_selection(dialog, payload_json)
            model = Sketchup.active_model
            return unless model

            payload = JSON.parse(payload_json.to_s)
            names   = payload.is_a?(Hash) ? payload['scene_names'] : payload

            Na__SceneImageExporter__ModelState.Na__SceneImageExporter__WriteSelectedScenes(model, names)
        rescue JSON::ParserError
            na_push_status(dialog, 'Invalid scene selection payload.', 'error')
        end
        private_class_method :na_handle_save_selection
        # ------------------------------------------------------------

        # HELPER FUNCTION | Persist the Settings Hash and Echo the Resolved Size
        # ------------------------------------------------------------
        def self.na_handle_save_settings(dialog, payload_json)
            model = Sketchup.active_model
            return unless model

            raw_settings = JSON.parse(payload_json.to_s)
            settings     = na_normalise_settings(raw_settings)

            Na__SceneImageExporter__ModelState.Na__SceneImageExporter__WriteSettings(model, settings)

            width, height = Na__SceneImageExporter__Exporter.Na__SceneImageExporter__ResolveDimensions(
                model.active_view, settings
            )

            na_execute_js(
                dialog,
                'Na__SceneExporter__ReceiveResolved',
                {
                    'width'            => width,
                    'height'           => height,
                    'sample_file_name' => na_sample_file_name(model, settings)
                }
            )
        rescue JSON::ParserError
            na_push_status(dialog, 'Invalid settings payload.', 'error')
        end
        private_class_method :na_handle_save_settings
        # ------------------------------------------------------------

        # HELPER FUNCTION | Open the OS Folder Picker and Store the Chosen Folder
        # ------------------------------------------------------------
        def self.na_handle_choose_folder(dialog)
            model = Sketchup.active_model
            return unless model

            settings   = Na__SceneImageExporter__ModelState.Na__SceneImageExporter__ReadSettings(model)
            start_dir  = na_resolve_default_folder(model, settings['export_folder'])
            chosen_dir = UI.select_directory(
                title:     'Choose the folder for the exported scene images',
                directory: start_dir
            )

            if chosen_dir.nil?
                na_push_status(dialog, 'Folder selection cancelled.', 'info')
                return
            end

            settings['export_folder'] = chosen_dir.to_s
            Na__SceneImageExporter__ModelState.Na__SceneImageExporter__WriteSettings(model, settings)
            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_FALLBACK_FOLDER_KEY, chosen_dir.to_s)

            na_execute_js(dialog, 'Na__SceneExporter__ReceiveFolder', { 'folder' => chosen_dir.to_s })
            na_push_status(dialog, "Export folder set to #{chosen_dir}", 'success')
        end
        private_class_method :na_handle_choose_folder
        # ------------------------------------------------------------

        # HELPER FUNCTION | Validate the Request Then Kick Off the Batch Export
        # ------------------------------------------------------------
        def self.na_handle_start_export(dialog, payload_json)
            model = Sketchup.active_model
            return na_push_status(dialog, 'No active SketchUp model.', 'error') unless model

            payload     = JSON.parse(payload_json.to_s)
            scene_names = Array(payload['scene_names']).map(&:to_s)
            settings    = na_normalise_settings(payload['settings'])

            if scene_names.empty?
                return na_push_status(dialog, 'Tick at least one scene before exporting.', 'warn')
            end

            folder_path = settings['export_folder'].to_s
            if folder_path.empty?
                return na_push_status(dialog, 'Choose an export folder before exporting.', 'warn')
            end

            Na__SceneImageExporter__ModelState.Na__SceneImageExporter__WriteSelectedScenes(model, scene_names)
            Na__SceneImageExporter__ModelState.Na__SceneImageExporter__WriteSettings(model, settings)

            progress_proc = proc { |status_hash| na_push_progress(dialog, status_hash) }

            result = Na__SceneImageExporter__Exporter.Na__SceneImageExporter__StartExport(
                scene_names, settings, folder_path, progress_proc
            )

            na_push_status(dialog, result['message'], result['success'] ? 'info' : 'error') unless result['success']
        rescue JSON::ParserError
            na_push_status(dialog, 'Invalid export payload.', 'error')
        end
        private_class_method :na_handle_start_export
        # ------------------------------------------------------------

        # HELPER FUNCTION | Reveal a Folder in the Host Operating System
        # ------------------------------------------------------------
        def self.na_open_folder_in_os(folder_path)
            clean_path = folder_path.to_s.strip
            return if clean_path.empty?
            return unless File.directory?(clean_path)

            if Sketchup.platform == :platform_win
                system('explorer', clean_path.tr('/', '\\'))
            else
                system('open', clean_path)
            end
        end
        private_class_method :na_open_folder_in_os
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Settings Normalisation
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Merge Incoming Settings Over the Defaults and Coerce Types
        # ------------------------------------------------------------
        def self.na_normalise_settings(raw_settings)
            settings = Na__SceneImageExporter__Presets.Na__SceneImageExporter__DefaultSettings
            return settings unless raw_settings.is_a?(Hash)

            %w[preset_key aspect_mode file_format filename_pattern overwrite_mode export_folder].each do |key|
                settings[key] = raw_settings[key].to_s if raw_settings.key?(key)
            end

            %w[image_height custom_aspect_width custom_aspect_height silhouette_width line_extension_amount].each do |key|
                settings[key] = raw_settings[key].to_i if raw_settings.key?(key)
            end

            %w[jpeg_quality line_scale_factor].each do |key|
                settings[key] = raw_settings[key].to_f if raw_settings.key?(key)
            end

            settings['transparent_background'] = !!raw_settings['transparent_background'] if raw_settings.key?('transparent_background')
            settings['antialias']              = true                                    # <-- Never user-disabled

            if raw_settings['render_overrides'].is_a?(Hash)
                overrides = settings['render_overrides']
                Na__SceneImageExporter__Presets::NA_RENDER_OVERRIDES.each do |entry|
                    state_value = raw_settings['render_overrides'][entry['key']].to_s
                    next unless %w[scene on off].include?(state_value)

                    overrides[entry['key']] = state_value
                end
                settings['render_overrides'] = overrides
            end

            settings['filename_pattern'] = Na__SceneImageExporter__Presets::NA_DEFAULT_FILENAME_PATTERN if settings['filename_pattern'].strip.empty?
            settings
        end
        private_class_method :na_normalise_settings
        # ------------------------------------------------------------

        # HELPER FUNCTION | Pick a Sensible Starting Folder for the OS Picker
        # ------------------------------------------------------------
        def self.na_resolve_default_folder(model, stored_folder)
            candidate = stored_folder.to_s.strip
            return candidate if !candidate.empty? && File.directory?(candidate)

            remembered = Sketchup.read_default(NA_DIALOG_PREFERENCES_KEY, NA_FALLBACK_FOLDER_KEY, '').to_s
            return remembered if !remembered.empty? && File.directory?(remembered)

            model_path = model.path.to_s
            return File.dirname(model_path) unless model_path.empty?

            ''
        rescue
            ''
        end
        private_class_method :na_resolve_default_folder
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Ruby To JavaScript Push Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Push the Full State Payload to the Dialog
        # ------------------------------------------------------------
        def self.na_push_payload(dialog)
            na_execute_js(dialog, 'Na__SceneExporter__ReceivePayload', na_build_payload)
        end
        private_class_method :na_push_payload
        # ------------------------------------------------------------

        # HELPER FUNCTION | Push an Export Progress Update to the Dialog
        # ------------------------------------------------------------
        def self.na_push_progress(dialog, status_hash)
            na_execute_js(dialog, 'Na__SceneExporter__ReceiveProgress', status_hash)
        end
        private_class_method :na_push_progress
        # ------------------------------------------------------------

        # HELPER FUNCTION | Push a Status Bar Message to the Dialog
        # ------------------------------------------------------------
        def self.na_push_status(dialog, message_text, status_variant = 'info')
            return unless dialog

            script = "window.Na__SceneExporter__ReceiveStatus(#{message_text.to_s.to_json}, #{status_variant.to_s.to_json});"
            dialog.execute_script(script)
            nil
        rescue => error
            puts "[Na__SceneImageExporter] Status push warning: #{error.class}: #{error.message}"
            nil
        end
        private_class_method :na_push_status
        # ------------------------------------------------------------

        # HELPER FUNCTION | Call a Named Dialog Function With a JSON Argument
        # ------------------------------------------------------------
        def self.na_execute_js(dialog, function_name, payload_hash)
            return unless dialog

            dialog.execute_script("window.#{function_name}(#{payload_hash.to_json});")
        rescue => error
            puts "[Na__SceneImageExporter] JS push warning (#{function_name}): #{error.class}: #{error.message}"
        end
        private_class_method :na_execute_js
        # ------------------------------------------------------------

        # HELPER FUNCTION | Wrap a Callback Body With Consistent Error Reporting
        # ------------------------------------------------------------
        def self.na_guard(callback_name)
            yield
        rescue => error
            puts "[Na__SceneImageExporter] #{callback_name} error: #{error.class}: #{error.message}"
            puts error.backtrace.first(6).join("\n") if error.backtrace
        end
        private_class_method :na_guard
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneImageExporter__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
