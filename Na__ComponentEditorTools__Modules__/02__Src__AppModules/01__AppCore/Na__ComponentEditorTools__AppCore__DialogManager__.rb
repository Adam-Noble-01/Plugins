# =============================================================================
# NA COMPONENT EDITOR TOOLS - APPCORE DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__AppCore__DialogManager__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__DialogManager
# PURPOSE    : Own HtmlDialog lifecycle and route JS callback actions to systems
# CREATED    : 2026
#
# =============================================================================

module Na__ComponentEditorTools
    module Na__DialogManager

# -----------------------------------------------------------------------------
# REGION | Dialog State
# -----------------------------------------------------------------------------

        @na_dialog = nil
        @na_selection_observer = nil
        @na_status_message = 'Ready.'
        @na_status_variant = 'info'
        @na_active_tab_id = 'overview'
        @na_current_selection_key = nil

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__ShowDialog
            if @na_dialog && @na_dialog.visible?
                @na_dialog.bring_to_front
                self.Na__ComponentEditorTools__BuildAndPushPayload
                return @na_dialog
            end

            @na_dialog = UI::HtmlDialog.new(self.Na__ComponentEditorTools__DialogOptions)

            ui_layout_path = Na__PathResolver.Na__ComponentEditorTools__UiLayoutFilePath
            if File.exist?(ui_layout_path)
                @na_dialog.set_file(ui_layout_path)
            else
                @na_dialog.set_html(self.Na__ComponentEditorTools__FallbackHtml)
            end

            self.Na__ComponentEditorTools__BindCallbacks(@na_dialog)
            @na_dialog.set_on_closed { @na_dialog = nil }
            @na_dialog.show

            self.Na__ComponentEditorTools__AttachSelectionObserverIfNeeded
            self.Na__ComponentEditorTools__BuildAndPushPayload
            self.Na__ComponentEditorTools__PushActiveTab
            @na_dialog
        rescue => error
            UI.messagebox("Na__ComponentEditorTools\n\n#{error.class}: #{error.message}")
            nil
        end

        def self.Na__ComponentEditorTools__DialogHandle
            @na_dialog
        end

        def self.Na__ComponentEditorTools__HandleSelectionChanged
            selected_key = Na__SelectionInspector.Na__ComponentEditorTools__SelectedInstanceKey
            return if selected_key.nil? && @na_current_selection_key
            return if selected_key == @na_current_selection_key

            self.Na__ComponentEditorTools__BuildAndPushPayload
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public UI Sync
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__SetActiveTab(active_tab_id)
            return if active_tab_id.nil?

            @na_active_tab_id = active_tab_id.to_s
            @na_active_tab_id = Na__ComponentEditorTools::NA_DEFAULT_ACTIVE_TAB if @na_active_tab_id.empty?
            self.Na__ComponentEditorTools__PushActiveTab
        end

        def self.Na__ComponentEditorTools__PushStatus(message_text, status_variant = 'info')
            @na_status_message = message_text.to_s
            @na_status_variant = status_variant.to_s.empty? ? 'info' : status_variant.to_s

            Na__UiBridge.Na__ComponentEditorTools__ExecuteJsonFunction(
                @na_dialog,
                'Na__ComponentEditorTools__ReceiveStatus',
                {
                    message: @na_status_message,
                    variant: @na_status_variant
                }
            )
        end

        def self.Na__ComponentEditorTools__BuildAndPushPayload
            selected_key = Na__SelectionInspector.Na__ComponentEditorTools__SelectedInstanceKey
            @na_current_selection_key = selected_key if selected_key

            payload_hash = Na__SelectionInspector.Na__ComponentEditorTools__BuildPayload(
                @na_status_message,
                @na_status_variant,
                @na_active_tab_id
            )

            Na__UiBridge.Na__ComponentEditorTools__ExecuteJsonFunction(
                @na_dialog,
                'Na__ComponentEditorTools__ReceivePayload',
                payload_hash
            )
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Binding
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__BindCallbacks(dialog)
            callback_registry = {
                'na_componenteditortools_request_selection' => proc {
                    self.Na__ComponentEditorTools__BuildAndPushPayload
                },
                'na_componenteditortools_set_active_tab' => proc { |tab_id|
                    self.Na__ComponentEditorTools__SetActiveTab(tab_id)
                },
                'na_componenteditortools_apply_basic_fields' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    result = Na__MetadataEditor.Na__ComponentEditorTools__ApplyBasicFields(payload_hash)
                    self.Na__ComponentEditorTools__HandleActionResult(result)
                },
                'na_componenteditortools_update_component' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    result = Na__MetadataEditor.Na__ComponentEditorTools__UpdateComponent(payload_hash)
                    self.Na__ComponentEditorTools__HandleActionResult(result)
                },
                'na_componenteditortools_set_attribute' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    result = Na__MetadataEditor.Na__ComponentEditorTools__SetAttribute(payload_hash)
                    self.Na__ComponentEditorTools__HandleActionResult(result)
                },
                'na_componenteditortools_delete_attribute' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    result = Na__MetadataEditor.Na__ComponentEditorTools__DeleteAttribute(payload_hash)
                    self.Na__ComponentEditorTools__HandleActionResult(result)
                },
                'na_componenteditortools_refresh_thumbnail' => proc {
                    result = Na__ThumbnailTools.Na__ComponentEditorTools__RefreshThumbnailFromCurrentView
                    self.Na__ComponentEditorTools__HandleActionResult(result)
                },
                'na_componenteditortools_capture_viewport_png' => proc {
                    result = Na__ThumbnailTools.Na__ComponentEditorTools__CaptureViewportPng
                    self.Na__ComponentEditorTools__HandleActionResult(result)
                },
                'na_componenteditortools_reload_plugin' => proc {
                    self.Na__ComponentEditorTools__HandleReloadRequest
                }
            }

            Na__UiBridge.Na__ComponentEditorTools__RegisterCallbacks(dialog, callback_registry)
        end

        def self.Na__ComponentEditorTools__HandleActionResult(result_hash)
            success_flag = self.Na__ComponentEditorTools__ResultValue(result_hash, :success)
            message_text = self.Na__ComponentEditorTools__ResultValue(result_hash, :message)
            status_variant = success_flag ? 'success' : 'error'

            self.Na__ComponentEditorTools__PushStatus(message_text, status_variant)
            self.Na__ComponentEditorTools__PushRenderPreview(result_hash)
        end

        def self.Na__ComponentEditorTools__HandleReloadRequest
            dialog_reference = @na_dialog
            active_tab_id = @na_active_tab_id

            reload_result = Na__ComponentEditorTools.Na__ComponentEditorTools__ReloadPluginData(dialog_reference, active_tab_id)
            return if reload_result[:success]

            self.Na__ComponentEditorTools__PushStatus(reload_result[:message], 'error')
            self.Na__ComponentEditorTools__BuildAndPushPayload
        end

        def self.Na__ComponentEditorTools__ResultValue(result_hash, key_name)
            return nil unless result_hash.is_a?(Hash)

            result_hash[key_name] || result_hash[key_name.to_s]
        end

        def self.Na__ComponentEditorTools__PushRenderPreview(result_hash)
            preview_path = self.Na__ComponentEditorTools__ResultValue(result_hash, :visible_view_render_path)
            return if preview_path.to_s.empty?
            return unless defined?(Na__ThumbnailTools)

            Na__UiBridge.Na__ComponentEditorTools__ExecuteJsonFunction(
                @na_dialog,
                'Na__ComponentEditorTools__ReceiveRenderPreview',
                {
                    current_thumbnail_preview_path: preview_path,
                    current_thumbnail_preview_uri: Na__ThumbnailTools.Na__ComponentEditorTools__FilePathToFileUri(preview_path),
                    current_thumbnail_preview_source: 'visible_viewport'
                }
            )
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__AttachSelectionObserverIfNeeded
            return if @na_selection_observer

            active_model = Sketchup.active_model
            return unless active_model

            @na_selection_observer = Na__ComponentEditorTools__SelectionObserver.new
            active_model.selection.add_observer(@na_selection_observer)
        rescue => error
            puts "[Na__ComponentEditorTools] Selection observer attach warning: #{error.class}: #{error.message}"
        end

        def self.Na__ComponentEditorTools__PushActiveTab
            Na__UiBridge.Na__ComponentEditorTools__ExecuteJsonFunction(
                @na_dialog,
                'Na__ComponentEditorTools__SetActiveTab',
                {
                    active_tab: @na_active_tab_id
                }
            )
        end

        def self.Na__ComponentEditorTools__DialogOptions
            {
                dialog_title: Na__ComponentEditorTools::NA_DIALOG_TITLE,
                preferences_key: Na__ComponentEditorTools::NA_DIALOG_PREFERENCES_KEY,
                scrollable: true,
                resizable: true,
                width: 980,
                height: 820,
                min_width: 760,
                min_height: 560,
                style: UI::HtmlDialog::STYLE_DIALOG
            }
        end

        def self.Na__ComponentEditorTools__FallbackHtml
            <<~HTML
            <!doctype html>
            <html lang="en">
            <head>
                <meta charset="utf-8">
                <title>Na Component Editor Tools</title>
            </head>
            <body>
                <h2>Na Component Editor Tools</h2>
                <p>UI layout file was not found.</p>
            </body>
            </html>
            HTML
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
