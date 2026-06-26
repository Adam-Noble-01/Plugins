# =============================================================================
# VALEDESIGNSUITE - BENCH CONFIGURATOR
# =============================================================================
#
# FILE       : BenchConfigurator.rb
# NAMESPACE  : BenchConfigurator
# MODULE     : BenchConfigurator
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Live Configurable Bench Builder for SketchUp
# VERSION    : 1.0.0
# CREATED    : 2025
#
# DESCRIPTION:
# - This script implements a configurable bench builder for SketchUp.
# - It uses a UI::HtmlDialog for interactive configuration of bench dimensions.
# - The bench is built based on JSON configuration data.
# - All dimensions are specified in millimeters and converted to inches for SketchUp.
# - Real-time preview updates as sliders are adjusted.
# - Supports multiple bench instances with automatic selection switching.
# =============================================================================

require 'sketchup.rb'
require 'json'

module BenchConfigurator

# -----------------------------------------------------------------------------
# REGION | Module Constants and Configuration
# -----------------------------------------------------------------------------

# MODULE CONSTANTS | Unit Conversion and Dictionary Keys
# ------------------------------------------------------------
MM_TO_INCH              =   1.0 / 25.4                                    # <-- Millimeter to inch conversion factor
BENCH_DICT_NAME         =   "BenchConfigurator_Config"                    # <-- Dictionary name for storing bench configuration
# endregion ----------------------------------------------------


# MODULE CONSTANTS | Default Bench Configuration JSON
# ------------------------------------------------------------
DEFAULT_CONFIG_JSON = <<~JSON_STRING
{
    "ComponentParent" : {
    "Component_Name"               :  "Test_Bench_Component",
    "Component_Version"            :  "1.0.0",
    "Component_Author"             :  "Adam Noble",
    "Component_Description"        :  "A simple bench component",
    "Component_Default_Length_mm"  :  1500,
    "Component_Default_Height_mm"  :  600,
    "Component_Default_Depth_mm"   :  500,
    "Component_UI_MinLength_mm"    :  1000,
    "Component_UI_MaxLength_mm"    :  3000,
    "Component_UI_MinHeight_mm"    :  500,
    "Component_UI_MaxHeight_mm"    :  800,
    "Component_UI_MinDepth_mm"     :  400,
    "Component_UI_MaxDepth_mm"     :  600
    }, 
    "SubComponents_Level-01" : { 
    "Bench_FrontLeftLeg" : { 
        "Position"    : { "PosX_mm" :  0,    "PosY_mm" : 0,   "PosZ_mm" : 0   }, 
        "Dimensions"  : { "LenX_mm" : 50,   "LenY_mm" : 50,   "LenZ_mm" : 600 }, 
        "Rotation"    : { "RotX_deg" : 0,   "RotY_deg" : 0,   "RotZ_deg" : 0  } 
    },  
    "Bench_FrontRightLeg" : { 
        "Position"    : { "PosX_mm"  : 1450, "PosY_mm" : 0,    "PosZ_mm"  : 0   }, 
        "Dimensions"  : { "LenX_mm"  : 50,   "LenY_mm" : 50,   "LenZ_mm"  : 600 }, 
        "Rotation"    : { "RotX_deg" : 0,   "RotY_deg" : 0,   "RotZ_deg" : 0   } 
    }, 
    "Bench_BackLeftLeg" : { 
        "Position"    : { "PosX_mm" :  0,   "PosY_mm" : 450,    "PosZ_mm" : 0 }, 
        "Dimensions"  : { "LenX_mm" : 50,   "LenY_mm" : 50,   "LenZ_mm" : 600 }, 
        "Rotation"    : { "RotX_deg" : 0,   "RotY_deg" : 0,   "RotZ_deg" : 0  } 
    },  
    "Bench_BackRightLeg" : { 
        "Position"    : { "PosX_mm" : 1450, "PosY_mm" : 450,    "PosZ_mm" : 0 }, 
        "Dimensions"  : { "LenX_mm" : 50,   "LenY_mm" : 50,   "LenZ_mm" : 600 }, 
        "Rotation"    : { "RotX_deg" : 0,   "RotY_deg" : 0,   "RotZ_deg" : 0  } 
    }, 
    "Bench_SeatTop" : { 
        "Position"    : { "PosX_mm" : 0,    "PosY_mm" : 0,    "PosZ_mm" : 600 }, 
        "Dimensions"  : { "LenX_mm" : 1500, "LenY_mm" : 500,  "LenZ_mm" : 50  }, 
        "Rotation"    : { "RotX_deg" : 0,   "RotY_deg" : 0,   "RotZ_deg" : 0  } 
    } 
}
}
JSON_STRING
# endregion ----------------------------------------------------



# MODULE VARIABLES | Component References and State
# ------------------------------------------------------------
DEFAULT_CONFIG          =   JSON.parse(DEFAULT_CONFIG_JSON)               # <-- Parsed default configuration
@component_refs         =   {}                                            # <-- References to sub-components for transformations
@bench_component        =   nil                                           # <-- Current bench component instance
@config                 =   DEFAULT_CONFIG.dup                            # <-- Current configuration
@dialog                 =   nil                                           # <-- HTML dialog instance
@selection_observer     =   nil                                           # <-- Selection observer instance
# endregion ----------------------------------------------------

# endregion -------------------------------------------------------------------


# CRITICAL HELPER FUNCTION | Convert Millimeters to Inches
# ------------------------------------------------------------
# Note : SketchUps Geometry Engine works in inches so this must be called and respected.
def self.mm_to_inch(mm)
    mm * MM_TO_INCH                                                      # <-- Apply conversion factor
end
# endregion ----------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Dictionary Functions - Store and Retrieve Bench Config Data
# -----------------------------------------------------------------------------

# FUNCTION | Save Bench Configuration to Component Dictionary
# ------------------------------------------------------------
def self.save_config_to_component(component, config)
    return unless component && component.valid?                           # <-- Validate component exists
    
    dict = component.definition.attribute_dictionary(BENCH_DICT_NAME, true)  # <-- Create dictionary if needed
    
    config_json = JSON.generate(config)                                  # <-- Serialize config to JSON
    dict["bench_config"] = config_json                                   # <-- Store serialized config
    
    dict["bench_config_formatted"] = format_json(config)                 # <-- Store formatted version
end
# endregion ----------------------------------------------------


# FUNCTION | Load Bench Configuration from Component Dictionary
# ------------------------------------------------------------
def self.load_config_from_component(component)
    return DEFAULT_CONFIG.dup unless component && component.valid?        # <-- Return default if invalid
    
    dict = component.definition.attribute_dictionary(BENCH_DICT_NAME)     # <-- Get dictionary if exists
    return DEFAULT_CONFIG.dup unless dict                                # <-- Return default if no dict
    
    config_json = dict["bench_config"]                                   # <-- Get config JSON from dict
    return DEFAULT_CONFIG.dup unless config_json                         # <-- Return default if no config
    
    begin
        config = JSON.parse(config_json)                                 # <-- Parse JSON config
        return config
    rescue
        return DEFAULT_CONFIG.dup                                        # <-- Return default on parse error
    end
end
# endregion ----------------------------------------------------


# HELPER FUNCTION | Format JSON with Column Alignment
# ------------------------------------------------------------
def self.format_json(json_obj)
    JSON.pretty_generate(json_obj)                                       # <-- Generate formatted JSON
end
# endregion ----------------------------------------------------

# endregion -------------------------------------------------------------------



# -----------------------------------------------------------------------------
# REGION | Geometry Functions - Create and Update Bench Geometry
# -----------------------------------------------------------------------------

    # FUNCTION | Create Initial Bench Geometry from Configuration
    # ------------------------------------------------------------
    def self.create_bench_geometry(config)
        return nil unless validate_bench_creation_preconditions              # Validate preconditions for creation
        
        model = Sketchup.active_model                                        # Get active SketchUp model
        model.start_operation("Create Bench", true)                         # Start operation for undo support
        
        bench_instance = create_main_bench_component(config)                 # Create main component structure
        create_all_bench_subcomponents(bench_instance.definition, config)   # Create all sub-components
        finalize_bench_creation(bench_instance, config)                     # Finalize and save bench
        
        model.commit_operation                                               # Commit the operation
        
        @bench_component = bench_instance                                    # Store bench component instance
        return bench_instance                                                # Return created bench instance
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Validate Preconditions for Bench Creation
    # ---------------------------------------------------------------
    def self.validate_bench_creation_preconditions
        return false unless Sketchup.active_model                           # Check active model exists
        return true                                                          # All preconditions met
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create Main Bench Component Structure
    # ---------------------------------------------------------------
    def self.create_main_bench_component(config)
        model = Sketchup.active_model                                        # Get active model reference
        bench_def = model.definitions.add("Bench_Component")                 # Create main component definition
        bench_instance = model.active_entities.add_instance(bench_def, Geom::Transformation.new)  # Create instance
        bench_instance.name = config["ComponentParent"]["Component_Name"]    # Set component name
        
        @component_refs = {}                                                 # Initialize component references hash
        return bench_instance                                                # Return created bench instance
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create All Bench Sub-Components
    # ---------------------------------------------------------------
    def self.create_all_bench_subcomponents(bench_definition, config)
        create_all_leg_components(bench_definition, config)                 # Create all four leg components
        create_seat_component(bench_definition, config)                     # Create seat top component
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create All Leg Components
    # ---------------------------------------------------------------
    def self.create_all_leg_components(bench_definition, config)
        create_front_leg_components(bench_definition, config)               # Create front legs
        create_back_leg_components(bench_definition, config)                # Create back legs
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Front Leg Components
    # ---------------------------------------------------------------
    def self.create_front_leg_components(bench_definition, config)
        create_front_left_leg_component(bench_definition, config)           # Create front left leg
        create_front_right_leg_component(bench_definition, config)          # Create front right leg
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Back Leg Components
    # ---------------------------------------------------------------
    def self.create_back_leg_components(bench_definition, config)
        create_back_left_leg_component(bench_definition, config)            # Create back left leg
        create_back_right_leg_component(bench_definition, config)           # Create back right leg
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Front Left Leg Component
    # ---------------------------------------------------------------
    def self.create_front_left_leg_component(bench_definition, config)
        leg_data = config["SubComponents_Level-01"]["Bench_FrontLeftLeg"]   # Get leg configuration data
        leg_group = create_leg_group(bench_definition, "Bench_FrontLeftLeg", leg_data)  # Create leg group with geometry
        @component_refs["Bench_FrontLeftLeg"] = leg_group                   # Store component reference
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Front Right Leg Component
    # ---------------------------------------------------------------
    def self.create_front_right_leg_component(bench_definition, config)
        leg_data = config["SubComponents_Level-01"]["Bench_FrontRightLeg"]  # Get leg configuration data
        leg_group = create_leg_group(bench_definition, "Bench_FrontRightLeg", leg_data)  # Create leg group with geometry
        @component_refs["Bench_FrontRightLeg"] = leg_group                  # Store component reference
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Back Left Leg Component
    # ---------------------------------------------------------------
    def self.create_back_left_leg_component(bench_definition, config)
        leg_data = config["SubComponents_Level-01"]["Bench_BackLeftLeg"]    # Get leg configuration data
        leg_group = create_leg_group(bench_definition, "Bench_BackLeftLeg", leg_data)  # Create leg group with geometry
        @component_refs["Bench_BackLeftLeg"] = leg_group                    # Store component reference
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Back Right Leg Component
    # ---------------------------------------------------------------
    def self.create_back_right_leg_component(bench_definition, config)
        leg_data = config["SubComponents_Level-01"]["Bench_BackRightLeg"]   # Get leg configuration data
        leg_group = create_leg_group(bench_definition, "Bench_BackRightLeg", leg_data)  # Create leg group with geometry
        @component_refs["Bench_BackRightLeg"] = leg_group                   # Store component reference
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Seat Component
    # ---------------------------------------------------------------
    def self.create_seat_component(bench_definition, config)
        seat_data = config["SubComponents_Level-01"]["Bench_SeatTop"]       # Get seat configuration data
        seat_group = create_seat_group(bench_definition, "Bench_SeatTop", seat_data)  # Create seat group with geometry
        @component_refs["Bench_SeatTop"] = seat_group                       # Store component reference
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Create Leg Group with Geometry
    # ---------------------------------------------------------------
    def self.create_leg_group(bench_definition, leg_name, leg_data)
        leg_group = bench_definition.entities.add_group                     # Create group for leg
        leg_group.name = leg_name                                           # Set group name
        
        create_box(                                                         # Create box geometry
            leg_group.entities,
            mm_to_inch(leg_data["Position"]["PosX_mm"]),                    # Convert position to inches
            mm_to_inch(leg_data["Position"]["PosY_mm"]),
            mm_to_inch(leg_data["Position"]["PosZ_mm"]),
            mm_to_inch(leg_data["Dimensions"]["LenX_mm"]),                  # Convert dimensions to inches
            mm_to_inch(leg_data["Dimensions"]["LenY_mm"]),
            mm_to_inch(leg_data["Dimensions"]["LenZ_mm"])
        )
        
        return leg_group                                                    # Return created leg group
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Create Seat Group with Geometry
    # ---------------------------------------------------------------
    def self.create_seat_group(bench_definition, seat_name, seat_data)
        seat_group = bench_definition.entities.add_group                    # Create group for seat
        seat_group.name = seat_name                                         # Set group name
        
        create_box(                                                         # Create box geometry
            seat_group.entities,
            mm_to_inch(seat_data["Position"]["PosX_mm"]),                   # Convert position to inches
            mm_to_inch(seat_data["Position"]["PosY_mm"]),
            mm_to_inch(seat_data["Position"]["PosZ_mm"]),
            mm_to_inch(seat_data["Dimensions"]["LenX_mm"]),                 # Convert dimensions to inches
            mm_to_inch(seat_data["Dimensions"]["LenY_mm"]),
            mm_to_inch(seat_data["Dimensions"]["LenZ_mm"])
        )
        
        return seat_group                                                   # Return created seat group
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Finalize Bench Creation Process
    # ---------------------------------------------------------------
    def self.finalize_bench_creation(bench_instance, config)
        save_config_to_component(bench_instance, config)                   # Save config to component dictionary
        add_materials(bench_instance.definition.entities)                  # Apply materials to components
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Bench Geometry Manipulation - Post Creation Updates
# -----------------------------------------------------------------------------

    # FUNCTION | Update Bench Geometry Based on New Configuration
    # ------------------------------------------------------------
    def self.update_bench_geometry(length_mm, height_mm, depth_mm)
        return unless validate_bench_update_preconditions                    # <-- Validate preconditions for update
        
        model = Sketchup.active_model                                        # <-- Get active model
        model.start_operation("Update Bench", true)                         # <-- Start operation for undo support
        
        scale_factors = calculate_geometry_scale_factors(length_mm, height_mm, depth_mm)  # <-- Calculate transformation scales
        update_configuration_values(length_mm, height_mm, depth_mm)         # <-- Update internal configuration
        
        transform_all_bench_components(scale_factors, length_mm, height_mm, depth_mm)  # <-- Apply transformations to components
        
        save_config_to_component(@bench_component, @config)                 # <-- Save updated config to dictionary
        model.commit_operation                                               # <-- Commit the operation
    end
    # ---------------------------------------------------------------


    # SUB FUNCTION | Validate Preconditions for Bench Update
    # ---------------------------------------------------------------
    def self.validate_bench_update_preconditions
        return false unless @bench_component && @bench_component.valid?      # <-- Check bench component exists and valid
        return false unless Sketchup.active_model                           # <-- Check active model exists
        return true                                                          # <-- All preconditions met
    end

    # ---------------------------------------------------------------


    # SUB FUNCTION | Calculate Scale Factors for Geometry Transformation
    # ------------------------------------------------------------
    def self.calculate_geometry_scale_factors(length_mm, height_mm, depth_mm)
        current_length_mm = @config["ComponentParent"]["Component_Default_Length_mm"]  # <-- Get current dimensions
        current_height_mm = @config["ComponentParent"]["Component_Default_Height_mm"]
        current_depth_mm = @config["ComponentParent"]["Component_Default_Depth_mm"]
        
        scale_factors = {                                                    # <-- Create scale factors hash
            length: length_mm.to_f / current_length_mm.to_f,               # <-- Calculate length scale
            height: height_mm.to_f / current_height_mm.to_f,               # <-- Calculate height scale
            depth:  depth_mm.to_f / current_depth_mm.to_f                  # <-- Calculate depth scale
        }
        
        return scale_factors                                                 # <-- Return calculated scales
    end
    # ---------------------------------------------------------------


    # SUB FUNCTION | Update Internal Configuration Values
    # ------------------------------------------------------------
    def self.update_configuration_values(length_mm, height_mm, depth_mm)
        update_parent_configuration(length_mm, height_mm, depth_mm)         # <-- Update parent component config
        update_seat_configuration(length_mm, height_mm, depth_mm)           # <-- Update seat component config
        update_legs_configuration(length_mm, height_mm, depth_mm)           # <-- Update all legs configuration
    end
    # ---------------------------------------------------------------


    # SUB HELPER FUNCTION | Update Parent Component Configuration
    # ------------------------------------------------------------
    def self.update_parent_configuration(length_mm, height_mm, depth_mm)
        @config["ComponentParent"]["Component_Default_Length_mm"] = length_mm  # <-- Set new length
        @config["ComponentParent"]["Component_Default_Height_mm"] = height_mm  # <-- Set new height
        @config["ComponentParent"]["Component_Default_Depth_mm"] = depth_mm    # <-- Set new depth

    # ---------------------------------------------------------------


    # SUB HELPER FUNCTION | Update Seat Component Configuration
    # ------------------------------------------------------------
    def self.update_seat_configuration(length_mm, height_mm, depth_mm)
        seat_config = @config["SubComponents_Level-01"]["Bench_SeatTop"]     # <-- Get seat configuration reference
        
        seat_config["Dimensions"]["LenX_mm"] = length_mm                     # <-- Update seat length
        seat_config["Dimensions"]["LenY_mm"] = depth_mm                      # <-- Update seat depth
        seat_config["Position"]["PosZ_mm"] = height_mm                       # <-- Update seat height position
    end

    # ---------------------------------------------------------------


    # SUB HELPER FUNCTION | Update All Legs Configuration
    # ------------------------------------------------------------
    def self.update_legs_configuration(length_mm, height_mm, depth_mm)
        update_front_legs_configuration(length_mm, height_mm)               # <-- Update front legs config
        update_back_legs_configuration(length_mm, height_mm, depth_mm)      # <-- Update back legs config
    end

    # ---------------------------------------------------------------


    # SUB HELPER FUNCTION | Update Front Legs Configuration
    # ------------------------------------------------------------
    def self.update_front_legs_configuration(length_mm, height_mm)
        front_left_config = @config["SubComponents_Level-01"]["Bench_FrontLeftLeg"]   # <-- Get front left leg config
        front_right_config = @config["SubComponents_Level-01"]["Bench_FrontRightLeg"] # <-- Get front right leg config
        
        front_left_config["Dimensions"]["LenZ_mm"] = height_mm               # <-- Update front left leg height
        front_right_config["Dimensions"]["LenZ_mm"] = height_mm              # <-- Update front right leg height
        front_right_config["Position"]["PosX_mm"] = length_mm - LEG_WIDTH_MM  # <-- Update front right leg X position
    end

    # ---------------------------------------------------------------


    # SUB HELPER FUNCTION | Update Back Legs Configuration
    # ------------------------------------------------------------
    def self.update_back_legs_configuration(length_mm, height_mm, depth_mm)
        back_left_config = @config["SubComponents_Level-01"]["Bench_BackLeftLeg"]     # <-- Get back left leg config
        back_right_config = @config["SubComponents_Level-01"]["Bench_BackRightLeg"]   # <-- Get back right leg config
        
        back_left_config["Dimensions"]["LenZ_mm"] = height_mm                # <-- Update back left leg height
        back_left_config["Position"]["PosY_mm"] = depth_mm - LEG_DEPTH_MM    # <-- Update back left leg Y position
        
        back_right_config["Dimensions"]["LenZ_mm"] = height_mm               # <-- Update back right leg height
        back_right_config["Position"]["PosX_mm"] = length_mm - LEG_WIDTH_MM  # <-- Update back right leg X position
        back_right_config["Position"]["PosY_mm"] = depth_mm - LEG_DEPTH_MM   # <-- Update back right leg Y position
    end
    # ---------------------------------------------------------------


    # SUB FUNCTION | Transform All Bench Components
    # ------------------------------------------------------------
    def self.transform_all_bench_components(scale_factors, length_mm, height_mm, depth_mm)
        transform_front_legs(scale_factors, length_mm, height_mm)           # <-- Transform front legs
        transform_back_legs(scale_factors, length_mm, height_mm, depth_mm)  # <-- Transform back legs
        transform_seat_component(scale_factors, height_mm)                  # <-- Transform seat component
    end
    # ---------------------------------------------------------------


    # SUB HELPER FUNCTION | Transform Front Legs Components
    # ------------------------------------------------------------
    def self.transform_front_legs(scale_factors, length_mm, height_mm)
        transform_front_left_leg(scale_factors[:height])                    # <-- Transform front left leg
        transform_front_right_leg(scale_factors, length_mm)                 # <-- Transform front right leg
    end
    # ---------------------------------------------------------------


    # SUB HELPER FUNCTION | Transform Back Legs Components
    # ------------------------------------------------------------
    def self.transform_back_legs(scale_factors, length_mm, height_mm, depth_mm)
        transform_back_left_leg(scale_factors, depth_mm)                    # <-- Transform back left leg
        transform_back_right_leg(scale_factors, length_mm, depth_mm)        # <-- Transform back right leg
    end
    # ---------------------------------------------------------------


    # SUB HELPER FUNCTION | Transform Front Left Leg Component
    # ------------------------------------------------------------
    def self.transform_front_left_leg(height_scale)
        front_left_leg
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Dialog Functions - Create and Manage HTML Dialog
# -----------------------------------------------------------------------------

# FUNCTION | Show Bench Configurator Dialog
# ------------------------------------------------------------
def self.show_dialog
    if @dialog && @dialog.visible?                                       # <-- Return if dialog already showing
        @dialog.bring_to_front
        return
    end
    
    @dialog = UI::HtmlDialog.new(                                        # <-- Create the dialog
        dialog_title: "Bench Configurator",
        preferences_key: "BenchConfigurator",
        width: 400,
        height: 600,
        left: 200,
        top: 200,
        resizable: true
    )
    
    html_content = <<-HTML                                               # <-- Set HTML content
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <title>Bench Configurator</title>
      <style>
        body {
          font-family: Arial, sans-serif;
          margin: 0;
          padding: 20px;
          background-color: #f0f0f0;
          color: #333;
        }
        h1 {
          color: #555;
          font-size: 20px;
          margin-bottom: 20px;
          text-align: center;
        }
        .slider-container {
          margin-bottom: 20px;
        }
        label {
          display: block;
          margin-bottom: 5px;
          font-weight: bold;
        }
        input[type="range"] {
          width: 100%;
          margin: 10px 0;
        }
        .value-display {
          text-align: center;
          font-size: 16px;
          margin-top: 5px;
          color: #0066cc;
        }
        button {
          background-color: #4CAF50;
          color: white;
          border: none;
          padding: 10px 15px;
          text-align: center;
          text-decoration: none;
          display: inline-block;
          font-size: 16px;
          margin: 10px 0;
          cursor: pointer;
          border-radius: 4px;
          width: 100%;
        }
        button:hover {
          background-color: #45a049;
        }
        hr {
          margin: 20px 0;
          border: 0;
          border-top: 1px solid #ddd;
        }
        .footer {
          margin-top: 20px;
          font-size: 12px;
          color: #888;
          text-align: center;
        }
      </style>
    </head>
    <body>
      <h1>Bench Configurator</h1>
      
      <div class="slider-container">
        <label for="length-slider">Bench Length (mm):</label>
        <input type="range" id="length-slider" min="1000" max="3000" value="1500" oninput="updateLength(this.value)">
        <div id="length-value" class="value-display">1500 mm</div>
      </div>
      
      <div class="slider-container">
        <label for="height-slider">Bench Height (mm):</label>
        <input type="range" id="height-slider" min="500" max="800" value="600" oninput="updateHeight(this.value)">
        <div id="height-value" class="value-display">600 mm</div>
      </div>
      
      <div class="slider-container">
        <label for="depth-slider">Bench Depth (mm):</label>
        <input type="range" id="depth-slider" min="400" max="600" value="500" oninput="updateDepth(this.value)">
        <div id="depth-value" class="value-display">500 mm</div>
      </div>
      
      <hr>
      
      <button id="create-bench-btn" onclick="createBench()">Create Bench</button>
      
      <div class="footer">
        Vale Design Suite - Bench Configurator Tool v1.0.0
      </div>
      
      <script>
        let lengthValue = 1500;
        let heightValue = 600;
        let depthValue = 500;
        let benchCreated = false;
        
        function initFromConfig(config) {
          if (!config) return;
          
          try {
            const parentConfig = config.ComponentParent;
            
            lengthValue = parentConfig.Component_Default_Length_mm;
            heightValue = parentConfig.Component_Default_Height_mm;
            depthValue = parentConfig.Component_Default_Depth_mm;
            
            document.getElementById('length-slider').value = lengthValue;
            document.getElementById('length-value').textContent = lengthValue + ' mm';
            
            document.getElementById('height-slider').value = heightValue;
            document.getElementById('height-value').textContent = heightValue + ' mm';
            
            document.getElementById('depth-slider').value = depthValue;
            document.getElementById('depth-value').textContent = depthValue + ' mm';
            
            document.getElementById('length-slider').min = parentConfig.Component_UI_MinLength_mm;
            document.getElementById('length-slider').max = parentConfig.Component_UI_MaxLength_mm;
            
            document.getElementById('height-slider').min = parentConfig.Component_UI_MinHeight_mm;
            document.getElementById('height-slider').max = parentConfig.Component_UI_MaxHeight_mm;
            
            document.getElementById('depth-slider').min = parentConfig.Component_UI_MinDepth_mm;
            document.getElementById('depth-slider').max = parentConfig.Component_UI_MaxDepth_mm;
            
            document.getElementById('create-bench-btn').textContent = benchCreated ? 'Update Bench' : 'Create Bench';
            
          } catch (e) {
            console.error('Error initializing from config:', e);
          }
        }
        
        function updateLength(value) {
          lengthValue = parseInt(value);
          document.getElementById('length-value').textContent = value + ' mm';
          if (benchCreated) {
            updateBench();
          }
        }
        
        function updateHeight(value) {
          heightValue = parseInt(value);
          document.getElementById('height-value').textContent = value + ' mm';
          if (benchCreated) {
            updateBench();
          }
        }
        
        function updateDepth(value) {
          depthValue = parseInt(value);
          document.getElementById('depth-value').textContent = value + ' mm';
          if (benchCreated) {
            updateBench();
          }
        }
        
        function createBench() {
          if (benchCreated) {
            updateBench();
          } else {
            sketchup.createBench(lengthValue, heightValue, depthValue);
            benchCreated = true;
            document.getElementById('create-bench-btn').textContent = 'Update Bench';
          }
        }
        
        function updateBench() {
          sketchup.updateBench(lengthValue, heightValue, depthValue);
        }
        
        window.setInitialConfig = function(configJson) {
          const config = JSON.parse(configJson);
          benchCreated = true;
          initFromConfig(config);
        };
      </script>
    </body>
    </html>
    HTML
    
    @dialog.set_html(html_content)                                       # <-- Set dialog HTML content
    
    @dialog.add_action_callback("createBench") do |action_context, length_mm, height_mm, depth_mm|  # <-- Set up callbacks
        @config["ComponentParent"]["Component_Default_Length_mm"] = length_mm  # <-- Update config with new values
        @config["ComponentParent"]["Component_Default_Height_mm"] = height_mm
        @config["ComponentParent"]["Component_Default_Depth_mm"] = depth_mm
        
        create_bench_geometry(@config)                                   # <-- Create bench geometry
        @dialog.execute_script("window.setInitialConfig('#{JSON.generate(@config).gsub("'", "\\\\'")}');")  # <-- Update dialog
    end
    
    @dialog.add_action_callback("updateBench") do |action_context, length_mm, height_mm, depth_mm|  # <-- Update callback
        update_bench_geometry(length_mm, height_mm, depth_mm)           # <-- Update bench geometry
    end
    
    @dialog.show                                                         # <-- Show the dialog
    
    model = Sketchup.active_model                                        # <-- Check for existing bench selection
    if model && model.selection.size == 1
        selected = model.selection[0]
        if selected.is_a?(Sketchup::ComponentInstance)
            config = load_config_from_component(selected)                # <-- Load config from selected bench
            if config
                @config = config
                @bench_component = selected
                
                @component_refs = {}                                     # <-- Get references to sub-components
                selected.definition.entities.grep(Sketchup::Group).each do |group|
                    @component_refs[group.name] = group if ["Bench_FrontLeftLeg", "Bench_FrontRightLeg", "Bench_BackLeftLeg", "Bench_BackRightLeg", "Bench_SeatTop"].include?(group.name)
                end
                
                @dialog.execute_script("window.setInitialConfig('#{JSON.generate(@config).gsub("'", "\\\\'")}');")  # <-- Update dialog with loaded config
            end
        end
    end
end
# endregion ----------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Selection Observer - Monitor Selection Changes
# -----------------------------------------------------------------------------

# CLASS | Bench Selection Observer for Multi-Bench Support
# ------------------------------------------------------------
class BenchSelectionObserver < Sketchup::SelectionObserver
    def onSelectionBulkChange(selection)
        return unless BenchConfigurator.dialog_visible?                  # <-- Skip if dialog not open
        
        if selection.size == 1 && selection[0].is_a?(Sketchup::ComponentInstance)  # <-- Check single component selected
            component = selection[0]
            
            dict = component.definition.attribute_dictionary(BENCH_DICT_NAME)  # <-- Check for bench config dictionary
            if dict && dict["bench_config"]
                config = BenchConfigurator.load_config_from_component(component)  # <-- Load config and update dialog
                BenchConfigurator.set_bench_component(component, config)
            end
        end
    end
end
# endregion ----------------------------------------------------


# HELPER FUNCTION | Check if Dialog is Visible
# ------------------------------------------------------------
def self.dialog_visible?
    @dialog && @dialog.visible?                                          # <-- Return dialog visibility state
end
# endregion ----------------------------------------------------


# FUNCTION | Set Bench Component and Update Dialog
# ------------------------------------------------------------
def self.set_bench_component(component, config)
    @bench_component = component                                         # <-- Set current bench component
    @config = config                                                     # <-- Set current config
    
    @component_refs = {}                                                 # <-- Get references to sub-components
    component.definition.entities.grep(Sketchup::Group).each do |group|
        @component_refs[group.name] = group if ["Bench_FrontLeftLeg", "Bench_FrontRightLeg", "Bench_BackLeftLeg", "Bench_BackRightLeg", "Bench_SeatTop"].include?(group.name)
    end
    
    @dialog.execute_script("window.setInitialConfig('#{JSON.generate(@config).gsub("'", "\\\\'")}');") if @dialog && @dialog.visible?  # <-- Update dialog with loaded config
end
# endregion ----------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Main Initialization - Set Up Tool and Show Dialog
# -----------------------------------------------------------------------------

# FUNCTION | Initialize the Bench Configurator Tool
# ------------------------------------------------------------
def self.init
    @selection_observer = BenchSelectionObserver.new                    # <-- Add selection observer
    Sketchup.active_model.selection.add_observer(@selection_observer)
    
    show_dialog                                                          # <-- Show the dialog
end
# endregion ----------------------------------------------------

# endregion -------------------------------------------------------------------

end

# Initialize the tool when the script is loaded
BenchConfigurator.init 