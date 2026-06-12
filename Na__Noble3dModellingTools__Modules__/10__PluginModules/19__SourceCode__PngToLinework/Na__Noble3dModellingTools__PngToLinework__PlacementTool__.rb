# =============================================================================
# NA NOBLE3D MODELLING TOOLS - PNG TO LINEWORK - PLACEMENT TOOL
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__PngToLinework__PlacementTool__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__PngToLinework
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Interactive crosshair placement tool for the traced linework
#              component, snapping to a 5mm grid (Insert Primitives pattern).
# CREATED    : 2026
#
# DESIGN NOTES:
# - The component instance arrives inside an OPEN model operation started by
#   the GeometryBuilder. Mouse moves reposition the instance with move! which
#   records no undo steps; the click commits the whole create-and-place flow
#   as one undo step, and ESC aborts it (erasing the component cleanly).
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__PngToLinework

        # CLASS | Crosshair Placement Tool with 5mm Grid Snap
        # ------------------------------------------------------------
        class Na__PngToLinework__PlacementTool

            NA_GRID_SIZE_MM      = 5.0
            NA_CROSSHAIR_SIZE    = 300.mm
            NA_CROSSHAIR_COLOR   = Sketchup::Color.new(0, 100, 255)
            NA_MM_PER_INCH       = 25.4

            def initialize(instance)
                @na_instance   = instance
                @na_ip         = Sketchup::InputPoint.new
                @na_cursor_pos = nil
                @na_placed     = false
            end

            def activate
                Sketchup.status_text = 'PNG To Linework | Click to place the linework (snaps to 5mm grid). ESC to cancel.'
            end

            def deactivate(view)
                na_abort_unless_placed
                view.invalidate if view
            end

            def onCancel(_reason, view)
                na_abort_unless_placed
                Sketchup.active_model.select_tool(nil)
                view.invalidate if view
            end

            def onMouseMove(_flags, x, y, view)
                @na_ip.pick(view, x, y)
                return unless @na_ip.valid?

                @na_cursor_pos = na_round_point_to_grid(@na_ip.position)
                na_move_instance_to(@na_cursor_pos)
                view.invalidate
            end

            def onLButtonDown(_flags, x, y, view)
                @na_ip.pick(view, x, y)
                return unless @na_ip.valid?

                final_point = na_round_point_to_grid(@na_ip.position)
                na_move_instance_to(final_point)

                model = Sketchup.active_model
                model.commit_operation
                @na_placed = true

                model.selection.clear
                model.selection.add(@na_instance) if @na_instance && @na_instance.valid?
                Sketchup.status_text = 'PNG linework placed.'
                model.select_tool(nil)
                view.invalidate
            end

            def draw(view)
                return unless @na_cursor_pos

                @na_ip.draw(view)
                na_draw_crosshair(view, @na_cursor_pos)
            end

            # HELPER FUNCTION | Snap a Point to the Nearest 5mm Grid Node
            # ------------------------------------------------------------
            def na_round_point_to_grid(point)
                snapped = [point.x, point.y, point.z].map do |axis_value|
                    axis_mm = axis_value * NA_MM_PER_INCH
                    ((axis_mm / NA_GRID_SIZE_MM).round * NA_GRID_SIZE_MM) / NA_MM_PER_INCH
                end
                Geom::Point3d.new(*snapped)
            end
            # ------------------------------------------------------------

            # HELPER FUNCTION | Move the Instance Origin Without Undo Recording
            # ------------------------------------------------------------
            def na_move_instance_to(point)
                return unless @na_instance && @na_instance.valid?

                @na_instance.move!(Geom::Transformation.translation(Geom::Vector3d.new(point.x, point.y, point.z)))
            end
            # ------------------------------------------------------------

            # HELPER FUNCTION | Draw the Six-Arm Blue Crosshair at the Cursor
            # ------------------------------------------------------------
            def na_draw_crosshair(view, cursor_pos)
                cx = cursor_pos.x
                cy = cursor_pos.y
                cz = cursor_pos.z

                view.line_stipple  = ''
                view.line_width    = 2
                view.drawing_color = NA_CROSSHAIR_COLOR

                view.draw_line(cursor_pos, Geom::Point3d.new(cx + NA_CROSSHAIR_SIZE, cy, cz))
                view.draw_line(cursor_pos, Geom::Point3d.new(cx - NA_CROSSHAIR_SIZE, cy, cz))
                view.draw_line(cursor_pos, Geom::Point3d.new(cx, cy + NA_CROSSHAIR_SIZE, cz))
                view.draw_line(cursor_pos, Geom::Point3d.new(cx, cy - NA_CROSSHAIR_SIZE, cz))
                view.draw_line(cursor_pos, Geom::Point3d.new(cx, cy, cz + NA_CROSSHAIR_SIZE))
                view.draw_line(cursor_pos, Geom::Point3d.new(cx, cy, cz - NA_CROSSHAIR_SIZE))
            end
            # ------------------------------------------------------------

            # HELPER FUNCTION | Abort the Open Operation if Placement Never Happened
            # ------------------------------------------------------------
            def na_abort_unless_placed
                return if @na_placed

                Sketchup.active_model.abort_operation                          # <-- Removes the unplaced component cleanly
                @na_placed = true                                              # <-- Guard against double abort from deactivate + cancel
                Sketchup.status_text = 'PNG linework placement cancelled.'
            rescue StandardError
                nil
            end
            # ------------------------------------------------------------

        end # class Na__PngToLinework__PlacementTool
        # ------------------------------------------------------------

    end # module Na__PngToLinework
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
