# =============================================================================
# VALEDESIGNSUITE - CAMERA VANISHING POINTS DRAWING AID
# =============================================================================
#
# FILE       : ValeSketchTools__DrawingAid__CreateCurrentSceneCameraVanishingPoints.rb
# NAMESPACE  : VanishingPointDrawingAid
# MODULE     : VanishingPointDrawingAid
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Generate vanishing points and horizon line for current camera view
# CREATED    : 2025
#
# DESCRIPTION:
# - This script creates vanishing points and horizon line geometry for perspective drawing.
# - It calculates vanishing points based on the current camera orientation.
# - Geometry is placed on a 2D plane perpendicular to camera, slightly forward.
# - Each scene can have its own vanishing point geometry with unique tags.
# - Supports 1-point, 2-point, and 3-point perspective based on camera angle.
# - Generates crosshair targets at vanishing points for ruler alignment.
# - Compatible with SketchUp 2026 Ruby API standards.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 01-Jan-2025 - Version 1.0.0
# - Initial implementation with basic vanishing point calculation
# - Support for 2-point perspective views
# - Crosshair target generation at vanishing points
# - Horizon line generation
#
# 01-Jan-2025 - Version 1.1.0
# - Integrated into ValeDesignSuite main menu interface
# - Added named materials for better organization
# - Blue Material: "01_VanishingPoints_HorizonLine"
# - Red Material: "01_VanishingPoints_VanishingPointCrosshairs"
# - Material cleanup on removal operations
#
# =============================================================================

require 'sketchup.rb'

module VanishingPointDrawingAid

# -----------------------------------------------------------------------------
# REGION | Module Constants and Configuration
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Drawing Parameters
    # ------------------------------------------------------------
    CROSSHAIR_SIZE          =   2.0                                          # <-- Size of crosshair in inches
    HORIZON_EXTEND_FACTOR   =   2.0                                          # <-- How far to extend horizon beyond viewport
    CAMERA_OFFSET_DISTANCE  =   20.0                                         # <-- Distance in front of camera in inches
    DEFAULT_TAG_NAME        =   "01_VanishingPoints"                         # <-- Default tag for vanishing point geometry
    # ------------------------------------------------------------

    # MODULE CONSTANTS | Color Settings
    # ------------------------------------------------------------
    VANISHING_POINT_COLOR   =   Sketchup::Color.new(255, 0, 0)              # <-- Red color for vanishing points
    HORIZON_LINE_COLOR      =   Sketchup::Color.new(0, 0, 255)              # <-- Blue color for horizon line
    CONSTRUCTION_COLOR      =   Sketchup::Color.new(128, 128, 128)          # <-- Gray for construction lines
    # ------------------------------------------------------------

    # MODULE CONSTANTS | Material Names
    # ------------------------------------------------------------
    HORIZON_LINE_MATERIAL_NAME      =   "01_VanishingPoints_HorizonLine"               # <-- Material name for horizon line
    VANISHING_POINT_MATERIAL_NAME   =   "01_VanishingPoints_VanishingPointCrosshairs"  # <-- Material name for vanishing point crosshairs
    CONSTRUCTION_MATERIAL_NAME      =   "01_VanishingPoints_ConstructionLines"         # <-- Material name for construction lines
    # ------------------------------------------------------------

    # MODULE CONSTANTS | Tag Names
    # ------------------------------------------------------------
    HORIZON_LINE_POINTS_TAG_NAME    =   "01_VanishingPoints_HorizonLine"               # <-- Tag name for horizon line group
    VANISHING_POINTS_TAG_NAME       =   "01_VanishingPoints"                           # <-- Tag name for vanishing point crosshairs groups
    # ------------------------------------------------------------

    # MODULE VARIABLES | State Management
    # ------------------------------------------------------------
    @horizon_line_group     =   nil                                          # <-- Horizon line group
    @vanishing_point_group  =   nil                                          # <-- Vanishing point crosshairs group
    @current_scene_name     =   nil                                          # <-- Track current scene
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Core Calculation Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Calculate Vanishing Points for Current Camera
    # ------------------------------------------------------------
    def self.calculate_vanishing_points
        model = Sketchup.active_model                                        # Get active model
        view = model.active_view                                             # Get active view
        camera = view.camera                                                 # Get camera from view
        
        return nil unless camera.perspective?                                # Only work with perspective cameras
        
        # Get camera properties
        eye = camera.eye                                                     # Camera position
        target = camera.target                                               # Where camera is looking
        up = camera.up                                                       # Camera up vector
        fov = camera.fov                                                     # Field of view in degrees
        
        # Calculate camera coordinate system
        forward = eye.vector_to(target).normalize                           # Forward direction
        right = forward.cross(up).normalize                                 # Right direction
        camera_up = right.cross(forward).normalize                          # Corrected up direction
        
        # Calculate vanishing points based on viewing angle
        vanishing_points = {}
        
        # World coordinate axes
        world_x = Geom::Vector3d.new(1, 0, 0)                              # World X-axis
        world_y = Geom::Vector3d.new(0, 1, 0)                              # World Y-axis
        world_z = Geom::Vector3d.new(0, 0, 1)                              # World Z-axis (up)
        
        # Check which world axes are visible (not parallel to view plane)
        x_visible = world_x.dot(forward).abs > 0.01
        y_visible = world_y.dot(forward).abs > 0.01
        z_visible = world_z.dot(forward).abs > 0.01
        
        # Calculate vanishing points for visible axes
        if x_visible
            vp_x = calculate_axis_vanishing_point(eye, world_x, forward, right, camera_up)
            vanishing_points[:x_axis] = vp_x if vp_x
        end
        
        if y_visible
            vp_y = calculate_axis_vanishing_point(eye, world_y, forward, right, camera_up)
            vanishing_points[:y_axis] = vp_y if vp_y
        end
        
        if z_visible
            vp_z = calculate_axis_vanishing_point(eye, world_z, forward, right, camera_up)
            vanishing_points[:z_axis] = vp_z if vp_z
        end
        
        # Calculate horizon line (where ground plane meets view at infinity)
        horizon_data = calculate_horizon_line(eye, forward, right, camera_up)
        
        return {
            vanishing_points: vanishing_points,
            horizon: horizon_data,
            camera_data: {
                eye: eye,
                target: target,
                forward: forward,
                right: right,
                up: camera_up,
                fov: fov
            }
        }
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Calculate Vanishing Point for World Axis
    # ---------------------------------------------------------------
    def self.calculate_axis_vanishing_point(eye, world_axis, forward, right, up)
        # Project world axis direction onto view plane to find vanishing point
        # This is where parallel lines in that direction appear to converge
        
        # Place vanishing point on a plane in front of camera
        plane_distance = CAMERA_OFFSET_DISTANCE
        plane_center = eye.offset(forward, plane_distance)
        
        # Project the world axis onto the view plane
        # The vanishing point is at infinity along the world axis direction
        # We simulate this by extending far along the axis
        far_distance = 10000.0  # Simulate infinity
        
        # Create a ray from eye along the world axis
        ray_point = eye.offset(world_axis, far_distance)
        
        # Find where this ray intersects the view plane
        # Using parametric line equation
        t = plane_distance / forward.dot(world_axis)
        
        if t.abs < 0.001 || t < 0  # Axis is parallel to view plane or behind camera
            return nil
        end
        
        # Calculate intersection point
        vp_x = eye.x + world_axis.x * t
        vp_y = eye.y + world_axis.y * t
        vp_z = eye.z + world_axis.z * t
        
        return Geom::Point3d.new(vp_x, vp_y, vp_z)
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Calculate Horizon Line
    # ---------------------------------------------------------------
    def self.calculate_horizon_line(eye, forward, right, up)
        # The horizon line is where the ground plane meets the sky at infinity
        # For a level camera, it's at eye height
        
        # Place horizon on a plane in front of camera
        plane_distance = CAMERA_OFFSET_DISTANCE
        plane_center = eye.offset(forward, plane_distance)
        
        # For horizon line, we need the intersection of ground plane with view
        # The horizon is always at eye level for level cameras
        horizon_height = eye.z
        
        # Calculate horizon endpoints far to left and right
        extend_distance = 5000.0  # Large distance for horizon
        
        # Project left and right points at eye level
        left_ray = right.reverse
        right_ray = right
        
        # Calculate horizon points
        left_point = plane_center.offset(left_ray, extend_distance)
        left_point.z = horizon_height
        
        right_point = plane_center.offset(right_ray, extend_distance)
        right_point.z = horizon_height
        
        return {
            start_point: left_point,
            end_point: right_point
        }
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Geometry Creation Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Create Vanishing Point Geometry
    # ------------------------------------------------------------
    def self.create_vanishing_point_geometry
        model = Sketchup.active_model                                       # Get active model
        
        # Start operation
        model.start_operation("Create Vanishing Points", true)
        
        # Remove existing vanishing point geometry if present
        remove_existing_vanishing_points
        
        # Calculate vanishing points
        vp_data = calculate_vanishing_points
        
        unless vp_data
            UI.messagebox("Camera must be in perspective mode!")
            model.abort_operation
            return
        end
        
        # Create separate groups for different geometry types
        scene_id = get_scene_identifier
        @horizon_line_group = model.active_entities.add_group
        @horizon_line_group.name = "HorizonLine_#{scene_id}"
        
        @vanishing_point_group = model.active_entities.add_group
        @vanishing_point_group.name = "VanishingPointCrosshairs_#{scene_id}"
        
        # Create geometry in separate groups
        create_horizon_line_geometry(vp_data[:horizon])                    # Create horizon line
        create_vanishing_point_crosshairs(vp_data[:vanishing_points])      # Create crosshairs
        
        # Apply separate tags
        apply_separate_vanishing_point_tags
        
        model.commit_operation
        
        # Report what was created
        vp_count = vp_data[:vanishing_points].size
        vp_types = vp_data[:vanishing_points].keys.map { |k| k.to_s.gsub('_', ' ') }.join(', ')
        
        message = "Created #{vp_count}-point perspective\n"
        message += "Vanishing points for: #{vp_types}\n"
        message += "Horizon line at eye level"
        
        UI.messagebox(message)
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create Horizon Line Geometry
    # ---------------------------------------------------------------
    def self.create_horizon_line_geometry(horizon_data)
        return unless horizon_data && @horizon_line_group
        
        entities = @horizon_line_group.entities                              # Use horizon line group
        
        # Create horizon line
        line = entities.add_line(horizon_data[:start_point], horizon_data[:end_point])
        
        # Apply color and style
        line.material = get_or_create_material(HORIZON_LINE_MATERIAL_NAME)
        line.set_attribute("VanishingPoints", "type", "horizon")
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create Vanishing Point Crosshairs
    # ---------------------------------------------------------------
    def self.create_vanishing_point_crosshairs(vanishing_points)
        return unless vanishing_points && @vanishing_point_group
        
        entities = @vanishing_point_group.entities
        
        vanishing_points.each do |type, position|
            next unless position
            
            create_single_crosshair(entities, position, type)               # Create crosshair at position
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Create Single Crosshair
    # ---------------------------------------------------------------
    def self.create_single_crosshair(entities, center_point, vp_type)
        # Get camera for orientation
        camera = Sketchup.active_model.active_view.camera
        eye = camera.eye
        
        # Calculate vectors from eye to vanishing point
        eye_to_vp = eye.vector_to(center_point).normalize
        
        # Create perpendicular vectors for crosshair
        # Use world up if possible, otherwise use camera up
        world_up = Geom::Vector3d.new(0, 0, 1)
        if eye_to_vp.parallel?(world_up)
            perp1 = eye_to_vp.cross(Geom::Vector3d.new(1, 0, 0)).normalize
        else
            perp1 = eye_to_vp.cross(world_up).normalize
        end
        perp2 = eye_to_vp.cross(perp1).normalize
        
        # Calculate crosshair endpoints
        half_size = CROSSHAIR_SIZE / 2.0
        
        # Horizontal line
        h_start = center_point.offset(perp1, -half_size)
        h_end = center_point.offset(perp1, half_size)
        h_line = entities.add_line(h_start, h_end)
        
        # Vertical line
        v_start = center_point.offset(perp2, -half_size)
        v_end = center_point.offset(perp2, half_size)
        v_line = entities.add_line(v_start, v_end)
        
        # Create circle oriented toward camera
        circle = entities.add_circle(center_point, eye_to_vp, CROSSHAIR_SIZE / 4.0, 16)
        
        # Apply color and attributes
        [h_line, v_line].each do |line|
            line.material = get_or_create_material(VANISHING_POINT_MATERIAL_NAME)
            line.set_attribute("VanishingPoints", "type", "crosshair_#{vp_type}")
        end
        
        circle.each do |edge|
            edge.material = get_or_create_material(VANISHING_POINT_MATERIAL_NAME)
            edge.set_attribute("VanishingPoints", "type", "circle_#{vp_type}")
        end
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Apply Separate Tags to Groups
    # ---------------------------------------------------------------
    def self.apply_separate_vanishing_point_tags
        model = Sketchup.active_model
        scene_id = get_scene_identifier
        
        # Create or get horizon line tag
        if @horizon_line_group
            horizon_tag = get_or_create_tag("#{HORIZON_LINE_POINTS_TAG_NAME}_#{scene_id}")
            @horizon_line_group.layer = horizon_tag if horizon_tag
        end
        
        # Create or get vanishing point crosshairs tag
        if @vanishing_point_group
            vp_tag = get_or_create_tag("#{VANISHING_POINTS_TAG_NAME}_#{scene_id}")
            @vanishing_point_group.layer = vp_tag if vp_tag
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Get or Create Named Material
    # ---------------------------------------------------------------
    def self.get_or_create_material(material_name)
        model = Sketchup.active_model
        materials = model.materials
        
        # Check if material already exists
        existing_material = materials[material_name]
        return existing_material if existing_material
        
        # Create new material with appropriate color
        new_material = materials.add(material_name)
        
        case material_name
        when HORIZON_LINE_MATERIAL_NAME
            new_material.color = HORIZON_LINE_COLOR                             # <-- Blue color for horizon line
        when VANISHING_POINT_MATERIAL_NAME
            new_material.color = VANISHING_POINT_COLOR                          # <-- Red color for vanishing points
        when CONSTRUCTION_MATERIAL_NAME
            new_material.color = CONSTRUCTION_COLOR                             # <-- Gray color for construction lines
        else
            new_material.color = CONSTRUCTION_COLOR                             # <-- Default to gray
        end
        
        return new_material
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Get or Create Named Tag
    # ---------------------------------------------------------------
    def self.get_or_create_tag(tag_name)
        model = Sketchup.active_model
        
        # Check if tag exists
        existing_tag = model.layers[tag_name]
        return existing_tag if existing_tag
        
        # Create new tag
        new_tag = model.layers.add(tag_name)
        new_tag.visible = true
        
        return new_tag
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Remove Existing Vanishing Points for Current Scene
    # ---------------------------------------------------------------
    def self.remove_existing_vanishing_points
        model = Sketchup.active_model
        scene_id = get_scene_identifier
        
        # Remove both types of groups for current scene
        horizon_group_pattern = "HorizonLine_#{scene_id}"
        vp_group_pattern = "VanishingPointCrosshairs_#{scene_id}"
        
        model.active_entities.grep(Sketchup::Group).each do |group|
            if group.name == horizon_group_pattern || group.name == vp_group_pattern
                group.erase!
            end
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Utility Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Get Scene Identifier
    # ---------------------------------------------------------------
    def self.get_scene_identifier
        model = Sketchup.active_model
        
        # If there's an active scene, use its name
        if model.pages.selected_page
            return model.pages.selected_page.name.gsub(/[^a-zA-Z0-9_]/, '_')
        else
            return "Default"
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Remove All Vanishing Points
    # ---------------------------------------------------------------
    def self.remove_all_vanishing_points
        model = Sketchup.active_model
        
        model.start_operation("Remove All Vanishing Points", true)
        
        # Remove all vanishing point groups
        model.active_entities.grep(Sketchup::Group).each do |group|
            if group.name.start_with?("VanishingPoints_")
                group.erase!
            end
        end
        
        # Remove all vanishing point tags
        model.layers.each do |layer|
            if layer.name.start_with?(DEFAULT_TAG_NAME)
                model.layers.remove(layer) if model.layers.respond_to?(:remove)
            end
        end
        
        # Remove vanishing point materials
        materials_to_remove = [
            HORIZON_LINE_MATERIAL_NAME,
            VANISHING_POINT_MATERIAL_NAME,
            CONSTRUCTION_MATERIAL_NAME
        ]
        
        materials_to_remove.each do |material_name|
            material = model.materials[material_name]
            if material
                model.materials.remove(material)                                # <-- Remove material from model
            end
        end
        
        model.commit_operation
        
        UI.messagebox("All vanishing points removed")
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Menu Integration (Disabled - Now integrated into ValeDesignSuite)
# -----------------------------------------------------------------------------

    # FUNCTION | Add Menu Items (Disabled for VDS Integration)
    # ---------------------------------------------------------------
    # def self.add_menu_items
    #     # Add to Extensions menu
    #     submenu = UI.menu("Extensions").add_submenu("Vanishing Points")
    #     
    #     submenu.add_item("Create Vanishing Points") {
    #         create_vanishing_point_geometry
    #     }
    #     
    # end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module VanishingPointDrawingAid

# VanishingPointDrawingAid.add_menu_items  # <-- Disabled for VDS integration 