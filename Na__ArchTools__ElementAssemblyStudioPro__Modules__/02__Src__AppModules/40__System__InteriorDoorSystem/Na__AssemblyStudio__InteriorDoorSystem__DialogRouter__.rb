# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - DIALOG ROUTER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__DialogRouter__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__DialogRouter
# AUTHOR     : Noble Architecture
# PURPOSE    : Receives door-tab callbacks from the shared HtmlDialog
#              and orchestrates create / update / live-update / measure flows.
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Mirrors the responsibility split used by Na__AssemblyStudio::Na__AppCore::Na__DialogManager
#   but only for door-tab actions. The shared HtmlDialog instance is owned by AppCore;
#   this router only consumes a reference to it for execute_script and
#   add_action_callback registration.
# - Responsibilities:
#     * Register door-tab JS callbacks on the shared dialog.
#     * Cache the most recent door measurement (Point A + dimensions).
#     * Orchestrate door create/update/live-update workflows.
#     * Drive the 3-point measure tool and post results back to the dialog.
#     * Provide load/clear hooks invoked by the selection observer.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__UiBridge__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__DataSerializer__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryEngine__'
require_relative '../06__Tools__MeasurementTools/Na__AssemblyStudio__MeasurementTools__ThreePointOpeningTool__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem
    module Na__DialogRouter

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools     = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        UiBridge       = Na__AssemblyStudio::Na__AppCore::Na__UiBridge
        DataSerializer = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__DataSerializer
        GeometryEngine = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryEngine
        AssetLibrary   = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__AssetLibrary
        InsertionFrame = Na__AssemblyStudio::Na__GeometryHelpers::Na__InsertionFrame                    # <-- Wall-aware insertion transform helper

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Variables
# -----------------------------------------------------------------------------
#
# v0.11.6 - The shared HtmlDialog is owned by
# Na__AssemblyStudio::Na__AppCore::Na__DialogManager. The router previously
# cached its own @na_dialog reference but that risked going stale
# across a Reload Scripts cycle. Every execute_script / visible? site
# now goes through the na_active_dialog helper below which asks the
# DialogManager for the live reference each time.
#
# -----------------------------------------------------------------------------

        @na_default_config       = nil            # <-- Default door config supplied by Main
        @na_current_config       = nil            # <-- Most recent door config received from JS
        @na_current_door_inst    = nil            # <-- Currently tracked door ComponentInstance
        @na_last_measurement     = nil            # <-- {:width_mm, :height_mm, :depth_mm, :origin_in => Geom::Point3d}

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Active Dialog Resolver (v0.11.6)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve the Currently Live Shared HtmlDialog
        # ------------------------------------------------------------
        # Single source of truth for the dialog reference. Returns nil
        # if Na__DialogManager has been torn down (e.g. mid-reload), so
        # callers must guard with `return unless dialog`.
        def self.na_active_dialog
            return nil unless defined?(::Na__AssemblyStudio::Na__AppCore::Na__DialogManager)
            mgr = ::Na__AssemblyStudio::Na__AppCore::Na__DialogManager
            return nil unless mgr.respond_to?(:na_get_dialog)
            mgr.na_get_dialog
        rescue StandardError
            nil
        end
        private_class_method :na_active_dialog
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Initialisation
# -----------------------------------------------------------------------------

        # FUNCTION | Initialise the Router and Register All Door Callbacks
        # ------------------------------------------------------------
        # Called from Na__AssemblyStudio::Na__InteriorDoorSystem.na_init_door_callbacks
        # after Na__AssemblyStudio::Na__AppCore::Na__DialogManager has built the
        # shared HtmlDialog.
        #
        # @param dialog [UI::HtmlDialog] Shared dialog instance
        # @param default_config [Hash] Default door configuration
        def self.na_init(dialog, default_config)
            DebugTools.na_debug_method("DialogRouter.na_init")
            @na_default_config  = default_config
            @na_current_config  = na_deep_clone(default_config)

            # v0.11.6 - Dialog passed through to callback registration
            # but no longer cached on this module. na_active_dialog
            # asks Na__DialogManager.na_get_dialog every time.
            na_register_callbacks(dialog)
            DebugTools.na_debug_success("Door dialog router initialised")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Provide the Currently Tracked Door Component Instance
        # ------------------------------------------------------------
        def self.na_current_door_component
            @na_current_door_inst
        end
        # ---------------------------------------------------------------

        # FUNCTION | Provide the Currently Cached Door Configuration
        # ------------------------------------------------------------
        def self.na_current_config
            @na_current_config
        end
        # ---------------------------------------------------------------

        # FUNCTION | Set the Currently Tracked Door Component Instance
        # ------------------------------------------------------------
        def self.na_set_door_component(instance)
            @na_current_door_inst = instance
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Registration
# -----------------------------------------------------------------------------

        # FUNCTION | Register All JS-to-Ruby Action Callbacks
        # ------------------------------------------------------------
        # @param dialog [UI::HtmlDialog] Shared dialog instance. Only
        #   used here to install action callbacks; subsequent calls
        #   resolve the dialog through na_active_dialog so a Reload
        #   Scripts cycle cannot orphan us with a stale reference.
        def self.na_register_callbacks(dialog)
            return unless dialog

            dialog.add_action_callback("na_createDoor") do |_ac, config_json|
                na_handle_create_door(config_json, mode: :auto)                                       # <-- Legacy smart entrypoint (back-compat)
            end

            dialog.add_action_callback("na_createDoorAtCursor") do |_ac, config_json|
                na_handle_create_door(config_json, mode: :cursor)                                     # <-- Discards pending measurement
            end

            dialog.add_action_callback("na_createDoorAtMeasurement") do |_ac, config_json|
                na_handle_create_door(config_json, mode: :measurement)                                # <-- Requires pending measurement
            end

            dialog.add_action_callback("na_updateDoor") do |_ac, config_json|
                na_handle_update_door(config_json)
            end

            dialog.add_action_callback("na_liveUpdateDoor") do |_ac, config_json|
                na_handle_live_update_door(config_json)
            end

            dialog.add_action_callback("na_measureDoorOpening") do |_ac|
                na_handle_measure_door_opening
            end

            dialog.add_action_callback("na_doorJsLog") do |_ac, message|
                DebugTools.na_debug_ui("[JS:Door] #{message}")
            end

            dialog.add_action_callback("na_doorRequestConfig") do |_ac|
                na_send_door_config_to_dialog
            end

            dialog.add_action_callback("na_requestDoorHandleAssetOptions") do |_ac|
                na_send_handle_asset_options_to_dialog
            end

            dialog.add_action_callback("na_requestDoorArchitraveAssetOptions") do |_ac|
                na_send_architrave_asset_options_to_dialog
            end

            dialog.add_action_callback("na_requestDoorHandlePreviewAsset") do |_ac, asset_key|
                na_send_handle_preview_asset_to_dialog(asset_key)
            end

            DebugTools.na_debug_ui("Door callbacks registered")
        end
        private_class_method :na_register_callbacks
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Handlers - Create / Update
# -----------------------------------------------------------------------------

        # FUNCTION | Handle Create Door Callback
        # ------------------------------------------------------------
        # FUNCTION | Handle the Create-Door Callback
        # ------------------------------------------------------------
        # @param config_json [String] Raw JSON payload from the dialog
        # @param mode        [Symbol] :cursor, :measurement, or :auto
        #     - :cursor      -> Discard any cached measurement; door is
        #                       inserted at the model drawing axes
        #                       origin (no placement tool is engaged on
        #                       the door path, so no cursor-follow ghost).
        #     - :measurement -> Require a cached 3-point frame, place
        #                       at the wall using xaxis/yaxis/zaxis.
        #     - :auto        -> Use the cached frame when present,
        #                       otherwise fall back to drawing axes.
        def self.na_handle_create_door(config_json, mode: :auto)
            DebugTools.na_debug_method("DialogRouter.na_handle_create_door (mode=#{mode})")
            model = Sketchup.active_model
            return unless model

            begin
                config_root        = JSON.parse(config_json)
                na_prune_obsolete_config_keys!(config_root)
                na_normalize_architrave_config_keys!(config_root)
                @na_current_config = config_root

                insertion_frame    = na_resolve_door_pending_frame_for_mode(mode)
                return if mode == :measurement && insertion_frame.nil?                                 # <-- Strict mode bail-out (status already emitted)

                model.start_operation("Create Interior Door", true)

                door_id            = DataSerializer.na_generate_next_door_id
                na_apply_create_metadata(config_root, door_id)
                door_config_block  = config_root[NA_DOOR_CONFIG_KEY]

                door_instance      = GeometryEngine.na_create_door(door_config_block, door_id, insertion_frame)

                if door_instance && door_instance.valid?
                    DataSerializer.na_set_door_id_on_instance(
                        door_instance, door_id, na_extract_door_description(config_root)
                    )
                    DataSerializer.na_save_door_data(door_id, config_root)

                    @na_current_door_inst = door_instance
                    model.commit_operation

                    DebugTools.na_debug_success("Created door #{door_id}")
                    na_send_status_to_dialog("success", "Door created: #{door_id}")
                else
                    model.abort_operation
                    DebugTools.na_debug_error("Failed to create door geometry")
                    na_send_status_to_dialog("error", "Failed to create door geometry")
                end
            rescue => e
                model.abort_operation if model
                DebugTools.na_debug_error("Error creating door", e)
                na_send_status_to_dialog("error", "Error: #{e.message}")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Handle Update Door Callback
        # ------------------------------------------------------------
        def self.na_handle_update_door(config_json)
            DebugTools.na_debug_method("DialogRouter.na_handle_update_door")
            model = Sketchup.active_model
            return unless model

            begin
                config_root        = JSON.parse(config_json)
                na_prune_obsolete_config_keys!(config_root)
                na_normalize_architrave_config_keys!(config_root)
                @na_current_config = config_root

                unless @na_current_door_inst && @na_current_door_inst.valid?
                    DebugTools.na_debug_warn("No valid door instance to update")
                    na_send_status_to_dialog("warning", "No door selected to update")
                    return
                end

                door_id = DataSerializer.na_get_door_id_from_instance(@na_current_door_inst)
                unless door_id
                    DebugTools.na_debug_warn("Selected component has no DoorID")
                    na_send_status_to_dialog("warning", "Selected component is not a configurable door")
                    return
                end

                model.start_operation("Update Interior Door", true)

                na_apply_modified_metadata(config_root)
                door_config_block = config_root[NA_DOOR_CONFIG_KEY]

                if GeometryEngine.na_update_door(@na_current_door_inst, door_config_block)
                    DataSerializer.na_set_door_id_on_instance(
                        @na_current_door_inst, door_id, na_extract_door_description(config_root)
                    )
                    DataSerializer.na_save_door_data(door_id, config_root)
                    model.commit_operation

                    DebugTools.na_debug_success("Updated door #{door_id}")
                    na_send_status_to_dialog("success", "Door updated: #{door_id}")
                else
                    model.abort_operation
                    DebugTools.na_debug_error("Failed to update door geometry")
                    na_send_status_to_dialog("error", "Failed to update door geometry")
                end
            rescue => e
                model.abort_operation if model
                DebugTools.na_debug_error("Error updating door", e)
                na_send_status_to_dialog("error", "Error: #{e.message}")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Handle Live Update Door Callback
        # ------------------------------------------------------------
        def self.na_handle_live_update_door(config_json)
            DebugTools.na_debug_method("DialogRouter.na_handle_live_update_door")
            model = Sketchup.active_model
            return unless model

            begin
                config_root         = JSON.parse(config_json)
                na_prune_obsolete_config_keys!(config_root)
                na_normalize_architrave_config_keys!(config_root)

                incoming_id         = na_extract_unique_id(config_root)
                current_id          = nil
                if @na_current_door_inst && @na_current_door_inst.valid?
                    current_id      = DataSerializer.na_get_door_id_from_instance(@na_current_door_inst)
                end

                if incoming_id && current_id && incoming_id != current_id
                    DebugTools.na_debug_warn("Live update skipped: stale data for #{incoming_id}, current door is #{current_id}")
                    return
                end

                @na_current_config  = config_root
                target              = GeometryEngine.na_find_live_update_target(@na_current_door_inst)

                unless target
                    DebugTools.na_debug_warn("Live update door: no door selected")
                    na_send_status_to_dialog("warning", "Select a door to use Live Mode")
                    return
                end
                @na_current_door_inst = target

                door_id             = DataSerializer.na_get_door_id_from_instance(target)
                unless door_id
                    DebugTools.na_debug_warn("Live update door: instance has no DoorID")
                    na_send_status_to_dialog("warning", "Selected item is not a Na Interior Door")
                    return
                end

                door_config_block   = config_root[NA_DOOR_CONFIG_KEY]
                model.start_operation("Live Update Interior Door", true, false, true)

                if GeometryEngine.na_update_door(target, door_config_block)
                    DataSerializer.na_save_door_data(door_id, config_root)
                    model.commit_operation
                    model.active_view.invalidate
                    DebugTools.na_debug_success("Live update applied to door #{door_id}")
                else
                    model.abort_operation
                end
            rescue => e
                model.abort_operation if model
                DebugTools.na_debug_error("Error in live update door", e)
                na_send_status_to_dialog("error", "Live update failed: #{e.message}")
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Handlers - Measurement
# -----------------------------------------------------------------------------

        # FUNCTION | Handle Measure Door Opening Callback
        # ------------------------------------------------------------
        # Activates the 3-point measure tool. The tool calls
        # na_send_door_measurement_to_dialog when the user has picked
        # all three points.
        def self.na_handle_measure_door_opening
            DebugTools.na_debug_method("DialogRouter.na_handle_measure_door_opening")
            # Shared three-point measure tool now lives in
            # 07__PluginCore__MeasurmentToolsModules so any future tab can
            # use the same module. The host (this router) is passed in so
            # the tool can call back via na_send_door_measurement_to_dialog.
            tool = ::Na__AssemblyStudio::Na__MeasurementTools::Na__ThreePointOpeningTool.new(self)
            Sketchup.active_model.select_tool(tool)
            DebugTools.na_debug_success("Measure Door Opening tool activated")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Receive Measurement from the 3-Point Tool
        # ------------------------------------------------------------
        # Caches Point A + the full orientation frame (xaxis along the
        # wall, yaxis through the wall depth, zaxis up) for use as the
        # next door's automatic insertion frame, then forwards the
        # dimensions to the JS side so the UI sliders reflect the
        # measurement.
        #
        # @param width_mm [Numeric]
        # @param height_mm [Numeric]
        # @param depth_mm [Numeric]
        # @param origin_x_in [Numeric] Point A X in inches
        # @param origin_y_in [Numeric] Point A Y in inches
        # @param origin_z_in [Numeric] Point A Z in inches
        # @param point_b_x_in [Numeric, nil] Point B X in inches (defines wall direction)
        # @param point_b_y_in [Numeric, nil] Point B Y in inches
        # @param point_b_z_in [Numeric, nil] Point B Z in inches
        # @param depth_x_in   [Numeric, nil] Depth point X in inches (into the wall)
        # @param depth_y_in   [Numeric, nil] Depth point Y in inches
        # @param depth_z_in   [Numeric, nil] Depth point Z in inches
        def self.na_send_door_measurement_to_dialog(width_mm, height_mm, depth_mm,
                                                     origin_x_in, origin_y_in, origin_z_in,
                                                     point_b_x_in = nil, point_b_y_in = nil, point_b_z_in = nil,
                                                     depth_x_in   = nil, depth_y_in   = nil, depth_z_in   = nil)
            origin_pt    = Geom::Point3d.new(origin_x_in, origin_y_in, origin_z_in)
            frame_struct = na_build_door_measurement_frame(
                origin_pt,
                point_b_x_in, point_b_y_in, point_b_z_in,
                depth_x_in,   depth_y_in,   depth_z_in
            )

            @na_last_measurement = {
                :width_mm  => width_mm,
                :height_mm => height_mm,
                :depth_mm  => depth_mm,
                :origin_in => origin_pt,
                :frame     => frame_struct                                                  # <-- Hash: {:origin_in, :xaxis, :yaxis, :zaxis}
            }

            dialog = na_active_dialog
            return unless dialog

            # v0.11.7 - Every numeric argument MUST be cast to Float before
            # interpolation, otherwise SketchUp's Length#to_s injects a
            # literal `"` or `'` into the JS source and the parser breaks
            # before `na_receiveDoorMeasurement` can run. The earlier door
            # at correct Point A but unchanged sliders symptom was caused
            # exactly by this. See the Length-Safe execute_script
            # Convention in the Architecture doc.
            width_f  = Float(width_mm)
            height_f = Float(height_mm)
            depth_f  = Float(depth_mm)
            ax       = Float(origin_x_in.to_f)                                # <-- Length#to_f -> raw inch Float
            ay       = Float(origin_y_in.to_f)
            az       = Float(origin_z_in.to_f)

            DebugTools.na_debug_info(
                "Sending door measurement to dialog: " \
                "W=#{width_f}mm H=#{height_f}mm D=#{depth_f}mm " \
                "origin=(#{ax}, #{ay}, #{az})in " \
                "frame_oriented=#{InsertionFrame.na_frame_has_orientation?(frame_struct)}"
            )
            sent = UiBridge.na_execute_numeric_function(
                dialog,
                'window.na_receiveDoorMeasurement',
                width_f, height_f, depth_f, ax, ay, az
            )
            unless sent
                DebugTools.na_debug_warn('Door measurement callback skipped: dialog/function not available')
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build the Door Measurement Frame from Raw Coords
        # ------------------------------------------------------------
        def self.na_build_door_measurement_frame(origin_pt, bx, by, bz, dx, dy, dz)
            point_b     = (bx && by && bz) ? Geom::Point3d.new(bx, by, bz) : nil
            depth_point = (dx && dy && dz) ? Geom::Point3d.new(dx, dy, dz) : nil

            return InsertionFrame.na_build_measurement_frame_3pt(origin_pt, point_b, depth_point) if point_b && depth_point
            return InsertionFrame.na_build_measurement_frame_2pt(origin_pt, point_b)              if point_b
            { InsertionFrame::NA_FRAME_KEY_ORIGIN => origin_pt }
        end
        private_class_method :na_build_door_measurement_frame
        # ---------------------------------------------------------------

        # FUNCTION | Notify the Dialog that the User Cancelled the Measure Tool
        # ------------------------------------------------------------
        def self.na_send_door_measure_cancelled_to_dialog
            dialog = na_active_dialog
            return unless dialog
            UiBridge.na_invoke(dialog, 'window.na_doorMeasureCancelled')
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Selection / Load / Clear
# -----------------------------------------------------------------------------

        # FUNCTION | Load a Door Configuration into the Dialog
        # ------------------------------------------------------------
        # Used by Na__AssemblyStudio::Na__InteriorDoorSystem.na_load_door_into_dialog
        # which is called by the selection observer.
        def self.na_load_door_into_dialog(instance, door_id)
            @na_current_door_inst = instance
            data                  = DataSerializer.na_load_door_data_from_instance(instance, door_id)

            if data
                architrave_migrated = na_normalize_architrave_config_keys!(data)
                @na_current_config = data

                if architrave_migrated
                    DataSerializer.na_save_door_data(door_id, data)
                end

                na_send_door_config_to_dialog
                na_send_status_to_dialog("info", "Loaded door: #{door_id}")
            else
                DebugTools.na_debug_warn("Could not load config for door #{door_id}")
                @na_current_config = na_deep_clone(@na_default_config)
                na_send_door_config_to_dialog
                na_send_status_to_dialog("warning", "Door #{door_id} selected but no saved config found")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Clear the Dialog When the User Deselects the Active Door
        # ------------------------------------------------------------
        def self.na_clear_door_from_dialog
            @na_current_door_inst = nil
            @na_current_config    = na_deep_clone(@na_default_config)

            dialog = na_active_dialog
            return unless dialog && dialog.visible?
            dialog.execute_script("window.na_clearCurrentDoor();")
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Dialog Communication
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Send the Current Door Config to the Dialog
        # ------------------------------------------------------------
        def self.na_send_door_config_to_dialog
            dialog = na_active_dialog
            return unless dialog && dialog.visible?
            payload = JSON.generate(@na_current_config || @na_default_config)
            escaped = payload.gsub("'", "\\\\'")
            dialog.execute_script("window.na_setInitialDoorConfig('#{escaped}');")
        end
        private_class_method :na_send_door_config_to_dialog
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Send Door Handle Asset Options to the Dialog
        # ------------------------------------------------------------
        # Builds the handle asset select options dynamically from the
        # current AssetLibrary folder so newly added JSON files appear
        # without hardcoding descriptor options in JS.
        def self.na_send_handle_asset_options_to_dialog
            dialog = na_active_dialog
            return unless dialog && dialog.visible?

            # Ensure fresh reads when users export/replace files mid-session.
            AssetLibrary.na_clear_caches if AssetLibrary.respond_to?(:na_clear_caches)

            # Interior handles plus the shared exterior-door handle bucket so the
            # exterior door dropdowns (double/single) can select the Scroll handle.
            keys = (AssetLibrary.na_list_assets(:handles) + AssetLibrary.na_list_assets(:exterior_handles)).uniq
            options = keys.map { |key| na_build_handle_option(key) }.compact
            options.sort_by! { |option| option["label"].to_s.downcase }

            config_key = @na_current_config.dig(NA_DOOR_CONFIG_KEY, "Na__DoorConfig__HandleAssetKey")
            default_key = if options.any? { |opt| opt["value"] == config_key }
                              config_key
                          elsif @na_default_config.dig(NA_DOOR_CONFIG_KEY, "Na__DoorConfig__HandleAssetKey")
                              @na_default_config.dig(NA_DOOR_CONFIG_KEY, "Na__DoorConfig__HandleAssetKey")
                          else
                              options.first && options.first["value"]
                          end

            payload = {
                "options"    => options,
                "defaultKey" => default_key
            }

            UiBridge.na_execute_json_function(dialog, "window.na_receiveDoorHandleAssetOptions", payload)
            if options.empty?
                na_send_status_to_dialog("warning", "No valid handle assets found in InteriorDoor__Handles__.")
            end
        rescue StandardError => e
            DebugTools.na_debug_error("Failed to send handle asset options", e)
        end
        private_class_method :na_send_handle_asset_options_to_dialog
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Send Door Architrave Asset Options to the Dialog
        # ------------------------------------------------------------
        # Builds the architrave profile select options dynamically from the
        # current AssetLibrary folder so every architrave JSON appears in
        # the menu without hardcoded labels in JS.
        def self.na_send_architrave_asset_options_to_dialog
            dialog = na_active_dialog
            return unless dialog && dialog.visible?

            # Ensure fresh reads when users add/replace files mid-session.
            AssetLibrary.na_clear_caches if AssetLibrary.respond_to?(:na_clear_caches)

            keys = AssetLibrary.na_list_assets(:architraves)
            options = keys.map { |key| na_build_architrave_option(key) }.compact
            options.sort_by! { |option| option["label"].to_s.downcase }

            config_key = @na_current_config.dig(NA_DOOR_CONFIG_KEY, NA_ARCHITRAVE_PROFILE_KEY)
            default_key = if options.any? { |opt| opt["value"] == config_key }
                              config_key
                          elsif @na_default_config.dig(NA_DOOR_CONFIG_KEY, NA_ARCHITRAVE_PROFILE_KEY)
                              @na_default_config.dig(NA_DOOR_CONFIG_KEY, NA_ARCHITRAVE_PROFILE_KEY)
                          else
                              options.first && options.first["value"]
                          end

            payload = {
                "options"    => options,
                "defaultKey" => default_key
            }

            UiBridge.na_execute_json_function(dialog, "window.na_receiveDoorArchitraveAssetOptions", payload)
            if options.empty?
                na_send_status_to_dialog("warning", "No valid architrave assets found in InteriorDoor__Architraves__.")
            end
        rescue StandardError => e
            DebugTools.na_debug_error("Failed to send architrave asset options", e)
        end
        private_class_method :na_send_architrave_asset_options_to_dialog
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Send Selected Handle 2D Preview Blocks to JS
        # ------------------------------------------------------------
        # Sends Plan2D + Elevation2D only (not mesh) for lightweight
        # dialog preview rendering.
        def self.na_send_handle_preview_asset_to_dialog(asset_key)
            dialog = na_active_dialog
            return unless dialog && dialog.visible?

            requested_key = asset_key.to_s.strip
            if requested_key.empty?
                requested_key = @na_current_config.dig(NA_DOOR_CONFIG_KEY, "Na__DoorConfig__HandleAssetKey").to_s
            end
            requested_key = "Na__InteriorDoor__Handle__Default" if requested_key.empty?

            asset = AssetLibrary.na_load_handle_asset(requested_key)
            unless asset.is_a?(Hash)
                DebugTools.na_debug_warn("Handle preview asset not found: #{requested_key}")
                return
            end

            plan_block, plan_warning = na_validate_preview_block(requested_key, "Na__Asset__Plan2D", asset["Na__Asset__Plan2D"])
            elevation_block, elevation_warning = na_validate_preview_block(
                requested_key,
                "Na__Asset__Elevation2D",
                asset["Na__Asset__Elevation2D"]
            )
            warnings = [plan_warning, elevation_warning].compact
            warnings.each { |warning| DebugTools.na_debug_warn(warning) }

            payload = {
                "assetKey"              => requested_key,
                "Na__Asset__Plan2D"     => plan_block,
                "Na__Asset__Elevation2D"=> elevation_block,
                "warnings"              => warnings
            }

            UiBridge.na_execute_json_function(dialog, "window.na_receiveDoorHandlePreviewAsset", payload)
        rescue StandardError => e
            DebugTools.na_debug_error("Failed to send handle preview asset", e)
        end
        private_class_method :na_send_handle_preview_asset_to_dialog
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build a Handle Select Option from Asset Metadata
        # ------------------------------------------------------------
        def self.na_build_handle_option(key)
            asset = AssetLibrary.na_load_handle_asset(key)
            return nil unless asset.is_a?(Hash)

            metadata = asset["Na__Asset__Metadata"]
            unless metadata.is_a?(Hash)
                DebugTools.na_debug_warn("Handle option '#{key}' missing Na__Asset__Metadata - skipping option")
                return nil
            end

            label = metadata["Na__Asset__Name"].to_s.strip
            if label.empty?
                DebugTools.na_debug_warn("Handle option '#{key}' missing Na__Asset__Name - skipping option")
                return nil
            end
            { "value" => key.to_s, "label" => label }
        end
        private_class_method :na_build_handle_option
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build an Architrave Select Option from Asset Metadata
        # ------------------------------------------------------------
        def self.na_build_architrave_option(key)
            asset = AssetLibrary.na_load_architrave_asset(key)
            return nil unless asset.is_a?(Hash)

            metadata = asset["Na__Asset__Metadata"]
            unless metadata.is_a?(Hash)
                DebugTools.na_debug_warn("Architrave option '#{key}' missing Na__Asset__Metadata - skipping option")
                return nil
            end

            label = metadata["Na__Asset__Name"].to_s.strip
            if label.empty?
                DebugTools.na_debug_warn("Architrave option '#{key}' missing Na__Asset__Name - skipping option")
                return nil
            end
            { "value" => key.to_s, "label" => label }
        end
        private_class_method :na_build_architrave_option
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Validate and Sanitize 2D Preview Block
        # ------------------------------------------------------------
        # Returns [sanitized_block_or_nil, warning_or_nil]
        def self.na_validate_preview_block(asset_key, block_name, block)
            unless block.is_a?(Hash)
                return [nil, "Handle preview '#{asset_key}' missing block #{block_name}"]
            end

            paths = block["Na__Geometry__Paths"]
            unless paths.is_a?(Array)
                return [nil, "Handle preview '#{asset_key}' block #{block_name} missing Na__Geometry__Paths array"]
            end

            valid_paths = paths.select { |path| na_valid_preview_path?(path) }
            if valid_paths.empty?
                return [nil, "Handle preview '#{asset_key}' block #{block_name} has no valid path records"]
            end

            sanitized = block.dup
            sanitized["Na__Geometry__Paths"] = valid_paths
            [sanitized, nil]
        end
        private_class_method :na_validate_preview_block
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Preview Path Contract Validation
        # ------------------------------------------------------------
        def self.na_valid_preview_path?(path)
            return false unless path.is_a?(Hash)
            type = path["PathType"].to_s.downcase

            case type
            when "polygon"
                vertices = path["Vertices_mm"]
                return false unless vertices.is_a?(Array) && !vertices.empty?
                return vertices.all? { |vertex| na_valid_xy_point?(vertex) }
            when "line"
                return na_valid_xy_point?(path["Start_mm"]) && na_valid_xy_point?(path["End_mm"])
            when "circle"
                return false unless na_valid_xy_point?(path["Center_mm"])
                return na_numeric_value?(path["Radius_mm"])
            else
                false
            end
        end
        private_class_method :na_valid_preview_path?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Validate XY Point Hash Shape
        # ------------------------------------------------------------
        def self.na_valid_xy_point?(point)
            return false unless point.is_a?(Hash)
            na_numeric_value?(point["X"]) && na_numeric_value?(point["Y"])
        end
        private_class_method :na_valid_xy_point?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Numeric Coercion Guard
        # ------------------------------------------------------------
        def self.na_numeric_value?(value)
            Float(value)
            true
        rescue StandardError
            false
        end
        private_class_method :na_numeric_value?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Forward a Status Message to the Dialog
        # ------------------------------------------------------------
        def self.na_send_status_to_dialog(status_type, message)
            dialog = na_active_dialog
            return unless dialog && dialog.visible?
            escaped = message.to_s.gsub("'", "\\\\'")
            dialog.execute_script("window.na_showStatus('#{status_type}', '#{escaped}');")
        end
        private_class_method :na_send_status_to_dialog
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Configuration Mutation
# -----------------------------------------------------------------------------

        NA_DOOR_CONFIG_KEY    = "Na__DoorConfiguration".freeze
        NA_DOOR_METADATA_KEY  = "Na__DoorMetadata".freeze
        NA_OBSOLETE_DOOR_CONFIG_KEYS = ["Na__DoorConfig__HandleSide"].freeze
        NA_ARCHITRAVE_PROFILE_KEY               = "Na__DoorConfig__ArchitraveProfileKey".freeze
        NA_ARCHITRAVE_LEGACY_ASSET_KEY          = "Na__DoorConfig__ArchitraveAssetKey".freeze
        NA_ARCHITRAVE_ENABLED_KEY               = "Na__DoorConfig__ArchitraveEnabled".freeze
        NA_ARCHITRAVE_FRONT_ENABLED_KEY         = "Na__DoorConfig__ArchitraveFrontEnabled".freeze
        NA_ARCHITRAVE_BACK_ENABLED_KEY          = "Na__DoorConfig__ArchitraveBackEnabled".freeze
        NA_ARCHITRAVE_LEGACY_DEFAULT_PROFILE_KEY= "Na__InteriorDoor__Architrave__Default".freeze
        NA_ARCHITRAVE_DEFAULT_PROFILE_KEY       = "Na__Asset__Plan2D__Architrave__Default__w70mm_x_d20mm".freeze

        # HELPER FUNCTION | Deep Clone via Marshal
        # ------------------------------------------------------------
        def self.na_deep_clone(obj)
            return nil if obj.nil?
            Marshal.load(Marshal.dump(obj))
        end
        private_class_method :na_deep_clone
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Set the Unique ID and Timestamps on a New Door's Metadata
        # ------------------------------------------------------------
        def self.na_apply_create_metadata(config_root, door_id)
            metadata = na_first_metadata_entry(config_root)
            return unless metadata
            now                                = Time.now.strftime("%Y-%m-%d %H:%M:%S")
            metadata["Na__Door__UniqueId"]     = door_id
            metadata["Na__Door__CreatedDate"]  = now
            metadata["Na__Door__LastModified"] = now
        end
        private_class_method :na_apply_create_metadata
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Refresh the LastModified Timestamp on an Updated Door
        # ------------------------------------------------------------
        def self.na_apply_modified_metadata(config_root)
            metadata = na_first_metadata_entry(config_root)
            return unless metadata
            metadata["Na__Door__LastModified"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
        end
        private_class_method :na_apply_modified_metadata
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Pull the Door Description Out of the Metadata Block
        # ------------------------------------------------------------
        def self.na_extract_door_description(config_root)
            metadata = na_first_metadata_entry(config_root)
            metadata && metadata["Na__Door__Description"]
        end
        private_class_method :na_extract_door_description
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Pull the UniqueId Out of the Metadata Block
        # ------------------------------------------------------------
        def self.na_extract_unique_id(config_root)
            metadata = na_first_metadata_entry(config_root)
            metadata && metadata["Na__Door__UniqueId"]
        end
        private_class_method :na_extract_unique_id
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return the First Metadata Entry (the array head)
        # ------------------------------------------------------------
        def self.na_first_metadata_entry(config_root)
            return nil unless config_root.is_a?(Hash)
            metadata = config_root[NA_DOOR_METADATA_KEY]
            return nil unless metadata.is_a?(Array)
            metadata.first.is_a?(Hash) ? metadata.first : nil
        end
        private_class_method :na_first_metadata_entry
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Remove Deprecated Door Configuration Keys
        # ------------------------------------------------------------
        def self.na_prune_obsolete_config_keys!(config_root)
            return unless config_root.is_a?(Hash)
            config_block = config_root[NA_DOOR_CONFIG_KEY]
            return unless config_block.is_a?(Hash)

            NA_OBSOLETE_DOOR_CONFIG_KEYS.each do |key|
                config_block.delete(key)
            end
        end
        private_class_method :na_prune_obsolete_config_keys!
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Normalize Architrave Keys for Legacy Payloads
        # ------------------------------------------------------------
        # Returns true when one or more migration changes are applied.
        def self.na_normalize_architrave_config_keys!(config_root)
            return false unless config_root.is_a?(Hash)
            config_block = config_root[NA_DOOR_CONFIG_KEY]
            return false unless config_block.is_a?(Hash)

            changed = false
            profile_key = config_block[NA_ARCHITRAVE_PROFILE_KEY].to_s.strip
            legacy_asset_key = config_block[NA_ARCHITRAVE_LEGACY_ASSET_KEY].to_s.strip

            if profile_key.empty? && !legacy_asset_key.empty?
                profile_key = legacy_asset_key
            end

            if profile_key.empty? || profile_key == NA_ARCHITRAVE_LEGACY_DEFAULT_PROFILE_KEY
                profile_key = NA_ARCHITRAVE_DEFAULT_PROFILE_KEY
            end

            if config_block[NA_ARCHITRAVE_PROFILE_KEY] != profile_key
                config_block[NA_ARCHITRAVE_PROFILE_KEY] = profile_key
                changed = true
            end

            if config_block.key?(NA_ARCHITRAVE_LEGACY_ASSET_KEY)
                config_block.delete(NA_ARCHITRAVE_LEGACY_ASSET_KEY)
                changed = true
            end

            if config_block.key?(NA_ARCHITRAVE_ENABLED_KEY)
                enabled = (config_block[NA_ARCHITRAVE_ENABLED_KEY] != false)
                if config_block[NA_ARCHITRAVE_FRONT_ENABLED_KEY] != enabled
                    config_block[NA_ARCHITRAVE_FRONT_ENABLED_KEY] = enabled
                    changed = true
                end
                if config_block[NA_ARCHITRAVE_BACK_ENABLED_KEY] != enabled
                    config_block[NA_ARCHITRAVE_BACK_ENABLED_KEY] = enabled
                    changed = true
                end
                config_block.delete(NA_ARCHITRAVE_ENABLED_KEY)
                changed = true
            else
                unless config_block.key?(NA_ARCHITRAVE_FRONT_ENABLED_KEY)
                    config_block[NA_ARCHITRAVE_FRONT_ENABLED_KEY] = true
                    changed = true
                end
                unless config_block.key?(NA_ARCHITRAVE_BACK_ENABLED_KEY)
                    config_block[NA_ARCHITRAVE_BACK_ENABLED_KEY] = true
                    changed = true
                end
            end

            changed
        end
        private_class_method :na_normalize_architrave_config_keys!
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Pending Measurement
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Consume Cached Point A as Insertion Origin (One-Shot)
        # ------------------------------------------------------------
        # Returns the Geom::Point3d (in inches) and clears the cache so
        # the next door created without a fresh measurement falls back
        # to the placement tool. This implements the "Point A + wall
        # direction from measurement is the priority insertion frame"
        # rule. Returns the frame Hash (with orientation vectors when
        # the 3-point tool captured them); falls back to just the
        # origin when the legacy 2-point payload was used.
        def self.na_consume_pending_measurement_frame
            return nil unless @na_last_measurement
            frame  = @na_last_measurement[:frame]
            origin = @na_last_measurement[:origin_in]
            @na_last_measurement = nil
            frame || (origin ? { InsertionFrame::NA_FRAME_KEY_ORIGIN => origin } : nil)
        end
        private_class_method :na_consume_pending_measurement_frame

        # HELPER FUNCTION | Resolve Pending Frame for a Create-Door Mode
        # ------------------------------------------------------------
        # Single source of truth for "which measurement (if any) does
        # this create call use?". Mirrors the Window-tab pattern so
        # both tabs share the same predictable two-button semantics.
        #
        # @param mode [Symbol] :cursor, :measurement, :auto
        # @return [Hash, nil] Frame Hash for the engine (nil = no frame)
        def self.na_resolve_door_pending_frame_for_mode(mode)
            case mode
            when :cursor
                na_consume_pending_measurement_frame                                                # <-- Discard the cache so it can't sneak in later
                nil                                                                                   # <-- Engine will fall back to model drawing axes
            when :measurement
                frame = na_consume_pending_measurement_frame
                unless frame
                    DebugTools.na_debug_warn("Create-Door-at-Measurement requested with no cached frame")
                    na_send_status_to_dialog("warning", 'No door measurement on file. Use "Measure Opening" first.')
                    return nil
                end
                frame
            else
                na_consume_pending_measurement_frame                                                # <-- Legacy "auto" behaviour
            end
        end
        private_class_method :na_resolve_door_pending_frame_for_mode
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__DialogRouter
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
