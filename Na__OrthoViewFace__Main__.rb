# -----------------------------------------------------------------------------
# REGION | Ortho View Align Tool
# -----------------------------------------------------------------------------
# Interactive tool to align camera to any face (nested or top-level)
# Sets camera to Parallel Projection (Ortho) and Zooms Extents to face
# Provides visual feedback with green overlay and red border
# -----------------------------------------------------------------------------

module Na__OrthoViewFace

    # -----------------------------------------------------------------------------
    # REGION | Tool Class
    # -----------------------------------------------------------------------------

    # FUNCTION | Ortho Alignment Interactive Tool
    # ------------------------------------------------------------
    class OrthoAlignTool

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            @ip            = Sketchup::InputPoint.new                     # <-- Create input point for detection
            @hover_face    = nil                                          # <-- Track face currently under cursor
            @hover_trans   = nil                                          # <-- Track transformation of nested face
            @cursor_id     = UI::create_cursor("Isocamera", 0, 0)         # <-- Standard Camera cursor (fallback if custom missing)
        end
        # ---------------------------------------------------------------

        # ACTIVATE | Called when tool is activated
        # ------------------------------------------------------------
        def activate
            puts "\n"                                                     # <-- Clean linebreak
            puts "----------------------------------------"                # <-- Print horizontal line
            puts "ORTHO VIEW ALIGN TOOL ACTIVATED"                        # <-- Print activation message
            puts "Hover over any face (nested groups supported)"           # <-- Print instruction
            puts "Click to Align Camera and Zoom Extents"                 # <-- Print instruction
            puts "----------------------------------------"                # <-- Print horizontal line

            Sketchup::set_status_text("Click face to Align View", SB_PROMPT) # <-- Set status bar text
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
        end
        # ---------------------------------------------------------------

        # ON MOUSE MOVE | Track cursor and handle Deep Selection
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            @ip.pick(view, x, y)                                          # <-- Update input point

            # Check if we are hovering over a face
            if @ip.valid? && @ip.face
                @hover_face  = @ip.face                                   # <-- Store reference to the face entity
                @hover_trans = @ip.transformation                         # <-- Store the accumulated transformation (World position)
            else
                @hover_face  = nil                                        # <-- Clear face if hitting void/edge/etc
                @hover_trans = nil                                        # <-- Clear transformation
            end

            view.invalidate                                               # <-- Redraw view to update overlays
        end
        # ---------------------------------------------------------------

        # DRAW | Render Visual Feedback (Green Overlay + Red Border)
        # ------------------------------------------------------------
        def draw(view)
            return unless @hover_face && @hover_trans                     # <-- Exit if no face is targeted

            # 1. Get Vertices of the outer loop
            # We focus on the outer loop for the main visual feedback
            # Using mesh could be more accurate for holes, but loop is faster for UI
            loop_verts = @hover_face.outer_loop.vertices

            # 2. Transform points to World Coordinates
            # This allows the visual to appear correctly even if face is deep in groups
            world_points = loop_verts.map { |v| v.position.transform(@hover_trans) }

            # 3. Draw Transparent Green Overlay
            # RGBA: Red=0, Green=255, Blue=0, Alpha=60 (approx 25% opacity)
            view.drawing_color = Sketchup::Color.new(0, 255, 0, 60)       # <-- Set fill color
            view.draw(GL_POLYGON, world_points)                           # <-- Draw filled polygon

            # 4. Draw Red Border
            view.line_width = 3                                           # <-- Make border thick
            view.drawing_color = Sketchup::Color.new(255, 0, 0)           # <-- Set border color (Red)
            view.draw(GL_LINE_LOOP, world_points)                         # <-- Draw closed loop
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOWN | Execute Camera Alignment
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            if @hover_face && @hover_trans                                # <-- Check if valid target
                align_camera_to_face(view, @hover_face, @hover_trans)     # <-- Perform alignment
            else
                UI.beep                                                   # <-- Audio feedback for miss
            end
        end
        # ---------------------------------------------------------------

        # -----------------------------------------------------------------------------
        # REGION | Core Logic
        # -----------------------------------------------------------------------------

        # FUNCTION | Calculate Vectors and Set Camera
        # ------------------------------------------------------------
        def align_camera_to_face(view, face, trans)
            model = Sketchup.active_model                                 # <-- Get active model

            # 1. Calculate World Vectors
            # We must apply the instance path transformation to get real-world direction
            normal_world = face.normal.transform(trans).normalize         # <-- World Normal
            center_world = face.bounds.center.transform(trans)            # <-- World Center Point

            # 2. Determine Up Vector
            # If normal is looking straight up/down (Z), we must use Y as 'Up' to avoid Gimbal lock
            if normal_world.parallel?(Z_AXIS)
                up_vec = Y_AXIS                                           # <-- Use Y if face is horizontal
            else
                up_vec = Z_AXIS                                           # <-- Use Z for walls/slopes
            end

            # 3. Setup Camera Coordinates
            target = center_world                                         # <-- Camera looks at face center
            eye    = center_world.offset(normal_world, 1000.mm)           # <-- Eye is pushed out along normal
                                                                          # Note: Distance implies direction in ortho, scale handled by zoom

            # 4. Apply Camera Settings
            cam = view.camera                                             # <-- Get current camera
            
            # Disable animation for instant snap (optional, looks snappier)
            # view.animation_duration = 0 
            
            cam.perspective = false                                       # <-- FORCE PARALLEL PROJECTION
            cam.set(eye, target, up_vec)                                  # <-- Set position and orientation

            # 5. Zoom Extents to the Face
            # We pass the world-space points to view.zoom to ensure we zoom to the 
            # specific nested instance, not the generic definition
            world_verts = face.outer_loop.vertices.map { |v| v.position.transform(trans) }
            view.zoom(world_verts)                                        # <-- Zoom to fit the face points

            puts "Aligned Ortho View to Face ID: #{face.entityID}"        # <-- Console log
            
            # Reset tool to select (optional, or keep tool active to hop between faces)
            # model.select_tool(nil) 
        end
        # ---------------------------------------------------------------

    end # End OrthoAlignTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Run Ortho Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind this method in Preferences -> Shortcuts
    # Method name: Na__OrthoViewFace.Na__OrthoViewFace__Run
    # ------------------------------------------------------------
    def self.Na__OrthoViewFace__Run
        model = Sketchup.active_model                                     # <-- Get active model
        return unless model                                               # <-- Exit if no active model

        model.select_tool(OrthoAlignTool.new)                             # <-- Activate the tool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Menu Registration
    # -----------------------------------------------------------------------------

    # FUNCTION | Install Menu and Commands
    # ------------------------------------------------------------
    def self.install_menu_and_commands
        return if @menu_installed                                         # <-- Exit if already installed

        # Create UI command
        cmd = UI::Command.new('NA_OrthoViewFace') do                      # <-- Create command
            Na__OrthoViewFace.Na__OrthoViewFace__Run                      # <-- Run logic
        end
        cmd.tooltip = "Align Ortho View to Face"                          # <-- Tooltip
        cmd.status_bar_text = "Align camera parallel to selected face"    # <-- Status bar
        cmd.menu_text = "Na__OrthoViewFace"                               # <-- Menu text

        # Add to Plugins menu
        UI.menu('Plugins').add_item(cmd)                                  # <-- Add item

        @menu_installed = true                                            # <-- Mark installed
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate for Model
    # ------------------------------------------------------------
    def self.activate_for_model(model)
        install_menu_and_commands                                         # <-- Install commands
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Module

# -----------------------------------------------------------------------------
# FILE LOADED CHECK
# -----------------------------------------------------------------------------
unless file_loaded?(__FILE__)
    Na__OrthoViewFace.activate_for_model(Sketchup.active_model)           # <-- Activate
    file_loaded(__FILE__)                                                 # <-- Mark loaded
end