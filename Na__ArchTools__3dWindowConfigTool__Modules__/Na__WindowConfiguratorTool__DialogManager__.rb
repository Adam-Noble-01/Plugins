# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__DialogManager__.rb
# NAMESPACE  : Na__WindowConfiguratorTool
# MODULE     : Na__DialogManager
# AUTHOR     : Noble Architecture
# PURPOSE    : Manages UI::HtmlDialog and JS ↔ Ruby communication
# CREATED    : 2026
# VERSION    : 0.2.3b
#
# DESCRIPTION:
# - Creates and manages the UI::HtmlDialog instance
# - Sets up all JavaScript → Ruby action callbacks
# - Handles create/update/export/reload/live-update actions
# - Manages dialog communication (sending config, status messages)
# - Loads window configuration into dialog on selection
# - Developer reload feature for rapid iteration
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative 'Na__WindowConfiguratorTool__DebugTools__'
require_relative 'Na__WindowConfiguratorTool__DataSerializer__'
require_relative 'Na__WindowConfiguratorTool__GeometryEngine__'
require_relative 'Na__WindowConfiguratorTool__DxfExporterLogic__'
require_relative 'Na__WindowConfiguratorTool__PlacementTool__'
require_relative File.join('07__PluginCore__MeasurmentToolsModules', 'Na__MeasurementTools__TwoPointOpeningTool__')
require_relative 'Na__WindowConfiguratorTool__FuseParts__'

module Na__WindowConfiguratorTool
    module Na__DialogManager

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__WindowConfiguratorTool::Na__DebugTools
        DataSerializer = Na__WindowConfiguratorTool::Na__DataSerializer
        GeometryEngine = Na__WindowConfiguratorTool::Na__GeometryEngine
        DxfExporter = Na__WindowConfiguratorTool::Na__DxfExporter
        FuseParts = Na__WindowConfiguratorTool::Na__FuseParts

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Variables
# -----------------------------------------------------------------------------

        @dialog = nil                  # HtmlDialog instance
        @window_component = nil        # Current window component being edited
        @config = nil                  # Current configuration hash
        @last_measure_origin = nil     # <-- Point A from the most recent measurement (Geom::Point3d, inches). One-shot, consumed by next na_create_window.
        @na_active_tab_id = "windows"  # <-- v0.11.6 Cache of the JS-side active tab; pushed by Na_AppContext via sketchup.na_setActiveTab.
        @current_placement_tool = nil  # <-- v0.11.6 Active Na__WindowPlacementTool instance (declared explicitly; previously implicit).

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        # FUNCTION | Show Configuration Dialog
        # ------------------------------------------------------------
        def self.na_show_dialog(html_file_path, plugin_root_path, default_config)
            DebugTools.na_debug_method("DialogManager.na_show_dialog")
            
            # Close existing dialog if open
            if @dialog && @dialog.visible?
                @dialog.close
            end
            
            # Create new dialog
            # Width bumped from 525 -> 720 to accommodate the new dual-tab layout
            # (Windows | Interior Doors) and the wider plan/elevation viewports
            # used by the Interior Door tab.
            @dialog = UI::HtmlDialog.new(
                dialog_title: "Na Architectural Configurator",
                preferences_key: "Na__WindowConfiguratorTool",
                scrollable: true,
                resizable: true,
                width: 720,
                height: 1200,
                left: 100,
                top: 100,
                style: UI::HtmlDialog::STYLE_DIALOG
            )
            
            # Load HTML content
            if File.exist?(html_file_path)
                @dialog.set_file(html_file_path)
                DebugTools.na_debug_ui("Loaded HTML from: #{html_file_path}")
            else
                DebugTools.na_debug_error("HTML file not found: #{html_file_path}")
                # Set fallback HTML
                @dialog.set_html(na_create_fallback_html)
            end
            
            # Setup callbacks
            na_setup_dialog_callbacks(plugin_root_path, default_config)
            
            # Show dialog
            @dialog.show
            
            # Initialize with default or selected window config
            na_check_initial_selection(default_config)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Check Initial Selection for Existing Window
        # ------------------------------------------------------------
        def self.na_check_initial_selection(default_config)
            selection = Sketchup.active_model.selection
            
            if selection.length == 1 && selection.first.is_a?(Sketchup::ComponentInstance)
                instance = selection.first
                window_id = DataSerializer.na_get_window_id_from_instance(instance)
                
                if window_id
                    DebugTools.na_debug_window("Found existing window in selection: #{window_id}")
                    na_load_window_into_dialog(instance, window_id, default_config)
                    return
                end
            end
            
            # No existing window selected, use default config
            @config = Marshal.load(Marshal.dump(default_config)) # Deep clone
            DebugTools.na_debug_window("Using default configuration")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Dialog Instance
        # ------------------------------------------------------------
        # @return [UI::HtmlDialog, nil] The dialog instance
        def self.na_get_dialog
            @dialog
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get the Cached Active Tab ID (v0.11.6)
        # ------------------------------------------------------------
        # Returns the JS-side active tab id that Na_AppContext pushed via
        # sketchup.na_setActiveTab. Used by the SelectionObserver to
        # decide whether to load window or door data and whether to
        # request an auto-switch on the dialog.
        # @return [String] One of "windows", "doors", "settings"
        def self.na_get_active_tab_id
            @na_active_tab_id || "windows"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Request the Dialog Switch to a Different Tab (v0.11.6)
        # ------------------------------------------------------------
        # Used by the SelectionObserver when the user clicks a component
        # belonging to a tab they are not currently viewing - the dialog
        # is asked to swap to the matching tab so the loaded config
        # actually appears. Defensive: silently no-ops if the dialog is
        # not visible. Sanitises the tab id so an unexpected character
        # cannot escape the JS string literal.
        # @param tab_id [String] The desired tab id ("windows", "doors", "settings")
        def self.na_request_tab_switch(tab_id)
            return unless @dialog && @dialog.visible?
            return if tab_id.nil?

            safe_id = tab_id.to_s.gsub(/[^A-Za-z0-9_-]/, "")                  # Strip any character that could break the literal
            return if safe_id.empty?

            @dialog.execute_script(
                "if(window.Na_AppContext){Na_AppContext.na_activateTab('#{safe_id}');}"
            )
            @na_active_tab_id = safe_id                                       # Update cache eagerly; JS will confirm on next na_setActiveTab
            DebugTools.na_debug_ui("Requested tab switch to #{safe_id}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Current Window Component
        # ------------------------------------------------------------
        # @return [Sketchup::ComponentInstance, nil] The current window component
        def self.na_get_window_component
            @window_component
        end
        # ---------------------------------------------------------------

        # FUNCTION | Set Current Window Component
        # ------------------------------------------------------------
        # @param instance [Sketchup::ComponentInstance] The window component
        def self.na_set_window_component(instance)
            @window_component = instance
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Current Config
        # ------------------------------------------------------------
        # @return [Hash, nil] The current configuration
        def self.na_get_config
            @config
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Setup
# -----------------------------------------------------------------------------

        # FUNCTION | Setup Dialog Action Callbacks
        # ------------------------------------------------------------
        def self.na_setup_dialog_callbacks(plugin_root_path, default_config)
            DebugTools.na_debug_method("DialogManager.na_setup_dialog_callbacks")
            
            # Callback: Create New Window
            @dialog.add_action_callback("na_createWindow") do |action_context, config_json|
                na_handle_create_window(config_json)
            end
            
            # Callback: Update Existing Window
            @dialog.add_action_callback("na_updateWindow") do |action_context, config_json|
                na_handle_update_window(config_json)
            end
            
            # Callback: Reload Scripts (Developer Feature)
            @dialog.add_action_callback("na_reloadScripts") do |action_context|
                na_reload_scripts(plugin_root_path)
            end

            # Callback: Settings Tab - Run the 2D-Only ValeSpec-Style JSON Exporter
            @dialog.add_action_callback("na_settingsExport2D") do |_action_context|
                na_handle_settings_export_2d
            end

            # Callback: Settings Tab - Run the Unified 2D + 3D Asset JSON Exporter
            @dialog.add_action_callback("na_settingsExport3D") do |_action_context|
                na_handle_settings_export_3d
            end
            
            # Callback: Export DXF
            @dialog.add_action_callback("na_exportDxf") do |action_context, config_json|
                na_handle_export_dxf(config_json)
            end
            
            # Callback: Request Current Config (for UI sync)
            @dialog.add_action_callback("na_requestConfig") do |action_context|
                na_send_config_to_dialog(default_config)
            end
            
            # Callback: Log from JavaScript
            @dialog.add_action_callback("na_jsLog") do |action_context, message|
                DebugTools.na_debug_ui("[JS] #{message}")
            end
            
            # Callback: Live Update (real-time geometry update)
            @dialog.add_action_callback("na_liveUpdate") do |action_context, config_json|
                na_handle_live_update(config_json, default_config)
            end
            
            # Callback: Measure Opening (activate 3D measurement tool)
            @dialog.add_action_callback("na_measureOpening") do |action_context|
                na_handle_measure_opening
            end

            # Callback: Tab key forwarded from dialog during placement mode
            # Fired by the JS Tab interceptor when na_placementModeActive is true.
            @dialog.add_action_callback("na_keyboard_tab") do |action_context|
                if @current_placement_tool
                    @current_placement_tool.na_rotate
                end
            end

            # Callback: Active Tab Sync (Pushed by Na_AppContext)
            # ------------------------------------------------------------
            # The JS-side Na_AppContext fires this every time the user
            # switches tabs (and once on dialog load). The Ruby
            # SelectionObserver consults the cached value before deciding
            # whether to load window or door data, so the routing
            # decision can be made without a synchronous call back into
            # the dialog.
            @dialog.add_action_callback("na_setActiveTab") do |_action_context, tab_id|
                @na_active_tab_id = tab_id.to_s if tab_id
                DebugTools.na_debug_ui("Active tab cached on Ruby side: #{@na_active_tab_id}")
            end

            DebugTools.na_debug_success("Dialog callbacks configured")
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Handlers
# -----------------------------------------------------------------------------

        # FUNCTION | Handle Create Window Callback
        # ------------------------------------------------------------
        def self.na_handle_create_window(config_json)
            DebugTools.na_debug_method("DialogManager.na_handle_create_window")
            
            begin
                config = JSON.parse(config_json)
                @config = config
                
                model = Sketchup.active_model
                model.start_operation("Create Window", true)
                
                # Generate new window ID
                window_id = DataSerializer.na_generate_next_window_id
                
                # Update metadata with ID
                if @config["windowMetadata"] && @config["windowMetadata"][0]
                    @config["windowMetadata"][0]["WindowUniqueId"] = window_id
                    @config["windowMetadata"][0]["CreatedDate"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
                    @config["windowMetadata"][0]["LastModified"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
                end
                
                # Consume any cached measurement origin (Point A) so the instance is
                # placed automatically at the measurement's base corner. This is the
                # priority insertion path when the user has just used the Measure tool.
                pending_origin = na_consume_pending_measurement_origin

                @window_component = GeometryEngine.na_create_window_geometry(
                    config["windowConfiguration"], window_id, pending_origin
                )

                if @window_component && @window_component.valid?
                    # Fuse parts if enabled (post-processing boolean operations)
                    if config["windowConfiguration"] && config["windowConfiguration"]["fuse_parts"] == true
                        DebugTools.na_debug_info("Fuse Parts enabled - running post-processing...")
                        na_send_status_to_dialog(nil, "info", "Fusing parts...")
                        fuse_summary = FuseParts.na_fuse_window_parts(@window_component.definition.entities)
                        DebugTools.na_debug_info("Fuse result: #{fuse_summary.inspect}")
                    end
                    
                    # Extract optional description suffix from metadata
                    description = nil
                    if @config["windowMetadata"] && @config["windowMetadata"][0]
                        description = @config["windowMetadata"][0]["WindowDescription"]
                    end
                    
                    # Set window ID and naming on the instance (AWN001__Window__Description)
                    DataSerializer.na_set_window_id_on_instance(@window_component, window_id, description)
                    
                    # Save config to component dictionary
                    DataSerializer.na_save_window_data(window_id, @config)
                    
                    model.commit_operation

                    if pending_origin
                        DebugTools.na_debug_success("Created window #{window_id} at measured Point A")
                        fuse_msg = (config["windowConfiguration"] && config["windowConfiguration"]["fuse_parts"] == true) ? " (fused)" : ""
                        na_send_status_to_dialog(nil, "success", "Window placed at measured Point A: #{window_id}#{fuse_msg}")
                    else
                        placement_tool = Na__WindowPlacementTool.new(@window_component)
                        @current_placement_tool = placement_tool
                        Sketchup.active_model.select_tool(placement_tool)

                        if @dialog && @dialog.visible?
                            @dialog.execute_script("window.na_setPlacementActive(true);")
                            @dialog.execute_script("if(document.activeElement){document.activeElement.blur();}")
                        end

                        DebugTools.na_debug_success("Created window #{window_id}")
                        fuse_msg = (config["windowConfiguration"] && config["windowConfiguration"]["fuse_parts"] == true) ? " (fused)" : ""
                        na_send_status_to_dialog(nil, "success", "Window created: #{window_id}#{fuse_msg}")
                    end
                else
                    model.abort_operation
                    DebugTools.na_debug_error("Failed to create window geometry")
                    na_send_status_to_dialog(nil, "error", "Failed to create window geometry")
                end
                
            rescue => e
                model.abort_operation if model
                DebugTools.na_debug_error("Error creating window", e)
                na_send_status_to_dialog(nil, "error", "Error: #{e.message}")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Handle Update Window Callback
        # ------------------------------------------------------------
        def self.na_handle_update_window(config_json)
            DebugTools.na_debug_method("DialogManager.na_handle_update_window")
            
            begin
                config = JSON.parse(config_json)
                @config = config
                
                unless @window_component && @window_component.valid?
                    DebugTools.na_debug_warn("No valid window component to update")
                    na_send_status_to_dialog(nil, "warning", "No window selected to update")
                    return
                end
                
                window_id = DataSerializer.na_get_window_id_from_instance(@window_component)
                unless window_id
                    DebugTools.na_debug_warn("Selected component has no WindowID")
                    na_send_status_to_dialog(nil, "warning", "Selected component is not a configurable window")
                    return
                end
                
                model = Sketchup.active_model
                model.start_operation("Update Window", true)
                
                # Update timestamp
                if @config["windowMetadata"] && @config["windowMetadata"][0]
                    @config["windowMetadata"][0]["LastModified"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
                end
                
                # Regenerate geometry (delegate to GeometryEngine)
                GeometryEngine.na_update_window_geometry(@window_component, config["windowConfiguration"])
                
                # Fuse parts if enabled (post-processing boolean operations)
                if config["windowConfiguration"] && config["windowConfiguration"]["fuse_parts"] == true
                    DebugTools.na_debug_info("Fuse Parts enabled - running post-processing...")
                    na_send_status_to_dialog(nil, "info", "Fusing parts...")
                    fuse_summary = FuseParts.na_fuse_window_parts(@window_component.definition.entities)
                    DebugTools.na_debug_info("Fuse result: #{fuse_summary.inspect}")
                end
                
                # Update instance/definition names if description changed
                description = nil
                if @config["windowMetadata"] && @config["windowMetadata"][0]
                    description = @config["windowMetadata"][0]["WindowDescription"]
                end
                DataSerializer.na_set_window_id_on_instance(@window_component, window_id, description)
                
                # Save updated config
                DataSerializer.na_save_window_data(window_id, @config)
                
                model.commit_operation
                
                DebugTools.na_debug_success("Updated window #{window_id}")
                fuse_msg = (config["windowConfiguration"] && config["windowConfiguration"]["fuse_parts"] == true) ? " (fused)" : ""
                na_send_status_to_dialog(nil, "success", "Window updated: #{window_id}#{fuse_msg}")
                
            rescue => e
                model.abort_operation if model
                DebugTools.na_debug_error("Error updating window", e)
                na_send_status_to_dialog(nil, "error", "Error: #{e.message}")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Handle DXF Export Callback
        # ------------------------------------------------------------
        def self.na_handle_export_dxf(config_json)
            DebugTools.na_debug_method("DialogManager.na_handle_export_dxf")
            
            begin
                # Parse configuration from JSON
                config = JSON.parse(config_json)
                DebugTools.na_debug_info("Generating DXF from config")
                
                # Generate DXF content using the dedicated exporter module
                dxf_content = DxfExporter.na_generate_dxf(config)
                
                unless dxf_content
                    DebugTools.na_debug_error("DXF generation returned nil")
                    na_send_status_to_dialog(nil, "error", "Failed to generate DXF content")
                    return
                end
                
                # Prompt for save location
                path = UI.savepanel("Export DXF", "", "window_export.dxf")
                
                if path
                    # Ensure .dxf extension
                    path = path + ".dxf" unless path.downcase.end_with?(".dxf")
                    
                    File.write(path, dxf_content)
                    DebugTools.na_debug_success("DXF exported to: #{path}")
                    na_send_status_to_dialog(nil, "success", "DXF exported: #{File.basename(path)}")
                else
                    DebugTools.na_debug_info("DXF export cancelled by user")
                end
                
            rescue JSON::ParserError => e
                DebugTools.na_debug_error("Invalid JSON in DXF export", e)
                na_send_status_to_dialog(nil, "error", "Invalid configuration data")
            rescue => e
                DebugTools.na_debug_error("Error exporting DXF", e)
                na_send_status_to_dialog(nil, "error", "Export failed: #{e.message}")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Handle Live Update Callback
        # ------------------------------------------------------------
        def self.na_handle_live_update(config_json, default_config)
            DebugTools.na_debug_method("DialogManager.na_handle_live_update")
            
            begin
                config = JSON.parse(config_json)
                
                # GUARD: Reject stale live updates from before a selection change.
                # The JS payload contains the WindowUniqueId it was built for.
                # If that doesn't match the currently tracked @window_component,
                # this update is outdated (e.g., debounce fired after user selected
                # a different window) and must be discarded.
                incoming_id = nil
                if config["windowMetadata"] && config["windowMetadata"][0]
                    incoming_id = config["windowMetadata"][0]["WindowUniqueId"]
                end
                
                current_id = nil
                if @window_component && @window_component.valid?
                    current_id = DataSerializer.na_get_window_id_from_instance(@window_component)
                end
                
                if incoming_id && current_id && incoming_id != current_id
                    DebugTools.na_debug_warn("Live update skipped: stale data for #{incoming_id}, current window is #{current_id}")
                    return
                end
                
                @config = config
                
                # Find the target window component to update (delegate to GeometryEngine)
                target_instance = GeometryEngine.na_find_live_update_target(@window_component)
                
                unless target_instance
                    DebugTools.na_debug_warn("Live update: No window selected")
                    na_send_status_to_dialog(default_config, "warning", "Select a window to use Live Mode")
                    return
                end
                
                # Store for future use
                @window_component = target_instance
                
                # Get window ID from the target
                window_id = DataSerializer.na_get_window_id_from_instance(target_instance)
                
                unless window_id
                    DebugTools.na_debug_warn("Live update: Selected component is not a Na Window")
                    na_send_status_to_dialog(default_config, "warning", "Selected item is not a Na Window")
                    return
                end
                
                # Perform the live update
                model = Sketchup.active_model
                model.start_operation("Live Update Window", true, false, true)  # Transparent operation
                
                # Regenerate geometry (delegate to GeometryEngine)
                GeometryEngine.na_update_window_geometry(target_instance, config["windowConfiguration"])
                
                # Fuse parts if enabled (post-processing boolean operations)
                # Note: This adds computational overhead to live updates
                if config["windowConfiguration"] && config["windowConfiguration"]["fuse_parts"] == true
                    DebugTools.na_debug_info("Fuse Parts enabled in Live Mode - running post-processing...")
                    begin
                        fuse_summary = FuseParts.na_fuse_window_parts(target_instance.definition.entities)
                        DebugTools.na_debug_info("Live Mode fuse result: #{fuse_summary.inspect}")
                    rescue => e
                        DebugTools.na_debug_error("Fuse Parts error in Live Mode (non-fatal)", e)
                        # Don't fail the entire live update if fusion fails
                    end
                end
                
                # Save updated config
                DataSerializer.na_save_window_data(window_id, @config)
                
                model.commit_operation
                
                # Force viewport refresh
                model.active_view.invalidate
                
                DebugTools.na_debug_success("Live update applied to #{window_id}")
                
            rescue => e
                DebugTools.na_debug_error("Error in live update", e)
                na_send_status_to_dialog(default_config, "error", "Live update failed: #{e.message}")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Handle Measure Opening Callback
        # ------------------------------------------------------------
        # Activates the MeasureOpeningTool in the 3D viewport.
        # Passes the active cill height plus the effective bottom frame thickness
        # so the tool can respect asymmetric frameless-bottom configurations.
        def self.na_handle_measure_opening
            DebugTools.na_debug_method("DialogManager.na_handle_measure_opening")
            
            # Get cill height and bottom frame thickness from current config (mirrors UI state)
            cill_height_mm = 50  # Default fallback
            frame_bottom_thickness_mm = 50  # Default fallback
            if @config && @config["windowConfiguration"]
                window_config = @config["windowConfiguration"]
                uniform_frame_thickness_mm = window_config.key?("frame_thickness_mm") ? window_config["frame_thickness_mm"].to_f : 50.0
                use_advanced_frame_controls = window_config["advanced_frame_controls"] == true
                frame_bottom_thickness_mm = if use_advanced_frame_controls && window_config.key?("frame_bottom_thickness_mm")
                    window_config["frame_bottom_thickness_mm"].to_f
                else
                    uniform_frame_thickness_mm
                end

                if window_config["has_cill"] != false && frame_bottom_thickness_mm > 0
                    cill_height_mm = window_config["cill_height_mm"] || 50
                else
                    cill_height_mm = 0
                end
            end
            
            # Activate the shared two-point measurement tool. Now sourced from
            # 07__PluginCore__MeasurmentToolsModules so the same module can serve
            # both the Window and Interior Door tools without circular requires.
            measure_tool = Na__MeasurementTools::Na__TwoPointOpeningTool.new(
                self, cill_height_mm, frame_bottom_thickness_mm
            )
            Sketchup.active_model.select_tool(measure_tool)
            
            DebugTools.na_debug_success("Measure Opening tool activated (cill_height=#{cill_height_mm}mm, frame_bottom_thickness=#{frame_bottom_thickness_mm}mm)")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Send Measurement to Dialog
        # ------------------------------------------------------------
        # Called by the MeasureOpeningTool after the user completes the
        # two-click measurement. Sends width, adjusted height and the
        # Point A origin (in inches) to the HTML dialog. Caches the
        # Point A so the next na_handle_create_window can use it as the
        # priority insertion origin (one-shot).
        # @param width_mm    [Numeric]              Measured opening width in millimetres
        # @param height_mm   [Numeric]              Adjusted opening height in millimetres
        # @param origin_x_in [Numeric, nil]         Point A X in inches (optional, backward-compatible)
        # @param origin_y_in [Numeric, nil]         Point A Y in inches
        # @param origin_z_in [Numeric, nil]         Point A Z in inches
        def self.na_send_measurement_to_dialog(width_mm, height_mm, origin_x_in = nil, origin_y_in = nil, origin_z_in = nil)
            has_origin = origin_x_in && origin_y_in && origin_z_in

            if has_origin
                @last_measure_origin = Geom::Point3d.new(origin_x_in, origin_y_in, origin_z_in)
                DebugTools.na_debug_info("Cached measure origin Point A (inches): #{@last_measure_origin.inspect}")
            end

            return unless @dialog && @dialog.visible?

            # v0.11.7 - Every numeric argument MUST be cast to Float before
            # interpolation, otherwise SketchUp's Length#to_s injects a
            # literal `"` or `'` into the JS source and the parser breaks
            # before `na_receiveMeasurement` can run. See the Length-Safe
            # execute_script Convention in the Architecture doc.
            width_f  = Float(width_mm)
            height_f = Float(height_mm)
            DebugTools.na_debug_info(
                "Sending measurement to dialog: W=#{width_f}mm, H=#{height_f}mm"
            )

            if has_origin
                ax = Float(origin_x_in.to_f)                                  # <-- Length#to_f -> raw inch Float
                ay = Float(origin_y_in.to_f)
                az = Float(origin_z_in.to_f)
                @dialog.execute_script(
                    "window.na_receiveMeasurement(#{width_f}, #{height_f}, #{ax}, #{ay}, #{az});"
                )
            else
                @dialog.execute_script(
                    "window.na_receiveMeasurement(#{width_f}, #{height_f});"
                )
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Consume the Cached Measurement Origin (One-Shot)
        # ------------------------------------------------------------
        # Returns the most-recently captured Point A as a Geom::Point3d
        # (in inches) and clears the cache. Used by GeometryEngine to
        # place a freshly-created window at the measurement's Point A.
        # If no measurement has been taken since the last create, this
        # returns nil and the caller falls back to the placement tool.
        def self.na_consume_pending_measurement_origin
            origin = @last_measure_origin
            @last_measure_origin = nil
            origin
        end
        # ---------------------------------------------------------------

        # FUNCTION | Send Measure Cancelled to Dialog
        # ------------------------------------------------------------
        # Called by the MeasureOpeningTool when the user cancels (ESC key).
        # Notifies the HTML dialog to remove the active button styling.
        def self.na_send_measure_cancelled_to_dialog
            return unless @dialog && @dialog.visible?
            
            DebugTools.na_debug_info("Sending measure cancelled notification to dialog")
            @dialog.execute_script("window.na_measureCancelled();")
        end
        # ---------------------------------------------------------------

        # MODULE CONSTANTS | Sub-Tool Folders That Must Reload With the Parent
        # ------------------------------------------------------------
        # Reload globs only the parent folder by default. Any sub-tool whose
        # Ruby modules need to be re-evaluated by the in-dialog Reload
        # Scripts button must be listed here. Adding a new sub-tool is a
        # one-line change and keeps reload logic free of `**/*.rb`
        # wildcards (which would also pull in third-party shared deps).
        NA_RELOAD_SUBFOLDERS = [
            "Na__InteriorDoorConfigurator__".freeze,                              # <-- Interior Door Configurator
            "65__DevTools".freeze,                                                # <-- Tool-agnostic JSON exporters
            "07__PluginCore__MeasurmentToolsModules".freeze                       # <-- Shared two/three-point measure tools
        ].freeze
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Collect All Ruby Files That Should Reload Together
        # ------------------------------------------------------------
        # Returns a stable, de-duplicated, sorted list of `.rb` paths covering
        # the plugin root plus every sub-tool folder declared in
        # NA_RELOAD_SUBFOLDERS. Missing sub-folders are silently skipped so
        # an optional sub-tool (e.g. dev-tools removed for shipping) does
        # not break reload.
        # @param plugin_root_path [String] Absolute path to the plugin module root
        # @return [Array<String>] Absolute paths of every .rb file to reload
        def self.na_collect_rb_files_for_reload(plugin_root_path)
            collected = Dir.glob(File.join(plugin_root_path, "*.rb"))           # <-- Top-level files (window tool)

            NA_RELOAD_SUBFOLDERS.each do |sub_folder|
                sub_path = File.join(plugin_root_path, sub_folder)              # Resolve absolute sub-folder path
                next unless File.directory?(sub_path)                           # Tolerate missing optional folders
                collected.concat(Dir.glob(File.join(sub_path, "*.rb")))         # Append every .rb directly inside
            end

            collected.uniq.sort                                                 # Stable, predictable reload order
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Format a Reloaded File Path for Console Output
        # ------------------------------------------------------------
        # Returns the file path relative to the plugin root when possible,
        # otherwise the bare basename. Keeps the reload log compact while
        # still distinguishing files in sub-tool folders from top-level files.
        # @param file_path [String]        Absolute path of the reloaded file
        # @param plugin_root_path [String] Plugin module root path
        # @return [String] Display label for console output
        def self.na_format_reload_path(file_path, plugin_root_path)
            normalized_root = plugin_root_path.tr("\\", "/")                    # Normalise Windows separators
            normalized_file = file_path.tr("\\", "/")                           # Normalise Windows separators
            if normalized_file.start_with?(normalized_root + "/")
                normalized_file.sub(normalized_root + "/", "")                  # Strip plugin-root prefix
            else
                File.basename(file_path)                                        # Fallback to basename
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Reload Scripts (Developer Feature)
        # ------------------------------------------------------------
        def self.na_reload_scripts(plugin_root_path)
            DebugTools.na_debug_method("DialogManager.na_reload_scripts")
            
            puts "\n" + "=" * 60
            puts "NA WINDOW CONFIGURATOR - RELOADING SCRIPTS"
            puts "=" * 60
            
            rb_reload_count = 0
            js_reload_count = 0
            error_count = 0
            
            # Collect Ruby files from the parent folder AND every sub-tool
            # folder declared in NA_RELOAD_SUBFOLDERS. Without this,
            # files in Na__InteriorDoorConfigurator__/ and 65__DevTools/
            # would never re-load and would silently run stale code after
            # the user pressed Reload Scripts.
            puts "\nReloading Ruby (.rb) files:"
            puts "  [ROOT]      #{plugin_root_path}"
            NA_RELOAD_SUBFOLDERS.each do |sub_folder|
                sub_path = File.join(plugin_root_path, sub_folder)
                marker   = File.directory?(sub_path) ? "[SUBFOLDER]" : "[MISSING] "
                puts "  #{marker} #{sub_folder}/"
            end

            rb_files = na_collect_rb_files_for_reload(plugin_root_path)

            rb_files.each do |file|
                begin
                    load file
                    rel_label = na_format_reload_path(file, plugin_root_path)   # Compact display path
                    puts "  [OK] #{rel_label}"
                    rb_reload_count += 1
                rescue => e
                    rel_label = na_format_reload_path(file, plugin_root_path)
                    puts "  [ERROR] #{rel_label}: #{e.message}"
                    error_count += 1
                end
            end
            
            # JavaScript files to reload (in dependency order)
            # All viewport modules now live in 06__PluginCore__HtmlDialogue__ViewportModules/
            # and are listed here using folder-relative paths so File.exist? on the
            # plugin root resolves them correctly. Order matters: SvgHelpers must
            # load before any *Generator that calls into it.
            js_files = [
                # Configuration (no dependencies)
                "Na__WindowConfiguratorTool__Ui__Config__.js",
                # UI Layer
                "Na__WindowConfiguratorTool__Ui__Controls__.js",
                "Na__WindowConfiguratorTool__Ui__Events__.js",
                # Shared Viewport Layer (folder-scoped)
                "06__PluginCore__HtmlDialogue__ViewportModules/Na__Viewport__SvgHelpers__.js",
                "06__PluginCore__HtmlDialogue__ViewportModules/Na__Viewport__Validation__.js",
                "06__PluginCore__HtmlDialogue__ViewportModules/Na__Viewport__WindowSvgGenerator__.js",
                "06__PluginCore__HtmlDialogue__ViewportModules/Na__Viewport__Controls__.js",
                "06__PluginCore__HtmlDialogue__ViewportModules/Na__Viewport__Instance__.js",
                "06__PluginCore__HtmlDialogue__ViewportModules/Na__Viewport__DoorPlanGenerator__.js",
                "06__PluginCore__HtmlDialogue__ViewportModules/Na__Viewport__DoorElevationGenerator__.js",
                # Export Layer
                "Na__WindowConfiguratorTool__Export__Dxf__.js",
                # Main Orchestrator
                "Na__WindowConfiguratorTool__UiLogic__.js",
                # Bridge
                "Na__WindowConfiguratorTool__UiEventToRubyApiBridge__.js"
            ]
            
            puts "\nReloading JavaScript (.js) files:"
            js_files.each do |filename|
                filepath = File.join(plugin_root_path, filename)
                if File.exist?(filepath)
                    puts "  [OK] #{filename}"
                    js_reload_count += 1
                else
                    puts "  [WARNING] #{filename} not found"
                end
            end
            
            total_count = rb_reload_count + js_reload_count
            
            puts "\n" + "-" * 60
            puts "Reload complete:"
            puts "  Ruby files:       #{rb_reload_count}"
            puts "  JavaScript files: #{js_reload_count}"
            puts "  Total reloaded:   #{total_count}"
            puts "  Errors:           #{error_count}"
            puts "=" * 60 + "\n"
            
            # Refresh UI
            UI.refresh_inspectors if UI.respond_to?(:refresh_inspectors)
            
            # Reopen dialog if it was visible (this reloads the JS files in the browser)
            if @dialog && @dialog.visible?
                @dialog.close
                # Note: Caller (Main module) should call na_show_dialog again
            end
            
            # Send status to dialog UI
            if error_count > 0
                na_send_status_to_dialog(nil, "warning", "Reloaded #{total_count} files (#{rb_reload_count} Ruby, #{js_reload_count} JS) with #{error_count} errors")
            else
                na_send_status_to_dialog(nil, "success", "Successfully reloaded #{total_count} files (#{rb_reload_count} Ruby, #{js_reload_count} JS)")
            end
            
            return {reload_dialog: true}  # Signal to caller to re-show dialog
        end
        # ---------------------------------------------------------------


        # FUNCTION | Settings Tab Handler - Run the 2D-Only ValeSpec-Style Exporter
        # ------------------------------------------------------------
        # Resolves Na__DevTools defensively so a missing dev-tools folder
        # does not crash the dialog.
        def self.na_handle_settings_export_2d
            DebugTools.na_debug_method("DialogManager.na_handle_settings_export_2d")

            unless defined?(::Na__DevTools)
                msg = "Dev tools not loaded - check 65__DevTools/ folder."
                puts "\n!! Settings : #{msg}"
                na_send_status_to_dialog(nil, "warning", msg)
                return
            end

            ::Na__DevTools.na_run_export_2d
            na_send_status_to_dialog(nil, "info", "2D exporter finished - see Ruby Console for output")
        rescue StandardError => e
            DebugTools.na_debug_error("Settings 2D export failed", e)
            na_send_status_to_dialog(nil, "warning", "2D export failed : #{e.message}")
        end
        # ---------------------------------------------------------------


        # FUNCTION | Settings Tab Handler - Run the Unified 2D + 3D Asset Exporter
        # ------------------------------------------------------------
        # Resolves Na__DevTools defensively so a missing dev-tools folder
        # does not crash the dialog.
        def self.na_handle_settings_export_3d
            DebugTools.na_debug_method("DialogManager.na_handle_settings_export_3d")

            unless defined?(::Na__DevTools)
                msg = "Dev tools not loaded - check 65__DevTools/ folder."
                puts "\n!! Settings : #{msg}"
                na_send_status_to_dialog(nil, "warning", msg)
                return
            end

            ::Na__DevTools.na_run_export_3d
            na_send_status_to_dialog(nil, "info", "3D exporter finished - see Ruby Console for output")
        rescue StandardError => e
            DebugTools.na_debug_error("Settings 3D export failed", e)
            na_send_status_to_dialog(nil, "warning", "3D export failed : #{e.message}")
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Communication
# -----------------------------------------------------------------------------

        # FUNCTION | Send Configuration to Dialog
        # ------------------------------------------------------------
        def self.na_send_config_to_dialog(default_config)
            return unless @dialog && @dialog.visible?
            
            config_json = JSON.generate(@config || default_config)
            escaped_json = config_json.gsub("'", "\\\\'")
            
            @dialog.execute_script("window.na_setInitialConfig('#{escaped_json}');")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Send Status Message to Dialog
        # ------------------------------------------------------------
        def self.na_send_status_to_dialog(default_config, status_type, message)
            return unless @dialog && @dialog.visible?
            
            escaped_message = message.gsub("'", "\\\\'")
            @dialog.execute_script("window.na_showStatus('#{status_type}', '#{escaped_message}');")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Placement Complete (called by PlacementTool on successful placement)
        # ------------------------------------------------------------
        def self.na_placement_complete
            @current_placement_tool = nil
            return unless @dialog && @dialog.visible?
            @dialog.execute_script("window.na_setPlacementActive(false);")
            na_send_status_to_dialog(nil, "success", "Window placed")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Placement Cancelled (called by PlacementTool on ESC / abort)
        # ------------------------------------------------------------
        def self.na_placement_cancelled
            @current_placement_tool = nil
            return unless @dialog && @dialog.visible?
            @dialog.execute_script("window.na_setPlacementActive(false);")
            na_send_status_to_dialog(nil, "info", "Placement cancelled")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Load Window into Dialog
        # ------------------------------------------------------------
        # Uses direct instance-based lookup to avoid redundant model-wide search.
        # Always updates the dialog — even if data load fails — to prevent
        # stale config from a previously selected window remaining visible.
        def self.na_load_window_into_dialog(instance, window_id, default_config)
            @window_component = instance
            @config = DataSerializer.na_load_window_data_from_instance(instance, window_id)
            
            if @config
                na_send_config_to_dialog(default_config)
                na_send_status_to_dialog(default_config, "info", "Loaded window: #{window_id}")
            else
                DebugTools.na_debug_warn("Could not load config for window #{window_id}")
                @config = Marshal.load(Marshal.dump(default_config))
                na_send_config_to_dialog(default_config)
                na_send_status_to_dialog(default_config, "warning", "Window #{window_id} selected but no saved config found")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Clear Window from Dialog (when deselected)
        # ------------------------------------------------------------
        def self.na_clear_window_from_dialog(default_config)
            @window_component = nil
            @config = Marshal.load(Marshal.dump(default_config))
            
            return unless @dialog && @dialog.visible?
            @dialog.execute_script("window.na_clearCurrentWindow();")
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Fallback HTML
# -----------------------------------------------------------------------------

        # FUNCTION | Create Fallback HTML (if file not found)
        # ------------------------------------------------------------
        def self.na_create_fallback_html
            <<~HTML
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <title>Na Window Configurator</title>
                <style>
                    body { font-family: Arial, sans-serif; padding: 20px; background: #2d2d2d; color: #fff; }
                    .error { color: #ff6b6b; background: #3d2d2d; padding: 15px; border-radius: 5px; }
                    button { background: #4a90d9; color: white; border: none; padding: 10px 20px; cursor: pointer; margin: 5px; }
                    button:hover { background: #5a9fe9; }
                    .na-fallback-reload { width: 28px; height: 28px; padding: 0; margin: 5px; font-size: 16px; line-height: 1;
                      display: inline-flex; align-items: center; justify-content: center; background: none; border: 1px solid #555;
                      color: #aaa; border-radius: 4px; cursor: pointer; }
                    .na-fallback-reload:hover { background: #444; color: #fff; border-color: #888; }
                </style>
            </head>
            <body>
                <h2>Na Window Configurator</h2>
                <div class="error">
                    <strong>Error:</strong> HTML layout file not found.<br>
                    Please ensure Na__WindowConfiguratorTool__UiLayout__.html exists in the plugin folder.
                </div>
                <br>
                <button type="button" class="na-fallback-reload" onclick="sketchup.na_reloadScripts()" title="Reload Scripts">&#x21bb;</button>
                
                <script>
                    window.na_setInitialConfig = function(json) { console.log('Config received'); };
                    window.na_clearCurrentWindow = function() { console.log('Window cleared'); };
                    window.na_showStatus = function(type, msg) { console.log(type + ': ' + msg); };
                </script>
            </body>
            </html>
            HTML
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__DialogManager
end # module Na__WindowConfiguratorTool

# =============================================================================
# END OF FILE
# =============================================================================
