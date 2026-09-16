# frozen_string_literal: true

module Na__Noble3dModellingTools
  module Na__VegetationSketcher
    module Dialog
      PREFS = 'Na__Noble3dModellingTools__VegetationSketcher'.freeze
      PREFIX = 'Na__Noble3dModellingTools__VegetationSketcher__'.freeze
      PANEL_DEBOUNCE = 0.65

      def self.show
        if @dialog && @dialog.visible?
          @dialog.bring_to_front
          return @dialog
        end
        @ready, @busy, @live = false, false, true
        @context = 0
        @session = "#{Time.now.to_f}-#{object_id}"
        @selection_signature = nil
        @epoch = (@epoch || 0) + 1
        attach_model
        @app_observer = AppObserver.new(self)
        Sketchup.add_observer(@app_observer)
        @dialog = UI::HtmlDialog.new(dialog_title: 'Na Noble3d Tools : Vegetation Sketcher',
          preferences_key: PREFS, style: UI::HtmlDialog::STYLE_DIALOG,
          width: 510, height: 900, min_width: 420, min_height: 620, resizable: true, scrollable: false)
        html = File.read(File.join(__dir__, PREFIX + 'UiLayout__.html'))
        html = html.gsub('{{STYLESHEET_CONTENT}}') { File.read(File.join(__dir__, PREFIX + 'Styles__.css')) }
        html = html.gsub('{{UI_BRIDGE_SCRIPT}}') { File.read(File.join(__dir__, PREFIX + 'UiBridge__.js')) }
        @dialog.set_html(html)
        @dialog.add_action_callback('na_ready') do |_context|
          begin
            first_ready = !@ready
            @ready = true
            sync_selection(force: first_ready)
            push_state
            preview
          rescue StandardError => e
            report_error(e)
          end
        end
        @dialog.add_action_callback('na_event') { |_context, raw| handle_event(raw) }
        @dialog.set_on_closed { teardown }
        @dialog.show
        @dialog
      end

      # One acknowledged command at a time. An edit carries the selection context
      # and persistent ID, so a delayed slider cannot update a different entity.
      def self.handle_event(raw)
        request = JSON.parse(raw)
        raise ArgumentError, 'Invalid bridge request.' unless request.is_a?(Hash)
        raise ArgumentError, 'The dialog was reloaded. Reopen Vegetation Sketcher.' unless request['session'] == @session
        raise ArgumentError, 'Vegetation Sketcher is busy.' if @busy
        @busy = true
        entered = true
        @source_revision = request['revision']
        dispatch(request['action'], request['payload'] || {})
        send_js('ack', { id: request['id'], success: true })
      rescue StandardError => e
        report_error(e)
        send_js('ack', { id: request.is_a?(Hash) ? request['id'] : nil, success: false })
      ensure
        if entered
          @busy = false
          @source_revision = nil
          queue_sync
        end
      end

      def self.dispatch(action, payload)
        attach_model
        case action
        when 'options', 'variation'
          validate_context(payload)
          options = Options.resolve(payload.fetch('settings'))
          options['seed'] = options['seed'] % 2147483646 + 1 if action == 'variation'
          apply_options(options)
          update_target(payload) if @target && @live && !placing?
          push_state
          preview
        when 'preset'
          stop
          new_mode
          apply_options(Options.preset(payload['preset']))
          push_state
          preview
        when 'tree_type'
          validate_context(payload)
          raise ArgumentError, 'Choose the Tree preset first.' unless @options['preset'] == 'tree'
          options = Options.tree_preset(payload['tree_type'])
          %w[seed smooth vary].each { |key| options[key] = @options[key] }
          apply_options(options)
          update_target(payload) if @target && @live && !placing?
          push_state
          preview
          report(Options.label(@options) + ' dimensions loaded. Adjust the size, then plant or update the selected tree.')
        when 'new'
          stop
          new_mode
          push_state
          preview
          report('Ready to create new vegetation. Click Draw in SketchUp.')
        when 'start'
          stop
          new_mode
          apply_options(payload.fetch('settings'))
          tool_class = @options['preset'] == 'hedge' ? HedgeTool : PlacementTool
          @tool = tool_class.new(@options, self)
          @observed_model.select_tool(@tool)
          @observed_model.active_view.invalidate
          Sketchup.focus if Sketchup.respond_to?(:focus)
          push_state
          report(@options['preset'] == 'hedge' ? 'Click or drag the first run, then click each corner. Enter or Finish creates the joined hedge.' : 'Plant mode is active. Click in SketchUp to create vegetation.')
        when 'stop'
          apply_options(payload['settings']) if payload['settings']
          @tool.finish_path if placing? && @tool.respond_to?(:finish_path)
          stop
          sync_selection(force: true)
          push_state
          report('Placement finished. Select vegetation to edit it, or draw a new form.')
        when 'load'
          sync_selection(force: true)
        when 'update'
          validate_context(payload)
          apply_options(payload.fetch('settings'))
          update_target(payload)
          push_state
          preview
        when 'live'
          validate_context(payload)
          @live = payload['enabled'] == true
          push_state
          report(@live ? 'Live editing enabled. Changes update the selected vegetation.' : 'Live editing paused. Use Update selected to apply changes.')
        else
          raise ArgumentError, "Unknown vegetation action: #{action}"
        end
      end

      def self.apply_options(raw)
        @options = Options.resolve(raw)
        Sketchup.write_default(PREFS, 'settings', JSON.generate(@options))
        @tool.update_options(@options) if placing?
      end

      def self.validate_context(payload)
        unless payload['context'] == @context && payload['target_id'] == target_id
          raise ArgumentError, 'Selection changed. The panel has refreshed; apply your change again.'
        end
        if @target && (!editable?(@target) || selected_entity != @target)
          queue_sync
          raise ArgumentError, 'The editing target changed or is locked. Select editable vegetation again.'
        end
      end

      def self.update_target(payload)
        validate_context(payload)
        raise ArgumentError, 'Select Noble vegetation to edit. Use Draw in SketchUp to create new vegetation.' unless @target
        if DataSerializer.load(@target) != @options
          Builder.update(@observed_model, @target, @options)
          @observed_model.active_view.invalidate
          report('Updated ' + @target.name + '. Undo restores its previous shape.', 'success')
        end
        @selection_signature = selection_signature
      end

      def self.new_mode
        cancel_panel
        detach_target
        @target = @last_created = nil
        @options = @options.merge('path' => nil) if @options
        @context += 1
        @selection_signature = selection_signature
        @selection_path = (@observed_model.active_path || []).map(&:persistent_id)
      end

      def self.selected_entity
        selection = @observed_model.selection.to_a
        selection.length == 1 ? selection.first : nil
      end

      def self.editable?(entity)
        DataSerializer.has_data?(entity) && !entity.locked? && @observed_model.active_entities.include?(entity)
      end

      def self.target_id
        @target && @target.valid? ? @target.persistent_id.to_s : nil
      end

      def self.selection_signature
        @observed_model.selection.to_a.map do |entity|
          if DataSerializer.container?(entity)
            [entity.persistent_id, entity.locked?, entity.name, entity.transformation.to_a,
             entity.definition.get_attribute(DataSerializer::DEFINITION_DICT, 'data'),
             entity.get_attribute(DataSerializer::INSTANCE_DICT, 'settings')]
          else
            [entity.entityID]
          end
        end
      end

      def self.sync_selection(force: false)
        return unless @dialog && @ready
        attach_model
        if placing? && !@tool.valid_context?
          stop
          force = true
          report('Editing context changed. Click Draw in SketchUp to start again.')
        end
        return if placing?
        signature = selection_signature
        path = (@observed_model.active_path || []).map(&:persistent_id)
        return if !force && signature == @selection_signature && path == @selection_path
        cancel_panel
        @selection_signature, @selection_path = signature, path
        detach_target
        @target = nil
        @context += 1
        entity = selected_entity
        if editable?(entity)
          @options = DataSerializer.load(entity)
          @target = entity
          @entity_observer = EntityObserver.new(self)
          entity.add_observer(@entity_observer)
          report('Selected ' + entity.name + '. Its saved settings are loaded.')
        elsif DataSerializer.has_data?(entity) && entity.locked?
          report('Selected vegetation is locked. Unlock it to edit, or draw a new form.')
        else
          report('Ready to create vegetation. No selection is needed.')
        end
        push_state
        preview
      rescue StandardError => e
        @target = nil
        push_state
        report_error(e)
      end

      def self.attach_model
        model = Sketchup.active_model
        return if @observed_model == model
        stop
        detach_model
        @observed_model = model
        @selection_observer = SelectionObserver.new(self)
        @model_observer = ModelObserver.new(self)
        model.selection.add_observer(@selection_observer)
        model.add_observer(@model_observer)
        @options = DataSerializer.model_options(model, Sketchup.read_default(PREFS, 'settings', '{}'))
        @target = @selection_signature = @last_created = nil
        @context = (@context || 0) + 1
      end

      def self.queue_sync
        return unless @dialog && @ready
        return if @sync_timer
        epoch = @epoch
        @sync_timer = UI.start_timer(0.05, false) do
          @sync_timer = nil
          next unless epoch == @epoch && @dialog && @ready
          @busy ? queue_sync : sync_selection
        end
      end

      def self.detach_target
        @target.remove_observer(@entity_observer) if @target && @target.valid? && @entity_observer
      ensure
        @entity_observer = nil
      end

      def self.detach_model
        detach_target
        if @observed_model
          @observed_model.selection.remove_observer(@selection_observer) if @selection_observer
          @observed_model.remove_observer(@model_observer) if @model_observer
        end
      rescue StandardError => e
        puts "[Noble Vegetation] Observer detach: #{e.message}"
      ensure
        @observed_model = @selection_observer = @model_observer = nil
      end

      def self.preview
        queue_panel(preview: true) if @options
      end

      # Do not build or serialise meshes on the mouse-event path. The latest
      # panel request wins after a quiet period; acknowledgements stay immediate.
      def self.queue_panel(preview: nil, progress: nil)
        return unless @dialog && @ready
        @pending_preview = preview unless preview.nil?
        @pending_progress = progress unless progress.nil?
        UI.stop_timer(@panel_timer) if @panel_timer
        token = @panel_token = (@panel_token || 0) + 1
        epoch, model, context, tool = @epoch, @observed_model, @context, @tool
        @panel_timer = UI.start_timer(PANEL_DEBOUNCE, false) do
          next unless token == @panel_token && epoch == @epoch && @dialog && @ready
          @panel_timer = nil
          if model != Sketchup.active_model || context != @context || tool != @tool
            cancel_panel
            next
          end
          if @busy
            queue_panel
            next
          end
          data, progress_data = @pending_preview, @pending_progress
          @pending_preview = @pending_progress = nil
          if data
            if data == true
              data = @tool.preview_data if placing? && @tool.respond_to?(:preview_data)
              data = Mesh.build(@options, preview: true) if data.nil? || data == true
            end
            send_js('preview', data)
          end
          send_js('viewport', progress_data) if progress_data
        rescue StandardError => e
          report_error(e)
        end
      end

      def self.cancel_panel
        @panel_token = (@panel_token || 0) + 1
        UI.stop_timer(@panel_timer) if @panel_timer
        @panel_timer = @pending_preview = @pending_progress = nil
      end

      def self.push_state
        send_js('state', { settings: @options, limit: Mesh::MAX_QUADS, limits: Options::LIMITS, tree_types: Options.tree_type_info,
          context: @context, target_id: target_id, target_name: @target && @target.valid? ? @target.name : nil,
          placing: placing?, live: @live, session: @session, revision: @source_revision })
      end

      def self.tool_progress(length, phase, count = nil)
        queue_panel(progress: { length: length && length.round(1), phase: phase, quads: count })
      end

      def self.tool_preview(data)
        queue_panel(preview: data)
      end

      def self.created(entity)
        @last_created = entity
        @observed_model.selection.clear
        @observed_model.selection.add(entity)
        report('Created ' + entity.name + '. Continue drawing, or Finish to edit it.', 'success')
        send_js('created', { id: entity.persistent_id.to_s, name: entity.name })
      end

      def self.new_variation
        apply_options(@options.merge('seed' => @options['seed'] % 2147483646 + 1))
        push_state
        preview
      end

      def self.report(message, variant = 'info')
        send_js('status', { message: message, variant: variant })
      end

      def self.report_error(error)
        report(error.message, 'error')
        puts "[Noble Vegetation] #{error.class}: #{error.message}\n#{error.backtrace&.first(5)&.join("\n")}"
      end

      def self.send_js(event, payload)
        return unless @dialog && @ready
        @dialog.execute_script("if(window.NaVegetation){window.NaVegetation.receive(#{JSON.generate(event)}, #{JSON.generate(payload)});}")
      end

      def self.placing?
        !!(@tool && @tool.active?)
      end

      def self.tool_stopped(tool)
        return unless @tool == tool
        cancel_panel
        @tool = nil
        @selection_signature = nil
        push_state
        queue_sync
      end

      def self.stop
        cancel_panel
        current = @tool
        @tool = nil
        current.model.select_tool(nil) if current && current.active? && current.model == Sketchup.active_model
      end

      def self.teardown
        @ready = false
        @epoch = (@epoch || 0) + 1
        UI.stop_timer(@sync_timer) if @sync_timer
        @sync_timer = nil
        stop
        detach_model
        Sketchup.remove_observer(@app_observer) if @app_observer
        @app_observer = @target = @dialog = nil
      end

      def self.reset
        dialog = @dialog
        teardown
        dialog.close if dialog && dialog.visible?
      end
    end
  end
end
