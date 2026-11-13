# =============================================================================
# NA POINT CLOUD VIEWER - CLIP BOX - TURNED BOXES
# =============================================================================
#
# FILE       : Na__PointCloudViewer__ClipBox__Turned__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__ClipBox (and Na__ClipBox::Na__ClipTurnTool)
# CREATED    : 13-Nov-2026 (v0.14.8)
# PURPOSE    : A clip box turned to follow a wall that is not square to the
#              model (Kann's boundary walls run 3.76 degrees off), or set at
#              any angle by an agent: saved in the cloud's record, drawn,
#              rendered, edited side by side and kept in clip scenes like a
#              level box. Adam, 13-Nov-2026: "Yes support turned clip boxes",
#              then "Yes, build it" for a turned box kept in the viewer.
#
# HOW A TURNED BOX IS KEPT: the box hash gains 'turned':
#     { 'origin' => [x, y, z], 'x_axis' => [...], 'y_axis' => [...],
#       'min' => [...], 'max' => [...] }
#   in model inches: a right-handed frame (z = x cross y, unit axes) and the
#   box's limits in it. 'min' and 'max' stay the LEVEL box round the turned
#   one, so everything that only needs the area (extents, Zoom to Cloud, the
#   filter preview's region, scene images' framing) works unchanged, and a
#   viewer older than 0.14.8 clips to that level box instead of failing.
#
# HOW IT RENDERS, ENGINE UNCHANGED (ABI 9): the engine tests each point,
#   after local -> model, against a box level with the axes it sees. The
#   cloud's transform and the camera are both folded into the box's frame
#   (Na__McpFrame, as the MCP's turned slices and ortho planes do), so the
#   engine's level box is the turned box and the picture is unchanged. The
#   Crop and Cut view is off while a turned box clips: its boxes are level in
#   the model, so they cannot be tested in the turned frame.
#
# WORKING IN THE BOX'S OWN AXES: Na__Clip__Space gives any box (level or
#   turned) as [frame or nil, lo, hi], the limits in its own axes. The edit
#   tool, the typed limits and the clip scenes work there; corners go back to
#   the model through the frame.
#
# =============================================================================

require_relative '../95__System__McpOperations/Na__PointCloudViewer__McpOperations__Frame__'

module Na__PointCloudViewer
    module Na__ClipBox

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_TURN_KEY        = 'turned'.freeze
        NA_TURN_ALIGNED    = 1e-9    # an axis this close to a model axis is level
        NA_TURN_PICK_COLOUR = Sketchup::Color.new(220, 30, 30) unless defined?(NA_TURN_PICK_COLOUR)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Reading a Box in Its Own Axes
    # -------------------------------------------------------------------------

        # The turned part of a box (a clip box or a clip scene), or nil when it
        # is level.
        def self.Na__Clip__TurnedPart(box)
            return nil unless box.is_a?(Hash)
            turned = box[NA_TURN_KEY]
            turned.is_a?(Hash) ? turned : nil
        end

        def self.Na__Clip__Turned?(box)
            self.Na__Clip__TurnedPart(box) ? true : false
        end

        # The frame Na__McpFrame works with: { 'origin', 'axes' => [x, y, z] }.
        def self.Na__Clip__TurnedFrame(turned)
            x = turned['x_axis']
            y = turned['y_axis']
            { 'origin' => turned['origin'], 'axes' => [x, y, Na__McpFrame.na_cross(x, y)] }
        end

        # [frame or nil, lo, hi]: the box in its own axes. lo and hi are the
        # box's own arrays, so a change to them changes the box (refresh the
        # level bounds after, with na_refresh_bounds).
        def self.Na__Clip__Space(box)
            turned = self.Na__Clip__TurnedPart(box)
            return [nil, box['min'], box['max']] unless turned
            [self.Na__Clip__TurnedFrame(turned), turned['min'], turned['max']]
        end

        # A point in the box's own axes, in the model.
        def self.Na__Clip__SpaceToModel(frame, point)
            frame ? Na__McpFrame.Na__Frame__ToModel(frame, point) : point.map(&:to_f)
        end

        # A model point (or direction) in the box's own axes.
        def self.Na__Clip__ModelToSpace(frame, point)
            frame ? Na__McpFrame.Na__Frame__ToFrame(frame, point) : point.map(&:to_f)
        end

        def self.Na__Clip__DirectionToSpace(frame, direction)
            return direction.map(&:to_f) unless frame
            frame['axes'].map { |axis| Na__McpFrame.na_dot(axis, direction) }
        end

        # The eight corners in the model, [x, y, z] each, ordered as
        # [0, 1].product([0, 1], [0, 1]) over the box's own x, y and z (the
        # cage's edge list depends on this order).
        def self.Na__Clip__CornersModel(box)
            frame, lo, hi = self.Na__Clip__Space(box)
            [0, 1].product([0, 1], [0, 1]).map do |ix, iy, iz|
                self.Na__Clip__SpaceToModel(frame, [ix.zero? ? lo[0] : hi[0], iy.zero? ? lo[1] : hi[1], iz.zero? ? lo[2] : hi[2]])
            end
        end

        # The box's plan angle: degrees anticlockwise from the red axis to its
        # own x, when it is turned about the vertical only; 0.0 for a level box;
        # nil for a box tilted out of level (an agent can set one).
        def self.Na__Clip__TurnAngle(box)
            turned = self.Na__Clip__TurnedPart(box)
            return 0.0 unless turned
            z = Na__McpFrame.na_cross(turned['x_axis'], turned['y_axis'])
            return nil unless (z[2] - 1.0).abs < 1e-9
            Math.atan2(turned['x_axis'][1], turned['x_axis'][0]) * 180.0 / Math::PI
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Making a Turned Box
    # -------------------------------------------------------------------------

        # A box from a frame (origin, x_axis, y_axis in model inches; the axes
        # any length, y made square to x) and its limits lo..hi in that frame.
        # A frame whose axes all lie along the model's axes gives a LEVEL box
        # (the same box, without 'turned'). Raises ArgumentError naming what
        # is wrong with the frame or the limits.
        def self.Na__Clip__MakeTurned(enabled, origin, x_axis, y_axis, lo, hi)
            frame = Na__McpFrame.Na__Frame__Make('origin' => origin, 'x_axis' => x_axis, 'y_axis' => y_axis)
            lo = lo.map { |value| Float(value) }
            hi = hi.map { |value| Float(value) }
            raise ArgumentError, 'A turned box needs three limits each way.' unless lo.length == 3 && hi.length == 3
            3.times do |axis|
                next if hi[axis] - lo[axis] >= NA_MIN_GAP_INCHES
                raise ArgumentError, "The box is too thin along its own #{%w[x y z][axis]}: each side must be at least #{(NA_MIN_GAP_INCHES * 25.4).round} mm."
            end
            x, y, _z = frame['axes']
            box = {
                'enabled'   => enabled ? true : false,
                NA_TURN_KEY => { 'origin' => frame['origin'], 'x_axis' => x, 'y_axis' => y, 'min' => lo, 'max' => hi }
            }
            self.na_refresh_bounds(box)
            return { 'enabled' => box['enabled'], 'min' => box['min'], 'max' => box['max'] } if self.na_axes_aligned?(frame['axes'])
            box
        end

        # The box turned about the vertical through its centre to `degrees`
        # (anticlockwise from red), its sizes along its own sides kept. With
        # centre_xy the centre moves there in plan; with length its size along
        # its own x becomes that. 0, 90, 180 and 270 give a level box.
        def self.Na__Clip__TurnedAbout(box, degrees, centre_xy = nil, length = nil)
            frame, lo, hi = self.Na__Clip__Space(box)
            centre = self.Na__Clip__SpaceToModel(frame, (0..2).map { |i| (lo[i] + hi[i]) / 2.0 })
            half = (0..2).map { |i| (hi[i] - lo[i]) / 2.0 }
            if centre_xy
                centre[0] = centre_xy[0].to_f
                centre[1] = centre_xy[1].to_f
            end
            half[0] = length / 2.0 if length
            radians = degrees.to_f * Math::PI / 180.0
            x_axis = [Math.cos(radians), Math.sin(radians), 0.0].map { |value| value.abs < NA_TURN_ALIGNED ? 0.0 : value }
            y_axis = [-x_axis[1], x_axis[0], 0.0]
            self.Na__Clip__MakeTurned(box['enabled'], centre, x_axis, y_axis, half.map { |value| -value }, half)
        end

        # Recomputes 'min' and 'max' (the level box round a turned one).
        def self.na_refresh_bounds(box)
            return box unless self.Na__Clip__TurnedPart(box)
            corners = self.Na__Clip__CornersModel(box)
            box['min'] = (0..2).map { |i| corners.map { |corner| corner[i] }.min }
            box['max'] = (0..2).map { |i| corners.map { |corner| corner[i] }.max }
            box
        end

        def self.na_axes_aligned?(axes)
            axes.all? { |axis| axis.count { |value| value.abs > NA_TURN_ALIGNED } == 1 }
        end

        # A deep copy of a box, turned part included.
        def self.na_box_dup(box)
            Marshal.load(Marshal.dump(box))
        end

        def self.na_same_turn?(a, b)
            ta = self.Na__Clip__TurnedPart(a)
            tb = self.Na__Clip__TurnedPart(b)
            return ta.nil? && tb.nil? unless ta && tb
            %w[origin x_axis y_axis min max].all? { |key| (0..2).all? { |i| (ta[key][i] - tb[key][i]).abs < 1e-6 } }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Rendering (ImageRenderer, the MCP seam's composite)
    # -------------------------------------------------------------------------

        # The cloud's render camera, transform and clip block: a turned box that
        # clips folds the cloud and the camera into its frame, so the engine's
        # level test is the turned box. Returns [camera_part, transform,
        # clip_params, turned]; turned is true when the fold was made (the Crop
        # and Cut tail must then be off).
        def self.Na__Clip__RenderParts(slot, camera_part, transform)
            turned = self.Na__Clip__IsActive?(slot) ? self.Na__Clip__TurnedPart(slot.clip) : nil
            return [camera_part, transform, self.Na__Clip__RenderParams(slot), false] unless turned
            frame = self.Na__Clip__TurnedFrame(turned)
            [Na__McpFrame.Na__Frame__Camera(frame, camera_part), Na__McpFrame.Na__Frame__Fold(frame, transform),
             [1] + turned['min'] + turned['max'], true]
        end

        # True while a turned box clips this cloud (the Crop and Cut view waits).
        def self.Na__Clip__TurnedActive?(slot)
            self.Na__Clip__IsActive?(slot) && self.Na__Clip__Turned?(slot.clip)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Turning the Active Cloud's Box (the Clipping tab)
    # -------------------------------------------------------------------------

        # Turns the box about the vertical through its centre to `degrees`
        # (text or a number), its sizes kept; 0 levels it. ONE undoable step.
        # Returns nil, or why nothing changed.
        def self.Na__Clip__Turn(slot, degrees)
            return 'Import a point cloud first.' unless slot
            self.Na__Clip__Ensure(slot)
            return 'There is no clip box yet. Draw one, or turn clipping on, first.' unless slot.clip
            value = Float(degrees.to_s.strip.sub(/[^\d.]+\z/, ''))   # "3.76", "3.76 deg", "3.76 degrees"
            return 'Type the turn in degrees, for example 3.76 or -12.5.' unless value.finite?
            box = self.Na__Clip__TurnedAbout(slot.clip, value)
            box['enabled'] = true
            slot.clip = box
            self.Na__Clip__Save(slot, self.na_op(slot, self.Na__Clip__Turned?(box) ? 'Turn Clip Box' : 'Level Clip Box'))
        rescue ArgumentError => error
            error.message.start_with?('invalid value') ? 'Type the turn in degrees, for example 3.76 or -12.5.' : error.message
        end

        def self.Na__Clip__Level(slot)
            self.Na__Clip__Turn(slot, 0)
        end

        # Turn to Two Points: the box runs from a to b (model inches) in plan,
        # its own x along the line, centred on it, as long as the line; its
        # depth, height and level are kept. The angle is kept within 90
        # degrees of red so Left stays on the left. Returns nil, or why not.
        def self.Na__Clip__TurnAlong(slot, a, b)
            return 'Import a point cloud first.' unless slot
            self.Na__Clip__Ensure(slot)
            return 'There is no clip box yet. Draw one, or turn clipping on, first: Turn to Two Points keeps its depth and height.' unless slot.clip
            dx = b[0].to_f - a[0].to_f
            dy = b[1].to_f - a[1].to_f
            length = Math.hypot(dx, dy)
            return "Click two points at least #{(NA_MIN_GAP_INCHES * 25.4).round} mm apart in plan." if length < NA_MIN_GAP_INCHES
            degrees = Math.atan2(dy, dx) * 180.0 / Math::PI
            degrees -= 180.0 if degrees > 90.0 + 1e-9
            degrees += 180.0 if degrees <= -90.0 + 1e-9
            box = self.Na__Clip__TurnedAbout(slot.clip, degrees, [(a[0].to_f + b[0].to_f) / 2.0, (a[1].to_f + b[1].to_f) / 2.0], length)
            box['enabled'] = true
            slot.clip = box
            self.Na__Clip__Save(slot, self.na_op(slot, 'Turn Clip Box to Two Points'))
        rescue ArgumentError => error
            error.message
        end

        def self.Na__Clip__StartTurnPick(slot)
            return 'Import a point cloud first.' unless slot
            self.Na__Clip__Ensure(slot)
            return 'There is no clip box yet. Draw one, or turn clipping on, first: Turn to Two Points keeps its depth and height.' unless slot.clip
            Sketchup.active_model.select_tool(Na__ClipTurnTool.new(slot))
            nil
        end

        # The Clipping tab's line about the turn.
        def self.na_turn_payload(clip)
            return { 'turned' => false, 'angle' => '', 'tilted' => false } unless clip
            angle = self.Na__Clip__TurnAngle(clip)
            {
                'turned' => self.Na__Clip__Turned?(clip),
                'angle'  => angle ? format('%.2f', angle).sub(/\.?0+\z/, '') : '',
                'tilted' => angle.nil?
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Turn to Two Points Tool
    # -------------------------------------------------------------------------

        # Two clicks along a wall face in plan; the box turns square to the line
        # (Na__Clip__TurnAlong), then Edit Clip Box starts so its sides can be
        # pushed to fit. InputPoint and every drawn point are world, which is
        # the model the clip box lives in.
        class Na__ClipTurnTool

            def initialize(slot)
                @slot   = slot
                @ip     = Sketchup::InputPoint.new
                @points = []
            end

            def activate
                self.na_status
                Sketchup.active_model.active_view.invalidate
            end

            def deactivate(view)
                view.invalidate
            end

            def resume(view)
                self.na_status
                view.invalidate
            end

            def onCancel(_reason, view)
                if @points.empty?
                    Sketchup.active_model.select_tool(nil)
                else
                    @points.clear
                    self.na_status
                end
                view.invalidate
            end

            def onMouseMove(_flags, x, y, view)
                @ip.pick(view, x, y)
                view.tooltip = @ip.tooltip if @ip.valid?
                view.invalidate
            end

            def onLButtonDown(_flags, x, y, view)
                @ip.pick(view, x, y)
                return UI.beep unless @ip.valid?
                @points << @ip.position
                if @points.length < 2
                    self.na_status
                    view.invalidate
                    return
                end
                a, b = @points
                @points = []
                problem = Na__ClipBox.Na__Clip__TurnAlong(@slot, a.to_a, b.to_a)
                if problem
                    UI.beep
                    Sketchup.status_text = problem
                    Na__ClipBox.na_notify_dialog
                    return
                end
                Na__RenderController.Na__Render__RefreshExtents(@slot.session)
                Na__ClipBox.Na__Clip__StartEditing(@slot)
                Na__ClipBox.na_notify_dialog
            end

            def draw(view)
                @ip.draw(view) if @ip.display?
                return if @points.empty?
                points = @points + (@ip.valid? ? [@ip.position] : [])
                return if points.length < 2
                view.line_stipple = ''
                view.line_width = 2
                view.drawing_color = Na__ClipBox::NA_TURN_PICK_COLOUR
                view.draw(GL_LINES, points[0, 2])
                view.line_width = 1
            end

            def getExtents
                box = Geom::BoundingBox.new
                @points.each { |point| box.add(point) }
                box.add(@ip.position) if @ip.valid?
                box
            end

            def na_status
                Sketchup.status_text = "#{Na__CloudSet.Na__Slots__Prefix(@slot)}Turn the clip box: " +
                                       (@points.empty? ? 'click one end of the wall face (in plan).' : 'click the other end. The box turns square to the line and runs its length.') +
                                       ' Esc starts again, then leaves.'
            end
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
