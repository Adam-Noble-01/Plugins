# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - CABINET PLACEMENT TOOL
# =============================================================================
#
# FILE       : Na__AssemblyStudio__PlacementTools__CabinetPlacementTool__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__PlacementTools
# CLASS      : Na__CabinetPlacementTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Places cabinets with the mouse, one click per unit, until Esc.
#              A ghost of the unit (its outline and fronts) follows the cursor:
#                - over an existing cabinet it snaps flush beside it, on the
#                  side of the half the cursor is over, at the same floor
#                  level and facing the same way, so a run is click, click;
#                - over a wall (any upright face) it backs onto the wall,
#                  facing the camera's side, standing on the floor level;
#                - anywhere else it sits at the cursor; Tab turns it 90 deg.
# CREATED    : 29-Oct-2026
#
# NOTHING IS CREATED UNTIL A CLICK
# - The ghost is drawn, not built, so moving the mouse adds no undo steps and
#   Esc leaves nothing behind. Each click asks the host to build one unit
#   (one undo step) from the configuration in the dialog at that moment.
#
# COORDINATES (see the Coordinate Rule)
# - InputPoint positions, the camera and everything drawn are world.
# - A picked cabinet's world placement is the product of the transformations
#   along its pick path: the first entry sits in the active context, so its
#   transformation reads as world; the rest are local to their parents.
# - A face normal is turned to world by the InputPoint's transformation.
# - The frame handed to the host is world and goes to add_instance as it is.
#
# KEYS
# - Tab turns the unit (free placement). Esc finishes. No single-letter keys.
#
# NAMING CONVENTION:
# - Class Na__CabinetPlacementTool; instance helpers prefixed na_*
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
    module Na__PlacementTools

        class Na__CabinetPlacementTool

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

            NA_KEY_TAB          = 9
            NA_INCH_TO_MM       = 25.4
            NA_GRID             = 5.mm
            NA_UPRIGHT_TOLERANCE= 0.15                                           # <-- |normal . up| below this: a wall
            NA_FLOOR_TOLERANCE  = 0.9                                            # <-- normal . up above this: a floor
            NA_ARROW_LENGTH     = 250.mm
            NA_MODE_COLORS = {
                :beside => Sketchup::Color.new(30, 160, 60),
                :wall   => Sketchup::Color.new(230, 130, 0),
                :free   => Sketchup::Color.new(0, 110, 230)
            }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool API - Life Cycle
# -----------------------------------------------------------------------------

            # FUNCTION | Attach the Host (the Cabinetry Dialog Router)
            # ------------------------------------------------------------
            # The host answers: na_placement_ghost, na_cabinet_id_of(instance),
            # na_place_cabinet(transform) and na_placement_ended.
            def initialize(host)
                @host           = host
                @ip             = Sketchup::InputPoint.new
                @frame          = nil
                @rotation_steps = 0
                @tab_held       = false
                @floor_level    = nil                                            # <-- Height (along up) of the last floor hovered
                @placed         = 0
                na_refresh_axes
            end
            # ---------------------------------------------------------------

            def activate
                na_refresh_axes
                @placed = 0
                na_update_status_text
                Sketchup.active_model.active_view.invalidate
            end

            def deactivate(view)
                @host.na_placement_ended if @host.respond_to?(:na_placement_ended)
                view.invalidate
            end

            def resume(view)
                na_update_status_text
                view.invalidate
            end

            # Public: the dialog forwards Tab here while it has the focus.
            def na_rotate
                @rotation_steps = (@rotation_steps + 1) % 4
                na_update_status_text
                Sketchup.active_model.active_view.invalidate
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool API - Mouse and Keys
# -----------------------------------------------------------------------------

            def onMouseMove(_flags, x, y, view)
                @ip.pick(view, x, y)
                return unless @ip.valid?
                @frame = na_resolve_frame(view, x, y)
                na_update_status_text
                view.invalidate
            end

            def onLButtonDown(flags, x, y, view)
                onMouseMove(flags, x, y, view)
                return unless @frame
                transform = Geom::Transformation.axes(@frame[:origin], @frame[:xaxis], @frame[:yaxis], @frame[:zaxis])
                @placed += 1 if @host.na_place_cabinet(transform)
                na_update_status_text
                view.invalidate
            end

            def onKeyDown(key, _repeat, _flags, _view)
                return false unless key == NA_KEY_TAB
                na_rotate unless @tab_held
                @tab_held = true
                true
            end

            def onKeyUp(key, _repeat, _flags, _view)
                @tab_held = false if key == NA_KEY_TAB
                false
            end

            def onCancel(_reason, _view)
                Sketchup.active_model.select_tool(nil)                          # <-- Esc ends the session; deactivate tells the host
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool API - Drawing
# -----------------------------------------------------------------------------

            def draw(view)
                @ip.draw(view) if @ip.valid? && @ip.display?
                ghost = @host.na_placement_ghost
                return unless @frame && ghost

                color = NA_MODE_COLORS[@frame[:mode]] || NA_MODE_COLORS[:free]
                view.drawing_color = color
                view.line_width    = 2
                view.line_stipple  = ''
                view.draw(GL_LINES, na_box_lines(ghost[:bounds]))
                view.line_width    = 1
                ghost[:fronts].each { |front| view.draw(GL_LINE_LOOP, na_front_loop(front)) }
                na_draw_facing_arrow(view, ghost[:bounds])
                na_draw_label(view, ghost)
            end

            def getExtents
                bounds = Geom::BoundingBox.new
                ghost  = @host.na_placement_ghost
                return bounds unless @frame && ghost
                na_box_corners(ghost[:bounds]).each { |point| bounds.add(point) }
                bounds
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Frame Resolution (Beside a Cabinet, On a Wall, Free)
# -----------------------------------------------------------------------------

            # FUNCTION | Where the Next Unit Goes for the Current Cursor
            # ------------------------------------------------------------
            # @return [Hash] { :origin, :xaxis, :yaxis, :zaxis, :mode, :note }
            def na_resolve_frame(view, x, y)
                na_note_floor_level
                beside = na_frame_beside_cabinet(view, x, y)
                return beside if beside
                wall = na_frame_on_wall(view)
                return wall if wall
                na_frame_free
            end

            # FUNCTION | Flush Beside the Cabinet Under the Cursor
            # ------------------------------------------------------------
            # Right half of the picked unit: the new one starts at its right
            # end. Left half: the new one ends at its left end.
            def na_frame_beside_cabinet(view, x, y)
                ghost = @host.na_placement_ghost
                return nil unless ghost
                picker = view.pick_helper
                picker.do_pick(x, y)
                picker.count.times do |index|
                    path = picker.path_at(index) || []
                    path.each_with_index do |entity, depth|
                        next unless entity.is_a?(Sketchup::ComponentInstance)
                        cabinet_id = @host.na_cabinet_id_of(entity)
                        next unless cabinet_id

                        world = na_world_transform(path, depth)
                        local = @ip.position.transform(world.inverse)
                        right_end = entity.definition.bounds.max.x
                        left_end  = entity.definition.bounds.min.x
                        width     = ghost[:bounds][:x1] / NA_INCH_TO_MM
                        on_right  = local.x > (left_end + right_end) / 2.0
                        start_x   = on_right ? right_end : left_end - width
                        return {
                            :origin => Geom::Point3d.new(start_x, 0, 0).transform(world),
                            :xaxis  => world.xaxis.normalize,
                            :yaxis  => world.yaxis.normalize,
                            :zaxis  => world.zaxis.normalize,
                            :mode   => :beside,
                            :note   => "#{on_right ? 'right of' : 'left of'} #{cabinet_id}"
                        }
                    end
                end
                nil
            end

            # FUNCTION | Backed Onto the Upright Face Under the Cursor
            # ------------------------------------------------------------
            def na_frame_on_wall(view)
                face = @ip.face
                return nil unless face && face.valid?
                normal = face.normal.transform(@ip.transformation)
                return nil if normal.length < 1e-6
                normal.normalize!
                return nil unless normal.dot(@up).abs < NA_UPRIGHT_TOLERANCE

                eye    = view.camera.eye
                normal = normal.reverse if normal.dot(eye - @ip.position) < 0     # <-- Face the side the camera is on
                yaxis  = normal.reverse
                yaxis  = yaxis - Geom::Vector3d.new(@up.x * yaxis.dot(@up), @up.y * yaxis.dot(@up), @up.z * yaxis.dot(@up))
                return nil if yaxis.length < 1e-6
                yaxis.normalize!
                xaxis = yaxis.cross(@up).normalize                                # <-- x = y x z keeps the frame right-handed
                {
                    :origin => na_on_floor(@ip.position),
                    :xaxis  => xaxis,
                    :yaxis  => yaxis,
                    :zaxis  => @up,
                    :mode   => :wall,
                    :note   => "on the wall"
                }
            end

            # FUNCTION | At the Cursor, Turned by Tab
            # ------------------------------------------------------------
            def na_frame_free
                turn  = Geom::Transformation.rotation(ORIGIN, @up, @rotation_steps * 90.degrees)
                xaxis = @axes_x.transform(turn).normalize
                yaxis = @up.cross(xaxis).normalize                                # <-- y = z x x
                {
                    :origin => na_snap(@ip.position),
                    :xaxis  => xaxis,
                    :yaxis  => yaxis,
                    :zaxis  => @up,
                    :mode   => :free,
                    :note   => "turned #{@rotation_steps * 90} deg"
                }
            end

# endregion -------------------------------------------------------------------

            private

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

            def na_refresh_axes
                model = Sketchup.active_model
                axes  = model && model.axes
                @axes_transform = axes ? axes.transformation : Geom::Transformation.new
                @axes_x         = axes ? axes.xaxis : X_AXIS
                @up             = axes ? axes.zaxis : Z_AXIS
                @axes_origin    = @axes_transform.origin
            end

            # World placement of the instance at `depth` along a pick path.
            def na_world_transform(path, depth)
                path[0..depth].inject(Geom::Transformation.new) do |product, entity|
                    entity.respond_to?(:transformation) ? product * entity.transformation : product
                end
            end

            # Remember the floor the cursor last passed over (an up-facing
            # face), so a unit backed onto a wall stands on that floor.
            def na_note_floor_level
                face = @ip.face
                return unless face && face.valid?
                normal = face.normal.transform(@ip.transformation)
                return if normal.length < 1e-6
                @floor_level = (@ip.position - @axes_origin).dot(@up) if normal.normalize.dot(@up) > NA_FLOOR_TOLERANCE
            end

            def na_on_floor(point)
                level = @floor_level || 0.0
                point.offset(@up, level - (point - @axes_origin).dot(@up))
            end

            # 5mm grid in the drawing axes' frame.
            def na_snap(point)
                local = point.transform(@axes_transform.inverse)
                snapped = Geom::Point3d.new((local.x / NA_GRID).round * NA_GRID,
                                            (local.y / NA_GRID).round * NA_GRID,
                                            (local.z / NA_GRID).round * NA_GRID)
                snapped.transform(@axes_transform)
            end

            # A unit-frame point (mm) to world.
            def na_world(x_mm, y_mm, z_mm)
                f = @frame
                f[:origin]
                    .offset(f[:xaxis], x_mm / NA_INCH_TO_MM)
                    .offset(f[:yaxis], y_mm / NA_INCH_TO_MM)
                    .offset(f[:zaxis], z_mm / NA_INCH_TO_MM)
            end

            def na_box_corners(b)
                [b[:x0], b[:x1]].product([b[:y0], b[:y1]], [b[:z0], b[:z1]]).map { |x, y, z| na_world(x, y, z) }
            end

            def na_box_lines(b)
                lines = []
                [[b[:y0], b[:z0]], [b[:y1], b[:z0]], [b[:y0], b[:z1]], [b[:y1], b[:z1]]].each { |y, z| lines << na_world(b[:x0], y, z) << na_world(b[:x1], y, z) }
                [[b[:x0], b[:z0]], [b[:x1], b[:z0]], [b[:x0], b[:z1]], [b[:x1], b[:z1]]].each { |x, z| lines << na_world(x, b[:y0], z) << na_world(x, b[:y1], z) }
                [[b[:x0], b[:y0]], [b[:x1], b[:y0]], [b[:x0], b[:y1]], [b[:x1], b[:y1]]].each { |x, y| lines << na_world(x, y, b[:z0]) << na_world(x, y, b[:z1]) }
                lines
            end

            def na_front_loop(front)
                [na_world(front[:x0], front[:y], front[:z0]), na_world(front[:x1], front[:y], front[:z0]),
                 na_world(front[:x1], front[:y], front[:z1]), na_world(front[:x0], front[:y], front[:z1])]
            end

            # An arrow on the floor out of the front, so the facing is plain.
            def na_draw_facing_arrow(view, b)
                mid  = (b[:x0] + b[:x1]) / 2.0
                from = na_world(mid, b[:y0], b[:z0])
                tip  = from.offset(@frame[:yaxis], -NA_ARROW_LENGTH)
                view.line_width = 3
                view.draw(GL_LINES, [from, tip,
                                     tip, tip.offset(@frame[:yaxis], NA_ARROW_LENGTH * 0.3).offset(@frame[:xaxis],  NA_ARROW_LENGTH * 0.2),
                                     tip, tip.offset(@frame[:yaxis], NA_ARROW_LENGTH * 0.3).offset(@frame[:xaxis], -NA_ARROW_LENGTH * 0.2)])
            end

            def na_draw_label(view, ghost)
                screen = view.screen_coords(na_world(ghost[:bounds][:x0], ghost[:bounds][:y0], ghost[:bounds][:z1]))
                view.drawing_color = Sketchup::Color.new(20, 20, 20)
                view.draw_text(Geom::Point3d.new(screen.x, screen.y - 24, 0), "#{ghost[:label]} - #{@frame[:note]}")
            end

            def na_update_status_text
                ghost = @host.na_placement_ghost
                label = ghost ? ghost[:label] : "unit"
                placed = @placed > 0 ? " | #{@placed} placed" : ""
                Sketchup.status_text = "Click to place the #{label}: over a unit to go beside it, over a wall to back onto it | Tab turns | Esc finishes#{placed}"
            end

# endregion -------------------------------------------------------------------

        end

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
