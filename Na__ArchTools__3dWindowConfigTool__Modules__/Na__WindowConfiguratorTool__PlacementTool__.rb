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
# - Supports 90-degree rotation cycle (0/90/180/270°) via TAB key
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
        NA_ROTATION_KEY   = 9                        # Tab (VK_TAB = 0x09) — no VK_TAB constant in SketchUp Ruby API
        NA_ROTATION_STEPS = [0, 90, 180, 270].freeze # Degrees for each step
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
            @rotation_step      = 0
            @key_tab_held       = false
            @placement_committed = false
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
            if @placement_committed
                DialogManager.na_placement_complete
            else
                DialogManager.na_placement_cancelled
            end
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
        # Tab key advances rotation by 90° (SKEXT-3890 held-flag guard prevents double-fire)
        def onKeyDown(key, repeat, flags, view)
            if key == NA_ROTATION_KEY && !@key_tab_held
                @key_tab_held = true
                na_advance_rotation
                na_update_status_text
                view.invalidate
            end
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Key Up Handler
        # ------------------------------------------------------------
        # Resets Tab held-flag so the next press registers correctly (SKEXT-3890 fix)
        def onKeyUp(key, repeat, flags, view)
            @key_tab_held = false if key == NA_ROTATION_KEY
            false
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
            
            # Flag as committed so deactivate notifies placement_complete (not cancelled)
            @placement_committed = true
            
            # Deactivate tool (triggers deactivate callback)
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
            
            # Draw rotation indicator when not at 0°
            if @rotation_step > 0
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
        
        # FUNCTION | Rotate (public entry point for DialogManager's na_keyboard_tab callback)
        # ------------------------------------------------------------
        # Called by DialogManager when Tab is forwarded from the HTML dialog.
        def na_rotate
            na_advance_rotation
            na_update_status_text
            Sketchup.active_model.active_view.invalidate
        end
        # ---------------------------------------------------------------

        private
        
        # FUNCTION | Advance Rotation by 90° (4-step cycle: 0° → 90° → 180° → 270° → 0°)
        # ------------------------------------------------------------
        def na_advance_rotation
            return unless @instance && @instance.valid?
            center   = @instance.bounds.center
            rotation = Geom::Transformation.rotation(center, Z_AXIS, 90.degrees)
            @instance.transform!(rotation)
            @rotation_step = (@rotation_step + 1) % 4
            DebugTools.na_debug_placement("Rotation: #{NA_ROTATION_STEPS[@rotation_step]}°")
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Update Status Bar Text
        # ------------------------------------------------------------
        def na_update_status_text
            degrees = NA_ROTATION_STEPS[@rotation_step]
            if @cursor_pos
                x_mm = (@cursor_pos.x * 25.4).round
                y_mm = (@cursor_pos.y * 25.4).round
                z_mm = (@cursor_pos.z * 25.4).round
                status = "Click to place window at X:#{x_mm}mm Y:#{y_mm}mm Z:#{z_mm}mm"
                status += " | TAB to rotate [Current: #{degrees}°] | ESC to cancel"
                Sketchup.status_text = status
            else
                Sketchup.status_text = "Move cursor to position window | TAB to rotate [Current: #{degrees}°] | ESC to cancel"
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
