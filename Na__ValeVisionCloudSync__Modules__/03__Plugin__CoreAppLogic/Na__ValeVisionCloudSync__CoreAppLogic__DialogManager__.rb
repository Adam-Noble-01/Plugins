# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__CoreAppLogic__DialogManager__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__DialogManager
# PURPOSE    : Create, render, and manage the HtmlDialog; bridge Ruby <-> JS
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Creates the UI::HtmlDialog with inlined CSS + JS from asset files.
# - Registers named callbacks for sync actions, settings path, and commands.
# - Exposes push methods so other modules can update the UI without holding
#   a dialog reference themselves.
#
# =============================================================================

require 'json'

module Na__ValeVisionCloudSync
    module Na__DialogManager

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        def self.Na__ValeVisionCloudSync__ShowDialog
            if @na_dialog && @na_dialog.visible?
                @na_dialog.bring_to_front
                na_push_project_path_status(@na_dialog)
                return @na_dialog
            end

            @na_dialog = UI::HtmlDialog.new(
                dialog_title:    Na__ConfigLoader.Na__ValeVisionCloudSync__DialogTitle,
                preferences_key: Na__ConfigLoader.Na__ValeVisionCloudSync__DialogPreferencesKey,
                scrollable:      true,
                resizable:       Na__ConfigLoader.Na__ValeVisionCloudSync__DialogResizable,
                width:           Na__ConfigLoader.Na__ValeVisionCloudSync__DialogWidth,
                height:          Na__ConfigLoader.Na__ValeVisionCloudSync__DialogHeight,
                style:           UI::HtmlDialog::STYLE_DIALOG
            )

            @na_dialog.set_html(na_render_dialog_html)
            na_setup_dialog_callbacks(@na_dialog)
            @na_dialog.set_on_closed { @na_dialog = nil }
            @na_dialog.show
            @na_dialog
        end

        def self.Na__ValeVisionCloudSync__DialogVisible
            !!(@na_dialog && @na_dialog.visible?)
        end

        def self.Na__ValeVisionCloudSync__RefreshDialogIfVisible
            return false unless self.Na__ValeVisionCloudSync__DialogVisible

            @na_dialog.set_html(na_render_dialog_html)
            na_push_project_path_status(@na_dialog)
            true
        end

        def self.Na__ValeVisionCloudSync__ResetDialog
            @na_dialog = nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | HTML Rendering
# -----------------------------------------------------------------------------

        def self.na_render_dialog_html
            html_template      = File.read(Na__PathResolver.Na__ValeVisionCloudSync__UiLayoutFilePath)
            stylesheet_content = File.read(Na__PathResolver.Na__ValeVisionCloudSync__UiStylesheetFilePath)
            ui_bridge_script   = File.read(Na__PathResolver.Na__ValeVisionCloudSync__UiBridgeFilePath)
            logo_uri           = na_resolve_logo_file_uri

            html_template
                .gsub('{{DIALOG_TITLE}}',      na_escape_html(Na__ConfigLoader.Na__ValeVisionCloudSync__DialogTitle))
                .gsub('{{LOGO_FILE_URI}}',      logo_uri)
                .gsub('{{STYLESHEET_CONTENT}}', stylesheet_content)
                .gsub('{{UI_BRIDGE_SCRIPT}}',   ui_bridge_script)
        end

        def self.na_resolve_logo_file_uri
            path = Na__PathResolver.Na__ValeVisionCloudSync__BrandLogoFilePath
            return '' unless File.exist?(path)

            forward_path = path.tr('\\', '/').gsub(/^\//, '')
            'file:///' + forward_path.gsub(' ', '%20')
        end

        def self.na_escape_html(raw_text)
            raw_text.to_s
                .gsub('&', '&amp;')
                .gsub('<', '&lt;')
                .gsub('>', '&gt;')
                .gsub('"', '&quot;')
                .gsub("'", '&#39;')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | JS Bridge — Callback Setup
# -----------------------------------------------------------------------------

        def self.na_setup_dialog_callbacks(dialog)
            na_setup_run_command_callback(dialog)
            na_setup_sync_action_callback(dialog)
            na_setup_save_path_override_callback(dialog)
            na_setup_clear_path_override_callback(dialog)
            na_setup_dialog_ready_callback(dialog)
        end

        # HELPER FUNCTION | run_command — routes standard commands (reload etc.)
        # ---------------------------------------------------------------
        def self.na_setup_run_command_callback(dialog)
            dialog.add_action_callback('run_command') do |_ctx, command_id|
                result = na_run_command_safe(command_id)
                na_update_status_element(
                    dialog,
                    result.fetch(:message, ''),
                    result.fetch(:success, false) ? 'success' : 'error'
                )
            end
        end

        # HELPER FUNCTION | na_vvcs_run_sync_action — runs one of the 4 sync ops
        # ---------------------------------------------------------------
        def self.na_setup_sync_action_callback(dialog)
            dialog.add_action_callback('na_vvcs_run_sync_action') do |_ctx, action_id|
                na_handle_sync_action(dialog, action_id.to_s)
            end
        end

        # HELPER FUNCTION | na_vvcs_save_path_override — persists project path
        # ---------------------------------------------------------------
        def self.na_setup_save_path_override_callback(dialog)
            dialog.add_action_callback('na_vvcs_save_path_override') do |_ctx, path_value|
                na_handle_save_path_override(dialog, path_value.to_s.strip)
            end
        end

        # HELPER FUNCTION | na_vvcs_clear_path_override — removes override
        # ---------------------------------------------------------------
        def self.na_setup_clear_path_override_callback(dialog)
            dialog.add_action_callback('na_vvcs_clear_path_override') do |_ctx|
                na_handle_clear_path_override(dialog)
            end
        end

        # HELPER FUNCTION | na_vvcs_dialog_ready — pushes initial state on load
        # ---------------------------------------------------------------
        def self.na_setup_dialog_ready_callback(dialog)
            dialog.add_action_callback('na_vvcs_dialog_ready') do |_ctx|
                na_push_project_path_status(dialog)
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Sync Action Handler
# -----------------------------------------------------------------------------

        def self.na_handle_sync_action(dialog, action_id)
            @na_active_dialog = dialog
            na_update_status_element(dialog, "Running: #{action_id.gsub('_', ' ')}...", 'info')
            na_push_report_to_dialog(dialog, na_build_running_report(action_id))

            result = if defined?(Na__SyncOrchestrator) &&
                        Na__SyncOrchestrator.respond_to?(:Na__ValeVisionCloudSync__RunSyncAction)
                Na__SyncOrchestrator.Na__ValeVisionCloudSync__RunSyncAction(action_id, self)
            else
                { success: false, message: 'Sync orchestrator not yet loaded.', steps: [] }
            end

            variant = result.fetch(:success, false) ? 'success' : 'error'
            na_update_status_element(dialog, result.fetch(:message, 'Done.'), variant)
            na_push_report_to_dialog(dialog, result)
            @na_active_dialog = nil
        end

        def self.na_build_running_report(action_id)
            {
                success: nil,
                running: true,
                action_id: action_id,
                message: 'Working, please wait...',
                steps: []
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Settings Path Handlers
# -----------------------------------------------------------------------------

        def self.na_handle_save_path_override(dialog, path_value)
            model = Sketchup.active_model
            unless model
                na_update_status_element(dialog, 'No active model - open a SketchUp file first.', 'error')
                return
            end

            dict = model.attribute_dictionary(Na__ConfigLoader.Na__ValeVisionCloudSync__ModelDictionaryName, true)
            dict['project_path_override'] = path_value

            na_push_project_path_status(dialog)
            na_update_status_element(dialog, 'Project path override saved.', 'success')
        end

        def self.na_handle_clear_path_override(dialog)
            model = Sketchup.active_model
            unless model
                na_update_status_element(dialog, 'No active model - open a SketchUp file first.', 'error')
                return
            end

            dict = model.attribute_dictionary(Na__ConfigLoader.Na__ValeVisionCloudSync__ModelDictionaryName, true)
            dict.delete_key('project_path_override')

            na_push_project_path_status(dialog)
            na_update_status_element(dialog, 'Project path override cleared.', 'info')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | JS Push — Status, Report, and Path Display
# -----------------------------------------------------------------------------

        def self.Na__ValeVisionCloudSync__PushStatus(status_text, status_variant = 'info')
            return unless self.Na__ValeVisionCloudSync__DialogVisible

            na_update_status_element(@na_dialog, status_text, status_variant)
        end

        def self.Na__ValeVisionCloudSync__PushReport(report_hash)
            return unless self.Na__ValeVisionCloudSync__DialogVisible

            na_push_report_to_dialog(@na_dialog, report_hash)
        end

        # Shim methods callable by Na__SyncOrchestrator when it receives self
        # ---------------------------------------------------------------
        def self.na_push_status(variant, message)
            target = @na_active_dialog || @na_dialog
            return unless target

            na_update_status_element(target, message, variant)
        end

        def self.na_push_report(report_hash)
            target = @na_active_dialog || @na_dialog
            return unless target

            na_push_report_to_dialog(target, report_hash)
        end

        def self.Na__ValeVisionCloudSync__PushProjectPathStatus
            return unless self.Na__ValeVisionCloudSync__DialogVisible

            na_push_project_path_status(@na_dialog)
        end

        def self.na_update_status_element(dialog, status_text, status_variant)
            script = <<~SCRIPT
            (function() {
                var el = document.getElementById('naVvcsStatus');
                if (!el) { return; }
                el.textContent = #{status_text.to_s.to_json};
                el.className = 'naVvcs__Status naVvcs__Status--' + #{status_variant.to_s.to_json};
            })();
            SCRIPT
            dialog.execute_script(script)
        end

        def self.na_push_report_to_dialog(dialog, report_hash)
            report_json = report_hash.to_json
            script      = "window.Na__Vvcs__ReceiveReport && window.Na__Vvcs__ReceiveReport(#{report_json});"
            dialog.execute_script(script)
        end

        def self.na_push_project_path_status(dialog)
            path_data = na_build_path_display_data
            data_json = path_data.to_json
            script    = "window.Na__Vvcs__ReceivePathStatus && window.Na__Vvcs__ReceivePathStatus(#{data_json});"
            dialog.execute_script(script)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Path Display Helpers
# -----------------------------------------------------------------------------

        def self.na_build_path_display_data
            model = Sketchup.active_model
            unless model
                return {
                    model_name:        '(No active model)',
                    model_path:        '',
                    derived_root:      '',
                    override_path:     '',
                    active_path:       '',
                    has_override:      false,
                    img_scene_count:   0
                }
            end

            dict         = model.attribute_dictionary(Na__ConfigLoader.Na__ValeVisionCloudSync__ModelDictionaryName, false)
            override_path = dict ? dict['project_path_override'].to_s : ''
            has_override  = !override_path.empty?

            derived_root = if defined?(Na__ProjectPathMapper) &&
                              Na__ProjectPathMapper.respond_to?(:Na__ValeVisionCloudSync__DeriveProjectRoot)
                Na__ProjectPathMapper.Na__ValeVisionCloudSync__DeriveProjectRoot(model) || ''
            else
                '(ProjectPathMapper not loaded)'
            end

            active_path   = has_override ? override_path : derived_root
            img_count     = na_count_img_scenes(model)

            {
                model_name:       File.basename(model.path.to_s, '.skp'),
                model_path:       model.path.to_s,
                derived_root:     derived_root,
                override_path:    override_path,
                active_path:      active_path,
                has_override:     has_override,
                img_scene_count:  img_count
            }
        end

        def self.na_count_img_scenes(model)
            prefix_regex = Na__ConfigLoader.Na__ValeVisionCloudSync__ScenePrefixRegex
            model.pages.count { |page| page.name.to_s.match?(prefix_regex) }
        rescue
            0
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Command Routing
# -----------------------------------------------------------------------------

        def self.na_run_command_safe(command_id)
            if Na__ValeVisionCloudSync.respond_to?(:Na__ValeVisionCloudSync__RunCommandById)
                Na__ValeVisionCloudSync.Na__ValeVisionCloudSync__RunCommandById(command_id)
            else
                { success: false, message: "Command router unavailable for: #{command_id}" }
            end
        rescue => error
            { success: false, message: "#{error.class}: #{error.message}" }
        end

# endregion -------------------------------------------------------------------

    end # module Na__DialogManager
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
