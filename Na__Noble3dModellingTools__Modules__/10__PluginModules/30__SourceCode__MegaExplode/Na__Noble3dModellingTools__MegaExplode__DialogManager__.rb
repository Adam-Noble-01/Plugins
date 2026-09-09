# =============================================================================
# NA NOBLE3D MODELLING TOOLS - MEGA EXPLODE - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__MegaExplode__DialogManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__MegaExplode__DialogManager
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Own the Mega Explode HtmlDialog, keep selection stats live,
#              persist cleanup toggles, and run the explode on confirm
# CREATED    : 2026
#
# DESIGN NOTES:
# - A fresh dialog is built on each invocation and @na_dialog is dropped on
#   close, so callbacks are always bound to the live instance.
# - All assets are inlined via set_html, matching the other feature modules.
# - Observer callbacks never do work inline. They set a flag and a zero-delay
#   UI timer picks the work up on the next main loop pass.
# - Toggle state persists through Sketchup.write_default. First-run defaults
#   are all off, as requested.
#
# RUBY -> JS : Na__MegaExplode__ReceivePayload(payload)
#              Na__MegaExplode__ReceiveSelection(selection)
#              Na__MegaExplode__ReceiveStatus(message, variant)
# JS -> RUBY : sketchup.na_dialog_ready / na_refresh / na_set_options
#              sketchup.na_explode      / na_js_log
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__MegaExplode__DialogManager

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIALOG_TITLE           = 'Na Noble3d Tools : Mega Explode'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__Noble3dModellingTools__MegaExplode'.freeze
        NA_DIALOG_WIDTH           = 480
        NA_DIALOG_HEIGHT          = 860
        NA_DIALOG_MIN_WIDTH       = 400
        NA_DIALOG_MIN_HEIGHT      = 580
        NA_PREF_MOVE_TO_UNTAGGED = 'move_to_untagged'.freeze
        NA_PREF_STRIP_MATERIALS  = 'strip_materials'.freeze
        NA_PREF_DELETE_FACES     = 'delete_faces'.freeze
        NA_PREF_DELETE_HIDDEN    = 'delete_hidden'.freeze
        NA_PREF_UNLOCK_LOCKED    = 'unlock_locked'.freeze
        NA_PREF_PURGE_UNUSED     = 'purge_unused'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Show the Mega Explode Dialog
        # ------------------------------------------------------------
        def self.Na__MegaExplode__ShowDialog
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
        def self.Na__MegaExplode__ResetDialog
            return unless @na_dialog

            @na_dialog.close if @na_dialog.visible?
            na_teardown_dialog_state
            true
        rescue => error
            puts "[Na__MegaExplode] Reset dialog warning: #{error.class}: #{error.message}"
            na_teardown_dialog_state
            false
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Detach Observer and Drop Every Cached Reference
        # ------------------------------------------------------------
        def self.na_teardown_dialog_state
            na_detach_observer
            @na_dialog           = nil
            @na_refresh_queued   = false
            @na_operation_busy   = false
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
            layout_path = File.join(__dir__, 'Na__Noble3dModellingTools__MegaExplode__UiLayout__.html')
            style_path  = File.join(__dir__, 'Na__Noble3dModellingTools__MegaExplode__Styles__.css')
            script_path = File.join(__dir__, 'Na__Noble3dModellingTools__MegaExplode__UiBridge__.js')

            File.read(layout_path)
                .gsub('{{STYLESHEET_CONTENT}}', File.read(style_path))
                .gsub('{{UI_BRIDGE_SCRIPT}}',   File.read(script_path))
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

            @na_selection_observer = Na__MegaExplode__SelectionObserver.new
            model.selection.add_observer(@na_selection_observer)
            @na_observed_model = model
        rescue => error
            puts "[Na__MegaExplode] Observer attach failed: #{error.class}: #{error.message}"
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
            puts "[Na__MegaExplode] Observer detach warning: #{error.class}: #{error.message}"
            @na_selection_observer = nil
            @na_observed_model     = nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Handle a Selection Change Reported by the Observer
        # ------------------------------------------------------------
        def self.Na__MegaExplode__DialogManager__HandleSelectionChanged
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
            puts "[Na__MegaExplode] Refresh queue warning: #{error.class}: #{error.message}"
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
            end

            dialog.add_action_callback('na_explode') do |_context, options_json|
                na_handle_explode_request(options_json)
            end

            dialog.add_action_callback('na_js_log') do |_context, message|
                puts "[Na__MegaExplode][JS] #{message}"
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Persist Toggles Posted From the Dialog
        # ------------------------------------------------------------
        def self.na_apply_options_json(options_json)
            options = na_parse_options_json(options_json)
            @na_move_to_untagged = options[:move_to_untagged]
            @na_strip_materials   = options[:strip_materials]
            @na_delete_faces       = options[:delete_faces]
            @na_delete_hidden      = options[:delete_hidden]
            @na_unlock_locked     = options[:unlock_locked]
            @na_purge_unused      = options[:purge_unused]
            na_write_settings
        rescue => error
            puts "[Na__MegaExplode] Options parse warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Run Mega Explode and Report the Outcome
        # ------------------------------------------------------------
        def self.na_handle_explode_request(options_json)
            na_apply_options_json(options_json)

            @na_operation_busy = true
            na_detach_observer
            result = Na__MegaExplode.Na__MegaExplode__ExplodeCurrentSelection(
                move_to_untagged: @na_move_to_untagged,
                strip_materials:  @na_strip_materials,
                delete_faces:     @na_delete_faces,
                delete_hidden:    @na_delete_hidden,
                unlock_locked:    @na_unlock_locked,
                purge_unused:     @na_purge_unused
            )

            na_push_status(result[:message], result[:success] ? 'success' : 'warn')
            na_push_full_payload
        rescue => error
            na_push_status("Mega Explode failed: #{error.class}: #{error.message}", 'warn')
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
            na_execute_js('Na__MegaExplode__ReceivePayload', na_build_payload)
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
            puts "[Na__MegaExplode] Model follow warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Push Only the Selection Summary
        # ------------------------------------------------------------
        def self.na_push_selection_summary
            na_follow_active_model
            na_execute_js('Na__MegaExplode__ReceiveSelection', na_build_selection_summary)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Push a Status Line to the Dialog Footer
        # ------------------------------------------------------------
        def self.na_push_status(message_text, variant)
            return unless @na_dialog && @na_dialog.visible?

            script = format(
                'if (typeof Na__MegaExplode__ReceiveStatus === "function") { Na__MegaExplode__ReceiveStatus(%s, %s); }',
                JSON.generate(message_text.to_s),
                JSON.generate(variant.to_s)
            )
            @na_dialog.execute_script(script)
        rescue => error
            puts "[Na__MegaExplode] Status push warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Complete State Payload
        # ------------------------------------------------------------
        def self.na_build_payload
            {
                'selection' => na_build_selection_summary,
                'settings'  => na_settings_payload
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Walk the Selection and Summarise What Would Be Exploded
        # ------------------------------------------------------------
        def self.na_build_selection_summary
            model = Sketchup.active_model
            return Na__MegaExplode__StatsCollector.Na__MegaExplode__StatsCollector__EmptySummary unless model

            Na__MegaExplode__StatsCollector.Na__MegaExplode__StatsCollector__Collect(
                model.selection,
                model
            )
        rescue => error
            puts "[Na__MegaExplode] Selection summary warning: #{error.class}: #{error.message}"
            Na__MegaExplode__StatsCollector.Na__MegaExplode__StatsCollector__EmptySummary
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Current Toggle State for the Dialog
        # ------------------------------------------------------------
        def self.na_settings_payload
            {
                'move_to_untagged' => !!@na_move_to_untagged,
                'strip_materials'  => !!@na_strip_materials,
                'delete_faces'     => !!@na_delete_faces,
                'delete_hidden'    => !!@na_delete_hidden,
                'unlock_locked'    => !!@na_unlock_locked,
                'purge_unused'     => !!@na_purge_unused
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
            puts "[Na__MegaExplode] Push warning for #{function_name}: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Settings Persistence
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Read the Persisted Toggle State
        # ------------------------------------------------------------
        def self.na_load_settings
            @na_move_to_untagged = na_read_flag(NA_PREF_MOVE_TO_UNTAGGED, false)
            @na_strip_materials  = na_read_flag(NA_PREF_STRIP_MATERIALS,  false)
            @na_delete_faces     = na_read_flag(NA_PREF_DELETE_FACES,     false)
            @na_delete_hidden    = na_read_flag(NA_PREF_DELETE_HIDDEN,    false)
            @na_unlock_locked     = na_read_flag(NA_PREF_UNLOCK_LOCKED,    false)
            @na_purge_unused      = na_read_flag(NA_PREF_PURGE_UNUSED,     false)
        rescue => error
            puts "[Na__MegaExplode] Settings read warning: #{error.class}: #{error.message}"
            @na_move_to_untagged = false
            @na_strip_materials  = false
            @na_delete_faces     = false
            @na_delete_hidden    = false
            @na_unlock_locked     = false
            @na_purge_unused      = false
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Persist the Current Toggle State
        # ------------------------------------------------------------
        def self.na_write_settings
            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_MOVE_TO_UNTAGGED, @na_move_to_untagged)
            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_STRIP_MATERIALS,  @na_strip_materials)
            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_DELETE_FACES,     @na_delete_faces)
            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_DELETE_HIDDEN,    @na_delete_hidden)
            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_UNLOCK_LOCKED,    @na_unlock_locked)
            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_PURGE_UNUSED,     @na_purge_unused)
        rescue => error
            puts "[Na__MegaExplode] Settings write warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read One Persisted Boolean
        # ------------------------------------------------------------
        def self.na_read_flag(preference_name, default_value)
            stored_value = Sketchup.read_default(NA_DIALOG_PREFERENCES_KEY, preference_name, default_value)
            na_parse_boolean(stored_value)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Parse the Options JSON Posted From the Dialog
        # ------------------------------------------------------------
        def self.na_parse_options_json(options_json)
            parsed = if options_json.is_a?(String)
                         JSON.parse(options_json)
                     elsif options_json.is_a?(Hash)
                         options_json
                     else
                         {}
                     end
            parsed = {} unless parsed.is_a?(Hash)

            {
                move_to_untagged: na_parse_boolean(parsed['move_to_untagged']),
                strip_materials:  na_parse_boolean(parsed['strip_materials']),
                delete_faces:     na_parse_boolean(parsed['delete_faces']),
                delete_hidden:    na_parse_boolean(parsed['delete_hidden']),
                unlock_locked:    na_parse_boolean(parsed['unlock_locked']),
                purge_unused:     na_parse_boolean(parsed['purge_unused'])
            }
        rescue
            {
                move_to_untagged: false,
                strip_materials:  false,
                delete_faces:     false,
                delete_hidden:    false,
                unlock_locked:    false,
                purge_unused:     false
            }
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

    end # module Na__MegaExplode__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
