# =============================================================================
# NA POINT CLOUD VIEWER - CLIP BOX - EDIT TOOL + CAGE
# =============================================================================
#
# FILE       : Na__PointCloudViewer__ClipBox__EditTool__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__ClipBox::Na__ClipBoxTool
# PURPOSE    : Moves the six sides of the clip box in the viewport, in the
#              way SketchUp's Push/Pull moves a face:
#                - hover a side's handle (or anywhere on that side) to pick it
#                - press-drag, or click / move / click
#                - type a distance + Enter: outward is positive; works during a
#                  move and straight after one (re-types the last move)
#                - Esc cancels the move in progress
#              Choosing any other tool finishes editing. The tool creates no
#              geometry and never snaps to points.
#
# DRAWING: the cage is drawn by the OVERLAY (after the cloud image), not by
#   Tool#draw, so the cloud picture can never cover it.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__ClipBox

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # slot: the cloud whose box is edited (the active one).
        def self.Na__Clip__StartEditing(slot)
            return 'Import a point cloud first: the clip box starts at the cloud\'s bounds.' unless slot
            self.Na__Clip__Ensure(slot)
            unless slot.clip
                return 'Load this point cloud first: the clip box starts at the cloud\'s bounds.' unless slot.cloud
                slot.clip = self.na_cloud_box(slot)
                problem = self.Na__Clip__Save(slot, self.na_op(slot, 'Create Clip Box'))
                return problem if problem
            end
            Sketchup.active_model.select_tool(Na__ClipBoxTool.new(slot))
            nil
        end

        def self.Na__Clip__StopEditing(_slot)
            Sketchup.active_model.select_tool(nil)
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Cage Drawing (called from Overlay#draw while editing)
    # -------------------------------------------------------------------------

        NA_CAGE_COLOUR   = Sketchup::Color.new(255, 128, 0)   unless defined?(NA_CAGE_COLOUR)
        NA_ACTIVE_COLOUR = Sketchup::Color.new(220, 30, 30)   unless defined?(NA_ACTIVE_COLOUR)
        NA_HANDLE_PX     = 6.0

        def self.Na__Clip__DrawCage(slot, view)
            clip = slot.clip
            return unless clip
            lo = clip['min']
            hi = clip['max']
            corners = [0, 1].product([0, 1], [0, 1]).map do |ix, iy, iz|
                Geom::Point3d.new(ix.zero? ? lo[0] : hi[0], iy.zero? ? lo[1] : hi[1], iz.zero? ? lo[2] : hi[2])
            end
            edges = [[0, 4], [2, 6], [1, 5], [3, 7], [0, 2], [4, 6], [1, 3], [5, 7], [0, 1], [2, 3], [4, 5], [6, 7]]
            view.line_stipple = ''
            view.line_width   = 2
            view.drawing_color = NA_CAGE_COLOUR
            view.draw(GL_LINES, edges.flat_map { |a, b| [corners[a], corners[b]] })

            highlight = slot.clip_drag_face || slot.clip_hover
            if highlight
                face = self.Na__Clip__Face(highlight)
                ring = self.na_face_corners(clip, face)
                view.line_width = 4
                view.drawing_color = NA_ACTIVE_COLOUR
                view.draw(GL_LINE_LOOP, ring)
            end
            view.line_width = 1

            NA_FACES.each do |face|
                centre = self.na_face_centre(clip, face)
                next unless self.na_in_front?(view, centre)
                screen = view.screen_coords(centre)
                size = face['id'] == highlight ? NA_HANDLE_PX * 1.5 : NA_HANDLE_PX
                square = [[-size, -size], [size, -size], [size, size], [-size, size]].map { |dx, dy| Geom::Point3d.new(screen.x + dx, screen.y + dy, 0) }
                view.drawing_color = face['id'] == highlight ? NA_ACTIVE_COLOUR : NA_CAGE_COLOUR
                view.draw2d(GL_QUADS, square)
            end
        end

        def self.na_face_centre(clip, face)
            centre = (0..2).map { |i| (clip['min'][i] + clip['max'][i]) / 2.0 }
            centre[face['axis']] = clip[face['side']][face['axis']]
            Geom::Point3d.new(*centre)
        end

        def self.na_face_corners(clip, face)
            axis = face['axis']
            others = [0, 1, 2] - [axis]
            [[0, 0], [1, 0], [1, 1], [0, 1]].map do |a, b|
                coords = []
                coords[axis] = clip[face['side']][axis]
                coords[others[0]] = a.zero? ? clip['min'][others[0]] : clip['max'][others[0]]
                coords[others[1]] = b.zero? ? clip['min'][others[1]] : clip['max'][others[1]]
                Geom::Point3d.new(*coords)
            end
        end

        def self.na_in_front?(view, point)
            camera = view.camera
            return true unless camera.perspective?
            camera.eye.vector_to(point).dot(camera.zaxis) > 0
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Tool
    # -------------------------------------------------------------------------

        class Na__ClipBoxTool

            NA_PICK_PX      = 14.0
            NA_DRAG_START_PX = 4.0

            def initialize(slot)
                @slot    = slot   # the cloud whose box this tool edits, fixed for the tool's life
                @drag    = nil    # { face, start_value, start_param, down_x, down_y, moved }
                @last    = nil    # { face, start_value } of the last committed move (VCB re-type)
            end

            def na_slot
                @slot
            end

            # -----------------------------------------------------------------
            # Lifecycle
            # -----------------------------------------------------------------

            def activate
                @slot.clip_editing = true
                Na__RenderController.Na__Render__RefreshExtents(@slot.session)
                self.na_status
                Sketchup.active_model.active_view.invalidate
                Na__ClipBox.na_notify_dialog
            end

            def deactivate(view)
                self.na_restore_drag
                @slot.clip_editing   = false
                @slot.clip_hover     = nil
                @slot.clip_drag_face = nil
                Na__RenderController.Na__Render__RefreshExtents(@slot.session)
                view.invalidate
                Na__ClipBox.na_notify_dialog
            end

            def resume(view)
                self.na_status
                view.invalidate
            end

            def onCancel(_reason, view)
                return unless @drag
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
                if @drag
                    @drag['moved'] ||= Math.hypot(x - @drag['down_x'], y - @drag['down_y']) > NA_DRAG_START_PX
                    self.na_follow_mouse(x, y, view)
                else
                    hover = self.na_pick_face(x, y, view)
                    if hover != @slot.clip_hover
                        @slot.clip_hover = hover
                        view.invalidate
                    end
                end
            end

            def onLButtonDown(_flags, x, y, view)
                return self.na_commit(view) if @drag                 # second click of click-move-click
                face_id = self.na_pick_face(x, y, view)
                return unless face_id
                face  = Na__ClipBox.Na__Clip__Face(face_id)
                param = self.na_axis_param(face, x, y, view)
                return unless param
                @drag = {
                    'face' => face, 'start_value' => Na__ClipBox.Na__Clip__FaceValue(@slot, face),
                    'start_param' => param, 'down_x' => x, 'down_y' => y, 'moved' => false,
                    'was_enabled' => @slot.clip['enabled']
                }
                @slot.clip_drag_face = face_id
                @slot.clip['enabled'] = true                        # clip live while moving
                Sketchup.vcb_value = ''
                Sketchup.status_text = "Moving the #{face['label']} side. Move the mouse and click, or type a distance. Esc cancels."
                view.invalidate
            end

            def onLButtonUp(_flags, _x, _y, view)
                self.na_commit(view) if @drag && @drag['moved']       # press-drag-release
            end

            # -----------------------------------------------------------------
            # Typed distance (outward positive), like Push/Pull
            # -----------------------------------------------------------------

            def onUserText(text, view)
                target = @drag || @last
                unless target
                    UI.beep
                    Sketchup.status_text = 'Pick a side of the clip box first, then type the distance.'
                    return
                end
                distance = text.to_l.to_f
                face = target['face']
                outward = face['side'] == 'max' ? 1.0 : -1.0
                if @drag.nil? && @last
                    @drag = { 'face' => face, 'start_value' => @last['start_value'], 'start_param' => 0.0, 'moved' => true,
                              'was_enabled' => @slot.clip['enabled'] }
                end
                Na__ClipBox.Na__Clip__SetFaceLive(@slot, face, target['start_value'] + outward * distance)
                self.na_commit(view)
            rescue ArgumentError
                UI.beep
                Sketchup.status_text = "\"#{text}\" is not a distance."
            end

            # -----------------------------------------------------------------
            # Internals
            # -----------------------------------------------------------------

            def na_follow_mouse(x, y, view)
                face  = @drag['face']
                param = self.na_axis_param(face, x, y, view)
                return unless param
                value = Na__ClipBox.Na__Clip__SetFaceLive(@slot, face, @drag['start_value'] + (param - @drag['start_param']))
                Sketchup.vcb_value = (value - @drag['start_value']).abs.to_l.to_s
                Na__ImageRenderer.Na__Image__NoteInteraction(@slot.session, view)
                Na__RenderController.Na__Render__RefreshExtents(@slot.session)
                view.invalidate
            end

            def na_commit(view)
                face = @drag['face']
                @last = { 'face' => face, 'start_value' => @drag['start_value'] }
                @drag = nil
                @slot.clip_drag_face = nil
                @slot.clip['enabled'] = true
                problem = Na__ClipBox.Na__Clip__Save(@slot, Na__ClipBox.na_op(@slot, "Move Clip #{face['label']}"))
                Sketchup.status_text = problem if problem
                Na__RenderController.Na__Render__RefreshExtents(@slot.session)
                view.invalidate
                self.na_status
                Na__ClipBox.na_notify_dialog
            end

            def na_restore_drag
                return unless @drag
                Na__ClipBox.Na__Clip__SetFaceLive(@slot, @drag['face'], @drag['start_value'])
                @slot.clip['enabled'] = @drag['was_enabled']
                @drag = nil
                @slot.clip_drag_face = nil
                Na__RenderController.Na__Render__RefreshExtents(@slot.session)
            end

            def na_status
                Sketchup.vcb_label = 'Distance'
                Sketchup.status_text = "#{Na__CloudSet.Na__Slots__Prefix(@slot)}Clip box: pick a side (the square handles) and drag it, or click, move and click. " \
                                       'Type a distance for precision. Esc cancels. Choose another tool to finish.'
            end

            # Handles first (they work from any angle), then the box faces under
            # the cursor (nearest hit along the pick ray).
            def na_pick_face(x, y, view)
                clip = @slot.clip
                return nil unless clip
                best = nil
                best_px = NA_PICK_PX
                NA_FACES.each do |face|
                    centre = Na__ClipBox.na_face_centre(clip, face)
                    next unless Na__ClipBox.na_in_front?(view, centre)
                    screen = view.screen_coords(centre)
                    distance = Math.hypot(screen.x - x, screen.y - y)
                    if distance < best_px
                        best_px = distance
                        best = face['id']
                    end
                end
                best || self.na_pick_face_by_ray(x, y, view)
            end

            def na_pick_face_by_ray(x, y, view)
                clip = @slot.clip
                origin, direction = view.pickray(x, y)
                o = origin.to_a
                d = direction.to_a
                best = nil
                best_t = Float::INFINITY
                NA_FACES.each do |face|
                    axis = face['axis']
                    next if d[axis].abs < 1e-12
                    t = (clip[face['side']][axis] - o[axis]) / d[axis]
                    next unless t > 0 && t < best_t
                    hit = (0..2).map { |i| o[i] + d[i] * t }
                    inside = ([0, 1, 2] - [axis]).all? { |i| hit[i] >= clip['min'][i] - 1e-6 && hit[i] <= clip['max'][i] + 1e-6 }
                    next unless inside
                    best_t = t
                    best = face['id']
                end
                best
            end

            # Parameter along the face's axis line closest to the mouse ray, so
            # the grabbed side follows the cursor at any view angle.
            def na_axis_param(face, x, y, view)
                origin, direction = view.pickray(x, y)
                centre = Na__ClipBox.na_face_centre(@slot.clip, face).to_a
                axis = [0.0, 0.0, 0.0]
                axis[face['axis']] = 1.0
                p = origin.to_a
                dvec = direction.to_a
                w0 = (0..2).map { |i| centre[i] - p[i] }
                b = axis.each_with_index.sum { |a, i| a * dvec[i] }
                c = dvec.sum { |v| v * v }
                dd = axis.each_with_index.sum { |a, i| a * w0[i] }
                e = dvec.each_with_index.sum { |v, i| v * w0[i] }
                denom = c - b * b
                return nil if denom.abs < 1e-9            # looking straight down the axis
                centre[face['axis']] + (b * e - c * dd) / denom
            end

        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Sync
    # -------------------------------------------------------------------------

        def self.na_notify_dialog
            return unless defined?(Na__DialogManager) && Na__DialogManager.Na__Dialog__Visible?
            UI.start_timer(0, false) { Na__PointCloudViewer::Na__DialogManager.Na__Dialog__PushState }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
