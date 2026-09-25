# =============================================================================
# NA NOBLE3D MODELLING TOOLS - VEGETATION SKETCHER - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__VegetationSketcher__DialogManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__VegetationSketcher__DialogManager
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Own the Vegetation Sketcher HtmlDialog, selection editing,
#              acknowledged JS commands and deferred preview work
# CREATED    : 2026
#
# DESIGN NOTES:
# - One acknowledged command at a time. An edit carries the selection context
#   and persistent ID, so a delayed slider cannot update a different entity.
# - Do not build or serialise meshes on the mouse-event path. The latest panel
#   request wins after a quiet period; acknowledgements stay immediate.
# - Observer callbacks never do work inline. They queue a UI timer.
#
# RUBY -> JS : Na__VegetationSketcher__Receive(event, payload)
# JS -> RUBY : sketchup.na_dialog_ready / na_event
#
# =============================================================================

require 'json'
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__Placement__'

module Na__Noble3dModellingTools
    module Na__VegetationSketcher__DialogManager

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIALOG_TITLE           = 'Na Noble3d Tools : Vegetation Sketcher'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__Noble3dModellingTools__VegetationSketcher'.freeze
        NA_DIALOG_WIDTH           = 510
        NA_DIALOG_HEIGHT          = 900
        NA_DIALOG_MIN_WIDTH       = 420
        NA_DIALOG_MIN_HEIGHT      = 620
        NA_PANEL_DEBOUNCE         = 0.65
        NA_PREF_SETTINGS          = 'settings'.freeze
        NA_PREF_PLACEMENT         = 'placement'.freeze
        NA_JS_RECEIVE             = 'Na__VegetationSketcher__Receive'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Show the Vegetation Sketcher Dialog
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__ShowDialog
            if @na_dialog && @na_dialog.visible?
                @na_dialog.bring_to_front
                return @na_dialog
            end

            @na_ready = false
            @na_busy = false
            @na_live = true
            @na_context = 0
            @na_session = "#{Time.now.to_f}-#{object_id}"
            @na_selection_signature = nil
            @na_epoch = (@na_epoch || 0) + 1
            na_attach_model
            @na_app_observer = Na__VegetationSketcher__AppObserver.new
            Sketchup.add_observer(@na_app_observer)

            @na_dialog = na_create_dialog
            @na_dialog.set_html(na_render_html)
            na_register_callbacks(@na_dialog)
            @na_dialog.set_on_closed { na_teardown_dialog_state }
            @na_dialog.show
            @na_dialog
        end
        # ------------------------------------------------------------

        # FUNCTION | Close and Forget the Dialog (Called by the Reload Manager)
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__ResetDialog
            Na__VegetationSketcher__ScatterDialog.Na__VegetationSketcher__Scatter__ResetDialog if defined?(Na__VegetationSketcher__ScatterDialog)
            dialog = @na_dialog
            na_teardown_dialog_state
            dialog.close if dialog && dialog.visible?
            true
        end
        # ------------------------------------------------------------

        # FUNCTION | Handle a Deferred Observer Refresh Request
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__DialogManager__HandleObserverEvent
            na_queue_sync
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
            layout_path = File.join(__dir__, 'Na__Noble3dModellingTools__VegetationSketcher__UiLayout__.html')
            style_path  = File.join(__dir__, 'Na__Noble3dModellingTools__VegetationSketcher__Styles__.css')
            script_path = File.join(__dir__, 'Na__Noble3dModellingTools__VegetationSketcher__UiBridge__.js')

            File.read(layout_path)
                .gsub('{{STYLESHEET_CONTENT}}') { File.read(style_path) }
                .gsub('{{UI_BRIDGE_SCRIPT}}')   { File.read(script_path) }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Register JS to Ruby Action Callbacks
        # ------------------------------------------------------------
        def self.na_register_callbacks(dialog)
            dialog.add_action_callback('na_dialog_ready') do |_context|
                begin
                    first_ready = !@na_ready
                    @na_ready = true
                    na_sync_selection(force: first_ready)
                    na_push_state
                    na_preview
                rescue StandardError => error
                    na_report_error(error)
                end
            end

            dialog.add_action_callback('na_event') do |_context, raw|
                na_handle_event(raw)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Detach Observers and Drop Cached Dialog State
        # ------------------------------------------------------------
        def self.na_teardown_dialog_state
            @na_ready = false
            @na_epoch = (@na_epoch || 0) + 1
            UI.stop_timer(@na_sync_timer) if @na_sync_timer
            @na_sync_timer = nil
            na_stop
            na_detach_model
            Sketchup.remove_observer(@na_app_observer) if @na_app_observer
            @na_app_observer = @na_target = @na_dialog = nil
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Acknowledged Command Bus
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Parse, Dispatch and Acknowledge One JS Command
        # ------------------------------------------------------------
        def self.na_handle_event(raw)
            request = JSON.parse(raw)
            raise ArgumentError, 'Invalid bridge request.' unless request.is_a?(Hash)
            raise ArgumentError, 'The dialog was reloaded. Reopen Vegetation Sketcher.' unless request['session'] == @na_session
            raise ArgumentError, 'Vegetation Sketcher is busy.' if @na_busy

            @na_busy = true
            entered = true
            @na_source_revision = request['revision']
            na_dispatch(request['action'], request['payload'] || {})
            na_send_js('ack', { id: request['id'], success: true })
        rescue StandardError => error
            na_report_error(error)
            na_send_js('ack', { id: request.is_a?(Hash) ? request['id'] : nil, success: false })
        ensure
            if entered
                @na_busy = false
                @na_source_revision = nil
                na_queue_sync
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Route One Named Action
        # ------------------------------------------------------------
        def self.na_dispatch(action, payload)
            na_attach_model
            case action
            when 'options', 'variation' then na_handle_options_action(action, payload)
            when 'placement'            then na_handle_placement_action(payload)
            when 'preset'               then na_handle_preset_action(payload)
            when 'tree_type'            then na_handle_tree_type_action(payload)
            when 'shrub_type'           then na_handle_shrub_type_action(payload)
            when 'new'                  then na_handle_new_action
            when 'start'                then na_handle_start_action(payload)
            when 'stop'                 then na_handle_stop_action(payload)
            when 'load'                 then na_sync_selection(force: true)
            when 'update'               then na_handle_update_action(payload)
            when 'live'                 then na_handle_live_action(payload)
            when 'scatter'
                na_stop
                Na__VegetationSketcher__ScatterDialog.Na__VegetationSketcher__Scatter__ShowDialog
            else
                raise ArgumentError, "Unknown vegetation action: #{action}"
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Apply Form Edits or a New Seed
        # ------------------------------------------------------------
        def self.na_handle_options_action(action, payload)
            na_validate_context(payload)
            options = Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Resolve(payload.fetch('settings'))
            options['seed'] = options['seed'] % 2147483646 + 1 if action == 'variation'
            na_apply_options(options)
            na_update_target(payload) if @na_target && @na_live && !na_placing?
            na_push_state
            na_preview
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Store Placement Variation Ranges
        # ------------------------------------------------------------
        # Not context-checked: the ranges belong to the planting tool, never
        # to the selected vegetation, so a selection change cannot stale them.
        def self.na_handle_placement_action(payload)
            na_apply_placement(payload.fetch('placement'))
            na_push_state
            na_report(@na_placement['enabled'] ? 'Placement variation saved. Each new plant rolls its own size and turn.' : 'Placement variation off. Plants use the exact size above.')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Switch Hedge, Tree or Shrub Preset
        # ------------------------------------------------------------
        def self.na_handle_preset_action(payload)
            na_stop
            na_new_mode
            na_apply_options(Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Preset(payload['preset']))
            na_push_state
            na_preview
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Load a Named Tree Species
        # ------------------------------------------------------------
        def self.na_handle_tree_type_action(payload)
            na_validate_context(payload)
            raise ArgumentError, 'Choose the Tree preset first.' unless @na_options['preset'] == 'tree'

            options = Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__TreePreset(payload['tree_type'])
            %w[seed smooth vary].each { |key| options[key] = @na_options[key] }
            na_apply_options(options)
            na_update_target(payload) if @na_target && @na_live && !na_placing?
            na_push_state
            na_preview
            na_report(Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Label(@na_options) + ' dimensions loaded. Adjust the size, then plant or update the selected tree.')
        end
        # ------------------------------------------------------------

        def self.na_handle_shrub_type_action(payload)
            na_validate_context(payload)
            raise ArgumentError, 'Choose the Planting preset first.' unless @na_options['preset'] == 'shrub'
            options = Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__ShrubPreset(payload['shrub_type'])
            %w[seed smooth vary].each { |key| options[key] = @na_options[key] }
            na_apply_options(options)
            na_update_target(payload) if @na_target && @na_live && !na_placing?
            na_push_state
            na_preview
            na_report(Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Label(@na_options) + ' loaded. Plant individually or choose a ready-made mix in Scatter.')
        end

        # HELPER FUNCTION | Leave Editing Mode Without Changing Settings
        # ------------------------------------------------------------
        def self.na_handle_new_action
            na_stop
            na_new_mode
            na_push_state
            na_preview
            na_report('Ready to create new vegetation. Click Draw in SketchUp.')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Activate Placement or Hedge Drawing
        # ------------------------------------------------------------
        def self.na_handle_start_action(payload)
            na_stop
            na_new_mode
            na_apply_options(payload.fetch('settings'))
            na_apply_placement(payload['placement']) if payload['placement']
            @na_tool = if @na_options['preset'] == 'hedge'
                           Na__VegetationSketcher__HedgeTool.new(@na_options, self)
                       else
                           Na__VegetationSketcher__PlacementTool.new(@na_options, self, na_placement)
                       end
            @na_observed_model.select_tool(@na_tool)
            @na_observed_model.active_view.invalidate
            Sketchup.focus if Sketchup.respond_to?(:focus)
            na_push_state
            na_report(@na_options['preset'] == 'hedge' ? 'Click or drag the first run, then click each corner. Enter or Finish creates the joined hedge.' : 'Plant mode is active. Click in SketchUp to create vegetation.')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Finish Placement and Return to Editing
        # ------------------------------------------------------------
        def self.na_handle_stop_action(payload)
            na_apply_options(payload['settings']) if payload['settings']
            @na_tool.na_finish_path if na_placing? && @na_tool.respond_to?(:na_finish_path)
            na_stop
            na_sync_selection(force: true)
            na_push_state
            na_report('Placement finished. Select vegetation to edit it, or draw a new form.')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Apply Settings to the Selected Entity
        # ------------------------------------------------------------
        def self.na_handle_update_action(payload)
            na_validate_context(payload)
            na_apply_options(payload.fetch('settings'))
            na_update_target(payload)
            na_push_state
            na_preview
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Pause or Resume Live Editing
        # ------------------------------------------------------------
        def self.na_handle_live_action(payload)
            na_validate_context(payload)
            @na_live = payload['enabled'] == true
            na_push_state
            na_report(@na_live ? 'Live editing enabled. Changes update the selected vegetation.' : 'Live editing paused. Use Update selected to apply changes.')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Store Settings and Push Them to an Active Tool
        # ------------------------------------------------------------
        def self.na_apply_options(raw)
            @na_options = Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Resolve(raw)
            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_SETTINGS, JSON.generate(@na_options))
            @na_tool.na_update_options(@na_options) if na_placing?
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Validate, Remember and Push Placement Ranges
        # ------------------------------------------------------------
        def self.na_apply_placement(raw)
            @na_placement = Na__VegetationSketcher__Placement.Na__VegetationSketcher__Placement__Resolve(raw)
            Sketchup.write_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_PLACEMENT, JSON.generate(@na_placement))
            @na_tool.na_update_placement(@na_placement) if na_placing? && @na_tool.respond_to?(:na_update_placement)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Placement Ranges, Read Once From Preferences
        # ------------------------------------------------------------
        def self.na_placement
            @na_placement ||= Na__VegetationSketcher__Placement.Na__VegetationSketcher__Placement__Load(
                Sketchup.read_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_PLACEMENT, '{}')
            )
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Reject Commands Aimed at a Stale Selection
        # ------------------------------------------------------------
        def self.na_validate_context(payload)
            unless payload['context'] == @na_context && payload['target_id'] == na_target_id
                raise ArgumentError, 'Selection changed. The panel has refreshed; apply your change again.'
            end
            if @na_target && (!na_editable?(@na_target) || na_selected_entity != @na_target)
                na_queue_sync
                raise ArgumentError, 'The editing target changed or is locked. Select editable vegetation again.'
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Rebuild the Selected Entity When Settings Differ
        # ------------------------------------------------------------
        def self.na_update_target(payload)
            na_validate_context(payload)
            raise ArgumentError, 'Select Noble vegetation to edit. Use Draw in SketchUp to create new vegetation.' unless @na_target

            if Na__VegetationSketcher__DataSerializer.Na__VegetationSketcher__DataSerializer__Load(@na_target) != @na_options
                Na__VegetationSketcher__Builder.Na__VegetationSketcher__Builder__Update(@na_observed_model, @na_target, @na_options)
                @na_observed_model.active_view.invalidate
                na_report('Updated ' + @na_target.name + '. Undo restores its previous shape.', 'success')
            end
            @na_selection_signature = na_selection_signature
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Selection and Model Attachment
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Leave the Current Editing Target
        # ------------------------------------------------------------
        def self.na_new_mode
            na_cancel_panel
            na_detach_target
            @na_target = @na_last_created = nil
            @na_options = @na_options.merge('path' => nil) if @na_options
            @na_context += 1
            @na_selection_signature = na_selection_signature
            @na_selection_path = (@na_observed_model.active_path || []).map(&:persistent_id)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Single Selected Entity, or Nil
        # ------------------------------------------------------------
        def self.na_selected_entity
            selection = @na_observed_model.selection.to_a
            selection.length == 1 ? selection.first : nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | True When the Entity Can Be Live-Edited
        # ------------------------------------------------------------
        def self.na_editable?(entity)
            Na__VegetationSketcher__DataSerializer.Na__VegetationSketcher__DataSerializer__HasData?(entity) &&
                !entity.locked? &&
                @na_observed_model.active_entities.include?(entity)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Persistent ID of the Current Editing Target
        # ------------------------------------------------------------
        def self.na_target_id
            @na_target && @na_target.valid? ? @na_target.persistent_id.to_s : nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Snapshot Used to Detect Selection Changes
        # ------------------------------------------------------------
        def self.na_selection_signature
            @na_observed_model.selection.to_a.map do |entity|
                if Na__VegetationSketcher__DataSerializer.Na__VegetationSketcher__DataSerializer__Container?(entity)
                    [
                        entity.persistent_id,
                        entity.locked?,
                        entity.name,
                        entity.transformation.to_a,
                        entity.definition.get_attribute(Na__VegetationSketcher__DataSerializer::NA_DEFINITION_DICT, 'data'),
                        entity.get_attribute(Na__VegetationSketcher__DataSerializer::NA_INSTANCE_DICT, 'settings')
                    ]
                else
                    [entity.entityID]
                end
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Load or Clear the Editing Target From Selection
        # ------------------------------------------------------------
        def self.na_sync_selection(force: false)
            return unless @na_dialog && @na_ready

            na_attach_model
            if na_placing? && !@na_tool.na_valid_context?
                na_stop
                force = true
                na_report('Editing context changed. Click Draw in SketchUp to start again.')
            end
            return if na_placing?

            signature = na_selection_signature
            path = (@na_observed_model.active_path || []).map(&:persistent_id)
            return if !force && signature == @na_selection_signature && path == @na_selection_path

            na_cancel_panel
            @na_selection_signature, @na_selection_path = signature, path
            na_detach_target
            @na_target = nil
            @na_context += 1
            entity = na_selected_entity
            if na_editable?(entity)
                @na_options = Na__VegetationSketcher__DataSerializer.Na__VegetationSketcher__DataSerializer__Load(entity)
                @na_target = entity
                @na_entity_observer = Na__VegetationSketcher__EntityObserver.new
                entity.add_observer(@na_entity_observer)
                na_report('Selected ' + entity.name + '. Its saved settings are loaded.')
            elsif Na__VegetationSketcher__DataSerializer.Na__VegetationSketcher__DataSerializer__HasData?(entity) && entity.locked?
                na_report('Selected vegetation is locked. Unlock it to edit, or draw a new form.')
            else
                na_report('Ready to create vegetation. No selection is needed.')
            end
            na_push_state
            na_preview
        rescue StandardError => error
            @na_target = nil
            na_push_state
            na_report_error(error)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Follow SketchUp's Active Model
        # ------------------------------------------------------------
        def self.na_attach_model
            model = Sketchup.active_model
            return if @na_observed_model == model

            na_stop
            na_detach_model
            @na_observed_model = model
            @na_selection_observer = Na__VegetationSketcher__SelectionObserver.new
            @na_model_observer = Na__VegetationSketcher__ModelObserver.new
            model.selection.add_observer(@na_selection_observer)
            model.add_observer(@na_model_observer)
            @na_options = Na__VegetationSketcher__DataSerializer.Na__VegetationSketcher__DataSerializer__ModelOptions(
                model,
                Sketchup.read_default(NA_DIALOG_PREFERENCES_KEY, NA_PREF_SETTINGS, '{}')
            )
            @na_target = @na_selection_signature = @na_last_created = nil
            @na_context = (@na_context || 0) + 1
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Defer Selection Sync Onto the Next UI Loop
        # ------------------------------------------------------------
        def self.na_queue_sync
            return unless @na_dialog && @na_ready
            return if @na_sync_timer

            epoch = @na_epoch
            @na_sync_timer = UI.start_timer(0.05, false) do
                @na_sync_timer = nil
                next unless epoch == @na_epoch && @na_dialog && @na_ready

                @na_busy ? na_queue_sync : na_sync_selection
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Detach the Entity Observer From the Target
        # ------------------------------------------------------------
        def self.na_detach_target
            @na_target.remove_observer(@na_entity_observer) if @na_target && @na_target.valid? && @na_entity_observer
        ensure
            @na_entity_observer = nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Detach Selection and Model Observers
        # ------------------------------------------------------------
        def self.na_detach_model
            na_detach_target
            if @na_observed_model
                @na_observed_model.selection.remove_observer(@na_selection_observer) if @na_selection_observer
                @na_observed_model.remove_observer(@na_model_observer) if @na_model_observer
            end
        rescue StandardError => error
            puts "[Na__VegetationSketcher] Observer detach: #{error.message}"
        ensure
            @na_observed_model = @na_selection_observer = @na_model_observer = nil
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Panel Preview Queue
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Request a Panel Preview After the Quiet Period
        # ------------------------------------------------------------
        def self.na_preview
            na_queue_panel(preview: true) if @na_options
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Coalesce Preview and Progress Until Debounce Fires
        # ------------------------------------------------------------
        def self.na_queue_panel(preview: nil, progress: nil)
            return unless @na_dialog && @na_ready

            @na_pending_preview = preview unless preview.nil?
            @na_pending_progress = progress unless progress.nil?
            UI.stop_timer(@na_panel_timer) if @na_panel_timer
            token = @na_panel_token = (@na_panel_token || 0) + 1
            epoch, model, context, tool = @na_epoch, @na_observed_model, @na_context, @na_tool
            @na_panel_timer = UI.start_timer(NA_PANEL_DEBOUNCE, false) do
                next unless token == @na_panel_token && epoch == @na_epoch && @na_dialog && @na_ready

                @na_panel_timer = nil
                if model != Sketchup.active_model || context != @na_context || tool != @na_tool
                    na_cancel_panel
                    next
                end
                if @na_busy
                    na_queue_panel
                    next
                end
                na_flush_panel
            rescue StandardError => error
                na_report_error(error)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Send the Latest Pending Preview and Progress
        # ------------------------------------------------------------
        def self.na_flush_panel
            data, progress_data = @na_pending_preview, @na_pending_progress
            @na_pending_preview = @na_pending_progress = nil
            if data
                if data == true
                    data = @na_tool.na_preview_data if na_placing? && @na_tool.respond_to?(:na_preview_data)
                    data = Na__VegetationSketcher__Mesh.Na__VegetationSketcher__Mesh__Build(@na_options, preview: true) if data.nil? || data == true
                end
                na_send_js('preview', data)
            end
            na_send_js('viewport', progress_data) if progress_data
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Drop Pending Panel Work
        # ------------------------------------------------------------
        def self.na_cancel_panel
            @na_panel_token = (@na_panel_token || 0) + 1
            UI.stop_timer(@na_panel_timer) if @na_panel_timer
            @na_panel_timer = @na_pending_preview = @na_pending_progress = nil
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tool Owner Protocol and JS Push
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Push Dialog State to the HtmlDialog
        # ------------------------------------------------------------
        def self.na_push_state
            na_send_js('state', {
                settings:    @na_options,
                placement:   na_placement,
                placement_limits: Na__VegetationSketcher__Placement::NA_LIMITS,
                limit:       Na__VegetationSketcher__Mesh::NA_MAX_QUADS,
                limits:      Na__VegetationSketcher__Options::NA_LIMITS,
                tree_types:  Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__TreeTypeInfo,
                shrub_types: Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__ShrubTypeInfo,
                context:     @na_context,
                target_id:   na_target_id,
                target_name: @na_target && @na_target.valid? ? @na_target.name : nil,
                placing:     na_placing?,
                live:        @na_live,
                session:     @na_session,
                revision:    @na_source_revision
            })
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Queue Drawing Progress For the Panel
        # ------------------------------------------------------------
        def self.na_tool_progress(length, phase, count = nil)
            na_queue_panel(progress: { length: length && length.round(1), phase: phase, quads: count })
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Queue an Already-Built Viewport Mesh
        # ------------------------------------------------------------
        def self.na_tool_preview(data)
            na_queue_panel(preview: data)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Select a Newly Created Instance
        # ------------------------------------------------------------
        def self.na_created(entity)
            @na_last_created = entity
            @na_observed_model.selection.clear
            @na_observed_model.selection.add(entity)
            na_report('Created ' + entity.name + '. Continue drawing, or Finish to edit it.', 'success')
            na_send_js('created', { id: entity.persistent_id.to_s, name: entity.name })
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Advance the Organic Seed
        # ------------------------------------------------------------
        def self.na_new_variation
            na_apply_options(@na_options.merge('seed' => @na_options['seed'] % 2147483646 + 1))
            na_push_state
            na_preview
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Push a Status Line
        # ------------------------------------------------------------
        def self.na_report(message, variant = 'info')
            na_send_js('status', { message: message, variant: variant })
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Report an Exception to the Panel and Console
        # ------------------------------------------------------------
        def self.na_report_error(error)
            na_report(error.message, 'error')
            puts "[Na__VegetationSketcher] #{error.class}: #{error.message}\n#{error.backtrace&.first(5)&.join("\n")}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Call Na__VegetationSketcher__Receive in the Dialog
        # ------------------------------------------------------------
        def self.na_send_js(event, payload)
            return unless @na_dialog && @na_ready

            script = format(
                'if (typeof %s === "function") { %s(%s, %s); }',
                NA_JS_RECEIVE,
                NA_JS_RECEIVE,
                JSON.generate(event),
                JSON.generate(payload)
            )
            @na_dialog.execute_script(script)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | True While a Placement Tool Owns the Model
        # ------------------------------------------------------------
        def self.na_placing?
            !!(@na_tool && @na_tool.na_active?)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Clear the Tool After SketchUp Deactivates It
        # ------------------------------------------------------------
        def self.na_tool_stopped(tool)
            return unless @na_tool == tool

            na_cancel_panel
            @na_tool = nil
            @na_selection_signature = nil
            na_push_state
            na_queue_sync
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Deactivate the Current Tool If It Is Still Active
        # ------------------------------------------------------------
        def self.na_stop
            na_cancel_panel
            current = @na_tool
            @na_tool = nil
            current.na_model.select_tool(nil) if current && current.na_active? && current.na_model == Sketchup.active_model
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__VegetationSketcher__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
