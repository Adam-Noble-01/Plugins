# =============================================================================
# NA ARRAY BUILDER TOOLS - DIALOG MANAGER
# =============================================================================
# FILE       : Na__ArrayBuilder__DialogManager__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Live create/edit sessions, guarded UI bridge and preset routing.
# =============================================================================

require 'sketchup.rb'
require 'json'
require 'securerandom'
require_relative 'Na__ArrayBuilder__Configuration__'
require_relative 'Na__ArrayBuilder__PathTool__'
require_relative 'Na__ArrayBuilder__SelectionArrayTool__'
require_relative 'Na__ArrayBuilder__GeometryBuilder__'
require_relative 'Na__ArrayBuilder__PresetsLibrary__'
require_relative 'Na__ArrayBuilder__PreviewGeometry__'
require_relative 'Na__ArrayBuilder__PluginReloader__'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__DialogManager

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle and Bridge
# -----------------------------------------------------------------------------

        def self.na_show_dialog(na_html, _na_root)
            if @dialog && @dialog.visible?
                @dialog.bring_to_front
                return
            end
            @na_ready = false
            @na_last_preview = nil
            @na_reloaded = false
            @na_live = Sketchup.read_default('Na__ArrayBuilderTools', 'live', true)
            @na_scope = 'single'
            @na_target = @na_tool = @na_picker = nil
            @na_model = Sketchup.active_model
            @na_config = Na__ArrayBuilder__DataSerializer.Na__Data__ModelSettings(@na_model)
            Na__Dialog__NewContext()
            @dialog = UI::HtmlDialog.new(
                dialog_title: 'Noble Array Builder', preferences_key: 'Na__ArrayBuilderTools__Studio',
                scrollable: false, resizable: true, width: 860, height: 800,
                min_width: 650, min_height: 520, style: UI::HtmlDialog::STYLE_DIALOG
            )
            @dialog.set_file(na_html)
            @dialog.add_action_callback('na_arrayAction') { |_na_context, na_json| Na__Dialog__Receive(na_json) }
            @dialog.set_on_closed do
                Na__Dialog__StopTool()
                @na_ready = false
                @dialog = nil
                @na_target = nil
                Na__Dialog__NewContext()
            end
            @dialog.show
        end

        def self.na_get_dialog
            @dialog
        end

        # FUNCTION | JSON Encoding Protects Names, Quotes and Multiline Messages
        # ------------------------------------------------------------
        def self.Na__Dialog__Send(na_event, na_payload)
            return unless @dialog && @na_ready
            @dialog.execute_script("window.Na__ArrayUi__Receive(#{JSON.generate(na_event)}, #{JSON.generate(na_payload)});")
        end

        def self.Na__Dialog__NewContext
            Na__ArrayBuilder__PreviewGeometry.Na__Preview__Clear()
            @na_context = SecureRandom.hex(12)
            @na_edit_path = @na_model ? (@na_model.active_path || []).map(&:persistent_id) : []
        end

        # FUNCTION | Reject Late Edits After a Target, Model or Context Change
        # ------------------------------------------------------------
        def self.Na__Dialog__CheckContext(na_payload)
            unless @na_model == Sketchup.active_model && na_payload['context'] == @na_context &&
                   @na_edit_path == (@na_model.active_path || []).map(&:persistent_id)
                Na__Dialog__Synchronise()
                raise ArgumentError, 'The model or editing context changed. The panel has refreshed.'
            end
            return unless @na_target
            if @na_signature && @na_signature != Na__Dialog__Signature()
                Na__Dialog__Synchronise()
                raise ArgumentError, 'The array changed in SketchUp. Its saved settings have been reloaded.'
            end
            unless @na_target.valid? && !@na_target.locked? && @na_model.active_entities.include?(@na_target) &&
                   @na_model.selection.to_a == [@na_target]
                Na__Dialog__Synchronise()
                raise ArgumentError, 'Select the array again before editing it.'
            end
        end

        def self.Na__Dialog__Receive(na_json)
            na_payload = JSON.parse(na_json)
            raise ArgumentError, 'Invalid Array Builder request.' unless na_payload.is_a?(Hash)
            na_action = na_payload['action']
            if na_action == 'ready'
                @na_ready = true
                Na__Dialog__PushState()
                Na__Dialog__PushGallery()
                Na__Dialog__Preview()
                if @na_open_edit
                    @na_open_edit = false
                    Na__Dialog__EditSelected()
                end
                if @na_reloaded
                    @na_reloaded = false
                    Na__Dialog__Send('tab', 'settings')
                    na_send_status_to_dialog('success', 'Array Builder reloaded. Your current settings have been retained.')
                end
                return
            end
            Na__Dialog__CheckContext(na_payload)
            @na_busy = true
            case na_action
            when 'configure', 'update'
                @na_config = Na__ArrayBuilder__Configuration.Na__Config__Resolve(na_payload.fetch('config'))
                @na_scope = na_payload['scope'] == 'linked' ? 'linked' : 'single'
                if @na_tool
                    @na_tool.Na__Tool__UpdateConfig(@na_config)
                elsif @na_target && (@na_live || na_action == 'update')
                    Na__Dialog__UpdateTarget()
                end
                Na__Dialog__Preview() unless @na_tool
            when 'start', 'redraw'
                @na_config = Na__ArrayBuilder__Configuration.Na__Config__Resolve(na_payload.fetch('config'))
                Na__Dialog__StartPath(na_action == 'redraw')
            when 'finish'
                @na_tool.Na__Tool__Finish if @na_tool
            when 'cancel'
                Na__Dialog__StopTool()
                Na__Dialog__Preview()
                na_send_status_to_dialog('info', 'Path preview cancelled.')
            when 'edit'
                Na__Dialog__EditSelected()
            when 'new'
                Na__Dialog__StopTool()
                @na_target = nil
                @na_config = Na__ArrayBuilder__Configuration.Na__Config__Resolve(na_payload['config']) if na_payload['config']
                Na__Dialog__NewContext()
                Na__Dialog__PushState()
                Na__Dialog__Preview()
            when 'pick'
                Na__Dialog__StopTool()
                @na_config = Na__ArrayBuilder__Configuration.Na__Config__Resolve(na_payload['config']) if na_payload['config']
                @na_picker = Na__ArrayBuilder__ObjectPicker.new(self)
                @na_model.select_tool(@na_picker)
                na_send_status_to_dialog('info', 'Click a group or component to use as the source.')
            when 'live'
                @na_live = na_payload['enabled'] == true
                Sketchup.write_default('Na__ArrayBuilderTools', 'live', @na_live)
                Na__Dialog__PushState()
            when 'preset_list'
                Na__Dialog__PushGallery()
            when 'preset_save'
                na_config = Na__ArrayBuilder__Configuration.Na__Config__Resolve(na_payload.fetch('config'))
                na_source = na_config['type'] == 'object' ? Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetPlacementInfo : nil
                na_record = Na__ArrayBuilder__PresetsLibrary.Na__Presets__Save(na_payload, na_config, na_source)
                Na__Dialog__PushGallery()
                Na__Dialog__Send('preset_saved', na_record)
                na_send_status_to_dialog('success', 'Preset saved to your gallery.')
            when 'preset_load', 'preset_edit'
                Na__Dialog__LoadPreset(na_payload['id'], na_action == 'preset_edit')
            when 'preset_archive'
                Na__ArrayBuilder__PresetsLibrary.Na__Presets__Archive(na_payload['id'])
                Na__Dialog__PushGallery()
                na_send_status_to_dialog('success', 'Preset moved to the library archive.')
            when 'reset'
                Na__Dialog__StopTool()
                @na_target = nil
                @na_config = Na__ArrayBuilder__Configuration.Na__Config__Resolve
                Na__Dialog__NewContext()
                Na__Dialog__PushState()
                Na__Dialog__Preview()
            when 'reload'
                Na__ArrayBuilder__PluginReloader.Na__Reload__Schedule({
                    config: Na__ArrayBuilder__Configuration.Na__Config__Resolve(na_payload.fetch('config')),
                    target: @na_target, scope: @na_scope, model: @na_model,
                    source: Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetPlacementInfo(),
                    source_name: Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetDisplayName()
                })
                na_send_status_to_dialog('info', 'Reloading Array Builder…')
            end
        rescue StandardError => na_error
            na_send_status_to_dialog('error', na_error.message)
        ensure
            @na_busy = false
        end

        # FUNCTION | Restore Draft State Without Applying Geometry Changes
        # ------------------------------------------------------------
        def self.Na__Dialog__RestoreReload(na_snapshot)
            return unless @na_model == na_snapshot[:model]
            @na_config = na_snapshot[:config]
            @na_scope = na_snapshot[:scope]
            na_target = na_snapshot[:target]
            if na_target && na_target.valid? && !na_target.locked? &&
               @na_model.active_entities.include?(na_target) && @na_model.selection.to_a == [na_target]
                @na_target = na_target
                @na_signature = Na__Dialog__Signature()
            end
            na_source = na_snapshot[:source]
            if na_source && na_source[:definition].valid?
                Na__ArrayBuilder__ObjectRegistry.Na__Registry__SetDefinition(na_source[:definition], na_snapshot[:source_name], na_source[:scale])
            end
            Na__Dialog__NewContext()
            @na_reloaded = true
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Creation and Editing
# -----------------------------------------------------------------------------

        def self.Na__Dialog__SelectedArray
            return nil unless @na_model
            na_selection = @na_model.selection.to_a
            na_entity = na_selection.length == 1 ? na_selection.first : nil
            Na__ArrayBuilder__DataSerializer.Na__Data__HasData?(na_entity) ? na_entity : nil
        end

        def self.Na__Dialog__EditSelected
            na_entity = Na__Dialog__SelectedArray()
            raise ArgumentError, 'Select one Noble array created with this version, then click Edit selected.' unless na_entity
            raise ArgumentError, 'Unlock the selected array before editing.' if na_entity.locked?
            na_data = Na__ArrayBuilder__DataSerializer.Na__Data__Load(na_entity)
            Na__Dialog__StopTool()
            @na_target = na_entity
            @na_config = na_data['configuration']
            @na_scope = 'single'
            Na__ArrayBuilder__ObjectRegistry.Na__Registry__Clear
            begin
                Na__ArrayBuilder__DataSerializer.Na__Data__RestoreSource(na_entity, na_data)
            rescue ArgumentError => na_error
                na_send_status_to_dialog('warning', na_error.message)
            end
            @na_signature = Na__Dialog__Signature()
            Na__Dialog__NewContext()
            Na__Dialog__PushState()
            Na__Dialog__Send('tab', 'edit')
            Na__Dialog__Preview()
        end

        def self.Na__Dialog__OpenEdit
            @na_open_edit = true
            Na__ArrayBuilderTools.na_init
            if @na_ready
                @na_open_edit = false
                Na__Dialog__EditSelected()
            end
        rescue StandardError => na_error
            na_send_status_to_dialog('error', na_error.message)
        end

        def self.Na__Dialog__StartPath(na_replace)
            raise ArgumentError, 'Open an array in Edit before redrawing its path.' if na_replace && !@na_target
            if @na_config['type'] == 'object' && !Na__ArrayBuilder__ObjectRegistry.Na__Registry__IsValid?
                raise ArgumentError, 'Pick a source group or component first.'
            end
            # Resolve selection before changing tools or edit state.
            if @na_config['path_source'] == 'selection'
                na_result = Na__ArrayBuilder__PathFromSelection.Na__PathFromSelection__BuildFromEntities(@na_model.selection.to_a)
                raise ArgumentError, na_result[:reason] unless na_result[:valid]
            end
            Na__Dialog__StopTool()
            @na_target = nil unless na_replace
            @na_replacing = na_replace
            Na__Dialog__NewContext()
            na_tool = if na_result
                Na__ArrayBuilder__SelectionArrayTool.new(@na_config, self, na_result[:points], na_result[:closed])
            else
                Na__ArrayBuilder__PathTool.new(@na_config.merge('path_source' => 'draw'), self)
            end
            @na_model.select_tool(na_tool)
            Na__Dialog__PushState()
            na_send_status_to_dialog('info', na_result ? 'Review the blue preview; change any parameter, then Build array.' : 'Click path points. Change parameters at any time. Enter or Finish path builds the array.')
        end

        # FUNCTION | A Completed Replacement Path Updates the Existing Instance
        # ------------------------------------------------------------
        def self.Na__Dialog__CommitPath(na_points, na_config)
            Na__Dialog__CheckContext('context' => @na_context)
            if @na_replacing && @na_target
                na_entity_inverse = @na_target.transformation.inverse
                na_local = na_points.map do |na_point|
                    na_point.transform(na_entity_inverse)
                end
                na_source = na_config['type'] == 'object' ? Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetPlacementInfo : nil
                Na__ArrayBuilder__GeometryBuilder.Na__Geometry__Update(@na_model, @na_target, na_config, @na_scope, na_source, na_local)
                na_entity = @na_target
            else
                na_entity = Na__ArrayBuilder__GeometryBuilder.na_create_array(na_points, na_config)
            end
            @na_last_created = na_entity
            @na_replacing = false
            @na_signature = Na__Dialog__Signature()
            na_entity
        end

        def self.Na__Dialog__UpdateTarget
            na_source = @na_config['type'] == 'object' ? Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetPlacementInfo : nil
            na_plan = Na__ArrayBuilder__GeometryBuilder.Na__Geometry__Update(@na_model, @na_target, @na_config, @na_scope, na_source)
            @na_config = na_plan[:config]
            @na_signature = Na__Dialog__Signature()
            na_send_preview_info(na_plan[:positions].length, na_plan[:length_mm], na_plan[:gap_mm])
            Na__Dialog__Send('updated', { 'linked_count' => @na_target.definition.instances.length })
            na_send_status_to_dialog('success', @na_scope == 'linked' ? 'Linked arrays updated. Undo restores this change.' : 'Array updated. Undo restores this change.')
        end

        def self.Na__Dialog__StopTool
            @na_replacing = false
            if @na_model && (@na_tool || @na_picker)
                @na_model.select_tool(nil)
            end
            @na_tool = @na_picker = nil
        end

        # FUNCTION | Draw Replacement Previews in the Existing Array's Frame
        # ------------------------------------------------------------
        def self.Na__Dialog__PreviewFrame
            @na_replacing && @na_target ? @na_target.transformation : Geom::Transformation.new
        end

        # Existing SketchUp tools use these compatibility bridge entry points.
        def self.na_register_selection_tool(na_tool)
            @na_tool = na_tool
            if na_tool.nil? && @na_preview_timer
                UI.stop_timer(@na_preview_timer)
                @na_preview_timer = @na_pending_plan = nil
            end
            Na__Dialog__Send('placing', !na_tool.nil?)
        end

        def self.na_send_array_complete(_na_count)
            Na__Dialog__PushState()
            Na__Dialog__Send('completed', true)
        end

        def self.na_send_reverse_state(na_state)
            @na_config['reverse_path'] = na_state
            Na__Dialog__Send('reverse', na_state)
        end

        def self.na_send_object_picked(_na_name, _na_width, _na_depth, _na_height)
            @na_config['type'] = 'object'
            @na_picker = nil
            Na__Dialog__NewContext()
            Na__Dialog__PushState()
            Na__Dialog__Preview()
            # A source replacement is applied by the next change or Update button.
        end

        def self.Na__Dialog__PickerStopped
            @na_picker = nil
        end

        def self.na_send_object_cleared
            Na__Dialog__PushState()
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Preview, Gallery and Read-Only State Synchronisation
# -----------------------------------------------------------------------------

        def self.na_send_status_to_dialog(na_type, na_message)
            Na__Dialog__Send('status', { 'type' => na_type, 'message' => na_message.to_s })
        end

        def self.na_send_preview_info(na_count, na_length, na_gap = nil)
            na_payload = [na_count, na_length.round(1), na_gap]
            return if @na_last_preview == na_payload
            @na_last_preview = na_payload
            Na__Dialog__Send('metrics', { 'count' => na_count, 'length_mm' => na_length, 'gap_mm' => na_gap })
        end

        def self.na_reset_preview_info_memo
            @na_last_preview = nil
        end

        def self.Na__Dialog__Preview
            return unless @na_ready
            na_source = @na_config['type'] == 'object' ? Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetPlacementInfo : nil
            na_points = @na_target ? Na__ArrayBuilder__DataSerializer.Na__Data__Points(Na__ArrayBuilder__DataSerializer.Na__Data__Load(@na_target)) : [ORIGIN, Geom::Point3d.new(3000.mm, 0, 0)]
            if @na_config['type'] == 'object' && !na_source
                Na__Dialog__Send('preview', { 'missing_source' => true })
                return
            end
            na_plan = Na__ArrayBuilder__LayoutEngine.Na__Layout__Resolve(@na_config, na_points, na_source)
            Na__Dialog__SendPlanPreview(na_plan, @na_target.nil?)
            na_send_preview_info(na_plan[:positions].length, na_plan[:length_mm], na_plan[:gap_mm])
        rescue StandardError => na_error
            Na__Dialog__Send('preview', { 'error' => na_error.message })
            na_send_status_to_dialog('warning', na_error.message)
        end

        # FUNCTION | Debounce Actual Geometry; Never Add Preview Entities to Model
        # ------------------------------------------------------------
        def self.Na__Dialog__QueuePreview(na_plan)
            @na_pending_plan = na_plan
            UI.stop_timer(@na_preview_timer) if @na_preview_timer
            return unless @na_ready
            na_context = @na_context
            @na_preview_timer = UI.start_timer(0.12, false) do
                @na_preview_timer = nil
                if @na_ready && @na_tool && @na_context == na_context && @na_pending_plan
                    na_plan = @na_pending_plan
                    na_geometry = Na__ArrayBuilder__PreviewGeometry.Na__Preview__Resolve(na_plan)
                    @na_tool.Na__Tool__SetGeometryPreview(na_plan, na_geometry, Na__Dialog__PreviewFrame())
                    Na__Dialog__SendPlanPreview(na_plan, false, true, na_geometry)
                end
            rescue StandardError => na_error
                na_send_status_to_dialog('warning', na_error.message)
            end
        end

        def self.Na__Dialog__CancelPreview
            UI.stop_timer(@na_preview_timer) if @na_preview_timer
            @na_preview_timer = @na_pending_plan = nil
        end

        def self.Na__Dialog__SendPlanPreview(na_plan, na_sample, na_placing = false, na_geometry = nil)
            na_geometry ||= Na__ArrayBuilder__PreviewGeometry.Na__Preview__Resolve(na_plan)
            na_payload = Na__ArrayBuilder__PreviewGeometry.Na__Preview__Payload(na_geometry, na_plan)
            Na__Dialog__Send('preview', na_payload.merge('sample' => na_sample, 'placing' => na_placing))
        end

        def self.Na__Dialog__PushState
            return unless @na_ready && @na_model
            na_source = Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetPlacementInfo
            na_selected = Na__Dialog__SelectedArray()
            Na__Dialog__Send('state', {
                'context' => @na_context, 'config' => @na_config, 'live' => @na_live,
                'editing' => !!@na_target, 'placing' => !!@na_tool, 'scope' => @na_scope,
                'can_edit' => !!na_selected && !na_selected.locked?,
                'target_name' => @na_target && @na_target.name,
                'linked_count' => @na_target ? @na_target.definition.instances.length : 0,
                'source_name' => na_source ? Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetDisplayName : nil,
                'source_dimensions' => na_source ? [na_source[:width], na_source[:depth], na_source[:height]].map { |na_value| (na_value * 25.4).round(1) } : nil
            })
        end

        def self.Na__Dialog__PushGallery
            Na__Dialog__Send('gallery', Na__ArrayBuilder__PresetsLibrary.Na__Presets__Scan)
        end

        def self.Na__Dialog__LoadPreset(na_id, na_editor)
            na_record = Na__ArrayBuilder__PresetsLibrary.Na__Presets__Read(na_id)
            # Load first; a damaged source cannot discard the current edit session.
            Na__ArrayBuilder__PresetsLibrary.Na__Presets__LoadSource(@na_model, na_record)
            Na__Dialog__StopTool()
            @na_target = nil
            @na_config = na_record['configuration']
            Na__Dialog__NewContext()
            Na__Dialog__PushState()
            Na__Dialog__Preview()
            Na__Dialog__Send(na_editor ? 'preset_edit' : 'preset_loaded', na_record)
        end

        def self.Na__Dialog__Signature
            return nil unless @na_target && @na_target.valid?
            [@na_target.transformation.to_a, @na_target.locked?,
             @na_target.definition.get_attribute(Na__ArrayBuilder__DataSerializer::NA_DEFINITION_DICT, 'data')]
        end

        # FUNCTION | Observers Schedule This Read; They Never Write Model Data
        # ------------------------------------------------------------
        def self.Na__Dialog__Synchronise
            return unless @na_ready && !@na_busy
            if @na_model != Sketchup.active_model
                Na__Dialog__StopTool()
                @na_model = Sketchup.active_model
                @na_target = nil
                @na_config = Na__ArrayBuilder__DataSerializer.Na__Data__ModelSettings(@na_model)
                Na__ArrayBuilder__ObjectRegistry.Na__Registry__Clear
                Na__Dialog__NewContext()
            elsif @na_edit_path != (@na_model.active_path || []).map(&:persistent_id) ||
                  (@na_target && (!@na_target.valid? || @na_target.locked? || @na_model.selection.to_a != [@na_target]))
                Na__Dialog__StopTool()
                @na_target = nil
                Na__Dialog__NewContext()
                na_send_status_to_dialog('info', 'Selection changed. Use Edit selected to open an array.')
            elsif @na_target && @na_signature != Na__Dialog__Signature()
                # Undo / Redo / external edits reload the saved recipe and cancel stale UI events.
                @na_config = Na__ArrayBuilder__DataSerializer.Na__Data__Load(@na_target)['configuration']
                Na__ArrayBuilder__DataSerializer.Na__Data__RestoreSource(@na_target, Na__ArrayBuilder__DataSerializer.Na__Data__Load(@na_target))
                Na__Dialog__NewContext()
                @na_signature = Na__Dialog__Signature()
                Na__Dialog__Preview()
            end
            Na__Dialog__PushState()
        rescue StandardError => na_error
            @na_target = nil
            Na__Dialog__NewContext()
            Na__Dialog__PushState()
            na_send_status_to_dialog('warning', na_error.message)
        end

# endregion -------------------------------------------------------------------

    end # module Na__ArrayBuilder__DialogManager
end # module Na__ArrayBuilderTools
