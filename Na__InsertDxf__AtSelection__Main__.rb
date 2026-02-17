# -----------------------------------------------------------------------------
# REGION | Insert DXF Tool with Interactive Placement
# -----------------------------------------------------------------------------
# Interactive tool to place DXF files with 5mm grid snapping
# Opens file dialog after click, imports DXF, rotates 90° around X-axis
# -----------------------------------------------------------------------------

module Na__InsertDxf
    
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
    
    # FUNCTION | DXF Interactive Placement Tool
    # ------------------------------------------------------------
    class DxfPlacementTool
        
        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            @ip            = Sketchup::InputPoint.new                     # <-- Create input point for snapping
            @cursor_pos    = nil                                          # <-- Store cursor position
            @crosshair_size = 300.mm                                      # <-- Cursor crosshair arm length (300mm)
        end
        # ---------------------------------------------------------------
        
        # ACTIVATE | Called when tool is activated
        # ------------------------------------------------------------
        def activate
            puts "\n"                                                     # <-- Clean linebreak
            puts "----------------------------------------"                # <-- Print horizontal line
            puts "DXF PLACEMENT TOOL ACTIVATED"                           # <-- Print activation message
            puts "Click to select insertion point (snaps to 5mm grid)"   # <-- Print instruction
            puts "File dialog will open after click"                      # <-- Print file dialog instruction
            puts "DXF will be rotated 90° around X-axis"                  # <-- Print rotation note
            puts "----------------------------------------"                # <-- Print horizontal line
            Sketchup::set_status_text("Click to select DXF insertion point", SB_PROMPT)  # <-- Set status bar text
        end
        # ---------------------------------------------------------------
        
        # RESUME | Called when tool is resumed
        # ------------------------------------------------------------
        def resume(view)
            view.invalidate                                               # <-- Refresh view to redraw cursor
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
        
        # ON LEFT BUTTON DOWN | Open file dialog and import DXF at click position
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @ip.pick(view, x, y)                                          # <-- Update input point
            position = @ip.position                                      # <-- Get click position
            
            if position                                                   # <-- Check if valid position
                import_dxf_at_position(position)                          # <-- Import DXF at position
                
                # Deactivate tool (single-use placement)
                model = Sketchup.active_model                             # <-- Get active model
                model.select_tool(nil)                                    # <-- Deactivate tool
            end                                                           # <-- End position check
        end
        # ---------------------------------------------------------------
        
        # IMPORT DXF AT POSITION | Import DXF file with rotation and translation
        # ------------------------------------------------------------
        def import_dxf_at_position(click_point)
            model = Sketchup.active_model                                 # <-- Get active model
            
            # Open file dialog to select DXF file
            path = UI.openpanel("Select DXF File", "", "DXF Files|*.dxf||")  # <-- Open file picker
            return unless path                                            # <-- User cancelled, exit
            
            # Snap clicked point to 5mm grid (insertion point)
            insertion_point = Na__InsertDxf.round_point_to_nearest_5mm(click_point)  # <-- Snap to grid
            
            # Start operation for undo support
            model.start_operation('Insert DXF', true)                     # <-- Begin undo operation
            
            begin
                # Get count of entities before import
                entities = model.active_entities                          # <-- Get active entities context
                entity_count_before = entities.length                     # <-- Count entities before import
                
                # Import DXF at origin (no dialog)
                status = model.import(path, false)                        # <-- Import DXF file
                
                if status                                                 # <-- Check import success
                    # Get newly imported entities (everything after original count)
                    entity_count_after = entities.length                  # <-- Count entities after import
                    new_entities = entities.to_a[entity_count_before..-1]  # <-- Get new entities array
                    
                    if new_entities && new_entities.length > 0           # <-- Check if entities were imported
                        # Create group from imported entities
                        dxf_group = entities.add_group(new_entities)      # <-- Group imported entities
                        dxf_group.name = "01__ImportedDXF"                # <-- Set group name
                        
                        # Create transformation: rotate 90° around X-axis, then translate
                        rotation = Geom::Transformation.rotation(ORIGIN, X_AXIS, 90.degrees)  # <-- Create rotation transform
                        translation = Geom::Transformation.translation(insertion_point.to_a)  # <-- Create translation transform
                        final_transform = translation * rotation          # <-- Combine transformations
                        
                        # Apply transformation to group
                        dxf_group.transformation = final_transform        # <-- Apply combined transformation
                        
                        # Commit operation
                        model.commit_operation                            # <-- Commit undo operation
                        
                        # Print success message
                        puts "\n"                                         # <-- Clean linebreak
                        puts "----------------------------------------"    # <-- Print horizontal line
                        puts "DXF IMPORTED SUCCESSFULLY"                  # <-- Print confirmation
                        puts "File: #{File.basename(path)}"               # <-- Print filename
                        puts "Insertion Point: X=#{insertion_point.x.to_mm.round(2)}mm, Y=#{insertion_point.y.to_mm.round(2)}mm, Z=#{insertion_point.z.to_mm.round(2)}mm"  # <-- Print position
                        puts "Entities Imported: #{new_entities.length}"  # <-- Print entity count
                        puts "Transformation: 90° rotation around X-axis"  # <-- Print transformation note
                        puts "----------------------------------------"    # <-- Print horizontal line
                    else                                                  # <-- No entities imported
                        model.abort_operation                             # <-- Abort operation
                        UI.messagebox("No entities were imported from the DXF file.")  # <-- Show error message
                        
                        puts "\n"                                         # <-- Clean linebreak
                        puts "----------------------------------------"    # <-- Print horizontal line
                        puts "DXF IMPORT FAILED: No entities"             # <-- Print error
                        puts "----------------------------------------"    # <-- Print horizontal line
                    end                                                   # <-- End entity check
                else                                                      # <-- Import failed
                    model.abort_operation                                 # <-- Abort operation
                    UI.messagebox("Failed to import DXF file. Check file format and try again.")  # <-- Show error message
                    
                    puts "\n"                                             # <-- Clean linebreak
                    puts "----------------------------------------"        # <-- Print horizontal line
                    puts "DXF IMPORT FAILED: Invalid file"                # <-- Print error
                    puts "----------------------------------------"        # <-- Print horizontal line
                end                                                       # <-- End import status check
                
            rescue => e                                                   # <-- Handle errors
                model.abort_operation                                     # <-- Abort operation
                UI.messagebox("Error importing DXF: #{e.message}")        # <-- Show error message
                
                puts "\n"                                                 # <-- Clean linebreak
                puts "----------------------------------------"            # <-- Print horizontal line
                puts "DXF IMPORT ERROR: #{e.message}"                     # <-- Print error
                puts "----------------------------------------"            # <-- Print horizontal line
            end                                                           # <-- End error handling
        end
        # ---------------------------------------------------------------
        
    end # End DxfPlacementTool class
    
    # endregion -------------------------------------------------------------------
    
    
    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Insert DXF at Selection (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind this method in Preferences → Shortcuts to activate the tool
    # Method name: Na__InsertDxf.Na__InsertDxf__InsertAtSelection
    # ------------------------------------------------------------
    def self.Na__InsertDxf__InsertAtSelection
        model = Sketchup.active_model                                    # <-- Get active model
        return unless model                                              # <-- Exit if no active model
        
        model.select_tool(DxfPlacementTool.new)                          # <-- Activate the tool
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
        
        # Create UI command for DXF placement tool
        cmd = UI::Command.new('NA_InsertDxfAtSelection') do                # <-- Create command with label
            Na__InsertDxf.Na__InsertDxf__InsertAtSelection                 # <-- Call the tool activation method
        end
        cmd.tooltip = "Insert DXF at Selection"                            # <-- Set tooltip
        cmd.status_bar_text = "Activate DXF placement tool (rotated 90° around X-axis)"  # <-- Set status bar text
        
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
    
end # End Na__InsertDxf module

# -----------------------------------------------------------------------------
# FILE LOADED CHECK | Prevent re-execution on reload
# -----------------------------------------------------------------------------
unless file_loaded?(__FILE__)
    # Activate immediately for the current model
    Na__InsertDxf.activate_for_model(Sketchup.active_model)              # <-- Activate menu registration
    
    file_loaded(__FILE__)                                                  # <-- Mark file as loaded
end

# -----------------------------------------------------------------------------
# CONSOLE EXECUTION | Uncomment to run directly in Ruby Console
# -----------------------------------------------------------------------------
# Na__InsertDxf.Na__InsertDxf__InsertAtSelection

