# -----------------------------------------------------------------------------
# REGION | Paint Deep Nested Faces Tool
# -----------------------------------------------------------------------------
# Interactive tool to paint faces nested deep within groups/components
# Applies current global material to the specific face under cursor
# Works across all hierarchy levels without entering groups
# -----------------------------------------------------------------------------

module Na__PaintDeepNestedFaces
    
    # -----------------------------------------------------------------------------
    # REGION | Tool Class
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Deep Paint Interactive Tool
    # ------------------------------------------------------------
    class DeepPaintTool
        
        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            @ip            = Sketchup::InputPoint.new                     # <-- Create input point for detection
            @cursor_id     = 634                                          # <-- Standard Paint Bucket Cursor ID
            @hover_face    = nil                                          # <-- Track face currently under cursor
        end
        # ---------------------------------------------------------------
        
        # ACTIVATE | Called when tool is activated
        # ------------------------------------------------------------
        def activate
            puts "\n"                                                     # <-- Clean linebreak
            puts "----------------------------------------"                # <-- Print horizontal line
            puts "DEEP PAINT TOOL ACTIVATED"                              # <-- Print activation message
            puts "Click any face to apply current material"               # <-- Print instruction
            puts "Current Material: #{get_current_material_name}"         # <-- Print current material
            puts "----------------------------------------"                # <-- Print horizontal line
            
            Sketchup::set_status_text("Click to paint deep nested faces", SB_PROMPT)  # <-- Set status bar text
            update_vcb_display                                             # <-- Update VCB display
        end
        # ---------------------------------------------------------------
        
        # DEACTIVATE | Called when tool is deselected
        # ------------------------------------------------------------
        def deactivate(view)
            view.invalidate                                               # <-- Refresh view to clear highlights
        end
        # ---------------------------------------------------------------
        
        # RESUME | Called when tool is resumed
        # ------------------------------------------------------------
        def resume(view)
            view.invalidate                                               # <-- Refresh view
            update_vcb_display                                             # <-- Update VCB display
        end
        # ---------------------------------------------------------------
        
        # ON SET CURSOR | Handle custom cursor
        # ------------------------------------------------------------
        def onSetCursor
            UI.set_cursor(@cursor_id)                                     # <-- Set cursor to Paint Bucket
        end
        # ---------------------------------------------------------------
        
        # ON MOUSE MOVE | Track cursor position and highlight faces
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            @ip.pick(view, x, y)                                          # <-- Update input point
            
            new_face = @ip.face                                           # <-- Get face under cursor
            
            if new_face != @hover_face                                    # <-- Check if target changed
                @hover_face = new_face                                    # <-- Update stored face
                view.invalidate                                           # <-- Redraw to update highlighting
            end
            
            # Update tooltips or status based on what is hovered
            if @hover_face
                view.tooltip = "Face in: #{@ip.instance_path.leaf.name}" if @ip.instance_path.leaf.respond_to?(:name)
            else
                view.tooltip = ""
            end
        end
        # ---------------------------------------------------------------
        
        # ON LEFT BUTTON DOWN | Execute Painting
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @ip.pick(view, x, y)                                          # <-- Update input point
            face = @ip.face                                               # <-- Get the deep face entity
            
            if face.is_a?(Sketchup::Face)                                 # <-- Validate it is a face
                apply_material(face)                                      # <-- Apply the material
            else
                UI.beep                                                   # <-- Beep if miss
            end
        end
        # ---------------------------------------------------------------
        
        # -----------------------------------------------------------------------------
        # REGION | Core Logic
        # -----------------------------------------------------------------------------
        
        # FUNCTION | Apply Material to Target Face
        # ------------------------------------------------------------
        def apply_material(face)
            model = Sketchup.active_model                                 # <-- Get active model
            mat   = model.materials.current                               # <-- Get current global material
            
            # Start operation for undo support
            op_name = mat ? "Paint #{mat.display_name}" : "Paint Default" # <-- Name for Undo
            model.start_operation(op_name, true)                          # <-- Begin undo operation
            
            # Apply material (nil = default material)
            face.material = mat                                           # <-- Set front material
            
            # Optional: Decide if back material should also be painted
            # We paint the front only to be safe.
            
            model.commit_operation                                        # <-- Commit undo operation
            
            puts "Painted face ID: #{face.entityID}"                      # <-- Log to console
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Get Current Material Name Helper
        # ------------------------------------------------------------
        def get_current_material_name
            mat = Sketchup.active_model.materials.current                 # <-- Get current material
            return mat ? mat.display_name : "[Default]"                   # <-- Return name or Default
        end
        # ---------------------------------------------------------------

        # FUNCTION | Update VCB
        # ------------------------------------------------------------
        def update_vcb_display
            name = get_current_material_name                              # <-- Get name
            Sketchup::set_status_text(name, SB_VCB_VALUE)                 # <-- Set VCB value
            Sketchup::set_status_text("Active Material", SB_VCB_LABEL)    # <-- Set VCB label
        end
        # ---------------------------------------------------------------
        
    end # End DeepPaintTool class
    
    # endregion -------------------------------------------------------------------
    
    
    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Activate Deep Paint Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind this method in Preferences -> Shortcuts
    # Method name: Na__PaintDeepNestedFaces.Na__PaintDeepNestedFaces__Run
    # ------------------------------------------------------------
    def self.Na__PaintDeepNestedFaces__Run
        model = Sketchup.active_model                                     # <-- Get active model
        return unless model                                               # <-- Exit if no active model
        
        model.select_tool(DeepPaintTool.new)                              # <-- Activate the tool
    end
    # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    
    # -----------------------------------------------------------------------------
    # REGION | Menu Registration and Startup Wiring
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Install Menu and Commands
    # ------------------------------------------------------------
    def self.install_menu_and_commands
        return if @menu_installed                                         # <-- Exit if already installed
        
        # Create UI command for Deep Paint Tool
        cmd = UI::Command.new('NA_PaintDeepNestedFaces') do               # <-- Create command with label
            Na__PaintDeepNestedFaces.Na__PaintDeepNestedFaces__Run        # <-- Call the tool activation method
        end
        cmd.tooltip = "Paint Deep Nested Faces"                           # <-- Set tooltip
        cmd.status_bar_text = "Paint faces inside groups without editing" # <-- Set status bar text
        
        # SET NAME FOR EXTENSIONS MENU AND HOTKEY SEARCH
        cmd.menu_text = "NA__PaintDeepNestedFaces"                        # <-- Set menu text as requested
        
        # Add command to Plugins menu
        UI.menu('Plugins').add_item(cmd)                                  # <-- Add to Plugins menu
        
        @menu_installed = true                                            # <-- Mark as installed
    end
    # ---------------------------------------------------------------
    
    # FUNCTION | Activate for Model
    # ------------------------------------------------------------
    def self.activate_for_model(model)
        install_menu_and_commands                                         # <-- Install menu and commands
    end
    # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
end # End Na__PaintDeepNestedFaces module

# -----------------------------------------------------------------------------
# FILE LOADED CHECK | Prevent re-execution on reload
# -----------------------------------------------------------------------------
unless file_loaded?(__FILE__)
    # Activate immediately for the current model
    Na__PaintDeepNestedFaces.activate_for_model(Sketchup.active_model)    # <-- Activate menu registration
    
    file_loaded(__FILE__)                                                 # <-- Mark file as loaded
end

# -----------------------------------------------------------------------------
# CONSOLE EXECUTION | Uncomment to run directly in Ruby Console
# -----------------------------------------------------------------------------
# Na__PaintDeepNestedFaces.Na__PaintDeepNestedFaces__Run