# -----------------------------------------------------------------------------
# REGION | Camera Helper Overlays - Rule of Thirds Grid
# -----------------------------------------------------------------------------
# Persistent overlay showing composition grid and power points
# Toggle on/off via hotkey or menu command
# -----------------------------------------------------------------------------

require 'sketchup.rb'
require 'extensions.rb'

module Na__CameraHelperOverlays
    
    # -----------------------------------------------------------------------------
    # REGION | Overlay Class
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Rule of Thirds Overlay Class
    # ------------------------------------------------------------
    # Subclass Sketchup::Overlay to create persistent drawing layer
    # Official API method for SketchUp 2024/2025+ to ensure graphics survive tool changes
    # ------------------------------------------------------------
    class ThirdsOverlay < Sketchup::Overlay
        
        # INITIALIZE | Create Overlay with Unique Identifier
        # ------------------------------------------------------------
        def initialize
            # unique_id: Unique identifier for the overlay (extension_id.overlay_id)
            # name: Display name shown in Overlays panel in SketchUp UI
            super('na_camerahelper.rule_of_thirds', 'Camera Composition Helper')  # <-- Create overlay with unique ID
        end
        # ---------------------------------------------------------------
        
        # DRAW | Render Grid and Power Points on Viewport
        # ------------------------------------------------------------
        # Called automatically by SketchUp engine whenever viewport refreshes
        # ------------------------------------------------------------
        def draw(view)
            # Get viewport dimensions (logical pixel dimensions)
            w = view.vpwidth                                              # <-- Viewport width in pixels
            h = view.vpheight                                             # <-- Viewport height in pixels
            
            # Calculate thirds for grid positioning
            x_third = w / 3.0                                             # <-- One-third viewport width
            y_third = h / 3.0                                             # <-- One-third viewport height
            
            # Define points for grid lines (Z-coordinate ignored in 2D but required by Point3d)
            points = [                                                     # <-- Array of line endpoints
                # Vertical Line 1 (Left)
                Geom::Point3d.new(x_third, 0, 0),                         # <-- Left vertical top
                Geom::Point3d.new(x_third, h, 0),                         # <-- Left vertical bottom
                
                # Vertical Line 2 (Right)
                Geom::Point3d.new(x_third * 2, 0, 0),                     # <-- Right vertical top
                Geom::Point3d.new(x_third * 2, h, 0),                     # <-- Right vertical bottom
                
                # Horizontal Line 1 (Top)
                Geom::Point3d.new(0, y_third, 0),                         # <-- Top horizontal left
                Geom::Point3d.new(w, y_third, 0),                         # <-- Top horizontal right
                
                # Horizontal Line 2 (Bottom)
                Geom::Point3d.new(0, y_third * 2, 0),                     # <-- Bottom horizontal left
                Geom::Point3d.new(w, y_third * 2, 0)                      # <-- Bottom horizontal right
            ]
            
            # Set graphic styles for grid lines
            view.drawing_color = Sketchup::Color.new(255, 0, 0, 200)      # <-- Red with transparency
            view.line_width = 2                                           # <-- Line width 2 pixels
            
            # Draw main grid using GL_LINES (unconnected lines between pairs of points)
            view.draw2d(GL_LINES, points)                                 # <-- Draw grid lines in 2D screen space
            
            # Draw power points (intersection points where thirds cross)
            power_points = [                                              # <-- Array of grid intersection points
                Geom::Point3d.new(x_third, y_third, 0),                   # <-- Top-left intersection
                Geom::Point3d.new(x_third * 2, y_third, 0),               # <-- Top-right intersection
                Geom::Point3d.new(x_third, y_third * 2, 0),               # <-- Bottom-left intersection
                Geom::Point3d.new(x_third * 2, y_third * 2, 0)            # <-- Bottom-right intersection
            ]
            
            # Set graphic styles for power points
            view.line_width = 6                                           # <-- Point size 6 pixels
            view.drawing_color = Sketchup::Color.new(255, 0, 0, 255)      # <-- Red fully opaque
            view.draw2d(GL_POINTS, power_points)                          # <-- Draw power point dots
        end
        # ---------------------------------------------------------------
        
    end # End ThirdsOverlay class
    
    # endregion -------------------------------------------------------------------
    
    
    # -----------------------------------------------------------------------------
    # REGION | Toggle Management
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Check if Overlay is Currently Active
    # ------------------------------------------------------------
    def self.overlay_active?
        model = Sketchup.active_model                                     # <-- Get active model
        return false unless model                                         # <-- Exit if no active model
        
        overlays = model.overlays                                         # <-- Get overlay collection
        overlay_id = 'na_camerahelper.rule_of_thirds'                     # <-- Unique overlay identifier
        
        # Search for overlay in collection
        existing = overlays.find { |o| o.overlay_id == overlay_id }      # <-- Check if overlay exists
        !existing.nil?                                                    # <-- Return true if found
    end
    # ---------------------------------------------------------------
    
    # FUNCTION | Add Overlay to Model
    # ------------------------------------------------------------
    def self.show_overlay
        model = Sketchup.active_model                                     # <-- Get active model
        return unless model                                               # <-- Exit if no active model
        
        overlays = model.overlays                                         # <-- Get overlay collection
        overlay_id = 'na_camerahelper.rule_of_thirds'                     # <-- Unique overlay identifier
        
        # Check if overlay already exists
        existing = overlays.find { |o| o.overlay_id == overlay_id }      # <-- Search for existing overlay
        
        unless existing                                                   # <-- Only add if doesn't exist
            overlay = ThirdsOverlay.new                                   # <-- Create new overlay instance
            overlays.add(overlay)                                         # <-- Add to overlay collection
        end                                                               # <-- End existence check
    end
    # ---------------------------------------------------------------
    
    # FUNCTION | Remove Overlay from Model
    # ------------------------------------------------------------
    def self.hide_overlay
        model = Sketchup.active_model                                     # <-- Get active model
        return unless model                                               # <-- Exit if no active model
        
        overlays = model.overlays                                         # <-- Get overlay collection
        overlay_id = 'na_camerahelper.rule_of_thirds'                     # <-- Unique overlay identifier
        
        # Find and remove overlay
        existing = overlays.find { |o| o.overlay_id == overlay_id }      # <-- Search for existing overlay
        
        if existing                                                       # <-- Check if overlay exists
            overlays.remove(existing)                                     # <-- Remove from collection
        end                                                               # <-- End existence check
    end
    # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    
    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------
    
    # FUNCTION | Toggle Camera Overlay (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind this method in Preferences → Shortcuts to activate/deactivate overlay
    # Method name: Na__CameraHelperOverlays.Na__CameraHelperOverlays__ToggleOverlay
    # ------------------------------------------------------------
    def self.Na__CameraHelperOverlays__ToggleOverlay
        model = Sketchup.active_model                                     # <-- Get active model
        return unless model                                               # <-- Exit if no active model
        
        # Check current state and toggle
        if overlay_active?                                                # <-- Check if overlay is currently active
            hide_overlay                                                  # <-- Remove overlay from view
            
            # Print disabled message
            puts "\n"                                                     # <-- Clean linebreak
            puts "----------------------------------------"                # <-- Print horizontal line
            puts "CAMERA OVERLAY DISABLED"                                # <-- Print disabled message
            puts "----------------------------------------"                # <-- Print horizontal line
        else                                                              # <-- Overlay is not active
            show_overlay                                                  # <-- Add overlay to view
            
            # Print enabled message
            puts "\n"                                                     # <-- Clean linebreak
            puts "----------------------------------------"                # <-- Print horizontal line
            puts "CAMERA OVERLAY ENABLED"                                 # <-- Print enabled message
            puts "----------------------------------------"                # <-- Print horizontal line
        end                                                               # <-- End state check
        
        model.active_view.invalidate                                      # <-- Refresh viewport to update overlay
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
        
        # Create UI command for camera overlay toggle
        cmd = UI::Command.new('Na__ToggleCameraOverlay') do                # <-- Create command with label
            Na__CameraHelperOverlays.Na__CameraHelperOverlays__ToggleOverlay  # <-- Call toggle method
        end
        cmd.tooltip = "Toggle Camera Composition Helper"                  # <-- Set tooltip
        cmd.status_bar_text = "Toggle rule of thirds overlay on/off"     # <-- Set status bar text
        
        # Add command to Plugins menu
        UI.menu('Plugins').add_item(cmd)                                  # <-- Add to Plugins menu
        
        @menu_installed = true                                            # <-- Mark as installed
    end
    # ---------------------------------------------------------------
    
    # FUNCTION | Activate for Model
    # ------------------------------------------------------------
    def self.activate_for_model(model)
        install_menu_and_commands                                         # <-- Install menu and commands
        # Overlay is OFF by default - must be toggled on by user via hotkey or menu
    end
    # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
end # End Na__CameraHelperOverlays module

# -----------------------------------------------------------------------------
# FILE LOADED CHECK | Prevent re-execution on reload
# -----------------------------------------------------------------------------
unless file_loaded?(__FILE__)
    # Activate immediately for the current model
    Na__CameraHelperOverlays.activate_for_model(Sketchup.active_model)   # <-- Activate menu and overlay registration
    
    file_loaded(__FILE__)                                                 # <-- Mark file as loaded
end

# -----------------------------------------------------------------------------
# CONSOLE EXECUTION | Uncomment to run directly in Ruby Console
# -----------------------------------------------------------------------------
# Na__CameraHelperOverlays.Na__CameraHelperOverlays__ToggleOverlay
