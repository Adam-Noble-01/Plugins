# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FACE PATTERN GENERATOR - DIALOG MANAGER
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__FacePatternGenerator__DialogManager

        NA_DIALOG_TITLE = 'Na Noble3d Tools : Face Pattern Generator'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__Noble3dModellingTools__FacePatternGenerator__Dialog'.freeze
        NA_DIALOG_WIDTH = 1280
        NA_DIALOG_HEIGHT = 860
        NA_DIALOG_MIN_WIDTH = 980
        NA_DIALOG_MIN_HEIGHT = 680

        def self.Na__FacePatternGenerator__ShowDialog(face_payload)
            @na_face_payload = face_payload

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

        def self.na_create_dialog
            UI::HtmlDialog.new(
                dialog_title: NA_DIALOG_TITLE,
                preferences_key: NA_DIALOG_PREFERENCES_KEY,
                style: UI::HtmlDialog::STYLE_DIALOG,
                width: NA_DIALOG_WIDTH,
                height: NA_DIALOG_HEIGHT,
                min_width: NA_DIALOG_MIN_WIDTH,
                min_height: NA_DIALOG_MIN_HEIGHT,
                resizable: true,
                scrollable: false
            )
        end
        private_class_method :na_create_dialog

        def self.na_render_html
            template = File.read(File.join(__dir__, 'Na__Noble3dModellingTools__FacePatternGenerator__UiLayout__.html'))
            stylesheet = File.read(File.join(__dir__, 'Na__Noble3dModellingTools__FacePatternGenerator__Styles__.css'))

            script_paths = [
                File.join(__dir__, '01__SharedJs', 'Na__FacePattern__DynamicUI__.js'),
                File.join(__dir__, '01__SharedJs', 'Na__FacePattern__Viewport__.js'),
                File.join(__dir__, '01__SharedJs', 'Na__FacePattern__Noise__.js'),
                File.join(__dir__, '01__SharedJs', 'Na__FacePattern__RectGeometry__.js'),
                File.join(__dir__, '01__SharedJs', 'Na__FacePattern__PolygonClip__.js'),
                File.join(__dir__, '01__SharedJs', 'Na__FacePattern__DxfExport__.js'),
                File.join(__dir__, '02__PatternGenerators', 'Na__FacePattern__PatioGenerator__.js'),
                File.join(__dir__, '02__PatternGenerators', 'Na__FacePattern__BrickworkGenerator__.js'),
                File.join(__dir__, '02__PatternGenerators', 'Na__FacePattern__StoneworkGenerator__.js'),
                File.join(__dir__, '02__PatternGenerators', 'Na__FacePattern__ShrubGenerator__.js'),
                File.join(__dir__, '02__PatternGenerators', 'Na__FacePattern__SlateRoofGenerator__.js'),
                File.join(__dir__, 'Na__Noble3dModellingTools__FacePatternGenerator__UiConfig__.js'),
                File.join(__dir__, 'Na__Noble3dModellingTools__FacePatternGenerator__SvgPreview__.js'),
                File.join(__dir__, 'Na__Noble3dModellingTools__FacePatternGenerator__AppCore__.js'),
                File.join(__dir__, 'Na__Noble3dModellingTools__FacePatternGenerator__UiBridge__.js')
            ]

            scripts_blob = script_paths.map { |path| File.read(path) }.join("\n\n")
            template
                .gsub('{{STYLESHEET_CONTENT}}', stylesheet)
                .gsub('{{SCRIPTS_CONTENT}}', scripts_blob)
        end
        private_class_method :na_render_html

        def self.na_register_callbacks(dialog)
            dialog.add_action_callback('na_dialog_ready') do |_ctx, _payload|
                na_push_face_payload(dialog, @na_face_payload) if @na_face_payload
            end

            dialog.add_action_callback('na_refresh_face') do |_ctx, _payload|
                result = Na__FacePatternGenerator__FaceData.Na__FacePatternGenerator__BuildSelectionPayload
                if result[:success]
                    @na_face_payload = result[:payload]
                    na_push_face_payload(dialog, @na_face_payload)
                    na_push_status(dialog, 'Face refreshed from current selection.', true)
                else
                    na_push_status(dialog, result[:message], false)
                end
            end

            dialog.add_action_callback('na_apply_pattern') do |_ctx, payload_json|
                na_handle_apply_pattern(dialog, payload_json)
            end

            dialog.add_action_callback('na_js_log') do |_ctx, message|
                puts "[Na__FacePatternGenerator][JS] #{message}"
            end
        end
        private_class_method :na_register_callbacks

        def self.na_handle_apply_pattern(dialog, payload_json)
            payload = JSON.parse(payload_json.to_s)
            pattern_type = payload.fetch('pattern_type', '').to_s

            result =
                if pattern_type == 'slate'
                    Na__FacePatternGenerator__SlateBuilder.Na__FacePatternGenerator__ApplySlatePattern(payload)
                else
                    Na__FacePatternGenerator__GeometryBuilder.Na__FacePatternGenerator__ApplyPolylines(payload)
                end

            na_push_status(dialog, result[:message], result[:success])
        rescue JSON::ParserError
            na_push_status(dialog, 'Invalid payload received from dialog.', false)
        rescue => error
            na_push_status(dialog, "Pattern apply failed: #{error.class}: #{error.message}", false)
        end
        private_class_method :na_handle_apply_pattern

        def self.na_push_face_payload(dialog, payload)
            dialog.execute_script("window.Na__FacePattern__SetFaceData(#{payload.to_json});")
        end
        private_class_method :na_push_face_payload

        def self.na_push_status(dialog, message_text, success_flag)
            dialog.execute_script("window.Na__FacePattern__SetStatus(#{message_text.to_s.to_json}, #{!!success_flag});")
        end
        private_class_method :na_push_status
    end
end

# =============================================================================
# END OF FILE
# =============================================================================
