# =============================================================================
# VALEDESIGNSUITE - WINDOW CONFIGURATOR
# =============================================================================
#
# FILE       : ATest01_-_WindowConfigurator.rb
# NAMESPACE  : WindowConfigurator
# MODULE     : WindowConfigurator
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Live Configurable Window Builder for SketchUp
# CREATED    : 2025
#
# DESCRIPTION:
# - This script implements a configurable window builder for SketchUp.
# - It uses a UI::HtmlDialog for interactive configuration of window dimensions.
# - The window is built based on JSON configuration data with frame, glass, and glaze bars.
# - All dimensions are specified in millimeters and converted to inches for SketchUp.
# - Real-time preview updates as sliders are adjusted.
# - Supports multiple window instances with automatic selection switching.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 25-May-2025 - Version 1.0.0
# - Initial Stable Release
#
# 25-May-2025 - Version 1.1.0
# - Bug Fixes & Stability Improvements
# - Colour Swatches Added & Dynamic material updating feature added.
#
# =============================================================================

require 'sketchup.rb'
require 'json'

module WindowConfigurator

# -----------------------------------------------------------------------------
# REGION | Module Constants and Configuration
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Unit Conversion and Dictionary Keys
    # ------------------------------------------------------------
    MM_TO_INCH              =   1.0 / 25.4                                    # <-- Millimeter to inch conversion factor
    WINDOW_DICT_NAME        =   "WindowConfigurator_Config"                   # <-- Dictionary name for storing window configuration
    FRAME_DEPTH_MM          =   50                                            # <-- Standard frame depth in millimeters
    FRAME_THICKNESS_MM      =   90                                            # <-- Default frame thickness in millimeters
    GLASS_DEPTH_MM          =   20                                            # <-- Glass pane depth in millimeters
    GLASS_OFFSET_MM         =   15                                            # <-- Glass offset from front face
    GLAZE_BAR_WIDTH_MM      =   20                                            # <-- Glaze bar width in millimeters
    GLAZE_BAR_THICKNESS_MM  =   30                                            # <-- Glaze bar thickness between panes
    # endregion ----------------------------------------------------


# REGION | MODULE CONFIG DATA | Default Window Configuration JSON
# -----------------------------------------------------------------------------

    DEFAULT_CONFIG_JSON = <<~JSON_STRING
    {
        "ComponentParent" : {
            "Component_Name"                        :  "Test_Window_Component",
            "Component_Version"                     :  "1.0.0",
            "Component_Author"                      :  "Adam Noble",
            "Component_Description"                 :  "A configurable Georgian-style window component",
            "Component_Default_Width_mm"            :  800,
            "Component_Default_Height_mm"           :  1500,
            "Component_Default_FrameThickness_mm"   :  90,
            "Component_Default_VerticalGlazeBars"   :  2,
            "Component_Default_HorizontalGlazeBars" :  3,
            "Component_Default_FrameColor"          :  "natural-wood",
            "Component_UI_MinWidth_mm"              :  400,
            "Component_UI_MaxWidth_mm"              :  1600,
            "Component_UI_MinHeight_mm"             :  500,
            "Component_UI_MaxHeight_mm"             :  3200,
            "Component_UI_MinFrameThickness_mm"     :  30,
            "Component_UI_MaxFrameThickness_mm"     :  150,
            "Component_UI_MinVerticalGlazeBars"     :  0,
            "Component_UI_MaxVerticalGlazeBars"     :  8,
            "Component_UI_MinHorizontalGlazeBars"   :  0,
            "Component_UI_MaxHorizontalGlazeBars"   :  6
        }, 
        "SubComponents_Level-01" : { 
            "Window_LeftJamb" : { 
                "Position"    : { "PosX_mm" :    0, "PosY_mm" :  0, "PosZ_mm" :   0 }, 
                "Dimensions"  : { "LenX_mm" :   90, "LenY_mm" : 50, "LenZ_mm" : 1500 }, 
                "Rotation"    : { "RotX_deg" :   0, "RotY_deg" :  0, "RotZ_deg" :   0 } 
            },  
            "Window_RightJamb" : { 
                "Position"    : { "PosX_mm" :  710, "PosY_mm" :  0, "PosZ_mm" :   0 }, 
                "Dimensions"  : { "LenX_mm" :   90, "LenY_mm" : 50, "LenZ_mm" : 1500 }, 
                "Rotation"    : { "RotX_deg" :   0, "RotY_deg" :  0, "RotZ_deg" :   0 } 
            }, 
            "Window_BottomRail" : { 
                "Position"    : { "PosX_mm" :   90, "PosY_mm" :  0, "PosZ_mm" :    0 }, 
                "Dimensions"  : { "LenX_mm" :  620, "LenY_mm" : 50, "LenZ_mm" :   90 }, 
                "Rotation"    : { "RotX_deg" :   0, "RotY_deg" :  0, "RotZ_deg" :   0 } 
            },  
            "Window_TopRail" : { 
                "Position"    : { "PosX_mm" :   90, "PosY_mm" :  0, "PosZ_mm" : 1410 }, 
                "Dimensions"  : { "LenX_mm" :  620, "LenY_mm" : 50, "LenZ_mm" :   90 }, 
                "Rotation"    : { "RotX_deg" :   0, "RotY_deg" :  0, "RotZ_deg" :   0 } 
            },
            "Window_Glass" : { 
                "Position"    : { "PosX_mm" :   90, "PosY_mm" : 15, "PosZ_mm" :   90 }, 
                "Dimensions"  : { "LenX_mm" :  620, "LenY_mm" : 20, "LenZ_mm" : 1320 }, 
                "Rotation"    : { "RotX_deg" :   0, "RotY_deg" :  0, "RotZ_deg" :   0 } 
            } 
        }
    }
    JSON_STRING
    # endregion --  --------------------------------------------------


    # MODULE VARIABLES | Component References and State
    # ------------------------------------------------------------
    DEFAULT_CONFIG          =   JSON.parse(DEFAULT_CONFIG_JSON)               # <-- Parsed default configuration
    @component_refs         =   {}                                            # <-- References to sub-components for transformations
    @window_component       =   nil                                           # <-- Current window component instance
    @config                 =   DEFAULT_CONFIG.dup                            # <-- Current configuration
    @dialog                 =   nil                                           # <-- HTML dialog instance
    @selection_observer     =   nil                                           # <-- Selection observer instance
    @glaze_bar_refs         =   []                                            # <-- References to glaze bar components
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


    # HELPER FUNCTION | Create Box Geometry
    # ---------------------------------------------------------------
    # Parameters:
    #   x, y, z: Coordinates for the base origin of the box (bottom-front-left corner of the initial face).
    #   width: Dimension of the box along the X-axis.
    #   height: Dimension of the box along the Y-axis.
    #   depth: Dimension of the box along the Z-axis (thickness for extrusion).
    def self.create_box(entities, x, y, z, width, height, depth)
        # Define points for the base face (on the XY plane at the given z height)
        points = [                                                           
            [x, y, z],
            [x + width, y, z],
            [x + width, y + height, z],
            [x, y + height, z]
        ]
        
        face = entities.add_face(points[0], points[1], points[2], points[3])  # <-- Create base face
        
        # Ensure the face normal is pointing upwards (+Z)
        if face.normal.z < 0
            face.reverse!                                                    # <-- Reverse face if normal is downwards
        end
        
        # Extrude the face upwards by the specified depth (thickness along Z)
        # Since normal.z is now 1 (or very close to it), positive depth extrudes in +Z.
        face.pushpull(depth)                                                 
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Dictionary Functions - Store and Retrieve Window Config Data
# -----------------------------------------------------------------------------

    # FUNCTION | Save Window Configuration to Component Dictionary
    # ------------------------------------------------------------
    def self.save_config_to_component(component, config)
        return unless component && component.valid?                           # <-- Validate component exists
        
        dict = component.definition.attribute_dictionary(WINDOW_DICT_NAME, true)  # <-- Create dictionary if needed
        
        config_json = JSON.generate(config)                                  # <-- Serialize config to JSON
        dict["window_config"] = config_json                                  # <-- Store serialized config
        
        dict["window_config_formatted"] = format_json(config)                # <-- Store formatted version
    end
    # ---------------------------------------------------------------


    # FUNCTION | Load Window Configuration from Component Dictionary
    # ------------------------------------------------------------
    def self.load_config_from_component(component)
        return DEFAULT_CONFIG.dup unless component && component.valid?        # <-- Return default if invalid
        
        dict = component.definition.attribute_dictionary(WINDOW_DICT_NAME)    # <-- Get dictionary if exists
        return DEFAULT_CONFIG.dup unless dict                                # <-- Return default if no dict
        
        config_json = dict["window_config"]                                  # <-- Get config JSON from dict
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
# REGION | Geometry Functions - Create and Update Window Geometry
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Update Frame Dimensions in a Config Object
    # ---------------------------------------------------------------
    def self.update_frame_dimensions_in_config(config_obj, width_mm, height_mm, frame_thickness_mm)
        stile_width = frame_thickness_mm
        rail_thickness = frame_thickness_mm

        # Left Jamb
        lj_conf = config_obj["SubComponents_Level-01"]["Window_LeftJamb"]
        lj_conf["Position"]["PosX_mm"] = 0
        lj_conf["Position"]["PosY_mm"] = 0 # Assuming Y is depth and constant from default
        lj_conf["Position"]["PosZ_mm"] = 0
        lj_conf["Dimensions"]["LenX_mm"] = stile_width
        lj_conf["Dimensions"]["LenY_mm"] = FRAME_DEPTH_MM # Use constant for depth
        lj_conf["Dimensions"]["LenZ_mm"] = height_mm

        # Right Jamb
        rj_conf = config_obj["SubComponents_Level-01"]["Window_RightJamb"]
        rj_conf["Position"]["PosX_mm"] = width_mm - stile_width
        rj_conf["Position"]["PosY_mm"] = 0 # Assuming Y is depth and constant from default
        rj_conf["Position"]["PosZ_mm"] = 0
        rj_conf["Dimensions"]["LenX_mm"] = stile_width
        rj_conf["Dimensions"]["LenY_mm"] = FRAME_DEPTH_MM # Use constant for depth
        rj_conf["Dimensions"]["LenZ_mm"] = height_mm
        
        rail_length = width_mm - (2 * stile_width)
        
        # Bottom Rail
        br_conf = config_obj["SubComponents_Level-01"]["Window_BottomRail"]
        br_conf["Position"]["PosX_mm"] = stile_width
        br_conf["Position"]["PosY_mm"] = 0 # Assuming Y is depth and constant from default
        br_conf["Position"]["PosZ_mm"] = 0
        br_conf["Dimensions"]["LenX_mm"] = rail_length
        br_conf["Dimensions"]["LenY_mm"] = FRAME_DEPTH_MM # Use constant for depth
        br_conf["Dimensions"]["LenZ_mm"] = rail_thickness
        
        # Top Rail
        tr_conf = config_obj["SubComponents_Level-01"]["Window_TopRail"]
        tr_conf["Position"]["PosX_mm"] = stile_width
        tr_conf["Position"]["PosY_mm"] = 0 # Assuming Y is depth and constant from default
        tr_conf["Position"]["PosZ_mm"] = height_mm - rail_thickness
        tr_conf["Dimensions"]["LenX_mm"] = rail_length
        tr_conf["Dimensions"]["LenY_mm"] = FRAME_DEPTH_MM # Use constant for depth
        tr_conf["Dimensions"]["LenZ_mm"] = rail_thickness
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Update Glass Dimensions in a Config Object
    # ---------------------------------------------------------------
    def self.update_glass_dimensions_in_config(config_obj, width_mm, height_mm, frame_thickness_mm)
        glass_width = width_mm - (2 * frame_thickness_mm)
        glass_height = height_mm - (2 * frame_thickness_mm)
        
        glass_conf = config_obj["SubComponents_Level-01"]["Window_Glass"]
        glass_conf["Position"]["PosX_mm"] = frame_thickness_mm
        glass_conf["Position"]["PosY_mm"] = GLASS_OFFSET_MM # Use constant for glass offset from front
        glass_conf["Position"]["PosZ_mm"] = frame_thickness_mm
        glass_conf["Dimensions"]["LenX_mm"] = glass_width
        glass_conf["Dimensions"]["LenY_mm"] = GLASS_DEPTH_MM    # Use constant for glass depth
        glass_conf["Dimensions"]["LenZ_mm"] = glass_height
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Prepare Full Configuration for New Window Creation
    # ---------------------------------------------------------------
    def self.prepare_config_for_creation(width_mm, height_mm, frame_thickness_mm, vertical_bars, horizontal_bars, frame_color)
        config = DEFAULT_CONFIG.dup

        parent_conf = config["ComponentParent"]
        parent_conf["Component_Default_Width_mm"] = width_mm
        parent_conf["Component_Default_Height_mm"] = height_mm
        parent_conf["Component_Default_FrameThickness_mm"] = frame_thickness_mm
        parent_conf["Component_Default_VerticalGlazeBars"] = vertical_bars
        parent_conf["Component_Default_HorizontalGlazeBars"] = horizontal_bars
        parent_conf["Component_Default_FrameColor"] = frame_color
        
        update_frame_dimensions_in_config(config, width_mm, height_mm, frame_thickness_mm)
        update_glass_dimensions_in_config(config, width_mm, height_mm, frame_thickness_mm)
        
        return config
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create Initial Window Geometry from Configuration
    # ------------------------------------------------------------
    def self.create_window_geometry(config)
        return nil unless validate_window_creation_preconditions             # Validate preconditions for creation
        
        model = Sketchup.active_model                                        # Get active SketchUp model
        model.start_operation("Create Window", true)                        # Start operation for undo support
        
        window_instance = create_main_window_component(config)               # Create main component structure
        create_all_window_subcomponents(window_instance.definition, config) # Create all sub-components
        finalize_window_creation(window_instance, config)                   # Finalize and save window
        
        model.commit_operation                                               # Commit the operation
        
        @window_component = window_instance                                  # Store window component instance
        return window_instance                                               # Return created window instance
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Validate Preconditions for Window Creation
    # ---------------------------------------------------------------
    def self.validate_window_creation_preconditions
        return false unless Sketchup.active_model                           # Check active model exists
        return true                                                          # All preconditions met
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create Main Window Component Structure
    # ---------------------------------------------------------------
    def self.create_main_window_component(config)
        model = Sketchup.active_model                                        # Get active model reference
        window_def = model.definitions.add("Window_Component")               # Create main component definition
        window_instance = model.active_entities.add_instance(window_def, Geom::Transformation.new)  # Create instance
        window_instance.name = config["ComponentParent"]["Component_Name"]   # Set component name
        
        @component_refs = {}                                                 # Initialize component references hash
        @glaze_bar_refs = []                                                 # Initialize glaze bar references
        return window_instance                                               # Return created window instance
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create All Window Sub-Components
    # ---------------------------------------------------------------
    def self.create_all_window_subcomponents(window_definition, config)
        create_frame_components(window_definition, config)                  # Create frame components
        create_glass_component(window_definition, config)                   # Create glass component
        create_glaze_bar_components(window_definition, config)              # Create glaze bar components
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Frame Components
    # ---------------------------------------------------------------
    def self.create_frame_components(window_definition, config)
        create_jamb_components(window_definition, config)                   # Create left and right jambs
        create_rail_components(window_definition, config)                   # Create top and bottom rails
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Jamb Components
    # ---------------------------------------------------------------
    def self.create_jamb_components(window_definition, config)
        create_left_jamb_component(window_definition, config)               # Create left jamb
        create_right_jamb_component(window_definition, config)              # Create right jamb
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Rail Components
    # ---------------------------------------------------------------
    def self.create_rail_components(window_definition, config)
        create_bottom_rail_component(window_definition, config)             # Create bottom rail
        create_top_rail_component(window_definition, config)                # Create top rail
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Left Jamb Component
    # ---------------------------------------------------------------
    def self.create_left_jamb_component(window_definition, config)
        jamb_data = config["SubComponents_Level-01"]["Window_LeftJamb"]      # Get jamb configuration data
        jamb_group = create_frame_group(window_definition, "Window_LeftJamb", jamb_data)  # Create jamb group with geometry
        @component_refs["Window_LeftJamb"] = jamb_group                      # Store component reference
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Right Jamb Component
    # ---------------------------------------------------------------
    def self.create_right_jamb_component(window_definition, config)
        jamb_data = config["SubComponents_Level-01"]["Window_RightJamb"]     # Get jamb configuration data
        jamb_group = create_frame_group(window_definition, "Window_RightJamb", jamb_data)  # Create jamb group with geometry
        @component_refs["Window_RightJamb"] = jamb_group                     # Store component reference
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Bottom Rail Component
    # ---------------------------------------------------------------
    def self.create_bottom_rail_component(window_definition, config)
        rail_data = config["SubComponents_Level-01"]["Window_BottomRail"]    # Get rail configuration data
        rail_group = create_frame_group(window_definition, "Window_BottomRail", rail_data)  # Create rail group with geometry
        @component_refs["Window_BottomRail"] = rail_group                    # Store component reference
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Top Rail Component
    # ---------------------------------------------------------------
    def self.create_top_rail_component(window_definition, config)
        rail_data = config["SubComponents_Level-01"]["Window_TopRail"]       # Get rail configuration data
        rail_group = create_frame_group(window_definition, "Window_TopRail", rail_data)  # Create rail group with geometry
        @component_refs["Window_TopRail"] = rail_group                       # Store component reference
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Glass Component
    # ---------------------------------------------------------------
    def self.create_glass_component(window_definition, config)
        glass_data = config["SubComponents_Level-01"]["Window_Glass"]        # Get glass configuration data
        glass_group = create_glass_group(window_definition, "Window_Glass", glass_data)  # Create glass group with geometry
        @component_refs["Window_Glass"] = glass_group                        # Store component reference
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Glaze Bar Components
    # ---------------------------------------------------------------
    def self.create_glaze_bar_components(window_definition, config)
        vertical_bars = config["ComponentParent"]["Component_Default_VerticalGlazeBars"]    # Get vertical bar count
        horizontal_bars = config["ComponentParent"]["Component_Default_HorizontalGlazeBars"]  # Get horizontal bar count
        
        create_vertical_glaze_bars(window_definition, config, vertical_bars)   # Create vertical glaze bars
        create_horizontal_glaze_bars(window_definition, config, horizontal_bars)  # Create horizontal glaze bars
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Vertical Glaze Bars
    # ---------------------------------------------------------------
    def self.create_vertical_glaze_bars(window_definition, config, bar_count)
        return if bar_count == 0                                            # Skip if no vertical bars
        
        glass_data = config["SubComponents_Level-01"]["Window_Glass"]        # Get glass dimensions for positioning
        glass_width = glass_data["Dimensions"]["LenX_mm"]                    # Get glass width
        glass_height = glass_data["Dimensions"]["LenZ_mm"]                   # Get glass height
        
        bar_spacing = glass_width.to_f / (bar_count + 1)                    # Calculate bar spacing
        
        (1..bar_count).each do |i|                                          # Create each vertical bar
            bar_x = glass_data["Position"]["PosX_mm"] + (bar_spacing * i) - (GLAZE_BAR_WIDTH_MM / 2)  # Calculate bar X position
            
            bar_data = {                                                     # Create bar data structure
                "Position" => {
                    "PosX_mm" => bar_x,
                    "PosY_mm" => glass_data["Position"]["PosY_mm"] - 5,
                    "PosZ_mm" => glass_data["Position"]["PosZ_mm"]
                },
                "Dimensions" => {
                    "LenX_mm" => GLAZE_BAR_WIDTH_MM,
                    "LenY_mm" => GLAZE_BAR_THICKNESS_MM,
                    "LenZ_mm" => glass_height
                }
            }
            
            bar_group = create_frame_group(window_definition, "VerticalGlazeBar_#{i}", bar_data)  # Create bar group
            @glaze_bar_refs << bar_group                                     # Store bar reference
        end
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Horizontal Glaze Bars
    # ---------------------------------------------------------------
    def self.create_horizontal_glaze_bars(window_definition, config, bar_count)
        return if bar_count <= 1                                            # Skip if one or no horizontal bars
        
        glass_data = config["SubComponents_Level-01"]["Window_Glass"]        # Get glass dimensions for positioning
        glass_width = glass_data["Dimensions"]["LenX_mm"]                    # Get glass width
        glass_height = glass_data["Dimensions"]["LenZ_mm"]                   # Get glass height
        
        bar_spacing = glass_height.to_f / bar_count                         # Calculate bar spacing
        
        (1..(bar_count - 1)).each do |i|                                    # Create each horizontal bar (excluding top/bottom)
            bar_z = glass_data["Position"]["PosZ_mm"] + (bar_spacing * i) - (GLAZE_BAR_WIDTH_MM / 2)  # Calculate bar Z position
            
            bar_data = {                                                     # Create bar data structure
                "Position" => {
                    "PosX_mm" => glass_data["Position"]["PosX_mm"],
                    "PosY_mm" => glass_data["Position"]["PosY_mm"] - 5,
                    "PosZ_mm" => bar_z
                },
                "Dimensions" => {
                    "LenX_mm" => glass_width,
                    "LenY_mm" => GLAZE_BAR_THICKNESS_MM,
                    "LenZ_mm" => GLAZE_BAR_WIDTH_MM
                }
            }
            
            bar_group = create_frame_group(window_definition, "HorizontalGlazeBar_#{i}", bar_data)  # Create bar group
            @glaze_bar_refs << bar_group                                     # Store bar reference
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Create Frame Group with Geometry
    # ---------------------------------------------------------------
    def self.create_frame_group(window_definition, frame_name, frame_data)
        frame_group = window_definition.entities.add_group                  # Create group for frame component
        frame_group.name = frame_name                                       # Set group name
        
        create_box(                                                         # Create box geometry
            frame_group.entities,
            mm_to_inch(frame_data["Position"]["PosX_mm"]),                  # Convert position to inches
            mm_to_inch(frame_data["Position"]["PosY_mm"]),
            mm_to_inch(frame_data["Position"]["PosZ_mm"]),
            mm_to_inch(frame_data["Dimensions"]["LenX_mm"]),                # Convert dimensions to inches
            mm_to_inch(frame_data["Dimensions"]["LenY_mm"]),
            mm_to_inch(frame_data["Dimensions"]["LenZ_mm"])
        )
        
        return frame_group                                                  # Return created frame group
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Create Glass Group with Geometry
    # ---------------------------------------------------------------
    def self.create_glass_group(window_definition, glass_name, glass_data)
        glass_group = window_definition.entities.add_group                  # Create group for glass
        glass_group.name = glass_name                                       # Set group name
        
        create_box(                                                         # Create box geometry
            glass_group.entities,
            mm_to_inch(glass_data["Position"]["PosX_mm"]),                  # Convert position to inches
            mm_to_inch(glass_data["Position"]["PosY_mm"]),
            mm_to_inch(glass_data["Position"]["PosZ_mm"]),
            mm_to_inch(glass_data["Dimensions"]["LenX_mm"]),                # Convert dimensions to inches
            mm_to_inch(glass_data["Dimensions"]["LenY_mm"]),
            mm_to_inch(glass_data["Dimensions"]["LenZ_mm"])
        )
        
        return glass_group                                                  # Return created glass group
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Finalize Window Creation Process
    # ---------------------------------------------------------------
    def self.finalize_window_creation(window_instance, config)
        save_config_to_component(window_instance, config)                   # Save config to component dictionary
        frame_color = config["ComponentParent"]["Component_Default_FrameColor"] || "natural-wood"  # Get frame color
        add_materials(window_instance.definition.entities, frame_color)     # Apply materials to components with color
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Window Geometry Manipulation - Post Creation Updates
# -----------------------------------------------------------------------------

    # FUNCTION | Update Window Geometry Based on New Configuration
    # ------------------------------------------------------------
    def self.update_window_geometry(width_mm, height_mm, frame_thickness_mm, vertical_bars, horizontal_bars, frame_color)
        return unless validate_window_update_preconditions                   # <-- Validate preconditions for update
        
        model = Sketchup.active_model                                        # <-- Get active model
        model.start_operation("Update Window", true)                        # <-- Start operation for undo support
        
        update_configuration_values(width_mm, height_mm, frame_thickness_mm, vertical_bars, horizontal_bars, frame_color)  # <-- Update internal configuration
        rebuild_window_geometry                                              # <-- Rebuild window with new parameters
        
        save_config_to_component(@window_component, @config)                # <-- Save updated config to dictionary
        model.commit_operation                                               # <-- Commit the operation
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Validate Preconditions for Window Update
    # ---------------------------------------------------------------
    def self.validate_window_update_preconditions
        return false unless @window_component && @window_component.valid?    # <-- Check window component exists and valid
        return false unless Sketchup.active_model                           # <-- Check active model exists
        return true                                                          # <-- All preconditions met
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Update Internal Configuration Values
    # ---------------------------------------------------------------
    def self.update_configuration_values(width_mm, height_mm, frame_thickness_mm, vertical_bars, horizontal_bars, frame_color)
        update_parent_configuration(width_mm, height_mm, frame_thickness_mm, vertical_bars, horizontal_bars, frame_color)  # <-- Update parent config
        update_frame_configuration(width_mm, height_mm, frame_thickness_mm)  # <-- Update frame components config
        update_glass_configuration(width_mm, height_mm, frame_thickness_mm)  # <-- Update glass component config
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Update Parent Component Configuration
    # ---------------------------------------------------------------
    def self.update_parent_configuration(width_mm, height_mm, frame_thickness_mm, vertical_bars, horizontal_bars, frame_color)
        @config["ComponentParent"]["Component_Default_Width_mm"] = width_mm           # <-- Set new width
        @config["ComponentParent"]["Component_Default_Height_mm"] = height_mm         # <-- Set new height
        @config["ComponentParent"]["Component_Default_FrameThickness_mm"] = frame_thickness_mm  # <-- Set new frame thickness
        @config["ComponentParent"]["Component_Default_VerticalGlazeBars"] = vertical_bars      # <-- Set vertical bars count
        @config["ComponentParent"]["Component_Default_HorizontalGlazeBars"] = horizontal_bars  # <-- Set horizontal bars count
        @config["ComponentParent"]["Component_Default_FrameColor"] = frame_color               # <-- Set new frame color
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Update Frame Configuration
    # ---------------------------------------------------------------
    def self.update_frame_configuration(width_mm, height_mm, frame_thickness_mm)
        stile_width = frame_thickness_mm
        rail_thickness = frame_thickness_mm

        # Stiles (left/right) run full height
        @config["SubComponents_Level-01"]["Window_LeftJamb"]["Position"]["PosX_mm"] = 0
        @config["SubComponents_Level-01"]["Window_LeftJamb"]["Position"]["PosZ_mm"] = 0
        @config["SubComponents_Level-01"]["Window_LeftJamb"]["Dimensions"]["LenX_mm"] = stile_width
        @config["SubComponents_Level-01"]["Window_LeftJamb"]["Dimensions"]["LenZ_mm"] = height_mm

        @config["SubComponents_Level-01"]["Window_RightJamb"]["Position"]["PosX_mm"] = width_mm - stile_width
        @config["SubComponents_Level-01"]["Window_RightJamb"]["Position"]["PosZ_mm"] = 0
        @config["SubComponents_Level-01"]["Window_RightJamb"]["Dimensions"]["LenX_mm"] = stile_width
        @config["SubComponents_Level-01"]["Window_RightJamb"]["Dimensions"]["LenZ_mm"] = height_mm

        # Rails (top/bottom) fit between stiles
        rail_length = width_mm - (2 * stile_width)

        @config["SubComponents_Level-01"]["Window_BottomRail"]["Position"]["PosX_mm"] = stile_width
        @config["SubComponents_Level-01"]["Window_BottomRail"]["Position"]["PosZ_mm"] = 0
        @config["SubComponents_Level-01"]["Window_BottomRail"]["Dimensions"]["LenX_mm"] = rail_length
        @config["SubComponents_Level-01"]["Window_BottomRail"]["Dimensions"]["LenZ_mm"] = rail_thickness

        @config["SubComponents_Level-01"]["Window_TopRail"]["Position"]["PosX_mm"] = stile_width
        @config["SubComponents_Level-01"]["Window_TopRail"]["Position"]["PosZ_mm"] = height_mm - rail_thickness
        @config["SubComponents_Level-01"]["Window_TopRail"]["Dimensions"]["LenX_mm"] = rail_length
        @config["SubComponents_Level-01"]["Window_TopRail"]["Dimensions"]["LenZ_mm"] = rail_thickness
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Update Glass Configuration
    # ---------------------------------------------------------------
    def self.update_glass_configuration(width_mm, height_mm, frame_thickness_mm)
        # Calculate glass dimensions (fits within frame opening)
        glass_width = width_mm - (2 * frame_thickness_mm)
        glass_height = height_mm - (2 * frame_thickness_mm)
        
        # Position glass within frame opening
        @config["SubComponents_Level-01"]["Window_Glass"]["Position"]["PosX_mm"] = frame_thickness_mm
        @config["SubComponents_Level-01"]["Window_Glass"]["Position"]["PosZ_mm"] = frame_thickness_mm
        @config["SubComponents_Level-01"]["Window_Glass"]["Dimensions"]["LenX_mm"] = glass_width
        @config["SubComponents_Level-01"]["Window_Glass"]["Dimensions"]["LenZ_mm"] = glass_height
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Rebuild Window Geometry
    # ---------------------------------------------------------------
    def self.rebuild_window_geometry
        clear_existing_geometry                                                 # <-- Clear existing geometry
        create_all_window_subcomponents(@window_component.definition, @config)  # <-- Recreate all components
        add_materials(@window_component.definition.entities, @config["ComponentParent"]["Component_Default_FrameColor"])  # <-- Reapply materials with color
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Clear Existing Geometry
    # ---------------------------------------------------------------
    def self.clear_existing_geometry
        @window_component.definition.entities.clear!                        # <-- Clear all entities
        @component_refs.clear                                               # <-- Clear component references
        @glaze_bar_refs.clear                                               # <-- Clear glaze bar references
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Material Functions - Apply Textures and Materials
# -----------------------------------------------------------------------------

    # FUNCTION | Add Materials to Window Components
    # ------------------------------------------------------------
    # RATIONALE: Container-level material application is preferred over face-level
    # application as it ensures SketchUp handles transparency correctly (especially
    # for glass components), improves solid tool compatibility, and aligns with
    # the modular sub-componentized architecture where each part receives appropriate
    # materials (wood/paint for frames, glass for glass components).
    
    def self.add_materials(entities, frame_color = "natural-wood")
        model = Sketchup.active_model                                          # <-- Get active model
        materials = model.materials                                            # <-- Get materials collection
        
        wood_material = create_wood_material(materials, frame_color)           # <-- Create wood material for frame with color
        glass_material = create_glass_material(materials)                      # <-- Create glass material
        
        apply_materials_to_containers(entities, wood_material, glass_material) # <-- Apply materials to containers
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Create Wood Material with Color Support
    # ---------------------------------------------------------------
    def self.create_wood_material(materials, frame_color)
        material_name = "WindowWood_#{frame_color}"                          # <-- Create unique material name
        wood_material = materials[material_name]                             # <-- Check if material exists
        
        unless wood_material
            wood_material = materials.add(material_name)                     # <-- Create new wood material
            wood_material.color = get_frame_color_rgb(frame_color)           # <-- Set color based on selection
        end
        
        return wood_material                                                 # <-- Return wood material
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Get RGB Values for Frame Colors
    # ---------------------------------------------------------------
    def self.get_frame_color_rgb(frame_color)
        case frame_color
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

    # SUB HELPER FUNCTION | Create Glass Material
    # ---------------------------------------------------------------
    def self.create_glass_material(materials)
        glass_material = materials["WindowGlass"]                            # <-- Check if material exists
        unless glass_material
            glass_material = materials.add("WindowGlass")                    # <-- Create new glass material
        end
        
        # Always set properties to ensure correct values
        glass_material.color = [190, 225, 235]                              # <-- Set light blue glass color
        glass_material.alpha = 0.25                                         # <-- Set 25% opacity (75% transparency)
        
        return glass_material                                               # <-- Return glass material
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Apply Materials to Containers
    # ---------------------------------------------------------------
    def self.apply_materials_to_containers(entities, wood_material, glass_material)
        entities.grep(Sketchup::Group).each do |group|                      # <-- Iterate through all groups
            if group.name == "Window_Glass"
                group.material = glass_material                             # <-- Apply glass material directly to container
            else
                group.material = wood_material                              # <-- Apply wood material directly to container
            end
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Selection Observer - Monitor Selection Changes
# -----------------------------------------------------------------------------

    # CLASS | Window Selection Observer for Multi-Window Support
    # ------------------------------------------------------------
    class WindowSelectionObserver < Sketchup::SelectionObserver
        def onSelectionBulkChange(selection)
            return unless WindowConfigurator.dialog_visible?                 # <-- Skip if dialog not open
            
            if selection.size == 1 && selection[0].is_a?(Sketchup::ComponentInstance)  # <-- Check single component selected
                component = selection[0]
                
                dict = component.definition.attribute_dictionary(WINDOW_DICT_NAME)  # <-- Check for window config dictionary
                if dict && dict["window_config"]
                    config = WindowConfigurator.load_config_from_component(component)  # <-- Load config and update dialog
                    WindowConfigurator.set_window_component(component, config)
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


    # FUNCTION | Set Window Component and Update Dialog
    # ---------------------------------------------------------------
    def self.set_window_component(component, config)
        @window_component = component                                        # <-- Set current window component
        @config = config                                                     # <-- Set current config
        
        @component_refs = {}                                                 # <-- Get references to sub-components
        component.definition.entities.grep(Sketchup::Group).each do |group|
            window_group_names = ["Window_LeftJamb", "Window_RightJamb", "Window_BottomRail", "Window_TopRail", "Window_Glass"]
            @component_refs[group.name] = group if window_group_names.include?(group.name)
        end
        
        @dialog.execute_script("window.setInitialConfig('#{JSON.generate(@config).gsub("'", "\\\\'")}');") if @dialog && @dialog.visible?  # <-- Update dialog with loaded config
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Main Initialization - Set Up Tool and Show Dialog
# -----------------------------------------------------------------------------

    # FUNCTION | Initialize the Window Configurator Tool
    # ------------------------------------------------------------
    def self.init
        @window_component = nil                                               # <-- Initialize window component reference
        @config = nil                                                         # <-- Initialize configuration data
        @component_refs = {}                                                 # <-- Initialize component references
        
        @selection_observer = WindowSelectionObserver.new                   # <-- Create selection observer instance
        Sketchup.active_model.selection.add_observer(@selection_observer)
        
        show_dialog                                                          # <-- Show the dialog
    end
    # ---------------------------------------------------------------

    # FUNCTION | Show Window Configurator Dialog
    # ------------------------------------------------------------
    def self.show_dialog
        if @dialog && @dialog.visible?                                       # <-- Return if dialog already showing
            @dialog.bring_to_front
            return
        end
        
        @dialog = UI::HtmlDialog.new(                                        # <-- Create the dialog
            dialog_title: "Window Configurator",
            preferences_key: "WindowConfigurator",
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
        
        check_for_existing_window_selection                                  # <-- Check for existing window selection
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
          <title>Window Configurator</title>
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
                --ValeWindowFrameColor             : #8B4513;
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

            h2 {
                font-family                        : var(--FontType_ValeTitleHeading01);
                font-size                          : var(--FontSize_ValeTitleHeading01);
                color                              : var(--FontCol_ValeTitleHeadingColour);
                margin-bottom                      : 15px;
            }

            h3 {
                font-family                        : var(--FontType_ValeTitleHeading02);
                font-size                          : var(--FontSize_ValeTitleHeading02);
                color                              : var(--FontCol_ValeTitleHeadingColour);
                margin-bottom                      : 12px;
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
                width                              : 70px; /* Adjusted width */
                -moz-appearance                    : textfield; /* Firefox - remove spinners */
            }

            .value-input::-webkit-outer-spin-button,
            .value-input::-webkit-inner-spin-button {
                -webkit-appearance                 : none; /* Chrome, Safari, Edge, Opera - remove spinners */
                margin                             : 0;
            }

            .unit-label {
                font-size                          : 0.8rem;
                font-weight                        : bold;
                color                              : var(--ValeSliderActiveColor);
                margin-left                        : 5px;
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

            /* Separator Styles */
            hr {
                margin                             : 30px 0;
                border                             : 0;
                border-top                         : 2px solid var(--ValeHighlightColor);
                background                         : linear-gradient(to right, transparent, var(--ValeHighlightColor), transparent);
                height                             : 2px;
            }

            /* Color Palette Styles */
            .color-palette-container {
                background-color                   : var(--ValeContentBackground);
                border                             : 1px solid var(--ValeBorderColor);
                border-radius                      : 8px;
                margin-bottom                      : 20px;
                box-shadow                         : 0 2px 6px rgba(0, 0, 0, 0.08);
                overflow                           : hidden;
            }

            .color-palette-header {
                background-color                   : rgba(0, 102, 0, 0.05);
                border-bottom                      : 1px solid var(--ValeBorderColor);
                padding                            : 15px 20px;
                cursor                             : pointer;
                user-select                        : none;
                display                            : flex;
                justify-content                    : space-between;
                align-items                        : center;
                transition                         : all 0.2s ease;
                position                           : relative;
            }

            .color-palette-header:hover {
                background-color                   : rgba(0, 102, 0, 0.1);
            }

            .color-palette-header .title {
                font-family                        : var(--FontType_ValeTitleHeading03);
                font-size                          : var(--FontSize_ValeTitleHeading03);
                font-weight                        : bold;
                color                              : var(--FontCol_ValeTitleHeadingColour);
                text-transform                     : uppercase;
                letter-spacing                     : 0.5px;
            }

            .color-palette-header .arrow {
                font-size                          : 14px;
                color                              : var(--ValeHighlightColor);
                transition                         : transform 0.3s ease;
                font-weight                        : bold;
            }

            .color-palette-header.expanded .arrow {
                transform                          : rotate(180deg);
            }

            .color-palette-content {
                display                            : none;
                padding                            : 20px;
                background-color                   : var(--ValeContentBackground);
            }

            .color-palette-content.visible {
                display                            : block;
                animation                          : slideDown 0.3s ease;
            }

            @keyframes slideDown {
                from {
                    opacity                        : 0;
                    transform                      : translateY(-10px);
                }
                to {
                    opacity                        : 1;
                    transform                      : translateY(0);
                }
            }

            .color-swatches {
                display                            : grid;
                grid-template-columns              : repeat(2, 1fr);
                gap                                : 15px;
            }

            .color-swatch {
                border                             : 2px solid var(--ValeBorderColor);
                border-radius                      : 8px;
                padding                            : 12px;
                text-align                         : center;
                cursor                             : pointer;
                transition                         : all 0.3s ease;
                background-color                   : var(--ValeContentBackground);
                position                           : relative;
                overflow                           : hidden;
            }

            .color-swatch:hover {
                border-color                       : var(--ValeHighlightColor);
                transform                          : translateY(-3px);
                box-shadow                         : 0 6px 12px rgba(0, 0, 0, 0.15);
            }

            .color-swatch.selected {
                border-color                       : var(--ValeHighlightColor);
                border-width                       : 3px;
                background-color                   : rgba(0, 102, 0, 0.05);
                transform                          : translateY(-2px);
                box-shadow                         : 0 4px 8px rgba(0, 0, 0, 0.1);
            }

            .color-swatch .color-sample {
                width                              : 100%;
                height                             : 40px;
                border-radius                      : 4px;
                margin-bottom                      : 8px;
                border                             : 1px solid rgba(0, 0, 0, 0.1);
                box-shadow                         : inset 0 1px 3px rgba(0, 0, 0, 0.1);
            }

            .color-swatch .color-name {
                font-size                          : 12px;
                font-weight                        : bold;
                color                              : var(--FontCol_ValeTitleHeadingColour);
                margin-bottom                      : 2px;
                text-transform                     : uppercase;
                letter-spacing                     : 0.3px;
            }

            .color-swatch .color-description {
                font-size                          : 10px;
                color                              : var(--FontCol_ValeStandardTextColour);
                font-style                         : italic;
                opacity                            : 0.8;
            }

            .selected-color-indicator {
                margin-top                         : 15px;
                padding                            : 12px 15px;
                background-color                   : rgba(0, 102, 0, 0.1);
                border                             : 1px solid var(--ValeHighlightColor);
                border-radius                      : 6px;
                font-size                          : 13px;
                font-weight                        : bold;
                text-align                         : center;
                color                              : var(--ValeHighlightColor);
                text-transform                     : uppercase;
                letter-spacing                     : 0.3px;
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
                
                .color-swatches {
                    grid-template-columns          : 1fr;
                }
            }
          </style>
        </head>


    <!-- ----------------------------------------------------------------- -->
    <!-- REGION  |  User Interface HTML Layout & Elements                  -->
    <!-- ----------------------------------------------------------------- -->
        <body>
        <h1>Window Configurator</h1>
    
        <div class="section-title">Window Dimensions</div>
        
        <div class="slider-container">
        <div class="slider-group">
            <label for="width-slider">Window Width (mm):</label>
            <input type="range" id="width-slider" min="600" max="2400" value="1200" oninput="updateWidth(this.value)">
            <div class="value-input-wrapper">
                <input type="number" id="width-value-input" class="value-input" step="1" value="1200" onchange="handleTextInputChange('width', event)" onkeydown="handleTextInputChange('width', event)">
                <span class="unit-label">mm</span>
            </div>
        </div>
        
        <div class="slider-group">
            <label for="height-slider">Window Height (mm):</label>
            <input type="range" id="height-slider" min="800" max="2400" value="1500" oninput="updateHeight(this.value)">
            <div class="value-input-wrapper">
                <input type="number" id="height-value-input" class="value-input" step="1" value="1500" onchange="handleTextInputChange('height', event)" onkeydown="handleTextInputChange('height', event)">
                <span class="unit-label">mm</span>
            </div>
        </div>
        
        <div class="slider-group">
            <label for="thickness-slider">Frame Thickness (mm):</label>
            <input type="range" id="thickness-slider" min="40" max="120" value="90" oninput="updateThickness(this.value)">
            <div class="value-input-wrapper">
                <input type="number" id="thickness-value-input" class="value-input" step="1" value="90" onchange="handleTextInputChange('thickness', event)" onkeydown="handleTextInputChange('thickness', event)">
                <span class="unit-label">mm</span>
            </div>
        </div>
        </div>
        
        <!-- ---------------------------------------------------------------- -->
        
        
        <!-- ----------------------------------------------------------------- -->
        <!-- UI MENU | Georgian Glaze Bar Configuration Controls               -->
        <!-- ----------------------------------------------------------------- -->
        
        <div class="section-title">Georgian Glaze Bars</div>
        
        <div class="slider-container">
        <div class="slider-group">
            <label for="vertical-bars-slider">Vertical Glaze Bars:</label>
            <input type="range" id="vertical-bars-slider" min="0" max="8" value="2" oninput="updateVerticalBars(this.value)">
            <div class="value-input-wrapper">
                <input type="number" id="vertical-bars-value-input" class="value-input" step="1" value="2" onchange="handleTextInputChange('vertical-bars', event)" onkeydown="handleTextInputChange('vertical-bars', event)">
                <span class="unit-label">bars</span>
            </div>
        </div>
        
        <div class="slider-group">
            <label for="horizontal-bars-slider">Horizontal Glaze Bars:</label>
            <input type="range" id="horizontal-bars-slider" min="1" max="8" value="3" oninput="updateHorizontalBars(this.value)">
            <div class="value-input-wrapper">
                <input type="number" id="horizontal-bars-value-input" class="value-input" step="1" value="3" onchange="handleTextInputChange('horizontal-bars', event)" onkeydown="handleTextInputChange('horizontal-bars', event)">
                <span class="unit-label">bars</span>
            </div>
        </div>
        </div>
        
        <!-- ---------------------------------------------------------------- -->
        
        <hr>
        
        <!-- UI MENU | Frame Color Swatches Selection Interface                -->
        <!-- ----------------------------------------------------------------- -->
        
        <div class="color-palette-container">
        <div class="color-palette-header" onclick="toggleColorPalette()">
            <span class="title">Frame Colors</span>
            <span class="arrow">▼</span>
        </div>
        <div class="color-palette-content" id="color-palette-content">
            <div class="color-swatches">
            <div class="color-swatch selected" data-color="natural-wood" onclick="selectColor('natural-wood')">
                <div class="color-sample" style="background: linear-gradient(45deg, #8B4513, #A0522D);"></div>
                <div class="color-name">Natural Wood</div>
                <div class="color-description">Traditional Oak</div>
            </div>
            <div class="color-swatch" data-color="pointing" onclick="selectColor('pointing')">
                <div class="color-sample" style="background-color: #E8E2D0;"></div>
                <div class="color-name">Pointing</div>
                <div class="color-description">F&B No.26</div>
            </div>
            <div class="color-swatch" data-color="card-room-green" onclick="selectColor('card-room-green')">
                <div class="color-sample" style="background-color: #7F8471;"></div>
                <div class="color-name">Card Room Green</div>
                <div class="color-description">F&B No.79</div>
            </div>
            <div class="color-swatch" data-color="borrowed-light" onclick="selectColor('borrowed-light')">
                <div class="color-sample" style="background-color: #DDE6E8;"></div>
                <div class="color-name">Borrowed Light</div>
                <div class="color-description">F&B No.235</div>
            </div>
            </div>
            <div class="selected-color-indicator" id="selected-color-indicator">
            Selected: Natural Wood (Traditional Oak)
            </div>
        </div>
        </div>
        
        <!-- ---------------------------------------------------------------- -->
          
          <button id="create-window-btn" onclick="createWindow()">Create Window</button>
          
          <div class="footer">
            Vale Design Suite - Window Configurator Tool v1.0.0
          </div>
        <!-- endregion ----------------------------------------------------------------- -->
          
          <script>

            // -----------------------------------------------------------------------------
            // REGION | Front End Javascript Section
            // -----------------------------------------------------------------------------

            // MODULE VARIABLES | Window Configuration State Variables
            // ------------------------------------------------------------
            let widthValue          = 1200;                                  // <-- Window width in millimeters
            let heightValue         = 1500;                                  // <-- Window height in millimeters  
            let thicknessValue      = 90;                                    // <-- Frame thickness in millimeters
            let verticalBarsValue   = 2;                                     // <-- Number of vertical glaze bars
            let horizontalBarsValue = 3;                                     // <-- Number of horizontal glaze bars
            let windowCreated       = false;                                 // <-- Flag to track if window exists
            let selectedColorValue  = 'natural-wood';                       // <-- Currently selected frame color
            //  -----------------------------------------------------------


            // FUNCTION | Initialize Dialog from Configuration Data
            // ------------------------------------------------------------
            function initFromConfig(config) {
                if (!config) return;                                         // <-- Exit if no config provided
                
                try {
                    const parentConfig = config.ComponentParent;             // <-- Get parent configuration object
                    
                    // UPDATE INTERNAL STATE VARIABLES
                    widthValue = parentConfig.Component_Default_Width_mm;                     // <-- Set width from config
                    heightValue = parentConfig.Component_Default_Height_mm;                   // <-- Set height from config
                    thicknessValue = parentConfig.Component_Default_FrameThickness_mm;        // <-- Set frame thickness from config
                    verticalBarsValue = parentConfig.Component_Default_VerticalGlazeBars;     // <-- Set vertical bars from config
                    horizontalBarsValue = parentConfig.Component_Default_HorizontalGlazeBars; // <-- Set horizontal bars from config
                    selectedColorValue = parentConfig.Component_Default_FrameColor || 'natural-wood'; // <-- Set frame color
                    
                    // UPDATE SLIDER VALUES AND INPUT FIELDS
                    document.getElementById('width-slider').value = widthValue;
                    document.getElementById('width-value-input').value = widthValue;
                    
                    document.getElementById('height-slider').value = heightValue;
                    document.getElementById('height-value-input').value = heightValue;
                    
                    document.getElementById('thickness-slider').value = thicknessValue;
                    document.getElementById('thickness-value-input').value = thicknessValue;
                    
                    document.getElementById('vertical-bars-slider').value = verticalBarsValue;
                    document.getElementById('vertical-bars-value-input').value = verticalBarsValue;
                    
                    document.getElementById('horizontal-bars-slider').value = horizontalBarsValue;
                    document.getElementById('horizontal-bars-value-input').value = horizontalBarsValue;

                    // UPDATE COLOR SELECTION
                    selectColor(selectedColorValue, false); // false to prevent immediate updateWindow call during init
                    
                    // UPDATE SLIDER CONSTRAINTS FROM CONFIGURATION
                    document.getElementById('width-slider').min = parentConfig.Component_UI_MinWidth_mm;         // <-- Set minimum width constraint
                    document.getElementById('width-slider').max = parentConfig.Component_UI_MaxWidth_mm;         // <-- Set maximum width constraint
                    
                    document.getElementById('height-slider').min = parentConfig.Component_UI_MinHeight_mm;       // <-- Set minimum height constraint
                    document.getElementById('height-slider').max = parentConfig.Component_UI_MaxHeight_mm;       // <-- Set maximum height constraint
                    
                    document.getElementById('thickness-slider').min = parentConfig.Component_UI_MinFrameThickness_mm; // <-- Set minimum thickness constraint
                    document.getElementById('thickness-slider').max = parentConfig.Component_UI_MaxFrameThickness_mm; // <-- Set maximum thickness constraint

                    document.getElementById('vertical-bars-slider').min = parentConfig.Component_UI_MinVerticalGlazeBars;
                    document.getElementById('vertical-bars-slider').max = parentConfig.Component_UI_MaxVerticalGlazeBars;

                    document.getElementById('horizontal-bars-slider').min = parentConfig.Component_UI_MinHorizontalGlazeBars;
                    document.getElementById('horizontal-bars-slider').max = parentConfig.Component_UI_MaxHorizontalGlazeBars;
                    
                    // UPDATE BUTTON TEXT BASED ON WINDOW STATE
                    document.getElementById('create-window-btn').textContent = windowCreated ? 'Update Window' : 'Create Window'; // <-- Set appropriate button text
                    
                } catch (e) {
                    console.error('Error initializing from config:', e);     // <-- Log initialization errors
                }
            }
            // ---------------------------------------------------------------

            // FUNCTION | Toggle Color Palette Visibility
            // ---------------------------------------------------------------
            function toggleColorPalette() {
                const content = document.getElementById('color-palette-content'); // <-- Get palette content element
                const header = document.querySelector('.color-palette-header');   // <-- Get palette header element
                
                if (content.classList.contains('visible')) {                 // <-- Check if palette is currently visible
                    content.classList.remove('visible');                     // <-- Hide palette content
                    header.classList.remove('expanded');                     // <-- Remove expanded state from header
                } else {
                    content.classList.add('visible');                        // <-- Show palette content
                    header.classList.add('expanded');                        // <-- Add expanded state to header
                }
            }
            // ---------------------------------------------------------------

            // FUNCTION | Select Frame Color and Update State
            // ---------------------------------------------------------------
            function selectColor(colorId, triggerUpdate = true) {
                // REMOVE SELECTED STATE FROM ALL COLOR SWATCHES
                document.querySelectorAll('.color-swatch').forEach(swatch => {   // <-- Iterate through all color swatches
                    swatch.classList.remove('selected');                     // <-- Remove selected class
                });
                
                // ADD SELECTED STATE TO CLICKED SWATCH
                const currentSwatch = document.querySelector(`[data-color="${colorId}"]`);
                if (currentSwatch) {
                    currentSwatch.classList.add('selected'); // <-- Add selected class to clicked swatch
                }
                
                // UPDATE INTERNAL COLOR STATE
                selectedColorValue = colorId;                                 // <-- Store selected color ID
                
                // UPDATE COLOR INDICATOR TEXT
                const colorNames = {                                          // <-- Define color name mappings
                    'natural-wood': 'Natural Wood (Traditional Oak)',
                    'pointing': 'Pointing (F&B No.26)',
                    'card-room-green': 'Card Room Green (F&B No.79)',
                    'borrowed-light': 'Borrowed Light (F&B No.235)'
                };
                
                document.getElementById('selected-color-indicator').textContent = 
                    'Selected: ' + (colorNames[colorId] || colorId);                      // <-- Update indicator text with selected color name
                
                // UPDATE WINDOW IF ALREADY CREATED AND triggerUpdate is true
                if (windowCreated && triggerUpdate) {                                          // <-- Check if window already exists
                    updateWindow();                                           // <-- Apply color change to existing window
                }
            }
            // ---------------------------------------------------------------

            // HELPER FUNCTION | Handle Text Input Change for Dimensions/Bars
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
                    case 'thickness':
                        inputElementId = 'thickness-value-input'; sliderElementId = 'thickness-slider'; 
                        valueToUpdateFunc = (v) => { thicknessValue = v; }; currentValue = thicknessValue;
                        break;
                    case 'vertical-bars':
                        inputElementId = 'vertical-bars-value-input'; sliderElementId = 'vertical-bars-slider'; 
                        valueToUpdateFunc = (v) => { verticalBarsValue = v; }; currentValue = verticalBarsValue;
                        break;
                    case 'horizontal-bars':
                        inputElementId = 'horizontal-bars-value-input'; sliderElementId = 'horizontal-bars-slider'; 
                        valueToUpdateFunc = (v) => { horizontalBarsValue = v; }; currentValue = horizontalBarsValue;
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

                if (windowCreated) {
                    updateWindow();
                }
            }
            // ---------------------------------------------------------------


            // FUNCTION | Update Window Width Value and Display
            // ---------------------------------------------------------------
            function updateWidth(value) {
                const newValue = parseInt(value)
                widthValue = newValue;                                 // <-- Parse and store new width value
                document.getElementById('width-value-input').value = newValue; // <-- Update width input field
                if (windowCreated) {                                          // <-- Check if window exists
                    updateWindow();                                           // <-- Apply width change to window
                }
            }
            // ---------------------------------------------------------------

            // FUNCTION | Update Window Height Value and Display
            // ---------------------------------------------------------------
            function updateHeight(value) {
                const newValue = parseInt(value)
                heightValue = newValue;                                // <-- Parse and store new height value
                document.getElementById('height-value-input').value = newValue; // <-- Update height input field
                if (windowCreated) {                                          // <-- Check if window exists
                    updateWindow();                                           // <-- Apply height change to window
                }
            }
            // ---------------------------------------------------------------

            // FUNCTION | Update Frame Thickness Value and Display
            // ---------------------------------------------------------------
            function updateThickness(value) {
                const newValue = parseInt(value)
                thicknessValue = newValue;                             // <-- Parse and store new thickness value
                document.getElementById('thickness-value-input').value = newValue; // <-- Update thickness input field
                if (windowCreated) {                                          // <-- Check if window exists
                    updateWindow();                                           // <-- Apply thickness change to window
                }
            }
            // ---------------------------------------------------------------

            // FUNCTION | Update Vertical Glaze Bars Count and Display
            // ---------------------------------------------------------------
            function updateVerticalBars(value) {
                const newValue = parseInt(value)
                verticalBarsValue = newValue;                          // <-- Parse and store new vertical bars count
                document.getElementById('vertical-bars-value-input').value = newValue; // <-- Update vertical bars input field
                if (windowCreated) {                                          // <-- Check if window exists
                    updateWindow();                                           // <-- Apply vertical bars change to window
                }
            }
            // ---------------------------------------------------------------

            // FUNCTION | Update Horizontal Glaze Bars Count and Display
            // ---------------------------------------------------------------
            function updateHorizontalBars(value) {
                const newValue = parseInt(value)
                horizontalBarsValue = newValue;                        // <-- Parse and store new horizontal bars count
                document.getElementById('horizontal-bars-value-input').value = newValue; // <-- Update horizontal bars input field
                if (windowCreated) {                                          // <-- Check if window exists
                    updateWindow();                                           // <-- Apply horizontal bars change to window
                }
            }
            // ---------------------------------------------------------------

            // FUNCTION | Create New Window or Update Existing Window
            // ---------------------------------------------------------------
            function createWindow() {
                if (windowCreated) {                                          // <-- Check if window already exists
                    updateWindow();                                           // <-- Update existing window with current values
                } else {
                    sketchup.createWindow(widthValue, heightValue, thicknessValue, verticalBarsValue, horizontalBarsValue, selectedColorValue); // <-- Create new window with current values
                    windowCreated = true;                                     // <-- Mark window as created
                    document.getElementById('create-window-btn').textContent = 'Update Window'; // <-- Change button text to update mode
                }
            }
            // ---------------------------------------------------------------

            // FUNCTION | Update Existing Window with Current Configuration
            // ---------------------------------------------------------------
            function updateWindow() {
                sketchup.updateWindow(widthValue, heightValue, thicknessValue, verticalBarsValue, horizontalBarsValue, selectedColorValue); // <-- Send update command to SketchUp with all current values
            }
            // ---------------------------------------------------------------

            // GLOBAL FUNCTION | Set Initial Configuration from SketchUp
            // ---------------------------------------------------------------
            window.setInitialConfig = function(configJson) {
                const config = JSON.parse(configJson);                       // <-- Parse JSON configuration from SketchUp
                windowCreated = true;                                         // <-- Mark window as already created
                initFromConfig(config);                                       // <-- Initialize dialog with loaded configuration
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
        @dialog.add_action_callback("createWindow") do |action_context, width, height, thickness, vertical_bars, horizontal_bars, frame_color|
            # This callback is for when the JS calls sketchup.createWindow for a new window.
            
            # Prepare a full, new configuration object based on defaults and current dialog values.
            prepared_config = prepare_config_for_creation(width, height, thickness, vertical_bars, horizontal_bars, frame_color)
            
            # Create the window geometry using this prepared configuration.
            created_instance = create_window_geometry(prepared_config) 
            
            if created_instance && created_instance.valid?
                @window_component = created_instance # Store reference to the new window component
                @config = prepared_config            # Store the configuration used for this new window
                
                # The JS side handles updating its `windowCreated` flag and button text.
                # If needed, we could also explicitly tell JS to re-sync with this new @config:
                # @dialog.execute_script("window.setInitialConfig('#{JSON.generate(@config).gsub("'", "\\\\'")}');")
                # However, the current JS `createWindow` function already sets its state.
            else
                puts "Error: Window creation failed."
                # Optionally, notify the user via the dialog if creation fails.
            end
        end
        
        @dialog.add_action_callback("updateWindow") do |action_context, width, height, thickness, vertical_bars, horizontal_bars, frame_color|
            update_window_geometry(width, height, thickness, vertical_bars, horizontal_bars, frame_color)
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Selection Observer - Monitor Selection Changes
# -----------------------------------------------------------------------------

    # CLASS | Window Selection Observer for Multi-Window Support
    # ------------------------------------------------------------
    class WindowSelectionObserver < Sketchup::SelectionObserver
        def onSelectionBulkChange(selection)
            return unless WindowConfigurator.dialog_visible?                 # <-- Skip if dialog not open
            
            if selection.size == 1 && selection[0].is_a?(Sketchup::ComponentInstance)  # <-- Check single component selected
                component = selection[0]
                
                dict = component.definition.attribute_dictionary(WINDOW_DICT_NAME)  # <-- Check for window config dictionary
                if dict && dict["window_config"]
                    config = WindowConfigurator.load_config_from_component(component)  # <-- Load config and update dialog
                    WindowConfigurator.set_window_component(component, config)
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


    # FUNCTION | Set Window Component and Update Dialog
    # ---------------------------------------------------------------
    def self.set_window_component(component, config)
        @window_component = component                                        # <-- Set current window component
        @config = config                                                     # <-- Set current config
        
        @component_refs = {}                                                 # <-- Get references to sub-components
        component.definition.entities.grep(Sketchup::Group).each do |group|
            window_group_names = ["Window_LeftJamb", "Window_RightJamb", "Window_BottomRail", "Window_TopRail", "Window_Glass"]
            @component_refs[group.name] = group if window_group_names.include?(group.name)
        end
        
        @dialog.execute_script("window.setInitialConfig('#{JSON.generate(@config).gsub("'", "\\\\'")}');") if @dialog && @dialog.visible?  # <-- Update dialog with loaded config
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Main Initialization - Set Up Tool and Show Dialog
# -----------------------------------------------------------------------------

    # FUNCTION | Initialize the Window Configurator Tool
    # ------------------------------------------------------------
    def self.init
        @window_component = nil                                               # <-- Initialize window component reference
        @config = nil                                                         # <-- Initialize configuration data
        @component_refs = {}                                                 # <-- Initialize component references
        
        @selection_observer = WindowSelectionObserver.new                   # <-- Create selection observer instance
        Sketchup.active_model.selection.add_observer(@selection_observer)
        
        show_dialog                                                          # <-- Show the dialog
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end

# Initialize the tool when the script is loaded
WindowConfigurator.init
