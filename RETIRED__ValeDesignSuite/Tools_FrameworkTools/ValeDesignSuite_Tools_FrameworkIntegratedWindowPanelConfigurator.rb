# =============================================================================
# VALEDESIGNSUITE - FRAMEWORK INTEGRATED WINDOW PANEL CONFIGURATOR
# =============================================================================
#
# FILE       :  ValeDesignSuite_Tools_FrameworkIntegratedWindowPanelConfigurator.rb
# NAMESPACE  :  ValeDesignSuite::Tools
# MODULE     :  FrameworkIntegratedWindowPanelConfigurator
# AUTHOR     :  Adam Noble - Noble Architecture
# PURPOSE    :  Integrated Window Panel Configurator for Framework System
# CREATED    :  25-May-2025
#
# =============================================================================
# IMPORTANT NOTES - DYNAMIC CONFIGURATION SYSTEM
# =============================================================================
# 
# ⚠️  CRITICAL: This script uses DYNAMIC CONFIGURATION loading from external JSON files.
# 
# DEFAULT CONFIGURATION SOURCE:
# - This script loads default panel configurations from:
#   "ValeDesignSuite_Config_FrameworkConfigurator_DefaultPanelConfig.json"
# - The JSON file is located in the same directory as this script
# - Changes to the JSON file will immediately affect new panel creation
# 
# CONFIGURATION BEHAVIOR:
# - If the JSON file is missing, the script falls back to hardcoded defaults
# - Panel dimensions, materials, and properties are loaded from the JSON
# - Framework constraints override JSON settings for width/positioning
# 
# CUSTOMIZATION:
# - To modify default panel settings, edit the JSON file directly
# - No code changes are required for basic configuration adjustments
# - The JSON file supports panel types, materials, and fabrication properties
# 
# FRAMEWORK INTEGRATION:
# - Panel dimensions are constrained by framework assembly requirements
# - Width is typically fixed by framework panel line length
# - Height and other properties can be configured within framework limits
# 
# FALLBACK SAFETY:
# - If JSON parsing fails, the script uses safe fallback values
# - Error messages are logged through the debug system
# - The system remains functional even with corrupted configuration files
# 
# =============================================================================
#
# DESCRIPTION:
# - This module integrates the window panel configurator with the framework configurator system.
# - It allows for configuration of individual window panels within framework assemblies.
# - Panel dimensions are constrained by the framework panel line dimensions.
# - Each panel maintains its own configuration while being part of the framework assembly.
# - Supports clicking on individual panels in the framework configurator for configuration.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 30-May-2025 - Version 1.0.0
# - Initial implementation of integrated window panel configurator
# - Framework panel dimension constraints implemented
# - Individual panel configuration support added
#
# 27-Jan-2025 - Version 1.1.0
# - Updated to load default configuration from external JSON file
# - Improved configuration management and fallback handling
#
# =============================================================================

require 'sketchup.rb'
require 'json'

# Require the WindowPanelConfigurator from the main directory
require_relative '../Tools_WindowPanelConfigurator/ValeDesignSuite_Tools_WindowPanelConfigurator'
require_relative 'ValeDesignSuite_Tools_FrameworkToolsSketchUpLogic'
require_relative 'ValeDesignSuite_Tools_FrameworkToolsDataSerializer'
require_relative 'ValeDesignSuite_Tools_FrameworkCoordinationManager'
require_relative 'ValeDesignSuite_Tools_FrameworkDebugTools'

module ValeDesignSuite
  module Tools
    module FrameworkIntegratedWindowPanelConfigurator

# -----------------------------------------------------------------------------
# REGION | Module Constants and Configuration
# -----------------------------------------------------------------------------

    # DEBUG TOOLS REFERENCE
    # ------------------------------------------------------------
    DebugTools = ValeDesignSuite::Tools::FrameworkDebugTools

    # MODULE CONSTANTS | Integration and Dictionary Keys
    # ------------------------------------------------------------
    INTEGRATED_PANEL_DICT_NAME  =   "ValeDesignSuite_IntegratedWindowPanels"     # <-- Dictionary for integrated panel data
    PANEL_CONFIG_KEY_PREFIX     =   "PanelConfig_"                               # <-- Prefix for panel configuration keys
    FRAMEWORK_PANEL_TYPE        =   "Window_Panel"                               # <-- Framework panel type for windows
        # ------------------------------------------------------------

    # MODULE VARIABLES | Component References and State
    # ------------------------------------------------------------
    @active_framework_component =   nil                                          # <-- Current framework component
    @active_panel_configs       =   {}                                           # <-- Hash of panel ID to window config
    @framework_assembly_id      =   nil                                          # <-- Current framework assembly ID
        # ------------------------------------------------------------

    # MODULE CONSTANTS | Window Panel Configuration Constants
    # ------------------------------------------------------------
    WINDOW_DICT_NAME        =   ValeDesignSuite::Tools::WindowPanelConfigurator::WINDOW_DICT_NAME  # <-- Use window configurator dictionary name
    MM_TO_INCH              =   ValeDesignSuite::Tools::WindowPanelConfigurator::MM_TO_INCH        # <-- Use window configurator conversion factor
    # ------------------------------------------------------------

    
# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Framework Integration Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Initialize Panel Configurator for Framework Assembly
    # ------------------------------------------------------------
    def self.initialize_for_framework_assembly(framework_component)
        return false unless framework_component && framework_component.valid?    # <-- Validate framework component
        
        @active_framework_component = framework_component                        # <-- Set active framework component
        @framework_assembly_id = get_assembly_id_from_component(framework_component)  # <-- Get assembly ID
        
        return false unless @framework_assembly_id                               # <-- Validate assembly ID exists
        
        load_existing_panel_configurations                                       # <-- Load existing panel configs
        return true                                                              # <-- Return success
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Get Assembly ID from Framework Component
    # ---------------------------------------------------------------
    def self.get_assembly_id_from_component(component)
        return nil unless component.is_a?(Sketchup::ComponentInstance)           # <-- Validate component type
        
        assembly_info_dict = component.attribute_dictionary(
            ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic::ASSEMBLY_INFO_DICT_NAME, 
            false
        )
        return nil unless assembly_info_dict                                     # <-- Return nil if no dictionary
        
        return assembly_info_dict[ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic::ASSEMBLY_ID_KEY]  # <-- Return assembly ID
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Load Existing Panel Configurations
    # ---------------------------------------------------------------
    def self.load_existing_panel_configurations
        return unless @active_framework_component && @framework_assembly_id      # <-- Validate prerequisites
        
        @active_panel_configs = {}                                               # <-- Reset panel configs
        
        # Get integrated panel dictionary from component
        panel_dict = @active_framework_component.attribute_dictionary(INTEGRATED_PANEL_DICT_NAME, false)
        return unless panel_dict                                                 # <-- Return if no panel dictionary
        
        # Load each panel configuration
        panel_dict.each do |key, value|
            next unless key.start_with?(PANEL_CONFIG_KEY_PREFIX)                 # <-- Skip non-panel keys
            
            panel_id = key.sub(PANEL_CONFIG_KEY_PREFIX, "")                      # <-- Extract panel ID
            
            begin
                panel_config = JSON.parse(value)                                 # <-- Parse panel configuration
                @active_panel_configs[panel_id] = panel_config                   # <-- Store panel configuration
            rescue JSON::ParserError => e
                DebugTools.debug_panel("Error loading panel config for #{panel_id}: #{e.message}") # <-- Log parsing errors
            end
        end
        
        DebugTools.debug_panel("Loaded #{@active_panel_configs.size} panel configurations for assembly #{@framework_assembly_id}")
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Configuration Loading and Management
# -----------------------------------------------------------------------------

    # FUNCTION | Load Default Panel Configuration from JSON File
    # ------------------------------------------------------------
    def self.load_default_panel_configuration
        begin
            config_file_path = File.join(__dir__, "ValeDesignSuite_Config_FrameworkConfigurator_DefaultPanelConfig.json")
            
            if File.exist?(config_file_path)                                     # <-- Check if config file exists
                config_content = File.read(config_file_path)                     # <-- Read config file content
                config_data = JSON.parse(config_content)                         # <-- Parse JSON content
                
                # Extract panel defaults
                panel_defaults = config_data["panel_defaults"]                   # <-- Get panel defaults section
                
                DebugTools.debug_panel("Loaded default panel configuration from external file")
                return panel_defaults                                             # <-- Return panel defaults
                
            else
                DebugTools.debug_panel("Default panel config file not found, using fallback configuration")
                return create_fallback_panel_configuration                       # <-- Use fallback if file missing
            end
            
        rescue JSON::ParserError => e
            DebugTools.debug_panel("Error parsing default panel config file: #{e.message}")
            return create_fallback_panel_configuration                           # <-- Use fallback on parse error
        rescue => e
            DebugTools.debug_panel("Error loading default panel config file: #{e.message}")
            return create_fallback_panel_configuration                           # <-- Use fallback on any error
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Create Fallback Panel Configuration
    # ---------------------------------------------------------------
    def self.create_fallback_panel_configuration
        {
            "name" => "Framework_Panel",
            "description" => "Standard Framework Infill Panel",
            "panel_type" => "solid",
            "dimensions" => {
                "length_mm" => 600,
                "height_mm" => 600,
                "thickness_mm" => 18,
                "min_length_mm" => 100,
                "max_length_mm" => 3000,
                "min_height_mm" => 100,
                "max_height_mm" => 3000,
                "min_thickness_mm" => 6,
                "max_thickness_mm" => 50
            },
            "material_properties" => {
                "default_material" => "Plywood_Birch",
                "grain_direction" => "horizontal",
                "surface_finish" => "natural",
                "edge_treatment" => "rounded"
            },
            "positioning" => {
                "origin_x" => 0.0,
                "origin_y" => 0.0,
                "origin_z" => 0.0,
                "rotation_degrees" => 0.0,
                "anchor_point" => "bottom_left",
                "inset_from_frame_mm" => 10,
                "alignment" => "center"
            }
        }
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Panel Configuration Management
# -----------------------------------------------------------------------------

    # FUNCTION | Configure Panel from Framework Panel Line Data
    # ------------------------------------------------------------
    def self.configure_panel_from_framework_data(panel_line_data)
        return nil unless panel_line_data && panel_line_data.is_a?(Hash)         # <-- Validate panel line data
        return nil unless @active_framework_component && @framework_assembly_id  # <-- Validate framework context
        
        panel_id = panel_line_data["PanelUniqueId"]                              # <-- Get panel unique ID
        return nil unless panel_id                                               # <-- Validate panel ID exists
        
        # Extract panel dimensions from framework data
        panel_width_mm = panel_line_data["length_mm"] || 800                     # <-- Get panel width from framework
        panel_height_mm = panel_line_data["PanelSizeZ"] || 1500                  # <-- Get panel height from framework
        panel_type = panel_line_data["PanelType"] || FRAMEWORK_PANEL_TYPE        # <-- Get panel type
        
        # Only configure if it's a window panel
        return nil unless panel_type == FRAMEWORK_PANEL_TYPE                     # <-- Skip non-window panels
        
        # Create or update window panel configuration
        window_config = create_constrained_window_config(panel_id, panel_width_mm, panel_height_mm)
        
        # Store configuration
        @active_panel_configs[panel_id] = window_config                          # <-- Store panel configuration
        save_panel_configuration(panel_id, window_config)                       # <-- Save to component dictionary
        
        return window_config                                                     # <-- Return created configuration
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create Constrained Window Configuration
    # ---------------------------------------------------------------
    def self.create_constrained_window_config(panel_id, width_mm, height_mm)
        # Start with default window configuration
        base_config = ValeDesignSuite::Tools::WindowPanelConfigurator::DEFAULT_CONFIG.dup                    # <-- Use window configurator defaults
        
        # Update metadata with panel ID and framework context
        base_config["windowMetadata"][0]["WindowUniqueId"] = panel_id           # <-- Set panel ID as window ID
        base_config["windowMetadata"][0]["WindowName"] = "FrameworkPanel_#{panel_id}"  # <-- Set descriptive name
        base_config["windowMetadata"][0]["WindowDescription"] = "Window panel integrated with framework assembly #{@framework_assembly_id}"
        base_config["windowMetadata"][0]["WindowLastModified"] = Time.now.strftime("%d-%b-%Y")
        
        # Update component IDs with panel ID
        ValeDesignSuite::Tools::WindowPanelConfigurator.update_component_ids_with_panel_id(base_config, panel_id)
        
        # Constrain dimensions to framework panel dimensions
        window_config = base_config["windowConfiguration"]
        window_config["Component_Default_Width_mm"] = width_mm                  # <-- Constrain width to framework
        window_config["Component_Default_Height_mm"] = height_mm                # <-- Constrain height to framework
        
        # Set UI constraints to prevent exceeding framework dimensions
        window_config["Component_UI_MinWidth_mm"] = [width_mm * 0.8, 400].max.to_i      # <-- Minimum 80% of framework width
        window_config["Component_UI_MaxWidth_mm"] = width_mm                     # <-- Maximum is framework width
        window_config["Component_UI_MinHeight_mm"] = [height_mm * 0.8, 500].max.to_i    # <-- Minimum 80% of framework height
        window_config["Component_UI_MaxHeight_mm"] = height_mm                   # <-- Maximum is framework height
        
        # Update frame and glass dimensions
        ValeDesignSuite::Tools::WindowPanelConfigurator.update_frame_dimensions_in_config(base_config, width_mm, height_mm, window_config["Component_Default_FrameThickness_mm"])
        ValeDesignSuite::Tools::WindowPanelConfigurator.update_glass_dimensions_in_config(base_config, width_mm, height_mm, window_config["Component_Default_FrameThickness_mm"])
        
        return base_config                                                       # <-- Return constrained configuration
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Save Panel Configuration to Component Dictionary
    # ---------------------------------------------------------------
    def self.save_panel_configuration(panel_id, config)
        return unless @active_framework_component && panel_id && config          # <-- Validate prerequisites
        
        # Get or create integrated panel dictionary
        panel_dict = @active_framework_component.attribute_dictionary(INTEGRATED_PANEL_DICT_NAME, true)
        
        # Save configuration as JSON string
        config_key = "#{PANEL_CONFIG_KEY_PREFIX}#{panel_id}"                     # <-- Create configuration key
        panel_dict[config_key] = JSON.generate(config)                          # <-- Save configuration as JSON
        
        DebugTools.debug_panel("Saved panel configuration for #{panel_id} in framework assembly #{@framework_assembly_id}")
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Panel Interaction and UI Integration
# -----------------------------------------------------------------------------

    # FUNCTION | Handle Panel Click from Framework Configurator
    # ------------------------------------------------------------
    def self.handle_panel_click(panel_id, framework_component = nil)
        # Initialize for framework if component provided
        if framework_component
            success = initialize_for_framework_assembly(framework_component)     # <-- Initialize framework context
            return false unless success                                          # <-- Return false if initialization failed
        end
        
        return false unless @active_framework_component && @framework_assembly_id  # <-- Validate framework context
        
        # Load framework data to get panel line information
        framework_data = ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic.load_framework_data_from_component(
            @active_framework_component.entityID
        )
        return false unless framework_data                                       # <-- Validate framework data loaded
        
        # Find the specific panel line data
        panel_lines = framework_data["frameworkPanelLines"] || []               # <-- Get panel lines array
        panel_line_data = panel_lines.find { |line| line["PanelUniqueId"] == panel_id }  # <-- Find specific panel
        
        return false unless panel_line_data                                      # <-- Validate panel found
        
        # Configure or update panel
        window_config = configure_panel_from_framework_data(panel_line_data)    # <-- Configure panel from framework data
        return false unless window_config                                        # <-- Validate configuration created
        
        # Show window configurator dialog with constrained configuration
        show_constrained_window_configurator(panel_id, window_config)           # <-- Show configurator dialog
        
        return true                                                              # <-- Return success
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Show Constrained Window Configurator Dialog
    # ---------------------------------------------------------------
    def self.show_constrained_window_configurator(panel_id, window_config)
        # Create a specialized dialog for framework-integrated panels
        dialog_title = "Configure Framework Panel: #{panel_id}"                 # <-- Set dialog title
        
        # Create HTML content with framework context
        html_content = create_framework_panel_dialog_html(panel_id, window_config)
        
        # Create and show dialog
        dialog = UI::HtmlDialog.new(
            {
                :dialog_title => dialog_title,
                :preferences_key => "ValeDesignSuite_FrameworkPanelConfig_#{panel_id}",
                :scrollable => false,
                :resizable => true,
                :width => 800,
                :height => 900,
                :left => 200,
                :top => 200,
                :min_width => 600,
                :min_height => 700,
                :max_width => 1200,
                :max_height => 1200,
                :style => UI::HtmlDialog::STYLE_DIALOG
            }
        )
        
        dialog.set_html(html_content)                                            # <-- Set dialog HTML content
        setup_framework_panel_dialog_callbacks(dialog, panel_id, window_config) # <-- Setup dialog callbacks
        dialog.show                                                              # <-- Show dialog
        
        return dialog                                                            # <-- Return dialog reference
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Framework Panel Dialog HTML
    # ---------------------------------------------------------------
    def self.create_framework_panel_dialog_html(panel_id, window_config)
        window_config_obj = window_config["windowConfiguration"]                # <-- Get window configuration object
        
        # Extract current values
        current_width = window_config_obj["Component_Default_Width_mm"]          # <-- Get current width
        current_height = window_config_obj["Component_Default_Height_mm"]        # <-- Get current height
        current_thickness = window_config_obj["Component_Default_FrameThickness_mm"]  # <-- Get current thickness
        current_vertical_bars = window_config_obj["Component_Default_VerticalGlazeBars"]  # <-- Get vertical bars
        current_horizontal_bars = window_config_obj["Component_Default_HorizontalGlazeBars"]  # <-- Get horizontal bars
        current_color = window_config_obj["Component_Default_FrameColor"]        # <-- Get frame color
        
        # Extract UI constraints
        min_width = window_config_obj["Component_UI_MinWidth_mm"]                # <-- Get minimum width
        max_width = window_config_obj["Component_UI_MaxWidth_mm"]                # <-- Get maximum width
        min_height = window_config_obj["Component_UI_MinHeight_mm"]              # <-- Get minimum height
        max_height = window_config_obj["Component_UI_MaxHeight_mm"]              # <-- Get maximum height
        
        return <<-HTML
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Framework Panel Configuration</title>
    <style>
        /* Framework Panel Configurator Styles */
        :root {
            --ValeBackgroundColor: #f5f5f5;
            --ValeHighlightColor: #006600;
            --FontCol_ValeStandardTextColour: #1e1e1e;
            --FontType_ValeStandardText: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        
        body {
            font-family: var(--FontType_ValeStandardText);
            background-color: var(--ValeBackgroundColor);
            color: var(--FontCol_ValeStandardTextColour);
            margin: 20px;
            padding: 0;
        }
        
        .panel-header {
            background-color: var(--ValeHighlightColor);
            color: white;
            padding: 15px;
            margin: -20px -20px 20px -20px;
            border-radius: 0;
        }
        
        .panel-header h1 {
            margin: 0;
            font-size: 1.2em;
        }
        
        .panel-header p {
            margin: 5px 0 0 0;
            font-size: 0.9em;
            opacity: 0.9;
        }
        
        .constraint-info {
            background-color: #fff3cd;
            border: 1px solid #ffeaa7;
            padding: 10px;
            margin-bottom: 20px;
            border-radius: 4px;
        }
        
        .constraint-info h3 {
            margin: 0 0 5px 0;
            color: #856404;
        }
        
        .section {
            background-color: white;
            padding: 15px;
            margin-bottom: 15px;
            border-radius: 4px;
            border: 1px solid #ddd;
        }
        
        .section h3 {
            margin: 0 0 15px 0;
            color: var(--ValeHighlightColor);
        }
        
        .slider-container {
            margin-bottom: 15px;
        }
        
        .slider-label {
            display: flex;
            justify-content: space-between;
            margin-bottom: 5px;
            font-weight: bold;
        }
        
        .slider {
            width: 100%;
            height: 6px;
            border-radius: 3px;
            background: #ddd;
            outline: none;
            -webkit-appearance: none;
        }
        
        .slider::-webkit-slider-thumb {
            -webkit-appearance: none;
            appearance: none;
            width: 20px;
            height: 20px;
            border-radius: 50%;
            background: var(--ValeHighlightColor);
            cursor: pointer;
        }
        
        .color-swatches {
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
        }
        
        .color-swatch {
            width: 40px;
            height: 40px;
            border-radius: 4px;
            border: 2px solid #ddd;
            cursor: pointer;
            transition: border-color 0.2s;
        }
        
        .color-swatch.selected {
            border-color: var(--ValeHighlightColor);
            border-width: 3px;
        }
        
        .button-container {
            display: flex;
            gap: 10px;
            margin-top: 20px;
        }
        
        .btn {
            padding: 10px 20px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
            transition: background-color 0.2s;
        }
        
        .btn-primary {
            background-color: var(--ValeHighlightColor);
            color: white;
        }
        
        .btn-primary:hover {
            background-color: #005500;
        }
        
        .btn-secondary {
            background-color: #6c757d;
            color: white;
        }
        
        .btn-secondary:hover {
            background-color: #5a6268;
        }
    </style>
</head>
<body>
    <div class="panel-header">
        <h1>Framework Panel Configuration</h1>
        <p>Panel ID: #{panel_id} | Framework Assembly: #{@framework_assembly_id}</p>
    </div>
    
    <div class="constraint-info">
        <h3>Framework Constraints</h3>
        <p>This panel\'s dimensions are constrained by the framework assembly. Width is fixed at #{max_width}mm based on the framework panel line length.</p>
    </div>
    
    <div class="section">
        <h3>Panel Dimensions</h3>
        
        <div class="slider-container">
            <div class="slider-label">
                <span>Width (CONSTRAINED)</span>
                <span id="width-value">#{current_width} mm</span>
            </div>
            <input type="range" id="width-slider" class="slider" 
                   min="#{min_width}" max="#{max_width}" value="#{current_width}"
                   disabled style="opacity: 0.5;">
            <small>Width is constrained by framework panel line (#{max_width}mm)</small>
        </div>
        
        <div class="slider-container">
            <div class="slider-label">
                <span>Height</span>
                <span id="height-value">#{current_height} mm</span>
            </div>
            <input type="range" id="height-slider" class="slider" 
                   min="#{min_height}" max="#{max_height}" value="#{current_height}"
                   oninput="updateHeight(this.value); applyConfiguration();">
        </div>
        
        <div class="slider-container">
            <div class="slider-label">
                <span>Frame Thickness</span>
                <span id="thickness-value">#{current_thickness} mm</span>
            </div>
            <input type="range" id="thickness-slider" class="slider" 
                   min="30" max="150" value="#{current_thickness}"
                   oninput="updateThickness(this.value); applyConfiguration();">
        </div>
    </div>
    
    <div class="section">
        <h3>Glaze Bar Configuration</h3>
        
        <div class="slider-container">
            <div class="slider-label">
                <span>Vertical Glaze Bars</span>
                <span id="vertical-bars-value">#{current_vertical_bars}</span>
            </div>
            <input type="range" id="vertical-bars-slider" class="slider" 
                   min="0" max="8" value="#{current_vertical_bars}"
                   oninput="updateVerticalBars(this.value); applyConfiguration();">
        </div>
        
        <div class="slider-container">
            <div class="slider-label">
                <span>Horizontal Glaze Bars</span>
                <span id="horizontal-bars-value">#{current_horizontal_bars}</span>
            </div>
            <input type="range" id="horizontal-bars-slider" class="slider" 
                   min="0" max="6" value="#{current_horizontal_bars}"
                   oninput="updateHorizontalBars(this.value); applyConfiguration();">
        </div>
    </div>
    
    <div class="section">
        <h3>Frame Color</h3>
        <div class="color-swatches">
            <div class="color-swatch #{current_color == 'natural-wood' ? 'selected' : ''}" 
                 style="background-color: #D2B48C;" 
                 onclick="selectColor('natural-wood'); applyConfiguration();" 
                 title="Natural Wood"></div>
            <div class="color-swatch #{current_color == 'white' ? 'selected' : ''}" 
                 style="background-color: #FFFFFF;" 
                 onclick="selectColor('white'); applyConfiguration();" 
                 title="White"></div>
            <div class="color-swatch #{current_color == 'black' ? 'selected' : ''}" 
                 style="background-color: #2C2C2C;" 
                 onclick="selectColor('black'); applyConfiguration();" 
                 title="Black"></div>
            <div class="color-swatch #{current_color == 'grey' ? 'selected' : ''}" 
                 style="background-color: #808080;" 
                 onclick="selectColor('grey'); applyConfiguration();" 
                 title="Grey"></div>
        </div>
    </div>
    
    <script>
        // Current configuration values
        let currentConfig = {
            width: #{current_width},
            height: #{current_height},
            thickness: #{current_thickness},
            verticalBars: #{current_vertical_bars},
            horizontalBars: #{current_horizontal_bars},
            color: \'#{current_color}\'
        };
        
        // Update functions
        function updateHeight(value) {
            currentConfig.height = parseInt(value);
            document.getElementById(\'height-value\').textContent = value + \' mm\';
        }
        
        function updateThickness(value) {
            currentConfig.thickness = parseInt(value);
            document.getElementById(\'thickness-value\').textContent = value + \' mm\';
        }
        
        function updateVerticalBars(value) {
            currentConfig.verticalBars = parseInt(value);
            document.getElementById(\'vertical-bars-value\').textContent = value;
        }
        
        function updateHorizontalBars(value) {
            currentConfig.horizontalBars = parseInt(value);
            document.getElementById(\'horizontal-bars-value\').textContent = value;
        }
        
        function selectColor(color) {
            currentConfig.color = color;
            // Update visual selection
            document.querySelectorAll(\'.color-swatch\').forEach(swatch => {
                swatch.classList.remove(\'selected\');
            });
            event.target.classList.add(\'selected\');
        }
        
        function applyConfiguration() {
            if (window.sketchup && window.sketchup.applyFrameworkPanelConfig) {
                window.sketchup.applyFrameworkPanelConfig(JSON.stringify(currentConfig));
            }
        }
        
        // Removed previewConfiguration and closeDialog functions as buttons are removed

    </script>
</body>
</html>
        HTML
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Setup Framework Panel Dialog Callbacks
    # ---------------------------------------------------------------
    def self.setup_framework_panel_dialog_callbacks(dialog, panel_id, window_config)
        # Callback for applying configuration
        dialog.add_action_callback("applyFrameworkPanelConfig") do |action_context, config_json|
            begin
                new_config = JSON.parse(config_json)                             # <-- Parse new configuration
                
                # Update window configuration with new values
                updated_config = update_window_config_from_dialog(window_config, new_config)
                
                # Save updated configuration
                @active_panel_configs[panel_id] = updated_config                 # <-- Store updated configuration
                save_panel_configuration(panel_id, updated_config)              # <-- Save to component dictionary
                
                # Update or create window geometry
                update_or_create_framework_panel_window_geometry(panel_id, updated_config)
                
                # **NEW**: Update framework data with new panel dimensions
                update_framework_data_from_panel_config(panel_id, updated_config)
                
                # **NEW**: Trigger coordination manager to update node positions
                ValeDesignSuite::Tools::FrameworkCoordinationManager.trigger_realtime_update
                
                # dialog.close # Dialog remains open for real-time updates
                DebugTools.debug_panel("Applied configuration for framework panel #{panel_id}")
                
            rescue JSON::ParserError => e
                DebugTools.debug_panel("Error parsing panel configuration: #{e.message}")          # <-- Log parsing errors
            end
        end
        
        # Removed callbacks for preview and close as buttons are removed

    end
    # ---------------------------------------------------------------

    # NEW FUNCTION | Update or Create Framework Panel Window Geometry
    # ------------------------------------------------------------
    def self.update_or_create_framework_panel_window_geometry(panel_id, window_config)
        return unless @active_framework_component && window_config               # <-- Validate prerequisites
        
        # Check if window already exists for this panel within the framework
        existing_window_group = find_existing_window_group_for_panel(panel_id)
        
        if existing_window_group && existing_window_group.valid?
            # Update existing window group
            update_existing_framework_panel_window_group(existing_window_group, window_config)
            DebugTools.debug_panel("Updated existing window group for panel #{panel_id}")
        else
            # Create new window group within framework
            window_group = create_framework_panel_window_group(panel_id, window_config)
            DebugTools.debug_panel("Created new window group for panel #{panel_id}")
        end
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Find Existing Window Group for Panel
    # ---------------------------------------------------------------
    def self.find_existing_window_group_for_panel(panel_id)
        return nil unless @active_framework_component                            # <-- Validate framework component
        
        # Search through the framework component's entities for a window group
        @active_framework_component.definition.entities.grep(Sketchup::Group).each do |group|
            if group.name && group.name.include?(panel_id) && group.name.include?("Window")
                return group                                                     # <-- Return matching window group
            end
        end
        
        return nil                                                               # <-- Return nil if not found
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Update Existing Framework Panel Window Group
    # ---------------------------------------------------------------
    def self.update_existing_framework_panel_window_group(window_group, window_config)
        return unless window_group && window_group.valid? && window_config       # <-- Validate prerequisites
        
        model = Sketchup.active_model
        model.start_operation("Update Framework Panel Window", true)            # <-- Start operation
        
        begin
            # Clear existing geometry in the group
            window_group.entities.clear!                                        # <-- Clear existing entities
            
            # Create new window geometry within the group
            ValeDesignSuite::Tools::WindowPanelConfigurator.create_all_window_subcomponents(window_group, window_config)
            
            # Apply materials
            window_config_obj = window_config["windowConfiguration"]
            frame_color = window_config_obj["Component_Default_FrameColor"] || "natural-wood"
            ValeDesignSuite::Tools::WindowPanelConfigurator.add_materials(window_group.entities, frame_color)
            
            # Save configuration to group
            save_panel_configuration_to_group(window_group, window_config)
            
            model.commit_operation                                               # <-- Commit operation
            DebugTools.debug_panel("Successfully updated window group geometry for panel")
            
        rescue => e
            model.abort_operation                                                # <-- Abort on error
            DebugTools.debug_panel("Error updating window group: #{e.message}")
            DebugTools.debug_panel(e.backtrace.join("\n"))
        end
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create Framework Panel Window Group
    # ---------------------------------------------------------------
    def self.create_framework_panel_window_group(panel_id, window_config)
        return nil unless @active_framework_component && window_config           # <-- Validate prerequisites
        
        model = Sketchup.active_model
        model.start_operation("Create Framework Panel Window", true)            # <-- Start operation
        
        begin
            # Create window group within framework component definition
            window_group = @active_framework_component.definition.entities.add_group
            window_group.name = "#{panel_id}_Window"                            # <-- Set descriptive name
            
            # Create window geometry within the group
            ValeDesignSuite::Tools::WindowPanelConfigurator.create_all_window_subcomponents(window_group, window_config)
            
            # Apply materials
            window_config_obj = window_config["windowConfiguration"]
            frame_color = window_config_obj["Component_Default_FrameColor"] || "natural-wood"
            ValeDesignSuite::Tools::WindowPanelConfigurator.add_materials(window_group.entities, frame_color)
            
            # Position window group based on panel location
            position_window_group_in_framework(panel_id, window_group)
            
            # Save configuration to group
            save_panel_configuration_to_group(window_group, window_config)
            
            model.commit_operation                                               # <-- Commit operation
            DebugTools.debug_panel("Successfully created window group for panel #{panel_id}")
            return window_group                                                  # <-- Return created group
            
        rescue => e
            model.abort_operation                                                # <-- Abort on error
            DebugTools.debug_panel("Error creating window group: #{e.message}")
            DebugTools.debug_panel(e.backtrace.join("\n"))
            return nil                                                           # <-- Return nil on error
        end
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Position Window Group in Framework
    # ---------------------------------------------------------------
    def self.position_window_group_in_framework(panel_id, window_group)
        return unless @active_framework_component && window_group               # <-- Validate prerequisites
        
        # Initialize coordination manager for proper coordinate transformation
        ValeDesignSuite::Tools::FrameworkCoordinationManager.initialize_for_framework_assembly(@active_framework_component)
        
        # Get coordinate transformation for this panel
        transform_data = ValeDesignSuite::Tools::FrameworkCoordinationManager.get_coordinate_transformation(panel_id)
        
        if transform_data && transform_data[:model]
            # Apply transformation to position window group correctly
            model_coords = transform_data[:model]
            transformation = Geom::Transformation.new([
                model_coords[:x], 
                model_coords[:y], 
                model_coords[:z]
            ])
            
            # Apply transformation to window group
            window_group.transformation = transformation
            
            DebugTools.debug_panel("Positioned window group for panel #{panel_id} at (#{(model_coords[:x]/1.mm).round(1)}, #{(model_coords[:y]/1.mm).round(1)}, #{(model_coords[:z]/1.mm).round(1)}) mm")
        else
            DebugTools.debug_panel("Warning: No coordinate transformation found for panel #{panel_id}, using fallback positioning")
            
            # Fallback: Try to get position from framework data directly
            framework_data = ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic.load_framework_data_from_component(
                @active_framework_component.entityID
            )
            
            if framework_data
                # Find panel line data
                panel_lines = framework_data["frameworkPanelLines"] || []               # <-- Get panel lines
                panel_line = panel_lines.find { |line| line["PanelUniqueId"] == panel_id }  # <-- Find specific panel
                
                if panel_line
                    # Get connected nodes to calculate panel position
                    from_node_id = panel_line["from_node_id"]
                    to_node_id = panel_line["to_node_id"]
                    
                    # Find node data
                    nodes = framework_data["frameworkNodes"] || []
                    from_node = nodes.find { |node| node["NodeUniqueId"] == from_node_id }
                    to_node = nodes.find { |node| node["NodeUniqueId"] == to_node_id }
                    
                    if from_node && to_node
                        # Calculate panel position between outer edges of nodes
                        # node.x now represents the LEFT EDGE of each node
                        from_node_full_width = from_node["NodeSizeX"] || 290
                        to_node_full_width = to_node["NodeSizeX"] || 290
                        
                        # Panel starts at right edge of from node and ends at left edge of to node
                        from_node_right_edge = from_node["x"] + from_node_full_width
                        to_node_left_edge = to_node["x"]
                        
                        # Panel left edge position (where it starts)
                        panel_left_edge = from_node_right_edge
                        
                        # Convert to model coordinates
                        model_x = panel_left_edge.mm
                        model_y = 0.mm  # Framework Y is always 0
                        model_z = 0.mm  # Framework Z starts at ground level
                        
                        transformation = Geom::Transformation.new([model_x, model_y, model_z])
                        window_group.transformation = transformation
                        
                        DebugTools.debug_panel("Positioned window group for panel #{panel_id} at fallback position (#{panel_left_edge}, 0, 0) mm")
                    else
                        DebugTools.debug_panel("Error: Could not find connected nodes for panel #{panel_id}")
                    end
                else
                    DebugTools.debug_panel("Error: Could not find panel data for #{panel_id}")
                end
            else
                DebugTools.debug_panel("Error: Could not load framework data for fallback positioning")
            end
        end
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Save Panel Configuration to Group
    # ---------------------------------------------------------------
    def self.save_panel_configuration_to_group(window_group, window_config)
        return unless window_group && window_group.valid? && window_config       # <-- Validate prerequisites
        
        # Save configuration directly to the window group
        dict = window_group.attribute_dictionary("WindowConfigurator_Config", true)
        config_json = JSON.generate(window_config)
        dict["window_config"] = config_json
        dict["window_config_formatted"] = JSON.pretty_generate(window_config)
        
        DebugTools.debug_panel("Saved window configuration to group")
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Interface Methods
# -----------------------------------------------------------------------------

    # FUNCTION | Get Panel Configuration for Panel ID
    # ------------------------------------------------------------
    def self.get_panel_configuration(panel_id)
        return @active_panel_configs[panel_id] if @active_panel_configs.key?(panel_id)  # <-- Return existing config
        return nil                                                               # <-- Return nil if not found
    end
    # ---------------------------------------------------------------

    # FUNCTION | Check if Framework Component has Integrated Panels
    # ------------------------------------------------------------
    def self.has_integrated_panels?(framework_component)
        return false unless framework_component && framework_component.valid?    # <-- Validate component
        
        panel_dict = framework_component.attribute_dictionary(INTEGRATED_PANEL_DICT_NAME, false)
        return false unless panel_dict                                           # <-- Return false if no dictionary
        
        # Check if any panel configurations exist
        panel_dict.each do |key, value|
            return true if key.start_with?(PANEL_CONFIG_KEY_PREFIX)              # <-- Return true if panel configs found
        end
        
        return false                                                             # <-- Return false if no panel configs
    end
    # ---------------------------------------------------------------

    # FUNCTION | List All Panel IDs for Framework Component
    # ------------------------------------------------------------
    def self.list_panel_ids_for_framework(framework_component)
        return [] unless framework_component && framework_component.valid?       # <-- Return empty array if invalid
        
        panel_dict = framework_component.attribute_dictionary(INTEGRATED_PANEL_DICT_NAME, false)
        return [] unless panel_dict                                              # <-- Return empty array if no dictionary
        
        panel_ids = []                                                           # <-- Initialize panel IDs array
        panel_dict.each do |key, value|
            if key.start_with?(PANEL_CONFIG_KEY_PREFIX)                          # <-- Check if panel configuration key
                panel_id = key.sub(PANEL_CONFIG_KEY_PREFIX, "")                  # <-- Extract panel ID
                panel_ids << panel_id                                            # <-- Add to panel IDs array
            end
        end
        
        return panel_ids                                                         # <-- Return panel IDs array
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    # HELPER FUNCTION | Update Window Config from Dialog (FIXED)
    # ---------------------------------------------------------------
    def self.update_window_config_from_dialog(base_config, dialog_config)
        updated_config = base_config.dup                                        # <-- Create copy of base config
        window_config_obj = updated_config["windowConfiguration"]               # <-- Get window configuration object
        
        # Update configuration values from dialog
        # NOTE: Width is intentionally not updated as it's constrained by framework
        window_config_obj["Component_Default_Height_mm"] = dialog_config["height"]  # <-- Update height
        window_config_obj["Component_Default_FrameThickness_mm"] = dialog_config["thickness"]  # <-- Update thickness
        window_config_obj["Component_Default_VerticalGlazeBars"] = dialog_config["verticalBars"]  # <-- Update vertical bars
        window_config_obj["Component_Default_HorizontalGlazeBars"] = dialog_config["horizontalBars"]  # <-- Update horizontal bars
        window_config_obj["Component_Default_FrameColor"] = dialog_config["color"]  # <-- Update frame color
        
        # Update frame and glass dimensions with current width (constrained) and new height
        current_width = window_config_obj["Component_Default_Width_mm"]          # <-- Keep constrained width
        ValeDesignSuite::Tools::WindowPanelConfigurator.update_frame_dimensions_in_config(
            updated_config, 
            current_width, 
            dialog_config["height"], 
            dialog_config["thickness"]
        )
        ValeDesignSuite::Tools::WindowPanelConfigurator.update_glass_dimensions_in_config(
            updated_config, 
            current_width, 
            dialog_config["height"], 
            dialog_config["thickness"]
        )
        
        # Update metadata timestamp
        updated_config["windowMetadata"][0]["WindowLastModified"] = Time.now.strftime("%d-%b-%Y")
        
        return updated_config                                                    # <-- Return updated configuration
    end
    # ---------------------------------------------------------------

    # NEW FUNCTION | Update Framework Data from Panel Configuration
    # ------------------------------------------------------------
    def self.update_framework_data_from_panel_config(panel_id, window_config)
        return unless @active_framework_component && panel_id && window_config  # <-- Validate prerequisites
        
        # Load current framework data
        framework_data = ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic.load_framework_data_from_component(
            @active_framework_component.entityID
        )
        return unless framework_data                                            # <-- Validate framework data loaded
        
        # Find and update the specific panel line data
        panel_lines = framework_data["frameworkPanelLines"] || []
        panel_line = panel_lines.find { |line| line["PanelUniqueId"] == panel_id }
        
        if panel_line
            # Extract panel dimensions from window configuration
            window_config_obj = window_config["windowConfiguration"]
            
            # Update panel dimensions from window configuration
            panel_line["length_mm"] = window_config_obj["Component_Default_Width_mm"]
            panel_line["PanelSizeZ"] = window_config_obj["Component_Default_Height_mm"]
            
            # Get assembly ID for saving
            assembly_id = ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic.get_assembly_id_from_component(@active_framework_component)
            
            if assembly_id
                # Save updated framework data back using the serializer
                success = ValeDesignSuite::DataUtils::FrameworkDataSerializer.save_assembly_data(assembly_id, framework_data)
                
                if success
                    DebugTools.debug_panel("Updated framework data for panel #{panel_id} - new dimensions: #{panel_line["length_mm"]}mm x #{panel_line["PanelSizeZ"]}mm")
                else
                    DebugTools.debug_panel("Warning: Failed to save updated framework data for panel #{panel_id}")
                end
            else
                DebugTools.debug_panel("Warning: Could not get assembly ID for framework component")
            end
        else
            DebugTools.debug_panel("Warning: Could not find panel line data for #{panel_id}")
        end
    end
    # ---------------------------------------------------------------

    end # module FrameworkIntegratedWindowPanelConfigurator
  end # module Tools
end # module ValeDesignSuite 