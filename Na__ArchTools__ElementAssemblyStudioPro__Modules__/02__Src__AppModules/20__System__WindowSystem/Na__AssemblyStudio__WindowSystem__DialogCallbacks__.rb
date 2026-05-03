# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM DIALOG CALLBACKS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__DialogCallbacks__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks
# AUTHOR     : Noble Architecture
# PURPOSE    : All window-tab specific JS->Ruby callbacks. Extracted from the
#              old 1037-line DialogManager so AppCore::DialogManager owns only
#              the generic chrome.
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__UiBridge__'
require_relative '../06__Tools__MeasurementTools/Na__AssemblyStudio__MeasurementTools__TwoPointOpeningTool__'
require_relative '../07__Tools__PlacementTools/Na__AssemblyStudio__PlacementTools__WindowPlacementTool__'
require_relative 'Na__AssemblyStudio__WindowSystem__GeometryEngine__'
require_relative 'Na__AssemblyStudio__WindowSystem__DataSerializer__'
require_relative 'Na__AssemblyStudio__WindowSystem__DxfExporter__'
require_relative 'Na__AssemblyStudio__WindowSystem__FuseParts__'

module Na__AssemblyStudio
    module Na__WindowSystem
        module Na__DialogCallbacks

            DebugTools     = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
            UiBridge       = Na__AssemblyStudio::Na__AppCore::Na__UiBridge
            DataSerializer = Na__AssemblyStudio::Na__WindowSystem::Na__DataSerializer
            GeometryEngine = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryEngine
            DxfExporter    = Na__AssemblyStudio::Na__WindowSystem::Na__DxfExporter
            FuseParts      = Na__AssemblyStudio::Na__WindowSystem::Na__FuseParts
            TwoPoint       = Na__AssemblyStudio::Na__MeasurementTools::Na__TwoPointOpeningTool
            PlacementTool  = Na__AssemblyStudio::Na__PlacementTools::Na__WindowPlacementTool

            @na_dialog               = nil
            @na_window_component     = nil
            @na_config               = nil
            @na_last_measure_origin  = nil
            @na_current_placement_tool = nil

            def self.na_attach_dialog(dialog)
                @na_dialog = dialog
            end

            def self.na_callback_registry
                {
                    "na_createWindow"    => proc { |json| na_handle_create_window(json) },
                    "na_updateWindow"    => proc { |json| na_handle_update_window(json) },
                    "na_exportDxf"       => proc { |json| na_handle_export_dxf(json) },
                    "na_liveUpdate"      => proc { |json| na_handle_live_update(json) },
                    "na_requestConfig"   => proc { na_send_config_to_dialog },
                    "na_measureOpening"  => proc { na_handle_measure_opening },
                    "na_keyboard_tab"    => proc { @na_current_placement_tool.na_rotate if @na_current_placement_tool }
                }
            end

            def self.na_default_config
                Na__AssemblyStudio::Na__WindowSystem::Na__Defaults.na_default_config
            end

            def self.na_check_initial_selection
                selection = Sketchup.active_model.selection
                if selection.length == 1 && selection.first.is_a?(Sketchup::ComponentInstance)
                    instance  = selection.first
                    window_id = DataSerializer.na_get_window_id_from_instance(instance)
                    if window_id
                        DebugTools.na_debug_window("Existing window in selection: #{window_id}")
                        na_load_window_into_dialog(instance, window_id)
                        return
                    end
                end
                @na_config = UiBridge.na_deep_clone(na_default_config)
            end

            # -----------------------------------------------------------------
            # REGION | Selection coordinator hooks
            # -----------------------------------------------------------------

            def self.na_load_window_into_dialog(instance, window_id)
                @na_window_component = instance
                @na_config           = DataSerializer.na_load_window_data_from_instance(instance, window_id)
                if @na_config
                    na_send_config_to_dialog
                    UiBridge.na_send_status(@na_dialog, 'info', "Loaded window: #{window_id}")
                else
                    DebugTools.na_debug_warn("Could not load config for window #{window_id}")
                    @na_config = UiBridge.na_deep_clone(na_default_config)
                    na_send_config_to_dialog
                    UiBridge.na_send_status(@na_dialog, 'warning', "Window #{window_id} selected but no saved config found")
                end
            end

            def self.na_clear_window_from_dialog
                @na_window_component = nil
                @na_config           = UiBridge.na_deep_clone(na_default_config)
                UiBridge.na_invoke(@na_dialog, 'window.na_clearCurrentWindow')
            end

            # -----------------------------------------------------------------
            # REGION | Create / Update / Live / DXF / Measure handlers
            # -----------------------------------------------------------------

            def self.na_handle_create_window(config_json)
                config    = JSON.parse(config_json)
                @na_config = config
                model     = Sketchup.active_model
                model.start_operation("Create Window", true)

                window_id = DataSerializer.na_generate_next_window_id
                if @na_config["windowMetadata"] && @na_config["windowMetadata"][0]
                    @na_config["windowMetadata"][0]["WindowUniqueId"] = window_id
                    @na_config["windowMetadata"][0]["CreatedDate"]    = Time.now.strftime("%Y-%m-%d %H:%M:%S")
                    @na_config["windowMetadata"][0]["LastModified"]   = Time.now.strftime("%Y-%m-%d %H:%M:%S")
                end

                pending_origin = na_consume_pending_measurement_origin

                @na_window_component = GeometryEngine.na_create_window_geometry(
                    config["windowConfiguration"], window_id, pending_origin
                )

                if @na_window_component && @na_window_component.valid?
                    if config["windowConfiguration"] && config["windowConfiguration"]["fuse_parts"] == true
                        UiBridge.na_send_status(@na_dialog, 'info', 'Fusing parts...')
                        FuseParts.na_fuse_window_parts(@na_window_component.definition.entities)
                    end

                    description = nil
                    if @na_config["windowMetadata"] && @na_config["windowMetadata"][0]
                        description = @na_config["windowMetadata"][0]["WindowDescription"]
                    end

                    DataSerializer.na_set_window_id_on_instance(@na_window_component, window_id, description)
                    DataSerializer.na_save_window_data(window_id, @na_config)
                    model.commit_operation

                    if pending_origin
                        UiBridge.na_send_status(@na_dialog, 'success', "Window placed at measured Point A: #{window_id}")
                    else
                        @na_current_placement_tool = PlacementTool.new(@na_window_component)
                        Sketchup.active_model.select_tool(@na_current_placement_tool)
                        UiBridge.na_invoke(@na_dialog, 'window.na_setPlacementActive', 'true')
                        UiBridge.na_send_status(@na_dialog, 'success', "Window created: #{window_id}")
                    end
                else
                    model.abort_operation
                    UiBridge.na_send_status(@na_dialog, 'error', 'Failed to create window geometry')
                end
            rescue StandardError => e
                begin; model.abort_operation if model; rescue StandardError; end
                DebugTools.na_debug_error("Error creating window", e)
                UiBridge.na_send_status(@na_dialog, 'error', "Error: #{e.message}")
            end

            def self.na_handle_update_window(config_json)
                config = JSON.parse(config_json)
                @na_config = config

                unless @na_window_component && @na_window_component.valid?
                    UiBridge.na_send_status(@na_dialog, 'warning', 'No window selected to update')
                    return
                end

                window_id = DataSerializer.na_get_window_id_from_instance(@na_window_component)
                unless window_id
                    UiBridge.na_send_status(@na_dialog, 'warning', 'Selected component is not a configurable window')
                    return
                end

                model = Sketchup.active_model
                model.start_operation("Update Window", true)

                if @na_config["windowMetadata"] && @na_config["windowMetadata"][0]
                    @na_config["windowMetadata"][0]["LastModified"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
                end

                GeometryEngine.na_update_window_geometry(@na_window_component, config["windowConfiguration"])

                if config["windowConfiguration"] && config["windowConfiguration"]["fuse_parts"] == true
                    UiBridge.na_send_status(@na_dialog, 'info', 'Fusing parts...')
                    FuseParts.na_fuse_window_parts(@na_window_component.definition.entities)
                end

                description = nil
                if @na_config["windowMetadata"] && @na_config["windowMetadata"][0]
                    description = @na_config["windowMetadata"][0]["WindowDescription"]
                end
                DataSerializer.na_set_window_id_on_instance(@na_window_component, window_id, description)
                DataSerializer.na_save_window_data(window_id, @na_config)
                model.commit_operation
                UiBridge.na_send_status(@na_dialog, 'success', "Window updated: #{window_id}")
            rescue StandardError => e
                begin; model.abort_operation if model; rescue StandardError; end
                DebugTools.na_debug_error("Error updating window", e)
                UiBridge.na_send_status(@na_dialog, 'error', "Error: #{e.message}")
            end

            def self.na_handle_export_dxf(config_json)
                config      = JSON.parse(config_json)
                dxf_content = DxfExporter.na_generate_dxf(config)
                unless dxf_content
                    UiBridge.na_send_status(@na_dialog, 'error', 'Failed to generate DXF content')
                    return
                end

                path = UI.savepanel("Export DXF", "", "window_export.dxf")
                if path
                    path = path + ".dxf" unless path.downcase.end_with?(".dxf")
                    File.write(path, dxf_content)
                    UiBridge.na_send_status(@na_dialog, 'success', "DXF exported: #{File.basename(path)}")
                end
            rescue JSON::ParserError => e
                DebugTools.na_debug_error("Invalid JSON in DXF export", e)
                UiBridge.na_send_status(@na_dialog, 'error', 'Invalid configuration data')
            rescue StandardError => e
                DebugTools.na_debug_error("Error exporting DXF", e)
                UiBridge.na_send_status(@na_dialog, 'error', "Export failed: #{e.message}")
            end

            def self.na_handle_live_update(config_json)
                config = JSON.parse(config_json)

                incoming_id = nil
                if config["windowMetadata"] && config["windowMetadata"][0]
                    incoming_id = config["windowMetadata"][0]["WindowUniqueId"]
                end

                current_id = nil
                if @na_window_component && @na_window_component.valid?
                    current_id = DataSerializer.na_get_window_id_from_instance(@na_window_component)
                end

                if incoming_id && current_id && incoming_id != current_id
                    DebugTools.na_debug_warn("Live update skipped: stale data for #{incoming_id}, current is #{current_id}")
                    return
                end

                @na_config = config
                target_instance = GeometryEngine.na_find_live_update_target(@na_window_component)
                unless target_instance
                    UiBridge.na_send_status(@na_dialog, 'warning', 'Select a window to use Live Mode')
                    return
                end

                @na_window_component = target_instance
                window_id = DataSerializer.na_get_window_id_from_instance(target_instance)
                unless window_id
                    UiBridge.na_send_status(@na_dialog, 'warning', 'Selected item is not a Na Window')
                    return
                end

                model = Sketchup.active_model
                model.start_operation("Live Update Window", true, false, true)
                GeometryEngine.na_update_window_geometry(target_instance, config["windowConfiguration"])

                if config["windowConfiguration"] && config["windowConfiguration"]["fuse_parts"] == true
                    begin
                        FuseParts.na_fuse_window_parts(target_instance.definition.entities)
                    rescue StandardError => e
                        DebugTools.na_debug_error("Fuse Parts error in Live Mode (non-fatal)", e)
                    end
                end

                DataSerializer.na_save_window_data(window_id, @na_config)
                model.commit_operation
                model.active_view.invalidate
                DebugTools.na_debug_success("Live update applied to #{window_id}")
            rescue StandardError => e
                DebugTools.na_debug_error("Error in live update", e)
                UiBridge.na_send_status(@na_dialog, 'error', "Live update failed: #{e.message}")
            end

            def self.na_handle_measure_opening
                cill_height_mm = 50
                frame_bottom_thickness_mm = 50
                if @na_config && @na_config["windowConfiguration"]
                    wc = @na_config["windowConfiguration"]
                    uniform = wc.key?("frame_thickness_mm") ? wc["frame_thickness_mm"].to_f : 50.0
                    use_advanced = wc["advanced_frame_controls"] == true
                    frame_bottom_thickness_mm = if use_advanced && wc.key?("frame_bottom_thickness_mm")
                        wc["frame_bottom_thickness_mm"].to_f
                    else
                        uniform
                    end
                    cill_height_mm = (wc["has_cill"] != false && frame_bottom_thickness_mm > 0) ? (wc["cill_height_mm"] || 50) : 0
                end

                tool = TwoPoint.new(self, cill_height_mm, frame_bottom_thickness_mm)
                Sketchup.active_model.select_tool(tool)
            end

            # Called by TwoPoint completion
            def self.na_send_measurement_to_dialog(width_mm, height_mm, ax = nil, ay = nil, az = nil)
                if ax && ay && az
                    @na_last_measure_origin = Geom::Point3d.new(ax, ay, az)
                end
                UiBridge.na_execute_numeric_function(
                    @na_dialog, 'window.na_receiveMeasurement',
                    *[width_mm, height_mm, ax, ay, az].compact
                )
            end

            def self.na_send_measure_cancelled_to_dialog
                UiBridge.na_invoke(@na_dialog, 'window.na_measureCancelled')
            end

            def self.na_consume_pending_measurement_origin
                origin = @na_last_measure_origin
                @na_last_measure_origin = nil
                origin
            end

            def self.na_send_config_to_dialog
                payload = @na_config || na_default_config
                UiBridge.na_execute_json_function(@na_dialog, 'window.na_setInitialConfig', payload)
            end

        end
    end
end
