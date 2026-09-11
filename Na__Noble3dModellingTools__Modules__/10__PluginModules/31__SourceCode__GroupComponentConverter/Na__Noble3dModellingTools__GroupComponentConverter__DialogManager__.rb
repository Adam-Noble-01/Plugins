# =============================================================================
# NA NOBLE3D MODELLING TOOLS - GROUP / COMPONENT CONVERTER - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__GroupComponentConverter__DialogManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__GroupComponentConverter__DialogManager
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Own the converter HtmlDialog, keep the selection report and
#              conversion preview live, persist the switches and toggles, and
#              run the conversion on confirm
# CREATED    : 2026
#
# DESIGN NOTES:
# - A fresh dialog is built on each invocation and @na_dialog is dropped on
#   close, so callbacks are always bound to the live instance.
# - All assets are inlined via set_html, matching the other feature modules.
# - Observer callbacks never do work inline. They set a flag and a zero-delay
#   UI timer picks the work up on the next main loop pass.
# - Every scan simulates both directions at both scopes, so flipping a switch
#   in the dialog redraws instantly. Toggles change the plan, so they post
#   back and trigger a rescan.
# - Switch and toggle state persists through Sketchup.write_default.
#
# RUBY -> JS : Na__GroupComponentConverter__ReceivePayload(payload)
#              Na__GroupComponentConverter__ReceiveSelection(selection)
#              Na__GroupComponentConverter__ReceiveStatus(message, variant)
# JS -> RUBY : sketchup.na_dialog_ready / na_refresh / na_set_options
#              sketchup.na_convert      / na_js_log
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__GroupComponentConverter__DialogManager

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIALOG_TITLE           = 'Na Noble3d Tools : Group / Component Converter'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__Noble3dModellingTools__GroupComponentConverter'.freeze
        NA_DIALOG_WIDTH           = 500
        NA_DIALOG_HEIGHT          = 900
        NA_DIALOG_MIN_WIDTH       = 420
        NA_DIALOG_MIN_HEIGHT      = 600
        NA_PREF_DIRECTION         = 'direction'.freeze
        NA_PREF_SCOPE             = 'scope'.freeze
        NA_PREF_MERGE_COMMON      = 'merge_common_groups'.freeze
        NA_PREF_MERGE_COPIES      = 'merge_group_copies'.freeze
        NA_PREF_INCLUDE_LOCKED    = 'include_locked'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Show the Converter Dialog
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__ShowDialog
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

            na_attach_observer(Sketchup.active_model)
            @na_dialog
        end
        # ------------------------------------------------------------

        # FUNCTION | Close and Forget the Dialog (Called by the Reload Manager)
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__ResetDialog
            return unless @na_dialog

            @na_dialog.close if @na_dialog.visible?
            na_teardown_dialog_state
            true
        rescue => error
            puts "[Na__GroupComponentConverter] Reset dialog warning: #{error.class}: #{error.message}"
            na_teardown_dialog_state
            false
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Detach Observer and Drop Every Cached Reference
        # ------------------------------------------------------------
        def self.na_teardown_dialog_state
            na_detach_observer
            @na_dialog         = nil
            @na_refresh_queued = false
            @na_operation_busy = false
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
            layout_path = File.join(__dir__, 'Na__Noble3dModellingTools__GroupComponentConverter__UiLayout__.html')
            style_path  = File.join(__dir__, 'Na__Noble3dModellingTools__GroupComponentConverter__Styles__.css')
            script_path = File.join(__dir__, 'Na__Noble3dModellingTools__GroupComponentConverter__UiBridge__.js')

            File.read(layout_path)
                .gsub('{{STYLESHEET_CONTENT}}') { File.read(style_path) }
                .gsub('{{UI_BRIDGE_SCRIPT}}')   { File.read(script_path) }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Observer Management
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Attach the Selection Observer
        # ------------------------------------------------------------
        def self.na_attach_observer(model)
            return unless model
            return if @na_selection_observer

            @na_selection_observer = Na__GroupComponentConverter__SelectionObserver.new
            model.selection.add_observer(@na_selection_observer)
            @na_observed_model = model
        rescue => error
            puts "[Na__GroupComponentConverter] Observer attach failed: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Detach and Discard the Selection Observer
        # ------------------------------------------------------------
        def self.na_detach_observer
            model = @na_observed_model || Sketchup.active_model
            model.selection.remove_observer(@na_selection_observer) if model && @na_selection_observer

            @na_selection_observer = nil
            @na_observed_model     = nil
        rescue => error
            puts "[Na__GroupComponentConverter] Observer detach warning: #{error.class}: #{error.message}"
            @na_selection_observer = nil
            @na_observed_model     = nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Handle a Selection Change Reported by the Observer
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__DialogManager__HandleSelectionChanged
            na_queue_refresh
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Defer a Refresh Onto the Next Main Loop Pass
        # ------------------------------------------------------------
        def self.na_queue_refresh
            return if @na_operation_busy
            return unless @na_dialog && @na_dialog.visible?
            return if @na_refresh_queued

            @na_refresh_queued = true
            UI.start_timer(0, false) do
                @na_refresh_queued = false
                next if @na_operation_busy

                na_push_selection_summary
            end
        rescue => error
            @na_refresh_queued = false
            puts "[Na__GroupComponentConverter] Refresh queue warning: #{error.class}: #{error.message}"
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

            dialog.add_action_callback('na_set_options') do |_context, options_json|
                na_apply_options_json(options_json)
                na_queue_refresh
            end

            dialog.add_action_callback('na_convert') do |_context, options_json|
                na_handle_convert_request(options_json)
            end

            dialog.add_action_callback('na_js_log') do |_context, message|
                puts "[Na__GroupComponentConverter][JS] #{message}"
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Persist Switches and Toggles Posted From the Dialog
        # ------------------------------------------------------------
        def self.na_apply_options_json(options_json)
            @na_options = Na__GroupComponentConverter__Options.Na__GroupComponentConverter__Options__Resolve(options_json)
            na_write_settings
        rescue => error
            puts "[Na__GroupComponentConverter] Options apply warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Run the Conversion and Report the Outcome
        # ------------------------------------------------------------
        def self.na_handle_convert_request(options_json)
            na_apply_options_json(options_json)

            @na_operation_busy = true
            na_detach_observer
            result = Na__GroupComponentConverter.Na__GroupComponentConverter__ConvertCurrentSelection(na_current_options)

            na_push_status(result[:message], result[:success] ? 'success' : 'warn')
            na_push_full_payload
        rescue => error
            na_push_status("Group / Component Converter failed: #{error.class}: #{error.message}", 'warn')
            na_push_full_payload
        ensure
            @na_operation_busy = false
            na_attach_observer(Sketchup.active_model) if @na_dialog
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
            na_execute_js('Na__GroupComponentConverter__ReceivePayload', na_build_payload)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Move the Observer If the Active Model Has Changed
        # ------------------------------------------------------------
        def self.na_follow_active_model
            model = Sketchup.active_model
            return unless model
            return if @na_observed_model && @na_observed_model == model

            na_detach_observer
            na_attach_observer(model)
        rescue => error
            puts "[Na__GroupComponentConverter] Model follow warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Push Only the Selection Report and Plans
        # ------------------------------------------------------------
        def self.na_push_selection_summary
            na_follow_active_model
            na_execute_js('Na__GroupComponentConverter__ReceiveSelection', na_build_selection_summary)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Push a Status Line to the Dialog Footer
        # ------------------------------------------------------------
        def self.na_push_status(message_text, variant)
            return unless @na_dialog && @na_dialog.visible?

            script = format(
                'if (typeof Na__GroupComponentConverter__ReceiveStatus === "function") { Na__GroupComponentConverter__ReceiveStatus(%s, %s); }',
                JSON.generate(message_text.to_s),
                JSON.generate(variant.to_s)
            )
            @na_dialog.execute_script(script)
        rescue => error
            puts "[Na__GroupComponentConverter] Status push warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Complete State Payload
        # ------------------------------------------------------------
        def self.na_build_payload
            {
                'selection' => na_build_selection_summary,
                'settings'  => Na__GroupComponentConverter__Options.Na__GroupComponentConverter__Options__ToPayload(na_current_options)
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Scan the Selection and Simulate Every Conversion
        # ------------------------------------------------------------
        def self.na_build_selection_summary
            model = Sketchup.active_model
            return Na__GroupComponentConverter__SelectionScanner.Na__GroupComponentConverter__SelectionScanner__EmptySummary unless model

            Na__GroupComponentConverter__SelectionScanner.Na__GroupComponentConverter__SelectionScanner__Scan(
                model.selection,
                na_current_options
            )
        rescue => error
            puts "[Na__GroupComponentConverter] Selection summary warning: #{error.class}: #{error.message}"
            Na__GroupComponentConverter__SelectionScanner.Na__GroupComponentConverter__SelectionScanner__EmptySummary
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Current Options, Loading Them on First Use
        # ------------------------------------------------------------
        def self.na_current_options
            na_load_settings unless @na_options
            @na_options
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
            puts "[Na__GroupComponentConverter] Push warning for #{function_name}: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Settings Persistence
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Read the Persisted Switches and Toggles
        # ------------------------------------------------------------
        def self.na_load_settings
            defaults = Na__GroupComponentConverter__Options.Na__GroupComponentConverter__Options__Defaults
            stored = {
                direction:           na_read_default(NA_PREF_DIRECTION,      defaults[:direction]),
                scope:               na_read_default(NA_PREF_SCOPE,          defaults[:scope]),
                merge_common_groups: na_read_default(NA_PREF_MERGE_COMMON,   defaults[:merge_common_groups]),
                merge_group_copies:  na_read_default(NA_PREF_MERGE_COPIES,   defaults[:merge_group_copies]),
                include_locked:      na_read_default(NA_PREF_INCLUDE_LOCKED, defaults[:include_locked])
            }
            @na_options = Na__GroupComponentConverter__Options.Na__GroupComponentConverter__Options__Resolve(stored)
        rescue => error
            puts "[Na__GroupComponentConverter] Settings read warning: #{error.class}: #{error.message}"
            @na_options = Na__GroupComponentConverter__Options.Na__GroupComponentConverter__Options__Defaults
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Persist the Current Switches and Toggles
        # ------------------------------------------------------------
        def self.na_write_settings
            options = na_current_options
            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_DIRECTION,       options[:direction])
            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_SCOPE,           options[:scope])
            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_MERGE_COMMON,    options[:merge_common_groups])
            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_MERGE_COPIES,    options[:merge_group_copies])
            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_INCLUDE_LOCKED,  options[:include_locked])
        rescue => error
            puts "[Na__GroupComponentConverter] Settings write warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read One Persisted Value
        # ------------------------------------------------------------
        def self.na_read_default(preference_name, default_value)
            Sketchup.read_default(NA_DIALOG_PREFERENCES_KEY, preference_name, default_value)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GroupComponentConverter__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
