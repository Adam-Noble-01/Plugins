# =============================================================================
# NA POINT CLOUD VIEWER - TRANSFORM - MOVE TOOL (GIMBAL)
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Transform__MoveTool__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__Placement::Na__CloudMoveTool
# PURPOSE    : Moves the cloud along the model's red, green or blue axis with
#              a three-arrow gimbal at the gimbal point (the centre of the
#              cloud's box, or a point picked with Set Gimbal Point; it moves
#              with the cloud):
#                - hover an arrow to pick it, then press-drag, or click /
#                  move / click
#                - moves snap to a step (5 mm by default; Transform tab)
#                - type a distance + Enter: along the arrow is positive; works
#                  during a move and straight after one (re-types it)
#                - Esc cancels the move in progress
#                - Set Gimbal Point: the next click (with SketchUp's inference,
#                  so it snaps to vertices and edges) places the gimbal
#              Only works while the position is unlocked. Creates no geometry.
#
# DRAWING: the gimbal is drawn by the OVERLAY after the cloud image (see
#   RenderController), so the points can never cover it. Arrows keep a fixed
#   size on screen at any zoom.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__Placement

    # -------------------------------------------------------------------------
    # REGION | Shared Drawing Helpers (Move + Rotate)
    # -------------------------------------------------------------------------

        NA_AXES = [
            { 'id' => 'x', 'label' => 'Red',   'vector' => [1.0, 0.0, 0.0] },
            { 'id' => 'y', 'label' => 'Green', 'vector' => [0.0, 1.0, 0.0] },
            { 'id' => 'z', 'label' => 'Blue',  'vector' => [0.0, 0.0, 1.0] }
        ].freeze unless defined?(NA_AXES)

        NA_AXIS_COLOURS = {
            'x' => Sketchup::Color.new(220, 40, 40),
            'y' => Sketchup::Color.new(30, 160, 60),
            'z' => Sketchup::Color.new(40, 90, 235)
        }.freeze unless defined?(NA_AXIS_COLOURS)
        NA_HOT_COLOUR    = Sketchup::Color.new(255, 196, 0)   unless defined?(NA_HOT_COLOUR)
        NA_GUIDE_COLOUR  = Sketchup::Color.new(90, 90, 90)    unless defined?(NA_GUIDE_COLOUR)
        NA_WHITE_COLOUR  = Sketchup::Color.new(255, 255, 255) unless defined?(NA_WHITE_COLOUR)
        NA_DARK_COLOUR   = Sketchup::Color.new(30, 30, 30)    unless defined?(NA_DARK_COLOUR)
        NA_INFERENCE_COLOUR = Sketchup::Color.new(0, 190, 80) unless defined?(NA_INFERENCE_COLOUR)
        NA_HEAD_PX       = 14.0
        NA_HEAD_HALF_PX  = 6.0

        def self.na_axis(axis_id)
            NA_AXES.find { |axis| axis['id'] == axis_id.to_s }
        end

        def self.na_gimbal_px
            Na__ConfigLoader.Na__Config__GetOr(90, 'transform', 'gimbalPx').to_f
        end

        def self.na_protractor_px
            Na__ConfigLoader.Na__Config__GetOr(80, 'transform', 'protractorPx').to_f
        end

        def self.na_point(coords)
            Geom::Point3d.new(*coords)
        end

        # Parameter along the line `origin + s * axis` closest to the mouse ray,
        # so a grabbed arrow follows the cursor from any view angle.
        def self.na_axis_param(origin, axis, x, y, view)
            ray_origin, direction = view.pickray(x, y)
            p = ray_origin.to_a
            d = direction.to_a
            w0 = (0..2).map { |i| origin[i] - p[i] }
            b  = (0..2).sum { |i| axis[i] * d[i] }
            c  = (0..2).sum { |i| d[i] * d[i] }
            dd = (0..2).sum { |i| axis[i] * w0[i] }
            e  = (0..2).sum { |i| d[i] * w0[i] }
            denom = c - b * b
            return nil if denom.abs < 1e-9          # looking straight down the axis
            (b * e - c * dd) / denom
        end

        def self.na_snap_distance(distance)
            snap = self.Na__Placement__SnapSettings
            step = snap['moveInches']
            return distance unless snap['moveEnabled'] && step > 1e-9
            (distance / step).round * step
        end

        def self.na_segment_distance(x, y, a, b)
            dx = b[0] - a[0]
            dy = b[1] - a[1]
            length_sq = dx * dx + dy * dy
            t = length_sq < 1e-9 ? 0.0 : [[((x - a[0]) * dx + (y - a[1]) * dy) / length_sq, 0.0].max, 1.0].min
            Math.hypot(x - (a[0] + t * dx), y - (a[1] + t * dy))
        end

        def self.na_square2d(view, centre, half, fill, outline)
            corners = [[-half, -half], [half, -half], [half, half], [-half, half]].map do |dx, dy|
                Geom::Point3d.new(centre[0] + dx, centre[1] + dy, 0)
            end
            view.drawing_color = fill
            view.draw2d(GL_QUADS, corners)
            view.line_width = 1
            view.drawing_color = outline
            view.draw2d(GL_LINE_LOOP, corners)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Gimbal Geometry + Drawing
    # -------------------------------------------------------------------------

        # Screen-space arrows for the gimbal at `origin` (model inches):
        # [{ 'id', 'o' => [x, y], 'tip' => [x, y], 'end' => [x, y] }], or nil when
        # the origin is behind the camera.
        def self.na_gimbal_screen(view, origin)
            point = self.na_point(origin)
            return nil unless Na__ClipBox.na_in_front?(view, point)
            o = view.screen_coords(point)
            length = view.pixels_to_model(self.na_gimbal_px, point).to_f
            NA_AXES.map do |axis|
                tip_point = self.na_point((0..2).map { |i| origin[i] + axis['vector'][i] * length })
                tip = view.screen_coords(tip_point)
                dx = tip.x - o.x
                dy = tip.y - o.y
                l = Math.hypot(dx, dy)
                head = l > 1e-6 ? [tip.x + dx / l * NA_HEAD_PX, tip.y + dy / l * NA_HEAD_PX] : [tip.x, tip.y]
                { 'id' => axis['id'], 'o' => [o.x, o.y], 'tip' => [tip.x, tip.y], 'end' => head, 'length' => l }
            end
        end

        def self.na_draw_gimbal(view, session, tool)
            placement = session.placement
            return unless placement
            drag = tool.na_drag
            if drag
                self.na_draw_axis_guide(view, session, drag['origin'], drag['axis'])
            end
            pick = tool.na_pick_marker
            if pick
                point = self.na_point(pick['point'])
                if Na__ClipBox.na_in_front?(view, point)
                    screen = view.screen_coords(point)
                    fill = pick['snapped'] ? NA_INFERENCE_COLOUR : NA_WHITE_COLOUR
                    self.na_square2d(view, [screen.x, screen.y], 5.0, fill, NA_DARK_COLOUR)
                end
            end
            arrows = self.na_gimbal_screen(view, self.Na__Placement__GimbalModel(session))
            return unless arrows
            hot = tool.na_hot_axis
            arrows.each do |arrow|
                colour = arrow['id'] == hot ? NA_HOT_COLOUR : NA_AXIS_COLOURS[arrow['id']]
                view.line_stipple  = ''
                view.line_width    = arrow['id'] == hot ? 5 : 3
                view.drawing_color = colour
                o, tip = arrow['o'], arrow['tip']
                view.draw2d(GL_LINES, [Geom::Point3d.new(o[0], o[1], 0), Geom::Point3d.new(tip[0], tip[1], 0)])
                next unless arrow['length'] > 4.0
                ux = (tip[0] - o[0]) / arrow['length']
                uy = (tip[1] - o[1]) / arrow['length']
                head = [
                    Geom::Point3d.new(arrow['end'][0], arrow['end'][1], 0),
                    Geom::Point3d.new(tip[0] - uy * NA_HEAD_HALF_PX, tip[1] + ux * NA_HEAD_HALF_PX, 0),
                    Geom::Point3d.new(tip[0] + uy * NA_HEAD_HALF_PX, tip[1] - ux * NA_HEAD_HALF_PX, 0)
                ]
                view.draw2d(GL_TRIANGLES, head)
            end
            self.na_square2d(view, arrows.first['o'], 4.0, NA_WHITE_COLOUR, NA_DARK_COLOUR)
        end

        # Dashed line along the drag axis through where the move started, plus a
        # hollow marker at the start, so the size of the move is easy to read.
        def self.na_draw_axis_guide(view, session, start, axis)
            reach = session.cloud && session.cloud.bounds ? [session.cloud.bounds.diagonal.to_f, 100.0].max : 1000.0
            a = self.na_point((0..2).map { |i| start[i] - axis['vector'][i] * reach })
            b = self.na_point((0..2).map { |i| start[i] + axis['vector'][i] * reach })
            view.line_stipple  = '-'
            view.line_width    = 1
            view.drawing_color = NA_AXIS_COLOURS[axis['id']]
            view.draw(GL_LINES, [a, b])
            view.line_stipple  = ''
            point = self.na_point(start)
            return unless Na__ClipBox.na_in_front?(view, point)
            screen = view.screen_coords(point)
            corners = [[-4, -4], [4, -4], [4, 4], [-4, 4]].map { |dx, dy| Geom::Point3d.new(screen.x + dx, screen.y + dy, 0) }
            view.drawing_color = NA_DARK_COLOUR
            view.draw2d(GL_LINE_LOOP, corners)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Move Tool
    # -------------------------------------------------------------------------

        class Na__CloudMoveTool

            NA_PICK_PX       = 10.0
            NA_DRAG_START_PX = 4.0

            def initialize(session)
                @session = session
                @drag    = nil    # { 'axis', 'start' => translation, 'origin' => gimbal, 'start_param', 'down_x', 'down_y', 'moved' }
                @last    = nil    # { 'axis', 'start', 'origin' } of the last committed move (VCB re-type)
                @hover   = nil
                @picking = false  # Set Gimbal Point: waiting for a click
                @ip      = Sketchup::InputPoint.new
                @pick    = nil    # { 'point', 'snapped' } under the cursor while picking
            end

            def na_picking_gimbal?
                @picking
            end

            def na_pick_marker
                @picking ? @pick : nil
            end

            def na_start_gimbal_pick
                self.na_restore_drag
                @picking = true
                @pick = nil
                self.na_status
                Sketchup.active_model.active_view.invalidate
            end

            def draw(view)
                @ip.draw(view) if @picking && @ip.valid? && @ip.display?
            end

            def na_kind
                'move'
            end

            def na_drag
                @drag
            end

            def na_hot_axis
                @drag ? @drag['axis']['id'] : @hover
            end

            def na_extent_points
                []
            end

            def na_draw_overlay(view)
                Na__Placement.na_draw_gimbal(view, @session, self)
            end

            # -----------------------------------------------------------------
            # Lifecycle
            # -----------------------------------------------------------------

            def activate
                @session.transform_tool = self
                self.na_status
                Sketchup.active_model.active_view.invalidate
                Na__ModelRegistry.na_notify_dialog
            end

            def deactivate(view)
                self.na_restore_drag
                @session.transform_tool = nil if @session.transform_tool.equal?(self)
                view.invalidate
                Na__ModelRegistry.na_notify_dialog
            end

            def resume(view)
                self.na_status
                view.invalidate
            end

            def onCancel(_reason, view)
                if @picking
                    @picking = false
                    @pick = nil
                    Na__ModelRegistry.na_notify_dialog
                end
                self.na_restore_drag
                view.invalidate
                self.na_status
            end

            def enableVCB?
                true
            end

            # -----------------------------------------------------------------
            # Mouse
            # -----------------------------------------------------------------

            def onMouseMove(_flags, x, y, view)
                return unless self.na_ready?
                if @picking
                    @ip.pick(view, x, y)
                    @pick = @ip.valid? ? { 'point' => @ip.position.to_a, 'snapped' => @ip.degrees_of_freedom.zero? } : nil
                    view.tooltip = @ip.tooltip if @ip.valid?
                    view.invalidate
                    return
                end
                if @drag
                    @drag['moved'] ||= Math.hypot(x - @drag['down_x'], y - @drag['down_y']) > NA_DRAG_START_PX
                    self.na_follow_mouse(x, y, view)
                else
                    hover = self.na_pick_axis(x, y, view)
                    if hover != @hover
                        @hover = hover
                        view.invalidate
                    end
                end
            end

            def onLButtonDown(_flags, x, y, view)
                return unless self.na_ready?
                return self.na_place_gimbal(x, y, view) if @picking
                return self.na_commit(view) if @drag                 # second click of click-move-click
                axis_id = self.na_pick_axis(x, y, view)
                return unless axis_id
                axis   = Na__Placement.na_axis(axis_id)
                start  = @session.placement['translation'].dup
                origin = Na__Placement.Na__Placement__GimbalModel(@session)
                param  = Na__Placement.na_axis_param(origin, axis['vector'], x, y, view)
                return unless param
                @drag = { 'axis' => axis, 'start' => start, 'origin' => origin, 'start_param' => param,
                          'down_x' => x, 'down_y' => y, 'moved' => false }
                Sketchup.vcb_value = ''
                Sketchup.status_text = "Moving along the #{axis['label'].downcase} axis. Release, or click again, to finish. " \
                                       'Type a distance for precision. Esc cancels.'
                view.invalidate
            end

            def onLButtonUp(_flags, _x, _y, view)
                self.na_commit(view) if @drag && @drag['moved']       # press-drag-release
            end

            # -----------------------------------------------------------------
            # Typed distance (along the arrow is positive)
            # -----------------------------------------------------------------

            def onUserText(text, view)
                target = @drag || @last
                if @picking
                    UI.beep
                    Sketchup.status_text = 'Click a point for the gimbal first, or press Esc.'
                    return
                end
                unless target && self.na_ready?
                    UI.beep
                    Sketchup.status_text = 'Drag an arrow first, then type the distance.'
                    return
                end
                distance = text.to_l.to_f
                @drag ||= { 'axis' => target['axis'], 'start' => target['start'], 'origin' => target['origin'], 'moved' => true }
                self.na_set_offset(distance)
                self.na_commit(view)
            rescue ArgumentError
                UI.beep
                Sketchup.status_text = "\"#{text}\" is not a distance."
            end

            # -----------------------------------------------------------------
            # Internals
            # -----------------------------------------------------------------

            def na_ready?
                @session.cloud && @session.placement && !@session.placement['locked']
            end

            def na_follow_mouse(x, y, view)
                axis  = @drag['axis']
                param = Na__Placement.na_axis_param(@drag['origin'], axis['vector'], x, y, view)
                return unless param
                distance = Na__Placement.na_snap_distance(param - @drag['start_param'])
                self.na_set_offset(distance)
                Sketchup.vcb_value = distance.to_l.to_s
                Na__ImageRenderer.Na__Image__NoteInteraction(@session, view)
                view.invalidate
            end

            def na_set_offset(distance)
                vector = @drag['axis']['vector']
                translation = (0..2).map { |i| @drag['start'][i] + vector[i] * distance }
                Na__Placement.Na__Placement__SetLive(@session, @session.placement['rotation'], translation)
            end

            def na_commit(view)
                axis   = @drag['axis']
                start  = @drag['start']
                origin = @drag['origin']
                @drag  = nil
                moved = (0..2).any? { |i| (@session.placement['translation'][i] - start[i]).abs > 1e-9 }
                if moved
                    @last = { 'axis' => axis, 'start' => start, 'origin' => origin }
                    Na__Placement.Na__Placement__Save(@session, "Point Cloud: Move Along #{axis['label']}")
                end
                view.invalidate
                self.na_status
                Na__ModelRegistry.na_notify_dialog
            end

            def na_restore_drag
                return unless @drag
                Na__Placement.Na__Placement__SetLive(@session, @session.placement['rotation'], @drag['start']) if @session.placement
                @drag = nil
            end

            def na_place_gimbal(x, y, view)
                @ip.pick(view, x, y)
                return unless @ip.valid?
                problem = Na__Placement.Na__Placement__SetGimbalPoint(@session, @ip.position.to_a)
                @picking = false
                @pick = nil
                Sketchup.status_text = problem if problem
                self.na_status unless problem
                view.invalidate
                Na__ModelRegistry.na_notify_dialog
            end

            def na_status
                if @picking
                    Sketchup.vcb_label = 'Distance'
                    Sketchup.status_text = 'Set gimbal point: click where the gimbal should sit. It snaps to vertices, edges and other ' \
                                           'points in the model. Esc keeps the current point.'
                    return
                end
                snap = Na__Placement.Na__Placement__SnapSettings
                display = Na__UnitContract.Na__Units__ModelDisplay(Sketchup.active_model)
                snap_text = if snap['moveEnabled']
                                "Moves snap to #{Na__UnitContract.Na__Units__InchesToPreciseText(snap['moveInches'], display)} #{display['suffix']}."
                            else
                                'Snapping is off.'
                            end
                Sketchup.vcb_label = 'Distance'
                Sketchup.status_text = "Move: drag a red, green or blue arrow to slide the cloud along that axis, or click an arrow, move and click. #{snap_text} " \
                                       'Type a distance for precision. Esc cancels.'
            end

            def na_pick_axis(x, y, view)
                arrows = Na__Placement.na_gimbal_screen(view, Na__Placement.Na__Placement__GimbalModel(@session))
                return nil unless arrows
                best = nil
                best_px = NA_PICK_PX
                arrows.each do |arrow|
                    distance = Na__Placement.na_segment_distance(x, y, arrow['o'], arrow['end'])
                    next unless distance < best_px
                    best_px = distance
                    best = arrow['id']
                end
                best
            end

        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
