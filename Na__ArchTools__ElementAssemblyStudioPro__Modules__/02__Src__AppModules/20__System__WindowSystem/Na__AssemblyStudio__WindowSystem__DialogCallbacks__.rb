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
require_relative 'Na__AssemblyStudio__WindowSystem__SashHornBuilder__'
require_relative 'Na__AssemblyStudio__WindowSystem__EdgeColourPainter__'
require_relative 'Na__AssemblyStudio__WindowSystem__LeadedGlassBuilder__'

module Na__AssemblyStudio
    module Na__WindowSystem
        module Na__DialogCallbacks

            DebugTools     = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
            UiBridge       = Na__AssemblyStudio::Na__AppCore::Na__UiBridge
            DataSerializer = Na__AssemblyStudio::Na__WindowSystem::Na__DataSerializer
            GeometryEngine = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryEngine
            DxfExporter    = Na__AssemblyStudio::Na__WindowSystem::Na__DxfExporter
            FuseParts      = Na__AssemblyStudio::Na__WindowSystem::Na__FuseParts
            SashHornBuilder = Na__AssemblyStudio::Na__WindowSystem::Na__SashHornBuilder
            EdgeColourPainter = Na__AssemblyStudio::Na__WindowSystem::Na__EdgeColourPainter
            LeadedGlassBuilder = Na__AssemblyStudio::Na__WindowSystem::Na__LeadedGlassBuilder
            TwoPoint       = Na__AssemblyStudio::Na__MeasurementTools::Na__TwoPointOpeningTool
            PlacementTool  = Na__AssemblyStudio::Na__PlacementTools::Na__WindowPlacementTool
            InsertionFrame = Na__AssemblyStudio::Na__GeometryHelpers::Na__InsertionFrame                  # <-- Wall-aware insertion transform helper

            @na_dialog               = nil
            @na_window_component     = nil
            @na_bifold_component     = nil
            @na_sliding_component    = nil
            @na_double_door_component = nil
            @na_single_door_component = nil
            @na_config               = nil
            @na_last_measure_frame   = nil                                                                # <-- { :origin_in, :xaxis, :yaxis, :zaxis } or { :origin_in => Point3d }
            @na_current_placement_tool = nil

            def self.na_attach_dialog(dialog)
                @na_dialog = dialog
            end

            def self.na_callback_registry
                {
                    "na_createWindow"               => proc { |json| na_handle_create_window(json, mode: :auto) },              # <-- Legacy smart entrypoint (back-compat)
                    "na_createWindowAtCursor"       => proc { |json| na_handle_create_window(json, mode: :cursor) },            # <-- Always engages placement tool, ignores pending measurement
                    "na_createWindowAtMeasurement"  => proc { |json| na_handle_create_window(json, mode: :measurement) },       # <-- Requires pending measurement, never engages placement tool
                    "na_updateWindow"               => proc { |json| na_handle_update_window(json) },
                    "na_exportDxf"                  => proc { |json| na_handle_export_dxf(json) },
                    "na_liveUpdate"                 => proc { |json| na_handle_live_update(json) },
                    "na_requestConfig"              => proc { na_send_config_to_dialog },
                    "na_requestSashHornAssets"      => proc { na_send_sash_horn_assets_to_dialog },
                    "na_measureOpening"             => proc { |json = nil| na_handle_measure_opening(json) },                  # <-- Optional live-config JSON from JS
                    "na_keyboard_tab"               => proc { @na_current_placement_tool.na_rotate if @na_current_placement_tool }
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

                    double_door_id = na_resolve_exterior_double_door_id(instance)
                    if double_door_id
                        DebugTools.na_debug_window("Existing exterior double door in selection: #{double_door_id}")
                        na_load_exterior_double_door_into_dialog(instance, double_door_id)
                        return
                    end

                    single_door_id = na_resolve_exterior_single_door_id(instance)
                    if single_door_id
                        DebugTools.na_debug_window("Existing exterior single door in selection: #{single_door_id}")
                        na_load_exterior_single_door_into_dialog(instance, single_door_id)
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

            # HELPER FUNCTION | Safely Resolve an Exterior Double Door ID
            # ------------------------------------------------------------
            def self.na_resolve_exterior_double_door_id(instance)
                return nil unless defined?(Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__DataSerializer)
                Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__DataSerializer
                    .na_get_door_id_from_instance(instance)
            rescue StandardError
                nil
            end
            private_class_method :na_resolve_exterior_double_door_id
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Safely Resolve an Exterior Single Door ID
            # ------------------------------------------------------------
            def self.na_resolve_exterior_single_door_id(instance)
                return nil unless defined?(Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__DataSerializer)
                Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__DataSerializer
                    .na_get_door_id_from_instance(instance)
            rescue StandardError
                nil
            end
            private_class_method :na_resolve_exterior_single_door_id
            # ---------------------------------------------------------------

            # -----------------------------------------------------------------
            # REGION | Selection coordinator hooks
            # -----------------------------------------------------------------

            def self.na_load_window_into_dialog(instance, window_id)
                @na_bifold_component = nil
                @na_sliding_component = nil
                @na_double_door_component = nil
                @na_single_door_component = nil
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
                @na_bifold_component = nil
                @na_sliding_component = nil
                @na_double_door_component = nil
                @na_single_door_component = nil
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
                @na_sliding_component = nil
                @na_double_door_component = nil
                @na_single_door_component = nil
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
                @na_sliding_component = nil
                @na_double_door_component = nil
                @na_single_door_component = nil
                @na_window_component = nil
                @na_config           = UiBridge.na_deep_clone(na_default_config)
                UiBridge.na_invoke(@na_dialog, 'window.na_clearCurrentWindow')
            end

            def self.na_load_sliding_into_dialog(instance, door_id)
                return unless defined?(Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__DataSerializer)
                sliding_serializer = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__DataSerializer

                @na_sliding_component = instance
                @na_bifold_component = nil
                @na_double_door_component = nil
                @na_single_door_component = nil
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
                @na_bifold_component = nil
                @na_double_door_component = nil
                @na_single_door_component = nil
                @na_window_component  = nil
                @na_config            = UiBridge.na_deep_clone(na_default_config)
                UiBridge.na_invoke(@na_dialog, 'window.na_clearCurrentWindow')
            end

            # @delegate: ../34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__DataSerializer__.rb
            def self.na_load_exterior_double_door_into_dialog(instance, door_id)
                return unless defined?(Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__DataSerializer)
                serializer = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__DataSerializer

                @na_double_door_component = instance
                @na_single_door_component = nil
                @na_bifold_component = nil
                @na_sliding_component = nil
                @na_window_component = instance
                stored = serializer.na_load_from_instance(instance)
                double_door_config = na_resolve_exterior_double_door_payload(stored)

                @na_config = na_wrap_exterior_double_door_config_as_window_payload(door_id, double_door_config)
                na_send_config_to_dialog
                UiBridge.na_send_status(@na_dialog, 'info', "Loaded exterior double door: #{door_id}")
            rescue StandardError => e
                DebugTools.na_debug_error("[ExtDouble] Error loading exterior double door #{door_id}", e)
                UiBridge.na_send_status(@na_dialog, 'warning', "Exterior double door #{door_id} selected but config could not be read")
            end

            def self.na_clear_exterior_double_door_from_dialog
                @na_double_door_component = nil
                @na_single_door_component = nil
                @na_bifold_component = nil
                @na_sliding_component = nil
                @na_window_component = nil
                @na_config = UiBridge.na_deep_clone(na_default_config)
                UiBridge.na_invoke(@na_dialog, 'window.na_clearCurrentWindow')
            end

            # @delegate: ../31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__DataSerializer__.rb
            def self.na_load_exterior_single_door_into_dialog(instance, door_id)
                return unless defined?(Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__DataSerializer)
                serializer = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__DataSerializer

                @na_single_door_component = instance
                @na_double_door_component = nil
                @na_bifold_component = nil
                @na_sliding_component = nil
                @na_window_component = instance
                stored = serializer.na_load_from_instance(instance)
                single_door_config = na_resolve_exterior_single_door_payload(stored)

                @na_config = na_wrap_exterior_single_door_config_as_window_payload(door_id, single_door_config)
                na_send_config_to_dialog
                UiBridge.na_send_status(@na_dialog, 'info', "Loaded exterior single door: #{door_id}")
            rescue StandardError => e
                DebugTools.na_debug_error("[ExtSingleDoor] Error loading exterior single door #{door_id}", e)
                UiBridge.na_send_status(@na_dialog, 'warning', "Exterior single door #{door_id} selected but config could not be read")
            end

            def self.na_clear_exterior_single_door_from_dialog
                @na_single_door_component = nil
                @na_double_door_component = nil
                @na_bifold_component = nil
                @na_sliding_component = nil
                @na_window_component = nil
                @na_config = UiBridge.na_deep_clone(na_default_config)
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
                # Advanced Glazebar Controls (Margin Glazing + Gothic Arch)
                "glazebar_margin_enabled",
                "glazebar_margin_offset_mm",
                "glazebar_gothic_arch_enabled",
                "glazebar_gothic_arch_amount",
                "glazebar_gothic_arch_height_mm",
                "glazebar_horizontal_offset_mm",                                                    # <-- V1.9.3 Horizontal Bar Vertical Offset
                # Leaded Glass Controls (overlay on outer glass face)
                "leaded_glass_controls",
                "leaded_glass_enabled",
                "horizontal_leaded_bars",
                "vertical_leaded_bars",
                "leaded_width_mm",
                "leaded_depth_mm",
                "leaded_centre_lines_only",
                "edge_colour_controls",
                "edge_colour_frame_id",
                "edge_colour_casement_id",
                "edge_colour_glazebar_id",
                "edge_colour_leaded_id",
                "edge_colour_fielded_panel_id",
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

            # HELPER FUNCTION | Pull the Stored Exterior Double Door Configuration
            # ------------------------------------------------------------
            def self.na_resolve_exterior_double_door_payload(stored_hash)
                if stored_hash.is_a?(Hash)
                    cfg_key = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::NA_KEY_CONFIGURATION
                    if stored_hash[cfg_key].is_a?(Hash)
                        return UiBridge.na_deep_clone(stored_hash[cfg_key])
                    end
                end
                UiBridge.na_deep_clone(Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::NA_DEFAULT_DOOR_CONFIG)
            end
            private_class_method :na_resolve_exterior_double_door_payload
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
                merged["ext_single_door_mode"] = false
                merged["double_door_mode"] = false
                merged["ui_element_category"] = "ExteriorDoors"
                merged["ui_exterior_door_type"] = "MultiFold"

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
                merged["ext_single_door_mode"] = false
                merged["double_door_mode"] = false
                merged["ui_element_category"] = "ExteriorDoors"
                merged["ui_exterior_door_type"] = "Sliding"

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

            # HELPER FUNCTION | Wrap Exterior Double Door Config for Window UI
            # ------------------------------------------------------------
            def self.na_wrap_exterior_double_door_config_as_window_payload(door_id, double_door_config)
                merged = UiBridge.na_deep_clone(na_default_config["windowConfiguration"] || {})
                merged.merge!(double_door_config) if double_door_config.is_a?(Hash)
                merged["multifold_mode"] = false
                merged["sliding_mode"] = false
                merged["door_mode"] = false
                merged["ext_single_door_mode"] = false
                merged["double_door_mode"] = true
                merged["ui_element_category"] = "ExteriorDoors"
                merged["ui_exterior_door_type"] = "Double"
                merged["double_door_active_leaf_width_mm"] ||= "EQ"

                {
                    "windowMetadata" => [
                        {
                            "WindowUniqueId" => door_id,
                            "WindowDescription" => "Exterior Double Door",
                            "CreatedDate" => "",
                            "LastModified" => Time.now.strftime("%Y-%m-%d %H:%M:%S")
                        }
                    ],
                    "windowComponents" => [],
                    "windowConfiguration" => merged
                }
            end
            private_class_method :na_wrap_exterior_double_door_config_as_window_payload
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Wrap Exterior Single Door Config for Window UI
            # ------------------------------------------------------------
            def self.na_wrap_exterior_single_door_config_as_window_payload(door_id, single_door_config)
                merged = UiBridge.na_deep_clone(na_default_config["windowConfiguration"] || {})
                merged.merge!(single_door_config) if single_door_config.is_a?(Hash)
                merged["multifold_mode"] = false
                merged["sliding_mode"] = false
                merged["door_mode"] = false
                merged["double_door_mode"] = false
                merged["ext_single_door_mode"] = true
                merged["ui_element_category"] = "ExteriorDoors"
                merged["ui_exterior_door_type"] = "Single"

                {
                    "windowMetadata" => [
                        {
                            "WindowUniqueId" => door_id,
                            "WindowDescription" => "Exterior Single Door",
                            "CreatedDate" => "",
                            "LastModified" => Time.now.strftime("%Y-%m-%d %H:%M:%S")
                        }
                    ],
                    "windowComponents" => [],
                    "windowConfiguration" => merged
                }
            end
            private_class_method :na_wrap_exterior_single_door_config_as_window_payload
            # ---------------------------------------------------------------

            def self.na_resolve_exterior_single_door_payload(stored_hash)
                if stored_hash.is_a?(Hash)
                    cfg_key = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::NA_KEY_CONFIGURATION
                    if stored_hash[cfg_key].is_a?(Hash)
                        return UiBridge.na_deep_clone(stored_hash[cfg_key])
                    end
                end
                UiBridge.na_deep_clone(Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::NA_DEFAULT_DOOR_CONFIG)
            end
            private_class_method :na_resolve_exterior_single_door_payload
            # ---------------------------------------------------------------

            # -----------------------------------------------------------------
            # REGION | Create / Update / Live / DXF / Measure handlers
            # -----------------------------------------------------------------

            # FUNCTION | Handle the Create-Window Callback (Window/Bifold/Sliding)
            # ------------------------------------------------------------
            # @param config_json [String] Raw JSON payload from the dialog
            # @param mode        [Symbol] :cursor, :measurement, or :auto
            #     - :cursor      -> Discard any cached measurement and engage
            #                       the SketchUp placement tool (cursor-follow ghost).
            #     - :measurement -> Require a cached measurement, place at the
            #                       wall, and skip the placement tool entirely.
            #     - :auto        -> Legacy behaviour kept for backward compat:
            #                       use the measurement when present, otherwise
            #                       fall back to the placement tool.
            def self.na_handle_create_window(config_json, mode: :auto)
                config    = JSON.parse(config_json)
                @na_config = config

                pending_frame = na_resolve_pending_frame_for_mode(mode)
                return if mode == :measurement && pending_frame.nil?                                 # <-- Strict mode bail-out (status already emitted)

                if na_is_bifold_mode?(config["windowConfiguration"])
                    return na_handle_create_bifold_door(config, pending_frame, mode)
                end

                if na_is_sliding_mode?(config["windowConfiguration"])
                    return na_handle_create_sliding_door(config, pending_frame, mode)
                end

                if na_is_exterior_double_door_mode?(config["windowConfiguration"])
                    return na_handle_create_exterior_double_door(config, pending_frame, mode)
                end

                if na_is_exterior_single_door_mode?(config["windowConfiguration"])
                    return na_handle_create_exterior_single_door(config, pending_frame, mode)
                end

                model     = Sketchup.active_model
                model.start_operation("Create Window", true)

                window_id = DataSerializer.na_generate_next_window_id
                if @na_config["windowMetadata"] && @na_config["windowMetadata"][0]
                    @na_config["windowMetadata"][0]["WindowUniqueId"] = window_id
                    @na_config["windowMetadata"][0]["CreatedDate"]    = Time.now.strftime("%Y-%m-%d %H:%M:%S")
                    @na_config["windowMetadata"][0]["LastModified"]   = Time.now.strftime("%Y-%m-%d %H:%M:%S")
                end

                @na_window_component = GeometryEngine.na_create_window_geometry(
                    config["windowConfiguration"], window_id, pending_frame
                )

                if @na_window_component && @na_window_component.valid?
                    na_track_created_component(@na_window_component, :window)
                    if config["windowConfiguration"] && config["windowConfiguration"]["fuse_parts"] == true
                        UiBridge.na_send_status(@na_dialog, 'info', 'Fusing parts...')
                        FuseParts.na_fuse_window_parts(@na_window_component.definition.entities)
                    end
                    na_apply_edge_colours_after_build(@na_window_component, config["windowConfiguration"])

                    description = nil
                    if @na_config["windowMetadata"] && @na_config["windowMetadata"][0]
                        description = @na_config["windowMetadata"][0]["WindowDescription"]
                    end

                    DataSerializer.na_set_window_id_on_instance(@na_window_component, window_id, description)
                    DataSerializer.na_save_window_data(window_id, @na_config)
                    model.commit_operation

                    na_finalise_window_placement(@na_window_component, window_id, pending_frame, mode)
                else
                    model.abort_operation
                    UiBridge.na_send_status(@na_dialog, 'error', 'Failed to create window geometry')
                end
            rescue StandardError => e
                begin; model.abort_operation if model; rescue StandardError; end
                DebugTools.na_debug_error("Error creating window", e)
                UiBridge.na_send_status(@na_dialog, 'error', "Error: #{e.message}")
            end

            # HELPER FUNCTION | Resolve the Frame to Pass to the Engine Based on Mode
            # ------------------------------------------------------------
            # Single source of truth for "which measurement (if any)
            # should this create call use?". Also emits the user-visible
            # warning when :measurement is requested but the cache is
            # empty so the engines never have to know about modes.
            def self.na_resolve_pending_frame_for_mode(mode)
                case mode
                when :cursor
                    na_consume_pending_measurement_frame                                            # <-- Discard the cache so it can't sneak in later
                    nil                                                                              # <-- Force placement tool branch in the finaliser
                when :measurement
                    frame = na_consume_pending_measurement_frame
                    unless frame
                        DebugTools.na_debug_warn("Create-at-Measurement requested with no cached frame")
                        UiBridge.na_send_status(@na_dialog, 'warning', 'No measurement on file. Use "Measure Opening" first.')
                        return nil
                    end
                    frame
                else
                    na_consume_pending_measurement_frame                                            # <-- Legacy "auto" behaviour
                end
            end
            private_class_method :na_resolve_pending_frame_for_mode

            # HELPER FUNCTION | Finalise Placement After a Successful Window Create
            # ------------------------------------------------------------
            # Engages the SketchUp placement tool only when no frame was
            # used (cursor mode or :auto with no measurement). When a
            # frame was supplied the window is already at the wall and
            # no cursor-follow ghost is shown.
            def self.na_finalise_window_placement(instance, window_id, pending_frame, mode)
                if pending_frame
                    oriented     = InsertionFrame.na_frame_has_orientation?(pending_frame)
                    status_label = oriented ? "measured Point A + wall direction" : "measured Point A"
                    UiBridge.na_send_status(@na_dialog, 'success', "Window placed at #{status_label}: #{window_id}")
                    return
                end

                @na_current_placement_tool = PlacementTool.new(instance)
                Sketchup.active_model.select_tool(@na_current_placement_tool)
                UiBridge.na_invoke(@na_dialog, 'window.na_setPlacementActive', 'true')
                cursor_label = (mode == :cursor) ? "at cursor" : ""
                UiBridge.na_send_status(@na_dialog, 'success', "Window created #{cursor_label}: #{window_id}".strip)
            end
            private_class_method :na_finalise_window_placement

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

            def self.na_handle_create_bifold_door(config, pending_frame = nil, mode = :auto)
                model = Sketchup.active_model
                return unless model

                window_config = config["windowConfiguration"] || {}

                model.start_operation("Create Bifold Door", true)

                Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem.na_require_bifold_modules
                bifold_engine     = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__GeometryEngine
                bifold_serializer = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__DataSerializer

                instance = bifold_engine.na_build_bifold_door(window_config, nil, pending_frame)

                if instance && instance.valid?
                    na_track_created_component(instance, :bifold)

                    na_apply_bifold_fuse_parts(instance, window_config)
                    na_apply_edge_colours_after_build(instance, window_config)

                    door_id = bifold_serializer.na_get_door_id_from_instance(instance)
                    if door_id
                        bifold_serializer.na_save_door_data(
                            door_id,
                            na_build_bifold_save_payload(door_id, window_config, true)
                        )
                    end

                    model.commit_operation

                    na_finalise_bifold_or_sliding_placement(instance, pending_frame, mode, "Bifold")
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
                na_apply_edge_colours_after_build(instance, window_config)

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
                na_apply_edge_colours_after_build(instance, window_config)

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

            def self.na_handle_create_sliding_door(config, pending_frame = nil, mode = :auto)
                model = Sketchup.active_model
                return unless model

                window_config = config["windowConfiguration"] || {}

                model.start_operation("Create Sliding Door", true)

                Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem.na_require_sliding_modules
                sliding_engine     = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__GeometryEngine
                sliding_serializer = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__DataSerializer

                instance = sliding_engine.na_build_sliding_door(window_config, nil, pending_frame)

                if instance && instance.valid?
                    na_track_created_component(instance, :sliding)

                    na_apply_sliding_fuse_parts(instance, window_config)
                    na_apply_edge_colours_after_build(instance, window_config)

                    door_id = sliding_serializer.na_get_door_id_from_instance(instance)
                    if door_id
                        sliding_serializer.na_save_door_data(
                            door_id,
                            na_build_sliding_save_payload(door_id, window_config, true)
                        )
                    end

                    model.commit_operation

                    na_finalise_bifold_or_sliding_placement(instance, pending_frame, mode, "Sliding")
                else
                    model.abort_operation
                    UiBridge.na_send_status(@na_dialog, 'error', 'Failed to create sliding door geometry')
                end
            rescue StandardError => e
                begin; model.abort_operation if model; rescue StandardError; end
                DebugTools.na_debug_error("Error creating sliding door", e)
                UiBridge.na_send_status(@na_dialog, 'error', "Error: #{e.message}")
            end

            # HELPER FUNCTION | Finalise Placement for a Bifold / Sliding Door
            # ------------------------------------------------------------
            # Engages the placement tool only when no measurement frame
            # was used (cursor mode). Shared between bifold + sliding so
            # both door variants get the exact same UX as the standard
            # window path.
            def self.na_finalise_bifold_or_sliding_placement(instance, pending_frame, mode, label)
                if pending_frame
                    oriented     = InsertionFrame.na_frame_has_orientation?(pending_frame)
                    status_label = oriented ? "measured Point A + wall direction" : "measured Point A"
                    UiBridge.na_send_status(@na_dialog, 'success', "#{label} placed at #{status_label}: #{instance.name}")
                    return
                end

                @na_current_placement_tool = PlacementTool.new(instance)
                Sketchup.active_model.select_tool(@na_current_placement_tool)
                UiBridge.na_invoke(@na_dialog, 'window.na_setPlacementActive', 'true')
                cursor_label = (mode == :cursor) ? "at cursor" : ""
                UiBridge.na_send_status(@na_dialog, 'success', "#{label} door created #{cursor_label}: #{instance.name}".strip)
            end
            private_class_method :na_finalise_bifold_or_sliding_placement

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
                na_apply_edge_colours_after_build(instance, window_config)

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
                na_apply_edge_colours_after_build(instance, window_config)

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

            # -----------------------------------------------------------------
            # REGION | Exterior Double Door dispatch
            # -----------------------------------------------------------------

            def self.na_is_exterior_double_door_mode?(window_config)
                window_config.is_a?(Hash) && window_config["double_door_mode"] == true
            end

            def self.na_is_exterior_single_door_mode?(window_config)
                window_config.is_a?(Hash) && window_config["ext_single_door_mode"] == true
            end

            # @delegate: ../34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__GeometryEngine__.rb
            def self.na_handle_create_exterior_double_door(config, pending_frame = nil, mode = :auto)
                window_config = config["windowConfiguration"] || {}
                Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem.na_require_modules
                engine = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__GeometryEngine
                serializer = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__DataSerializer

                instance = engine.na_build_exterior_double_door(window_config, nil, pending_frame)
                unless instance && instance.valid?
                    UiBridge.na_send_status(@na_dialog, 'error', 'Failed to create exterior double door geometry')
                    return
                end

                na_track_created_component(instance, :double_door)
                door_id = serializer.na_get_door_id_from_instance(instance)
                if config["windowMetadata"] && config["windowMetadata"][0]
                    config["windowMetadata"][0]["WindowUniqueId"] = door_id
                    config["windowMetadata"][0]["CreatedDate"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
                    config["windowMetadata"][0]["LastModified"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
                end
                @na_config = config
                na_finalise_bifold_or_sliding_placement(instance, pending_frame, mode, "Exterior double")
            rescue StandardError => e
                DebugTools.na_debug_error("Error creating exterior double door", e)
                UiBridge.na_send_status(@na_dialog, 'error', "Error: #{e.message}")
            end

            def self.na_handle_update_exterior_double_door(config)
                instance = @na_double_door_component
                unless instance && instance.valid?
                    UiBridge.na_send_status(@na_dialog, 'warning', 'No exterior double door selected to update')
                    return
                end

                Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem.na_require_modules
                engine = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__GeometryEngine
                serializer = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__DataSerializer
                current_id = serializer.na_get_door_id_from_instance(instance)
                incoming_id = config.dig("windowMetadata", 0, "WindowUniqueId")
                unless current_id
                    UiBridge.na_send_status(@na_dialog, 'warning', 'Selected component is not an exterior double door')
                    return
                end
                if incoming_id && incoming_id != current_id
                    UiBridge.na_send_status(@na_dialog, 'warning', "Update rejected: selected #{current_id}, received #{incoming_id}")
                    return
                end
                updated = engine.na_update_exterior_double_door(instance, config["windowConfiguration"] || {})
                if updated
                    @na_config = config
                    UiBridge.na_send_status(@na_dialog, 'success', "Exterior double door updated: #{instance.name}")
                else
                    UiBridge.na_send_status(@na_dialog, 'error', 'Exterior double door update failed')
                end
            rescue StandardError => e
                DebugTools.na_debug_error("Error updating exterior double door", e)
                UiBridge.na_send_status(@na_dialog, 'error', "Error: #{e.message}")
            end

            def self.na_handle_live_update_exterior_double_door(config)
                instance = @na_double_door_component
                return unless instance && instance.valid?

                Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem.na_require_modules
                serializer = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__DataSerializer
                current_id = serializer.na_get_door_id_from_instance(instance)
                incoming_id = config.dig("windowMetadata", 0, "WindowUniqueId")
                if incoming_id && current_id && incoming_id != current_id
                    DebugTools.na_debug_warn("Exterior double door live update skipped: stale #{incoming_id}, current #{current_id}")
                    return
                end

                engine = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__GeometryEngine
                if engine.na_update_exterior_double_door(
                    instance,
                    config["windowConfiguration"] || {},
                    transparent: true
                )
                    @na_config = config
                    Sketchup.active_model.active_view.invalidate
                end
            rescue StandardError => e
                DebugTools.na_debug_error("Live update exterior double door failed (non-fatal)", e)
            end

            # @delegate: ../31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__GeometryEngine__.rb
            def self.na_handle_create_exterior_single_door(config, pending_frame = nil, mode = :auto)
                window_config = config["windowConfiguration"] || {}
                Na__AssemblyStudio::Na__ExteriorSingleDoorSystem.na_require_modules
                engine = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__GeometryEngine
                serializer = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__DataSerializer

                instance = engine.na_build_exterior_single_door(window_config, nil, pending_frame)
                unless instance && instance.valid?
                    UiBridge.na_send_status(@na_dialog, 'error', 'Failed to create exterior single door geometry')
                    return
                end

                na_track_created_component(instance, :single_door)
                door_id = serializer.na_get_door_id_from_instance(instance)
                if config["windowMetadata"] && config["windowMetadata"][0]
                    config["windowMetadata"][0]["WindowUniqueId"] = door_id
                    config["windowMetadata"][0]["CreatedDate"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
                    config["windowMetadata"][0]["LastModified"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
                end
                @na_config = config
                na_finalise_bifold_or_sliding_placement(instance, pending_frame, mode, "Exterior single")
            rescue StandardError => e
                DebugTools.na_debug_error("Error creating exterior single door", e)
                UiBridge.na_send_status(@na_dialog, 'error', "Error: #{e.message}")
            end

            def self.na_handle_update_exterior_single_door(config)
                instance = @na_single_door_component
                unless instance && instance.valid?
                    UiBridge.na_send_status(@na_dialog, 'warning', 'No exterior single door selected to update')
                    return
                end

                Na__AssemblyStudio::Na__ExteriorSingleDoorSystem.na_require_modules
                engine = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__GeometryEngine
                serializer = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__DataSerializer
                current_id = serializer.na_get_door_id_from_instance(instance)
                incoming_id = config.dig("windowMetadata", 0, "WindowUniqueId")
                unless current_id
                    UiBridge.na_send_status(@na_dialog, 'warning', 'Selected component is not an exterior single door')
                    return
                end
                if incoming_id && incoming_id != current_id
                    UiBridge.na_send_status(@na_dialog, 'warning', "Update rejected: selected #{current_id}, received #{incoming_id}")
                    return
                end
                updated = engine.na_update_exterior_single_door(instance, config["windowConfiguration"] || {})
                if updated
                    @na_config = config
                    UiBridge.na_send_status(@na_dialog, 'success', "Exterior single door updated: #{instance.name}")
                else
                    UiBridge.na_send_status(@na_dialog, 'error', 'Exterior single door update failed')
                end
            rescue StandardError => e
                DebugTools.na_debug_error("Error updating exterior single door", e)
                UiBridge.na_send_status(@na_dialog, 'error', "Error: #{e.message}")
            end

            def self.na_handle_live_update_exterior_single_door(config)
                instance = @na_single_door_component
                return unless instance && instance.valid?

                Na__AssemblyStudio::Na__ExteriorSingleDoorSystem.na_require_modules
                serializer = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__DataSerializer
                current_id = serializer.na_get_door_id_from_instance(instance)
                incoming_id = config.dig("windowMetadata", 0, "WindowUniqueId")
                if incoming_id && current_id && incoming_id != current_id
                    DebugTools.na_debug_warn("Exterior single door live update skipped: stale #{incoming_id}, current #{current_id}")
                    return
                end

                engine = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__GeometryEngine
                if engine.na_update_exterior_single_door(
                    instance,
                    config["windowConfiguration"] || {},
                    transparent: true
                )
                    @na_config = config
                    Sketchup.active_model.active_view.invalidate
                end
            rescue StandardError => e
                DebugTools.na_debug_error("Live update exterior single door failed (non-fatal)", e)
            end

            # endregion -------------------------------------------------------

            # HELPER FUNCTION | Track One Newly Created Window-Tab Product
            # ------------------------------------------------------------
            def self.na_track_created_component(instance, type)
                @na_window_component = instance
                @na_bifold_component = type == :bifold ? instance : nil
                @na_sliding_component = type == :sliding ? instance : nil
                @na_double_door_component = type == :double_door ? instance : nil
                @na_single_door_component = type == :single_door ? instance : nil
            end
            private_class_method :na_track_created_component
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

            # HELPER FUNCTION | Final Edge-Colour Paint Pass (Post Create / Fuse)
            # ------------------------------------------------------------
            def self.na_apply_edge_colours_after_build(instance, window_config)
                return unless instance && instance.valid?
                return unless window_config.is_a?(Hash)

                LeadedGlassBuilder.na_migrate_legacy_leaded_colour!(window_config)
                EdgeColourPainter.na_apply_assembly_edge_colours(
                    instance.definition.entities,
                    window_config
                )
            rescue StandardError => e
                DebugTools.na_debug_error("Edge colour paint failed (non-fatal)", e)
            end
            private_class_method :na_apply_edge_colours_after_build
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

                if na_is_exterior_double_door_mode?(config["windowConfiguration"])
                    return na_handle_update_exterior_double_door(config)
                end

                if na_is_exterior_single_door_mode?(config["windowConfiguration"])
                    return na_handle_update_exterior_single_door(config)
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
                na_apply_edge_colours_after_build(@na_window_component, config["windowConfiguration"])

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
                config = JSON.parse(config_json)
                window_config = config["windowConfiguration"] || config
                if na_is_exterior_double_door_mode?(window_config)
                    Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem.na_require_modules
                    dxf_content = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__DxfExporter
                        .na_export_dxf(window_config)
                    default_filename = "exterior_double_door_export.dxf"
                else
                    dxf_content = DxfExporter.na_generate_dxf(window_config)
                    default_filename = "window_export.dxf"
                end
                unless dxf_content
                    UiBridge.na_send_status(@na_dialog, 'error', 'Failed to generate DXF content')
                    return
                end

                path = UI.savepanel("Export DXF", "", default_filename)
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

                if na_is_exterior_double_door_mode?(config["windowConfiguration"])
                    return na_handle_live_update_exterior_double_door(config)
                end

                if na_is_exterior_single_door_mode?(config["windowConfiguration"])
                    return na_handle_live_update_exterior_single_door(config)
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
                na_apply_edge_colours_after_build(target_instance, config["windowConfiguration"])

                DataSerializer.na_save_window_data(window_id, @na_config)
                model.commit_operation
                model.active_view.invalidate
                DebugTools.na_debug_success("Live update applied to #{window_id}")
            rescue StandardError => e
                DebugTools.na_debug_error("Error in live update", e)
                UiBridge.na_send_status(@na_dialog, 'error', "Live update failed: #{e.message}")
            end

            # FUNCTION | Engage the Measure-Opening Tool (Cill-Aware)
            # ------------------------------------------------------------
            # @param config_json [String, nil] Optional JSON envelope
            #     pushed by JS at the moment the user clicked Measure
            #     Opening. When supplied we treat it as the authoritative
            #     source of "Include Cill" + cill_height_mm + the per-
            #     edge frame thickness so the cill subtraction always
            #     matches the LIVE UI state.
            #     When nil we fall back to the cached @na_config (set by
            #     the most recent Create) so the legacy no-arg callback
            #     contract still works.
            def self.na_handle_measure_opening(config_json = nil)
                live_config               = na_parse_measure_payload(config_json) || @na_config
                cill_height_mm            = 50                                                      # <-- Defaults match Defaults__.rb
                frame_bottom_thickness_mm = 50

                if live_config && live_config["windowConfiguration"]
                    wc                        = live_config["windowConfiguration"]
                    frame_bottom_thickness_mm = na_resolve_frame_bottom_thickness_mm(wc)
                    cill_height_mm            = na_resolve_cill_subtraction_mm(wc, frame_bottom_thickness_mm)
                end

                DebugTools.na_debug_method(
                    "na_handle_measure_opening (cill_subtract=#{cill_height_mm}mm, " \
                    "frame_bottom=#{frame_bottom_thickness_mm}mm, " \
                    "source=#{config_json ? 'live' : (@na_config ? 'cached' : 'defaults')})"
                )

                tool = TwoPoint.new(self, cill_height_mm, frame_bottom_thickness_mm)
                Sketchup.active_model.select_tool(tool)
            end

            # HELPER FUNCTION | Parse the Optional Live Config JSON From JS
            # ------------------------------------------------------------
            # Wrapped in rescue so a malformed payload never crashes the
            # measure tool - it just falls back to the cached config.
            def self.na_parse_measure_payload(config_json)
                return nil unless config_json.is_a?(String) && !config_json.empty?
                JSON.parse(config_json)
            rescue StandardError => e
                DebugTools.na_debug_warn("Measure callback received malformed config JSON: #{e.message}")
                nil
            end
            private_class_method :na_parse_measure_payload

            # HELPER FUNCTION | Resolve the Effective Frame-Bottom Thickness
            # ------------------------------------------------------------
            # Honours the advanced per-edge override when enabled, else
            # uses the uniform `frame_thickness_mm`. 50mm default keeps
            # backward compat with the legacy hard-coded value.
            def self.na_resolve_frame_bottom_thickness_mm(wc)
                uniform      = wc.key?("frame_thickness_mm") ? wc["frame_thickness_mm"].to_f : 50.0
                use_advanced = wc["advanced_frame_controls"] == true
                if use_advanced && wc.key?("frame_bottom_thickness_mm")
                    wc["frame_bottom_thickness_mm"].to_f
                else
                    uniform
                end
            end
            private_class_method :na_resolve_frame_bottom_thickness_mm

            # HELPER FUNCTION | Resolve the Cill Subtraction in mm
            # ------------------------------------------------------------
            # Returns the amount that should be DEDUCTED from the raw
            # measured Z height before the value is forwarded to the
            # dialog. Returns 0 when:
            #   - the user has toggled "Include Cill" OFF, OR
            #   - the frame is bottom-frameless (frame_bottom == 0), OR
            #   - `has_cill` is missing AND the user has no live config
            #     (defensive: treat unknown state as no cill so we do
            #     not invent a phantom 50mm deduction).
            # Otherwise returns the configured `cill_height_mm` (50mm
            # default when the key is missing on a positive `has_cill`).
            def self.na_resolve_cill_subtraction_mm(wc, frame_bottom_thickness_mm)
                return 0 unless wc["has_cill"] == true
                return 0 unless frame_bottom_thickness_mm > 0
                (wc["cill_height_mm"] || 50).to_f
            end
            private_class_method :na_resolve_cill_subtraction_mm

            # Called by TwoPoint completion. ax/ay/az carry Point A; the
            # optional bx/by/bz carry Point B so the GeometryEngine can
            # derive the wall-direction xaxis and respect the user's
            # drawing axes when inserting the new component.
            def self.na_send_measurement_to_dialog(width_mm, height_mm,
                                                    ax = nil, ay = nil, az = nil,
                                                    bx = nil, by = nil, bz = nil)
                @na_last_measure_frame = na_build_window_measurement_frame(ax, ay, az, bx, by, bz)
                UiBridge.na_execute_numeric_function(
                    @na_dialog, 'window.na_receiveMeasurement',
                    *[width_mm, height_mm, ax, ay, az].compact
                )
            end

            def self.na_send_measure_cancelled_to_dialog
                UiBridge.na_invoke(@na_dialog, 'window.na_measureCancelled')
            end

            # FUNCTION | Consume the Pending Measurement (Frame or Origin Only)
            # ------------------------------------------------------------
            # Returns the most recent measurement frame Hash and clears
            # it so the next created window without a fresh measurement
            # falls back to the placement tool. The Hash may carry just
            # :origin_in (2-point fallback) or the full orientation
            # vector trio.
            def self.na_consume_pending_measurement_frame
                frame = @na_last_measure_frame
                @na_last_measure_frame = nil
                frame
            end

            # HELPER FUNCTION | Build the Measurement Frame from Raw Callback Coords
            # ------------------------------------------------------------
            def self.na_build_window_measurement_frame(ax, ay, az, bx, by, bz)
                return nil unless ax && ay && az
                point_a = Geom::Point3d.new(ax, ay, az)
                return { InsertionFrame::NA_FRAME_KEY_ORIGIN => point_a } unless bx && by && bz

                point_b = Geom::Point3d.new(bx, by, bz)
                InsertionFrame.na_build_measurement_frame_2pt(point_a, point_b)
            end

            def self.na_send_config_to_dialog
                payload = @na_config || na_default_config
                UiBridge.na_execute_json_function(@na_dialog, 'window.na_setInitialConfig', payload)
            end

            def self.na_send_sash_horn_assets_to_dialog
                UiBridge.na_execute_json_function(
                    @na_dialog,
                    'window.na_receiveSashHornAssets',
                    SashHornBuilder.na_load_all_assets
                )
            end

        end
    end
end
