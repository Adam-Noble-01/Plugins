# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - MAIN ORCHESTRATOR
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__Main__.rb
# NAMESPACE  : Na__WindowConfiguratorTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Main orchestrator for the 3D Window Configurator Tool
# CREATED    : 2026
#
# DESCRIPTION:
# - This is the main entry point for the Window Configurator Tool
# - Manages UI::HtmlDialog for the configuration interface
# - Handles geometry creation and updates
# - Implements crosshair placement tool for positioning windows
# - Provides selection observer for detecting existing window components
# - Includes developer reload feature for rapid iteration
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
# - Distinguishes Noble Architecture code from third-party libraries
#
# ADAPTED FROM:
# - EXAMPLE__ValeDesignSuite_Tools_WindowPanelConfigurator.rb
# - EXAMPLE__Na__SimpleWindowMaker__Main__.rb
# - Na__GenerateStructuralElement__BIM__Main__.rb
#
# =============================================================================

require 'sketchup.rb'
require 'json'

# Load dependent modules
require_relative 'Na__WindowConfiguratorTool__DebugTools__'
require_relative 'Na__WindowConfiguratorTool__DataSerializer__'
require_relative 'Na__WindowConfiguratorTool__GeometryHelpers__'
require_relative 'Na__WindowConfiguratorTool__DxfExporterLogic__'

module Na__WindowConfiguratorTool

# =============================================================================
# REGION | Module References
# =============================================================================

    DebugTools = Na__WindowConfiguratorTool::Na__DebugTools
    DataSerializer = Na__WindowConfiguratorTool::Na__DataSerializer
    GeometryHelpers = Na__WindowConfiguratorTool::Na__GeometryHelpers
    DxfExporter = Na__WindowConfiguratorTool::Na__DxfExporter

# endregion ===================================================================

# =============================================================================
# REGION | Module Constants
# =============================================================================

    # CONSTANTS | Unit Conversion
    # ------------------------------------------------------------
    NA_MM_TO_INCH = 1.0 / 25.4                                      # Millimeter to inch conversion
    
    # CONSTANTS | File Paths
    # ------------------------------------------------------------
    NA_PLUGIN_ROOT = File.dirname(__FILE__).freeze                  # Plugin root directory
    NA_HTML_FILE   = File.join(NA_PLUGIN_ROOT, 'Na__WindowConfiguratorTool__UiLayout__.html').freeze
    
    # CONSTANTS | Dictionary Names (reference from DataSerializer)
    # ------------------------------------------------------------
    NA_WINDOW_DICT_NAME = "Na__WindowConfigurator_Config".freeze    # Legacy fallback dictionary
    
    # CONSTANTS | Default Window Dimensions (in mm)
    # ------------------------------------------------------------
    NA_DEFAULT_WIDTH           = 900                                # Default window width
    NA_DEFAULT_HEIGHT          = 1200                               # Default window height
    NA_DEFAULT_FRAME_THICKNESS = 50                                 # Default frame thickness
    NA_DEFAULT_CASEMENT_WIDTH  = 65                                 # Default casement profile width
    NA_DEFAULT_GLASS_THICKNESS = 24                                 # Default glass unit thickness
    NA_DEFAULT_GLAZE_BAR_WIDTH = 25                                 # Default glaze bar width (was 30)
    NA_DEFAULT_CILL_DEPTH      = 50                                 # Default cill projection
    NA_DEFAULT_CILL_HEIGHT     = 30                                 # Default cill height
    NA_DEFAULT_MULLION_COUNT   = 0                                  # Default number of mullions
    NA_DEFAULT_MULLION_WIDTH   = 40                                 # Default mullion profile width (was 65)
    
    # CONSTANTS | Material Colors
    # ------------------------------------------------------------
    NA_FRAME_COLOR = Sketchup::Color.new(210, 180, 140)             # Tan/wood color for frame
    NA_GLASS_COLOR = Sketchup::Color.new(200, 220, 240, 100)        # Light blue transparent for glass
    NA_CILL_COLOR  = Sketchup::Color.new(180, 160, 140)             # Darker tan for cill

# endregion ===================================================================

# =============================================================================
# REGION | Default Configuration JSON
# =============================================================================

    NA_DEFAULT_CONFIG_JSON = <<~JSON_STRING
    {
        "windowMetadata": [
            {
                "WindowUniqueId": null,
                "WindowName": "New Window",
                "WindowNotes": "Created with Na Window Configurator",
                "CreatedDate": null,
                "LastModified": null
            }
        ],
        "windowComponents": [],
        "windowConfiguration": {
            "width_mm": 900,
            "height_mm": 1200,
            "frame_thickness_mm": 50,
            "casement_width_mm": 65,
            "casement_sizes_individual": false,
            "casement_top_rail_mm": 65,
            "casement_bottom_rail_mm": 65,
            "casement_left_stile_mm": 65,
            "casement_right_stile_mm": 65,
            "twin_casements": false,
            "mullion_width_mm": 40,
            "mullions": 0,
            "glass_thickness_mm": 24,
            "horizontal_glaze_bars": 0,
            "vertical_glaze_bars": 0,
            "glaze_bar_width_mm": 25,
            "has_cill": true,
            "cill_depth_mm": 50,
            "cill_height_mm": 30,
            "frame_color": "#D2B48C",
            "show_dimensions": true,
            "show_casements": true
        }
    }
    JSON_STRING

    NA_DEFAULT_CONFIG = JSON.parse(NA_DEFAULT_CONFIG_JSON)

# endregion ===================================================================

# =============================================================================
# REGION | Module Variables
# =============================================================================

    @na_dialog = nil                                                # HtmlDialog instance
    @na_window_component = nil                                      # Current window component being edited
    @na_config = nil                                                # Current configuration hash
    @na_selection_observer = nil                                    # Selection observer instance

# endregion ===================================================================

# =============================================================================
# REGION | Initialization and Entry Points
# =============================================================================

    # FUNCTION | Initialize the Tool
    # ------------------------------------------------------------
    def self.na_init
        DebugTools.na_debug_method("na_init")
        
        # Attach selection observer
        @na_selection_observer = Na__WindowSelectionObserver.new
        Sketchup.active_model.selection.add_observer(@na_selection_observer)
        
        # Show the dialog
        na_show_dialog
        
        DebugTools.na_debug_success("Window Configurator Tool initialized")
    end
    # ---------------------------------------------------------------

    # FUNCTION | Show the Configuration Dialog
    # ------------------------------------------------------------
    def self.na_show_dialog
        DebugTools.na_debug_method("na_show_dialog")
        
        # Close existing dialog if open
        if @na_dialog && @na_dialog.visible?
            @na_dialog.close
        end
        
        # Create new dialog
        @na_dialog = UI::HtmlDialog.new(
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
        if File.exist?(NA_HTML_FILE)
            @na_dialog.set_file(NA_HTML_FILE)
            DebugTools.na_debug_ui("Loaded HTML from: #{NA_HTML_FILE}")
        else
            DebugTools.na_debug_error("HTML file not found: #{NA_HTML_FILE}")
            # Set fallback HTML
            @na_dialog.set_html(na_create_fallback_html)
        end
        
        # Setup callbacks
        na_setup_dialog_callbacks
        
        # Show dialog
        @na_dialog.show
        
        # Initialize with default or selected window config
        na_check_initial_selection
    end
    # ---------------------------------------------------------------

    # FUNCTION | Check Initial Selection for Existing Window
    # ------------------------------------------------------------
    def self.na_check_initial_selection
        selection = Sketchup.active_model.selection
        
        if selection.length == 1 && selection.first.is_a?(Sketchup::ComponentInstance)
            instance = selection.first
            window_id = DataSerializer.na_get_window_id_from_instance(instance)
            
            if window_id
                DebugTools.na_debug_window("Found existing window in selection: #{window_id}")
                na_load_window_into_dialog(instance, window_id)
                return
            end
        end
        
        # No existing window selected, use default config
        @na_config = Marshal.load(Marshal.dump(NA_DEFAULT_CONFIG)) # Deep clone
        DebugTools.na_debug_window("Using default configuration")
    end
    # ---------------------------------------------------------------

# endregion ===================================================================

# =============================================================================
# REGION | Dialog Callbacks Setup
# =============================================================================

    # FUNCTION | Setup Dialog Action Callbacks
    # ------------------------------------------------------------
    def self.na_setup_dialog_callbacks
        DebugTools.na_debug_method("na_setup_dialog_callbacks")
        
        # Callback: Create New Window
        @na_dialog.add_action_callback("na_createWindow") do |action_context, config_json|
            na_handle_create_window(config_json)
        end
        
        # Callback: Update Existing Window
        @na_dialog.add_action_callback("na_updateWindow") do |action_context, config_json|
            na_handle_update_window(config_json)
        end
        
        # Callback: Reload Scripts (Developer Feature)
        @na_dialog.add_action_callback("na_reloadScripts") do |action_context|
            na_reload_scripts
        end
        
        # Callback: Export DXF (receives config JSON, generates DXF in Ruby)
        @na_dialog.add_action_callback("na_exportDxf") do |action_context, config_json|
            na_handle_export_dxf(config_json)
        end
        
        # Callback: Request Current Config (for UI sync)
        @na_dialog.add_action_callback("na_requestConfig") do |action_context|
            na_send_config_to_dialog
        end
        
        # Callback: Log from JavaScript
        @na_dialog.add_action_callback("na_jsLog") do |action_context, message|
            DebugTools.na_debug_ui("[JS] #{message}")
        end
        
        # Callback: Live Update (real-time geometry update)
        @na_dialog.add_action_callback("na_liveUpdate") do |action_context, config_json|
            na_handle_live_update(config_json)
        end
        
        DebugTools.na_debug_success("Dialog callbacks configured")
    end
    # ---------------------------------------------------------------

# endregion ===================================================================

# =============================================================================
# REGION | Callback Handlers
# =============================================================================

    # FUNCTION | Handle Create Window Callback
    # ------------------------------------------------------------
    def self.na_handle_create_window(config_json)
        DebugTools.na_debug_method("na_handle_create_window")
        
        begin
            config = JSON.parse(config_json)
            @na_config = config
            
            model = Sketchup.active_model
            model.start_operation("Create Window", true)
            
            # Generate new window ID
            window_id = DataSerializer.na_generate_next_window_id
            
            # Update metadata with ID
            if @na_config["windowMetadata"] && @na_config["windowMetadata"][0]
                @na_config["windowMetadata"][0]["WindowUniqueId"] = window_id
                @na_config["windowMetadata"][0]["CreatedDate"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
                @na_config["windowMetadata"][0]["LastModified"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
            end
            
            # Create the window geometry (pass the pre-generated window_id)
            @na_window_component = na_create_window_geometry(config["windowConfiguration"], window_id)
            
            if @na_window_component && @na_window_component.valid?
                # Set window ID on the instance
                DataSerializer.na_set_window_id_on_instance(@na_window_component, window_id)
                
                # Save config to component dictionary
                DataSerializer.na_save_window_data(window_id, @na_config)
                
                model.commit_operation
                
                # Activate placement tool (pass has_cill for Z offset)
                has_cill = config["windowConfiguration"]["has_cill"] != false
                placement_tool = Na__WindowPlacementTool.new(@na_window_component, has_cill)
                Sketchup.active_model.select_tool(placement_tool)
                
                DebugTools.na_debug_success("Created window #{window_id}")
                na_send_status_to_dialog("success", "Window created: #{window_id}")
            else
                model.abort_operation
                DebugTools.na_debug_error("Failed to create window geometry")
                na_send_status_to_dialog("error", "Failed to create window geometry")
            end
            
        rescue => e
            model.abort_operation if model
            DebugTools.na_debug_error("Error creating window", e)
            na_send_status_to_dialog("error", "Error: #{e.message}")
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Handle Update Window Callback
    # ------------------------------------------------------------
    def self.na_handle_update_window(config_json)
        DebugTools.na_debug_method("na_handle_update_window")
        
        begin
            config = JSON.parse(config_json)
            @na_config = config
            
            unless @na_window_component && @na_window_component.valid?
                DebugTools.na_debug_warn("No valid window component to update")
                na_send_status_to_dialog("warning", "No window selected to update")
                return
            end
            
            window_id = DataSerializer.na_get_window_id_from_instance(@na_window_component)
            unless window_id
                DebugTools.na_debug_warn("Selected component has no WindowID")
                na_send_status_to_dialog("warning", "Selected component is not a configurable window")
                return
            end
            
            model = Sketchup.active_model
            model.start_operation("Update Window", true)
            
            # Update timestamp
            if @na_config["windowMetadata"] && @na_config["windowMetadata"][0]
                @na_config["windowMetadata"][0]["LastModified"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
            end
            
            # Regenerate geometry
            na_update_window_geometry(@na_window_component, config["windowConfiguration"])
            
            # Save updated config
            DataSerializer.na_save_window_data(window_id, @na_config)
            
            model.commit_operation
            
            DebugTools.na_debug_success("Updated window #{window_id}")
            na_send_status_to_dialog("success", "Window updated: #{window_id}")
            
        rescue => e
            model.abort_operation if model
            DebugTools.na_debug_error("Error updating window", e)
            na_send_status_to_dialog("error", "Error: #{e.message}")
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Handle DXF Export Callback
    # ------------------------------------------------------------
    # Receives configuration JSON from JavaScript, generates DXF using
    # the dedicated DxfExporter module, and saves to user-selected location.
    def self.na_handle_export_dxf(config_json)
        DebugTools.na_debug_method("na_handle_export_dxf")
        
        begin
            # Parse configuration from JSON
            config = JSON.parse(config_json)
            DebugTools.na_debug_info("Generating DXF from config")
            
            # Generate DXF content using the dedicated exporter module
            dxf_content = DxfExporter.na_generate_dxf(config)
            
            unless dxf_content
                DebugTools.na_debug_error("DXF generation returned nil")
                na_send_status_to_dialog("error", "Failed to generate DXF content")
                return
            end
            
            # Prompt for save location
            path = UI.savepanel("Export DXF", "", "window_export.dxf")
            
            if path
                # Ensure .dxf extension
                path = path + ".dxf" unless path.downcase.end_with?(".dxf")
                
                File.write(path, dxf_content)
                DebugTools.na_debug_success("DXF exported to: #{path}")
                na_send_status_to_dialog("success", "DXF exported: #{File.basename(path)}")
            else
                DebugTools.na_debug_info("DXF export cancelled by user")
            end
            
        rescue JSON::ParserError => e
            DebugTools.na_debug_error("Invalid JSON in DXF export", e)
            na_send_status_to_dialog("error", "Invalid configuration data")
        rescue => e
            DebugTools.na_debug_error("Error exporting DXF", e)
            na_send_status_to_dialog("error", "Export failed: #{e.message}")
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Handle Live Update Callback (Real-time geometry update)
    # ------------------------------------------------------------
    # Called from JavaScript when Live Mode is enabled and config changes.
    # Uses debouncing to prevent overwhelming SketchUp with rapid updates.
    def self.na_handle_live_update(config_json)
        DebugTools.na_debug_method("na_handle_live_update")
        
        begin
            config = JSON.parse(config_json)
            @na_config = config
            
            # Find the target window component to update
            target_instance = na_find_live_update_target
            
            unless target_instance
                DebugTools.na_debug_warn("Live update: No window selected. Select a window or create one first.")
                na_send_status_to_dialog("warning", "Select a window to use Live Mode")
                return
            end
            
            # Get window ID from the target
            window_id = DataSerializer.na_get_window_id_from_instance(target_instance)
            
            unless window_id
                DebugTools.na_debug_warn("Live update: Selected component is not a Na Window")
                na_send_status_to_dialog("warning", "Selected item is not a Na Window")
                return
            end
            
            # Perform the live update
            model = Sketchup.active_model
            model.start_operation("Live Update Window", true, false, true)  # Transparent operation
            
            # Regenerate geometry
            na_update_window_geometry(target_instance, config["windowConfiguration"])
            
            # Save updated config
            DataSerializer.na_save_window_data(window_id, @na_config)
            
            model.commit_operation
            
            # Force viewport refresh
            model.active_view.invalidate
            
            DebugTools.na_debug_success("Live update applied to #{window_id}")
            
        rescue => e
            DebugTools.na_debug_error("Error in live update", e)
            na_send_status_to_dialog("error", "Live update failed: #{e.message}")
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Find Target for Live Update
    # ------------------------------------------------------------
    # Returns the window component to update, checking:
    # 1. Stored @na_window_component (from previous selection/creation)
    # 2. Current model selection (if it's a Na Window)
    def self.na_find_live_update_target
        # First, check if we have a valid stored component
        if @na_window_component && @na_window_component.valid?
            return @na_window_component
        end
        
        # Second, check the current selection
        model = Sketchup.active_model
        selection = model.selection
        
        return nil if selection.empty?
        
        # Look for a Na Window component in selection
        selection.each do |entity|
            if entity.is_a?(Sketchup::ComponentInstance)
                window_id = DataSerializer.na_get_window_id_from_instance(entity)
                if window_id
                    # Found a valid Na Window - store it and return
                    @na_window_component = entity
                    return entity
                end
            end
        end
        
        nil
    end
    # ---------------------------------------------------------------

# endregion ===================================================================

# =============================================================================
# REGION | Dialog Communication
# =============================================================================

    # FUNCTION | Send Configuration to Dialog
    # ------------------------------------------------------------
    def self.na_send_config_to_dialog
        return unless @na_dialog && @na_dialog.visible?
        
        config_json = JSON.generate(@na_config || NA_DEFAULT_CONFIG)
        escaped_json = config_json.gsub("'", "\\\\'")
        
        @na_dialog.execute_script("window.na_setInitialConfig('#{escaped_json}');")
    end
    # ---------------------------------------------------------------

    # FUNCTION | Send Status Message to Dialog
    # ------------------------------------------------------------
    def self.na_send_status_to_dialog(status_type, message)
        return unless @na_dialog && @na_dialog.visible?
        
        escaped_message = message.gsub("'", "\\\\'")
        @na_dialog.execute_script("window.na_showStatus('#{status_type}', '#{escaped_message}');")
    end
    # ---------------------------------------------------------------

    # FUNCTION | Load Window into Dialog
    # ------------------------------------------------------------
    def self.na_load_window_into_dialog(instance, window_id)
        @na_window_component = instance
        @na_config = DataSerializer.na_load_window_data(window_id)
        
        if @na_config
            na_send_config_to_dialog
            na_send_status_to_dialog("info", "Loaded window: #{window_id}")
        else
            DebugTools.na_debug_warn("Could not load config for window #{window_id}")
            @na_config = Marshal.load(Marshal.dump(NA_DEFAULT_CONFIG))
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Clear Window from Dialog (when deselected)
    # ------------------------------------------------------------
    def self.na_clear_window_from_dialog
        @na_window_component = nil
        @na_config = Marshal.load(Marshal.dump(NA_DEFAULT_CONFIG))
        
        return unless @na_dialog && @na_dialog.visible?
        @na_dialog.execute_script("window.na_clearCurrentWindow();")
    end
    # ---------------------------------------------------------------

# endregion ===================================================================

# =============================================================================
# REGION | Geometry Creation Engine
# =============================================================================

    # FUNCTION | Create Window Geometry
    # ------------------------------------------------------------
    # @param config [Hash] Window configuration
    # @param window_id [String] Pre-generated window ID (e.g., "PNL001")
    # @return [Sketchup::ComponentInstance, nil] The created component instance
    def self.na_create_window_geometry(config, window_id = nil)
        DebugTools.na_debug_method("na_create_window_geometry")
        
        model = Sketchup.active_model
        entities = model.active_entities
        
        # Generate window ID if not provided
        window_id ||= DataSerializer.na_generate_next_window_id
        
        begin
            # Extract configuration values
            width            = (config["width_mm"] || NA_DEFAULT_WIDTH).to_f * NA_MM_TO_INCH
            height           = (config["height_mm"] || NA_DEFAULT_HEIGHT).to_f * NA_MM_TO_INCH
            frame_thickness  = (config["frame_thickness_mm"] || NA_DEFAULT_FRAME_THICKNESS).to_f * NA_MM_TO_INCH
            casement_width   = (config["casement_width_mm"] || NA_DEFAULT_CASEMENT_WIDTH).to_f * NA_MM_TO_INCH
            show_casements   = config["show_casements"] != false
            twin_casements   = config["twin_casements"] == true
            num_mullions     = (config["mullions"] || NA_DEFAULT_MULLION_COUNT).to_i
            mullion_width    = (config["mullion_width_mm"] || NA_DEFAULT_MULLION_WIDTH).to_f * NA_MM_TO_INCH
            glass_thickness  = (config["glass_thickness_mm"] || NA_DEFAULT_GLASS_THICKNESS).to_f * NA_MM_TO_INCH
            h_bars           = (config["horizontal_glaze_bars"] || 0).to_i
            v_bars           = (config["vertical_glaze_bars"] || 0).to_i
            bar_width        = (config["glaze_bar_width_mm"] || NA_DEFAULT_GLAZE_BAR_WIDTH).to_f * NA_MM_TO_INCH
            has_cill         = config["has_cill"] != false
            cill_depth       = (config["cill_depth_mm"] || NA_DEFAULT_CILL_DEPTH).to_f * NA_MM_TO_INCH
            cill_height      = (config["cill_height_mm"] || NA_DEFAULT_CILL_HEIGHT).to_f * NA_MM_TO_INCH
            
            # Individual casement sizes (when casement_sizes_individual is true)
            use_individual_sizes = config["casement_sizes_individual"] == true
            cas_top_rail     = use_individual_sizes ? (config["casement_top_rail_mm"] || casement_width.to_mm).to_f * NA_MM_TO_INCH : casement_width
            cas_bottom_rail  = use_individual_sizes ? (config["casement_bottom_rail_mm"] || casement_width.to_mm).to_f * NA_MM_TO_INCH : casement_width
            cas_left_stile   = use_individual_sizes ? (config["casement_left_stile_mm"] || casement_width.to_mm).to_f * NA_MM_TO_INCH : casement_width
            cas_right_stile  = use_individual_sizes ? (config["casement_right_stile_mm"] || casement_width.to_mm).to_f * NA_MM_TO_INCH : casement_width
            
            # Frame depth (Y direction) - 76mm standard
            frame_depth = 76.0 * NA_MM_TO_INCH
            
            # Calculate openings
            num_openings = num_mullions + 1
            inner_width = width - (2 * frame_thickness)
            inner_height = height - (2 * frame_thickness)
            total_mullion_width = num_mullions * mullion_width
            available_width = inner_width - total_mullion_width
            opening_width = available_width / num_openings
            
            DebugTools.na_debug_geometry("Creating window: #{width.to_mm.round}mm x #{height.to_mm.round}mm, #{num_openings} opening(s), twin_casements: #{twin_casements}")
            
            # Create component definition first
            component_name = "Na_Window_#{window_id}"
            definitions = model.definitions
            component_def = definitions.add(component_name)
            window_entities = component_def.entities
            
            # Create materials once
            frame_material = na_get_or_create_material("Na_Frame_Wood", NA_FRAME_COLOR)
            glass_material = na_get_or_create_material("Na_Glass", NA_GLASS_COLOR)
            cill_material = na_get_or_create_material("Na_Cill_Stone", NA_CILL_COLOR)
            
            # Create outer frame
            na_create_frame_geometry(window_entities, width, height, frame_thickness, frame_depth, frame_material)
            
            # Create mullions
            (1..num_mullions).each do |m|
                mullion_x = frame_thickness + (m * opening_width) + ((m - 1) * mullion_width)
                na_create_mullion_geometry(window_entities, m, mullion_x, inner_height, mullion_width, frame_depth, frame_thickness, frame_material)
            end
            
            # Create each opening with casement (if enabled), glass, and glaze bars
            (0...num_openings).each do |i|
                opening_x = frame_thickness + (i * (opening_width + mullion_width))
                opening_z = frame_thickness
                casement_depth = frame_depth * 0.7
                
                if twin_casements
                    # TWIN CASEMENTS: Two casements per opening, meeting at center
                    half_width = opening_width / 2.0
                    
                    if show_casements
                        # Left casement of the pair (index i*2)
                        na_create_casement_geometry_individual(window_entities, i * 2, half_width, inner_height, 
                            cas_top_rail, cas_bottom_rail, cas_left_stile, cas_right_stile,
                            casement_depth, opening_x, opening_z, frame_material)
                        
                        # Right casement of the pair (index i*2+1)
                        na_create_casement_geometry_individual(window_entities, i * 2 + 1, half_width, inner_height,
                            cas_top_rail, cas_bottom_rail, cas_left_stile, cas_right_stile,
                            casement_depth, opening_x + half_width, opening_z, frame_material)
                        
                        # Glass inside left casement
                        glass_offset_x_left = opening_x + cas_left_stile
                        glass_offset_z = opening_z + cas_bottom_rail
                        glass_w_left = half_width - cas_left_stile - cas_right_stile
                        glass_h = inner_height - cas_top_rail - cas_bottom_rail
                        na_create_glass_geometry(window_entities, i * 2, glass_w_left, glass_h, glass_thickness, glass_offset_x_left, glass_offset_z, frame_depth, glass_material)
                        
                        # Glass inside right casement
                        glass_offset_x_right = opening_x + half_width + cas_left_stile
                        glass_w_right = half_width - cas_left_stile - cas_right_stile
                        na_create_glass_geometry(window_entities, i * 2 + 1, glass_w_right, glass_h, glass_thickness, glass_offset_x_right, glass_offset_z, frame_depth, glass_material)
                        
                        # Glaze bars for left casement
                        if h_bars > 0 || v_bars > 0
                            na_create_glazebar_geometry(window_entities, i * 2, glass_w_left, glass_h, h_bars, v_bars, bar_width, glass_thickness, glass_offset_x_left, glass_offset_z, frame_depth, frame_material)
                            na_create_glazebar_geometry(window_entities, i * 2 + 1, glass_w_right, glass_h, h_bars, v_bars, bar_width, glass_thickness, glass_offset_x_right, glass_offset_z, frame_depth, frame_material)
                        end
                    else
                        # Direct glazed twin - two glass panes
                        na_create_glass_geometry(window_entities, i * 2, half_width, inner_height, glass_thickness, opening_x, opening_z, frame_depth, glass_material)
                        na_create_glass_geometry(window_entities, i * 2 + 1, half_width, inner_height, glass_thickness, opening_x + half_width, opening_z, frame_depth, glass_material)
                    end
                else
                    # SINGLE CASEMENT: One casement per opening
                    if show_casements
                        # Casement frame for this opening with individual sizes
                        na_create_casement_geometry_individual(window_entities, i, opening_width, inner_height,
                            cas_top_rail, cas_bottom_rail, cas_left_stile, cas_right_stile,
                            casement_depth, opening_x, opening_z, frame_material)
                        
                        # Glass inside casement
                        glass_offset_x = opening_x + cas_left_stile
                        glass_offset_z = opening_z + cas_bottom_rail
                        glass_width = opening_width - cas_left_stile - cas_right_stile
                        glass_height = inner_height - cas_top_rail - cas_bottom_rail
                    else
                        # Direct glazed - glass sits directly in opening
                        glass_offset_x = opening_x
                        glass_offset_z = opening_z
                        glass_width = opening_width
                        glass_height = inner_height
                    end
                    
                    # Create glass pane
                    na_create_glass_geometry(window_entities, i, glass_width, glass_height, glass_thickness, glass_offset_x, glass_offset_z, frame_depth, glass_material)
                    
                    # Create glaze bars for this opening
                    if h_bars > 0 || v_bars > 0
                        na_create_glazebar_geometry(window_entities, i, glass_width, glass_height, h_bars, v_bars, bar_width, glass_thickness, glass_offset_x, glass_offset_z, frame_depth, frame_material)
                    end
                end
            end
            
            # Create cill
            if has_cill
                na_create_cill_geometry(window_entities, width, cill_depth, cill_height, frame_depth, cill_material)
            end
            
            # Add component instance at origin
            instance = entities.add_instance(component_def, IDENTITY)
            
            DebugTools.na_debug_geometry("Created window component: #{component_name}")
            return instance
            
        rescue => e
            DebugTools.na_debug_error("Error in na_create_window_geometry", e)
            return nil
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Update Window Geometry
    # ------------------------------------------------------------
    def self.na_update_window_geometry(instance, config)
        DebugTools.na_debug_method("na_update_window_geometry")
        
        return unless instance && instance.valid?
        
        begin
            # Store current transformation
            current_transform = instance.transformation
            
            # Clear existing geometry in the definition
            definition = instance.definition
            definition.entities.clear!
            
            # Extract configuration values
            width            = (config["width_mm"] || NA_DEFAULT_WIDTH).to_f * NA_MM_TO_INCH
            height           = (config["height_mm"] || NA_DEFAULT_HEIGHT).to_f * NA_MM_TO_INCH
            frame_thickness  = (config["frame_thickness_mm"] || NA_DEFAULT_FRAME_THICKNESS).to_f * NA_MM_TO_INCH
            casement_width   = (config["casement_width_mm"] || NA_DEFAULT_CASEMENT_WIDTH).to_f * NA_MM_TO_INCH
            show_casements   = config["show_casements"] != false
            twin_casements   = config["twin_casements"] == true
            num_mullions     = (config["mullions"] || NA_DEFAULT_MULLION_COUNT).to_i
            mullion_width    = (config["mullion_width_mm"] || NA_DEFAULT_MULLION_WIDTH).to_f * NA_MM_TO_INCH
            glass_thickness  = (config["glass_thickness_mm"] || NA_DEFAULT_GLASS_THICKNESS).to_f * NA_MM_TO_INCH
            h_bars           = (config["horizontal_glaze_bars"] || 0).to_i
            v_bars           = (config["vertical_glaze_bars"] || 0).to_i
            bar_width        = (config["glaze_bar_width_mm"] || NA_DEFAULT_GLAZE_BAR_WIDTH).to_f * NA_MM_TO_INCH
            has_cill         = config["has_cill"] != false
            cill_depth       = (config["cill_depth_mm"] || NA_DEFAULT_CILL_DEPTH).to_f * NA_MM_TO_INCH
            cill_height      = (config["cill_height_mm"] || NA_DEFAULT_CILL_HEIGHT).to_f * NA_MM_TO_INCH
            frame_depth      = 76.0 * NA_MM_TO_INCH
            
            # Individual casement sizes (when casement_sizes_individual is true)
            use_individual_sizes = config["casement_sizes_individual"] == true
            cas_top_rail     = use_individual_sizes ? (config["casement_top_rail_mm"] || casement_width.to_mm).to_f * NA_MM_TO_INCH : casement_width
            cas_bottom_rail  = use_individual_sizes ? (config["casement_bottom_rail_mm"] || casement_width.to_mm).to_f * NA_MM_TO_INCH : casement_width
            cas_left_stile   = use_individual_sizes ? (config["casement_left_stile_mm"] || casement_width.to_mm).to_f * NA_MM_TO_INCH : casement_width
            cas_right_stile  = use_individual_sizes ? (config["casement_right_stile_mm"] || casement_width.to_mm).to_f * NA_MM_TO_INCH : casement_width
            
            # Calculate openings
            num_openings = num_mullions + 1
            inner_width = width - (2 * frame_thickness)
            inner_height = height - (2 * frame_thickness)
            total_mullion_width = num_mullions * mullion_width
            available_width = inner_width - total_mullion_width
            opening_width = available_width / num_openings
            
            window_entities = definition.entities
            
            # Get or create materials
            frame_material = na_get_or_create_material("Na_Frame_Wood", NA_FRAME_COLOR)
            glass_material = na_get_or_create_material("Na_Glass", NA_GLASS_COLOR)
            cill_material = na_get_or_create_material("Na_Cill_Stone", NA_CILL_COLOR)
            
            # Create outer frame
            na_create_frame_geometry(window_entities, width, height, frame_thickness, frame_depth, frame_material)
            
            # Create mullions
            (1..num_mullions).each do |m|
                mullion_x = frame_thickness + (m * opening_width) + ((m - 1) * mullion_width)
                na_create_mullion_geometry(window_entities, m, mullion_x, inner_height, mullion_width, frame_depth, frame_thickness, frame_material)
            end
            
            # Create each opening with casement (if enabled), glass, and glaze bars
            (0...num_openings).each do |i|
                opening_x = frame_thickness + (i * (opening_width + mullion_width))
                opening_z = frame_thickness
                casement_depth = frame_depth * 0.7
                
                if twin_casements
                    # TWIN CASEMENTS: Two casements per opening, meeting at center
                    half_width = opening_width / 2.0
                    
                    if show_casements
                        # Left casement of the pair
                        na_create_casement_geometry_individual(window_entities, i * 2, half_width, inner_height,
                            cas_top_rail, cas_bottom_rail, cas_left_stile, cas_right_stile,
                            casement_depth, opening_x, opening_z, frame_material)
                        
                        # Right casement of the pair
                        na_create_casement_geometry_individual(window_entities, i * 2 + 1, half_width, inner_height,
                            cas_top_rail, cas_bottom_rail, cas_left_stile, cas_right_stile,
                            casement_depth, opening_x + half_width, opening_z, frame_material)
                        
                        # Glass inside left casement
                        glass_offset_x_left = opening_x + cas_left_stile
                        glass_offset_z = opening_z + cas_bottom_rail
                        glass_w_left = half_width - cas_left_stile - cas_right_stile
                        glass_h = inner_height - cas_top_rail - cas_bottom_rail
                        na_create_glass_geometry(window_entities, i * 2, glass_w_left, glass_h, glass_thickness, glass_offset_x_left, glass_offset_z, frame_depth, glass_material)
                        
                        # Glass inside right casement
                        glass_offset_x_right = opening_x + half_width + cas_left_stile
                        glass_w_right = half_width - cas_left_stile - cas_right_stile
                        na_create_glass_geometry(window_entities, i * 2 + 1, glass_w_right, glass_h, glass_thickness, glass_offset_x_right, glass_offset_z, frame_depth, glass_material)
                        
                        # Glaze bars for both casements
                        if h_bars > 0 || v_bars > 0
                            na_create_glazebar_geometry(window_entities, i * 2, glass_w_left, glass_h, h_bars, v_bars, bar_width, glass_thickness, glass_offset_x_left, glass_offset_z, frame_depth, frame_material)
                            na_create_glazebar_geometry(window_entities, i * 2 + 1, glass_w_right, glass_h, h_bars, v_bars, bar_width, glass_thickness, glass_offset_x_right, glass_offset_z, frame_depth, frame_material)
                        end
                    else
                        # Direct glazed twin - two glass panes
                        na_create_glass_geometry(window_entities, i * 2, half_width, inner_height, glass_thickness, opening_x, opening_z, frame_depth, glass_material)
                        na_create_glass_geometry(window_entities, i * 2 + 1, half_width, inner_height, glass_thickness, opening_x + half_width, opening_z, frame_depth, glass_material)
                    end
                else
                    # SINGLE CASEMENT: One casement per opening
                    if show_casements
                        # Casement frame for this opening with individual sizes
                        na_create_casement_geometry_individual(window_entities, i, opening_width, inner_height,
                            cas_top_rail, cas_bottom_rail, cas_left_stile, cas_right_stile,
                            casement_depth, opening_x, opening_z, frame_material)
                        
                        # Glass inside casement
                        glass_offset_x = opening_x + cas_left_stile
                        glass_offset_z = opening_z + cas_bottom_rail
                        glass_w = opening_width - cas_left_stile - cas_right_stile
                        glass_h = inner_height - cas_top_rail - cas_bottom_rail
                    else
                        # Direct glazed - glass sits directly in opening
                        glass_offset_x = opening_x
                        glass_offset_z = opening_z
                        glass_w = opening_width
                        glass_h = inner_height
                    end
                    
                    # Create glass pane
                    na_create_glass_geometry(window_entities, i, glass_w, glass_h, glass_thickness, glass_offset_x, glass_offset_z, frame_depth, glass_material)
                    
                    # Create glaze bars for this opening
                    if h_bars > 0 || v_bars > 0
                        na_create_glazebar_geometry(window_entities, i, glass_w, glass_h, h_bars, v_bars, bar_width, glass_thickness, glass_offset_x, glass_offset_z, frame_depth, frame_material)
                    end
                end
            end
            
            # Create cill
            if has_cill
                na_create_cill_geometry(window_entities, width, cill_depth, cill_height, frame_depth, cill_material)
            end
            
            DebugTools.na_debug_geometry("Updated window geometry (twin_casements: #{twin_casements})")
            
        rescue => e
            DebugTools.na_debug_error("Error in na_update_window_geometry", e)
        end
    end
    # ---------------------------------------------------------------

# endregion ===================================================================

# =============================================================================
# REGION | Geometry Helper Functions
# =============================================================================

    # FUNCTION | Get or Create Material
    # ------------------------------------------------------------
    def self.na_get_or_create_material(name, color)
        materials = Sketchup.active_model.materials
        material = materials[name]
        
        unless material
            material = materials.add(name)
            material.color = color
            material.alpha = color.alpha / 255.0 if color.alpha < 255
        end
        
        return material
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create Frame Geometry (Outer Frame)
    # ------------------------------------------------------------
    # JOINERY CONVENTION: Stiles (vertical) span full height, 
    # Rails (horizontal) are inset between stiles.
    # This matches real window construction.
    # Each piece is created as a separate named group for easy identification.
    def self.na_create_frame_geometry(entities, width, height, thickness, depth, material)
        DebugTools.na_debug_geometry("Creating outer frame: #{width.to_mm.round}x#{height.to_mm.round}mm")
        
        # Left stile - FULL HEIGHT (Z = 0 to height)
        GeometryHelpers.na_create_frame_stile(entities, "Left", 0, 0, 0, thickness, depth, height, material)
        
        # Right stile - FULL HEIGHT (Z = 0 to height) at X = width - thickness
        GeometryHelpers.na_create_frame_stile(entities, "Right", width - thickness, 0, 0, thickness, depth, height, material)
        
        # Bottom rail - INSET between stiles (X = thickness to width - thickness), at Z = 0
        GeometryHelpers.na_create_frame_rail(entities, "Bottom", thickness, 0, 0, width - (2 * thickness), depth, thickness, material)
        
        # Top rail - INSET between stiles (X = thickness to width - thickness), at Z = height - thickness
        GeometryHelpers.na_create_frame_rail(entities, "Top", thickness, 0, height - thickness, width - (2 * thickness), depth, thickness, material)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create Mullion Geometry (Vertical Divider)
    # ------------------------------------------------------------
    # @param entities [Sketchup::Entities] Target entities collection
    # @param mullion_index [Integer] Index of this mullion (1-based)
    # @param x_pos [Float] X position for the mullion
    # @param inner_height [Float] Height of the inner window area (between top/bottom rails)
    # @param mullion_width [Float] Width of the mullion
    # @param depth [Float] Depth of the mullion (Y direction)
    # @param frame_thickness [Float] Thickness of the outer frame (for Z offset)
    # @param material [Sketchup::Material] Material to apply
    def self.na_create_mullion_geometry(entities, mullion_index, x_pos, inner_height, mullion_width, depth, frame_thickness, material)
        DebugTools.na_debug_geometry("Creating mullion #{mullion_index} at X=#{x_pos.to_mm.round}mm")
        
        # Mullion spans from bottom frame rail to top frame rail
        GeometryHelpers.na_create_mullion(entities, mullion_index, x_pos, 0, frame_thickness, mullion_width, depth, inner_height, material)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create Casement Geometry (Legacy - uniform thickness)
    # ------------------------------------------------------------
    # JOINERY CONVENTION: Stiles (vertical) span full height, 
    # Rails (horizontal) are inset between stiles.
    # This matches real window construction.
    # Each piece is created as a separate named group for easy identification.
    # @param opening_index [Integer] Index of the opening (0-based)
    def self.na_create_casement_geometry(entities, opening_index, cas_width, cas_height, thickness, depth, offset_x, offset_z, material)
        DebugTools.na_debug_geometry("Creating casement #{opening_index} at offset (#{offset_x.to_mm.round}, #{offset_z.to_mm.round})")
        
        y_offset = 6.mm  # Slightly inset from outer frame in Y direction
        
        # Left stile - FULL HEIGHT of casement
        GeometryHelpers.na_create_casement_stile(entities, opening_index, "Left", offset_x, y_offset, offset_z, thickness, depth, cas_height, material)
        
        # Right stile - FULL HEIGHT of casement
        GeometryHelpers.na_create_casement_stile(entities, opening_index, "Right", offset_x + cas_width - thickness, y_offset, offset_z, thickness, depth, cas_height, material)
        
        # Bottom rail - INSET between stiles
        GeometryHelpers.na_create_casement_rail(entities, opening_index, "Bottom", offset_x + thickness, y_offset, offset_z, cas_width - (2 * thickness), depth, thickness, material)
        
        # Top rail - INSET between stiles
        GeometryHelpers.na_create_casement_rail(entities, opening_index, "Top", offset_x + thickness, y_offset, offset_z + cas_height - thickness, cas_width - (2 * thickness), depth, thickness, material)
    end
    # ---------------------------------------------------------------
    
    # FUNCTION | Create Casement Geometry with Individual Sizes
    # ------------------------------------------------------------
    # JOINERY CONVENTION: Stiles (vertical) span full height, 
    # Rails (horizontal) are inset between stiles.
    # This version supports different widths for each rail and stile.
    # @param opening_index [Integer] Index of the opening (0-based)
    # @param cas_width [Float] Total casement width
    # @param cas_height [Float] Total casement height
    # @param top_rail [Float] Top rail thickness
    # @param bottom_rail [Float] Bottom rail thickness
    # @param left_stile [Float] Left stile thickness
    # @param right_stile [Float] Right stile thickness
    # @param depth [Float] Casement depth (Y direction)
    # @param offset_x [Float] X offset from frame origin
    # @param offset_z [Float] Z offset from frame origin
    # @param material [Sketchup::Material] Material to apply
    def self.na_create_casement_geometry_individual(entities, opening_index, cas_width, cas_height, top_rail, bottom_rail, left_stile, right_stile, depth, offset_x, offset_z, material)
        DebugTools.na_debug_geometry("Creating casement #{opening_index} with individual sizes at offset (#{offset_x.to_mm.round}, #{offset_z.to_mm.round})")
        DebugTools.na_debug_geometry("  - Top Rail: #{top_rail.to_mm.round}mm, Bottom Rail: #{bottom_rail.to_mm.round}mm")
        DebugTools.na_debug_geometry("  - Left Stile: #{left_stile.to_mm.round}mm, Right Stile: #{right_stile.to_mm.round}mm")
        
        y_offset = 6.mm  # Slightly inset from outer frame in Y direction
        
        # Left stile - FULL HEIGHT of casement
        GeometryHelpers.na_create_casement_stile(entities, opening_index, "Left", offset_x, y_offset, offset_z, left_stile, depth, cas_height, material)
        
        # Right stile - FULL HEIGHT of casement
        GeometryHelpers.na_create_casement_stile(entities, opening_index, "Right", offset_x + cas_width - right_stile, y_offset, offset_z, right_stile, depth, cas_height, material)
        
        # Bottom rail - INSET between stiles (width excludes both stiles)
        rail_width = cas_width - left_stile - right_stile
        GeometryHelpers.na_create_casement_rail(entities, opening_index, "Bottom", offset_x + left_stile, y_offset, offset_z, rail_width, depth, bottom_rail, material)
        
        # Top rail - INSET between stiles (positioned at top minus rail height)
        GeometryHelpers.na_create_casement_rail(entities, opening_index, "Top", offset_x + left_stile, y_offset, offset_z + cas_height - top_rail, rail_width, depth, top_rail, material)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create Glass Geometry
    # ------------------------------------------------------------
    # @param opening_index [Integer] Index of the opening (0-based)
    def self.na_create_glass_geometry(entities, opening_index, glass_width, glass_height, thickness, offset_x, offset_z, frame_depth, material)
        DebugTools.na_debug_geometry("Creating glass pane #{opening_index}: #{glass_width.to_mm.round}x#{glass_height.to_mm.round}mm")
        
        # Center glass in frame depth
        y_offset = (frame_depth - thickness) / 2.0
        
        GeometryHelpers.na_create_glass_pane(entities, opening_index, offset_x, y_offset, offset_z, glass_width, thickness, glass_height, material)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create Glaze Bar Geometry
    # ------------------------------------------------------------
    # @param opening_index [Integer] Index of the opening (0-based)
    def self.na_create_glazebar_geometry(entities, opening_index, glass_width, glass_height, h_bars, v_bars, bar_width, glass_thickness, offset_x, offset_z, frame_depth, material)
        DebugTools.na_debug_geometry("Creating glaze bars for opening #{opening_index}: #{h_bars}H x #{v_bars}V")
        
        # Position bars at glass depth, slightly proud
        y_offset = (frame_depth - glass_thickness) / 2.0 - 3.mm
        bar_depth = glass_thickness + 6.mm
        
        # Horizontal bars
        if h_bars > 0
            section_height = glass_height / (h_bars + 1)
            (1..h_bars).each do |i|
                bar_z = offset_z + (section_height * i) - (bar_width / 2)
                GeometryHelpers.na_create_glaze_bar_horizontal(entities, opening_index, i, offset_x, y_offset, bar_z, glass_width, bar_depth, bar_width, material)
            end
        end
        
        # Vertical bars
        if v_bars > 0
            section_width = glass_width / (v_bars + 1)
            (1..v_bars).each do |i|
                bar_x = offset_x + (section_width * i) - (bar_width / 2)
                GeometryHelpers.na_create_glaze_bar_vertical(entities, opening_index, i, bar_x, y_offset, offset_z, bar_width, bar_depth, glass_height, material)
            end
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create Cill Geometry
    # ------------------------------------------------------------
    def self.na_create_cill_geometry(entities, width, cill_projection, cill_height, frame_depth, material)
        DebugTools.na_debug_geometry("Creating cill: #{width.to_mm.round}mm wide, #{cill_projection.to_mm.round}mm projection")
        
        # Cill sits below window (negative Z) and projects forward (negative Y)
        cill_x = 0
        cill_y = -cill_projection
        cill_z = -cill_height
        cill_depth = cill_projection + frame_depth  # Projects front and extends to back of frame
        
        GeometryHelpers.na_create_cill(entities, cill_x, cill_y, cill_z, width, cill_depth, cill_height, material)
    end
    # ---------------------------------------------------------------

# endregion ===================================================================

# =============================================================================
# REGION | Developer Reload Feature
# =============================================================================

    # FUNCTION | Reload Scripts
    # ------------------------------------------------------------
    def self.na_reload_scripts
        DebugTools.na_debug_method("na_reload_scripts")
        
        puts "\n" + "=" * 60
        puts "NA WINDOW CONFIGURATOR - RELOADING SCRIPTS"
        puts "=" * 60
        
        reload_count = 0
        error_count = 0
        
        # Get all .rb files in the plugin directory
        rb_files = Dir.glob(File.join(NA_PLUGIN_ROOT, "*.rb"))
        
        rb_files.each do |file|
            begin
                load file
                puts "  [OK] Loaded: #{File.basename(file)}"
                reload_count += 1
            rescue => e
                puts "  [ERROR] #{File.basename(file)}: #{e.message}"
                error_count += 1
            end
        end
        
        puts "-" * 60
        puts "Reload complete: #{reload_count} files loaded, #{error_count} errors"
        puts "=" * 60 + "\n"
        
        # Refresh UI
        UI.refresh_inspectors if UI.respond_to?(:refresh_inspectors)
        
        # Reopen dialog if it was visible
        if @na_dialog && @na_dialog.visible?
            @na_dialog.close
            na_show_dialog
        end
        
        na_send_status_to_dialog("success", "Scripts reloaded: #{reload_count} files")
    end
    # ---------------------------------------------------------------

# endregion ===================================================================

# =============================================================================
# REGION | Fallback HTML
# =============================================================================

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

# endregion ===================================================================

# =============================================================================
# REGION | Selection Observer Class
# =============================================================================

    class Na__WindowSelectionObserver < Sketchup::SelectionObserver
        
        # Called when selection changes
        def onSelectionBulkChange(selection)
            Na__WindowConfiguratorTool::DebugTools.na_debug_observer("Selection changed: #{selection.length} entities")
            
            if selection.length == 1 && selection.first.is_a?(Sketchup::ComponentInstance)
                instance = selection.first
                window_id = Na__WindowConfiguratorTool::DataSerializer.na_get_window_id_from_instance(instance)
                
                if window_id
                    Na__WindowConfiguratorTool::DebugTools.na_debug_observer("Selected window: #{window_id}")
                    Na__WindowConfiguratorTool.na_load_window_into_dialog(instance, window_id)
                end
            elsif selection.empty?
                Na__WindowConfiguratorTool.na_clear_window_from_dialog
            end
        end
        
        # Called when selection is cleared
        def onSelectionCleared(selection)
            Na__WindowConfiguratorTool::DebugTools.na_debug_observer("Selection cleared")
            Na__WindowConfiguratorTool.na_clear_window_from_dialog
        end
    end

# endregion ===================================================================

# =============================================================================
# REGION | Placement Tool Class
# =============================================================================

    class Na__WindowPlacementTool
        
        # CONSTANTS
        CONSTRAIN_MODIFIER_KEY = COPY_MODIFIER_KEY  # Shift key for rotation toggle
        Z_AXIS = Geom::Vector3d.new(0, 0, 1)
        CROSSHAIR_SIZE = 300.mm
        CILL_Z_OFFSET = 50.mm  # Z offset when cill is enabled
        
        def initialize(instance, has_cill = false)
            @instance = instance
            @has_cill = has_cill
            @ip = Sketchup::InputPoint.new
            @cursor_pos = nil
            @crosshair_size = CROSSHAIR_SIZE
            @rotated = false
            @original_transform = instance.transformation.clone
            @last_position = instance.bounds.min
            @z_offset = has_cill ? CILL_Z_OFFSET : 0
            
            Na__WindowConfiguratorTool::DebugTools.na_debug_placement("Placement tool initialized (has_cill: #{has_cill}, z_offset: #{@z_offset.to_mm.round}mm)")
        end
        
        def activate
            Na__WindowConfiguratorTool::DebugTools.na_debug_placement("Placement tool activated")
            na_update_status_text
            Sketchup.active_model.active_view.invalidate
        end
        
        def deactivate(view)
            Na__WindowConfiguratorTool::DebugTools.na_debug_placement("Placement tool deactivated")
            view.invalidate
        end
        
        def onMouseMove(flags, x, y, view)
            @ip.pick(view, x, y)
            return unless @ip.valid?
            
            # Snap cursor position to 5mm grid
            @cursor_pos = na_round_to_grid(@ip.position)
            
            if @instance && @instance.valid?
                # Apply Z offset for cill if enabled
                target_pos = Geom::Point3d.new(@cursor_pos.x, @cursor_pos.y, @cursor_pos.z + @z_offset)
                
                # Calculate movement delta from current instance position to target
                current_min = @instance.bounds.min
                delta = target_pos - current_min
                
                # Apply translation to move instance to target position
                translation = Geom::Transformation.new(delta)
                @instance.transform!(translation)
                
                # Update last position
                @last_position = target_pos
            end
            
            # Update status text with current position
            na_update_status_text
            
            view.invalidate
        end
        
        def onKeyDown(key, repeat, flags, view)
            if key == CONSTRAIN_MODIFIER_KEY && repeat == 1
                na_toggle_rotation
                na_update_status_text
                view.invalidate
            end
            false  # Return false to not block VCB
        end
        
        def onLButtonDown(flags, x, y, view)
            @ip.pick(view, x, y)
            return unless @ip.valid?
            
            # Snap final position to 5mm grid
            cursor_pt = na_round_to_grid(@ip.position)
            
            # Apply Z offset for cill if enabled
            final_pt = Geom::Point3d.new(cursor_pt.x, cursor_pt.y, cursor_pt.z + @z_offset)
            
            # Move instance to final position if cursor moved since last move
            if @instance && @instance.valid?
                current_min = @instance.bounds.min
                delta = final_pt - current_min
                if delta.length > 0.001
                    translation = Geom::Transformation.new(delta)
                    @instance.transform!(translation)
                end
            end
            
            Na__WindowConfiguratorTool::DebugTools.na_debug_placement("Window placed at: #{final_pt} (cursor: #{cursor_pt}, z_offset: #{@z_offset.to_mm.round}mm)")
            
            # Commit the placement
            Sketchup.active_model.selection.clear
            Sketchup.active_model.selection.add(@instance) if @instance && @instance.valid?
            
            # Deactivate tool
            Sketchup.active_model.select_tool(nil)
        end
        
        def onCancel(reason, view)
            Na__WindowConfiguratorTool::DebugTools.na_debug_placement("Placement cancelled")
            
            # Delete the instance if cancelled
            if @instance && @instance.valid?
                @instance.erase!
            end
            
            view.invalidate
        end
        
        private
        
        # Toggle 90-degree rotation around Z axis
        def na_toggle_rotation
            return unless @instance && @instance.valid?
            
            # Get center of instance for rotation pivot
            center = @instance.bounds.center
            
            # Calculate rotation angle (toggle between +90 and -90)
            angle = @rotated ? -90.degrees : 90.degrees
            
            # Create and apply rotation transformation
            rotation = Geom::Transformation.rotation(center, Z_AXIS, angle)
            @instance.transform!(rotation)
            
            # Toggle rotation state
            @rotated = !@rotated
            
            Na__WindowConfiguratorTool::DebugTools.na_debug_placement("Rotation toggled: #{@rotated ? '90°' : '0°'}")
        end
        
        # Update status bar text
        def na_update_status_text
            if @cursor_pos
                # Show coordinates in mm (snapped to 5mm grid)
                x_mm = (@cursor_pos.x * 25.4).round
                y_mm = (@cursor_pos.y * 25.4).round
                z_mm = (@cursor_pos.z * 25.4).round
                rotation_angle = @rotated ? 90 : 0
                
                status = "Click to place window at X:#{x_mm}mm Y:#{y_mm}mm Z:#{z_mm}mm"
                status += " | Press SHIFT to rotate 90° [Current: #{rotation_angle}°] | ESC to cancel"
                Sketchup.status_text = status
            else
                Sketchup.status_text = "Move cursor to position window | Press SHIFT to rotate 90° | ESC to cancel"
            end
        end
        
        public
        
        def draw(view)
            return unless @cursor_pos
            
            # Draw 3D crosshair
            view.line_width = 2
            
            # X axis (red)
            view.drawing_color = Sketchup::Color.new(255, 0, 0)
            view.draw_line(@cursor_pos.offset(X_AXIS, -@crosshair_size), @cursor_pos.offset(X_AXIS, @crosshair_size))
            
            # Y axis (green)
            view.drawing_color = Sketchup::Color.new(0, 255, 0)
            view.draw_line(@cursor_pos.offset(Y_AXIS, -@crosshair_size), @cursor_pos.offset(Y_AXIS, @crosshair_size))
            
            # Z axis (blue)
            view.drawing_color = Sketchup::Color.new(0, 0, 255)
            view.draw_line(@cursor_pos, @cursor_pos.offset(Z_AXIS, @crosshair_size))
            
            # Draw rotation indicator if rotated
            if @rotated
                view.drawing_color = Sketchup::Color.new(255, 165, 0)  # Orange
                view.line_width = 3
                # Draw small arc to indicate rotation
                arc_radius = @crosshair_size * 0.3
                segments = 12
                arc_points = []
                (0..segments).each do |i|
                    angle = (i.to_f / segments) * 90.degrees
                    pt = Geom::Point3d.new(
                        @cursor_pos.x + arc_radius * Math.cos(angle),
                        @cursor_pos.y + arc_radius * Math.sin(angle),
                        @cursor_pos.z
                    )
                    arc_points << pt
                end
                view.draw_polyline(arc_points)
            end
        end
        
        # Helper: Round to 5mm grid
        def na_round_to_grid(point)
            grid = 5.mm
            Geom::Point3d.new(
                (point.x / grid).round * grid,
                (point.y / grid).round * grid,
                (point.z / grid).round * grid
            )
        end
    end

# endregion ===================================================================

end # module Na__WindowConfiguratorTool

# =============================================================================
# REGION | SketchUp Menu Registration
# =============================================================================

# NOTE: Menu and toolbar registration is handled by the loader script
#       (Na__WindowConfiguratorTool__Loader.rb in the root Plugins folder)
#
#       This main file contains only the tool logic and is loaded by the loader.

# =============================================================================
# END OF FILE
# =============================================================================
