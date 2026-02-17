# -----------------------------------------------------------------------------
# REGION | Insert Primitive Cube Tool
# -----------------------------------------------------------------------------
# Interactive tool to place primitive cube with 5mm grid snapping
# Creates 1000mm x 1000mm x 1000mm cube as a group at clicked position
# -----------------------------------------------------------------------------

module Na__InsertPrimatives
    
    # -----------------------------------------------------------------------------
    # REGION | Helper Functions
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Round Point to Nearest 5mm Grid Coordinate
    # ------------------------------------------------------------
    def self.round_point_to_nearest_5mm(pt)
        mm_inch = 25.4                                                      # <-- Millimeters to inches conversion
        step    = 5.0                                                       # <-- Grid step size (5mm)
        x_mm    = pt.x * mm_inch                                             # <-- Convert X to millimeters
        y_mm    = pt.y * mm_inch                                             # <-- Convert Y to millimeters
        z_mm    = pt.z * mm_inch                                             # <-- Convert Z to millimeters
        
        rx = (x_mm / step).round * step                                     # <-- Round X to nearest 5mm
        ry = (y_mm / step).round * step                                     # <-- Round Y to nearest 5mm
        rz = (z_mm / step).round * step                                     # <-- Round Z to nearest 5mm
        
        Geom::Point3d.new(rx / mm_inch, ry / mm_inch, rz / mm_inch)        # <-- Return snapped point in inches
    end
    # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    
    # -----------------------------------------------------------------------------
    # REGION | Tool Class
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Primitive Cube Interactive Placement Tool
    # ------------------------------------------------------------
    class PrimitiveCubeTool
        
        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            @ip            = Sketchup::InputPoint.new                     # <-- Create input point for snapping
            @cursor_pos    = nil                                          # <-- Store cursor position
            @crosshair_size = 300.mm                                      # <-- Cursor crosshair arm length (300mm)
            @cube_size_x   = 1000.mm                                      # <-- Cube X dimension (default 1000mm)
            @cube_size_y   = 1000.mm                                      # <-- Cube Y dimension (default 1000mm)
            @cube_size_z   = 1000.mm                                      # <-- Cube Z dimension (default 1000mm)
            @last_cube_group = nil                                        # <-- Reference to last created cube group
            @last_corner_position = nil                                    # <-- Store last corner position for regeneration
        end
        # ---------------------------------------------------------------
        
        # ACTIVATE | Called when tool is activated
        # ------------------------------------------------------------
        def activate
            puts "\n"                                                     # <-- Clean linebreak
            puts "----------------------------------------"                # <-- Print horizontal line
            puts "PRIMITIVE CUBE TOOL ACTIVATED"                          # <-- Print activation message
            puts "Click to place cube (snaps to 5mm grid)"                # <-- Print instruction
            puts "After placing, type dimensions in VCB: X,Y,Z"          # <-- Print VCB instruction
            puts "Example: 2000,4000,100 (regenerates last cube)"          # <-- Print example
            puts "Default: 1000mm x 1000mm x 1000mm"                     # <-- Print default size
            puts "----------------------------------------"                # <-- Print horizontal line
            Sketchup::set_status_text("Click to place primitive cube", SB_PROMPT)  # <-- Set status bar text
            update_vcb_display                                             # <-- Update VCB display
        end
        # ---------------------------------------------------------------
        
        # RESUME | Called when tool is resumed
        # ------------------------------------------------------------
        def resume(view)
            view.invalidate                                               # <-- Refresh view to redraw cursor
            update_vcb_display                                             # <-- Update VCB display
        end
        # ---------------------------------------------------------------
        
        # ON MOUSE MOVE | Track cursor position with snapping
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            @ip.pick(view, x, y)                                          # <-- Update input point with snapping
            @cursor_pos = @ip.position                                    # <-- Store cursor position
            view.invalidate                                               # <-- Refresh view to redraw cursor
        end
        # ---------------------------------------------------------------
        
        # DRAW | Render blue 3D crosshair cursor at mouse position
        # ------------------------------------------------------------
        def draw(view)
            return unless @cursor_pos                                     # <-- Exit if no cursor position yet
            
            # Draw input point (shows vertex snapping indicator)
            @ip.draw(view)                                                # <-- Draw standard InputPoint indicator
            
            # Draw custom blue crosshair cursor
            cx = @cursor_pos.x                                            # <-- Get cursor X coordinate
            cy = @cursor_pos.y                                            # <-- Get cursor Y coordinate
            cz = @cursor_pos.z                                            # <-- Get cursor Z coordinate
            size = @crosshair_size                                        # <-- Get crosshair size
            
            # Define crosshair line endpoints (world-aligned)
            x_pos = Geom::Point3d.new(cx + size, cy, cz)                  # <-- Positive X direction
            x_neg = Geom::Point3d.new(cx - size, cy, cz)                  # <-- Negative X direction
            y_pos = Geom::Point3d.new(cx, cy + size, cz)                 # <-- Positive Y direction
            y_neg = Geom::Point3d.new(cx, cy - size, cz)                 # <-- Negative Y direction
            z_pos = Geom::Point3d.new(cx, cy, cz + size)                 # <-- Positive Z direction
            z_neg = Geom::Point3d.new(cx, cy, cz - size)                 # <-- Negative Z direction
            
            # Set drawing color to blue
            view.line_stipple = ""                                        # <-- Solid line
            view.line_width = 2                                           # <-- Line width 2 pixels
            view.drawing_color = Sketchup::Color.new(0, 100, 255)         # <-- Blue color
            
            # Draw 3D crosshair lines (X, Y, Z axes)
            view.draw_line(@cursor_pos, x_pos)                            # <-- Draw +X arm
            view.draw_line(@cursor_pos, x_neg)                            # <-- Draw -X arm
            view.draw_line(@cursor_pos, y_pos)                            # <-- Draw +Y arm
            view.draw_line(@cursor_pos, y_neg)                            # <-- Draw -Y arm
            view.draw_line(@cursor_pos, z_pos)                            # <-- Draw +Z arm
            view.draw_line(@cursor_pos, z_neg)                            # <-- Draw -Z arm
        end
        # ---------------------------------------------------------------
        
        # ON LEFT BUTTON DOWN | Create cube geometry at click position
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @ip.pick(view, x, y)                                          # <-- Update input point
            position = @ip.position                                      # <-- Get click position
            
            if position                                                   # <-- Check if valid position
                create_cube_geometry(position)                             # <-- Create the cube geometry
                # Tool stays active for regeneration via VCB
            end                                                           # <-- End position check
        end
        # ---------------------------------------------------------------
        
        # -----------------------------------------------------------------------------
        # REGION | VCB (Value Control Box) Handling
        # -----------------------------------------------------------------------------
        
        # FUNCTION | Enable VCB Input
        # ------------------------------------------------------------
        def enableVCB?
            true                                                           # <-- Enable VCB input
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Update VCB Display with Current Dimensions
        # ------------------------------------------------------------
        def update_vcb_display
            x_mm = @cube_size_x.to_mm.round                              # <-- Convert X to millimeters
            y_mm = @cube_size_y.to_mm.round                              # <-- Convert Y to millimeters
            z_mm = @cube_size_z.to_mm.round                              # <-- Convert Z to millimeters
            Sketchup::set_status_text("#{x_mm},#{y_mm},#{z_mm}", SB_VCB_VALUE)  # <-- Set VCB value
            Sketchup::set_status_text("Cube Dimensions (X,Y,Z in mm)", SB_VCB_LABEL)  # <-- Set VCB label
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Handle User Text Input in VCB
        # ------------------------------------------------------------
        def onUserText(text, view)
            # Parse comma-separated values
            parts = text.split(',').map(&:strip)                          # <-- Split by comma and trim whitespace
            
            if parts.length == 3                                          # <-- Check if three values provided
                begin
                    # Parse each value as a length (supports mm, cm, m, etc.)
                    x_val = parts[0].to_l                                 # <-- Parse X dimension
                    y_val = parts[1].to_l                                 # <-- Parse Y dimension
                    z_val = parts[2].to_l                                 # <-- Parse Z dimension
                    
                    # Validate dimensions are positive
                    if x_val > 0 && y_val > 0 && z_val > 0               # <-- Check all dimensions positive
                        @cube_size_x = x_val                              # <-- Store X dimension
                        @cube_size_y = y_val                              # <-- Store Y dimension
                        @cube_size_z = z_val                              # <-- Store Z dimension
                        
                        update_vcb_display                                 # <-- Update VCB display
                        
                        # Regenerate last cube if it exists
                        if @last_cube_group && @last_cube_group.valid? && @last_corner_position  # <-- Check if last cube exists
                            regenerate_cube(@last_cube_group, @last_corner_position)  # <-- Regenerate cube with new dimensions
                            
                            # Update status text to show regeneration
                            x_mm = @cube_size_x.to_mm.round               # <-- Convert X to millimeters
                            y_mm = @cube_size_y.to_mm.round                # <-- Convert Y to millimeters
                            z_mm = @cube_size_z.to_mm.round                # <-- Convert Z to millimeters
                            Sketchup::set_status_text("Cube regenerated: #{x_mm}mm x #{y_mm}mm x #{z_mm}mm", SB_PROMPT)  # <-- Set status text
                        else                                               # <-- No cube to regenerate
                            # Update status text to show new dimensions for next cube
                            x_mm = @cube_size_x.to_mm.round               # <-- Convert X to millimeters
                            y_mm = @cube_size_y.to_mm.round                # <-- Convert Y to millimeters
                            z_mm = @cube_size_z.to_mm.round                # <-- Convert Z to millimeters
                            Sketchup::set_status_text("Dimensions set: #{x_mm}mm x #{y_mm}mm x #{z_mm}mm", SB_PROMPT)  # <-- Set status text
                        end                                                # <-- End cube check
                        
                        view.invalidate                                   # <-- Refresh view
                    else                                                  # <-- Handle invalid dimensions
                        UI.beep                                           # <-- Play error sound
                        Sketchup::set_status_text("Dimensions must be positive", SB_PROMPT)  # <-- Set error message
                    end                                                   # <-- End dimension validation
                rescue => e                                               # <-- Handle parsing errors
                    UI.beep                                               # <-- Play error sound
                    Sketchup::set_status_text("Invalid format. Use: X,Y,Z (e.g., 2000,4000,100)", SB_PROMPT)  # <-- Set error message
                end                                                       # <-- End error handling
            else                                                          # <-- Handle wrong number of values
                UI.beep                                                   # <-- Play error sound
                Sketchup::set_status_text("Enter 3 comma-separated values: X,Y,Z (e.g., 2000,4000,100)", SB_PROMPT)  # <-- Set error message
            end                                                           # <-- End value count check
        end
        # ---------------------------------------------------------------
        
        # endregion -------------------------------------------------------------------
        
        # REGENERATE CUBE | Rebuild cube with new dimensions at same position
        # ------------------------------------------------------------
        def regenerate_cube(cube_group, corner_position)
            return unless cube_group && cube_group.valid?                   # <-- Validate cube group
            
            model = Sketchup.active_model                                 # <-- Get active model
            
            # Start operation for undo support
            model.start_operation('Regenerate Primitive Cube', true)      # <-- Begin undo operation
            
            # Reset group transformation to identity (removes previous rotation)
            cube_group.transformation = Geom::Transformation.new            # <-- Reset transformation
            
            # Clear existing geometry in the group
            cube_group.entities.clear!                                     # <-- Clear all entities in group
            
            # Get corner coordinates
            corner_x = corner_position.x                                   # <-- Corner X coordinate
            corner_y = corner_position.y                                   # <-- Corner Y coordinate
            corner_z = corner_position.z                                   # <-- Corner Z coordinate
            
            # Use current cube dimensions
            cube_size_x = @cube_size_x                                    # <-- Cube X dimension
            cube_size_y = @cube_size_y                                    # <-- Cube Y dimension
            cube_size_z = @cube_size_z                                    # <-- Cube Z dimension
            
            # Get group entities collection
            group_entities = cube_group.entities                            # <-- Get group entities collection
            
            # Create base face points (bottom face at corner Z, extending +X and +Y)
            points = [                                                     # <-- Array of face corner points
                Geom::Point3d.new(corner_x, corner_y, corner_z),          # <-- Bottom-left corner
                Geom::Point3d.new(corner_x + cube_size_x, corner_y, corner_z), # <-- Bottom-right corner
                Geom::Point3d.new(corner_x + cube_size_x, corner_y + cube_size_y, corner_z), # <-- Top-right corner
                Geom::Point3d.new(corner_x, corner_y + cube_size_y, corner_z)  # <-- Top-left corner
            ]
            
            # Create base face inside group
            face = group_entities.add_face(points[0], points[1], points[2], points[3])  # <-- Create base face
            
            # Ensure face normal is pointing upwards (+Z)
            if face.normal.z < 0                                         # <-- Check if normal is downwards
                face.reverse!                                             # <-- Reverse face if normal is downwards
            end                                                           # <-- End normal check
            
            # Extrude face upwards by Z dimension to create cube
            face.pushpull(cube_size_z)                                    # <-- Extrude face to create cube
            
            # Commit operation
            model.commit_operation                                        # <-- Commit undo operation
            
            puts "\n"                                                     # <-- Clean linebreak
            puts "----------------------------------------"                # <-- Print horizontal line
            puts "PRIMITIVE CUBE REGENERATED"                             # <-- Print confirmation
            x_mm = cube_size_x.to_mm.round                                 # <-- Convert X to millimeters
            y_mm = cube_size_y.to_mm.round                                # <-- Convert Y to millimeters
            z_mm = cube_size_z.to_mm.round                                # <-- Convert Z to millimeters
            puts "New Size: #{x_mm}mm x #{y_mm}mm x #{z_mm}mm"           # <-- Print new size
            puts "----------------------------------------"                # <-- Print horizontal line
        end
        # ---------------------------------------------------------------
        
        # CREATE CUBE GEOMETRY | Build cube at specified position with 5mm snapping
        # ------------------------------------------------------------
        def create_cube_geometry(click_point)
            model = Sketchup.active_model                                 # <-- Get active model
            
            # Start operation for undo support
            model.start_operation('Insert Primitive Cube', true)          # <-- Begin undo operation
            
            # Snap clicked point to 5mm grid (this becomes bottom-left-front corner)
            snapped_corner = Na__InsertPrimatives.round_point_to_nearest_5mm(click_point)  # <-- Snap to grid
            
            # Get corner coordinates (bottom-left-front corner)
            corner_x = snapped_corner.x                                   # <-- Corner X coordinate
            corner_y = snapped_corner.y                                   # <-- Corner Y coordinate
            corner_z = snapped_corner.z                                  # <-- Corner Z coordinate
            
            # Use stored cube dimensions (defaults to 1000mm if not set)
            cube_size_x = @cube_size_x                                   # <-- Cube X dimension
            cube_size_y = @cube_size_y                                   # <-- Cube Y dimension
            cube_size_z = @cube_size_z                                   # <-- Cube Z dimension
            
            # Get active entities context
            entities = model.active_entities                              # <-- Get active entities context
            
            # Create base face points (bottom face at clicked Z, extending +X and +Y)
            points = [                                                     # <-- Array of face corner points
                Geom::Point3d.new(corner_x, corner_y, corner_z),          # <-- Bottom-left corner
                Geom::Point3d.new(corner_x + cube_size_x, corner_y, corner_z), # <-- Bottom-right corner
                Geom::Point3d.new(corner_x + cube_size_x, corner_y + cube_size_y, corner_z), # <-- Top-right corner
                Geom::Point3d.new(corner_x, corner_y + cube_size_y, corner_z)  # <-- Top-left corner
            ]
            
            # Create group first, then create geometry inside it
            cube_group = entities.add_group                               # <-- Create new empty group
            cube_group.name = "01__PrimitiveCube"                         # <-- Set group name
            group_entities = cube_group.entities                           # <-- Get group entities collection
            
            # Create base face inside group
            face = group_entities.add_face(points[0], points[1], points[2], points[3])  # <-- Create base face
            
            # Ensure face normal is pointing upwards (+Z)
            if face.normal.z < 0                                         # <-- Check if normal is downwards
                face.reverse!                                             # <-- Reverse face if normal is downwards
            end                                                           # <-- End normal check
            
            # Extrude face upwards by Z dimension to create cube
            face.pushpull(cube_size_z)                                    # <-- Extrude face to create cube
            
            # Store reference to last created cube for regeneration
            @last_cube_group = cube_group                                  # <-- Store cube group reference
            @last_corner_position = snapped_corner                        # <-- Store corner position
            
            # Commit operation
            model.commit_operation                                        # <-- Commit undo operation
            
            puts "\n"                                                     # <-- Clean linebreak
            puts "----------------------------------------"                # <-- Print horizontal line
            puts "PRIMITIVE CUBE CREATED"                                 # <-- Print confirmation
            puts "Bottom-Left-Front Corner: X=#{corner_x.to_mm.round(2)}mm, Y=#{corner_y.to_mm.round(2)}mm, Z=#{corner_z.to_mm.round(2)}mm"  # <-- Print position
            x_mm = cube_size_x.to_mm.round                                # <-- Convert X to millimeters
            y_mm = cube_size_y.to_mm.round                                # <-- Convert Y to millimeters
            z_mm = cube_size_z.to_mm.round                                # <-- Convert Z to millimeters
            puts "Size: #{x_mm}mm x #{y_mm}mm x #{z_mm}mm (extends +X, +Y, +Z)"  # <-- Print size
            puts "----------------------------------------"                # <-- Print horizontal line
        end
        # ---------------------------------------------------------------
        
    end # End PrimitiveCubeTool class
    
    # endregion -------------------------------------------------------------------
    
    
    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Insert Primitive Cube (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind this method in Preferences → Shortcuts to activate the tool
    # Method name: Na__InsertPrimatives.Na__InsertPrimatives__InsertCube
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__InsertCube
        model = Sketchup.active_model                                    # <-- Get active model
        return unless model                                              # <-- Exit if no active model
        
        model.select_tool(PrimitiveCubeTool.new)                         # <-- Activate the tool
    end
    # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    
    # -----------------------------------------------------------------------------
    # REGION | Menu Registration and Startup Wiring
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Install Menu and Commands
    # ------------------------------------------------------------
    def self.install_menu_and_commands
        return if @menu_installed                                          # <-- Exit if already installed
        
        # Create UI command for primitive cube tool
        cmd = UI::Command.new('NA_InsertPrimitiveCube') do                 # <-- Create command with label
            Na__InsertPrimatives.Na__InsertPrimatives__InsertCube          # <-- Call the tool activation method
        end
        cmd.tooltip = "Insert Primitive Cube"                              # <-- Set tooltip
        cmd.status_bar_text = "Activate primitive cube placement tool"    # <-- Set status bar text
        
        # Add command to Plugins menu
        UI.menu('Plugins').add_item(cmd)                                   # <-- Add to Plugins menu
        
        @menu_installed = true                                              # <-- Mark as installed
    end
    # ---------------------------------------------------------------
    
    # FUNCTION | Activate for Model
    # ------------------------------------------------------------
    def self.activate_for_model(model)
        install_menu_and_commands                                           # <-- Install menu and commands
    end
    # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
end # End Na__InsertPrimatives module

# -----------------------------------------------------------------------------
# FILE LOADED CHECK | Prevent re-execution on reload
# -----------------------------------------------------------------------------
unless file_loaded?(__FILE__)
    # Activate immediately for the current model
    Na__InsertPrimatives.activate_for_model(Sketchup.active_model)        # <-- Activate menu registration
    
    file_loaded(__FILE__)                                                  # <-- Mark file as loaded
end

# -----------------------------------------------------------------------------
# CONSOLE EXECUTION | Uncomment to run directly in Ruby Console
# -----------------------------------------------------------------------------
# Na__InsertPrimatives.Na__InsertPrimatives__InsertCube

