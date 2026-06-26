# =============================================================================
# VALEDESIGNSUITE - FRAMEWORK NODE CONFIGURATOR
# =============================================================================
#
# FILE       : ValeDesignSuite_Tools_FrameworkNodeConfigurator.rb
# NAMESPACE  : ValeDesignSuite::Tools
# MODULE     : FrameworkNodeConfigurator
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Live Configurable Framework Node Builder for SketchUp
# CREATED    : 2025
#
# =============================================================================
# IMPORTANT NOTES - DYNAMIC CONFIGURATION SYSTEM
# =============================================================================
# 
# ⚠️  CRITICAL: This script uses DYNAMIC CONFIGURATION loading from external JSON files.
# 
# DEFAULT CONFIGURATION SOURCE:
# - This script loads default node configurations from:
#   "ValeDesignSuite_Config_FrameworkConfigurator_DefaultNodeConfig.json"
# - The JSON file is located in the same directory as this script
# - Changes to the JSON file will immediately affect new node creation
# 
# CONFIGURATION BEHAVIOR:
# - If the JSON file is missing, the script falls back to hardcoded defaults
# - The JSON structure is converted to legacy format for backward compatibility
# - All node dimensions, materials, and constraints are loaded from the JSON
# 
# CUSTOMIZATION:
# - To modify default node settings, edit the JSON file directly
# - No code changes are required for basic configuration adjustments
# - The JSON file supports full node type definitions and UI constraints
# 
# FALLBACK SAFETY:
# - If JSON parsing fails, the script uses safe fallback values
# - Error messages are logged through the debug system
# - The system remains functional even with corrupted configuration files
# 
# =============================================================================
#
# DESCRIPTION:
# - This script implements a configurable framework node builder for SketchUp.
# - It uses a UI::HtmlDialog for interactive configuration of node dimensions and types.
# - The nodes are built based on JSON configuration data with proper column geometry.
# - All dimensions are specified in millimeters and converted to inches for SketchUp.
# - Real-time preview updates as sliders are adjusted.
# - Supports multiple node instances with automatic selection switching.
# - Each node component is assigned a unique Node ID (e.g., "ND001", "ND002").
# - Coordinates are defined at origin (0,0,0) rather than being centered on columns.
# - Contains relative directory paths for detailed column components.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 30-May-2025 - Version 1.0.0
# - Initial implementation based on WindowPanelConfigurator structure
# - JSON-based node configuration system implemented
# - Origin-based coordinate system implemented
# - Relative directory path system for detailed columns added
#
# 27-Jan-2025 - Version 1.1.0
# - Updated to load default configuration from external JSON file
# - Improved configuration management and default value handling
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative 'ValeDesignSuite_Tools_FrameworkDebugTools'

module ValeDesignSuite
  module Tools
    module FrameworkNodeConfigurator

# -----------------------------------------------------------------------------
# REGION | Module Constants and Configuration
# -----------------------------------------------------------------------------

    # DEBUG TOOLS REFERENCE
    # ------------------------------------------------------------
    DebugTools = ValeDesignSuite::Tools::FrameworkDebugTools

    # MODULE CONSTANTS | Unit Conversion and Dictionary Keys
    # ------------------------------------------------------------
    MM_TO_INCH              =   1.0 / 25.4                                    # <-- Millimeter to inch conversion factor
    NODE_DICT_NAME          =   "FrameworkNodeConfigurator_Config"            # <-- Dictionary name for storing node configuration
    STANDARD_WIDTH_MM       =   290                                           # <-- Standard node width in millimeters
    STANDARD_DEPTH_MM       =   94                                            # <-- Standard node depth in millimeters
    STANDARD_HEIGHT_MM      =   2000                                          # <-- Standard node height in millimeters
    
    # CONFIGURATION FILE PATHS
    # ------------------------------------------------------------
    DEFAULT_CONFIG_FILE_PATH = File.join(__dir__, "ValeDesignSuite_Config_FrameworkConfigurator_DefaultNodeConfig.json")
    # endregion ----------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Configuration Loading Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Load Default Configuration from JSON File
    # ------------------------------------------------------------
    def self.load_default_configuration
        begin
            if File.exist?(DEFAULT_CONFIG_FILE_PATH)                         # <-- Check if config file exists
                config_content = File.read(DEFAULT_CONFIG_FILE_PATH)         # <-- Read config file content
                config_data = JSON.parse(config_content)                     # <-- Parse JSON content
                
                # Extract node defaults and convert to legacy format
                node_defaults = config_data["node_defaults"]                 # <-- Get node defaults section
                
                # Convert to legacy DEFAULT_CONFIG format for compatibility
                legacy_config = {
                    "nodeMetadata" => [
                        {
                            "NodeUniqueId" => "ND001",
                            "NodeName" => node_defaults["name"] || "Framework_Node",
                            "NodeVersion" => "1.0.0",
                            "NodeAuthor" => "Adam Noble - Noble Architecture",
                            "NodeDescription" => node_defaults["description"] || "A configurable framework node component",
                            "NodeNotes" => "Default node configuration loaded from external file",
                            "NodeCreatedDate" => Time.now.strftime("%d-%b-%Y"),
                            "NodeLastModified" => Time.now.strftime("%d-%b-%Y")
                        }
                    ],
                    "nodeComponents" => [
                        {
                            "ComponentUniqueId" => "ND001_MainColumn",
                            "ComponentName" => "Node_MainColumn",
                            "ComponentType" => "Column_Structure",
                            "ComponentMaterial" => node_defaults["material_properties"]["default_material"] || "Wood_Pine",
                            "ComponentDetailPath" => "Components/Columns/Standard_290mm_Column.skp",
                            "Position" => { 
                                "PosX_mm" => node_defaults["positioning"]["origin_x"] || 0, 
                                "PosY_mm" => node_defaults["positioning"]["origin_y"] || 0, 
                                "PosZ_mm" => node_defaults["positioning"]["origin_z"] || 0 
                            },
                            "Dimensions" => { 
                                "LenX_mm" => node_defaults["dimensions"]["width_mm"] || 70, 
                                "LenY_mm" => node_defaults["dimensions"]["depth_mm"] || 44, 
                                "LenZ_mm" => node_defaults["dimensions"]["height_mm"] || 70 
                            },
                            "Rotation" => { 
                                "RotX_deg" => node_defaults["positioning"]["rotation_degrees"] || 0, 
                                "RotY_deg" => 0, 
                                "RotZ_deg" => 0 
                            }
                        }
                    ],
                    "nodeConfiguration" => {
                        "Component_Default_Width_mm" => node_defaults["dimensions"]["width_mm"] || 70,
                        "Component_Default_Depth_mm" => node_defaults["dimensions"]["depth_mm"] || 44,
                        "Component_Default_Height_mm" => node_defaults["dimensions"]["height_mm"] || 70,
                        "Component_Default_NodeType" => node_defaults["node_type"] || "corner",
                        "Component_Default_Material" => node_defaults["material_properties"]["default_material"] || "Wood_Pine",
                        "Component_UI_MinWidth_mm" => node_defaults["dimensions"]["min_width_mm"] || 44,
                        "Component_UI_MaxWidth_mm" => node_defaults["dimensions"]["max_width_mm"] || 150,
                        "Component_UI_MinDepth_mm" => node_defaults["dimensions"]["min_depth_mm"] || 20,
                        "Component_UI_MaxDepth_mm" => node_defaults["dimensions"]["max_depth_mm"] || 100,
                        "Component_UI_MinHeight_mm" => node_defaults["dimensions"]["min_height_mm"] || 44,
                        "Component_UI_MaxHeight_mm" => node_defaults["dimensions"]["max_height_mm"] || 150,
                        "Component_DetailPath_CornerColumn" => "Components/Columns/Corner_Column.skp",
                        "Component_DetailPath_290mmColumn" => "Components/Columns/Standard_290mm_Column.skp",
                        "Component_DetailPath_390mmColumn" => "Components/Columns/Wide_390mm_Column.skp",
                        "Component_DetailPath_100mmColumn" => "Components/Columns/Narrow_100mm_Column.skp"
                    }
                }
                
                DebugTools.debug_node("Loaded default node configuration from external file")
                return legacy_config                                          # <-- Return converted configuration
                
            else
                DebugTools.debug_node("Default config file not found, using fallback configuration")
                return create_fallback_configuration                          # <-- Use fallback if file missing
            end
            
        rescue JSON::ParserError => e
            DebugTools.debug_node("Error parsing default config file: #{e.message}")
            return create_fallback_configuration                              # <-- Use fallback on parse error
        rescue => e
            DebugTools.debug_node("Error loading default config file: #{e.message}")
            return create_fallback_configuration                              # <-- Use fallback on any error
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Create Fallback Configuration
    # ---------------------------------------------------------------
    def self.create_fallback_configuration
        {
            "nodeMetadata" => [
                {
                    "NodeUniqueId" => "ND001",
                    "NodeName" => "Framework_Node",
                    "NodeVersion" => "1.0.0",
                    "NodeAuthor" => "Adam Noble - Noble Architecture",
                    "NodeDescription" => "A configurable framework node component with detailed column system",
                    "NodeNotes" => "Fallback node configuration",
                    "NodeCreatedDate" => Time.now.strftime("%d-%b-%Y"),
                    "NodeLastModified" => Time.now.strftime("%d-%b-%Y")
                }
            ],
            "nodeComponents" => [
                {
                    "ComponentUniqueId" => "ND001_MainColumn",
                    "ComponentName" => "Node_MainColumn",
                    "ComponentType" => "Column_Structure",
                    "ComponentMaterial" => "Wood_Pine",
                    "ComponentDetailPath" => "Components/Columns/Standard_290mm_Column.skp",
                    "Position" => { "PosX_mm" => 0, "PosY_mm" => 0, "PosZ_mm" => 0 },
                    "Dimensions" => { "LenX_mm" => 70, "LenY_mm" => 44, "LenZ_mm" => 70 },
                    "Rotation" => { "RotX_deg" => 0, "RotY_deg" => 0, "RotZ_deg" => 0 }
                }
            ],
            "nodeConfiguration" => {
                "Component_Default_Width_mm" => 70,
                "Component_Default_Depth_mm" => 44,
                "Component_Default_Height_mm" => 70,
                "Component_Default_NodeType" => "corner",
                "Component_Default_Material" => "Wood_Pine",
                "Component_UI_MinWidth_mm" => 44,
                "Component_UI_MaxWidth_mm" => 150,
                "Component_UI_MinDepth_mm" => 20,
                "Component_UI_MaxDepth_mm" => 100,
                "Component_UI_MinHeight_mm" => 44,
                "Component_UI_MaxHeight_mm" => 150,
                "Component_DetailPath_CornerColumn" => "Components/Columns/Corner_Column.skp",
                "Component_DetailPath_290mmColumn" => "Components/Columns/Standard_290mm_Column.skp",
                "Component_DetailPath_390mmColumn" => "Components/Columns/Wide_390mm_Column.skp",
                "Component_DetailPath_100mmColumn" => "Components/Columns/Narrow_100mm_Column.skp"
            }
        }
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Variables and State Management
# -----------------------------------------------------------------------------

    # MODULE VARIABLES | Component References and State
    # ------------------------------------------------------------
    DEFAULT_CONFIG          =   load_default_configuration                    # <-- Load configuration from external file
    @component_refs         =   {}                                            # <-- References to sub-components for transformations
    @node_component         =   nil                                           # <-- Current node component instance
    @config                 =   DEFAULT_CONFIG.dup                            # <-- Current configuration
    @dialog                 =   nil                                           # <-- HTML dialog instance
    @selection_observer     =   nil                                           # <-- Selection observer instance
    @node_id_counter        =   1                                             # <-- Counter for generating unique node IDs
    # endregion ----------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helper Functions - Core Utilities
# -----------------------------------------------------------------------------

    # CRITICAL HELPER FUNCTION | Convert Millimeters to Inches
    # ------------------------------------------------------------
    # Note : SketchUps Geometry Engine works in inches so this must be called and respected.
    def self.mm_to_inch(mm)
        mm * MM_TO_INCH                                                      # <-- Apply conversion factor
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Generate Next Node ID
    # ---------------------------------------------------------------
    def self.generate_next_node_id
        # Find the highest existing node ID number
        max_id = 0
        model = Sketchup.active_model
        
        if model && model.definitions
            model.definitions.each do |definition|
                dict = definition.attribute_dictionary(NODE_DICT_NAME)
                next unless dict
                
                config_json = dict["node_config"]
                next unless config_json
                
                begin
                    config = JSON.parse(config_json)
                    if config["nodeMetadata"] && config["nodeMetadata"].is_a?(Array)
                        config["nodeMetadata"].each do |metadata|
                            if metadata["NodeUniqueId"] && metadata["NodeUniqueId"].match(/^ND(\d{3})$/)
                                id_num = $1.to_i
                                max_id = id_num if id_num > max_id
                            end
                        end
                    end
                rescue JSON::ParserError
                    # Skip invalid JSON
                end
            end
        end
        
        next_id = max_id + 1
        return "ND#{format('%03d', next_id)}"                                # <-- Return formatted node ID
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Update Component IDs with Node ID
    # ---------------------------------------------------------------
    def self.update_component_ids_with_node_id(config, node_id)
        return unless config["nodeComponents"]
        
        config["nodeComponents"].each do |component|
            component_name = component["ComponentName"]
            case component_name
            when "Node_MainColumn"
                component["ComponentUniqueId"] = "#{node_id}_MainColumn"
            end
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Create Box Geometry at Origin
    # ---------------------------------------------------------------
    # Parameters:
    #   x, y, z: Coordinates for the origin corner (0,0,0 for origin-based system).
    #   width: Dimension of the box along the X-axis.
    #   depth: Dimension of the box along the Y-axis.
    #   height: Dimension of the box along the Z-axis.
    def self.create_box_at_origin(entities, x, y, z, width, depth, height)
        # Define points for the base face (on the XY plane at the given z height)
        points = [                                                           
            [x, y, z],
            [x + width, y, z],
            [x + width, y + depth, z],
            [x, y + depth, z]
        ]
        
        face = entities.add_face(points[0], points[1], points[2], points[3])  # <-- Create base face
        
        # Ensure the face normal is pointing upwards (+Z)
        if face.normal.z < 0
            face.reverse!                                                    # <-- Reverse face if normal is downwards
        end
        
        # Extrude the face upwards by the specified height
        face.pushpull(height)                                                 
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dictionary Functions - Store and Retrieve Node Config Data
# -----------------------------------------------------------------------------

    # FUNCTION | Save Node Configuration to Component Dictionary
    # ------------------------------------------------------------
    def self.save_config_to_component(component, config)
        return unless component && component.valid?                           # <-- Validate component exists
        
        dict = component.definition.attribute_dictionary(NODE_DICT_NAME, true)  # <-- Create dictionary if needed
        
        config_json = JSON.generate(config)                                  # <-- Serialize config to JSON
        dict["node_config"] = config_json                                    # <-- Store serialized config
        
        dict["node_config_formatted"] = format_json(config)                  # <-- Store formatted version
    end
    # ---------------------------------------------------------------

    # FUNCTION | Load Node Configuration from Component Dictionary
    # ------------------------------------------------------------
    def self.load_config_from_component(component)
        return DEFAULT_CONFIG.dup unless component && component.valid?        # <-- Return default if invalid
        
        dict = component.definition.attribute_dictionary(NODE_DICT_NAME)      # <-- Get dictionary if exists
        return DEFAULT_CONFIG.dup unless dict                                # <-- Return default if no dict
        
        config_json = dict["node_config"]                                    # <-- Get config JSON from dict
        return DEFAULT_CONFIG.dup unless config_json                         # <-- Return default if no config
        
        begin
            config = JSON.parse(config_json)                                 # <-- Parse JSON config
            return config
        rescue
            return DEFAULT_CONFIG.dup                                        # <-- Return default on parse error
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Format JSON with Column Alignment
    # ---------------------------------------------------------------
    def self.format_json(json_obj)
        JSON.pretty_generate(json_obj)                                       # <-- Generate formatted JSON
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Geometry Functions - Create and Update Node Geometry
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Update Node Dimensions in Configuration
    # ---------------------------------------------------------------
    def self.update_node_dimensions_in_config(config_obj, width_mm, depth_mm, height_mm)
        return unless config_obj["nodeComponents"]
        
        config_obj["nodeComponents"].each do |component|
            case component["ComponentName"]
            when "Node_MainColumn"
                component["Position"]["PosX_mm"] = 0                         # <-- Origin-based positioning
                component["Position"]["PosY_mm"] = 0
                component["Position"]["PosZ_mm"] = 0
                component["Dimensions"]["LenX_mm"] = width_mm
                component["Dimensions"]["LenY_mm"] = depth_mm
                component["Dimensions"]["LenZ_mm"] = height_mm
            end
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Update Node Type and Detail Path in Configuration
    # ---------------------------------------------------------------
    def self.update_node_type_in_config(config_obj, node_type)
        return unless config_obj["nodeComponents"] && config_obj["nodeConfiguration"]
        
        # Update the node type in configuration
        config_obj["nodeConfiguration"]["Component_Default_NodeType"] = node_type
        
        # Update the detail path based on node type
        detail_path_key = "Component_DetailPath_#{node_type.gsub('Column_', '')}"
        detail_path = config_obj["nodeConfiguration"][detail_path_key]
        
        config_obj["nodeComponents"].each do |component|
            if component["ComponentName"] == "Node_MainColumn"
                component["ComponentDetailPath"] = detail_path if detail_path
                break
            end
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Prepare Full Configuration for New Node Creation
    # ---------------------------------------------------------------
    def self.prepare_config_for_creation(width_mm, depth_mm, height_mm, node_type, material)
        config = DEFAULT_CONFIG.dup
        node_id = generate_next_node_id                                      # <-- Generate unique node ID

        # Update metadata with new node ID and current timestamp
        config["nodeMetadata"][0]["NodeUniqueId"] = node_id
        config["nodeMetadata"][0]["NodeName"] = "Node_#{node_id}"
        config["nodeMetadata"][0]["NodeLastModified"] = Time.now.strftime("%d-%b-%Y")

        # Update component IDs with node ID
        update_component_ids_with_node_id(config, node_id)

        # Update configuration values
        node_config = config["nodeConfiguration"]
        node_config["Component_Default_Width_mm"] = width_mm
        node_config["Component_Default_Depth_mm"] = depth_mm
        node_config["Component_Default_Height_mm"] = height_mm
        node_config["Component_Default_NodeType"] = node_type
        node_config["Component_Default_Material"] = material
        
        # Update node dimensions and type
        update_node_dimensions_in_config(config, width_mm, depth_mm, height_mm)
        update_node_type_in_config(config, node_type)
        
        return config
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create Initial Node Geometry from Configuration
    # ---------------------------------------------------------------
    def self.create_node_geometry(config)
        return nil unless validate_node_creation_preconditions               # Validate preconditions for creation
        
        model = Sketchup.active_model                                        # Get active SketchUp model
        model.start_operation("Create Node", true)                          # Start operation for undo support
        
        node_instance = create_main_node_component(config)                   # Create main component structure
        create_all_node_subcomponents(node_instance.definition, config)     # Create all sub-components
        finalize_node_creation(node_instance, config)                       # Finalize and save node
        
        model.commit_operation                                               # Commit the operation
        
        @node_component = node_instance                                      # Store node component instance
        return node_instance                                                 # Return created node instance
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Validate Preconditions for Node Creation
    # ---------------------------------------------------------------
    def self.validate_node_creation_preconditions
        return false unless Sketchup.active_model                           # Check active model exists
        return true                                                          # All preconditions met
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create Main Node Component Structure
    # ---------------------------------------------------------------
    def self.create_main_node_component(config)
        model = Sketchup.active_model                                        # Get active model reference
        
        # Get node ID and node name from metadata
        node_id = config["nodeMetadata"][0]["NodeUniqueId"] rescue "ND001"
        node_name = config["nodeMetadata"][0]["NodeName"] rescue "Node_Component"
        
        node_def = model.definitions.add("#{node_name}_#{node_id}")          # Create main component definition with node ID
        node_instance = model.active_entities.add_instance(node_def, Geom::Transformation.new)  # Create instance
        node_instance.name = node_name                                       # Set component name
        
        @component_refs = {}                                                 # Initialize component references hash
        return node_instance                                                 # Return created node instance
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create All Node Sub-Components
    # ---------------------------------------------------------------
    def self.create_all_node_subcomponents(node_definition, config)
        create_main_column_component(node_definition, config)               # Create main column component
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Main Column Component
    # ---------------------------------------------------------------
    def self.create_main_column_component(node_definition, config)
        return unless config["nodeComponents"]
        
        config["nodeComponents"].each do |component_data|
            if component_data["ComponentType"] == "Column_Structure"
                create_column_component_from_data(node_definition, component_data)
                break
            end
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Create Column Component from Data
    # ---------------------------------------------------------------
    def self.create_column_component_from_data(node_definition, component_data)
        column_group = node_definition.entities.add_group                   # Create group for column component
        column_group.name = component_data["ComponentName"]                 # Set group name
        
        create_box_at_origin(                                               # Create box geometry at origin
            column_group.entities,
            mm_to_inch(component_data["Position"]["PosX_mm"]),              # Convert position to inches
            mm_to_inch(component_data["Position"]["PosY_mm"]),
            mm_to_inch(component_data["Position"]["PosZ_mm"]),
            mm_to_inch(component_data["Dimensions"]["LenX_mm"]),            # Convert dimensions to inches
            mm_to_inch(component_data["Dimensions"]["LenY_mm"]),
            mm_to_inch(component_data["Dimensions"]["LenZ_mm"])
        )
        
        @component_refs[component_data["ComponentName"]] = column_group      # Store component reference
        return column_group                                                 # Return created column group
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Finalize Node Creation Process
    # ---------------------------------------------------------------
    def self.finalize_node_creation(node_instance, config)
        save_config_to_component(node_instance, config)                     # Save config to component dictionary
        
        node_config = config["nodeConfiguration"]
        material = node_config["Component_Default_Material"] || "natural-wood"  # Get material
        add_materials(node_instance.definition.entities, material)          # Apply materials to components
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Node Geometry Manipulation - Post Creation Updates
# -----------------------------------------------------------------------------

    # FUNCTION | Update Node Geometry Based on New Configuration
    # ------------------------------------------------------------
    def self.update_node_geometry(width_mm, depth_mm, height_mm, node_type, material)
        return unless validate_node_update_preconditions                     # <-- Validate preconditions for update
        
        model = Sketchup.active_model                                        # <-- Get active model
        model.start_operation("Update Node", true)                          # <-- Start operation for undo support
        
        update_configuration_values(width_mm, depth_mm, height_mm, node_type, material)  # <-- Update internal configuration
        rebuild_node_geometry                                                # <-- Rebuild node with new parameters
        
        save_config_to_component(@node_component, @config)                  # <-- Save updated config to dictionary
        model.commit_operation                                               # <-- Commit the operation
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Validate Preconditions for Node Update
    # ---------------------------------------------------------------
    def self.validate_node_update_preconditions
        return false unless @node_component && @node_component.valid?        # <-- Check node component exists and valid
        return false unless Sketchup.active_model                           # <-- Check active model exists
        return true                                                          # <-- All preconditions met
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Update Internal Configuration Values
    # ---------------------------------------------------------------
    def self.update_configuration_values(width_mm, depth_mm, height_mm, node_type, material)
        update_node_configuration(width_mm, depth_mm, height_mm, node_type, material)  # <-- Update node config
        update_node_dimensions_configuration(width_mm, depth_mm, height_mm)  # <-- Update dimensions config
        update_metadata_timestamp                                           # <-- Update last modified timestamp
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Update Node Configuration
    # ---------------------------------------------------------------
    def self.update_node_configuration(width_mm, depth_mm, height_mm, node_type, material)
        node_config = @config["nodeConfiguration"]
        node_config["Component_Default_Width_mm"] = width_mm                 # <-- Set new width
        node_config["Component_Default_Depth_mm"] = depth_mm                 # <-- Set new depth
        node_config["Component_Default_Height_mm"] = height_mm               # <-- Set new height
        node_config["Component_Default_NodeType"] = node_type               # <-- Set new node type
        node_config["Component_Default_Material"] = material                # <-- Set new material
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Update Node Dimensions Configuration
    # ---------------------------------------------------------------
    def self.update_node_dimensions_configuration(width_mm, depth_mm, height_mm)
        update_node_dimensions_in_config(@config, width_mm, depth_mm, height_mm)  # <-- Use existing helper function
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Update Metadata Timestamp
    # ---------------------------------------------------------------
    def self.update_metadata_timestamp
        if @config["nodeMetadata"] && @config["nodeMetadata"].is_a?(Array) && !@config["nodeMetadata"].empty?
            @config["nodeMetadata"][0]["NodeLastModified"] = Time.now.strftime("%d-%b-%Y")  # <-- Update timestamp
        end
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Rebuild Node Geometry
    # ---------------------------------------------------------------
    def self.rebuild_node_geometry
        clear_existing_geometry                                              # <-- Clear existing geometry
        create_all_node_subcomponents(@node_component.definition, @config)  # <-- Recreate all components
        
        node_config = @config["nodeConfiguration"]
        material = node_config["Component_Default_Material"]
        add_materials(@node_component.definition.entities, material)        # <-- Reapply materials
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Clear Existing Geometry
    # ---------------------------------------------------------------
    def self.clear_existing_geometry
        @node_component.definition.entities.clear!                          # <-- Clear all entities
        @component_refs.clear                                               # <-- Clear component references
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Material Functions - Apply Textures and Materials
# -----------------------------------------------------------------------------

    # FUNCTION | Add Materials to Node Components
    # ------------------------------------------------------------
    def self.add_materials(entities, material = "natural-wood")
        model = Sketchup.active_model                                        # <-- Get active model
        materials = model.materials                                          # <-- Get materials collection
        
        node_material = create_node_material(materials, material)            # <-- Create node material
        
        apply_materials_to_containers(entities, node_material)              # <-- Apply materials to containers
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Node Material with Color Support
    # ---------------------------------------------------------------
    def self.create_node_material(materials, material_type)
        material_name = "NodeMaterial_#{material_type}"                      # <-- Create unique material name
        node_material = materials[material_name]                             # <-- Check if material exists
        
        unless node_material
            node_material = materials.add(material_name)                     # <-- Create new node material
            node_material.color = get_material_color_rgb(material_type)      # <-- Set color based on selection
        end
        
        return node_material                                                 # <-- Return node material
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Get RGB Values for Material Colors
    # ---------------------------------------------------------------
    def self.get_material_color_rgb(material_type)
        case material_type
        when "natural-wood"
            return [168, 145, 111]                                           # <-- Traditional oak color (#a8916f)
        when "pointing"
            return [232, 226, 208]                                           # <-- Farrow & Ball Pointing (#e8e2d0)
        when "card-room-green"
            return [127, 132, 113]                                           # <-- Farrow & Ball Card Room Green (#7f8471)
        when "borrowed-light"
            return [221, 230, 232]                                           # <-- Farrow & Ball Borrowed Light (#dde6e8)
        else
            return [168, 145, 111]                                           # <-- Default to natural wood
        end
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Apply Materials to Containers
    # ---------------------------------------------------------------
    def self.apply_materials_to_containers(entities, node_material)
        entities.grep(Sketchup::Group).each do |group|                      # <-- Iterate through all groups
            group.material = node_material                                   # <-- Apply node material directly to container
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Selection Observer - Monitor Selection Changes
# -----------------------------------------------------------------------------

    # CLASS | Node Selection Observer for Multi-Node Support
    # ------------------------------------------------------------
    class NodeSelectionObserver < Sketchup::SelectionObserver
        def onSelectionBulkChange(selection)
            return unless FrameworkNodeConfigurator.dialog_visible?          # <-- Skip if dialog not open
            
            if selection.size == 1 && selection[0].is_a?(Sketchup::ComponentInstance)  # <-- Check single component selected
                component = selection[0]
                
                dict = component.definition.attribute_dictionary(NODE_DICT_NAME)  # <-- Check for node config dictionary
                if dict && dict["node_config"]
                    config = FrameworkNodeConfigurator.load_config_from_component(component)  # <-- Load config and update dialog
                    FrameworkNodeConfigurator.set_node_component(component, config)
                end
            end
        end
    end
    # endregion ----------------------------------------------------

    # HELPER FUNCTION | Check if Dialog is Visible
    # ---------------------------------------------------------------
    def self.dialog_visible?
        @dialog && @dialog.visible?                                          # <-- Return dialog visibility state
    end
    # ---------------------------------------------------------------

    # FUNCTION | Set Node Component and Update Dialog
    # ---------------------------------------------------------------
    def self.set_node_component(component, config)
        @node_component = component                                          # <-- Set current node component
        @config = config                                                     # <-- Set current config
        
        @component_refs = {}                                                 # <-- Get references to sub-components
        component.definition.entities.grep(Sketchup::Group).each do |group|
            node_group_names = ["Node_MainColumn"]
            @component_refs[group.name] = group if node_group_names.include?(group.name)
        end
        
        @dialog.execute_script("window.setInitialConfig('#{JSON.generate(@config).gsub("'", "\\\\'")}');") if @dialog && @dialog.visible?  # <-- Update dialog with loaded config
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Main Initialization - Set Up Tool and Show Dialog
# -----------------------------------------------------------------------------

    # FUNCTION | Initialize the Node Configurator Tool
    # ------------------------------------------------------------
    def self.init
        @node_component = nil                                                # <-- Initialize node component reference
        @config = nil                                                        # <-- Initialize configuration data
        @component_refs = {}                                                 # <-- Initialize component references
        
        @selection_observer = NodeSelectionObserver.new                     # <-- Create selection observer instance
        Sketchup.active_model.selection.add_observer(@selection_observer)
        
        show_dialog                                                          # <-- Show the dialog
    end
    # ---------------------------------------------------------------

    # FUNCTION | Show Node Configurator Dialog
    # ------------------------------------------------------------
    def self.show_dialog
        if @dialog && @dialog.visible?                                       # <-- Return if dialog already showing
            @dialog.bring_to_front
            return
        end
        
        @dialog = UI::HtmlDialog.new(                                        # <-- Create the dialog
            dialog_title: "Framework Node Configurator",
            preferences_key: "FrameworkNodeConfigurator",
            width: 450,
            height: 700,
            left: 200,
            top: 200,
            resizable: true
        )
        
        html_content = create_dialog_html_content                            # <-- Generate HTML content
        @dialog.set_html(html_content)                                       # <-- Set dialog HTML content
        
        setup_dialog_callbacks                                               # <-- Set up dialog callbacks
        @dialog.show                                                         # <-- Show the dialog
        
        check_for_existing_node_selection                                    # <-- Check for existing node selection
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Check for Existing Node Selection
    # ---------------------------------------------------------------
    def self.check_for_existing_node_selection
        model = Sketchup.active_model
        return unless model && model.selection.size == 1
        
        selected = model.selection[0]
        if selected.is_a?(Sketchup::ComponentInstance)
            dict = selected.definition.attribute_dictionary(NODE_DICT_NAME)
            if dict && dict["node_config"]
                config = load_config_from_component(selected)
                set_node_component(selected, config)
            end
        end
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Dialog HTML Content
    # ---------------------------------------------------------------
    def self.create_dialog_html_content
        <<-HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <title>Framework Node Configurator</title>
          <style>
            /* CSS Variables - Vale Design Suite Standards */
            :root {
                --FontCol_ValeTitleTextColour      : #172b3a;
                --FontCol_ValeTitleHeadingColour   : #172b3a;
                --FontCol_ValeStandardTextColour   : #1e1e1e;
                --FontCol_ValeLinkTextColour       : #336699;
                --FontCol_ValeVisitedTextColour    : #663399;
                --FontCol_ValeHoverTextColour      : #3377aa;
                --FontCol_ValeActiveTextColour     : #006600;
                --FontCol_ValeDisabledTextColour   : #999999;
                font-size                          : 14px;
                --FontSize_ValeTitleText           : 1.4rem;
                --FontSize_ValeTitleHeading01      : 1.10rem;
                --FontSize_ValeTitleHeading02      : 1.00rem;
                --FontSize_ValeTitleHeading03      : 0.95rem;
                --FontSize_ValeTitleHeading04      : 0.90rem;
                --FontSize_ValeStandardText        : 0.85rem;
                --FontType_ValeTitleText           : 'Arial', sans-serif;
                --FontType_ValeTitleHeading01      : 'Arial', sans-serif;
                --FontType_ValeTitleHeading02      : 'Arial', sans-serif;
                --FontType_ValeTitleHeading03      : 'Arial', sans-serif;
                --FontType_ValeTitleHeading04      : 'Arial', sans-serif;
                --FontType_ValeStandardText        : 'Arial', sans-serif;
                --FontType_ValeLightText           : 'Arial', sans-serif;
                --ValeBackgroundColor              : #f0f0f0;
                --ValeContentBackground            : #ffffff;
                --ValeBorderColor                  : #dddddd;
                --ValeHighlightColor               : #006600;
                --ValePrimaryButtonBg              : #4CAF50;
                --ValePrimaryButtonHoverBg         : #45a049;
                --ValePrimaryButtonText            : #ffffff;
                --ValeSecondaryButtonBg            : #172b3a;
                --ValeSecondaryButtonHoverBg       : #2a4a63;
                --ValeSecondaryButtonText          : #ffffff;
                --ValeSliderActiveColor            : #0066cc;
                --ValeNodeFrameColor               : #8B4513;
            }

            /* Base Layout Styles */
            html, body {
                margin                             : 0;
                padding                            : 0;
                font-family                        : var(--FontType_ValeStandardText);
                font-size                          : var(--FontSize_ValeStandardText);
                color                              : var(--FontCol_ValeStandardTextColour);
                background-color                   : var(--ValeBackgroundColor);
                height                             : 100vh;
                overflow                           : hidden;
            }

            body {
                padding                            : 20px;
                box-sizing                         : border-box;
                display                            : flex;
                flex-direction                     : column;
            }

            /* Typography Styles */
            h1 {
                font-family                        : var(--FontType_ValeTitleText);
                font-size                          : var(--FontSize_ValeTitleText);
                color                              : var(--FontCol_ValeTitleTextColour);
                text-align                         : center;
                margin-top                         : 0;
                margin-bottom                      : 20px;
            }

            /* Section and Container Styles */
            .section-title {
                font-family                        : var(--FontType_ValeTitleHeading04);
                font-size                          : var(--FontSize_ValeTitleHeading04);
                font-weight                        : bold;
                color                              : var(--FontCol_ValeTitleHeadingColour);
                margin-top                         : 25px;
                margin-bottom                      : 15px;
                border-bottom                      : 2px solid var(--ValeHighlightColor);
                padding-bottom                     : 8px;
                text-transform                     : uppercase;
                letter-spacing                     : 0.5px;
            }

            .slider-container {
                background-color                   : var(--ValeContentBackground);
                border                             : 1px solid var(--ValeBorderColor);
                border-radius                      : 6px;
                padding                            : 15px;
                margin-bottom                      : 15px;
                box-shadow                         : 0 2px 4px rgba(0, 0, 0, 0.05);
                transition                         : box-shadow 0.2s ease;
            }

            .slider-container:hover {
                box-shadow                         : 0 4px 8px rgba(0, 0, 0, 0.1);
            }

            /* Slider Group Styles */
            .slider-group {
                margin-bottom                      : 20px;
            }

            .slider-group:last-child {
                margin-bottom                      : 0;
            }

            /* Form Element Styles */
            label {
                display                            : block;
                font-family                        : var(--FontType_ValeTitleHeading04);
                font-size                          : var(--FontSize_ValeTitleHeading04);
                font-weight                        : bold;
                color                              : var(--FontCol_ValeTitleHeadingColour);
                margin-bottom                      : 8px;
                letter-spacing                     : 0.3px;
            }

            input[type="range"] {
                width                              : 100%;
                height                             : 8px;
                margin                             : 15px 0;
                appearance                         : none;
                background                         : var(--ValeBorderColor);
                border-radius                      : 4px;
                outline                            : none;
                cursor                             : pointer;
            }

            input[type="range"]::-webkit-slider-thumb {
                appearance                         : none;
                width                              : 20px;
                height                             : 20px;
                background                         : var(--ValeSliderActiveColor);
                border-radius                      : 50%;
                cursor                             : pointer;
                transition                         : all 0.2s ease;
            }

            input[type="range"]::-webkit-slider-thumb:hover {
                background                         : var(--ValeHighlightColor);
                transform                          : scale(1.1);
            }

            input[type="range"]::-moz-range-thumb {
                width                              : 20px;
                height                             : 20px;
                background                         : var(--ValeSliderActiveColor);
                border-radius                      : 50%;
                cursor                             : pointer;
                border                             : none;
                transition                         : all 0.2s ease;
            }

            /* Value Input Styles */
            .value-input-wrapper {
                display                            : flex;
                align-items                        : center;
                justify-content                    : center;
                background-color                   : rgba(0, 102, 204, 0.1);
                padding                            : 4px 8px;
                border-radius                      : 4px;
                margin-top                         : 8px;
                border                             : 1px solid rgba(0, 102, 204, 0.2);
            }

            .value-input {
                font-size                          : 0.8rem;
                font-weight                        : bold;
                color                              : var(--ValeSliderActiveColor);
                background-color                   : transparent;
                border                             : none;
                text-align                         : right;
                width                              : 70px;
                -moz-appearance                    : textfield;
            }

            .value-input::-webkit-outer-spin-button,
            .value-input::-webkit-inner-spin-button {
                -webkit-appearance                 : none;
                margin                             : 0;
            }

            .unit-label {
                font-size                          : 0.8rem;
                font-weight                        : bold;
                color                              : var(--ValeSliderActiveColor);
                margin-left                        : 5px;
            }

            /* Node Type Selection Styles */
            .node-type-container {
                background-color                   : var(--ValeContentBackground);
                border                             : 1px solid var(--ValeBorderColor);
                border-radius                      : 6px;
                padding                            : 15px;
                margin-bottom                      : 15px;
            }

            .node-type-grid {
                display                            : grid;
                grid-template-columns              : repeat(2, 1fr);
                gap                                : 10px;
                margin-top                         : 10px;
            }

            .node-type-option {
                border                             : 2px solid var(--ValeBorderColor);
                border-radius                      : 6px;
                padding                            : 10px;
                text-align                         : center;
                cursor                             : pointer;
                transition                         : all 0.2s ease;
                background-color                   : var(--ValeContentBackground);
            }

            .node-type-option:hover {
                border-color                       : var(--ValeHighlightColor);
                transform                          : translateY(-2px);
                box-shadow                         : 0 4px 8px rgba(0, 0, 0, 0.1);
            }

            .node-type-option.selected {
                border-color                       : var(--ValeHighlightColor);
                border-width                       : 3px;
                background-color                   : rgba(0, 102, 0, 0.05);
            }

            .node-type-name {
                font-size                          : 12px;
                font-weight                        : bold;
                color                              : var(--FontCol_ValeTitleHeadingColour);
                margin-bottom                      : 5px;
            }

            .node-type-dimensions {
                font-size                          : 10px;
                color                              : var(--FontCol_ValeStandardTextColour);
                opacity                            : 0.8;
            }

            /* Button Styles */
            button {
                background-color                   : var(--ValePrimaryButtonBg);
                color                              : var(--ValePrimaryButtonText);
                border                             : none;
                padding                            : 12px 20px;
                font-family                        : var(--FontType_ValeStandardText);
                font-size                          : 1rem;
                font-weight                        : bold;
                text-align                         : center;
                text-decoration                    : none;
                display                            : inline-block;
                margin                             : 15px 0;
                cursor                             : pointer;
                border-radius                      : 6px;
                width                              : 100%;
                transition                         : all 0.3s ease;
                box-shadow                         : 0 2px 4px rgba(0, 0, 0, 0.1);
                text-transform                     : uppercase;
                letter-spacing                     : 0.5px;
            }

            button:hover {
                background-color                   : var(--ValePrimaryButtonHoverBg);
                transform                          : translateY(-2px);
                box-shadow                         : 0 4px 8px rgba(0, 0, 0, 0.15);
            }

            button:active {
                transform                          : translateY(0);
                box-shadow                         : 0 2px 4px rgba(0, 0, 0, 0.1);
            }

            /* Footer Styles */
            .footer {
                margin-top                         : auto;
                padding-top                        : 20px;
                font-size                          : 11px;
                color                              : var(--FontCol_ValeDisabledTextColour);
                text-align                         : center;
                border-top                         : 1px solid var(--ValeBorderColor);
                font-style                         : italic;
                letter-spacing                     : 0.2px;
            }

            /* Responsive Adjustments */
            @media (max-width: 480px) {
                body {
                    padding                        : 15px;
                }
                
                .slider-container {
                    padding                        : 12px;
                }
                
                .node-type-grid {
                    grid-template-columns          : 1fr;
                }
            }
          </style>
        </head>

    <!-- ----------------------------------------------------------------- -->
    <!-- REGION  |  User Interface HTML Layout & Elements                  -->
    <!-- ----------------------------------------------------------------- -->
        <body>
        <h1>Framework Node Configurator</h1>
    
        <div class="section-title">Node Dimensions</div>
        
        <div class="slider-container">
        <div class="slider-group">
            <label for="width-slider">Node Width (mm):</label>
            <input type="range" id="width-slider" min="100" max="390" value="290" oninput="updateWidth(this.value)">
            <div class="value-input-wrapper">
                <input type="number" id="width-value-input" class="value-input" step="1" value="290" onchange="handleTextInputChange('width', event)" onkeydown="handleTextInputChange('width', event)">
                <span class="unit-label">mm</span>
            </div>
        </div>
        
        <div class="slider-group">
            <label for="depth-slider">Node Depth (mm):</label>
            <input type="range" id="depth-slider" min="94" max="94" value="94" oninput="updateDepth(this.value)" disabled style="opacity: 0.5;">
            <div class="value-input-wrapper">
                <input type="number" id="depth-value-input" class="value-input" step="1" value="94" readonly style="opacity: 0.5;">
                <span class="unit-label">mm</span>
            </div>
            <small>Depth is fixed at 94mm for framework compatibility</small>
        </div>
        
        <div class="slider-group">
            <label for="height-slider">Node Height (mm):</label>
            <input type="range" id="height-slider" min="1500" max="3000" value="2000" oninput="updateHeight(this.value)">
            <div class="value-input-wrapper">
                <input type="number" id="height-value-input" class="value-input" step="1" value="2000" onchange="handleTextInputChange('height', event)" onkeydown="handleTextInputChange('height', event)">
                <span class="unit-label">mm</span>
            </div>
        </div>
        </div>
        
        <!-- ---------------------------------------------------------------- -->
        
        <!-- ----------------------------------------------------------------- -->
        <!-- UI MENU | Node Type Selection Controls                            -->
        <!-- ----------------------------------------------------------------- -->
        
        <div class="section-title">Node Type</div>
        
        <div class="node-type-container">
            <div class="node-type-grid">
                <div class="node-type-option" data-type="Column_CornerColumn" onclick="selectNodeType('Column_CornerColumn')">
                    <div class="node-type-name">Corner Column</div>
                    <div class="node-type-dimensions">290×94×2000mm</div>
                </div>
                <div class="node-type-option selected" data-type="Column_290mm" onclick="selectNodeType('Column_290mm')">
                    <div class="node-type-name">290mm Column</div>
                    <div class="node-type-dimensions">290×94×2000mm</div>
                </div>
                <div class="node-type-option" data-type="Column_390mm" onclick="selectNodeType('Column_390mm')">
                    <div class="node-type-name">390mm Column</div>
                    <div class="node-type-dimensions">390×94×2000mm</div>
                </div>
                <div class="node-type-option" data-type="Column_100mm" onclick="selectNodeType('Column_100mm')">
                    <div class="node-type-name">100mm Column</div>
                    <div class="node-type-dimensions">100×94×2000mm</div>
                </div>
            </div>
        </div>
        
        <!-- ---------------------------------------------------------------- -->
          
          <button id="create-node-btn" onclick="createNode()">Create New Node</button>
          
          <div class="footer">
            Vale Design Suite - Framework Node Configurator Tool v1.0.0
          </div>
        <!-- endregion ----------------------------------------------------------------- -->
          
          <script>

            // -----------------------------------------------------------------------------
            // REGION | Front End Javascript Section
            // -----------------------------------------------------------------------------

            // MODULE VARIABLES | Node Configuration State Variables
            // ------------------------------------------------------------
            let widthValue          = 290;                                   // <-- Node width in millimeters
            let depthValue          = 94;                                    // <-- Node depth in millimeters (fixed)
            let heightValue         = 2000;                                  // <-- Node height in millimeters  
            let selectedNodeType    = 'Column_290mm';                       // <-- Currently selected node type
            let selectedMaterial    = 'natural-wood';                       // <-- Currently selected material
            let currentNodeComponent = null;                                 // <-- Reference to currently selected node component
            //  -----------------------------------------------------------

            // FUNCTION | Initialize Dialog from Configuration Data
            // ------------------------------------------------------------
            function initFromConfig(config) {
                if (!config) return;                                         // <-- Exit if no config provided
                
                try {
                    const nodeConfig = config.nodeConfiguration;             // <-- Get node configuration object
                    
                    // UPDATE INTERNAL STATE VARIABLES
                    widthValue = nodeConfig.Component_Default_Width_mm;                       // <-- Set width from config
                    depthValue = nodeConfig.Component_Default_Depth_mm;                       // <-- Set depth from config
                    heightValue = nodeConfig.Component_Default_Height_mm;                     // <-- Set height from config
                    selectedNodeType = nodeConfig.Component_Default_NodeType || 'Column_290mm'; // <-- Set node type from config
                    selectedMaterial = nodeConfig.Component_Default_Material || 'natural-wood'; // <-- Set material from config
                    
                    // UPDATE SLIDER VALUES AND INPUT FIELDS
                    document.getElementById('width-slider').value = widthValue;
                    document.getElementById('width-value-input').value = widthValue;
                    
                    document.getElementById('depth-slider').value = depthValue;
                    document.getElementById('depth-value-input').value = depthValue;
                    
                    document.getElementById('height-slider').value = heightValue;
                    document.getElementById('height-value-input').value = heightValue;

                    // UPDATE NODE TYPE SELECTION
                    selectNodeType(selectedNodeType, false); // false to prevent immediate updateNode call during init
                    
                    // UPDATE SLIDER CONSTRAINTS FROM CONFIGURATION
                    document.getElementById('width-slider').min = nodeConfig.Component_UI_MinWidth_mm;         // <-- Set minimum width constraint
                    document.getElementById('width-slider').max = nodeConfig.Component_UI_MaxWidth_mm;         // <-- Set maximum width constraint
                    
                    document.getElementById('height-slider').min = nodeConfig.Component_UI_MinHeight_mm;       // <-- Set minimum height constraint
                    document.getElementById('height-slider').max = nodeConfig.Component_UI_MaxHeight_mm;       // <-- Set maximum height constraint
                    
                } catch (e) {
                    console.error('Error initializing from config:', e);     // <-- Log initialization errors
                }
            }
            // ---------------------------------------------------------------

            // FUNCTION | Select Node Type and Update State
            // ---------------------------------------------------------------
            function selectNodeType(nodeType, triggerUpdate = true) {
                // REMOVE SELECTED STATE FROM ALL NODE TYPE OPTIONS
                document.querySelectorAll('.node-type-option').forEach(option => {   // <-- Iterate through all node type options
                    option.classList.remove('selected');                     // <-- Remove selected class
                });
                
                // ADD SELECTED STATE TO CLICKED OPTION
                const currentOption = document.querySelector(`[data-type="${nodeType}"]`);
                if (currentOption) {
                    currentOption.classList.add('selected');                 // <-- Add selected class to clicked option
                }
                
                // UPDATE INTERNAL NODE TYPE STATE
                selectedNodeType = nodeType;                                  // <-- Store selected node type
                
                // UPDATE WIDTH CONSTRAINTS BASED ON NODE TYPE
                updateWidthConstraintsForNodeType(nodeType);                 // <-- Update width constraints
                
                // UPDATE NODE IF CURRENTLY SELECTED NODE EXISTS AND triggerUpdate is true
                if (currentNodeComponent && triggerUpdate) {                 // <-- Check if a node is currently selected
                    updateNode();                                             // <-- Apply node type change to selected node
                }
            }
            // ---------------------------------------------------------------

            // HELPER FUNCTION | Update Width Constraints for Node Type
            // ---------------------------------------------------------------
            function updateWidthConstraintsForNodeType(nodeType) {
                const widthSlider = document.getElementById('width-slider');
                const widthInput = document.getElementById('width-value-input');
                
                switch (nodeType) {
                    case 'Column_CornerColumn':
                    case 'Column_290mm':
                        widthSlider.min = 290; widthSlider.max = 290;
                        if (widthValue !== 290) {
                            widthValue = 290;
                            widthSlider.value = 290;
                            widthInput.value = 290;
                        }
                        break;
                    case 'Column_390mm':
                        widthSlider.min = 390; widthSlider.max = 390;
                        if (widthValue !== 390) {
                            widthValue = 390;
                            widthSlider.value = 390;
                            widthInput.value = 390;
                        }
                        break;
                    case 'Column_100mm':
                        widthSlider.min = 100; widthSlider.max = 100;
                        if (widthValue !== 100) {
                            widthValue = 100;
                            widthSlider.value = 100;
                            widthInput.value = 100;
                        }
                        break;
                }
            }
            // ---------------------------------------------------------------

            // HELPER FUNCTION | Handle Text Input Change for Dimensions
            // ---------------------------------------------------------------
            function handleTextInputChange(type, event) {
                if (event && event.type === 'keydown' && event.key !== 'Enter') {
                    return; // Only process keydown if it's Enter, or if it's 'change' event (blur)
                }

                let inputElementId, sliderElementId, valueToUpdateFunc, currentValue;
                let minVal, maxVal;

                switch (type) {
                    case 'width':
                        inputElementId = 'width-value-input'; sliderElementId = 'width-slider'; 
                        valueToUpdateFunc = (v) => { widthValue = v; }; currentValue = widthValue;
                        break;
                    case 'height':
                        inputElementId = 'height-value-input'; sliderElementId = 'height-slider'; 
                        valueToUpdateFunc = (v) => { heightValue = v; }; currentValue = heightValue;
                        break;
                    default: return;
                }

                const inputElement = document.getElementById(inputElementId);
                const sliderElement = document.getElementById(sliderElementId);
                minVal = parseInt(sliderElement.min);
                maxVal = parseInt(sliderElement.max);

                let newValue = parseInt(inputElement.value);

                if (isNaN(newValue)) {
                    newValue = currentValue; // Revert to current global value if input is invalid
                } else {
                    newValue = Math.round(newValue); // Ensure whole number
                    if (newValue < minVal) newValue = minVal;
                    if (newValue > maxVal) newValue = maxVal;
                }

                inputElement.value = newValue;    // Update input field with validated/corrected value
                sliderElement.value = newValue;   // Sync slider
                valueToUpdateFunc(newValue);      // Update the global JS variable

                if (currentNodeComponent) {       // <-- Update selected node if one exists
                    updateNode();
                }
            }
            // ---------------------------------------------------------------

            // FUNCTION | Update Node Width Value and Display
            // ---------------------------------------------------------------
            function updateWidth(value) {
                const newValue = parseInt(value)
                widthValue = newValue;                                       // <-- Parse and store new width value
                document.getElementById('width-value-input').value = newValue; // <-- Update width input field
                if (currentNodeComponent) {                                  // <-- Check if a node is selected
                    updateNode();                                            // <-- Apply width change to selected node
                }
            }
            // ---------------------------------------------------------------

            // FUNCTION | Update Node Depth Value and Display (Fixed)
            // ---------------------------------------------------------------
            function updateDepth(value) {
                // Depth is fixed at 94mm for framework compatibility
                depthValue = 94;                                             // <-- Keep depth fixed
            }
            // ---------------------------------------------------------------

            // FUNCTION | Update Node Height Value and Display
            // ---------------------------------------------------------------
            function updateHeight(value) {
                const newValue = parseInt(value)
                heightValue = newValue;                                      // <-- Parse and store new height value
                document.getElementById('height-value-input').value = newValue; // <-- Update height input field
                if (currentNodeComponent) {                                  // <-- Check if a node is selected
                    updateNode();                                            // <-- Apply height change to selected node
                }
            }
            // ---------------------------------------------------------------

            // FUNCTION | Create New Node (Always Creates New)
            // ---------------------------------------------------------------
            function createNode() {
                sketchup.createNode(widthValue, depthValue, heightValue, selectedNodeType, selectedMaterial); // <-- Always create new node with current values
            }
            // ---------------------------------------------------------------

            // FUNCTION | Update Currently Selected Node with Current Configuration
            // ---------------------------------------------------------------
            function updateNode() {
                if (currentNodeComponent) {                                  // <-- Only update if a node is selected
                    sketchup.updateNode(widthValue, depthValue, heightValue, selectedNodeType, selectedMaterial); // <-- Send update command to SketchUp with all current values
                }
            }
            // ---------------------------------------------------------------

            // GLOBAL FUNCTION | Set Initial Configuration from SketchUp
            // ---------------------------------------------------------------
            window.setInitialConfig = function(configJson) {
                const config = JSON.parse(configJson);                       // <-- Parse JSON configuration from SketchUp
                currentNodeComponent = true;                                  // <-- Mark that a node is currently selected
                initFromConfig(config);                                       // <-- Initialize dialog with loaded configuration
            };
            // ---------------------------------------------------------------

            // GLOBAL FUNCTION | Clear Current Node Selection
            // ---------------------------------------------------------------
            window.clearCurrentNode = function() {
                currentNodeComponent = null;                                  // <-- Clear current node reference
            };
            // ---------------------------------------------------------------

        // endregion ----------------------------------------------------
          </script>
        </body>
        </html>
        HTML
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Setup Dialog Callbacks
    # ---------------------------------------------------------------
    def self.setup_dialog_callbacks
        @dialog.add_action_callback("createNode") do |action_context, width, depth, height, node_type, material|
            # This callback is for when the JS calls sketchup.createNode for a new node.
            
            # Prepare a full, new configuration object based on defaults and current dialog values.
            prepared_config = prepare_config_for_creation(width, depth, height, node_type, material)
            
            # Create the node geometry using this prepared configuration.
            created_instance = create_node_geometry(prepared_config) 
            
            if created_instance && created_instance.valid?
                @node_component = created_instance # Store reference to the new node component
                @config = prepared_config          # Store the configuration used for this new node
            else
                puts "Error: Node creation failed."
            end
        end
        
        @dialog.add_action_callback("updateNode") do |action_context, width, depth, height, node_type, material|
            update_node_geometry(width, depth, height, node_type, material)
        end
    end
    # ---------------------------------------------------------------

    end # module FrameworkNodeConfigurator
  end # module Tools
end # module ValeDesignSuite

# Initialize the tool when the script is loaded
# ValeDesignSuite::Tools::FrameworkNodeConfigurator.init  # <-- COMMENTED OUT: This was causing automatic dialog opening on startup