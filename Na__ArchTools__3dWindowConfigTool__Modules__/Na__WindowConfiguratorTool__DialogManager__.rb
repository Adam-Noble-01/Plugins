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
require_relative 'Na__WindowConfiguratorTool__MeasureOpeningTool__'
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
            @dialog = UI::HtmlDialog.new(
                dialog_title: "Na Window Configurator",
                preferences_key: "Na__WindowConfiguratorTool",
                scrollable: true,
                resizable: true,
                width: 525,
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
                
                # Create the window geometry (delegate to GeometryEngine)
                @window_component = GeometryEngine.na_create_window_geometry(config["windowConfiguration"], window_id)
                
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
                    
                    # Activate placement tool
                    placement_tool = Na__WindowPlacementTool.new(@window_component)
                    Sketchup.active_model.select_tool(placement_tool)
                    
                    DebugTools.na_debug_success("Created window #{window_id}")
                    fuse_msg = (config["windowConfiguration"] && config["windowConfiguration"]["fuse_parts"] == true) ? " (fused)" : ""
                    na_send_status_to_dialog(nil, "success", "Window created: #{window_id}#{fuse_msg}")
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
        # Passes the current cill_height_mm from config so the tool can
        # deduct it from the measured Z height.
        def self.na_handle_measure_opening
            DebugTools.na_debug_method("DialogManager.na_handle_measure_opening")
            
            # Get cill height and frame thickness from current config (mirrors UI state)
            cill_height_mm = 50  # Default fallback
            frame_thickness_mm = 50  # Default fallback
            if @config && @config["windowConfiguration"]
                cill_height_mm = @config["windowConfiguration"]["cill_height_mm"] || 50
                frame_thickness_mm = @config["windowConfiguration"]["frame_thickness_mm"] || 50
            end
            
            # Activate the Measure Opening Tool (tool handles frameless logic internally)
            measure_tool = Na__MeasureOpeningTool.new(self, cill_height_mm, frame_thickness_mm)
            Sketchup.active_model.select_tool(measure_tool)
            
            DebugTools.na_debug_success("Measure Opening tool activated (cill_height=#{cill_height_mm}mm, frame_thickness=#{frame_thickness_mm}mm)")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Send Measurement to Dialog
        # ------------------------------------------------------------
        # Called by the MeasureOpeningTool after the user completes the
        # two-click measurement. Sends width and adjusted height to the
        # HTML dialog to update the configurator sliders.
        # @param width_mm [Numeric] Measured opening width in millimeters
        # @param height_mm [Numeric] Adjusted opening height in millimeters
        def self.na_send_measurement_to_dialog(width_mm, height_mm)
            return unless @dialog && @dialog.visible?
            
            DebugTools.na_debug_info("Sending measurement to dialog: W=#{width_mm}mm, H=#{height_mm}mm")
            @dialog.execute_script("window.na_receiveMeasurement(#{width_mm}, #{height_mm});")
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
            
            # Reload Ruby files
            puts "\nReloading Ruby (.rb) files:"
            rb_files = Dir.glob(File.join(plugin_root_path, "*.rb"))
            
            rb_files.each do |file|
                begin
                    load file
                    puts "  [OK] #{File.basename(file)}"
                    rb_reload_count += 1
                rescue => e
                    puts "  [ERROR] #{File.basename(file)}: #{e.message}"
                    error_count += 1
                end
            end
            
            # JavaScript files to reload (in dependency order)
            js_files = [
                # Configuration (no dependencies)
                "Na__WindowConfiguratorTool__Ui__Config__.js",
                # UI Layer
                "Na__WindowConfiguratorTool__Ui__Controls__.js",
                "Na__WindowConfiguratorTool__Ui__Events__.js",
                # Viewport Layer
                "Na__WindowConfiguratorTool__Viewport__Validation__.js",
                "Na__WindowConfiguratorTool__Viewport__SvgGenerator__.js",
                "Na__WindowConfiguratorTool__Viewport__Controls__.js",
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
                </style>
            </head>
            <body>
                <h2>Na Window Configurator</h2>
                <div class="error">
                    <strong>Error:</strong> HTML layout file not found.<br>
                    Please ensure Na__WindowConfiguratorTool__UiLayout__.html exists in the plugin folder.
                </div>
                <br>
                <button onclick="sketchup.na_reloadScripts()">Reload Scripts</button>
                
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
