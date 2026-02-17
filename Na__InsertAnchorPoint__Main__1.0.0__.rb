# --------------------------------------
# INSERT ANCHOR POINT TOOL
# --------------------------------------
# Interactive tool to place anchor point crosshairs with custom line styles
# Creates 4-way crosshair geometry with dashed red lines at selected vertices
# --------------------------------------
#
# SKETCHUP PREDEFINED LINE STYLE NAMES (Ruby API 2025)
# --------------------------------------
# | Line Style Name          | Visual Description                    |
# |--------------------------|---------------------------------------|
# | "Solid Basic"            | Standard solid line                   |
# | "Short dash"             | Short dashed pattern                  |
# | "Dash"                   | Medium dashed pattern                 |
# | "Dot"                    | Dotted pattern                        |
# | "Dash dot"               | Alternating dash and dot              |
# | "Dash double-dot"        | Dash followed by two dots             |
# | "Dash triple-dot"        | Dash followed by three dots           |
# | "Double-dash dot"        | Two dashes followed by dot            |
# | "Double-dash double-dot" | Two dashes followed by two dots       |
# | "Double-dash triple-dot" | Two dashes followed by three dots     |
# | "Long-dash dash"         | Long dash followed by short dash      |
# | "Long-dash double-dash"  | Long dash followed by two short dashes|
# --------------------------------------
# NOTE: Line style names are CASE-SENSITIVE and must match exactly
# --------------------------------------

module Util

    # --------------------------------------
    # SETUP | Ensure Tag and Material Resources Exist
    # --------------------------------------
    def self.setup_anchor_point_resources
        model          = Sketchup.active_model                    # <-- Get active model
        layers         = model.layers                             # <-- Get layers (tags) collection
        materials      = model.materials                          # <-- Get materials collection
        line_styles    = model.line_styles                        # <-- Get line styles collection
        
        tag_name       = "01__LineType__AnchorPoints"             # <-- Tag name constant
        material_name  = "01__LineType__AnchorPoints__RedLinework"  # <-- Material name constant
        
        # Check if tag exists, create if missing
        anchor_tag = layers[tag_name]                             # <-- Try to get existing tag
        if anchor_tag.nil?                                        # <-- Check if tag doesn't exist
            anchor_tag = layers.add(tag_name)                     # <-- Create new tag
            puts "Created tag: #{tag_name}"                       # <-- Print confirmation
        end                                                       # <-- End tag creation check
        
        # Apply dashed line style to tag
        dashed_style = line_styles["Dash"]                        # <-- Get dash line style (correct name)
        if dashed_style                                           # <-- Check if dash style exists
            anchor_tag.line_style = dashed_style                  # <-- Apply dash style to tag
            puts "Applied 'Dash' line style to tag"              # <-- Print confirmation
        else                                                      # <-- Handle missing line style
            puts "WARNING: 'Dash' line style not found"          # <-- Print warning
        end                                                       # <-- End line style application
        
        # Check if material exists, create if missing
        anchor_material = materials[material_name]                # <-- Try to get existing material
        if anchor_material.nil?                                   # <-- Check if material doesn't exist
            anchor_material = materials.add(material_name)        # <-- Create new material
            anchor_material.color = Sketchup::Color.new(255, 0, 0)  # <-- Set pure red color
            puts "Created material: #{material_name}"             # <-- Print confirmation
        end                                                       # <-- End material creation check
        
        return anchor_tag, anchor_material                        # <-- Return tag and material objects
    end
    
    # --------------------------------------
    # TOOL CLASS | Anchor Point Interactive Placement Tool
    # --------------------------------------
    class AnchorPointTool
        
        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            @ip            = Sketchup::InputPoint.new             # <-- Create input point for snapping
            @cursor_pos    = nil                                  # <-- Store cursor position
            @crosshair_size = 100.mm                              # <-- Cursor crosshair arm length (50mm)
        end
        
        # ACTIVATE | Called when tool is activated
        # ------------------------------------------------------------
        def activate
            puts "\n"                                             # <-- Clean linebreak
            puts "----------------------------------------"        # <-- Print horizontal line
            puts "ANCHOR POINT TOOL ACTIVATED"                    # <-- Print activation message
            puts "Click on a vertex to place anchor point"        # <-- Print instruction
            puts "----------------------------------------"        # <-- Print horizontal line
            Sketchup::set_status_text("Click to place anchor point", SB_PROMPT)  # <-- Set status bar text
        end
        
        # RESUME | Called when tool is resumed
        # ------------------------------------------------------------
        def resume(view)
            view.invalidate                                       # <-- Refresh view to redraw cursor
        end
        
        # ON MOUSE MOVE | Track cursor position with vertex snapping
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            @ip.pick(view, x, y)                                  # <-- Update input point with snapping
            @cursor_pos = @ip.position                            # <-- Store cursor position
            view.invalidate                                       # <-- Refresh view to redraw cursor
        end
        
        # DRAW | Render blue 3D crosshair cursor at mouse position
        # ------------------------------------------------------------
        def draw(view)
            return unless @cursor_pos                             # <-- Exit if no cursor position yet
            
            # Draw input point (shows vertex snapping indicator)
            @ip.draw(view)                                        # <-- Draw standard InputPoint indicator
            
            # Draw custom blue crosshair cursor
            cx = @cursor_pos.x                                    # <-- Get cursor X coordinate
            cy = @cursor_pos.y                                    # <-- Get cursor Y coordinate
            cz = @cursor_pos.z                                    # <-- Get cursor Z coordinate
            size = @crosshair_size                                # <-- Get crosshair size
            
            # Define crosshair line endpoints (world-aligned)
            x_pos = Geom::Point3d.new(cx + size, cy, cz)          # <-- Positive X direction
            x_neg = Geom::Point3d.new(cx - size, cy, cz)          # <-- Negative X direction
            y_pos = Geom::Point3d.new(cx, cy + size, cz)          # <-- Positive Y direction
            y_neg = Geom::Point3d.new(cx, cy - size, cz)          # <-- Negative Y direction
            z_pos = Geom::Point3d.new(cx, cy, cz + size)          # <-- Positive Z direction
            z_neg = Geom::Point3d.new(cx, cy, cz - size)          # <-- Negative Z direction
            
            # Set drawing color to blue
            view.line_stipple = ""                                # <-- Solid line
            view.line_width = 2                                   # <-- Line width 2 pixels
            view.drawing_color = Sketchup::Color.new(0, 100, 255) # <-- Blue color
            
            # Draw 3D crosshair lines (X, Y, Z axes)
            view.draw_line(@cursor_pos, x_pos)                    # <-- Draw +X arm
            view.draw_line(@cursor_pos, x_neg)                    # <-- Draw -X arm
            view.draw_line(@cursor_pos, y_pos)                    # <-- Draw +Y arm
            view.draw_line(@cursor_pos, y_neg)                    # <-- Draw -Y arm
            view.draw_line(@cursor_pos, z_pos)                    # <-- Draw +Z arm
            view.draw_line(@cursor_pos, z_neg)                    # <-- Draw -Z arm
        end
        
        # ON LEFT BUTTON DOWN | Create anchor point geometry at click position
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @ip.pick(view, x, y)                                  # <-- Update input point
            position = @ip.position                               # <-- Get click position
            
            if position                                           # <-- Check if valid position
                create_anchor_point_geometry(position)            # <-- Create the crosshair geometry
                Sketchup.active_model.select_tool(nil)            # <-- Deactivate tool
            end                                                   # <-- End position check
        end
        
        # CREATE ANCHOR POINT GEOMETRY | Build crosshair at specified position
        # ------------------------------------------------------------
        def create_anchor_point_geometry(center_point)
            model = Sketchup.active_model                         # <-- Get active model
            
            # Start operation for undo support
            model.start_operation('Insert Anchor Point', true)   # <-- Begin undo operation
            
            # Get resources (tag and material)
            anchor_tag, anchor_material = Util.setup_anchor_point_resources  # <-- Ensure resources exist
            
            # Get center coordinates
            cx = center_point.x                                   # <-- Center X coordinate
            cy = center_point.y                                   # <-- Center Y coordinate
            cz = center_point.z                                   # <-- Center Z coordinate
            arm_length = 250.mm                                   # <-- Crosshair arm length (250mm)
            
            # Define crosshair endpoints (world-aligned, XY plane only)
            pt_x_pos = Geom::Point3d.new(cx + arm_length, cy, cz)  # <-- +X endpoint
            pt_x_neg = Geom::Point3d.new(cx - arm_length, cy, cz)  # <-- -X endpoint
            pt_y_pos = Geom::Point3d.new(cx, cy + arm_length, cz)  # <-- +Y endpoint
            pt_y_neg = Geom::Point3d.new(cx, cy - arm_length, cz)  # <-- -Y endpoint
            
            # Create edges collection
            edges = []                                            # <-- Array to store created edges
            entities = model.active_entities                      # <-- Get active entities context
            
            # Create 4 crosshair edges
            edges << entities.add_line(center_point, pt_x_pos)    # <-- Create +X edge
            edges << entities.add_line(center_point, pt_y_pos)    # <-- Create +Y edge
            edges << entities.add_line(center_point, pt_x_neg)    # <-- Create -X edge
            edges << entities.add_line(center_point, pt_y_neg)    # <-- Create -Y edge
            
            # Apply tag and material to all edges
            edges.each do |edge|                                  # <-- Loop through each edge
                edge.layer = anchor_tag                           # <-- Apply tag to edge
                edge.material = anchor_material                   # <-- Apply red material to edge
            end                                                   # <-- End edge loop
            
            # Group all edges into a single container
            group = entities.add_group(edges)                     # <-- Create group from edges
            group.name = "01__AnchorPoint"                        # <-- Set group name
            
            # Commit operation
            model.commit_operation                                # <-- Commit undo operation
            
            puts "\n"                                             # <-- Clean linebreak
            puts "----------------------------------------"        # <-- Print horizontal line
            puts "ANCHOR POINT CREATED"                           # <-- Print confirmation
            puts "Position: X=#{cx.to_mm.round(2)}mm, Y=#{cy.to_mm.round(2)}mm, Z=#{cz.to_mm.round(2)}mm"  # <-- Print position
            puts "----------------------------------------"        # <-- Print horizontal line
        end
        
    end # End AnchorPointTool class
    
    # --------------------------------------
    # MAIN ENTRY POINT | Activate Anchor Point Tool
    # --------------------------------------
    def self.InsertAnchorPoint
        setup_anchor_point_resources                              # <-- Ensure resources exist
        Sketchup.active_model.select_tool(AnchorPointTool.new)    # <-- Activate the tool
    end

end # End Util module

# --------------------------------------
# UNCOMMENT TO IMMEDIATELY CALL FOR DIRECT CONSOLE EXECUTION
# --------------------------------------
# Util.InsertAnchorPoint

