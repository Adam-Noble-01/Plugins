# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW PLACEMENT TOOL
# =============================================================================
#
# FILE       : Na__AssemblyStudio__PlacementTools__WindowPlacementTool__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__PlacementTools
# CLASS      : Na__WindowPlacementTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Interactive placement tool for positioning a freshly-created
#              window component. 5mm grid snap, Tab cycles 90deg rotations,
#              ESC cancels and erases the instance.
#
# REFACTOR NOTES (v2 / EASP)
# - Explicit require_relative on AppCore::DialogManager (was relying on load
#   order via Main).
# - Diagnostics routed through unified DebugTools.
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__DialogManager__'

module Na__AssemblyStudio
    module Na__PlacementTools

        class Na__WindowPlacementTool

            DebugTools    = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
            DialogManager = Na__AssemblyStudio::Na__AppCore::Na__DialogManager

            NA_ROTATION_KEY   = 9
            NA_ROTATION_STEPS = [0, 90, 180, 270].freeze
            NA_Z_AXIS         = Geom::Vector3d.new(0, 0, 1)
            NA_CROSSHAIR_SIZE = 300.mm
            NA_GRID_SIZE      = 5.mm

            def initialize(instance)
                @instance            = instance
                @ip                  = Sketchup::InputPoint.new
                @cursor_pos          = nil
                @rotation_step       = 0
                @key_tab_held        = false
                @placement_committed = false
                @original_transform  = instance.transformation.clone
                @last_position       = instance.bounds.min
                DebugTools.na_debug_placement("Placement tool initialized")
            end

            def activate
                DebugTools.na_debug_placement("Placement tool activated")
                na_update_status_text
                Sketchup.active_model.active_view.invalidate
            end

            def deactivate(view)
                DebugTools.na_debug_placement("Placement tool deactivated")
                if @placement_committed
                    DialogManager.respond_to?(:na_placement_complete) ? DialogManager.na_placement_complete : na_signal_dialog(:complete)
                else
                    DialogManager.respond_to?(:na_placement_cancelled) ? DialogManager.na_placement_cancelled : na_signal_dialog(:cancel)
                end
                view.invalidate
            end

            def onMouseMove(_flags, x, y, view)
                @ip.pick(view, x, y)
                return unless @ip.valid?
                @cursor_pos = na_round_to_grid(@ip.position)

                if @instance && @instance.valid?
                    delta = @cursor_pos - @instance.bounds.min
                    @instance.transform!(Geom::Transformation.new(delta))
                    @last_position = @cursor_pos
                end
                na_update_status_text
                view.invalidate
            end

            def onKeyDown(key, _repeat, _flags, view)
                if key == NA_ROTATION_KEY && !@key_tab_held
                    @key_tab_held = true
                    na_advance_rotation
                    na_update_status_text
                    view.invalidate
                end
                false
            end

            def onKeyUp(key, _repeat, _flags, _view)
                @key_tab_held = false if key == NA_ROTATION_KEY
                false
            end

            def onLButtonDown(_flags, x, y, _view)
                @ip.pick(_view, x, y)
                return unless @ip.valid?
                final_pt = na_round_to_grid(@ip.position)

                if @instance && @instance.valid?
                    delta = final_pt - @instance.bounds.min
                    @instance.transform!(Geom::Transformation.new(delta)) if delta.length > 0.001
                end

                DebugTools.na_debug_placement("Window placed at: #{final_pt}")
                Sketchup.active_model.selection.clear
                Sketchup.active_model.selection.add(@instance) if @instance && @instance.valid?
                @placement_committed = true
                Sketchup.active_model.select_tool(nil)
            end

            def onCancel(_reason, view)
                DebugTools.na_debug_placement("Placement cancelled")
                @instance.erase! if @instance && @instance.valid?
                view.invalidate
            end

            def draw(view)
                return unless @cursor_pos
                view.line_width = 2
                view.drawing_color = Sketchup::Color.new(255, 0, 0)
                view.draw_line(@cursor_pos.offset(X_AXIS, -NA_CROSSHAIR_SIZE), @cursor_pos.offset(X_AXIS, NA_CROSSHAIR_SIZE))
                view.drawing_color = Sketchup::Color.new(0, 255, 0)
                view.draw_line(@cursor_pos.offset(Y_AXIS, -NA_CROSSHAIR_SIZE), @cursor_pos.offset(Y_AXIS, NA_CROSSHAIR_SIZE))
                view.drawing_color = Sketchup::Color.new(0, 0, 255)
                view.draw_line(@cursor_pos, @cursor_pos.offset(NA_Z_AXIS, NA_CROSSHAIR_SIZE))

                if @rotation_step > 0
                    view.drawing_color = Sketchup::Color.new(255, 165, 0)
                    view.line_width = 3
                    arc_radius = NA_CROSSHAIR_SIZE * 0.3
                    segments = 12
                    arc_points = []
                    (0..segments).each do |i|
                        angle = (i.to_f / segments) * 90.degrees
                        arc_points << Geom::Point3d.new(
                            @cursor_pos.x + arc_radius * Math.cos(angle),
                            @cursor_pos.y + arc_radius * Math.sin(angle),
                            @cursor_pos.z
                        )
                    end
                    view.draw_polyline(arc_points)
                end
            end

            # Public: called by DialogManager via the JS Tab interceptor
            def na_rotate
                na_advance_rotation
                na_update_status_text
                Sketchup.active_model.active_view.invalidate
            end

            private

            def na_advance_rotation
                return unless @instance && @instance.valid?
                center   = @instance.bounds.center
                rotation = Geom::Transformation.rotation(center, NA_Z_AXIS, 90.degrees)
                @instance.transform!(rotation)
                @rotation_step = (@rotation_step + 1) % 4
                DebugTools.na_debug_placement("Rotation: #{NA_ROTATION_STEPS[@rotation_step]} degrees")
            end

            def na_update_status_text
                degrees = NA_ROTATION_STEPS[@rotation_step]
                if @cursor_pos
                    x_mm = (@cursor_pos.x * 25.4).round
                    y_mm = (@cursor_pos.y * 25.4).round
                    z_mm = (@cursor_pos.z * 25.4).round
                    Sketchup.status_text =
                        "Click to place window at X:#{x_mm}mm Y:#{y_mm}mm Z:#{z_mm}mm | TAB to rotate [Current: #{degrees}deg] | ESC to cancel"
                else
                    Sketchup.status_text =
                        "Move cursor to position window | TAB to rotate [Current: #{degrees}deg] | ESC to cancel"
                end
            end

            def na_round_to_grid(point)
                Geom::Point3d.new(
                    (point.x / NA_GRID_SIZE).round * NA_GRID_SIZE,
                    (point.y / NA_GRID_SIZE).round * NA_GRID_SIZE,
                    (point.z / NA_GRID_SIZE).round * NA_GRID_SIZE
                )
            end

            def na_signal_dialog(_kind)
                # Optional fallback when DialogManager doesn't expose the new
                # placement_complete / placement_cancelled methods (legacy compat).
            end

        end

    end
end
