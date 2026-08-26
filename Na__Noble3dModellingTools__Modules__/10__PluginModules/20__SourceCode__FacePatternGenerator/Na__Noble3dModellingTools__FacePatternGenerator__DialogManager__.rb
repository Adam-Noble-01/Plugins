# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FACE PATTERN GENERATOR - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__FacePatternGenerator__DialogManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__FacePatternGenerator__DialogManager
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Manage the Face Pattern Generator HtmlDialog, push the selected
#              face payload to the SVG preview, and receive apply requests.
# CREATED    : 2026
#
# DESIGN NOTES:
# - A new dialog is created fresh on each invocation; @na_dialog is nilled on
#   close so callbacks are always registered on the live instance.
# - All pattern generation and SVG preview happens in the dialog JavaScript;
#   Ruby only validates face selection, ferries the face payload, and builds
#   the final geometry (edges or slate component instances).
# - All dialog assets are inlined via set_html (no external file base URL).
#
# RUBY -> JS : Na__FacePattern__SetFaceData(payload)
#              Na__FacePattern__SetStatus(message, success)
# JS -> RUBY : sketchup.na_dialog_ready / na_refresh_face / na_apply_pattern
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__FacePatternGenerator__DialogManager

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIALOG_TITLE           = 'Na Noble3d Tools : Face Pattern Generator'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__Noble3dModellingTools__FacePatternGenerator__Dialog'.freeze
        NA_DIALOG_WIDTH           = 1280
        NA_DIALOG_HEIGHT          = 860
        NA_DIALOG_MIN_WIDTH       = 980
        NA_DIALOG_MIN_HEIGHT      = 680

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Show the Pattern Dialog and Push the Selected Face Payload
        # ------------------------------------------------------------
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

        # HELPER FUNCTION | Assemble the Dialog HTML with Inlined Assets
        # ------------------------------------------------------------
        def self.na_render_html
            layout_path = File.join(__dir__, 'Na__Noble3dModellingTools__FacePatternGenerator__UiLayout__.html')
            style_path  = File.join(__dir__, 'Na__Noble3dModellingTools__FacePatternGenerator__Styles__.css')

            script_paths = [
                File.join(__dir__, '01__SharedJs', 'Na__FacePattern__DynamicUI__.js'),
                File.join(__dir__, '01__SharedJs', 'Na__FacePattern__Viewport__.js'),
                File.join(__dir__, '01__SharedJs', 'Na__FacePattern__Noise__.js'),
                File.join(__dir__, '01__SharedJs', 'Na__FacePattern__RectGeometry__.js'),
                File.join(__dir__, '01__SharedJs', 'Na__FacePattern__PolygonClip__.js'),
                File.join(__dir__, '01__SharedJs', 'Na__FacePattern__RectClip__.js'),
                File.join(__dir__, '01__SharedJs', 'Na__FacePattern__DxfExport__.js'),
                File.join(__dir__, '02__PatternGenerators', 'Na__FacePattern__PatioGenerator__.js'),
                File.join(__dir__, '02__PatternGenerators', 'Na__FacePattern__BrickworkGenerator__.js'),
                File.join(__dir__, '02__PatternGenerators', 'Na__FacePattern__StoneworkGenerator__.js'),
                File.join(__dir__, '02__PatternGenerators', 'Na__FacePattern__ShrubGenerator__.js'),
                File.join(__dir__, '02__PatternGenerators', 'Na__FacePattern__SlateRoofGenerator__.js'),
                File.join(__dir__, '02__PatternGenerators', 'Na__FacePattern__RosemaryRoofGenerator__.js'),
                File.join(__dir__, 'Na__Noble3dModellingTools__FacePatternGenerator__UiConfig__.js'),
                File.join(__dir__, 'Na__Noble3dModellingTools__FacePatternGenerator__SvgPreview__.js'),
                File.join(__dir__, 'Na__Noble3dModellingTools__FacePatternGenerator__AppCore__.js'),
                File.join(__dir__, 'Na__Noble3dModellingTools__FacePatternGenerator__UiBridge__.js')
            ]

            template = File.read(layout_path)
            scripts_blob = script_paths.map { |path| File.read(path) }.join("\n\n")

            template
                .gsub('{{STYLESHEET_CONTENT}}', File.read(style_path))
                .gsub('{{SCRIPTS_CONTENT}}', scripts_blob)
        end
        private_class_method :na_render_html
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Registration
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Register All JS-To-Ruby Action Callbacks
        # ------------------------------------------------------------
        def self.na_register_callbacks(dialog)
            dialog.add_action_callback('na_dialog_ready') do |_ctx, _payload|
                begin
                    na_push_face_payload(dialog, @na_face_payload) if @na_face_payload
                rescue => error
                    puts "[Na__FacePatternGenerator] na_dialog_ready error: #{error.class}: #{error.message}"
                end
            end

            dialog.add_action_callback('na_refresh_face') do |_ctx, _payload|
                begin
                    result = Na__FacePatternGenerator__FaceData.Na__FacePatternGenerator__BuildSelectionPayload
                    if result[:success]
                        @na_face_payload = result[:payload]
                        na_push_face_payload(dialog, @na_face_payload)
                        na_push_status(dialog, 'Face refreshed from current selection.', true)
                    else
                        na_push_status(dialog, result[:message], false)
                    end
                rescue => error
                    puts "[Na__FacePatternGenerator] na_refresh_face error: #{error.class}: #{error.message}"
                    na_push_status(dialog, "Face refresh failed: #{error.message}", false)
                end
            end

            dialog.add_action_callback('na_apply_pattern') do |_ctx, payload_json|
                begin
                    na_handle_apply_pattern(dialog, payload_json)
                rescue => error
                    puts "[Na__FacePatternGenerator] na_apply_pattern error: #{error.class}: #{error.message}"
                    na_push_status(dialog, "Pattern apply failed: #{error.message}", false)
                end
            end

            dialog.add_action_callback('na_js_log') do |_ctx, message|
                puts "[Na__FacePatternGenerator][JS] #{message}"
            end
        end
        private_class_method :na_register_callbacks
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Handlers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Dispatch Apply Request to the Correct Ruby Builder
        # ------------------------------------------------------------
        def self.na_handle_apply_pattern(dialog, payload_json)
            payload      = JSON.parse(payload_json.to_s)
            pattern_type = payload.fetch('pattern_type', '').to_s

            result =
                if pattern_type == 'slate'
                    Na__FacePatternGenerator__SlateBuilder.Na__FacePatternGenerator__ApplySlatePattern(payload)
                elsif pattern_type == 'rosemary'
                    Na__FacePatternGenerator__RosemaryBuilder.Na__FacePatternGenerator__ApplyRosemaryPattern(payload)
                else
                    Na__FacePatternGenerator__GeometryBuilder.Na__FacePatternGenerator__ApplyPolylines(payload)
                end

            na_push_status(dialog, result[:message], result[:success])
        rescue JSON::ParserError
            na_push_status(dialog, 'Invalid payload received from dialog.', false)
        end
        private_class_method :na_handle_apply_pattern
        # ------------------------------------------------------------

        # HELPER FUNCTION | Send the Face Payload to the Dialog JavaScript
        # ------------------------------------------------------------
        def self.na_push_face_payload(dialog, payload)
            dialog.execute_script("window.Na__FacePattern__SetFaceData(#{payload.to_json});")
        end
        private_class_method :na_push_face_payload
        # ------------------------------------------------------------

        # HELPER FUNCTION | Push a Status Message Back to the Dialog
        # ------------------------------------------------------------
        def self.na_push_status(dialog, message_text, success_flag)
            script = "window.Na__FacePattern__SetStatus(#{message_text.to_json}, #{!!success_flag});"
            dialog.execute_script(script)
        end
        private_class_method :na_push_status
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__FacePatternGenerator__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
