# =============================================================================
# NA POINT CLOUD VIEWER - TRANSFORM - ROTATE TOOL (PROTRACTOR)
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Transform__RotateTool__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__Placement::Na__CloudRotateTool
# PURPOSE    : Rotates the cloud the way SketchUp's Rotate tool rotates
#              geometry:
#                1. click the centre of rotation
#                2. click a point that sets the starting direction (for
#                   example along a wall in the cloud)
#                3. move to rotate and click to finish, for example on a model
#                   edge, to line the cloud up with it
#              Points 1 and 3 use SketchUp's inference (endpoints, edges,
#              axes) so the cloud can be aligned with existing geometry. Type
#              an angle for precision, during a rotation or straight after one.
#              Arrow keys lock the protractor: Right = red axis, Left = green,
#              Up = blue (the default, a plan rotation). Esc cancels.
#              Only works while the position is unlocked. Creates no geometry.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__Placement

    # -------------------------------------------------------------------------
    # REGION | Protractor Drawing
    # -------------------------------------------------------------------------

        NA_INFERENCE_COLOUR = Sketchup::Color.new(0, 190, 80) unless defined?(NA_INFERENCE_COLOUR)

        # Two unit vectors spanning the plane square to `axis`.
        def self.na_plane_basis(axis)
            helper = axis[2].abs < 0.9 ? [0.0, 0.0, 1.0] : [1.0, 0.0, 0.0]
            u = self.na_cross(axis, helper)
            length = Math.sqrt(u.sum { |c| c * c })
            u = u.map { |c| c / length }
            [u, self.na_cross(axis, u)]
        end

        def self.na_cross(a, b)
            [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
        end

        def self.na_dot(a, b)
            a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
        end

        def self.na_draw_protractor(view, info)
            centre = info['centre']
            return unless centre
            c = self.na_point(centre)
            return unless Na__ClipBox.na_in_front?(view, c)
            axis = self.na_axis(info['axis_id'])
            u, w = self.na_plane_basis(axis['vector'])
            radius = view.pixels_to_model(self.na_protractor_px, c).to_f
            at = lambda do |angle, scale|
                self.na_point((0..2).map { |i| centre[i] + (u[i] * Math.cos(angle) + w[i] * Math.sin(angle)) * radius * scale })
            end

            view.line_stipple  = ''
            view.line_width    = 2
            view.drawing_color = NA_AXIS_COLOURS[axis['id']]
            view.draw(GL_LINE_LOOP, (0...48).map { |i| at.call(i * Math::PI / 24.0, 1.0) })
            view.line_width = 1
            ticks = (0...24).flat_map do |i|
                angle = i * Math::PI / 12.0
                [at.call(angle, i % 6 == 0 ? 0.72 : 0.86), at.call(angle, 1.0)]
            end
            view.draw(GL_LINES, ticks)
            view.draw(GL_LINES, [at.call(0, 0.12), at.call(Math::PI, 0.12), at.call(Math::PI / 2, 0.12), at.call(-Math::PI / 2, 0.12)])

            if info['start']
                view.line_stipple  = '-'
                view.drawing_color = NA_DARK_COLOUR
                view.draw(GL_LINES, [c, self.na_point(self.na_reach(centre, info['start'], radius))])
                view.line_stipple  = ''
            end
            if info['current']
                view.line_width    = info['state'] == 2 ? 2 : 1
                view.line_stipple  = info['state'] == 2 ? '' : '-'
                view.drawing_color = info['state'] == 2 ? NA_HOT_COLOUR : NA_DARK_COLOUR
                view.draw(GL_LINES, [c, self.na_point(self.na_reach(centre, info['current'], radius))])
                view.line_stipple  = ''
            end
            snapped = info['snap_point']
            if snapped
                point = self.na_point(snapped)
                if Na__ClipBox.na_in_front?(view, point)
                    screen = view.screen_coords(point)
                    self.na_square2d(view, [screen.x, screen.y], 5.0, NA_INFERENCE_COLOUR, NA_DARK_COLOUR)
                end
            end
            view.line_width = 1
        end

        # The point itself, or the protractor's rim when the point is closer.
        def self.na_reach(centre, point, radius)
            v = (0..2).map { |i| point[i] - centre[i] }
            length = Math.sqrt(v.sum { |c| c * c })
            return point if length >= radius || length < 1e-9
            (0..2).map { |i| centre[i] + v[i] / length * radius }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Rotate Tool
    # -------------------------------------------------------------------------

        class Na__CloudRotateTool

            NA_KEY_RIGHT = defined?(VK_RIGHT) ? VK_RIGHT : 39
            NA_KEY_LEFT  = defined?(VK_LEFT)  ? VK_LEFT  : 37
            NA_KEY_UP    = defined?(VK_UP)    ? VK_UP    : 38

            attr_reader :state, :axis_id

            def initialize(session)
                @session   = session
                @ip        = Sketchup::InputPoint.new
                @ip_centre = Sketchup::InputPoint.new
                @axis_id   = 'z'
                @last      = nil   # { 'axis_id', 'centre', 'start_placement' } of the last rotation (VCB re-type)
                self.na_reset_state
            end

            def na_kind
                'rotate'
            end

            def na_extent_points
                [@centre, @start, @current].compact.map { |coords| Na__Placement.na_point(coords) }
            end

            def na_draw_overlay(view)
                centre = @centre || (@hover_centre if @state.zero?)
                Na__Placement.na_draw_protractor(view, {
                    'centre' => centre, 'axis_id' => @axis_id, 'state' => @state,
                    'start' => @start, 'current' => (@current if @state >= 1),
                    'snap_point' => @snap_point
                })
            end

            # -----------------------------------------------------------------
            # Lifecycle
            # -----------------------------------------------------------------

            def activate
                @session.transform_tool = self
                self.na_reset_state
                self.na_status
                Sketchup.active_model.active_view.invalidate
                Na__ModelRegistry.na_notify_dialog
            end

            def deactivate(view)
                self.na_restore_live
                @session.transform_tool = nil if @session.transform_tool.equal?(self)
                Na__RenderController.Na__Render__RefreshExtents(@session)
                view.invalidate
                Na__ModelRegistry.na_notify_dialog
            end

            def resume(view)
                self.na_status
                view.invalidate
            end

            def onCancel(_reason, view)
                self.na_restore_live
                self.na_reset_state
                Na__RenderController.Na__Render__RefreshExtents(@session)
                self.na_status
                view.invalidate
            end

            def enableVCB?
                true
            end

            def draw(view)
                @ip.draw(view) if @ip.valid? && @ip.display?
            end

            # Right = red, Left = green, Up = blue. Pressing a locked key again
            # returns to blue (plan rotation). Fixed once a rotation is under way.
            def onKeyDown(key, _repeat, _flags, view)
                axis_id = { NA_KEY_RIGHT => 'x', NA_KEY_LEFT => 'y', NA_KEY_UP => 'z' }[key]
                return false unless axis_id
                if @state == 2
                    UI.beep
                    return true
                end
                @axis_id = @axis_id == axis_id && axis_id != 'z' ? 'z' : axis_id
                @start = nil
                @current = nil
                self.na_status
                view.invalidate
                true
            end

            # -----------------------------------------------------------------
            # Mouse
            # -----------------------------------------------------------------

            def onMouseMove(_flags, x, y, view)
                return unless self.na_ready?
                self.na_pick(view, x, y)
                view.tooltip = @ip.tooltip if @ip.valid?
                case @state
                when 0
                    @hover_centre = @ip.valid? ? @ip.position.to_a : nil
                when 1
                    @current = self.na_plane_point(x, y, view)
                when 2
                    @current = self.na_plane_point(x, y, view)
                    angle = @current ? self.na_angle_to(@current) : nil
                    if angle
                        @angle = self.na_snap_angle(angle)
                        self.na_apply_angle(@angle)
                        Sketchup.vcb_value = Na__UnitContract.Na__Units__TrimNumber(@angle * 180.0 / Math::PI, 2)
                        Na__ImageRenderer.Na__Image__NoteInteraction(@session, view)
                    end
                end
                Na__RenderController.Na__Render__RefreshExtents(@session)
                view.invalidate
            end

            def onLButtonDown(_flags, x, y, view)
                return unless self.na_ready?
                self.na_pick(view, x, y)
                case @state
                when 0
                    return unless @ip.valid?
                    @centre = @ip.position.to_a
                    @ip_centre.copy!(@ip)
                    @state = 1
                when 1
                    point = self.na_plane_point(x, y, view)
                    return unless point && Math.sqrt((0..2).sum { |i| (point[i] - @centre[i])**2 }) > 1e-3
                    @start   = point
                    @current = point
                    @angle   = 0.0
                    @start_placement = { 'rotation' => @session.placement['rotation'].dup, 'translation' => @session.placement['translation'].dup }
                    @state = 2
                    Sketchup.vcb_value = ''
                when 2
                    self.na_commit(view)
                end
                self.na_status
                view.invalidate
            end

            # -----------------------------------------------------------------
            # Typed angle (degrees, anticlockwise positive about the axis)
            # -----------------------------------------------------------------

            def onUserText(text, view)
                degrees = Na__Placement.Na__Placement__ParseAngle(text)
                if @state == 2
                    @angle = degrees * Math::PI / 180.0
                    self.na_apply_angle(@angle)
                    self.na_commit(view)
                elsif @last && self.na_ready?
                    rotation, translation = Na__Placement.Na__Placement__RotatedAbout(
                        @last['start_placement']['rotation'], @last['start_placement']['translation'],
                        Na__Placement.na_axis(@last['axis_id'])['vector'], degrees * Math::PI / 180.0, @last['centre'])
                    Na__Placement.Na__Placement__SetLive(@session, rotation, translation)
                    Na__Placement.Na__Placement__Save(@session, 'Point Cloud: Rotate')
                    view.invalidate
                    Na__ModelRegistry.na_notify_dialog
                else
                    UI.beep
                    Sketchup.status_text = 'Pick the centre and the starting direction first, then type the angle.'
                end
            rescue ArgumentError => error
                UI.beep
                Sketchup.status_text = error.message
            end

            # -----------------------------------------------------------------
            # Internals
            # -----------------------------------------------------------------

            def na_ready?
                @session.cloud && @session.placement && !@session.placement['locked']
            end

            def na_reset_state
                @state           = 0
                @centre          = nil
                @hover_centre    = nil
                @start           = nil
                @current         = nil
                @snap_point      = nil
                @angle           = 0.0
                @start_placement = nil
            end

            def na_pick(view, x, y)
                if @state.zero?
                    @ip.pick(view, x, y)
                else
                    @ip.pick(view, x, y, @ip_centre)
                end
                snapped = @ip.valid? && @ip.degrees_of_freedom.zero?
                @snap_point = snapped ? @ip.position.to_a : nil
            end

            def na_axis_vector
                Na__Placement.na_axis(@axis_id)['vector']
            end

            # The cursor on the protractor's plane: an inferred point (endpoint,
            # edge...) dropped onto the plane, otherwise the mouse ray meeting it.
            def na_plane_point(x, y, view)
                axis = self.na_axis_vector
                if @snap_point
                    offset = Na__Placement.na_dot((0..2).map { |i| @snap_point[i] - @centre[i] }, axis)
                    return (0..2).map { |i| @snap_point[i] - axis[i] * offset }
                end
                origin, direction = view.pickray(x, y)
                o = origin.to_a
                d = direction.to_a
                denom = Na__Placement.na_dot(d, axis)
                return nil if denom.abs < 1e-9
                s = Na__Placement.na_dot((0..2).map { |i| @centre[i] - o[i] }, axis) / denom
                return nil unless s > 0
                (0..2).map { |i| o[i] + d[i] * s }
            end

            def na_angle_to(point)
                axis = self.na_axis_vector
                v1 = (0..2).map { |i| @start[i] - @centre[i] }
                v2 = (0..2).map { |i| point[i] - @centre[i] }
                return nil if Na__Placement.na_dot(v1, v1) < 1e-12 || Na__Placement.na_dot(v2, v2) < 1e-12
                Math.atan2(Na__Placement.na_dot(Na__Placement.na_cross(v1, v2), axis), Na__Placement.na_dot(v1, v2))
            end

            def na_snap_angle(angle)
                snap = Na__Placement.Na__Placement__SnapSettings
                step = snap['angleDegrees'] * Math::PI / 180.0
                return angle unless snap['angleEnabled'] && step > 1e-9
                (angle / step).round * step
            end

            def na_apply_angle(angle)
                rotation, translation = Na__Placement.Na__Placement__RotatedAbout(
                    @start_placement['rotation'], @start_placement['translation'], self.na_axis_vector, angle, @centre)
                Na__Placement.Na__Placement__SetLive(@session, rotation, translation)
            end

            def na_commit(view)
                if @angle.abs < 1e-9
                    self.na_restore_live
                else
                    Na__Placement.Na__Placement__Save(@session, 'Point Cloud: Rotate')
                    @last = { 'axis_id' => @axis_id, 'centre' => @centre, 'start_placement' => @start_placement }
                end
                self.na_reset_state
                Na__RenderController.Na__Render__RefreshExtents(@session)
                view.invalidate
                Na__ModelRegistry.na_notify_dialog
            end

            def na_restore_live
                return unless @state == 2 && @start_placement && @session.placement
                Na__Placement.Na__Placement__SetLive(@session, @start_placement['rotation'], @start_placement['translation'])
            end

            def na_status
                axis_name = { 'x' => 'red', 'y' => 'green', 'z' => 'blue' }[@axis_id]
                Sketchup.vcb_label = 'Angle'
                Sketchup.status_text = case @state
                                       when 0 then "Rotate about the #{axis_name} axis: click the centre of rotation. " \
                                                   'Arrow keys lock the axis: Right = red, Left = green, Up = blue.'
                                       when 1 then 'Click a point that sets the starting direction, for example along a wall in the cloud.'
                                       else 'Move to rotate, then click to finish. Click on a model edge or point to line the cloud up with it. ' \
                                            'Type an angle for precision. Esc cancels.'
                                       end
            end

        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
