# frozen_string_literal: true
# Noble vegetation scatter menu. Explicit regenerate; no per-slider model work.
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__ScatterTool__'
module Na__Noble3dModellingTools
    module Na__VegetationSketcher__ScatterDialog
        NA_PREFIX = 'Na__Noble3dModellingTools__VegetationSketcher__'.freeze

        def self.Na__VegetationSketcher__Scatter__ShowDialog
            return @na_dialog.bring_to_front if @na_dialog && @na_dialog.visible?
            @na_options = Na__VegetationSketcher__ScatterCore.na_options
            @na_sources, @na_context = [], 0
            @na_session = "#{Time.now.to_f}-scatter"
            @na_epoch = (@na_epoch || 0) + 1
            na_attach
            @na_dialog = UI::HtmlDialog.new(dialog_title: 'Na Noble3d Tools : Vegetation Scatter',
                preferences_key: 'Na__NobleVegetationScatter', style: UI::HtmlDialog::STYLE_DIALOG,
                width: 540, height: 840, min_width: 450, min_height: 600, resizable: true, scrollable: false)
            html = File.read(File.join(__dir__,NA_PREFIX+'ScatterUi__.html'))
            html = html.gsub('{{STYLESHEET_CONTENT}}') { File.read(File.join(__dir__,NA_PREFIX+'Styles__.css')) }
            html = html.gsub('{{UI_BRIDGE_SCRIPT}}') { File.read(File.join(__dir__,NA_PREFIX+'ScatterUi__.js')) }
            @na_dialog.set_html(html)
            @na_dialog.add_action_callback('na_scatter_ready') { |_|
                @na_ready = true
                na_sync
                na_state(true)
            }
            @na_dialog.add_action_callback('na_scatter_event') { |_,raw| na_event(raw) }
            @na_dialog.set_on_closed { self.Na__VegetationSketcher__Scatter__ResetDialog }
            @na_dialog.show
        end

        def self.Na__VegetationSketcher__Scatter__ResetDialog
            dialog, @na_dialog = @na_dialog, nil
            @na_ready = false
            @na_epoch = (@na_epoch || 0) + 1
            UI.stop_timer(@na_timer) if @na_timer
            @na_timer = nil
            @na_tool.na_stop if @na_tool
            @na_tool = nil
            na_detach
            dialog.close if dialog && dialog.visible?
        end

        def self.na_attach
            return if @na_model == Sketchup.active_model
            @na_tool.na_stop if @na_tool
            na_detach
            @na_model = Sketchup.active_model
            @na_target, @na_signature, @na_tool = nil, nil, nil
            @na_sources = []
            @na_reload_form = true
            @na_context += 1
            @na_selection_observer = Na__VegetationSketcher__ScatterSelectionObserver.new
            @na_model_observer = Na__VegetationSketcher__ScatterModelObserver.new
            @na_app_observer = Na__VegetationSketcher__ScatterAppObserver.new
            @na_model.selection.add_observer(@na_selection_observer)
            @na_model.add_observer(@na_model_observer)
            Sketchup.add_observer(@na_app_observer)
        end

        def self.na_detach
            @na_model.selection.remove_observer(@na_selection_observer) if @na_model && @na_selection_observer
            @na_model.remove_observer(@na_model_observer) if @na_model && @na_model_observer
            Sketchup.remove_observer(@na_app_observer) if @na_app_observer
            @na_model = @na_selection_observer = @na_model_observer = @na_app_observer = nil
        end

        def self.na_queue_sync
            return unless @na_dialog && @na_ready && !@na_timer
            epoch = @na_epoch
            @na_timer = UI.start_timer(0.15,false) do
                @na_timer = nil
                next unless @na_dialog && @na_ready && epoch == @na_epoch
                @na_busy ? na_queue_sync : na_sync
            end
        end

        def self.na_sync
            na_attach
            if @na_tool
                @na_tool.na_stop unless @na_tool.na_context?
                return if @na_tool
            end
            selected = @na_model.selection.to_a
            entity = selected.length == 1 ? selected.first : nil
            forest = Na__VegetationSketcher__ScatterModel.na_forest?(entity) && !entity.locked? && @na_model.active_entities.include?(entity)
            signature = [selected.map(&:persistent_id), entity && entity.get_attribute(Na__VegetationSketcher__ScatterModel::NA_DICT,'data'), forest, (@na_model.active_path || []).map(&:persistent_id)]
            return if signature == @na_signature
            @na_signature = signature
            @na_context += 1
            @na_target = forest ? entity : nil
            if @na_target
                data = Na__VegetationSketcher__ScatterModel.na_load(@na_target)
                @na_options, @na_sources = data.values_at('options','sources')
            end
            na_state(!!@na_target)
        rescue StandardError => error
            @na_target = nil
            na_status(error.message,true)
            na_state(false)
        end

        def self.na_target_id; @na_target && @na_target.valid? ? @na_target.persistent_id.to_s : nil; end
        def self.na_validate(payload)
            raise ArgumentError, 'The selection changed. Use the refreshed scatter menu.' unless payload['context'] == @na_context && payload['target_id'] == na_target_id
        end

        def self.na_apply(payload)
            @na_options = Na__VegetationSketcher__ScatterCore.na_options(payload.fetch('options'))
            weights = payload.fetch('weights')
            raise ArgumentError, 'The source mix changed. Capture or load it again.' unless weights.is_a?(Hash) && weights.keys.sort == @na_sources.map { |s| s['key'] }.sort
            sources = @na_sources.map { |s| s.merge('weight' => weights.fetch(s['key'])) }
            Na__VegetationSketcher__ScatterCore.na_weights(sources)
            @na_sources = sources
        end

        def self.na_event(raw)
            request = JSON.parse(raw)
            raise ArgumentError, 'Invalid scatter command.' unless request.is_a?(Hash) && request['session'] == @na_session
            raise ArgumentError, 'The scatter menu is busy.' if @na_busy
            @na_busy = true
            entered = true
            na_attach
            payload, action = request.fetch('payload'), request['action']
            na_validate(payload)
            raise ArgumentError, 'Finish the active brush before changing scatter settings.' if @na_tool && action != 'finish'
            store = Na__VegetationSketcher__ScatterModel
            case action
            when 'bed_mix', 'flower_mix'
                flowers = action == 'flower_mix'
                @na_sources = store.na_bed_sources(flowers ? 'flowers' : 'shrubs')
                @na_options = Na__VegetationSketcher__ScatterCore.na_options('radius' => flowers ? 900 : 1200, 'spacing' => flowers ? 500 : 650, 'scale_min' => 90, 'scale_max' => 110, 'limit' => flowers ? 1000 : 1500)
                @na_target = nil
                @na_context += 1
                # Do not reload a previously selected forest after loading a new mix.
                @na_model.selection.clear
                na_status((flowers ? 'Flowers and grasses' : 'Planting-bed') + ' mix loaded: six forms, two variations each. Adjust weights, then paint a new bed.')
            when 'capture'
                @na_sources = store.na_capture(@na_model)
                @na_target = nil
                @na_context += 1
                na_status("Captured #{@na_sources.length} source items. Set their weights, then paint a new forest.")
            when 'paint'
                na_apply(payload)
                definitions = store.na_definitions(@na_model,@na_sources,@na_target)
                @na_sources = @na_sources.each_with_index.map { |s,i| s.merge('definition_pid' => definitions[i] && definitions[i].persistent_id) }
                @na_target = nil
                @na_context += 1
                @na_tool = Na__VegetationSketcher__ScatterTool.new(@na_model,@na_options,@na_sources,self)
                @na_model.select_tool(@na_tool)
                Sketchup.focus if Sketchup.respond_to?(:focus)
                na_status('Drag on a face or terrain. Release to plant each stroke; Finish ends the brush.')
            when 'regenerate', 'variation'
                unless @na_target && @na_model.selection.to_a == [@na_target] && !@na_target.locked? && @na_model.active_entities.include?(@na_target)
                    raise ArgumentError, 'Select one unlocked Noble forest in the current editing context.'
                end
                na_apply(payload)
                @na_options['seed'] = @na_options['seed'] % 2147483646 + 1 if action == 'variation'
                data = store.na_load(@na_target)
                result = store.na_generate(@na_model,@na_options,@na_sources,data['dabs'])
                store.na_rebuild(@na_model,@na_target,@na_options,@na_sources,data['dabs'],result)
                na_status("Regenerated #{result[:plants].length} plants.#{result[:capped] ? ' Plant limit reached.' : ''}")
                @na_signature = nil
            when 'finish'
                @na_tool.na_stop if @na_tool
            else
                raise ArgumentError, 'Unknown scatter action.'
            end
            na_state(true)
            na_send('ack',{ id: request['id'], success: true })
        rescue StandardError => error
            na_status(error.message,true)
            na_state(false)
            na_send('ack',{ id: request.is_a?(Hash) ? request['id'] : nil, success: false })
        ensure
            if entered
                @na_busy = false
                na_queue_sync
            end
        end

        def self.na_state(load)
            begin
                count = @na_target && @na_target.valid? ? Na__VegetationSketcher__ScatterModel.na_load(@na_target)['count'] : nil
            rescue StandardError
                # A damaged/deleted target must not prevent a failure ACK.
                @na_target = nil
                @na_context += 1
                count = nil
            end
            load ||= @na_reload_form
            @na_reload_form = false
            na_send('state',{ session: @na_session, context: @na_context, target_id: na_target_id, count: count,
                painting: !!@na_tool, options: @na_options, sources: @na_sources, load: load,
                selected: @na_model ? @na_model.selection.length : 0 })
        end
        def self.na_send(event,payload)
            return unless @na_dialog && @na_ready
            @na_dialog.execute_script("if(window.Na__VegetationScatter__Receive){window.Na__VegetationScatter__Receive(#{JSON.generate(event)},#{JSON.generate(payload)});}")
        end
        def self.na_status(message,error = false); na_send('status',{ message: message, error: error }); end
        def self.na_painted(group,result)
            na_status("#{result[:plants].length} plants.#{result[:capped] ? ' Plant limit reached.' : ''} Paint another stroke, or Finish to edit.")
        end
        def self.na_tool_finished(tool)
            return unless @na_tool == tool
            @na_tool = nil
            if tool.na_group && tool.na_group.valid? && @na_model == Sketchup.active_model
                @na_model.selection.clear
                @na_model.selection.add(tool.na_group)
            end
            @na_signature = nil
            na_state(false)
            na_queue_sync
        end
    end

    class Na__VegetationSketcher__ScatterSelectionObserver < Sketchup::SelectionObserver
        def onSelectionBulkChange(_); Na__VegetationSketcher__ScatterDialog.na_queue_sync; end
        def onSelectionAdded(*); Na__VegetationSketcher__ScatterDialog.na_queue_sync; end
        def onSelectionRemoved(*); Na__VegetationSketcher__ScatterDialog.na_queue_sync; end
        def onSelectionCleared(*); Na__VegetationSketcher__ScatterDialog.na_queue_sync; end
    end
    class Na__VegetationSketcher__ScatterModelObserver < Sketchup::ModelObserver
        def onTransactionCommit(*); Na__VegetationSketcher__ScatterDialog.na_queue_sync; end
        def onTransactionUndo(*); Na__VegetationSketcher__ScatterDialog.na_queue_sync; end
        def onTransactionRedo(*); Na__VegetationSketcher__ScatterDialog.na_queue_sync; end
        def onTransactionAbort(*); Na__VegetationSketcher__ScatterDialog.na_queue_sync; end
        def onActivePathChanged(*); Na__VegetationSketcher__ScatterDialog.na_queue_sync; end
    end
    class Na__VegetationSketcher__ScatterAppObserver < Sketchup::AppObserver
        def onNewModel(*); Na__VegetationSketcher__ScatterDialog.na_queue_sync; end
        def onOpenModel(*); Na__VegetationSketcher__ScatterDialog.na_queue_sync; end
        def onActivateModel(*); Na__VegetationSketcher__ScatterDialog.na_queue_sync; end
    end
end
