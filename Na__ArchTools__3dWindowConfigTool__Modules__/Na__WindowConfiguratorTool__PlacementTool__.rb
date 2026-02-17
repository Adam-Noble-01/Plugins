# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - PLACEMENT TOOL
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__PlacementTool__.rb
# NAMESPACE  : Na__WindowConfiguratorTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Interactive placement tool for positioning window components
# CREATED    : 2026
# VERSION    : 0.2.3b
#
# DESCRIPTION:
# - Provides crosshair-based placement tool for positioning window components
# - Supports 90-degree rotation toggle via SHIFT key
# - Snaps to 5mm grid for precise placement
# - Shows real-time preview with 3D crosshair and rotation indicator
# - Allows cancellation (ESC) which deletes the component
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__WindowConfiguratorTool__DebugTools__'

module Na__WindowConfiguratorTool

# =============================================================================
# REGION | Placement Tool Class
# =============================================================================

    class Na__WindowPlacementTool
        
        # CONSTANTS
        # ------------------------------------------------------------
        CONSTRAIN_MODIFIER_KEY = COPY_MODIFIER_KEY  # Shift key for rotation toggle
        Z_AXIS = Geom::Vector3d.new(0, 0, 1)
        CROSSHAIR_SIZE = 300.mm
        GRID_SIZE = 5.mm  # Snap grid size
        
        # FUNCTION | Initialize Placement Tool
        # ------------------------------------------------------------
        # @param instance [Sketchup::ComponentInstance] The window component to place
        def initialize(instance)
            @instance = instance
            @ip = Sketchup::InputPoint.new
            @cursor_pos = nil
            @crosshair_size = CROSSHAIR_SIZE
            @rotated = false
            @original_transform = instance.transformation.clone
            @last_position = instance.bounds.min
            
            DebugTools.na_debug_placement("Placement tool initialized")
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Tool Activated
        # ------------------------------------------------------------
        def activate
            DebugTools.na_debug_placement("Placement tool activated")
            na_update_status_text
            Sketchup.active_model.active_view.invalidate
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Tool Deactivated
        # ------------------------------------------------------------
        def deactivate(view)
            DebugTools.na_debug_placement("Placement tool deactivated")
            view.invalidate
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Mouse Move Handler
        # ------------------------------------------------------------
        # Updates window position as cursor moves, snapped to grid
        def onMouseMove(flags, x, y, view)
            @ip.pick(view, x, y)
            return unless @ip.valid?
            
            # Snap cursor position to 5mm grid
            @cursor_pos = na_round_to_grid(@ip.position)
            
            if @instance && @instance.valid?
                # Calculate movement delta from current instance position to cursor
                current_min = @instance.bounds.min
                delta = @cursor_pos - current_min
                
                # Apply translation to move instance to cursor position
                translation = Geom::Transformation.new(delta)
                @instance.transform!(translation)
                
                # Update last position
                @last_position = @cursor_pos
            end
            
            # Update status text with current position
            na_update_status_text
            
            view.invalidate
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Key Down Handler
        # ------------------------------------------------------------
        # SHIFT key toggles 90-degree rotation
        def onKeyDown(key, repeat, flags, view)
            if key == CONSTRAIN_MODIFIER_KEY && repeat == 1
                na_toggle_rotation
                na_update_status_text
                view.invalidate
            end
            false  # Return false to not block VCB
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Left Mouse Button Down Handler
        # ------------------------------------------------------------
        # Commits the placement at the current position
        def onLButtonDown(flags, x, y, view)
            @ip.pick(view, x, y)
            return unless @ip.valid?
            
            # Snap final position to 5mm grid
            final_pt = na_round_to_grid(@ip.position)
            
            # Move instance to final position if cursor moved since last move
            if @instance && @instance.valid?
                current_min = @instance.bounds.min
                delta = final_pt - current_min
                if delta.length > 0.001
                    translation = Geom::Transformation.new(delta)
                    @instance.transform!(translation)
                end
            end
            
            DebugTools.na_debug_placement("Window placed at: #{final_pt}")
            
            # Commit the placement
            Sketchup.active_model.selection.clear
            Sketchup.active_model.selection.add(@instance) if @instance && @instance.valid?
            
            # Deactivate tool
            Sketchup.active_model.select_tool(nil)
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Cancel Handler
        # ------------------------------------------------------------
        # ESC key cancels placement and deletes the component
        def onCancel(reason, view)
            DebugTools.na_debug_placement("Placement cancelled")
            
            # Delete the instance if cancelled
            if @instance && @instance.valid?
                @instance.erase!
            end
            
            view.invalidate
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Draw Handler
        # ------------------------------------------------------------
        # Draws 3D crosshair and rotation indicator
        def draw(view)
            return unless @cursor_pos
            
            # Draw 3D crosshair
            view.line_width = 2
            
            # X axis (red)
            view.drawing_color = Sketchup::Color.new(255, 0, 0)
            view.draw_line(@cursor_pos.offset(X_AXIS, -@crosshair_size), @cursor_pos.offset(X_AXIS, @crosshair_size))
            
            # Y axis (green)
            view.drawing_color = Sketchup::Color.new(0, 255, 0)
            view.draw_line(@cursor_pos.offset(Y_AXIS, -@crosshair_size), @cursor_pos.offset(Y_AXIS, @crosshair_size))
            
            # Z axis (blue)
            view.drawing_color = Sketchup::Color.new(0, 0, 255)
            view.draw_line(@cursor_pos, @cursor_pos.offset(Z_AXIS, @crosshair_size))
            
            # Draw rotation indicator if rotated
            if @rotated
                view.drawing_color = Sketchup::Color.new(255, 165, 0)  # Orange
                view.line_width = 3
                # Draw small arc to indicate rotation
                arc_radius = @crosshair_size * 0.3
                segments = 12
                arc_points = []
                (0..segments).each do |i|
                    angle = (i.to_f / segments) * 90.degrees
                    pt = Geom::Point3d.new(
                        @cursor_pos.x + arc_radius * Math.cos(angle),
                        @cursor_pos.y + arc_radius * Math.sin(angle),
                        @cursor_pos.z
                    )
                    arc_points << pt
                end
                view.draw_polyline(arc_points)
            end
        end
        # ---------------------------------------------------------------
        
        private
        
        # FUNCTION | Toggle 90-Degree Rotation
        # ------------------------------------------------------------
        def na_toggle_rotation
            return unless @instance && @instance.valid?
            
            # Get center of instance for rotation pivot
            center = @instance.bounds.center
            
            # Calculate rotation angle (toggle between +90 and -90)
            angle = @rotated ? -90.degrees : 90.degrees
            
            # Create and apply rotation transformation
            rotation = Geom::Transformation.rotation(center, Z_AXIS, angle)
            @instance.transform!(rotation)
            
            # Toggle rotation state
            @rotated = !@rotated
            
            DebugTools.na_debug_placement("Rotation toggled: #{@rotated ? '90°' : '0°'}")
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Update Status Bar Text
        # ------------------------------------------------------------
        def na_update_status_text
            if @cursor_pos
                # Show coordinates in mm (snapped to 5mm grid)
                x_mm = (@cursor_pos.x * 25.4).round
                y_mm = (@cursor_pos.y * 25.4).round
                z_mm = (@cursor_pos.z * 25.4).round
                rotation_angle = @rotated ? 90 : 0
                
                status = "Click to place window at X:#{x_mm}mm Y:#{y_mm}mm Z:#{z_mm}mm"
                status += " | Press SHIFT to rotate 90° [Current: #{rotation_angle}°] | ESC to cancel"
                Sketchup.status_text = status
            else
                Sketchup.status_text = "Move cursor to position window | Press SHIFT to rotate 90° | ESC to cancel"
            end
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Round Point to Grid
        # ------------------------------------------------------------
        # @param point [Geom::Point3d] Point to round
        # @return [Geom::Point3d] Point snapped to 5mm grid
        def na_round_to_grid(point)
            Geom::Point3d.new(
                (point.x / GRID_SIZE).round * GRID_SIZE,
                (point.y / GRID_SIZE).round * GRID_SIZE,
                (point.z / GRID_SIZE).round * GRID_SIZE
            )
        end
        # ---------------------------------------------------------------
        
    end

# endregion ===================================================================

end # module Na__WindowConfiguratorTool

# =============================================================================
# END OF FILE
# =============================================================================
