# =============================================================================
# NA NOBLE3D MODELLING TOOLS - PAINT DEEP NESTED FACES - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__PaintDeepNestedFaces__DialogManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__PaintDeepNestedFaces__DialogManager
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Own the Paint Deep Nested Faces HtmlDialog, hold the observers
#              that keep it live, and run the paint on request.
# CREATED    : 2026
#
# DESIGN NOTES:
# - A fresh dialog is built on each invocation and @na_dialog is dropped on
#   close, so callbacks are always bound to the live instance.
# - All assets are inlined via set_html, matching the other feature modules.
# - Observer callbacks never do work inline. They set a flag and a zero-delay
#   UI timer picks the work up on the next main loop pass, which keeps heavy
#   traversal out of the SketchUp observer stack.
# - Toggle state persists through Sketchup.write_default, so the tool reopens
#   the way it was last left.
#
# RUBY -> JS : Na__PaintFaces__ReceivePayload(payload)
#              Na__PaintFaces__ReceiveMaterial(material)
#              Na__PaintFaces__ReceiveSelection(selection)
#              Na__PaintFaces__ReceiveStatus(message, variant)
# JS -> RUBY : sketchup.na_dialog_ready      / na_refresh
#              sketchup.na_set_deep_nesting  / na_set_isolate_shared
#              sketchup.na_paint_faces       / na_js_log
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__PaintDeepNestedFaces__DialogManager

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIALOG_TITLE           = 'Na Noble3d Tools : Paint Deep Nested Faces'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__Noble3dModellingTools__PaintDeepNestedFaces'.freeze
        NA_DIALOG_WIDTH           = 460
        NA_DIALOG_HEIGHT          = 720
        NA_DIALOG_MIN_WIDTH       = 380
        NA_DIALOG_MIN_HEIGHT      = 560
        NA_OPERATION_NAME         = 'Paint Deep Nested Faces'.freeze
        NA_PREF_DEEP_NESTING      = 'deep_nesting'.freeze
        NA_PREF_ISOLATE_SHARED    = 'isolate_shared'.freeze
        NA_PREVIEW_FACE_LIMIT     = 25_000                                          # <-- Live count stops here; painting is never capped

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Show the Paint Deep Nested Faces Dialog
        # ------------------------------------------------------------
        def self.Na__PaintDeepNestedFaces__ShowDialog
            if @na_dialog && @na_dialog.visible?
                @na_dialog.bring_to_front
                na_push_full_payload
                return @na_dialog
            end

            na_load_settings

            @na_dialog = na_create_dialog
            @na_dialog.set_html(na_render_html)
            na_register_callbacks(@na_dialog)
            @na_dialog.set_on_closed { na_teardown_dialog_state }
            @na_dialog.show
            @na_dialog.bring_to_front

            na_attach_observers(Sketchup.active_model)
            @na_dialog
        end
        # ------------------------------------------------------------

        # FUNCTION | Close and Forget the Dialog (Called by the Reload Manager)
        # ------------------------------------------------------------
        def self.Na__PaintDeepNestedFaces__ResetDialog
            return unless @na_dialog

            @na_dialog.close if @na_dialog.visible?
            na_teardown_dialog_state
            true
        rescue => error
            puts "[Na__PaintDeepNestedFaces] Reset dialog warning: #{error.class}: #{error.message}"
            na_teardown_dialog_state
            false
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Detach Observers and Drop Every Cached Reference
        # ------------------------------------------------------------
        def self.na_teardown_dialog_state
            na_detach_observers
            @na_dialog         = nil
            @na_refresh_queued = false
            nil
        end
        # ------------------------------------------------------------

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

        # HELPER FUNCTION | Assemble the Dialog HTML With Inlined Assets
        # ------------------------------------------------------------
        def self.na_render_html
            layout_path = File.join(__dir__, 'Na__Noble3dModellingTools__PaintDeepNestedFaces__UiLayout__.html')
            style_path  = File.join(__dir__, 'Na__Noble3dModellingTools__PaintDeepNestedFaces__Styles__.css')
            script_path = File.join(__dir__, 'Na__Noble3dModellingTools__PaintDeepNestedFaces__UiBridge__.js')

            File.read(layout_path)
                .gsub('{{STYLESHEET_CONTENT}}', File.read(style_path))
                .gsub('{{UI_BRIDGE_SCRIPT}}',   File.read(script_path))
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Observer Management
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Attach the Materials and Selection Observers
        # ------------------------------------------------------------
        def self.na_attach_observers(model)
            return unless model

            unless @na_materials_observer
                @na_materials_observer = Na__PaintDeepNestedFaces__MaterialsObserver.new
                model.materials.add_observer(@na_materials_observer)
            end

            unless @na_selection_observer
                @na_selection_observer = Na__PaintDeepNestedFaces__SelectionObserver.new
                model.selection.add_observer(@na_selection_observer)
            end

            @na_observed_model = model
        rescue => error
            puts "[Na__PaintDeepNestedFaces] Observer attach failed: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Detach and Discard Both Observers
        # ------------------------------------------------------------
        def self.na_detach_observers
            model = @na_observed_model || Sketchup.active_model

            if model
                model.materials.remove_observer(@na_materials_observer) if @na_materials_observer
                model.selection.remove_observer(@na_selection_observer) if @na_selection_observer
            end

            @na_materials_observer = nil
            @na_selection_observer = nil
            @na_observed_model     = nil
        rescue => error
            puts "[Na__PaintDeepNestedFaces] Observer detach warning: #{error.class}: #{error.message}"
            @na_materials_observer = nil
            @na_selection_observer = nil
            @na_observed_model     = nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Handle a Materials Tray Change Reported by the Observer
        # ------------------------------------------------------------
        def self.Na__PaintDeepNestedFaces__DialogManager__HandleMaterialChanged
            na_queue_refresh
        end
        # ------------------------------------------------------------

        # FUNCTION | Handle a Selection Change Reported by the Observer
        # ------------------------------------------------------------
        def self.Na__PaintDeepNestedFaces__DialogManager__HandleSelectionChanged
            na_queue_refresh
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Defer a Refresh Onto the Next Main Loop Pass
        # ------------------------------------------------------------
        # Observer callbacks fire mid-operation and can fire many times in a
        # burst. Coalescing them onto a single zero-delay timer keeps the walk
        # out of the observer stack and collapses the burst into one update.
        # ------------------------------------------------------------
        def self.na_queue_refresh
            return unless @na_dialog && @na_dialog.visible?
            return if @na_refresh_queued

            @na_refresh_queued = true
            UI.start_timer(0, false) do
                @na_refresh_queued = false
                na_push_full_payload
            end
        rescue => error
            @na_refresh_queued = false
            puts "[Na__PaintDeepNestedFaces] Refresh queue warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Callbacks
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Register Every JS to Ruby Action Callback
        # ------------------------------------------------------------
        def self.na_register_callbacks(dialog)
            dialog.add_action_callback('na_dialog_ready') do |_context|
                na_push_full_payload
            end

            dialog.add_action_callback('na_refresh') do |_context|
                na_push_full_payload
                na_push_status('Refreshed from the model.', 'info')
            end

            dialog.add_action_callback('na_set_deep_nesting') do |_context, value_json|
                @na_deep_nesting = na_parse_boolean(value_json)
                Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_DEEP_NESTING, @na_deep_nesting)
                na_push_selection_summary
            end

            dialog.add_action_callback('na_set_isolate_shared') do |_context, value_json|
                @na_isolate_shared = na_parse_boolean(value_json)
                Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_ISOLATE_SHARED, @na_isolate_shared)
                na_push_selection_summary
            end

            dialog.add_action_callback('na_paint_faces') do |_context|
                na_handle_paint_request
            end

            dialog.add_action_callback('na_js_log') do |_context, message|
                puts "[Na__PaintDeepNestedFaces][JS] #{message}"
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Run the Paint and Report the Outcome
        # ------------------------------------------------------------
        def self.na_handle_paint_request
            result = Na__PaintDeepNestedFaces.Na__PaintDeepNestedFaces__PaintCurrentSelection(
                @na_deep_nesting,
                @na_isolate_shared
            )

            na_push_status(result[:message], result[:success] ? 'success' : 'warn')
            na_push_full_payload
        rescue => error
            na_push_status("Paint failed: #{error.class}: #{error.message}", 'warn')
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Payload Construction and Push Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Push the Complete Dialog State
        # ------------------------------------------------------------
        def self.na_push_full_payload
            na_follow_active_model
            na_execute_js('Na__PaintFaces__ReceivePayload', na_build_payload)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Move the Observers If the Active Model Has Changed
        # ------------------------------------------------------------
        # Opening a different model leaves the observers watching the old one,
        # so the swatch and the face count would quietly go stale. Re-binding
        # on refresh keeps the dialog useful across a model switch.
        # ------------------------------------------------------------
        def self.na_follow_active_model
            model = Sketchup.active_model
            return unless model
            return if @na_observed_model && @na_observed_model == model

            na_detach_observers
            na_attach_observers(model)
        rescue => error
            puts "[Na__PaintDeepNestedFaces] Model follow warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Push Only the Selection Summary
        # ------------------------------------------------------------
        def self.na_push_selection_summary
            na_execute_js('Na__PaintFaces__ReceiveSelection', na_build_selection_summary)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Push a Status Line to the Dialog Footer
        # ------------------------------------------------------------
        def self.na_push_status(message_text, variant)
            return unless @na_dialog && @na_dialog.visible?

            script = format(
                'if (typeof Na__PaintFaces__ReceiveStatus === "function") { Na__PaintFaces__ReceiveStatus(%s, %s); }',
                JSON.generate(message_text.to_s),
                JSON.generate(variant.to_s)
            )
            @na_dialog.execute_script(script)
        rescue => error
            puts "[Na__PaintDeepNestedFaces] Status push warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Complete State Payload
        # ------------------------------------------------------------
        def self.na_build_payload
            {
                'material'  => Na__PaintDeepNestedFaces__MaterialProbe
                               .Na__PaintDeepNestedFaces__MaterialProbe__DescribeCurrent,
                'selection' => na_build_selection_summary,
                'settings'  => {
                    'deep_nesting'   => !!@na_deep_nesting,
                    'isolate_shared' => !!@na_isolate_shared
                }
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Walk the Selection and Summarise What Would Be Painted
        # ------------------------------------------------------------
        def self.na_build_selection_summary
            model = Sketchup.active_model
            return na_empty_selection_summary unless model

            selection = model.selection
            return na_empty_selection_summary if selection.empty?

            collected = Na__PaintDeepNestedFaces__FaceCollector
                        .Na__PaintDeepNestedFaces__FaceCollector__Collect(
                            selection, @na_deep_nesting, false, NA_PREVIEW_FACE_LIMIT
                        )

            na_selection_summary_from_stats(collected[:stats], selection.count)
        rescue => error
            puts "[Na__PaintDeepNestedFaces] Selection summary warning: #{error.class}: #{error.message}"
            na_empty_selection_summary
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Convert Collector Statistics Into Dialog Fields
        # ------------------------------------------------------------
        def self.na_selection_summary_from_stats(stats, selected_count)
            {
                'has_selection'          => true,
                'selected_count'         => selected_count,
                'face_count'             => stats[:face_count],
                'direct_face_count'      => stats[:direct_face_count],
                'container_count'        => stats[:container_count],
                'deepest_level'          => stats[:deepest_level],
                'locked_container_count' => stats[:locked_container_count],
                'skipped_container_count' => stats[:skipped_nested_container_count],
                'shared_definition_count' => stats[:shared_definition_count],
                'other_instance_count'   => stats[:other_instance_count],
                'limit_reached'          => stats[:limit_reached],
                'preview_limit'          => NA_PREVIEW_FACE_LIMIT
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Summary Used When Nothing Is Selected
        # ------------------------------------------------------------
        def self.na_empty_selection_summary
            {
                'has_selection'          => false,
                'selected_count'         => 0,
                'face_count'             => 0,
                'direct_face_count'      => 0,
                'container_count'        => 0,
                'deepest_level'          => 0,
                'locked_container_count' => 0,
                'skipped_container_count' => 0,
                'shared_definition_count' => 0,
                'other_instance_count'   => 0,
                'limit_reached'          => false,
                'preview_limit'          => NA_PREVIEW_FACE_LIMIT
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Call a Named JS Function With a JSON Payload
        # ------------------------------------------------------------
        def self.na_execute_js(function_name, payload_hash)
            return unless @na_dialog && @na_dialog.visible?

            script = format(
                'if (typeof %s === "function") { %s(%s); }',
                function_name,
                function_name,
                JSON.generate(payload_hash)
            )
            @na_dialog.execute_script(script)
        rescue => error
            puts "[Na__PaintDeepNestedFaces] Push warning for #{function_name}: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Settings Persistence
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Read the Persisted Toggle State
        # ------------------------------------------------------------
        # Deep nesting is the documented default for this tool, so an absent
        # preference resolves to true rather than false.
        # ------------------------------------------------------------
        def self.na_load_settings
            @na_deep_nesting   = na_parse_boolean(
                Sketchup.read_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_DEEP_NESTING, true)
            )
            @na_isolate_shared = na_parse_boolean(
                Sketchup.read_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_ISOLATE_SHARED, false)
            )
        rescue => error
            puts "[Na__PaintDeepNestedFaces] Settings read warning: #{error.class}: #{error.message}"
            @na_deep_nesting   = true
            @na_isolate_shared = false
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Coerce Any Stored or Posted Value Into a Boolean
        # ------------------------------------------------------------
        def self.na_parse_boolean(raw_value)
            return raw_value if raw_value == true || raw_value == false

            %w[true 1].include?(raw_value.to_s.strip.downcase)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PaintDeepNestedFaces__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
