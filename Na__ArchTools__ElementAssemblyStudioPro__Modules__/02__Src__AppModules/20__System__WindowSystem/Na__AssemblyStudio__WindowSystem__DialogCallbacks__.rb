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
            @na_bifold_component     = nil
            @na_sliding_component    = nil
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

                    bifold_id = na_resolve_bifold_id(instance)
                    if bifold_id
                        DebugTools.na_debug_window("Existing bifold door in selection: #{bifold_id}")
                        na_load_bifold_into_dialog(instance, bifold_id)
                        return
                    end

                    sliding_id = na_resolve_sliding_id(instance)
                    if sliding_id
                        DebugTools.na_debug_window("Existing sliding door in selection: #{sliding_id}")
                        na_load_sliding_into_dialog(instance, sliding_id)
                        return
                    end
                end
                @na_config = UiBridge.na_deep_clone(na_default_config)
            end

            # HELPER FUNCTION | Safely Resolve a Bifold Door ID From an Instance
            # ------------------------------------------------------------
            def self.na_resolve_bifold_id(instance)
                return nil unless defined?(Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__DataSerializer)
                Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__DataSerializer
                    .na_get_door_id_from_instance(instance)
            rescue StandardError
                nil
            end
            private_class_method :na_resolve_bifold_id
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Safely Resolve a Sliding Door ID From an Instance
            # ------------------------------------------------------------
            def self.na_resolve_sliding_id(instance)
                return nil unless defined?(Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__DataSerializer)
                Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__DataSerializer
                    .na_get_door_id_from_instance(instance)
            rescue StandardError
                nil
            end
            private_class_method :na_resolve_sliding_id
            # ---------------------------------------------------------------

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
            # REGION | Bifold + Sliding selection coordinator hooks (Phase 3.5)
            # -----------------------------------------------------------------
            # These run when the SelectionCoordinator's bifold / sliding handler
            # fires (handlers are registered by ExtFold__Init / ExtSlide__Init
            # using `tab_id => 'windows'` so the user is brought back to the
            # Windows tab whenever an existing ADR is clicked). The payload
            # we push to JS reuses the standard `windowConfiguration` envelope
            # plus the relevant mode flag so the WindowSystem MainUiLogic can
            # toggle the correct sub-section visible.
            # -----------------------------------------------------------------

            def self.na_load_bifold_into_dialog(instance, door_id)
                return unless defined?(Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__DataSerializer)
                bifold_serializer = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__DataSerializer

                @na_bifold_component = instance
                @na_window_component = instance

                stored = bifold_serializer.na_load_door_data_from_instance(instance, door_id)
                bifold_config = na_resolve_bifold_payload(stored)

                @na_config = na_wrap_bifold_config_as_window_payload(door_id, bifold_config)
                na_send_config_to_dialog
                UiBridge.na_send_status(@na_dialog, 'info', "Loaded bifold door: #{door_id}")
            rescue StandardError => e
                DebugTools.na_debug_error("[ExtFold] Error loading bifold #{door_id}", e)
                UiBridge.na_send_status(@na_dialog, 'warning', "Bifold #{door_id} selected but config could not be read")
            end

            def self.na_clear_bifold_from_dialog
                @na_bifold_component = nil
                @na_window_component = nil
                @na_config           = UiBridge.na_deep_clone(na_default_config)
                UiBridge.na_invoke(@na_dialog, 'window.na_clearCurrentWindow')
            end

            def self.na_load_sliding_into_dialog(instance, door_id)
                return unless defined?(Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__DataSerializer)
                sliding_serializer = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__DataSerializer

                @na_sliding_component = instance
                @na_window_component  = instance

                stored = sliding_serializer.na_load_door_data_from_instance(instance, door_id)
                sliding_config = na_resolve_sliding_payload(stored)

                @na_config = na_wrap_sliding_config_as_window_payload(door_id, sliding_config)
                na_send_config_to_dialog
                UiBridge.na_send_status(@na_dialog, 'info', "Loaded sliding door: #{door_id}")
            rescue StandardError => e
                DebugTools.na_debug_error("[ExtSlide] Error loading sliding #{door_id}", e)
                UiBridge.na_send_status(@na_dialog, 'warning', "Sliding #{door_id} selected but config could not be read")
            end

            def self.na_clear_sliding_from_dialog
                @na_sliding_component = nil
                @na_window_component  = nil
                @na_config            = UiBridge.na_deep_clone(na_default_config)
                UiBridge.na_invoke(@na_dialog, 'window.na_clearCurrentWindow')
            end

            # CONSTANT | Shared Window-Level Keys Stored Alongside Bifold / Sliding Doors
            # ------------------------------------------------------------
            # Phase-9 unified the bifold + sliding door dimensions, frame,
            # cill, glaze bars and fuse_parts toggle with the parent
            # WindowSystem's controls. These keys live on the shared
            # `windowConfiguration` and need to round-trip through the
            # door's saved attribute dictionary so a single ADR can be
            # reloaded with all of its visual state intact.
            NA_DOOR_SHARED_WINDOW_KEYS = [
                "width_mm",
                "height_mm",
                "frame_thickness_mm",
                "advanced_frame_controls",
                "frame_top_thickness_mm",
                "frame_bottom_thickness_mm",
                "frame_left_thickness_mm",
                "frame_right_thickness_mm",
                "frame_depth_mm",
                "frame_wall_inset_mm",
                "has_cill",
                "paint_cill",
                "cill_height_mm",
                "cill_depth_mm",
                "frame_material_id",
                "horizontal_glaze_bars",
                "vertical_glaze_bars",
                "glaze_bar_width_mm",
                "glazebar_inset_mm",
                "glass_thickness_mm",
                "removed_glazebars",
                "fuse_parts"
            ].freeze

            # HELPER FUNCTION | Migrate Legacy Door-Local Dimension Keys (Phase-9)
            # ------------------------------------------------------------
            # Pre-Phase-9 saved blobs carry their own opening dimensions
            # (bifold_door_opening_width_mm, sliding_door_opening_height_mm,
            # bifold_door_floor_clearance_mm, etc). Copy those into the
            # shared window keys when the new keys are missing, then drop
            # the legacy keys so the in-memory config matches the new
            # schema. Mutates the supplied hash in place.
            def self.na_migrate_legacy_door_dimension_keys(door_config, prefix)
                return door_config unless door_config.is_a?(Hash)

                legacy_width      = "#{prefix}_opening_width_mm"
                legacy_height     = "#{prefix}_opening_height_mm"
                legacy_clearance  = "#{prefix}_floor_clearance_mm"
                legacy_walldepth  = "#{prefix}_wall_depth_mm"

                if door_config.key?(legacy_width)
                    door_config["width_mm"] ||= door_config[legacy_width]
                    door_config.delete(legacy_width)
                end
                if door_config.key?(legacy_height)
                    door_config["height_mm"] ||= door_config[legacy_height]
                    door_config.delete(legacy_height)
                end
                if door_config.key?(legacy_clearance)
                    door_config["frame_bottom_thickness_mm"] ||= door_config[legacy_clearance]
                    door_config.delete(legacy_clearance)
                end
                door_config.delete(legacy_walldepth) if door_config.key?(legacy_walldepth)

                door_config
            end
            private_class_method :na_migrate_legacy_door_dimension_keys
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Pull the Stored Bifold Configuration Block (or Defaults)
            # ------------------------------------------------------------
            def self.na_resolve_bifold_payload(stored_hash)
                if stored_hash.is_a?(Hash)
                    cfg_key = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::NA_KEY_DOOR_CONFIGURATION
                    if stored_hash[cfg_key].is_a?(Hash)
                        cloned = UiBridge.na_deep_clone(stored_hash[cfg_key])
                        return na_migrate_legacy_door_dimension_keys(cloned, "bifold_door")
                    end
                end
                UiBridge.na_deep_clone(Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::NA_DEFAULT_DOOR_CONFIG)
            end
            private_class_method :na_resolve_bifold_payload
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Pull the Stored Sliding Configuration Block (or Defaults)
            # ------------------------------------------------------------
            def self.na_resolve_sliding_payload(stored_hash)
                if stored_hash.is_a?(Hash)
                    cfg_key = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_CONFIGURATION
                    if stored_hash[cfg_key].is_a?(Hash)
                        cloned = UiBridge.na_deep_clone(stored_hash[cfg_key])
                        return na_migrate_legacy_door_dimension_keys(cloned, "sliding_door")
                    end
                end
                UiBridge.na_deep_clone(Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_DEFAULT_DOOR_CONFIG)
            end
            private_class_method :na_resolve_sliding_payload
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Wrap a Bifold Config in the Standard windowConfiguration Envelope
            # ------------------------------------------------------------
            # Force `multifold_mode` true so the JS MainUiLogic toggles the
            # bifold section visible and the dispatch path stays on the
            # bifold engine for any downstream Update / Live calls.
            def self.na_wrap_bifold_config_as_window_payload(door_id, bifold_config)
                merged = UiBridge.na_deep_clone(na_default_config["windowConfiguration"] || {})
                merged.merge!(bifold_config) if bifold_config.is_a?(Hash)
                merged["multifold_mode"] = true
                merged["sliding_mode"]   = false
                merged["door_mode"]      = false

                {
                    "windowMetadata" => [
                        {
                            "WindowUniqueId"    => door_id,
                            "WindowDescription" => "Bifold Door",
                            "CreatedDate"       => "",
                            "LastModified"      => Time.now.strftime("%Y-%m-%d %H:%M:%S")
                        }
                    ],
                    "windowComponents"    => [],
                    "windowConfiguration" => merged
                }
            end
            private_class_method :na_wrap_bifold_config_as_window_payload
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Wrap a Sliding Config in the Standard windowConfiguration Envelope
            # ------------------------------------------------------------
            def self.na_wrap_sliding_config_as_window_payload(door_id, sliding_config)
                merged = UiBridge.na_deep_clone(na_default_config["windowConfiguration"] || {})
                merged.merge!(sliding_config) if sliding_config.is_a?(Hash)
                merged["multifold_mode"] = false
                merged["sliding_mode"]   = true
                merged["door_mode"]      = false

                {
                    "windowMetadata" => [
                        {
                            "WindowUniqueId"    => door_id,
                            "WindowDescription" => "Sliding Door",
                            "CreatedDate"       => "",
                            "LastModified"      => Time.now.strftime("%Y-%m-%d %H:%M:%S")
                        }
                    ],
                    "windowComponents"    => [],
                    "windowConfiguration" => merged
                }
            end
            private_class_method :na_wrap_sliding_config_as_window_payload
            # ---------------------------------------------------------------

            # -----------------------------------------------------------------
            # REGION | Create / Update / Live / DXF / Measure handlers
            # -----------------------------------------------------------------

            def self.na_handle_create_window(config_json)
                config    = JSON.parse(config_json)
                @na_config = config

                if na_is_bifold_mode?(config["windowConfiguration"])
                    return na_handle_create_bifold_door(config)
                end

                if na_is_sliding_mode?(config["windowConfiguration"])
                    return na_handle_create_sliding_door(config)
                end

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

            # -----------------------------------------------------------------
            # REGION | Bifold dispatch (Phase 3a)
            # -----------------------------------------------------------------
            # Detects multifold_mode == true on the inbound windowConfiguration
            # and routes Create / Update / Live calls to the
            # ExteriorMultiFoldingDoorSystem geometry engine. This avoids the
            # WindowSystem DataSerializer overwriting the bifold instance name
            # and definition. Phase 3.5 will replace this with full
            # DataSerializer + SelectionCoordinator wiring.
            # -----------------------------------------------------------------

            def self.na_is_bifold_mode?(window_config)
                return false unless window_config.is_a?(Hash)

                window_config["multifold_mode"] == true
            end

            def self.na_handle_create_bifold_door(config)
                model = Sketchup.active_model
                return unless model

                window_config = config["windowConfiguration"] || {}
                pending_origin = na_consume_pending_measurement_origin

                model.start_operation("Create Bifold Door", true)

                Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem.na_require_bifold_modules
                bifold_engine     = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__GeometryEngine
                bifold_serializer = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__DataSerializer

                instance = bifold_engine.na_build_bifold_door(window_config, nil, pending_origin)

                if instance && instance.valid?
                    @na_bifold_component = instance
                    @na_window_component = instance

                    na_apply_bifold_fuse_parts(instance, window_config)

                    door_id = bifold_serializer.na_get_door_id_from_instance(instance)
                    if door_id
                        bifold_serializer.na_save_door_data(
                            door_id,
                            na_build_bifold_save_payload(door_id, window_config, true)
                        )
                    end

                    model.commit_operation

                    if pending_origin
                        UiBridge.na_send_status(@na_dialog, 'success', "Bifold placed at measured Point A: #{instance.name}")
                    else
                        @na_current_placement_tool = PlacementTool.new(instance)
                        Sketchup.active_model.select_tool(@na_current_placement_tool)
                        UiBridge.na_invoke(@na_dialog, 'window.na_setPlacementActive', 'true')
                        UiBridge.na_send_status(@na_dialog, 'success', "Bifold door created: #{instance.name}")
                    end
                else
                    model.abort_operation
                    UiBridge.na_send_status(@na_dialog, 'error', 'Failed to create bifold door geometry')
                end
            rescue StandardError => e
                begin; model.abort_operation if model; rescue StandardError; end
                DebugTools.na_debug_error("Error creating bifold door", e)
                UiBridge.na_send_status(@na_dialog, 'error', "Error: #{e.message}")
            end

            def self.na_handle_update_bifold_door(config)
                instance = @na_bifold_component
                unless instance && instance.valid?
                    UiBridge.na_send_status(@na_dialog, 'warning', 'No bifold door selected to update')
                    return
                end

                window_config = config["windowConfiguration"] || {}
                model = Sketchup.active_model
                model.start_operation("Update Bifold Door", true)

                Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem.na_require_bifold_modules
                bifold_engine     = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__GeometryEngine
                bifold_serializer = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__DataSerializer

                bifold_engine.na_update_bifold_door(instance, window_config)

                na_apply_bifold_fuse_parts(instance, window_config)

                door_id = bifold_serializer.na_get_door_id_from_instance(instance)
                if door_id
                    bifold_serializer.na_save_door_data(
                        door_id,
                        na_build_bifold_save_payload(door_id, window_config, false)
                    )
                end

                model.commit_operation
                UiBridge.na_send_status(@na_dialog, 'success', "Bifold door updated: #{instance.name}")
            rescue StandardError => e
                begin; model.abort_operation if model; rescue StandardError; end
                DebugTools.na_debug_error("Error updating bifold door", e)
                UiBridge.na_send_status(@na_dialog, 'error', "Error: #{e.message}")
            end

            def self.na_handle_live_update_bifold_door(config)
                instance = @na_bifold_component
                return unless instance && instance.valid?

                window_config = config["windowConfiguration"] || {}
                model = Sketchup.active_model
                model.start_operation("Live Update Bifold", true, false, true)

                Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem.na_require_bifold_modules
                bifold_engine     = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__GeometryEngine
                bifold_serializer = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__DataSerializer

                bifold_engine.na_update_bifold_door(instance, window_config)

                na_apply_bifold_fuse_parts(instance, window_config)

                door_id = bifold_serializer.na_get_door_id_from_instance(instance)
                if door_id
                    bifold_serializer.na_save_door_data(
                        door_id,
                        na_build_bifold_save_payload(door_id, window_config, false)
                    )
                end

                model.commit_operation
                model.active_view.invalidate
                DebugTools.na_debug_success("Live update applied to bifold #{instance.name}")
            rescue StandardError => e
                begin; model.abort_operation if model; rescue StandardError; end
                DebugTools.na_debug_error("Live update bifold (non-fatal)", e)
            end

            # HELPER FUNCTION | Build the Save Hash for the Bifold DataSerializer
            # ------------------------------------------------------------
            # Filters the live windowConfiguration down to the bifold_door_*
            # keys plus the shared window-level keys (Phase-9: dimensions,
            # frame, cill, glaze bars, fuse_parts) so the saved blob is
            # self-contained. Wraps it in the bifold metadata + config
            # envelope expected by `Na__DataSerializer.na_save_door_data`.
            def self.na_build_bifold_save_payload(door_id, window_config, is_create)
                bifold_only = {}
                window_config.each do |k, v|
                    next unless k.is_a?(String)
                    bifold_only[k] = v if k.start_with?("bifold_door_")
                end
                NA_DOOR_SHARED_WINDOW_KEYS.each do |k|
                    bifold_only[k] = window_config[k] if window_config.key?(k)
                end

                meta_key = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::NA_KEY_DOOR_METADATA
                comp_key = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::NA_KEY_DOOR_COMPONENTS
                cfg_key  = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::NA_KEY_DOOR_CONFIGURATION

                now = Time.now.strftime("%Y-%m-%d %H:%M:%S")

                {
                    meta_key => [
                        {
                            "DoorID"        => door_id,
                            "DoorType"      => "BifoldDoor",
                            "Layout"        => window_config["bifold_door_layout"],
                            "PanelCount"    => window_config["bifold_door_panel_count"],
                            "CreatedDate"   => is_create ? now : nil,
                            "LastModified"  => now
                        }.compact
                    ],
                    comp_key => [],
                    cfg_key  => bifold_only
                }
            end
            private_class_method :na_build_bifold_save_payload
            # ---------------------------------------------------------------

            # -----------------------------------------------------------------
            # REGION | Sliding dispatch (Phase 3b)
            # -----------------------------------------------------------------
            # Detects sliding_mode == true on the inbound windowConfiguration
            # and routes Create / Update / Live calls to the
            # ExteriorSlidingDoorSystem geometry engine. Mirrors the bifold
            # dispatch above. Phase-3.5 replaces this with full DataSerializer
            # + SelectionCoordinator wiring.
            # -----------------------------------------------------------------

            def self.na_is_sliding_mode?(window_config)
                return false unless window_config.is_a?(Hash)

                window_config["sliding_mode"] == true
            end

            def self.na_handle_create_sliding_door(config)
                model = Sketchup.active_model
                return unless model

                window_config = config["windowConfiguration"] || {}
                pending_origin = na_consume_pending_measurement_origin

                model.start_operation("Create Sliding Door", true)

                Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem.na_require_sliding_modules
                sliding_engine     = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__GeometryEngine
                sliding_serializer = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__DataSerializer

                instance = sliding_engine.na_build_sliding_door(window_config, nil, pending_origin)

                if instance && instance.valid?
                    @na_sliding_component = instance
                    @na_window_component  = instance

                    na_apply_sliding_fuse_parts(instance, window_config)

                    door_id = sliding_serializer.na_get_door_id_from_instance(instance)
                    if door_id
                        sliding_serializer.na_save_door_data(
                            door_id,
                            na_build_sliding_save_payload(door_id, window_config, true)
                        )
                    end

                    model.commit_operation

                    if pending_origin
                        UiBridge.na_send_status(@na_dialog, 'success', "Sliding placed at measured Point A: #{instance.name}")
                    else
                        @na_current_placement_tool = PlacementTool.new(instance)
                        Sketchup.active_model.select_tool(@na_current_placement_tool)
                        UiBridge.na_invoke(@na_dialog, 'window.na_setPlacementActive', 'true')
                        UiBridge.na_send_status(@na_dialog, 'success', "Sliding door created: #{instance.name}")
                    end
                else
                    model.abort_operation
                    UiBridge.na_send_status(@na_dialog, 'error', 'Failed to create sliding door geometry')
                end
            rescue StandardError => e
                begin; model.abort_operation if model; rescue StandardError; end
                DebugTools.na_debug_error("Error creating sliding door", e)
                UiBridge.na_send_status(@na_dialog, 'error', "Error: #{e.message}")
            end

            def self.na_handle_update_sliding_door(config)
                instance = @na_sliding_component
                unless instance && instance.valid?
                    UiBridge.na_send_status(@na_dialog, 'warning', 'No sliding door selected to update')
                    return
                end

                window_config = config["windowConfiguration"] || {}
                model = Sketchup.active_model
                model.start_operation("Update Sliding Door", true)

                Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem.na_require_sliding_modules
                sliding_engine     = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__GeometryEngine
                sliding_serializer = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__DataSerializer

                sliding_engine.na_update_sliding_door(instance, window_config)

                na_apply_sliding_fuse_parts(instance, window_config)

                door_id = sliding_serializer.na_get_door_id_from_instance(instance)
                if door_id
                    sliding_serializer.na_save_door_data(
                        door_id,
                        na_build_sliding_save_payload(door_id, window_config, false)
                    )
                end

                model.commit_operation
                UiBridge.na_send_status(@na_dialog, 'success', "Sliding door updated: #{instance.name}")
            rescue StandardError => e
                begin; model.abort_operation if model; rescue StandardError; end
                DebugTools.na_debug_error("Error updating sliding door", e)
                UiBridge.na_send_status(@na_dialog, 'error', "Error: #{e.message}")
            end

            def self.na_handle_live_update_sliding_door(config)
                instance = @na_sliding_component
                return unless instance && instance.valid?

                window_config = config["windowConfiguration"] || {}
                model = Sketchup.active_model
                model.start_operation("Live Update Sliding", true, false, true)

                Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem.na_require_sliding_modules
                sliding_engine     = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__GeometryEngine
                sliding_serializer = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__DataSerializer

                sliding_engine.na_update_sliding_door(instance, window_config)

                na_apply_sliding_fuse_parts(instance, window_config)

                door_id = sliding_serializer.na_get_door_id_from_instance(instance)
                if door_id
                    sliding_serializer.na_save_door_data(
                        door_id,
                        na_build_sliding_save_payload(door_id, window_config, false)
                    )
                end

                model.commit_operation
                model.active_view.invalidate
                DebugTools.na_debug_success("Live update applied to sliding #{instance.name}")
            rescue StandardError => e
                begin; model.abort_operation if model; rescue StandardError; end
                DebugTools.na_debug_error("Live update sliding (non-fatal)", e)
            end

            # HELPER FUNCTION | Build the Save Hash for the Sliding DataSerializer
            # ------------------------------------------------------------
            # Filters the live windowConfiguration down to the sliding_door_*
            # keys plus the shared window-level keys (Phase-9: dimensions,
            # frame, cill, glaze bars, fuse_parts) so the saved blob is
            # self-contained.
            def self.na_build_sliding_save_payload(door_id, window_config, is_create)
                sliding_only = {}
                window_config.each do |k, v|
                    next unless k.is_a?(String)
                    sliding_only[k] = v if k.start_with?("sliding_door_")
                end
                NA_DOOR_SHARED_WINDOW_KEYS.each do |k|
                    sliding_only[k] = window_config[k] if window_config.key?(k)
                end

                meta_key = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_METADATA
                comp_key = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_COMPONENTS
                cfg_key  = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_CONFIGURATION

                now = Time.now.strftime("%Y-%m-%d %H:%M:%S")

                {
                    meta_key => [
                        {
                            "DoorID"        => door_id,
                            "DoorType"      => "SlidingDoor",
                            "Mode"          => window_config["sliding_door_mode"],
                            "CreatedDate"   => is_create ? now : nil,
                            "LastModified"  => now
                        }.compact
                    ],
                    comp_key => [],
                    cfg_key  => sliding_only
                }
            end
            private_class_method :na_build_sliding_save_payload
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Run the Bifold-Panel FuseParts Pipeline (Phase-9)
            # ------------------------------------------------------------
            # Mirrors the WindowSystem fuse step: only fires when
            # `fuse_parts === true` on the live windowConfiguration. Walks the
            # ADR ComponentDefinition entities and fuses every per-leaf
            # timber assembly into a single solid, leaving glass + glaze
            # bars + animation MOD groups intact.
            def self.na_apply_bifold_fuse_parts(instance, window_config)
                return unless instance && instance.valid?
                return unless window_config.is_a?(Hash)
                return unless window_config["fuse_parts"] == true

                Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem.na_require_bifold_modules
                fuser = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__FuseParts__Panel
                return unless fuser

                UiBridge.na_send_status(@na_dialog, 'info', 'Fusing bifold panels...')
                fuser.na_fuse_bifold_panels(instance.definition.entities)
            rescue StandardError => e
                DebugTools.na_debug_error("Bifold fuse-parts failed (non-fatal)", e)
            end
            private_class_method :na_apply_bifold_fuse_parts
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Run the Sliding-Panel FuseParts Pipeline (Phase-9)
            # ------------------------------------------------------------
            def self.na_apply_sliding_fuse_parts(instance, window_config)
                return unless instance && instance.valid?
                return unless window_config.is_a?(Hash)
                return unless window_config["fuse_parts"] == true

                Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem.na_require_sliding_modules
                fuser = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__FuseParts__Panel
                return unless fuser

                UiBridge.na_send_status(@na_dialog, 'info', 'Fusing sliding panels...')
                fuser.na_fuse_sliding_panels(instance.definition.entities)
            rescue StandardError => e
                DebugTools.na_debug_error("Sliding fuse-parts failed (non-fatal)", e)
            end
            private_class_method :na_apply_sliding_fuse_parts
            # ---------------------------------------------------------------

            def self.na_handle_update_window(config_json)
                config = JSON.parse(config_json)
                @na_config = config

                if na_is_bifold_mode?(config["windowConfiguration"])
                    return na_handle_update_bifold_door(config)
                end

                if na_is_sliding_mode?(config["windowConfiguration"])
                    return na_handle_update_sliding_door(config)
                end

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

                if na_is_bifold_mode?(config["windowConfiguration"])
                    return na_handle_live_update_bifold_door(config)
                end

                if na_is_sliding_mode?(config["windowConfiguration"])
                    return na_handle_live_update_sliding_door(config)
                end

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
