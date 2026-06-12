# =============================================================================
# NA NOBLE3D MODELLING TOOLS - PNG TO LINEWORK - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__PngToLinework__DialogManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__PngToLinework__DialogManager
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Manage the PNG To Linework HtmlDialog, push the source image as
#              a base64 data URI, and receive traced polylines for building.
# CREATED    : 2026
#
# DESIGN NOTES:
# - A new dialog is created fresh on each invocation; @na_dialog is nilled on
#   close so callbacks are always registered on the live instance.
# - All raster decoding and tracing happens in the dialog's JavaScript (canvas)
#   because SketchUp Ruby has no PNG decoder; Ruby only validates, ferries the
#   image bytes, and builds the final geometry.
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__PngToLinework__DialogManager

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIALOG_TITLE           = 'Na Noble3d Tools : PNG To Linework'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__Noble3dModellingTools__PngToLinework__Dialog'.freeze
        NA_DIALOG_WIDTH           = 1180
        NA_DIALOG_HEIGHT          = 780
        NA_DIALOG_MIN_WIDTH       = 900
        NA_DIALOG_MIN_HEIGHT      = 620

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Show the Trace Dialog and Push the Selected Image
        # ------------------------------------------------------------
        def self.Na__PngToLinework__DialogManager__ShowDialog(image_payload)
            if @na_dialog && @na_dialog.visible?
                @na_dialog.close
                @na_dialog = nil
            end

            @na_dialog = na_create_dialog
            @na_dialog.set_html(na_render_html)
            na_register_callbacks(@na_dialog)
            @na_dialog.set_on_closed { @na_dialog = nil }
            @na_pending_image = image_payload
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
        # ------------------------------------------------------------

        # HELPER FUNCTION | Assemble the Dialog HTML with Inlined Assets
        # ------------------------------------------------------------
        def self.na_render_html
            layout_path  = File.join(__dir__, 'Na__Noble3dModellingTools__PngToLinework__UiLayout__.html')
            style_path   = File.join(__dir__, 'Na__Noble3dModellingTools__PngToLinework__Styles__.css')
            trace_path   = File.join(__dir__, 'Na__Noble3dModellingTools__PngToLinework__TraceEngine__.js')
            preview_path = File.join(__dir__, 'Na__Noble3dModellingTools__PngToLinework__SvgPreview__.js')
            bridge_path  = File.join(__dir__, 'Na__Noble3dModellingTools__PngToLinework__UiBridge__.js')

            template = File.read(layout_path)
            template
                .gsub('{{STYLESHEET_CONTENT}}',   File.read(style_path))
                .gsub('{{TRACE_ENGINE_SCRIPT}}',  File.read(trace_path))
                .gsub('{{SVG_PREVIEW_SCRIPT}}',   File.read(preview_path))
                .gsub('{{UI_BRIDGE_SCRIPT}}',     File.read(bridge_path))
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Registration
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Register All JS-To-Ruby Action Callbacks
        # ------------------------------------------------------------
        def self.na_register_callbacks(dialog)
            dialog.add_action_callback('na_dialog_ready') do |_ctx, _param|
                begin
                    na_push_pending_image(dialog)
                rescue => error
                    puts "[Na__PngToLinework] na_dialog_ready error: #{error.class}: #{error.message}"
                end
            end

            dialog.add_action_callback('na_choose_png') do |_ctx, _param|
                begin
                    na_handle_choose_png(dialog)
                rescue => error
                    puts "[Na__PngToLinework] na_choose_png error: #{error.class}: #{error.message}"
                    UI.messagebox("PNG To Linework: file selection error\n#{error.message}")
                end
            end

            dialog.add_action_callback('na_create_linework') do |_ctx, payload_json|
                begin
                    na_handle_create_linework(dialog, payload_json)
                rescue => error
                    puts "[Na__PngToLinework] na_create_linework error: #{error.class}: #{error.message}"
                    na_push_status(dialog, "Create failed: #{error.message}", false)
                end
            end

            dialog.add_action_callback('na_js_log') do |_ctx, message|
                puts "[Na__PngToLinework][JS] #{message}"
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Handlers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Push the Image Selected Before the Dialog Opened
        # ------------------------------------------------------------
        def self.na_push_pending_image(dialog)
            return unless @na_pending_image

            na_push_image_to_dialog(dialog, @na_pending_image)
            @na_pending_image = nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Let the User Pick a Different PNG from the Dialog
        # ------------------------------------------------------------
        def self.na_handle_choose_png(dialog)
            image_payload = Na__PngToLinework.Na__PngToLinework__PickAndValidatePng
            return unless image_payload

            na_push_image_to_dialog(dialog, image_payload)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Send the Image Payload to the Dialog JavaScript
        # ------------------------------------------------------------
        def self.na_push_image_to_dialog(dialog, image_payload)
            payload_json = {
                dataUri:     image_payload[:data_uri],
                fileName:    image_payload[:file_name],
                pixelWidth:  image_payload[:pixel_width],
                pixelHeight: image_payload[:pixel_height]
            }.to_json

            dialog.execute_script("window.Na__PngToLinework__SetSourceImage(#{payload_json});")
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Component and Activate the Placement Tool
        # ------------------------------------------------------------
        def self.na_handle_create_linework(dialog, payload_json)
            payload   = JSON.parse(payload_json)
            polylines = payload['polylines']
            plane     = payload['plane'].to_s
            base_name = payload['fileName'].to_s.sub(/\.png\z/i, '')
            base_name = 'PngLinework' if base_name.empty?

            model = Sketchup.active_model
            model.select_tool(nil)                                            # <-- Ends any pending placement before starting anew

            component_name = "Na__PngLinework__#{base_name}__#{Time.now.strftime('%H%M%S')}"
            result = Na__PngToLinework__GeometryBuilder.Na__PngToLinework__BuildLineworkComponent(
                polylines, plane, component_name
            )

            unless result[:success]
                na_push_status(dialog, result[:message], false)
                return
            end

            model.select_tool(Na__PngToLinework::Na__PngToLinework__PlacementTool.new(result[:instance]))
            na_push_status(dialog, "#{result[:message]} Click in the model to place (5mm snap), ESC to cancel.", true)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Push a Status Message Back to the Dialog
        # ------------------------------------------------------------
        def self.na_push_status(dialog, message_text, success_flag)
            script = "window.Na__PngToLinework__SetStatus(#{message_text.to_json}, #{!!success_flag});"
            dialog.execute_script(script)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PngToLinework__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
