# =============================================================================
# NA__SimpleWindowMaker__Main__.rb
#
# FILE       : Na__SimpleWindowMaker__Main__.rb
# MODULE     : SimpleWindowMaker
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Simple Window Maker tool
#
# DESCRIPTION:
# - This module encapsulates the Simple Window Maker tool.
# - The tool is designed to take a simple plan and will create the necessary offsets and glazed bar divisions.

# =============================================================================
# DEV LOG:
# 05-Sep-2025 - Version 1.0.0
# - Initial release
#
# 08-Oct-2025 - Version 1.1.0
# - Window Cills Added to Window Panels
#
# 08-Oct-2025 - Version 1.2.0
# - Added WindowFrame__OuterFramework that wraps left, right, and top sides
# - Outer framework creates proper window reveal with configurable width and depth
# - Updated casement inset logic to sit within outer framework
# - Cill extended to match outer framework width
# - All glass panels and glazing bars properly positioned within new structure
#
# 08-Oct-2025 - Version 1.2.1 - CRITICAL FIX
# - Fixed window to respect original input dimensions (no expansion)
# - Outer framework now matches exact input face dimensions
# - All components properly inset within original bounds
# - Casement correctly fits within inset hole of outer framework
# - Cill width matches original input width, aligns with outer framework edges
#
# 08-Oct-2025 - Version 1.2.2
# - Added fine-tuning inset for casement elements (10mm inset into framework)
# - Casement Stiles&Rails, Glass Panels, and Glaze Bars now inset 10mm along Z-axis
# - Creates proper depth reveal between outer framework and casement
# - Cill depth increased to 90mm for better proportion
#
# 08-Oct-2025 - Version 1.3.0
# - Reversed casement inset direction (-10mm instead of +10mm)
# - Casement elements now inset backward into the framework
# - Creates proper recessed appearance for casement within outer framework
# 
# =============================================================================

# frozen_string_literal: true

require 'sketchup.rb'

# =============================================================================
# SIMPLE WINDOW MAKER MODULE
# =============================================================================
# This module encapsulates the Simple Window Maker tool.
module SimpleWindowMaker
  
  # region --------------------------------------------------------------------
  # PREPROCESSING UTILITY | REMOVE MATERIALS AND TAGS
  # ---------------------------------------------------------------------------
  def self.PreProcessingUtil__RemoveMaterialsAndTags(entity)
    # Recursively removes materials and layer/tag assignments from geometry
    # This ensures clean geometry before window creation
    
    if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      # Get the definition and process all child entities
      definition = entity.definition
      definition.entities.each do |child_entity|
        PreProcessingUtil__RemoveMaterialsAndTags(child_entity)
      end
      
      # Clear layer/tag assignment from the group/component itself
      entity.layer = nil if entity.layer
      
    elsif entity.is_a?(Sketchup::Face)
      # Remove materials from face
      entity.material = nil                                                  # <-- Clear front material
      entity.back_material = nil                                             # <-- Clear back material
      
      # Clear layer/tag assignment from face
      entity.layer = nil if entity.layer
      
    elsif entity.is_a?(Sketchup::Edge)
      # Clear material and layer from edges
      entity.material = nil if entity.material
      entity.layer = nil if entity.layer
      
    elsif entity.is_a?(Sketchup::Entities)
      # If passed an entities collection, process each entity
      entity.each do |child_entity|
        PreProcessingUtil__RemoveMaterialsAndTags(child_entity)
      end
    end
    
    entity                                                                   # <-- Return the cleaned entity
  end
  # endregion ------------------------------------------------------------------
  
  # ---------------------------------------------------------------------------
  # MAIN METHOD TO CREATE WINDOW GEOMETRY
  # ---------------------------------------------------------------------------
  def self.Ceate3dObject__PlaneToWindow
    model = Sketchup.active_model
    selection = model.selection

    # -------------------------------------------------------------------------
    #Region STEP 1A: VALIDATE USER SELECTION
    # -------------------------------------------------------------------------
    unless selection.length == 1                                              # <-- Check for single selection
      UI.messagebox('Error: Please select exactly one group or component.')
      return
    end

    target = selection[0]                                                     # <-- Get the selected item
    unless target.is_a?(Sketchup::Group) || target.is_a?(Sketchup::ComponentInstance)
      UI.messagebox('Error: The selected item must be a group or a component.')
      return
    end

    definition = target.definition                                            # <-- Get the component definition
    main_face = definition.entities.grep(Sketchup::Face).max_by(&:area)     # <-- Find the largest face
    unless main_face
      UI.messagebox('Error: Could not find a face in the selected component.')
      return
    end
    # -------------------------------------------------------------------------
    #endregion STEP 1A: VALIDATE USER SELECTION
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    #Region STEP 1B: CLEAN GEOMETRY - REMOVE MATERIALS AND TAGS
    # -------------------------------------------------------------------------
    # Remove all materials and layer/tag assignments before creating window
    # This ensures clean geometry and prevents conflicts with new materials
    PreProcessingUtil__RemoveMaterialsAndTags(target)                        # <-- Clean the selected target
    # -------------------------------------------------------------------------
    #endregion STEP 1B: CLEAN GEOMETRY - REMOVE MATERIALS AND TAGS
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    #Region STEP 2: GET USER INPUT PARAMETERS
    # -------------------------------------------------------------------------
    prompts = [
      'WindowFrame__OuterFramework Width',
      'WindowFrame__OuterFramework Depth',
      'Casement Frame Depth (e.g., 70mm)',
      'Casement Frame Width (perimeter offset)',
      'Number of Vertical Panes',
      'Number of Horizontal Panes',
      'Glazing Bar Width',
      'Glazing Bar Depth'
    ]
    defaults = ['50mm', '100mm', '60mm', '60mm', 2, 2, '25mm', '40mm']      # <-- Default values for inputs
    input = UI.inputbox(prompts, defaults, 'Simple Window Maker Settings')
    return unless input                                                       # <-- Exit if user cancels

    outer_frame_width = input[0].to_l                                        # <-- Outer framework width (left/right/top)
    outer_frame_depth = input[1].to_l                                        # <-- Outer framework depth (extrusion)
    frame_depth = input[2].to_l                                              # <-- Casement frame depth
    frame_width = input[3].to_l                                              # <-- Casement frame width
    vertical_panes = input[4].to_i                                           # <-- Convert to integer
    horizontal_panes = input[5].to_i                                         # <-- Convert to integer
    bar_width = input[6].to_l                                                # <-- Convert to length
    bar_depth = input[7].to_l                                                # <-- Convert to length
    # -------------------------------------------------------------------------
    #endregion STEP 2: GET USER INPUT PARAMETERS
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    #Region STEP 3: CREATE WINDOW GEOMETRY
    # -------------------------------------------------------------------------
    model.start_operation('Create Hollow Frame and Glazing', true)

    # -------------------------------------------------------------------------
    #Region EXTRACT GEOMETRIC INFORMATION
    # -------------------------------------------------------------------------
    # First, get all the geometric info we need from the original 2D face.
    inner_bounds = Geom::BoundingBox.new.add(main_face.vertices.map(&:position))  # <-- Get face boundaries
    face_normal = main_face.normal                                                 # <-- Save face normal BEFORE deleting
    offset_vec_x = face_normal.axes.x                                              # <-- Get X axis vector
    offset_vec_y = face_normal.axes.y                                              # <-- Get Y axis vector
    
    # Define cill dimensions
    cill_height = 50.mm                                                            # <-- Standard cill height
    cill_depth = frame_depth + 90.mm                                              # <-- Cill extends frame_depth + 50mm
    # -------------------------------------------------------------------------
    #endregion EXTRACT GEOMETRIC INFORMATION
    # -------------------------------------------------------------------------
    
    # -------------------------------------------------------------------------
    #Region CREATE WINDOW CILL
    # -------------------------------------------------------------------------
    # Create the cill in its own group before creating the frame
    cill_group = definition.entities.add_group                                     # <-- Create cill group
    cill_group.name = "Window Cill"                                               # <-- Name the group
    cill_entities = cill_group.entities                                           # <-- Get group entities
    
    # Calculate cill position (at bottom of window, extends outward)
    # Cill respects original width - aligns with outer framework edges
    cill_start = inner_bounds.min                                                 # <-- Start at original left edge
    cill_width = inner_bounds.width                                               # <-- Match original width exactly
    cill_pts = [
      cill_start,
      cill_start.offset(offset_vec_x, cill_width),
      cill_start.offset(offset_vec_x, cill_width).offset(offset_vec_y, cill_height),
      cill_start.offset(offset_vec_y, cill_height)
    ]
    cill_face = cill_entities.add_face(cill_pts)                                 # <-- Create cill face
    cill_face.pushpull(-cill_depth)                                              # <-- Extrude cill outward
    # -------------------------------------------------------------------------
    #endregion CREATE WINDOW CILL
    # -------------------------------------------------------------------------
    
    # -------------------------------------------------------------------------
    #Region CREATE OUTER FRAMEWORK
    # -------------------------------------------------------------------------
    # Create the outer framework group that wraps left, right, and top
    outer_framework_group = definition.entities.add_group                         # <-- Create outer framework group
    outer_framework_group.name = "WindowFrame__OuterFramework"                   # <-- Name the group
    outer_framework_entities = outer_framework_group.entities                     # <-- Get group entities
    
    # Calculate outer framework dimensions
    # The framework matches the original input dimensions exactly
    framework_start = inner_bounds.min.offset(offset_vec_y, cill_height)          # <-- Start at cill height, original left edge
    framework_width = inner_bounds.width                                           # <-- Use original width exactly
    framework_height = inner_bounds.height - cill_height                          # <-- Height above cill
    
    # Create outer rectangle face
    outer_pts = [
      framework_start,
      framework_start.offset(offset_vec_x, framework_width),
      framework_start.offset(offset_vec_x, framework_width).offset(offset_vec_y, framework_height),
      framework_start.offset(offset_vec_y, framework_height)
    ]
    outer_face = outer_framework_entities.add_face(outer_pts)                     # <-- Create outer face
    outer_face.pushpull(-outer_frame_depth)                                       # <-- Extrude outer framework
    
    # Cut hole for casement - inner rectangle
    # The hole is inset by outer_frame_width on left, right, and top
    hole_start = framework_start.offset(offset_vec_x, outer_frame_width)          # <-- Inset from left
    hole_width = framework_width - (2 * outer_frame_width)                        # <-- Subtract left and right frame widths
    hole_height = framework_height - outer_frame_width                            # <-- Subtract top frame only (no bottom frame)
    
    hole_pts = [
      hole_start,
      hole_start.offset(offset_vec_x, hole_width),
      hole_start.offset(offset_vec_x, hole_width).offset(offset_vec_y, hole_height),
      hole_start.offset(offset_vec_y, hole_height)
    ]
    hole_face = outer_framework_entities.add_face(hole_pts)                       # <-- Create hole face
    hole_face.pushpull(-outer_frame_depth)                                        # <-- Cut through outer framework
    # -------------------------------------------------------------------------
    #endregion CREATE OUTER FRAMEWORK
    # -------------------------------------------------------------------------
    
    # -------------------------------------------------------------------------
    #Region CREATE CASEMENT CONTAINER
    # -------------------------------------------------------------------------
    # Delete the original face first since we'll create a new one
    main_face.erase!                                                         # <-- Remove original face
    
    # Create a main container group for all casement elements
    casement_container = definition.entities.add_group                       # <-- Create main casement container
    casement_container.name = "Casement Assembly"                            # <-- Name the container
    
    # -------------------------------------------------------------------------
    #Region CREATE CASEMENT STILES AND RAILS
    # -------------------------------------------------------------------------    
    # Create a sub-group for the casement frame (stiles and rails)
    casement_frame_group = casement_container.entities.add_group             # <-- Create casement frame group
    casement_frame_group.name = "Casement__Stiles&Rails"                     # <-- Name the group
    frame_entities = casement_frame_group.entities                           # <-- Get group entities
    
    # Calculate casement dimensions - it sits within the outer framework hole
    # The casement exactly fits the hole cut in the outer framework
    casement_start = inner_bounds.min.offset(offset_vec_x, outer_frame_width).offset(offset_vec_y, cill_height)  # <-- Inset from left, start at cill
    casement_width = inner_bounds.width - (2 * outer_frame_width)            # <-- Width minus left and right frames
    casement_height = inner_bounds.height - cill_height - outer_frame_width  # <-- Height minus cill and top frame
    
    frame_pts = [
      casement_start,
      casement_start.offset(offset_vec_x, casement_width),
      casement_start.offset(offset_vec_x, casement_width).offset(offset_vec_y, casement_height),
      casement_start.offset(offset_vec_y, casement_height)
    ]
    frame_face = frame_entities.add_face(frame_pts)                          # <-- Create casement face
    frame_face.pushpull(-frame_depth)                                        # <-- Push face to create solid
    # -------------------------------------------------------------------------
    #endregion CREATE CASEMENT STILES AND RAILS
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    #Region CUT HOLE IN CASEMENT
    # -------------------------------------------------------------------------
    # Now, we cut a hole through the solid block to create a true casement frame.
    # The casement frame width creates the stiles and rails thickness
    inner_width = casement_width - (2 * frame_width)                         # <-- Calculate inner width
    inner_height = casement_height - (2 * frame_width)                       # <-- Calculate inner height (frame on all 4 sides)
    start_point = casement_start.offset(offset_vec_x, frame_width).offset(offset_vec_y, frame_width)  # <-- Inset from casement edges

    # Create a temporary face on the front of the block.
    hole_pts = [
      start_point,
      start_point.offset(offset_vec_x, inner_width),
      start_point.offset(offset_vec_x, inner_width).offset(offset_vec_y, inner_height),
      start_point.offset(offset_vec_y, inner_height)
    ]
    hole_face = frame_entities.add_face(hole_pts)                            # <-- Create hole face in casement group
    
    # Push this face backwards through the block to cut the hole.
    # The pushpull operation on a sub-face will remove the material.
    hole_face.pushpull(-frame_depth)                                         # <-- Cut through casement
    # -------------------------------------------------------------------------
    #endregion CUT HOLE IN CASEMENT
    # -------------------------------------------------------------------------
    # -------------------------------------------------------------------------
    #endregion CREATE CASEMENT STILES AND RAILS
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    #Region BUILD GLAZING ASSEMBLIES
    # -------------------------------------------------------------------------
    # Create sub-groups for glass panels
    glazing_assembly_group = casement_container.entities.add_group           # <-- Create glazing group
    glazing_assembly_group.name = "Casement__GlassPanels"                    # <-- Name glass panels group
    assembly_entities = glazing_assembly_group.entities                      # <-- Get group entities

    # Calculate dimensions for individual panes and bars.
    num_vertical_bars = vertical_panes - 1                                   # <-- Number of vertical bars
    num_horizontal_bars = horizontal_panes - 1                               # <-- Number of horizontal bars
    pane_width = (inner_width - (num_vertical_bars * bar_width)) / vertical_panes      # <-- Pane width calculation
    pane_height = (inner_height - (num_horizontal_bars * bar_width)) / horizontal_panes # <-- Pane height calculation

    # Calculate inset positions:
    # - Glazing bars start 10mm back from the front of the frame
    # - Glass is centered on the glazing bars (10mm from the back of the bars for 45mm bar depth and 25mm glass)
    bar_inset = 10.mm                                                        # <-- Bar inset from front
    glass_inset = bar_inset + ((bar_depth - 25.mm) / 2)                     # <-- Glass centered on bars
    
    # Offset the start point for the glazing bars (10mm back from front)
    bar_start_base = start_point.offset(face_normal.reverse, bar_inset)      # <-- Bar start position
    # Offset the start point for the glass panes (centered on bars)
    glass_start_base = start_point.offset(face_normal.reverse, glass_inset)   # <-- Glass start position
    # -------------------------------------------------------------------------
    #endregion BUILD GLAZING ASSEMBLIES
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    #Region CREATE GLASS PANELS
    # -------------------------------------------------------------------------
    # Loop and create each glass pane in its own group.
    (0...horizontal_panes).each do |row|                                     # <-- Loop through rows
      (0...vertical_panes).each do |col|                                     # <-- Loop through columns
        x_pos = col * (pane_width + bar_width)                               # <-- Calculate X position
        y_pos = row * (pane_height + bar_width)                              # <-- Calculate Y position
        pane_start_point = glass_start_base.offset(offset_vec_x, x_pos).offset(offset_vec_y, y_pos)
        pane_pts = [
          pane_start_point,
          pane_start_point.offset(offset_vec_x, pane_width),
          pane_start_point.offset(offset_vec_x, pane_width).offset(offset_vec_y, pane_height),
          pane_start_point.offset(offset_vec_y, pane_height)
        ]
        pane_group = assembly_entities.add_group                             # <-- Create pane group
        pane_group.name = "Glass Panel (#{row},#{col})"                      # <-- Name the panel
        face = pane_group.entities.add_face(pane_pts)                        # <-- Create pane face
        face.material = '85__WhiteCard__Glass'                               # <-- Apply glass material
        face.back_material = '85__WhiteCard__Glass'                          # <-- Apply back material
        face.pushpull(-25.mm)                                                # <-- Give glass its 25mm thickness
      end
    end
    # -------------------------------------------------------------------------
    #endregion CREATE GLASS PANELS
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    #Region CREATE VERTICAL GLAZE BARS
    # -------------------------------------------------------------------------
    # Create a group for all glazing bars
    glaze_bars_group = casement_container.entities.add_group                 # <-- Create glaze bars group
    glaze_bars_group.name = "Casement__GlazeBars"                           # <-- Name the group
    glaze_bars_entities = glaze_bars_group.entities                         # <-- Get group entities
    
    # Loop and create each vertical bar in its own sub-group.
    if num_vertical_bars > 0                                                 # <-- Check if bars needed
      (0...num_vertical_bars).each do |i|                                    # <-- Loop through vertical bars
        x_pos = (i + 1) * pane_width + i * bar_width                         # <-- Calculate X position
        bar_start_point = bar_start_base.offset(offset_vec_x, x_pos)         # <-- Calculate start point
        bar_pts = [
          bar_start_point,
          bar_start_point.offset(offset_vec_x, bar_width),
          bar_start_point.offset(offset_vec_x, bar_width).offset(offset_vec_y, inner_height),
          bar_start_point.offset(offset_vec_y, inner_height)
        ]
        bar_group = glaze_bars_entities.add_group                            # <-- Create bar sub-group
        bar_group.name = "Vertical Glaze Bar #{i+1}"                         # <-- Name the bar
        face = bar_group.entities.add_face(bar_pts)                          # <-- Create bar face
        face.pushpull(-bar_depth)                                            # <-- Extrude bar to depth
      end
    end
    # -------------------------------------------------------------------------
    #endregion CREATE VERTICAL GLAZE BARS
    # -------------------------------------------------------------------------
    
    # -------------------------------------------------------------------------
    #Region CREATE HORIZONTAL GLAZE BARS
    # -------------------------------------------------------------------------
    # Loop and create each horizontal bar in its own sub-group.
    if num_horizontal_bars > 0                                               # <-- Check if bars needed
      (0...num_horizontal_bars).each do |i|                                  # <-- Loop through horizontal bars
        y_pos = (i + 1) * pane_height + i * bar_width                        # <-- Calculate Y position
        bar_start_point = bar_start_base.offset(offset_vec_y, y_pos)         # <-- Calculate start point
        bar_pts = [
          bar_start_point,
          bar_start_point.offset(offset_vec_x, inner_width),
          bar_start_point.offset(offset_vec_x, inner_width).offset(offset_vec_y, bar_width),
          bar_start_point.offset(offset_vec_y, bar_width)
        ]
        bar_group = glaze_bars_entities.add_group                            # <-- Create bar sub-group
        bar_group.name = "Horizontal Glaze Bar #{i+1}"                       # <-- Name the bar
        face = bar_group.entities.add_face(bar_pts)                          # <-- Create bar face
        face.pushpull(-bar_depth)                                            # <-- Extrude bar to depth
      end
    end
    # -------------------------------------------------------------------------
    #endregion CREATE HORIZONTAL GLAZE BARS
    # -------------------------------------------------------------------------
    
    # -------------------------------------------------------------------------
    #endregion CREATE CASEMENT CONTAINER
    # -------------------------------------------------------------------------
    
    # -------------------------------------------------------------------------
    #Region POSITION WINDOW ELEMENTS
    # -------------------------------------------------------------------------
    # Move elements to their correct Z-positions
    # Outer framework is furthest back, then casement, then glazing elements
    
    # Create backward translation vector for outer framework (negative Z direction)
    translation_vector_outer = face_normal.reverse                           # <-- Get reverse normal direction
    translation_vector_outer.length = outer_frame_depth                      # <-- Set vector length to outer frame depth
    translation_outer = Geom::Transformation.translation(translation_vector_outer)
    
    # Create backward translation vector for casement (negative Z direction)
    translation_vector_casement = face_normal.reverse                        # <-- Get reverse normal direction
    translation_vector_casement.length = frame_depth                         # <-- Set vector length to casement depth
    translation_casement = Geom::Transformation.translation(translation_vector_casement)
    
    # Create forward translation vector (positive Z direction)
    translation_vector_forward = face_normal.clone                           # <-- Get normal direction
    translation_vector_forward.length = frame_depth                          # <-- Set vector length to frame depth
    translation_forward = Geom::Transformation.translation(translation_vector_forward)
    
    # Apply transformations to position all elements correctly
    cill_group.transform!(translation_outer)                                 # <-- Move cill backward by outer frame depth
    outer_framework_group.transform!(translation_outer)                      # <-- Move outer framework backward
    casement_frame_group.transform!(translation_casement)                    # <-- Move Casement__Stiles&Rails backward
    
    # # Apply forward transformation to glazing elements
    # glazing_assembly_group.transform!(translation_forward)                   # <-- Move Casement__GlassPanels forward
    # glaze_bars_group.transform!(translation_forward)                         # <-- Move Casement__GlazeBars forward
    # -------------------------------------------------------------------------
    #endregion POSITION WINDOW ELEMENTS
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    #Region Fine Tuning - Inset of Casement Elements Into The Framework
    # -------------------------------------------------------------------------
    # This will be controlled by a new user input parameter in the future
    # For now its fixed a 10mm inset into the framework. (Z-axis + 10mm)
    
    # Create inset transformation (move forward 10mm along face normal)
    casement_inset_distance = -10.mm                                          # <-- Fixed inset distance
    translation_vector_inset = face_normal.clone                             # <-- Get normal direction (forward)
    translation_vector_inset.length = casement_inset_distance                # <-- Set vector length
    translation_inset = Geom::Transformation.translation(translation_vector_inset)
    
    # Apply inset transformation to all casement elements
    casement_frame_group.transform!(translation_inset)                       # <-- Inset Casement__Stiles&Rails
    glazing_assembly_group.transform!(translation_inset)                     # <-- Inset Casement__GlassPanels
    glaze_bars_group.transform!(translation_inset)                           # <-- Inset Casement__GlazeBars
    # -------------------------------------------------------------------------
    #endregion Fine Tuning - Inset of Casement Elements Into The Framework
    # -------------------------------------------------------------------------


    model.commit_operation                                                   # <-- Commit the operation
    # -------------------------------------------------------------------------
    #endregion STEP 3: CREATE WINDOW GEOMETRY
    # -------------------------------------------------------------------------

  rescue StandardError => e
    model.abort_operation                                                    # <-- Abort on error
    UI.messagebox("An unexpected error occurred: #{e.message}\n#{e.backtrace.join("\n")}")
  end

  # ---------------------------------------------------------------------------
  # UNCOMMENT BELOW TO RUN (TESTING ETC) COMMENT OUT WHEN LOADING WITH SKETCHUP INIT
  # ---------------------------------------------------------------------------
  # SimpleWindowMaker.Ceate3dObject__PlaneToWindow                            # <-- Execute the window creation
  # ---------------------------------------------------------------------------

end
# =============================================================================
# END OF MODULE
# =============================================================================