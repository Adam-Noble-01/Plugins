# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - DIALOG ROUTER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__Cabinetry__DialogRouter__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorCabinetrySystem
# MODULE     : Na__DialogRouter
# AUTHOR     : Noble Architecture
# PURPOSE    : Receives the Interior Cabinetry tab's callbacks and runs its
#              flows: place at the cursor, insert along a measured run,
#              update, Live Mode, rename, and the selection load / clear.
# CREATED    : 29-Oct-2026
#
# THE TWO WAYS TO PUT UNITS IN
# - Create at Cursor : starts Na__CabinetPlacementTool. One click per unit,
#                      beside an existing unit, backed onto a wall, or free.
#                      Changes made in the dialog meanwhile reach the next
#                      click (na_syncCabinetPlacementConfig). Esc finishes.
# - Measure Run then Insert in Run : Na__RunMeasureTool returns a run frame;
#                      every Insert in Run places the dialog's unit at the
#                      next free point along it, left to right, and reports
#                      how much of the run is left. The run stays until the
#                      next measurement or Clear Run.
#
# CALLBACKS (JS -> Ruby)
#   na_createCabinetAtCursor(json)        na_createCabinetInRun(json)
#   na_updateCabinet(json)                na_liveUpdateCabinet(json)
#   na_measureCabinetRun()                na_clearCabinetRun()
#   na_syncCabinetPlacementConfig(json)   na_cabinetPlacementRotate()
#   na_renameCabinet(json)                na_requestCabinetAssetOptions()
#   na_cabinetRequestConfig()             na_cabinetJsLog(message)
#
# RUBY -> JS
#   window.na_setInitialCabinetConfig(json)   window.na_clearCurrentCabinet()
#   window.na_receiveCabinetRun(json)         window.na_cabinetMeasureCancelled()
#   window.na_setCabinetPlacementActive(bool) window.na_receiveCabinetAssetOptions(json)
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__UiBridge__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__ComponentNameSuffix__'
require_relative '../06__Tools__MeasurementTools/Na__AssemblyStudio__MeasurementTools__RunMeasureTool__'
require_relative '../07__Tools__PlacementTools/Na__AssemblyStudio__PlacementTools__CabinetPlacementTool__'
require_relative 'Na__AssemblyStudio__Cabinetry__Defaults__'
require_relative 'Na__AssemblyStudio__Cabinetry__LayoutResolver__'
require_relative 'Na__AssemblyStudio__Cabinetry__AssetLibrary__'
require_relative 'Na__AssemblyStudio__Cabinetry__DataSerializer__'
require_relative 'Na__AssemblyStudio__Cabinetry__GeometryEngine__'

module Na__AssemblyStudio
module Na__InteriorCabinetrySystem
    module Na__DialogRouter

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        UiBridge        = Na__AssemblyStudio::Na__AppCore::Na__UiBridge
        NameSuffix      = Na__AssemblyStudio::Na__GeometryHelpers::Na__ComponentNameSuffix
        RunMeasureTool  = Na__AssemblyStudio::Na__MeasurementTools::Na__RunMeasureTool
        PlacementTool   = Na__AssemblyStudio::Na__PlacementTools::Na__CabinetPlacementTool
        Defaults        = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__Defaults
        LayoutResolver  = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__LayoutResolver
        AssetLibrary    = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__AssetLibrary
        DataSerializer  = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__DataSerializer
        GeometryEngine  = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__GeometryEngine

        NA_TYPE_LABELS = { "Base" => "Base Unit", "Wall" => "Wall Unit", "Tower" => "Tall Unit" }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Variables
# -----------------------------------------------------------------------------

        @na_default_config   = nil      # <-- Root payload with the UK defaults
        @na_current_config   = nil      # <-- Root payload last loaded or sent
        @na_current_instance = nil      # <-- Cabinet last created, loaded or updated
        @na_run              = nil      # <-- { :frame => {...}, :used_mm => Float }
        @na_placement_tool   = nil
        @na_placement_root   = nil      # <-- Root payload the next click places
        @na_ghost            = nil      # <-- Outline the placement tool draws

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Initialisation
# -----------------------------------------------------------------------------

        # FUNCTION | Remember the Defaults and Register Every Callback
        # ------------------------------------------------------------
        def self.na_init(dialog, default_config)
            @na_default_config = default_config
            @na_current_config ||= na_deep_clone(default_config)
            UiBridge.na_register_callbacks(dialog, na_callback_registry)
            DebugTools.na_debug_ui("Cabinetry callbacks registered")
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Callback Name -> Handler
        # ------------------------------------------------------------
        def self.na_callback_registry
            {
                "na_createCabinetAtCursor"      => proc { |json| na_start_placement(json) },
                "na_createCabinetInRun"         => proc { |json| na_create_in_run(json) },
                "na_updateCabinet"              => proc { |json| na_update(json, live: false) },
                "na_liveUpdateCabinet"          => proc { |json| na_update(json, live: true) },
                "na_measureCabinetRun"          => proc { na_start_run_measure },
                "na_clearCabinetRun"            => proc { na_clear_run },
                "na_syncCabinetPlacementConfig" => proc { |json| na_sync_placement_config(json) },
                "na_cabinetPlacementRotate"     => proc { @na_placement_tool.na_rotate if @na_placement_tool },
                "na_renameCabinet"              => proc { |json| na_rename(json) },
                "na_requestCabinetAssetOptions" => proc { na_send_asset_options },
                "na_cabinetRequestConfig"       => proc { na_send_config },
                "na_cabinetJsLog"               => proc { |message| DebugTools.na_debug_ui("[JS:Cabinet] #{message}") }
            }
        end
        private_class_method :na_callback_registry
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Create at Cursor (Placement Tool Host)
# -----------------------------------------------------------------------------

        # FUNCTION | Start Placing Units With the Mouse
        # ------------------------------------------------------------
        def self.na_start_placement(config_json)
            @na_placement_root = na_parse(config_json)
            return unless @na_placement_root
            na_refresh_ghost
            @na_placement_tool = PlacementTool.new(self)
            Sketchup.active_model.select_tool(@na_placement_tool)
            UiBridge.na_invoke(na_dialog, "window.na_setCabinetPlacementActive", "true")
            na_status("info", "Click to place the #{@na_ghost[:label]}. Over a unit it goes beside it, over a wall it backs onto it. Tab turns it, Esc finishes.")
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Dialog Changed While Placing: Use It for the Next Click
        # ------------------------------------------------------------
        def self.na_sync_placement_config(config_json)
            return unless @na_placement_tool
            root = na_parse(config_json)
            return unless root
            @na_placement_root = root
            na_refresh_ghost
            Sketchup.active_model.active_view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Placement Tool Host: the Outline to Draw
        # ------------------------------------------------------------
        def self.na_placement_ghost
            @na_ghost
        end
        # ---------------------------------------------------------------

        # FUNCTION | Placement Tool Host: Is This Instance a Cabinet (Its Id)
        # ------------------------------------------------------------
        def self.na_cabinet_id_of(instance)
            DataSerializer.na_get_id_from_instance(instance)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Placement Tool Host: Build One Unit at a World Frame
        # ------------------------------------------------------------
        # @return [Boolean]
        def self.na_place_cabinet(transform)
            return false unless @na_placement_root
            !na_create(na_deep_clone(@na_placement_root), transform, "Place Cabinet").nil?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Placement Tool Host: Placing Has Finished
        # ------------------------------------------------------------
        def self.na_placement_ended
            @na_placement_tool = nil
            UiBridge.na_invoke(na_dialog, "window.na_setCabinetPlacementActive", "false")
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Measured Run
# -----------------------------------------------------------------------------

        # FUNCTION | Start the Run Measure Tool
        # ------------------------------------------------------------
        def self.na_start_run_measure
            Sketchup.active_model.select_tool(RunMeasureTool.new(self))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Run Measure Tool Host: the Run Was Measured
        # ------------------------------------------------------------
        # @param frame [Hash] { :origin, :xaxis, :yaxis, :zaxis, :length_mm } (world)
        def self.na_send_cabinet_run_to_dialog(frame)
            @na_run = { :frame => frame, :used_mm => 0.0 }
            na_send_run_state
        end
        # ---------------------------------------------------------------

        # FUNCTION | Run Measure Tool Host: Measuring Was Cancelled
        # ------------------------------------------------------------
        def self.na_send_cabinet_measure_cancelled_to_dialog
            UiBridge.na_invoke(na_dialog, "window.na_cabinetMeasureCancelled")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Forget the Measured Run
        # ------------------------------------------------------------
        def self.na_clear_run
            @na_run = nil
            na_send_run_state
        end
        # ---------------------------------------------------------------

        # FUNCTION | Insert the Dialog's Unit at the Next Free Point of the Run
        # ------------------------------------------------------------
        def self.na_create_in_run(config_json)
            unless @na_run
                na_status("warning", "No run measured yet. Use Measure Run first.")
                return
            end
            root = na_parse(config_json)
            return unless root

            frame  = @na_run[:frame]
            width  = LayoutResolver.na_effective(root[Defaults::NA_KEY_CONFIGURATION] || {})[:width]
            origin = frame[:origin].offset(frame[:xaxis], @na_run[:used_mm] / 25.4)
            transform = Geom::Transformation.axes(origin, frame[:xaxis], frame[:yaxis], frame[:zaxis])

            return unless na_create(root, transform, "Insert Cabinet in Run")
            @na_run[:used_mm] += width
            over = @na_run[:used_mm] - frame[:length_mm]
            na_status("warning", "This unit runs #{over.round}mm past the end of the measured run.") if over > 0.5
            na_send_run_state
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Tell the Dialog the Run's Length and How Much Is Used
        # ------------------------------------------------------------
        def self.na_send_run_state
            payload = @na_run ? { "active" => true, "lengthMm" => @na_run[:frame][:length_mm].round(1),
                                  "usedMm" => @na_run[:used_mm].round(1) } : { "active" => false }
            UiBridge.na_execute_json_function(na_dialog, "window.na_receiveCabinetRun", payload)
        end
        private_class_method :na_send_run_state
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Create, Update, Live Update, Rename
# -----------------------------------------------------------------------------

        # FUNCTION | Build One Cabinet as One Undo Step and Select It
        # ------------------------------------------------------------
        # @return [Sketchup::ComponentInstance, nil]
        def self.na_create(root, transform, operation_name)
            model = Sketchup.active_model
            model.start_operation(operation_name, true)
            cabinet_id = DataSerializer.na_generate_next_id
            na_stamp_metadata(root, cabinet_id, created: true)
            config     = root[Defaults::NA_KEY_CONFIGURATION] || {}
            instance   = GeometryEngine.na_create_cabinet(config, cabinet_id, transform)
            unless instance
                model.abort_operation
                na_status("error", "The cabinet could not be built. See the Ruby Console.")
                return nil
            end

            unit_type = LayoutResolver.na_effective(config)[:type]
            DataSerializer.na_apply_identity(instance, cabinet_id, unit_type, na_metadata(root)["Na__Cabinet__ComponentName"].to_s)
            DataSerializer.na_save(cabinet_id, root)
            model.commit_operation

            @na_current_instance = instance
            @na_current_config   = root
            model.selection.clear
            model.selection.add(instance)
            na_status("success", "#{instance.name} placed.")
            instance
        rescue StandardError => e
            model.abort_operation if model
            DebugTools.na_debug_error("Cabinet create failed", e)
            na_status("error", "Cabinet create failed: #{e.message}")
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rebuild the Selected Cabinet (Update or Live Mode)
        # ------------------------------------------------------------
        def self.na_update(config_json, live:)
            root = na_parse(config_json)
            return unless root
            target = GeometryEngine.na_find_live_update_target(@na_current_instance)
            unless target
                na_status("warning", live ? "Select a cabinet to use Live Mode." : "Select a cabinet to update.")
                return
            end
            cabinet_id = DataSerializer.na_get_id_from_instance(target)
            incoming   = na_metadata(root)["Na__Cabinet__UniqueId"]
            return if live && incoming && incoming != cabinet_id                 # <-- Stale live payload for another cabinet

            model = Sketchup.active_model
            model.start_operation(live ? "Live Update Cabinet" : "Update Cabinet", true, false, live)
            na_stamp_metadata(root, cabinet_id, created: false)
            config = root[Defaults::NA_KEY_CONFIGURATION] || {}
            if GeometryEngine.na_update_cabinet(target, config)
                DataSerializer.na_apply_identity(target, cabinet_id, LayoutResolver.na_effective(config)[:type])
                DataSerializer.na_save(cabinet_id, root)
                model.commit_operation
                @na_current_instance = target
                @na_current_config   = root
                na_status("success", "#{target.name} updated.") unless live
            else
                model.abort_operation
                na_status("error", "The cabinet could not be rebuilt. See the Ruby Console.")
            end
        rescue StandardError => e
            model.abort_operation if model
            DebugTools.na_debug_error("Cabinet update failed", e)
            na_status("error", "Cabinet update failed: #{e.message}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rename the Selected Cabinet (the Name Tail Only)
        # ------------------------------------------------------------
        def self.na_rename(payload_json)
            payload  = na_parse(payload_json) || {}
            instance = GeometryEngine.na_find_live_update_target(@na_current_instance)
            return unless instance
            cabinet_id = DataSerializer.na_get_id_from_instance(instance)
            data       = DataSerializer.na_load_from_instance(instance, cabinet_id) || na_deep_clone(@na_default_config)
            unit_type  = LayoutResolver.na_effective(data[Defaults::NA_KEY_CONFIGURATION] || {})[:type]

            model = Sketchup.active_model
            model.start_operation("Rename Cabinet", true)
            name = DataSerializer.na_apply_identity(instance, cabinet_id, unit_type, payload["name"].to_s)
            na_metadata(data)["Na__Cabinet__ComponentName"] = NameSuffix.na_extract(name.to_s, Defaults.na_name_head(cabinet_id, unit_type))
            DataSerializer.na_save(cabinet_id, data)
            model.commit_operation
            na_status("success", "Renamed #{name}.")
        rescue StandardError => e
            model.abort_operation if model
            DebugTools.na_debug_error("Cabinet rename failed", e)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Selection Load / Clear
# -----------------------------------------------------------------------------

        # FUNCTION | A Cabinet Was Selected: Show Its Settings
        # ------------------------------------------------------------
        def self.na_load_into_dialog(instance, cabinet_id)
            @na_current_instance = instance
            data = DataSerializer.na_load_from_instance(instance, cabinet_id)
            unless data
                na_status("warning", "#{cabinet_id} has no saved settings; showing the defaults.")
                data = na_deep_clone(@na_default_config)
            end
            metadata = na_metadata(data)
            metadata["Na__Cabinet__UniqueId"]      = cabinet_id
            metadata["Na__Cabinet__ComponentName"] = DataSerializer.na_current_tail(instance, cabinet_id)
            @na_current_config = data
            na_send_config
        end
        # ---------------------------------------------------------------

        # FUNCTION | Nothing (or Something Else) Is Selected
        # ------------------------------------------------------------
        def self.na_clear_from_dialog
            @na_current_instance = nil
            UiBridge.na_invoke(na_dialog, "window.na_clearCurrentCabinet")
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Push the Current Root Payload to the Dialog
        # ------------------------------------------------------------
        def self.na_send_config
            UiBridge.na_execute_json_function(na_dialog, "window.na_setInitialCabinetConfig", @na_current_config || @na_default_config)
        end
        private_class_method :na_send_config
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Asset Options (Handles and Legs)
# -----------------------------------------------------------------------------

        # FUNCTION | Send the Handle and Leg Lists, With Their Preview Data
        # ------------------------------------------------------------
        def self.na_send_asset_options
            AssetLibrary.na_clear_cache
            payload = {
                "handles" => AssetLibrary.na_list(:handles).map { |key| na_handle_option(key) }.compact,
                "legs"    => AssetLibrary.na_list(:legs).map { |key| na_leg_option(key) }.compact
            }
            UiBridge.na_execute_json_function(na_dialog, "window.na_receiveCabinetAssetOptions", payload)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | One Handle Option With Its Elevation and Plan Paths
        # ------------------------------------------------------------
        # The elevation draws the handle on the fronts; the plan is its profile
        # out of the door, which the section preview shows from the side.
        def self.na_handle_option(key)
            asset = AssetLibrary.na_load(:handles, key)
            return nil unless asset
            {
                "value"      => key,
                "label"      => AssetLibrary.na_display_name(:handles, key),
                "kind"       => AssetLibrary.na_metadata_value(asset, "Na__CabinetPlacement__Kind", "Bar"),
                "length"     => AssetLibrary.na_metadata_value(asset, "Na__CabinetPlacement__Length_mm", 0),
                "projection" => AssetLibrary.na_metadata_value(asset, "Na__CabinetPlacement__Projection_mm", 0),
                "elevation"  => asset["Na__Asset__Elevation2D"],
                "plan"       => asset["Na__Asset__Plan2D"]
            }
        end
        private_class_method :na_handle_option
        # ---------------------------------------------------------------

        # HELPER FUNCTION | One Leg Option With Its Side Outline
        # ------------------------------------------------------------
        def self.na_leg_option(key)
            asset = AssetLibrary.na_load(:legs, key)
            return nil unless asset
            {
                "value"     => key,
                "label"     => AssetLibrary.na_display_name(:legs, key),
                "nominal"   => AssetLibrary.na_metadata_value(asset, "Na__CabinetPlacement__NominalHeight_mm", 150),
                "zoneMin"   => AssetLibrary.na_metadata_value(asset, "Na__CabinetPlacement__StretchZoneMin_mm", 0),
                "zoneMax"   => AssetLibrary.na_metadata_value(asset, "Na__CabinetPlacement__StretchZoneMax_mm", 0),
                "elevation" => asset["Na__Asset__Elevation2D"]
            }
        end
        private_class_method :na_leg_option
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | The Live Shared Dialog (Owned by AppCore)
        # ------------------------------------------------------------
        def self.na_dialog
            return nil unless defined?(::Na__AssemblyStudio::Na__AppCore::Na__DialogManager)
            ::Na__AssemblyStudio::Na__AppCore::Na__DialogManager.na_get_dialog
        end
        private_class_method :na_dialog
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Status Message in the Dialog's Dock
        # ------------------------------------------------------------
        def self.na_status(type, message)
            UiBridge.na_send_status(na_dialog, type, message)
        end
        private_class_method :na_status
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Parse a Payload (Nil, With a Status, When Unreadable)
        # ------------------------------------------------------------
        def self.na_parse(json)
            parsed = JSON.parse(json.to_s)
            parsed.is_a?(Hash) ? parsed : nil
        rescue JSON::ParserError => e
            DebugTools.na_debug_error("Cabinet payload unreadable", e)
            na_status("error", "The cabinet settings could not be read.")
            nil
        end
        private_class_method :na_parse
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The First Metadata Entry of a Root Payload
        # ------------------------------------------------------------
        def self.na_metadata(root)
            list = root[Defaults::NA_KEY_METADATA]
            root[Defaults::NA_KEY_METADATA] = list = [{}] unless list.is_a?(Array) && list.first.is_a?(Hash)
            list.first
        end
        private_class_method :na_metadata
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Id and Timestamps on the Metadata
        # ------------------------------------------------------------
        def self.na_stamp_metadata(root, cabinet_id, created:)
            metadata = na_metadata(root)
            now      = Time.now.strftime("%Y-%m-%d %H:%M:%S")
            metadata["Na__Cabinet__UniqueId"]     = cabinet_id
            metadata["Na__Cabinet__CreatedDate"]  = now if created || metadata["Na__Cabinet__CreatedDate"].nil?
            metadata["Na__Cabinet__LastModified"] = now
        end
        private_class_method :na_stamp_metadata
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Rebuild the Placement Ghost From the Placement Config
        # ------------------------------------------------------------
        def self.na_refresh_ghost
            config = (@na_placement_root && @na_placement_root[Defaults::NA_KEY_CONFIGURATION]) || {}
            layout = LayoutResolver.na_resolve(config)
            values = layout[:values]
            @na_ghost = {
                :bounds => layout[:bounds],
                :fronts => layout[:fronts].map { |front| { :x0 => front[:x0], :x1 => front[:x1], :z0 => front[:z0], :z1 => front[:z1], :y => front[:y0] } },
                :label  => "#{values[:width].round} #{NA_TYPE_LABELS[values[:type]]}"
            }
        end
        private_class_method :na_refresh_ghost
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Deep Copy Through Marshal
        # ------------------------------------------------------------
        def self.na_deep_clone(object)
            object.nil? ? nil : Marshal.load(Marshal.dump(object))
        end
        private_class_method :na_deep_clone
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__DialogRouter
end # module Na__InteriorCabinetrySystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
