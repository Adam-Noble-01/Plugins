# =============================================================================
# CAMERA AGENT TOOL - SIMPLIFIED VERSION
# =============================================================================
#
# FILE       :  Util_CameraAgentTool_MainPluginScript.rb
# AUTHOR     :  Adam Noble - Noble Architecture
# PURPOSE    :  Interactive camera agent placement tool for virtual tour preparation
# CREATED    :  2025
#
# DESCRIPTION:
# - This tool allows users to place camera agents (SketchUp components) into a model.
# - Each agent stores camera configuration data in a dictionary for use in GLB viewers.
# - Agents act as waypoints for creating virtual tours in Babylon JS applications.
# - Provides HTML dialog interface for agent configuration and management.
# - Exports all agent data as JSON for downstream processing.
# - Camera agents include visual representation of person and view direction.
#
# -----------------------------------------------------------------------------

require 'sketchup.rb'
require 'json'

# -----------------------------------------------------------------------------
# REGION | Extension Registration and Menu Setup
# -----------------------------------------------------------------------------

unless file_loaded?(__FILE__)
    ext = SketchupExtension.new("Camera Agent Tool", __FILE__)
    ext.description = "Interactive camera agent placement tool for virtual tour preparation"
    ext.version = "1.0.0"
    ext.creator = "Adam Noble - Noble Architecture"
    
    Sketchup.register_extension(ext, true)
    
    # Add menu item
    UI.menu("Extensions").add_item("Camera Agent Tool") {
        CameraAgentTool.show_dialog
    }
    
    file_loaded(__FILE__)
end

# endregion -------------------------------------------------------------------

module CameraAgentTool

# -----------------------------------------------------------------------------
# REGION | Module Constants and Configuration
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Agent Geometry and Dictionary Keys
    # ------------------------------------------------------------
    MM_TO_INCH              =   1.0 / 25.4                                    # <-- Millimeter to inch conversion factor
    AGENT_DICT_NAME         =   "CameraAgentData"                            # <-- Model dictionary name for all agents
    AGENT_COMPONENT_NAME    =   "Camera_Agent"                               # <-- Base name for agent components
    PERSON_WIDTH_MM         =   650                                           # <-- Triangle person width in millimeters
    PERSON_HEIGHT_MM        =   1800                                          # <-- Triangle person height in millimeters
    CAMERA_HEIGHT_MM        =   1700                                          # <-- Default camera height in millimeters
    VIEW_CONE_LENGTH_MM     =   3000                                          # <-- View cone length in millimeters
    VIEW_CONE_ANGLE_DEG     =   60                                            # <-- View cone angle in degrees
    AGENT_OPACITY           =   0.5                                           # <-- Agent geometry opacity (50%)
    AGENT_COLOR             =   Sketchup::Color.new(255, 0, 0, 128)          # <-- Semi-transparent red color
    # ---------------------------------------------------------------

    # MODULE CONSTANTS | Default Camera Configuration
    # ------------------------------------------------------------
    DEFAULT_ASPECT_RATIO    =   "16:9"                                        # <-- Default camera aspect ratio
    DEFAULT_LENS_MM         =   35                                            # <-- Default camera lens in millimeters
    DEFAULT_FOV_DEG         =   60                                            # <-- Default field of view in degrees
    # ---------------------------------------------------------------

    # MODULE VARIABLES | Tool State and References
    # ------------------------------------------------------------
    @dialog                 =   nil                                           # <-- HTML dialog instance
    @selection_observer     =   nil                                           # <-- Selection observer instance
    @current_agent          =   nil                                           # <-- Currently selected agent
    @agent_counter          =   0                                             # <-- Counter for unique agent IDs
    @placement_tool         =   nil                                           # <-- Agent placement tool instance
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Basic Data Serialization Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Serialize Agent Data to JSON
    # ------------------------------------------------------------
    def self.serialize_agent_data(data)
        begin
            return JSON.generate(data)                                       # <-- Convert to JSON string
        rescue => e
            puts "Error serializing agent data: #{e.message}"               # <-- Log error
            return nil
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Deserialize Agent Data from JSON
    # ------------------------------------------------------------
    def self.deserialize_agent_data(json_string)
        begin
            return JSON.parse(json_string)                                   # <-- Parse JSON string
        rescue => e
            puts "Error deserializing agent data: #{e.message}"             # <-- Log error
            return nil
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Save Data to Model Dictionary
    # ------------------------------------------------------------
    def self.save_to_model_dictionary(key, data)
        model = Sketchup.active_model                                        # <-- Get active model
        return false unless model                                            # <-- Exit if no model
        
        dict = model.attribute_dictionary(AGENT_DICT_NAME, true)            # <-- Create if needed
        serialized_data = serialize_agent_data(data)                        # <-- Serialize data
        
        if serialized_data
            dict[key] = serialized_data                                      # <-- Store serialized data
            dict["lastModified"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")   # <-- Update timestamp
            return true                                                      # <-- Success
        end
        
        return false                                                         # <-- Failure
    end
    # ---------------------------------------------------------------

    # FUNCTION | Load Data from Model Dictionary
    # ------------------------------------------------------------
    def self.load_from_model_dictionary(key)
        model = Sketchup.active_model                                        # <-- Get active model
        return nil unless model                                              # <-- Exit if no model
        
        dict = model.attribute_dictionary(AGENT_DICT_NAME)                  # <-- Get dictionary
        return nil unless dict && dict[key]                                  # <-- Exit if no data
        
        return deserialize_agent_data(dict[key])                            # <-- Deserialize and return
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Core Utility Functions
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Convert Millimeters to Inches
    # ---------------------------------------------------------------
    def self.mm_to_inch(mm)
        mm * MM_TO_INCH                                                      # <-- Apply conversion factor
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Convert Inches to Millimeters
    # ---------------------------------------------------------------
    def self.inch_to_mm(inches)
        inches / MM_TO_INCH                                                  # <-- Apply inverse conversion factor
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Generate Next Agent ID
    # ---------------------------------------------------------------
    def self.generate_next_agent_id
        agents = load_from_model_dictionary("agents") || []                  # <-- Load existing agents
        max_id = 0                                                           # <-- Initialize max ID counter
        
        agents.each do |agent|
            if agent["agentId"] && agent["agentId"].match(/^CAM(\d{3})$/)
                id_num = $1.to_i                                             # <-- Extract ID number
                max_id = id_num if id_num > max_id                          # <-- Update max if higher
            end
        end
        
        next_id = max_id + 1                                                 # <-- Increment to next ID
        return "CAM#{format('%03d', next_id)}"                              # <-- Return formatted ID
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Camera Agent Geometry Creation
# -----------------------------------------------------------------------------

    # FUNCTION | Create Camera Agent Component
    # ------------------------------------------------------------
    def self.create_camera_agent(position, direction = nil)
        return nil unless validate_agent_creation_preconditions              # <-- Validate preconditions
        
        model = Sketchup.active_model                                        # <-- Get active model
        model.start_operation("Create Camera Agent", true)                  # <-- Start operation
        
        agent_id = generate_next_agent_id                                   # <-- Generate unique agent ID
        agent_name = "#{AGENT_COMPONENT_NAME}_#{agent_id}"                  # <-- Create agent name
        
        # Create component definition
        agent_def = model.definitions.add(agent_name)                        # <-- Add new definition
        create_agent_geometry(agent_def)                                     # <-- Create agent geometry
        
        # Create instance at position
        transformation = create_agent_transformation(position, direction)    # <-- Create transformation
        agent_instance = model.active_entities.add_instance(agent_def, transformation)  # <-- Add instance
        agent_instance.name = agent_name                                     # <-- Set instance name
        
        # Initialize agent data
        initialize_agent_data(agent_instance, agent_id, position)           # <-- Initialize data
        
        model.commit_operation                                               # <-- Commit operation
        return agent_instance                                                # <-- Return created instance
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Validate Agent Creation Preconditions
    # ---------------------------------------------------------------
    def self.validate_agent_creation_preconditions
        return false unless Sketchup.active_model                           # <-- Check model exists
        return true                                                          # <-- All preconditions met
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create Agent Geometry
    # ---------------------------------------------------------------
    def self.create_agent_geometry(definition)
        entities = definition.entities                                       # <-- Get definition entities
        
        # Create person triangle (elevation view)
        create_person_triangle(entities)                                     # <-- Create person representation
        
        # Create view cone (plan view)
        create_view_cone(entities)                                           # <-- Create view direction cone
        
        # Apply material
        apply_agent_material(entities)                                       # <-- Apply semi-transparent red
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Person Triangle
    # ---------------------------------------------------------------
    def self.create_person_triangle(entities)
        # Person triangle in YZ plane (facing X direction)
        width_inches = mm_to_inch(PERSON_WIDTH_MM)                           # <-- Convert width to inches
        height_inches = mm_to_inch(PERSON_HEIGHT_MM)                        # <-- Convert height to inches
        
        # Triangle points (centered at origin)
        pts = []
        pts << [0, -width_inches/2, 0]                                      # <-- Bottom left
        pts << [0, width_inches/2, 0]                                       # <-- Bottom right
        pts << [0, 0, height_inches]                                        # <-- Top center
        
        face = entities.add_face(pts)                                        # <-- Create triangle face
        face.reverse! if face.normal.x < 0                                  # <-- Ensure normal faces +X
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create View Cone
    # ---------------------------------------------------------------
    def self.create_view_cone(entities)
        # View cone in XY plane at camera height
        cone_length = mm_to_inch(VIEW_CONE_LENGTH_MM)                       # <-- Convert length to inches
        camera_height = mm_to_inch(CAMERA_HEIGHT_MM)                        # <-- Convert height to inches
        half_angle = VIEW_CONE_ANGLE_DEG / 2.0 * Math::PI / 180.0          # <-- Half angle in radians
        
        # Cone points
        pts = []
        pts << [0, 0, camera_height]                                        # <-- Apex at camera position
        pts << [cone_length, cone_length * Math.tan(half_angle), camera_height]   # <-- Right edge
        pts << [cone_length, -cone_length * Math.tan(half_angle), camera_height]  # <-- Left edge
        
        face = entities.add_face(pts)                                        # <-- Create cone face
        face.reverse! if face.normal.z < 0                                  # <-- Ensure normal faces +Z
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Apply Agent Material
    # ---------------------------------------------------------------
    def self.apply_agent_material(entities)
        model = Sketchup.active_model                                        # <-- Get active model
        materials = model.materials                                          # <-- Get materials collection
        
        # Create or get agent material
        material_name = "CameraAgent_Material"                               # <-- Material name
        material = materials[material_name]                                  # <-- Check if exists
        
        unless material
            material = materials.add(material_name)                          # <-- Create new material
            material.color = AGENT_COLOR                                     # <-- Set color with alpha
            material.alpha = AGENT_OPACITY                                   # <-- Set opacity
        end
        
        # Apply to all faces
        entities.each do |entity|
            if entity.is_a?(Sketchup::Face)
                entity.material = material                                   # <-- Apply material to face
                entity.back_material = material                              # <-- Apply to back face too
            end
        end
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create Agent Transformation
    # ---------------------------------------------------------------
    def self.create_agent_transformation(position, direction = nil)
        # Default direction is along positive X axis
        direction ||= Geom::Vector3d.new(1, 0, 0)                          # <-- Default direction
        direction.normalize!                                                 # <-- Ensure unit vector
        
        # Calculate rotation from default (X-axis) to desired direction
        default_dir = Geom::Vector3d.new(1, 0, 0)                          # <-- Default X direction
        axis = default_dir.cross(direction)                                 # <-- Rotation axis
        angle = default_dir.angle_between(direction)                        # <-- Rotation angle
        
        # Create transformation
        transformation = Geom::Transformation.new(position)                  # <-- Start with position
        
        if axis.length > 0.001  # Avoid rotation if directions are parallel
            rotation = Geom::Transformation.rotation(position, axis, angle) # <-- Create rotation
            transformation = transformation * rotation                       # <-- Apply rotation
        end
        
        return transformation                                                # <-- Return combined transform
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Agent Data Management
# -----------------------------------------------------------------------------

    # FUNCTION | Initialize Agent Data
    # ------------------------------------------------------------
    def self.initialize_agent_data(agent_instance, agent_id, position)
        # Calculate global position and direction
        global_position = position                                           # <-- Already in global coords
        transformation = agent_instance.transformation                       # <-- Get instance transform
        direction_vector = transformation.xaxis                              # <-- Get direction from transform
        
        # Create agent data structure
        agent_data = {
            "agentId" => agent_id,                                          # <-- Unique agent ID
            "agentName" => "Camera Agent #{agent_id}",                     # <-- Display name
            "waypointNumber" => agent_id.match(/\d+/)[0].to_i,             # <-- Extract waypoint number
            "position" => {
                "x" => inch_to_mm(global_position.x),                      # <-- X in millimeters
                "y" => inch_to_mm(global_position.y),                      # <-- Y in millimeters
                "z" => inch_to_mm(global_position.z) + CAMERA_HEIGHT_MM    # <-- Z at camera height
            },
            "direction" => {
                "x" => direction_vector.x,                                  # <-- Direction X component
                "y" => direction_vector.y,                                  # <-- Direction Y component
                "z" => direction_vector.z                                   # <-- Direction Z component
            },
            "rotation" => {
                "heading" => Math.atan2(direction_vector.y, direction_vector.x) * 180.0 / Math::PI,  # <-- Heading in degrees
                "pitch" => 0.0,                                            # <-- Pitch angle
                "roll" => 0.0                                              # <-- Roll angle
            },
            "camera" => {
                "aspectRatio" => DEFAULT_ASPECT_RATIO,                     # <-- Aspect ratio
                "lensMm" => DEFAULT_LENS_MM,                               # <-- Lens in millimeters
                "fovDegrees" => DEFAULT_FOV_DEG                           # <-- Field of view
            },
            "metadata" => {
                "createdDate" => Time.now.strftime("%Y-%m-%d %H:%M:%S"),  # <-- Creation timestamp
                "lastModified" => Time.now.strftime("%Y-%m-%d %H:%M:%S")  # <-- Last modified
            }
        }
        
        # Store data in model dictionary
        save_agent_to_model_dictionary(agent_data)                          # <-- Save to model dict
        
        # Store reference on component instance
        agent_instance.set_attribute("CameraAgent", "agentId", agent_id)    # <-- Store ID on instance
    end
    # ---------------------------------------------------------------

    # FUNCTION | Save Agent to Model Dictionary
    # ------------------------------------------------------------
    def self.save_agent_to_model_dictionary(agent_data)
        # Load existing agents
        agents = load_from_model_dictionary("agents") || []                  # <-- Get existing agents
        
        # Update or add agent
        agent_index = agents.find_index { |a| a["agentId"] == agent_data["agentId"] }  # <-- Find existing
        if agent_index
            agents[agent_index] = agent_data                                # <-- Update existing
        else
            agents << agent_data                                            # <-- Add new agent
        end
        
        # Save back to dictionary
        save_to_model_dictionary("agents", agents)                          # <-- Save updated agents
    end
    # ---------------------------------------------------------------

    # FUNCTION | Load Agent from Model Dictionary
    # ------------------------------------------------------------
    def self.load_agent_from_model_dictionary(agent_id)
        agents = load_from_model_dictionary("agents")                       # <-- Load all agents
        return nil unless agents                                             # <-- Exit if no agents
        
        agent = agents.find { |a| a["agentId"] == agent_id }               # <-- Find specific agent
        return agent                                                         # <-- Return found agent
    end
    # ---------------------------------------------------------------

    # FUNCTION | Update Agent Data
    # ------------------------------------------------------------
    def self.update_agent_data(agent_id, updates)
        agent_data = load_agent_from_model_dictionary(agent_id)             # <-- Load existing data
        return unless agent_data                                             # <-- Exit if not found
        
        # Update position if agent moved
        agent_instance = find_agent_instance_by_id(agent_id)                # <-- Find component instance
        if agent_instance
            update_agent_position_data(agent_data, agent_instance)          # <-- Update position
        end
        
        # Apply updates
        updates.each do |key, value|
            if agent_data.key?(key)
                agent_data[key] = value                                      # <-- Update value
            elsif key.include?(".")  # Handle nested updates like "camera.lensMm"
                keys = key.split(".")                                        # <-- Split nested key
                target = agent_data
                keys[0..-2].each { |k| target = target[k] }                # <-- Navigate to parent
                target[keys.last] = value                                    # <-- Update nested value
            end
        end
        
        # Update timestamp
        agent_data["metadata"]["lastModified"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")  # <-- Update modified time
        
        # Save back to dictionary
        save_agent_to_model_dictionary(agent_data)                          # <-- Save updated data
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Update Agent Position Data
    # ---------------------------------------------------------------
    def self.update_agent_position_data(agent_data, agent_instance)
        transformation = agent_instance.transformation                       # <-- Get current transform
        position = transformation.origin                                     # <-- Get position
        direction = transformation.xaxis                                     # <-- Get direction
        
        # Update position
        agent_data["position"]["x"] = inch_to_mm(position.x)               # <-- Update X
        agent_data["position"]["y"] = inch_to_mm(position.y)               # <-- Update Y
        agent_data["position"]["z"] = inch_to_mm(position.z) + CAMERA_HEIGHT_MM  # <-- Update Z at camera height
        
        # Update direction
        agent_data["direction"]["x"] = direction.x                          # <-- Update direction X
        agent_data["direction"]["y"] = direction.y                          # <-- Update direction Y
        agent_data["direction"]["z"] = direction.z                          # <-- Update direction Z
        
        # Update rotation
        agent_data["rotation"]["heading"] = Math.atan2(direction.y, direction.x) * 180.0 / Math::PI  # <-- Update heading
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Find Agent Instance by ID
    # ---------------------------------------------------------------
    def self.find_agent_instance_by_id(agent_id)
        model = Sketchup.active_model                                        # <-- Get active model
        return nil unless model                                              # <-- Exit if no model
        
        model.active_entities.grep(Sketchup::ComponentInstance).each do |instance|
            stored_id = instance.get_attribute("CameraAgent", "agentId")    # <-- Get stored ID
            return instance if stored_id == agent_id                        # <-- Return if match
        end
        
        return nil                                                           # <-- Not found
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | JSON Export Functionality
# -----------------------------------------------------------------------------

    # FUNCTION | Export All Agents to JSON
    # ------------------------------------------------------------
    def self.export_agents_to_json
        model = Sketchup.active_model                                        # <-- Get active model
        return unless model                                                  # <-- Exit if no model
        
        # Load all agents from model dictionary
        agents = load_from_model_dictionary("agents")                       # <-- Load agents
        unless agents && !agents.empty?
            UI.messagebox("No camera agents found in model.")               # <-- Show message
            return
        end
        
        begin
            # Create export data structure
            export_data = {
                "exportInfo" => {
                    "exportDate" => Time.now.strftime("%Y-%m-%d %H:%M:%S"), # <-- Export timestamp
                    "modelName" => model.title,                              # <-- Model name
                    "exportedBy" => "Camera Agent Tool",                     # <-- Tool identifier
                    "version" => "1.0.0"                                     # <-- Export version
                },
                "cameraAgents" => agents                                     # <-- All agents data
            }
            
            # Get save path from user
            filename = "Data_-_CameraAgentData.json"                        # <-- Default filename
            path = UI.savepanel("Export Camera Agents", "", filename)       # <-- Show save dialog
            
            if path
                # Write JSON file
                File.open(path, 'w') do |file|
                    file.write(JSON.pretty_generate(export_data))           # <-- Write formatted JSON
                end
                
                UI.messagebox("Camera agents exported successfully!\n\nExported #{agents.length} agents to:\n#{path}")
            end
            
        rescue => e
            UI.messagebox("Error exporting camera agents: #{e.message}")    # <-- Show error
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | HTML Dialog Interface
# -----------------------------------------------------------------------------

    # FUNCTION | Show Camera Agent Dialog
    # ------------------------------------------------------------
    def self.show_dialog
        if @dialog && @dialog.visible?                                       # <-- Return if already showing
            @dialog.bring_to_front                                           # <-- Bring to front
            return
        end
        
        create_dialog                                                        # <-- Create new dialog
        setup_dialog_callbacks                                               # <-- Setup callbacks
        setup_selection_observer                                             # <-- Setup observer
        
        @dialog.show                                                         # <-- Show dialog
        
        # Check for existing selection
        check_for_existing_agent_selection                                  # <-- Update if agent selected
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create Dialog
    # ---------------------------------------------------------------
    def self.create_dialog
        @dialog = UI::HtmlDialog.new(
            :dialog_title => "Camera Agent Tool",                            # <-- Dialog title
            :preferences_key => "ValeDesignSuite_CameraAgentTool",          # <-- Preferences key
            :scrollable => true,                                             # <-- Allow scrolling
            :resizable => true,                                              # <-- Allow resizing
            :width => 400,                                                   # <-- Initial width
            :height => 700,                                                  # <-- Initial height
            :left => 100,                                                    # <-- Initial X position
            :top => 100,                                                     # <-- Initial Y position
            :min_width => 350,                                               # <-- Minimum width
            :min_height => 600                                               # <-- Minimum height
        )
        
        @dialog.set_html(create_dialog_html_content)                        # <-- Set HTML content
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create Dialog HTML Content
    # ---------------------------------------------------------------
    def self.create_dialog_html_content
        <<-HTML
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Camera Agent Tool</title>
    <style>
        /* CSS Variables - Vale Design Suite Standards */
        :root {
            --FontCol_ValeTitleTextColour      : #172b3a;
            --FontCol_ValeStandardTextColour   : #1e1e1e;
            --FontCol_ValeLinkTextColour       : #336699;
            --FontCol_ValeHoverTextColour      : #3377aa;
            --FontCol_ValeDisabledTextColour   : #999999;
            --ValeBackgroundColor              : #f5f5f5;
            --ValeWhiteBackground              : #ffffff;
            --ValeBorderColor                  : #cccccc;
            --ValeHighlightColor               : #0066cc;
            --ValeSuccessColor                 : #28a745;
            --ValeWarningColor                 : #ffc107;
            --ValeDangerColor                  : #dc3545;
            font-size                          : 14px;
            --FontSize_ValeTitleText           : 1.4rem;
            --FontSize_ValeTitleHeading01      : 1.10rem;
            --FontSize_ValeTitleHeading02      : 1.00rem;
            --FontSize_ValeStandardText        : 0.85rem;
        }

        /* Base Layout Styles */
        html, body {
            margin                             : 0;
            padding                            : 0;
            font-family                        : Arial, sans-serif;
            font-size                          : var(--FontSize_ValeStandardText);
            color                              : var(--FontCol_ValeStandardTextColour);
            background-color                   : var(--ValeBackgroundColor);
            height                             : 100vh;
            overflow-y                         : auto;
        }

        /* Container Styles */
        .container {
            padding                            : 20px;
            max-width                          : 100%;
            box-sizing                         : border-box;
        }

        /* Header Styles */
        h1 {
            font-size                          : var(--FontSize_ValeTitleText);
            color                              : var(--FontCol_ValeTitleTextColour);
            margin                             : 0 0 20px 0;
            text-align                         : center;
        }

        /* Section Styles */
        .section {
            background                         : var(--ValeWhiteBackground);
            border                             : 1px solid var(--ValeBorderColor);
            border-radius                      : 8px;
            padding                            : 15px;
            margin-bottom                      : 15px;
        }

        .section-title {
            font-size                          : var(--FontSize_ValeTitleHeading01);
            color                              : var(--FontCol_ValeTitleTextColour);
            margin-bottom                      : 10px;
            font-weight                        : bold;
        }

        /* Form Styles */
        .form-group {
            margin-bottom                      : 12px;
        }

        label {
            display                            : block;
            margin-bottom                      : 4px;
            font-weight                        : bold;
            color                              : var(--FontCol_ValeStandardTextColour);
        }

        input[type="text"],
        input[type="number"],
        select {
            width                              : 100%;
            padding                            : 8px;
            border                             : 1px solid var(--ValeBorderColor);
            border-radius                      : 4px;
            font-size                          : var(--FontSize_ValeStandardText);
            box-sizing                         : border-box;
        }

        input[readonly] {
            background-color                   : #f0f0f0;
            color                              : var(--FontCol_ValeDisabledTextColour);
        }

        /* Button Styles */
        .button {
            width                              : 100%;
            padding                            : 10px;
            margin                             : 5px 0;
            border                             : none;
            border-radius                      : 4px;
            font-size                          : var(--FontSize_ValeStandardText);
            font-weight                        : bold;
            cursor                             : pointer;
            transition                         : background-color 0.3s;
        }

        .button-primary {
            background-color                   : var(--ValeHighlightColor);
            color                              : white;
        }

        .button-primary:hover {
            background-color                   : var(--FontCol_ValeHoverTextColour);
        }

        .button-success {
            background-color                   : var(--ValeSuccessColor);
            color                              : white;
        }

        .button-success:hover {
            background-color                   : #218838;
        }

        .button-warning {
            background-color                   : var(--ValeWarningColor);
            color                              : black;
        }

        .button-warning:hover {
            background-color                   : #e0a800;
        }

        /* Status Message Styles */
        .status-message {
            padding                            : 10px;
            margin                             : 10px 0;
            border-radius                      : 4px;
            text-align                         : center;
            display                            : none;
        }

        .status-success {
            background-color                   : #d4edda;
            color                              : #155724;
            border                             : 1px solid #c3e6cb;
        }

        .status-error {
            background-color                   : #f8d7da;
            color                              : #721c24;
            border                             : 1px solid #f5c6cb;
        }

        /* Position Display Styles */
        .position-grid {
            display                            : grid;
            grid-template-columns              : repeat(3, 1fr);
            gap                                : 10px;
        }

        .position-item {
            text-align                         : center;
        }

        .position-value {
            font-size                          : 1.1em;
            font-weight                        : bold;
            color                              : var(--ValeHighlightColor);
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Camera Agent Tool</h1>
        
        <!-- ----------------------------------------------------------------- -->
        <!-- REGION  |  Agent Information Section                               -->
        <!-- ----------------------------------------------------------------- -->
        
        <div class="section">
            <div class="section-title">Agent Information</div>
            <div class="form-group">
                <label for="agentId">Agent ID</label>
                <input type="text" id="agentId" readonly>
            </div>
            <div class="form-group">
                <label for="agentName">Agent Name</label>
                <input type="text" id="agentName" placeholder="Enter agent name">
            </div>
            <div class="form-group">
                <label for="waypointNumber">Waypoint Number</label>
                <input type="number" id="waypointNumber" min="1" max="999">
            </div>
        </div>
        
        <!-- ----------------------------------------------------------------- -->
        <!-- REGION  |  Position and Orientation Section                        -->
        <!-- ----------------------------------------------------------------- -->
        
        <div class="section">
            <div class="section-title">Position & Orientation</div>
            <div class="position-grid">
                <div class="position-item">
                    <label>X (mm)</label>
                    <div class="position-value" id="posX">0</div>
                </div>
                <div class="position-item">
                    <label>Y (mm)</label>
                    <div class="position-value" id="posY">0</div>
                </div>
                <div class="position-item">
                    <label>Z (mm)</label>
                    <div class="position-value" id="posZ">0</div>
                </div>
            </div>
            <div class="form-group" style="margin-top: 10px;">
                <label>Heading (degrees)</label>
                <div class="position-value" id="heading">0.0°</div>
            </div>
        </div>
        
        <!-- ----------------------------------------------------------------- -->
        <!-- REGION  |  Camera Configuration Section                            -->
        <!-- ----------------------------------------------------------------- -->
        
        <div class="section">
            <div class="section-title">Camera Configuration</div>
            <div class="form-group">
                <label for="aspectRatio">Aspect Ratio</label>
                <select id="aspectRatio">
                    <option value="16:9">16:9 (Widescreen)</option>
                    <option value="4:3">4:3 (Standard)</option>
                    <option value="1:1">1:1 (Square)</option>
                    <option value="21:9">21:9 (Ultrawide)</option>
                </select>
            </div>
            <div class="form-group">
                <label for="lensMm">Lens (mm)</label>
                <select id="lensMm">
                    <option value="14">14mm (Ultra Wide)</option>
                    <option value="24">24mm (Wide)</option>
                    <option value="28">28mm (Wide)</option>
                    <option value="35" selected>35mm (Standard)</option>
                    <option value="50">50mm (Normal)</option>
                    <option value="85">85mm (Portrait)</option>
                    <option value="135">135mm (Telephoto)</option>
                </select>
            </div>
            <div class="form-group">
                <label for="fovDegrees">Field of View (degrees)</label>
                <input type="number" id="fovDegrees" min="10" max="170" value="60">
            </div>
        </div>
        
        <!-- ----------------------------------------------------------------- -->
        <!-- REGION  |  Action Buttons Section                                  -->
        <!-- ----------------------------------------------------------------- -->
        
        <div class="section">
            <button class="button button-primary" onclick="placeNewAgent()">Place New Camera Agent</button>
            <button class="button button-success" onclick="saveAgentData()">Save Agent Data</button>
            <button class="button button-warning" onclick="exportAgentsData()">Export All Agents to JSON</button>
        </div>
        
        <!-- Status Message -->
        <div id="statusMessage" class="status-message"></div>
        
        <!-- endregion ----------------------------------------------------------------- -->
    </div>

    <script>
    // -----------------------------------------------------------------------------
    // REGION | Front End Javascript Section
    // -----------------------------------------------------------------------------

        // MODULE VARIABLES | Current Agent State
        // ------------------------------------------------------------
        let currentAgentId = null;                                           // <-- Currently selected agent ID
        let isUpdating = false;                                              // <-- Flag to prevent recursive updates
        // ------------------------------------------------------------

        // FUNCTION | Initialize Dialog from Agent Data
        // ------------------------------------------------------------
        function initFromAgentData(agentData) {
            if (!agentData || isUpdating) return;                            // <-- Exit if no data or updating
            
            isUpdating = true;                                               // <-- Set updating flag
            
            try {
                // Update agent information
                currentAgentId = agentData.agentId;                         // <-- Store current agent ID
                document.getElementById('agentId').value = agentData.agentId || '';           // <-- Set agent ID
                document.getElementById('agentName').value = agentData.agentName || '';       // <-- Set agent name
                document.getElementById('waypointNumber').value = agentData.waypointNumber || 1;  // <-- Set waypoint number
                
                // Update position display
                if (agentData.position) {
                    document.getElementById('posX').textContent = Math.round(agentData.position.x || 0);  // <-- Update X position
                    document.getElementById('posY').textContent = Math.round(agentData.position.y || 0);  // <-- Update Y position
                    document.getElementById('posZ').textContent = Math.round(agentData.position.z || 0);  // <-- Update Z position
                }
                
                // Update orientation display
                if (agentData.rotation) {
                    document.getElementById('heading').textContent = (agentData.rotation.heading || 0).toFixed(1) + '°';  // <-- Update heading
                }
                
                // Update camera configuration
                if (agentData.camera) {
                    document.getElementById('aspectRatio').value = agentData.camera.aspectRatio || '16:9';     // <-- Set aspect ratio
                    document.getElementById('lensMm').value = agentData.camera.lensMm || '35';                // <-- Set lens mm
                    document.getElementById('fovDegrees').value = agentData.camera.fovDegrees || 60;          // <-- Set FOV
                }
                
            } catch (e) {
                console.error('Error initializing from agent data:', e);     // <-- Log errors
            } finally {
                isUpdating = false;                                          // <-- Clear updating flag
            }
        }
        // ---------------------------------------------------------------

        // FUNCTION | Place New Camera Agent
        // ---------------------------------------------------------------
        function placeNewAgent() {
            window.location = 'skp:placeNewAgent';                           // <-- Trigger Ruby callback
        }
        // ---------------------------------------------------------------

        // FUNCTION | Save Current Agent Data
        // ---------------------------------------------------------------
        function saveAgentData() {
            if (!currentAgentId) {
                showStatus('No agent selected', 'error');                    // <-- Show error if no agent
                return;
            }
            
            // Gather updated data
            const updates = {
                agentName: document.getElementById('agentName').value,       // <-- Get agent name
                waypointNumber: parseInt(document.getElementById('waypointNumber').value),  // <-- Get waypoint number
                'camera.aspectRatio': document.getElementById('aspectRatio').value,         // <-- Get aspect ratio
                'camera.lensMm': parseInt(document.getElementById('lensMm').value),         // <-- Get lens mm
                'camera.fovDegrees': parseFloat(document.getElementById('fovDegrees').value)  // <-- Get FOV
            };
            
            // Send update to Ruby
            window.location = 'skp:updateAgent@' + JSON.stringify({
                agentId: currentAgentId,
                updates: updates
            });
            
            showStatus('Agent data saved successfully', 'success');          // <-- Show success message
        }
        // ---------------------------------------------------------------

        // FUNCTION | Export All Agents Data
        // ---------------------------------------------------------------
        function exportAgentsData() {
            window.location = 'skp:exportAgents';                            // <-- Trigger export callback
        }
        // ---------------------------------------------------------------

        // HELPER FUNCTION | Show Status Message
        // ---------------------------------------------------------------
        function showStatus(message, type) {
            const statusEl = document.getElementById('statusMessage');       // <-- Get status element
            statusEl.textContent = message;                                  // <-- Set message text
            statusEl.className = 'status-message status-' + type;           // <-- Set status class
            statusEl.style.display = 'block';                                // <-- Show message
            
            setTimeout(() => {
                statusEl.style.display = 'none';                             // <-- Hide after delay
            }, 3000);
        }
        // ---------------------------------------------------------------

        // FUNCTION | Clear Dialog Fields
        // ---------------------------------------------------------------
        function clearDialog() {
            currentAgentId = null;                                           // <-- Clear current agent
            document.getElementById('agentId').value = '';                   // <-- Clear agent ID
            document.getElementById('agentName').value = '';                 // <-- Clear agent name
            document.getElementById('waypointNumber').value = '1';           // <-- Reset waypoint number
            document.getElementById('posX').textContent = '0';               // <-- Clear X position
            document.getElementById('posY').textContent = '0';               // <-- Clear Y position
            document.getElementById('posZ').textContent = '0';               // <-- Clear Z position
            document.getElementById('heading').textContent = '0.0°';         // <-- Clear heading
            document.getElementById('aspectRatio').value = '16:9';           // <-- Reset aspect ratio
            document.getElementById('lensMm').value = '35';                  // <-- Reset lens mm
            document.getElementById('fovDegrees').value = '60';              // <-- Reset FOV
        }
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
        # Place new agent callback
        @dialog.add_action_callback("placeNewAgent") do |action_context|
            activate_placement_tool                                          # <-- Activate placement tool
        end
        
        # Update agent callback
        @dialog.add_action_callback("updateAgent") do |action_context, data_json|
            begin
                data = JSON.parse(data_json)                                # <-- Parse update data
                update_agent_data(data["agentId"], data["updates"])        # <-- Update agent data
            rescue => e
                puts "Error updating agent: #{e.message}"                   # <-- Log error
            end
        end
        
        # Export agents callback
        @dialog.add_action_callback("exportAgents") do |action_context|
            export_agents_to_json                                            # <-- Export all agents
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Agent Placement Tool
# -----------------------------------------------------------------------------

    # CLASS | Camera Agent Placement Tool
    # ------------------------------------------------------------
    class CameraAgentPlacementTool
        def initialize
            @current_point = nil                                             # <-- Current mouse position
            @preview_transformation = nil                                    # <-- Preview transformation
        end
        
        def activate
            @current_point = nil                                             # <-- Reset current point
            Sketchup.active_model.active_view.invalidate                    # <-- Refresh view
        end
        
        def deactivate(view)
            view.invalidate                                                  # <-- Refresh view on deactivate
        end
        
        def onMouseMove(flags, x, y, view)
            @current_point = view.inputpoint(x, y).position                 # <-- Get 3D point from mouse
            
            # Calculate direction based on camera view
            camera = view.camera                                             # <-- Get camera
            eye = camera.eye                                                 # <-- Camera position
            direction = @current_point - eye                                 # <-- Direction to point
            direction.z = 0                                                  # <-- Keep horizontal
            direction.normalize!                                             # <-- Normalize vector
            
            @preview_transformation = CameraAgentTool.create_agent_transformation(@current_point, direction)
            view.invalidate                                                  # <-- Refresh view
        end
        
        def onLButtonDown(flags, x, y, view)
            if @current_point
                # Calculate direction
                camera = view.camera                                         # <-- Get camera
                eye = camera.eye                                             # <-- Camera position
                direction = @current_point - eye                             # <-- Direction to point
                direction.z = 0                                              # <-- Keep horizontal
                direction.normalize!                                         # <-- Normalize vector
                
                # Create agent at clicked position
                agent = CameraAgentTool.create_camera_agent(@current_point, direction)  # <-- Create agent
                
                # Select the new agent
                Sketchup.active_model.selection.clear                        # <-- Clear selection
                Sketchup.active_model.selection.add(agent) if agent         # <-- Select new agent
                
                # Deactivate tool
                Sketchup.active_model.select_tool(nil)                      # <-- Deactivate tool
            end
        end
        
        def draw(view)
            if @current_point && @preview_transformation
                # Draw preview at current position
                view.drawing_color = Sketchup::Color.new(255, 0, 0, 128)    # <-- Semi-transparent red
                view.line_width = 2                                          # <-- Line width
                
                # Draw simple crosshair at position
                size = CameraAgentTool.mm_to_inch(500)                      # <-- Crosshair size
                pt = @current_point                                          # <-- Center point
                
                view.draw_line([pt.x - size, pt.y, pt.z], [pt.x + size, pt.y, pt.z])  # <-- Horizontal line
                view.draw_line([pt.x, pt.y - size, pt.z], [pt.x, pt.y + size, pt.z])  # <-- Vertical line
                
                # Draw direction arrow
                direction = @preview_transformation.xaxis                    # <-- Get direction
                arrow_length = CameraAgentTool.mm_to_inch(1000)            # <-- Arrow length
                arrow_end = pt + direction.to_a.map { |v| v * arrow_length }  # <-- Arrow end point
                
                view.draw_line(pt, arrow_end)                               # <-- Draw arrow line
            end
        end
        
        def getExtents
            bb = Geom::BoundingBox.new                                      # <-- Create bounding box
            if @current_point
                bb.add(@current_point)                                       # <-- Add current point
                size = CameraAgentTool.mm_to_inch(3000)                    # <-- Preview size
                bb.add([@current_point.x + size, @current_point.y + size, @current_point.z + size])
                bb.add([@current_point.x - size, @current_point.y - size, @current_point.z - size])
            end
            return bb                                                        # <-- Return bounding box
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate Placement Tool
    # ------------------------------------------------------------
    def self.activate_placement_tool
        @placement_tool = CameraAgentPlacementTool.new                      # <-- Create new tool
        Sketchup.active_model.select_tool(@placement_tool)                  # <-- Activate tool
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Selection Observer
# -----------------------------------------------------------------------------

    # CLASS | Camera Agent Selection Observer
    # ------------------------------------------------------------
    class CameraAgentSelectionObserver < Sketchup::SelectionObserver
        def onSelectionBulkChange(selection)
            return unless CameraAgentTool.dialog_visible?                    # <-- Skip if dialog not open
            
            # Check if a camera agent is selected
            selection.each do |entity|
                if entity.is_a?(Sketchup::ComponentInstance)
                    agent_id = entity.get_attribute("CameraAgent", "agentId")  # <-- Get agent ID
                    if agent_id
                        CameraAgentTool.handle_agent_selection(entity, agent_id)  # <-- Handle selection
                        return
                    end
                end
            end
            
            # No agent selected - clear dialog
            CameraAgentTool.clear_dialog_selection                          # <-- Clear selection
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Setup Selection Observer
    # ---------------------------------------------------------------
    def self.setup_selection_observer
        @selection_observer = CameraAgentSelectionObserver.new              # <-- Create observer
        Sketchup.active_model.selection.add_observer(@selection_observer)   # <-- Add to selection
    end
    # ---------------------------------------------------------------

    # FUNCTION | Handle Agent Selection
    # ------------------------------------------------------------
    def self.handle_agent_selection(agent_instance, agent_id)
        @current_agent = agent_instance                                      # <-- Store current agent
        
        # Load agent data
        agent_data = load_agent_from_model_dictionary(agent_id)            # <-- Load from dictionary
        
        if agent_data
            # Update position from current instance location
            update_agent_position_data(agent_data, agent_instance)          # <-- Update position
            
            # Send to dialog
            update_dialog_with_agent_data(agent_data)                       # <-- Update dialog
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Update Dialog with Agent Data
    # ------------------------------------------------------------
    def self.update_dialog_with_agent_data(agent_data)
        return unless @dialog && @dialog.visible?                           # <-- Check dialog exists
        
        js_command = "initFromAgentData(#{agent_data.to_json});"           # <-- Create JS command
        @dialog.execute_script(js_command)                                   # <-- Execute in dialog
    end
    # ---------------------------------------------------------------

    # FUNCTION | Clear Dialog Selection
    # ------------------------------------------------------------
    def self.clear_dialog_selection
        return unless @dialog && @dialog.visible?                           # <-- Check dialog exists
        
        @current_agent = nil                                                 # <-- Clear current agent
        @dialog.execute_script("clearDialog();")                            # <-- Clear dialog fields
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Check Dialog Visibility
    # ------------------------------------------------------------
    def self.dialog_visible?
        @dialog && @dialog.visible?                                          # <-- Return visibility state
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Check for Existing Agent Selection
    # ---------------------------------------------------------------
    def self.check_for_existing_agent_selection
        selection = Sketchup.active_model.selection                         # <-- Get current selection
        
        selection.each do |entity|
            if entity.is_a?(Sketchup::ComponentInstance)
                agent_id = entity.get_attribute("CameraAgent", "agentId")   # <-- Check for agent ID
                if agent_id
                    handle_agent_selection(entity, agent_id)                # <-- Handle if found
                    return
                end
            end
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------



    # FUNCTION | Initialize Camera Agent Tool
    # ------------------------------------------------------------
    def self.init
        @dialog = nil                                                        # <-- Initialize dialog
        @selection_observer = nil                                            # <-- Initialize observer
        @current_agent = nil                                                 # <-- Initialize current agent
        @placement_tool = nil                                                # <-- Initialize placement tool
    end
    # ---------------------------------------------------------------

end # module CameraAgentTool

# Initialize the module
CameraAgentTool.init 