# =============================================================================
# NA POINT CLOUD VIEWER - CLIP BOX - DRAW TOOL
# =============================================================================
#
# FILE       : Na__PointCloudViewer__ClipBox__DrawTool__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__ClipBox::Na__ClipDrawTool
# PURPOSE    : Draws a new clip box straight into the model, the way Insert
#              Primitives' Drawn Volume draws a box (Adam, 26-Oct-2026):
#                - drag out the base rectangle (or click, move, click), then
#                  drag the height off it and click
#                - every pick lands on the snap grid (5 mm unless the Clipping
#                  tab says otherwise); CTRL takes SketchUp's inference exactly
#                  where it lands (a vertex, an edge), CTRL+SHIFT takes it and
#                  then rounds it onto the grid
#                - TAB cycles the base plane: Auto, Plan, Front, Side. An arrow
#                  key locks it as SketchUp's tools do (Up plan, Right side,
#                  Left front); Down, or the same arrow again, frees it
#                - type W,H or W,H,D while drawing the base, a height (or +50,
#                  -25) while drawing the height, or W,H,D straight after a box
#                  to change it in place; a typed side stops following the
#                  mouse until Backspace frees it
#                - Backspace frees the last typed side, else steps back; Esc
#                  cancels a box, and leaves the tool when there is none
#              The box clips every cloud on show (Na__Clip__SetBoxOn: ONE
#              undoable step) and the tool stays ready for the next area.
#              Clip Box Around Selection fits the same kind of box round what
#              is selected. Nothing here creates geometry.
#
# CLIP BOXES ARE LEVEL: a clip box is axis aligned in the MODEL (see State), so
#   this tool draws and snaps along the model's red, green and blue axes, never
#   along rotated drawing axes.
#
# DRAWING: the preview is drawn by the OVERLAY after the cloud picture (as the
#   clip cage is), in screen space so floors and walls never hide a box that
#   sits inside them. Tool#draw draws it only while the overlay cannot (the
#   clouds switched off, or drawing paused after a fault).
#
# =============================================================================

module Na__PointCloudViewer
    module Na__ClipBox

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        # u and v are the base rectangle's sides, n the height (model axes).
        NA_DRAW_PLANES = {
            'xy' => { 'label' => 'Plan',  'axes' => [0, 1, 2] },
            'xz' => { 'label' => 'Front', 'axes' => [0, 2, 1] },
            'yz' => { 'label' => 'Side',  'axes' => [1, 2, 0] }
        }.freeze
        NA_DRAW_PLANE_CYCLE = %w[auto xy xz yz].freeze
        NA_DRAW_AXIS_PLANE  = { 'x' => 'yz', 'y' => 'xz', 'z' => 'xy' }.freeze   # an arrow names the plane's normal
        NA_DRAW_AXIS_INDEX  = { 'x' => 0, 'y' => 1, 'z' => 2 }.freeze
        NA_MARGIN_MAX_MM    = 5000.0

        # Insert Primitives' palette: the base rectangle blue, the box amber.
        # The box is drawn over everything, so its fill is the thin one that
        # lets the model and the cloud read through six overlapping faces.
        NA_DRAW_PLANE_FILL   = Sketchup::Color.new(0, 120, 255, 70)    unless defined?(NA_DRAW_PLANE_FILL)
        NA_DRAW_PLANE_BORDER = Sketchup::Color.new(0, 110, 235, 230)   unless defined?(NA_DRAW_PLANE_BORDER)
        NA_DRAW_BOX_FILL     = Sketchup::Color.new(255, 150, 30, 34)   unless defined?(NA_DRAW_BOX_FILL)
        NA_DRAW_BOX_BORDER   = Sketchup::Color.new(226, 118, 0, 235)   unless defined?(NA_DRAW_BOX_BORDER)
        NA_DRAW_LAST_BORDER  = Sketchup::Color.new(226, 118, 0, 150)   unless defined?(NA_DRAW_LAST_BORDER)
        NA_DRAW_ANCHOR       = Sketchup::Color.new(0, 190, 70)         unless defined?(NA_DRAW_ANCHOR)
        NA_DRAW_TEXT         = Sketchup::Color.new(20, 20, 20)         unless defined?(NA_DRAW_TEXT)
        NA_DRAW_HALO         = Sketchup::Color.new(255, 255, 255)      unless defined?(NA_DRAW_HALO)
        NA_DRAW_ACCENT       = Sketchup::Color.new(0, 90, 190)         unless defined?(NA_DRAW_ACCENT)
        NA_DRAW_PINNED       = Sketchup::Color.new(200, 70, 0)         unless defined?(NA_DRAW_PINNED)
        NA_DRAW_AXIS_COLOURS = [
            Sketchup::Color.new(213, 40, 60), Sketchup::Color.new(30, 165, 70), Sketchup::Color.new(45, 90, 220)
        ].freeze unless defined?(NA_DRAW_AXIS_COLOURS)
        NA_DRAW_CROSSHAIR_IN = 250.0 / 25.4
        NA_DRAW_MARK_PX      = 7.0
        NA_DRAW_TEXT_SIZE    = 12
        NA_DRAW_LINE_PX      = 16
        NA_DRAW_HALO_OFFSETS = [[-1, 0], [1, 0], [0, -1], [0, 1]].freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Draw Settings (per user, Clipping tab)
    # -------------------------------------------------------------------------

        # The snap grid in millimetres: the user's choice, else the default
        # (clip.draw.gridMm: 5 mm, Insert Primitives' voxel).
        def self.Na__Clip__DrawGridMm
            stored = Na__UserConfigStore.Na__UserConfig__Get('clip', 'drawGridMm', nil)
            return stored.to_f if stored.is_a?(Numeric) && self.na_grid_step?(stored.to_f)
            default = Na__ConfigLoader.Na__Config__GetOr(5, 'clip', 'draw', 'gridMm').to_f
            default > 0 ? default : 5.0
        end

        def self.Na__Clip__DrawGridSteps
            steps = Array(Na__ConfigLoader.Na__Config__GetOr([1, 5, 10, 25, 50, 100], 'clip', 'draw', 'gridStepsMm'))
            steps = steps.map(&:to_f).select(&:positive?)
            steps.empty? ? [5.0] : steps
        end

        def self.Na__Clip__DrawGridInches
            self.Na__Clip__DrawGridMm / 25.4
        end

        # A point onto the grid, along the model's own axes (model inches).
        def self.Na__Clip__SnapPoint(coords, step = nil)
            step ||= self.Na__Clip__DrawGridInches
            coords.map { |value| (value.to_f / step).round * step }
        end

        # Returns nil, or why nothing changed.
        def self.Na__Clip__SetDrawGridMm(value)
            mm = (Float(value) rescue nil)
            return 'Choose one of the grid sizes shown.' unless mm && self.na_grid_step?(mm)
            Na__UserConfigStore.Na__UserConfig__Set('clip', 'drawGridMm', mm)
            nil
        end

        # How far Clip Box Around Selection reaches past what is selected.
        def self.Na__Clip__SelectionMarginMm
            stored = Na__UserConfigStore.Na__UserConfig__Get('clip', 'selectionMarginMm', nil)
            return stored.to_f if stored.is_a?(Numeric) && stored.to_f >= 0 && stored.to_f <= NA_MARGIN_MAX_MM
            default = Na__ConfigLoader.Na__Config__GetOr(100, 'clip', 'draw', 'selectionMarginMm').to_f
            default >= 0 ? default : 100.0
        end

        def self.Na__Clip__SetSelectionMarginMm(text)
            mm = (Float(text.to_s.strip) rescue nil)
            return "Type the margin in millimetres, from 0 to #{NA_MARGIN_MAX_MM.round}." unless mm && mm >= 0 && mm <= NA_MARGIN_MAX_MM
            Na__UserConfigStore.Na__UserConfig__Set('clip', 'selectionMarginMm', mm)
            nil
        end

        def self.na_grid_step?(mm)
            self.Na__Clip__DrawGridSteps.any? { |step| (step - mm).abs < 1e-9 }
        end

        def self.na_mm_text(mm)
            Na__UnitContract.Na__Units__TrimNumber(mm, 2)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Start, Apply, Around Selection
    # -------------------------------------------------------------------------

        # Selects the Draw Clip Box tool (a fresh one, ready for a new box).
        # Returns nil, or why not.
        def self.Na__Clip__StartDrawing(session)
            return 'The point cloud overlay is not available for this model (SketchUp 2023 or newer is required).' unless session
            return 'There is no point cloud in this model yet. Import one on the View tab first.' if Na__CloudSet.Na__Slots__All(session).empty?
            Sketchup.active_model.select_tool(Na__ClipDrawTool.new(session))
            nil
        end

        def self.Na__Clip__StopDrawing(session)
            Sketchup.active_model.select_tool(nil) if session && session.clip_draw_tool
            nil
        end

        # The two corners of a box from its anchor, base plane and SIGNED sizes
        # [u, v, n] (model inches).
        def self.Na__Clip__DrawCorners(anchor, plane, signed)
            u, v, n = NA_DRAW_PLANES[plane]['axes']
            far = anchor.map(&:to_f)
            far[u] += signed[0]
            far[v] += signed[1]
            far[n] += signed[2]
            [(0..2).map { |i| [anchor[i], far[i]].min }, (0..2).map { |i| [anchor[i], far[i]].max }]
        end

        # Gives `slots` the box and makes sure it is seen: those clouds and the
        # overlay are switched on. Returns nil, or why nothing changed.
        def self.Na__Clip__ApplyAreaBox(session, slots, min, max, text)
            problem = self.Na__Clip__SetBoxOn(session, slots, min, max, text)
            return problem if problem
            slots.each { |slot| Na__CloudSet.Na__Slots__SetVisible(slot, true) unless slot.visible }
            Na__ModelRegistry.Na__Registry__SetVisible(true) unless Na__ModelRegistry.Na__Registry__IsVisible?
            Na__RenderController.Na__Render__RefreshExtents(session)
            model = session.model
            model.active_view.invalidate if model
            self.na_notify_dialog
            nil
        end

        # "2400 x 3600 x 2700 mm": along red, green and blue, in the model's units.
        def self.Na__Clip__SizeText(min, max, model)
            display = Na__UnitContract.Na__Units__ModelDisplay(model)
            sizes = (0..2).map { |i| Na__UnitContract.Na__Units__InchesToPreciseText(max[i] - min[i], display) }
            "#{sizes.join(' x ')} #{display['suffix']}"
        end

        # What the status line says once `slots` have a box.
        def self.Na__Clip__AreaMessage(lead, slots, min, max)
            first = slots.first
            text = "#{lead}: #{self.Na__Clip__SizeText(min, max, first ? first.model : Sketchup.active_model)}."
            text += " Clipping #{self.Na__Clip__Names(slots)}." if first && Na__CloudSet.Na__Slots__Multi?(first.session)
            waiting = slots.reject(&:cloud)
            unless waiting.empty?
                one = waiting.length == 1
                text += " #{self.Na__Clip__Names(waiting)} #{one ? 'is' : 'are'} not loaded; the box is kept for when #{one ? 'it is' : 'they are'} reloaded."
            end
            text
        end

        # Clip Box Around Selection: the box round what is selected (inside a
        # group being edited too), grown by the margin and rounded OUTWARDS
        # onto the grid, for every cloud on show. Returns [problem, note].
        def self.Na__Clip__BoxAroundSelection(session, model)
            return ['The point cloud overlay is not available for this model (SketchUp 2023 or newer is required).', nil] unless session && model
            slots = self.Na__Clip__TargetSlots(session)
            return ['There is no point cloud in this model yet. Import one on the View tab first.', nil] if slots.empty?
            bounds = self.na_selection_bounds(model)
            return ['Select something first (a wall, a room, a few edges), then Clip Box Around Selection fits the clip box round it.', nil] unless bounds
            margin_mm = self.Na__Clip__SelectionMarginMm
            margin = margin_mm / 25.4
            step = self.Na__Clip__DrawGridInches
            min = bounds[0].map { |value| ((value - margin) / step + 1e-9).floor * step }
            max = bounds[1].map { |value| ((value + margin) / step - 1e-9).ceil * step }
            3.times do |axis|
                next if max[axis] - min[axis] >= NA_MIN_GAP_INCHES
                centre = (min[axis] + max[axis]) / 2.0
                min[axis] = ((centre - NA_MIN_GAP_INCHES / 2.0) / step).floor * step
                max[axis] = ((centre + NA_MIN_GAP_INCHES / 2.0) / step).ceil * step
            end
            problem = self.Na__Clip__ApplyAreaBox(session, slots, min, max, 'Clip Box Around Selection')
            return [problem, nil] if problem
            note = self.Na__Clip__AreaMessage('Clip box round the selection', slots, min, max)
            note += " It reaches #{self.na_mm_text(margin_mm)} mm past what is selected." if margin_mm > 0
            [nil, note]
        end

        # [min, max] (model inches) round everything selected, or nil. Bounds
        # are in the open group's own axes, so they go through edit_transform.
        def self.na_selection_bounds(model)
            selection = model.selection
            return nil if selection.nil? || selection.empty?
            transform = model.respond_to?(:edit_transform) ? model.edit_transform : nil
            lo = nil
            hi = nil
            selection.each do |entity|
                next unless entity.respond_to?(:bounds)
                box = entity.bounds
                next if box.nil? || box.empty?
                a = box.min.to_a
                b = box.max.to_a
                [a[0], b[0]].product([a[1], b[1]], [a[2], b[2]]).each do |corner|
                    point = Geom::Point3d.new(*corner)
                    point = point.transform(transform) if transform
                    coords = point.to_a
                    lo = lo ? (0..2).map { |i| [lo[i], coords[i]].min } : coords.dup
                    hi = hi ? (0..2).map { |i| [hi[i], coords[i]].max } : coords.dup
                end
            end
            lo ? [lo, hi] : nil
        end

        # The Clipping tab's Draw a Clip Box card.
        def self.Na__Clip__DrawPayload(session)
            slots = session ? self.Na__Clip__TargetSlots(session) : []
            {
                'isDrawing'   => session && session.clip_draw_tool ? true : false,
                'hasClouds'   => !slots.empty?,
                'multi'       => session ? Na__CloudSet.Na__Slots__Multi?(session) : false,
                'targetsText' => self.Na__Clip__Names(slots),
                'noneShown'   => session ? Na__CloudSet.Na__Slots__All(session).none?(&:visible) : false,
                'gridMm'      => self.Na__Clip__DrawGridMm,
                'gridSteps'   => self.Na__Clip__DrawGridSteps,
                'marginMm'    => self.Na__Clip__SelectionMarginMm
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Preview Drawing (stateless; the tool hands everything in)
    # -------------------------------------------------------------------------

        # Screen points for draw2d, or nil when any point is behind a
        # perspective camera (a part projected box is worse than none).
        def self.na_screen_points(view, points)
            camera = view.camera
            points.map do |point|
                if camera.perspective?
                    return nil unless camera.eye.vector_to(point).dot(camera.zaxis) > 0
                end
                screen = view.screen_coords(point)
                Geom::Point3d.new(screen.x, screen.y, 0)
            end
        end

        def self.na_draw_quad(view, points, fill, border, on_top = true)
            flat = on_top ? self.na_screen_points(view, points) : nil
            view.line_stipple = ''
            view.line_width = 2
            if flat
                view.drawing_color = fill
                view.draw2d(GL_QUADS, flat)
                view.drawing_color = border
                view.draw2d(GL_LINE_LOOP, flat)
            else
                view.drawing_color = fill
                view.draw(GL_QUADS, points)
                view.drawing_color = border
                view.draw(GL_LINE_LOOP, points)
            end
        end

        # near / far: the box's two rectangles, corner for corner.
        def self.na_draw_box(view, near, far, fill, border, on_top = true)
            near2 = on_top ? self.na_screen_points(view, near) : nil
            far2  = near2 ? self.na_screen_points(view, far) : nil
            a, b, draw = far2 ? [near2, far2, :draw2d] : [near, far, :draw]
            sides = (0..3).map { |i| j = (i + 1) % 4; [a[i], a[j], b[j], b[i]] }
            view.line_stipple = ''
            view.drawing_color = fill
            view.send(draw, GL_QUADS, a)
            view.send(draw, GL_QUADS, b)
            sides.each { |quad| view.send(draw, GL_QUADS, quad) }
            view.line_width = 2
            view.drawing_color = border
            view.send(draw, GL_LINE_LOOP, a)
            view.send(draw, GL_LINE_LOOP, b)
            view.send(draw, GL_LINES, (0..3).flat_map { |i| [a[i], b[i]] })
        end

        # The last box drawn, as a thin dashed cage, while it can still be
        # changed by typing.
        def self.na_draw_cage_lines(view, min, max, colour)
            corners = [0, 1].product([0, 1], [0, 1]).map do |ix, iy, iz|
                Geom::Point3d.new(ix.zero? ? min[0] : max[0], iy.zero? ? min[1] : max[1], iz.zero? ? min[2] : max[2])
            end
            edges = [[0, 4], [2, 6], [1, 5], [3, 7], [0, 2], [4, 6], [1, 3], [5, 7], [0, 1], [2, 3], [4, 5], [6, 7]]
            view.line_stipple = '-'
            view.line_width = 1
            view.drawing_color = colour
            view.draw(GL_LINES, edges.flat_map { |a, b| [corners[a], corners[b]] })
            view.line_stipple = ''
        end

        # Red, green and blue arms through a point (one colour for the anchor).
        def self.na_draw_crosshair(view, coords, colour = nil)
            return unless coords
            view.line_stipple = ''
            view.line_width = 2
            3.times do |axis|
                a = coords.dup
                b = coords.dup
                a[axis] -= NA_DRAW_CROSSHAIR_IN
                b[axis] += NA_DRAW_CROSSHAIR_IN
                view.drawing_color = colour || NA_DRAW_AXIS_COLOURS[axis]
                view.draw(GL_LINES, [Geom::Point3d.new(*a), Geom::Point3d.new(*b)])
            end
        end

        # A locked base plane: a long line in the colour of its normal axis.
        def self.na_draw_axis_ray(view, coords, axis)
            return unless coords
            point = Geom::Point3d.new(*coords)
            span = view.pixels_to_model([view.vpwidth, view.vpheight].max, point).to_f * 1.2
            span = 2400.0 unless span > 0
            a = coords.dup
            b = coords.dup
            a[axis] -= span
            b[axis] += span
            view.line_stipple = ''
            view.line_width = 1
            view.drawing_color = NA_DRAW_AXIS_COLOURS[axis]
            view.draw(GL_LINES, [Geom::Point3d.new(*a), Geom::Point3d.new(*b)])
        end

        # CTRL+SHIFT: an open square on the grid point the vertex became, with
        # a dotted leader from the vertex.
        def self.na_draw_grid_mark(view, raw, snapped)
            flat = self.na_screen_points(view, [Geom::Point3d.new(*raw), Geom::Point3d.new(*snapped)])
            return unless flat
            vertex, grid = flat
            view.line_width = 2
            view.drawing_color = NA_DRAW_PINNED
            if Math.hypot(vertex.x - grid.x, vertex.y - grid.y) >= 1.0
                view.line_stipple = '.'
                view.draw2d(GL_LINES, [vertex, grid])
            end
            view.line_stipple = ''
            h = NA_DRAW_MARK_PX
            view.draw2d(GL_LINE_LOOP, [[-h, -h], [h, -h], [h, h], [-h, h]].map { |dx, dy| Geom::Point3d.new(grid.x + dx, grid.y + dy, 0) })
        end

        # Text with a one pixel white halo, readable on the sky and on the cloud.
        def self.na_draw_text(view, x, y, lines, colour = nil)
            Array(lines).each_with_index do |line, index|
                text = line.to_s
                next if text.empty?
                line_y = y + index * NA_DRAW_LINE_PX
                NA_DRAW_HALO_OFFSETS.each do |dx, dy|
                    view.draw_text(Geom::Point3d.new(x + dx, line_y + dy, 0), text, size: NA_DRAW_TEXT_SIZE, bold: true, color: NA_DRAW_HALO)
                end
                view.draw_text(Geom::Point3d.new(x, line_y, 0), text, size: NA_DRAW_TEXT_SIZE, bold: true, color: colour || NA_DRAW_TEXT)
            end
        end

        def self.na_draw_label_at(view, point, lines, dx, dy, colour = nil)
            return unless self.na_in_front?(view, point)
            screen = view.screen_coords(point)
            self.na_draw_text(view, screen.x + dx, screen.y + dy, lines, colour)
        end

        def self.na_draw_edge_label(view, a, b, text, colour)
            middle = Geom::Point3d.new((a.x + b.x) / 2.0, (a.y + b.y) / 2.0, (a.z + b.z) / 2.0)
            self.na_draw_label_at(view, middle, text, 8, -8, colour)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Tool
    # -------------------------------------------------------------------------

        class Na__ClipDrawTool

            NA_DRAG_PX       = 6.0          # below this a press and release is a click
            NA_TAB_KEY       = 9            # no VK_TAB in the SketchUp API
            NA_BACKSPACE_KEY = 8
            NA_DELETE_KEY    = defined?(VK_DELETE) ? VK_DELETE : 46
            NA_CTRL_MASK     = 8            # MK_CONTROL in a mouse event's flags
            NA_SHIFT_MASK    = defined?(CONSTRAIN_MODIFIER_MASK) ? CONSTRAIN_MODIFIER_MASK : 4
            NA_CTRL_KEY      = defined?(COPY_MODIFIER_KEY) ? COPY_MODIFIER_KEY : 17
            NA_SHIFT_KEY     = defined?(CONSTRAIN_MODIFIER_KEY) ? CONSTRAIN_MODIFIER_KEY : 16
            NA_ARROW_AXES    = {
                (defined?(VK_RIGHT) ? VK_RIGHT : 39) => 'x',
                (defined?(VK_LEFT)  ? VK_LEFT  : 37) => 'y',
                (defined?(VK_UP)    ? VK_UP    : 38) => 'z'
            }.freeze
            NA_DOWN_KEY      = defined?(VK_DOWN) ? VK_DOWN : 40
            NA_VCB_KEYS      = ((48..57).to_a + (96..111).to_a + [187, 188, 189, 190]).freeze   # digits, + , - .
            NA_PLANE_SWITCH  = 0.6          # a new base plane must be clearly better, so it never flaps
            NA_SLOT_WORDS    = ['first side', 'second side', 'height'].freeze

            # session: the model's cloud session. The box goes to the clouds on
            # show when it is finished, so the tool is bound to no one cloud.
            def initialize(session)
                @session    = session
                @ip         = Sketchup::InputPoint.new
                @ip_anchor  = Sketchup::InputPoint.new
                @plane_lock = 'auto'
                @plane      = 'xy'
                @axis_lock  = nil
                @ctrl       = false
                @shift      = false
                @tab_held   = false
                @mouse      = nil    # [x, y] of the last mouse event
                @cursor     = nil    # where the cursor snaps to (model inches)
                @cursor_raw = nil    # where it was before snapping
                @last       = nil    # the box last drawn: { anchor, plane, sign, size, min, max, ids }
                @done_text  = nil    # what the status line says about it
                @ip_in_tool = false  # InputPoint#draw refused from the overlay: Tool#draw draws it
                @exit_scheduled = false
                self.na_reset
            end

            def na_session
                @session
            end

            def na_state
                @state
            end

            # -----------------------------------------------------------------
            # Lifecycle
            # -----------------------------------------------------------------

            def activate
                @session.clip_draw_tool = self
                @ctrl = false
                @shift = false
                self.na_reset
                Na__RenderController.Na__Render__RefreshExtents(@session)
                self.na_refresh_texts(true)
                Sketchup.active_model.active_view.invalidate
                Na__ClipBox.na_notify_dialog
            end

            def deactivate(view)
                @session.clip_draw_tool = nil if @session.clip_draw_tool.equal?(self)
                Sketchup.vcb_label = ''
                Sketchup.vcb_value = ''
                Na__RenderController.Na__Render__RefreshExtents(@session)
                view.invalidate
                Na__ClipBox.na_notify_dialog
            end

            # A key or modifier released while another tool (Orbit) had the
            # mouse must not stay stuck.
            def resume(view)
                @ctrl = false
                @shift = false
                @typing = false
                self.na_refresh_texts(true)
                view.invalidate
            end

            def suspend(view)
                view.invalidate
            end

            def onCancel(reason, view)
                @typing = false
                if @state != :idle
                    self.na_reset
                    self.na_refresh_texts
                    view.invalidate
                    return
                end
                self.na_schedule_exit if reason == 0
                view.invalidate
            end

            def enableVCB?
                true
            end

            # -----------------------------------------------------------------
            # Mouse
            # -----------------------------------------------------------------

            def onMouseMove(flags, x, y, view)
                self.na_sync_modifiers(flags)
                self.na_update_cursor(view, x, y)
                Na__RenderController.Na__Render__RefreshExtents(@session) unless @state == :idle   # the near and far planes take in the box
                self.na_refresh_texts
                view.tooltip = @ip.tooltip if self.na_inference_driving? && @ip.valid?
                view.invalidate
            end

            def onLButtonDown(flags, x, y, view)
                @typing = false
                self.na_sync_modifiers(flags)
                case @state
                when :idle
                    position = self.na_ip_position(view, x, y)
                    return unless position
                    self.na_clear_pins
                    @anchor = self.na_snap(position)
                    @ip_anchor.copy!(@ip)
                    @cursor_raw = position
                    @cursor = @anchor.dup
                    @state = :base
                    @plane = @plane_lock unless @plane_lock == 'auto'
                    @size = [0.0, 0.0, 0.0]
                    @sign = [1.0, 1.0, 1.0]
                    @press = [x, y]
                    @last = nil                      # a new box: the last one can no longer be typed over
                    @done_text = nil
                when :base
                    @press = nil
                    self.na_update_cursor(view, x, y)
                    self.na_finish_base(view)
                when :height
                    @press = nil
                    self.na_update_cursor(view, x, y)
                    self.na_commit(view)
                end
                self.na_refresh_texts
                view.invalidate
            end

            # Press, drag and release draws the base in one gesture; a release
            # that barely moved is a click, so click, move, click works too.
            def onLButtonUp(flags, x, y, view)
                self.na_sync_modifiers(flags)
                press = @press
                @press = nil
                return unless press && @state == :base
                return if (x - press[0]).abs + (y - press[1]).abs < NA_DRAG_PX
                self.na_update_cursor(view, x, y)
                return unless self.na_base_valid?
                self.na_finish_base(view)
                self.na_refresh_texts
                view.invalidate
            end

            # A double click arrives as down, up, double click, up, so the first
            # down has usually done the work: only a stage that is ready to
            # finish is finished here, and nothing beeps.
            def onLButtonDoubleClick(flags, x, y, view)
                self.na_sync_modifiers(flags)
                return if @state == :idle
                self.na_update_cursor(view, x, y)
                if @state == :base
                    self.na_finish_base(view) if self.na_base_valid?
                elsif self.na_height_valid?
                    self.na_commit(view)
                end
                self.na_refresh_texts
                view.invalidate
            end

            # Enter with nothing typed finishes the stage.
            def onReturn(view)
                case @state
                when :base   then self.na_finish_base(view)
                when :height then self.na_commit(view)
                end
                self.na_refresh_texts
                view.invalidate
            end

            # The right click menu: the base plane, the snap grid, finish.
            def getMenu(menu, _flags = 0, _x = 0, _y = 0, _view = nil)
                planes = menu.add_submenu('Base Plane')
                NA_DRAW_PLANE_CYCLE.each do |key|
                    label = key == 'auto' ? 'Auto (follows the drag)' : NA_DRAW_PLANES[key]['label']
                    item = planes.add_item(label) { self.na_set_plane_lock(key, Sketchup.active_model.active_view) }
                    planes.set_validation_proc(item) { @plane_lock == key ? MF_CHECKED : MF_UNCHECKED }
                end
                grid = menu.add_submenu('Snap Grid')
                Na__ClipBox.Na__Clip__DrawGridSteps.each do |mm|
                    item = grid.add_item("#{Na__ClipBox.na_mm_text(mm)} mm") do
                        Na__ClipBox.Na__Clip__SetDrawGridMm(mm)
                        self.na_refresh_texts(true)
                        Na__ClipBox.na_notify_dialog
                    end
                    grid.set_validation_proc(item) { (Na__ClipBox.Na__Clip__DrawGridMm - mm).abs < 1e-9 ? MF_CHECKED : MF_UNCHECKED }
                end
                menu.add_separator
                menu.add_item('Finish Drawing') { self.na_schedule_exit }
                true
            end

            # -----------------------------------------------------------------
            # Keyboard and the Measurements box
            # -----------------------------------------------------------------

            def onKeyDown(key, _repeat, _flags, view)
                if key == NA_CTRL_KEY && !@ctrl
                    @ctrl = true
                    return self.na_after_key(view)
                end
                if key == NA_SHIFT_KEY && !@shift
                    @shift = true
                    return self.na_after_key(view)
                end
                axis = NA_ARROW_AXES[key]
                if axis || key == NA_DOWN_KEY
                    self.na_lock_axis(axis, view)
                    return false
                end
                if key == NA_TAB_KEY && !@tab_held
                    @tab_held = true
                    self.na_cycle_plane(view)
                    return false
                end
                if key == NA_BACKSPACE_KEY || key == NA_DELETE_KEY
                    return false if @typing                       # mid entry this is a typo fix
                    self.na_step_back(view)
                    return false
                end
                @typing = true if NA_VCB_KEYS.include?(key)
                false
            end

            def onKeyUp(key, _repeat, _flags, view)
                @tab_held = false if key == NA_TAB_KEY
                if key == NA_CTRL_KEY && @ctrl
                    @ctrl = false
                    self.na_after_key(view)
                end
                if key == NA_SHIFT_KEY && @shift
                    @shift = false
                    self.na_after_key(view)
                end
                false
            end

            # Base: W | W,H | ,H | W,H,D. Height: D | +D | -D. After a box:
            # W,H,D changes it. Lengths in the model's units (a bare number) or
            # with a unit ("2.4m").
            def onUserText(text, view)
                @typing = false
                tokens = self.na_parse_entry(text)
                case @state
                when :base   then self.na_type_base(tokens, view)
                when :height then self.na_type_height(tokens, view)
                else              self.na_type_revise(tokens, view)
                end
                self.na_refresh_texts(true)
                view.invalidate
            rescue ArgumentError => error
                UI.beep
                Sketchup.status_text = error.message
            end

            # -----------------------------------------------------------------
            # Drawing (the overlay calls na_draw_overlay; Tool#draw is the
            # stand in while the overlay is switched off)
            # -----------------------------------------------------------------

            def draw(view)
                if self.na_overlay_draws?(view)
                    @ip.draw(view) if @ip_in_tool && self.na_inference_driving? && @ip.valid? && @ip.display?
                    return
                end
                self.na_draw_preview(view, true)
            end

            def na_draw_overlay(view)
                self.na_draw_preview(view, false)
            end

            def getExtents
                box = Geom::BoundingBox.new
                points = self.na_extent_points
                box.add(*points) unless points.empty?
                box
            end

            # Every point the preview draws at (the overlay's extents too).
            def na_extent_points
                points = []
                points << Geom::Point3d.new(*@cursor) if @cursor
                if @anchor
                    rect = self.na_rect_points
                    points.concat(rect)
                    points.concat(self.na_far_points(rect)) if @state == :height
                end
                if @last && @state == :idle
                    points << Geom::Point3d.new(*@last['min']) << Geom::Point3d.new(*@last['max'])
                end
                points
            end

            # -----------------------------------------------------------------
            # Internals: state
            # -----------------------------------------------------------------

            def na_reset
                @state      = :idle
                @anchor     = nil
                @press      = nil
                @typing     = false
                @size       = [0.0, 0.0, 0.0]
                @sign       = [1.0, 1.0, 1.0]
                @last_status = nil
                @last_vcb    = nil
                self.na_clear_pins
            end

            def na_clear_pins
                @pinned = {}
                @pin_order = []
            end

            def na_pin(slot)
                @pin_order.delete(slot)
                @pin_order << slot
                @pinned[slot] = true
            end

            def na_pinned?(slot)
                @pinned[slot] ? true : false
            end

            def na_base_valid?
                @size[0] >= NA_MIN_GAP_INCHES && @size[1] >= NA_MIN_GAP_INCHES
            end

            def na_height_valid?
                @size[2] >= NA_MIN_GAP_INCHES
            end

            def na_signed
                (0..2).map { |slot| @size[slot] * @sign[slot] }
            end

            def na_min_side_text
                "#{(NA_MIN_GAP_INCHES * 25.4).round} mm"
            end

            # The base is settled: on to the height.
            def na_finish_base(view)
                unless self.na_base_valid?
                    UI.beep
                    Sketchup.status_text = "Drag further: each side of a clip box must be at least #{self.na_min_side_text}."
                    return false
                end
                @state = :height
                unless self.na_pinned?(2)
                    @size[2] = 0.0
                    @sign[2] = 1.0
                end
                self.na_update_cursor(view, *@mouse) if @mouse
                true
            end

            # The box is finished: it clips every cloud on show.
            def na_commit(view)
                unless self.na_base_valid? && self.na_height_valid?
                    UI.beep
                    Sketchup.status_text = "Drag further: each side of a clip box must be at least #{self.na_min_side_text}."
                    return false
                end
                min, max = Na__ClipBox.Na__Clip__DrawCorners(@anchor, @plane, self.na_signed)
                slots = Na__ClipBox.Na__Clip__TargetSlots(@session)
                problem = Na__ClipBox.Na__Clip__ApplyAreaBox(@session, slots, min, max, 'Draw Clip Box')
                if problem
                    UI.beep
                    Sketchup.status_text = problem
                    return false
                end
                @last = { 'anchor' => @anchor.dup, 'plane' => @plane, 'sign' => @sign.dup, 'size' => @size.dup,
                          'min' => min, 'max' => max, 'ids' => slots.map(&:id) }
                @done_text = Na__ClipBox.Na__Clip__AreaMessage('Clip box drawn', slots, min, max)
                self.na_reset
                view.invalidate
                true
            end

            # The box last drawn can be typed over while every cloud it went to
            # still has exactly that box (an Undo, or any other change, ends it).
            def na_revise_slots
                return nil unless @last
                slots = @last['ids'].map { |id| Na__CloudSet.Na__Slots__Find(@session, id) }
                return nil if slots.empty? || slots.any?(&:nil?)
                same = slots.all? do |slot|
                    Na__ClipBox.Na__Clip__Ensure(slot)
                    clip = slot.clip
                    clip && clip['enabled'] && (0..2).all? { |i| (clip['min'][i] - @last['min'][i]).abs < 1e-6 && (clip['max'][i] - @last['max'][i]).abs < 1e-6 }
                end
                same ? slots : nil
            end

            def na_schedule_exit
                return if @exit_scheduled
                @exit_scheduled = true
                UI.start_timer(0, false) do
                    @exit_scheduled = false
                    model = Sketchup.active_model
                    model.select_tool(nil) if model && @session.clip_draw_tool.equal?(self)
                end
            end

            # -----------------------------------------------------------------
            # Internals: where the cursor is
            # -----------------------------------------------------------------

            # Three sources, each the steadiest for its stage: SketchUp's
            # inference while waiting and on an Auto plane, the pick ray on a
            # locked plane, the pick ray against the height line while drawing
            # the height. CTRL always asks for the inference.
            def na_update_cursor(view, x, y)
                @mouse = [x, y]
                point = if @ctrl
                            self.na_ip_position(view, x, y)
                        elsif @state == :height
                            self.na_point_on_height_line(view, x, y)
                        elsif @state == :base && @plane_lock != 'auto'
                            self.na_point_on_plane(view, x, y, @plane_lock)
                        else
                            self.na_ip_position(view, x, y)
                        end
                point ||= self.na_ip_position(view, x, y)
                return unless point
                @cursor_raw = point
                @cursor = self.na_snap(point)
                self.na_recalculate
            end

            def na_ip_position(view, x, y)
                if @state == :idle || !@ip_anchor.valid?
                    @ip.pick(view, x, y)
                else
                    @ip.pick(view, x, y, @ip_anchor)
                end
                @ip.valid? ? @ip.position.to_a.map(&:to_f) : nil
            rescue StandardError
                nil
            end

            def na_point_on_plane(view, x, y, plane)
                return nil unless @anchor
                normal = NA_DRAW_PLANES[plane]['axes'][2]
                origin, direction = view.pickray(x, y)
                o = origin.to_a
                d = direction.to_a
                return nil if d[normal].abs < 1e-12
                t = (@anchor[normal] - o[normal]) / d[normal]
                return nil unless t > 0                           # behind the eye: a box turned inside out
                (0..2).map { |i| o[i] + d[i] * t }
            end

            # The point on the height line (through the anchor, along the base
            # plane's normal) nearest the pick ray.
            def na_point_on_height_line(view, x, y)
                return nil unless @anchor
                normal = NA_DRAW_PLANES[@plane]['axes'][2]
                axis = [0.0, 0.0, 0.0]
                axis[normal] = 1.0
                origin, direction = view.pickray(x, y)
                o = origin.to_a
                d = direction.to_a
                w0 = (0..2).map { |i| @anchor[i] - o[i] }
                b = (0..2).sum { |i| axis[i] * d[i] }
                c = (0..2).sum { |i| d[i] * d[i] }
                dd = (0..2).sum { |i| axis[i] * w0[i] }
                e = (0..2).sum { |i| d[i] * w0[i] }
                denom = c - b * b
                return nil if denom.abs < 1e-9                    # looking straight along the height line
                s = (b * e - c * dd) / denom
                t = (e - b * dd) / denom
                return nil unless t > 0
                point = @anchor.dup
                point[normal] += s
                point
            end

            # Grid, unless CTRL alone asks for the inference as it lands.
            def na_snap(point)
                return point.dup if self.na_snap_mode == :vertex
                Na__ClipBox.Na__Clip__SnapPoint(point)
            end

            def na_snap_mode
                return :grid unless @ctrl
                @shift ? :vertex_grid : :vertex
            end

            def na_inference_driving?
                @ctrl || @state == :idle || (@state == :base && @plane_lock == 'auto')
            end

            def na_recalculate
                return unless @anchor && @cursor
                delta = (0..2).map { |i| @cursor[i] - @anchor[i] }
                case @state
                when :base
                    @plane = @plane_lock == 'auto' ? self.na_infer_plane(delta) : @plane_lock
                    u, v, = NA_DRAW_PLANES[@plane]['axes']
                    self.na_take(0, delta[u]) unless self.na_pinned?(0)
                    self.na_take(1, delta[v]) unless self.na_pinned?(1)
                when :height
                    self.na_take(2, delta[NA_DRAW_PLANES[@plane]['axes'][2]]) unless self.na_pinned?(2)
                end
            end

            def na_take(slot, travel)
                @sign[slot] = travel < 0 ? -1.0 : 1.0
                @size[slot] = travel.abs
            end

            # The axis the drag moved least along is the plane's normal; the
            # plane only changes when another is clearly better.
            def na_infer_plane(delta)
                d = delta.map(&:abs)
                candidate = if d[2] <= d[0] && d[2] <= d[1] then 'xy'
                            elsif d[1] <= d[0] && d[1] <= d[2] then 'xz'
                            else 'yz'
                            end
                return candidate if candidate == @plane
                current = d[NA_DRAW_PLANES[@plane]['axes'][2]]
                d[NA_DRAW_PLANES[candidate]['axes'][2]] > current * NA_PLANE_SWITCH ? @plane : candidate
            end

            def na_sync_modifiers(flags)
                bits = flags.to_i
                @ctrl  = (bits & NA_CTRL_MASK) != 0
                @shift = (bits & NA_SHIFT_MASK) != 0
            end

            def na_after_key(view)
                self.na_update_cursor(view, *@mouse) if @mouse
                self.na_refresh_texts
                view.invalidate
                false
            end

            # -----------------------------------------------------------------
            # Internals: planes, arrows, stepping back
            # -----------------------------------------------------------------

            # axis: the arrow that locked it ('x', 'y', 'z'), drawn as a line
            # through the corner; nil for Tab and the menu.
            def na_set_plane_lock(key, view, axis = nil)
                if @state == :height
                    UI.beep
                    Sketchup.status_text = 'The base is set already. Backspace goes back to it to change its plane.'
                    return
                end
                @plane_lock = key
                @plane = key unless key == 'auto'
                @axis_lock = key == 'auto' ? nil : axis
                self.na_update_cursor(view, *@mouse) if @mouse && @state != :idle
                self.na_refresh_texts(true)
                view.invalidate
            end

            def na_cycle_plane(view)
                index = NA_DRAW_PLANE_CYCLE.index(@plane_lock) || 0
                self.na_set_plane_lock(NA_DRAW_PLANE_CYCLE[(index + 1) % NA_DRAW_PLANE_CYCLE.length], view)
            end

            # An arrow names the normal of the base plane (Up: plan); the same
            # arrow again, or Down, lets the drag choose again.
            def na_lock_axis(axis, view)
                return self.na_set_plane_lock('auto', view) if axis.nil? || axis == @axis_lock
                self.na_set_plane_lock(NA_DRAW_AXIS_PLANE[axis], view, axis)
            end

            def na_step_back(view)
                slot = @pin_order.pop
                if slot
                    @pinned.delete(slot)
                    self.na_update_cursor(view, *@mouse) if @mouse
                    Sketchup.status_text = "The #{NA_SLOT_WORDS[slot]} follows the mouse again."
                    view.invalidate
                    return
                end
                case @state
                when :height
                    @state = :base
                    @size[2] = 0.0
                when :base
                    self.na_reset
                end
                self.na_refresh_texts(true)
                view.invalidate
            end

            # -----------------------------------------------------------------
            # Internals: typed sizes
            # -----------------------------------------------------------------

            # [[sign, inches] or nil, ...]; sign nil (absolute), :plus or :minus.
            def na_parse_entry(text)
                parts = text.to_s.split(',', -1)
                raise ArgumentError, 'Type a size, for example 2400,3600,2700.' if parts.empty? || parts.all? { |part| part.strip.empty? }
                raise ArgumentError, 'A clip box takes at most three sizes: W,H,D.' if parts.length > 3
                display = Na__UnitContract.Na__Units__ModelDisplay(Sketchup.active_model)
                parts.map do |part|
                    token = part.strip
                    next nil if token.empty?
                    sign = { '+' => :plus, '-' => :minus }[token[0]]
                    token = token[1..-1].strip if sign
                    [sign, Na__UnitContract.Na__Units__ParseDisplayLength(token, display)]
                end
            end

            # Sizes for `slots` (0, 1: the base's sides, 2: the height) against
            # the live ones, token for slot; +/- add to the live size.
            def na_resolve(tokens, live, slots)
                sizes = live.each_with_index.map do |value, index|
                    token = tokens[index]
                    next value.abs unless token
                    sign, amount = token
                    case sign
                    when :plus  then value.abs + amount
                    when :minus then value.abs - amount
                    else             amount
                    end
                end
                sizes.each_with_index do |value, index|
                    next if tokens[index].nil? || value >= NA_MIN_GAP_INCHES
                    raise ArgumentError, "The #{NA_SLOT_WORDS[slots[index]]} would be too small: each side of a clip box must be at least #{self.na_min_side_text}."
                end
                sizes
            end

            # One bare value goes to the first side still following the mouse,
            # so 2400 then 3600 pins one side and then the other. A comma keeps
            # an entry positional (",3600" is the second side).
            def na_align_single(tokens, slots)
                return tokens unless tokens.length == 1
                position = slots.index { |slot| !self.na_pinned?(slot) } || 0
                Array.new(position, nil) + tokens
            end

            def na_apply_typed(tokens, slots)
                tokens = self.na_align_single(tokens, slots)
                live = slots.map { |slot| @size[slot] }
                sizes = self.na_resolve(tokens, live, slots)
                slots.each_with_index do |slot, index|
                    next unless tokens[index]
                    @size[slot] = sizes[index]
                    self.na_pin(slot)
                end
            end

            def na_type_base(tokens, view)
                if tokens.length == 3
                    self.na_apply_typed(tokens, [0, 1, 2])
                    return self.na_commit(view) if [0, 1, 2].all? { |slot| self.na_pinned?(slot) }
                else
                    self.na_apply_typed(tokens, [0, 1])
                end
                self.na_finish_base(view) if self.na_pinned?(0) && self.na_pinned?(1)
            end

            def na_type_height(tokens, view)
                raise ArgumentError, 'The height takes one value, for example 2700 or +300.' if tokens.length > 1 || tokens.first.nil?
                self.na_apply_typed(tokens, [2])
                self.na_commit(view)
            end

            # W,H,D straight after a box changes it, from the same corner and
            # in the same directions, for the same clouds.
            def na_type_revise(tokens, view)
                slots = self.na_revise_slots
                unless slots
                    raise ArgumentError, 'Click the first corner of a box before typing a size.' unless @last
                    @last = nil
                    raise ArgumentError, 'That box has been changed since it was drawn. Draw a new one.'
                end
                sizes = self.na_resolve(tokens, @last['size'], [0, 1, 2])
                signed = (0..2).map { |slot| sizes[slot] * @last['sign'][slot] }
                min, max = Na__ClipBox.Na__Clip__DrawCorners(@last['anchor'], @last['plane'], signed)
                problem = Na__ClipBox.Na__Clip__ApplyAreaBox(@session, slots, min, max, 'Change Clip Box')
                if problem
                    UI.beep
                    Sketchup.status_text = problem
                    return
                end
                @last = @last.merge('size' => sizes, 'min' => min, 'max' => max)
                @done_text = Na__ClipBox.Na__Clip__AreaMessage('Clip box changed', slots, min, max)
            end

            # -----------------------------------------------------------------
            # Internals: the status line and the Measurements box
            # -----------------------------------------------------------------

            def na_length_text(inches)
                inches.to_f.to_l.to_s
            end

            def na_size_text(slot)
                text = Na__UnitContract.Na__Units__InchesToPreciseText(@size[slot], self.na_display)
                self.na_pinned?(slot) ? "[#{text}]" : text
            end

            def na_display
                Na__UnitContract.Na__Units__ModelDisplay(Sketchup.active_model)
            end

            def na_plane_text
                label = NA_DRAW_PLANES[@plane_lock == 'auto' ? @plane : @plane_lock]['label']
                @plane_lock == 'auto' ? "#{label} (Auto)" : "#{label} (locked)"
            end

            def na_snap_text
                grid = "#{Na__ClipBox.na_mm_text(Na__ClipBox.Na__Clip__DrawGridMm)} mm grid"
                case self.na_snap_mode
                when :vertex      then 'Ctrl: snapping to the model, off the grid'
                when :vertex_grid then "Ctrl+Shift: snapping to the model, then the #{grid}"
                else                   "Snapping to the #{grid}; Ctrl snaps to the model"
                end
            end

            def na_status_text
                suffix = self.na_display['suffix']
                case @state
                when :base
                    "Draw Clip Box: #{self.na_size_text(0)} x #{self.na_size_text(1)} #{suffix} on the #{self.na_plane_text} plane. " \
                    "Release, or click, to set the base, then pull the height. Type W,H or W,H,D. #{self.na_snap_text}. " \
                    'Tab changes the plane. Backspace steps back. Esc cancels.'
                when :height
                    "Draw Clip Box: #{self.na_size_text(0)} x #{self.na_size_text(1)} x #{self.na_size_text(2)} #{suffix}. " \
                    "Click to clip to it, or type the height (+300, -50 change it). #{self.na_snap_text}. Backspace steps back. Esc cancels."
                else
                    lead = @done_text ? "#{@done_text} " : ''
                    more = self.na_revise_slots ? 'Type W,H,D to change it, or click the first corner of the next box.' : 'Click the first corner, or press and drag the base rectangle.'
                    "#{lead}#{more} Plane: #{self.na_plane_text}. #{self.na_snap_text}. Esc leaves the tool."
                end
            end

            def na_vcb
                case @state
                when :base   then ['Sides', [0, 1].map { |slot| self.na_length_text(@size[slot]) }.join(',')]
                when :height then [@plane == 'xy' ? 'Height' : 'Depth', self.na_length_text(@size[2])]
                else
                    return ['Box', @last['size'].map { |value| self.na_length_text(value) }.join(',')] if @last && self.na_revise_slots
                    ['Box', '']
                end
            end

            # Sketchup.status_text is a native call made on every mouse move:
            # it is only sent when the text changes.
            def na_refresh_texts(force = false)
                status = self.na_status_text
                if force || status != @last_status
                    Sketchup.status_text = status
                    @last_status = status
                end
                label, value = self.na_vcb
                return unless force || [label, value] != @last_vcb
                Sketchup.vcb_label = label
                Sketchup.vcb_value = value
                @last_vcb = [label, value]
            end

            # -----------------------------------------------------------------
            # Internals: the preview
            # -----------------------------------------------------------------

            # The overlay draws the preview over the cloud picture, unless it
            # is switched off or paused after a fault.
            def na_overlay_draws?(view)
                model = view.respond_to?(:model) ? view.model : Sketchup.active_model
                overlay = Na__ModelRegistry.Na__Registry__FindOverlay(model)
                overlay && overlay.enabled? && !@session.fault ? true : false
            rescue StandardError
                false
            end

            def na_rect_points
                u, v, = NA_DRAW_PLANES[@plane]['axes']
                su = @size[0] * @sign[0]
                sv = @size[1] * @sign[1]
                [[0.0, 0.0], [su, 0.0], [su, sv], [0.0, sv]].map do |du, dv|
                    coords = @anchor.dup
                    coords[u] += du
                    coords[v] += dv
                    Geom::Point3d.new(*coords)
                end
            end

            def na_far_points(rect)
                n = NA_DRAW_PLANES[@plane]['axes'][2]
                offset = @size[2] * @sign[2]
                rect.map do |point|
                    coords = point.to_a
                    coords[n] += offset
                    Geom::Point3d.new(*coords)
                end
            end

            def na_draw_preview(view, from_tool)
                self.na_draw_inference(view, from_tool)
                if @axis_lock
                    Na__ClipBox.na_draw_axis_ray(view, @anchor || @cursor, Na__ClipBox::NA_DRAW_AXIS_INDEX[@axis_lock])
                end
                if @state == :idle
                    if @last && self.na_revise_slots
                        Na__ClipBox.na_draw_cage_lines(view, @last['min'], @last['max'], Na__ClipBox::NA_DRAW_LAST_BORDER)
                    end
                    Na__ClipBox.na_draw_crosshair(view, @cursor)
                else
                    self.na_draw_shape(view)
                    Na__ClipBox.na_draw_crosshair(view, @anchor, Na__ClipBox::NA_DRAW_ANCHOR)
                end
                if self.na_snap_mode == :vertex_grid && @cursor_raw && @cursor
                    Na__ClipBox.na_draw_grid_mark(view, @cursor_raw, @cursor)
                end
            rescue StandardError => error
                Na__DebugTools.Na__Debug__Warn("The clip box being drawn could not be shown: #{error.message}")
            end

            # SketchUp's own inference marker, while the inference drives the
            # cursor. InputPoint#draw is a tool's to call: if it refuses from
            # the overlay, Tool#draw draws it from then on.
            def na_draw_inference(view, from_tool)
                return unless self.na_inference_driving? && @ip.valid? && @ip.display?
                return if !from_tool && @ip_in_tool
                @ip.draw(view)
            rescue StandardError
                @ip_in_tool = true
            end

            def na_draw_shape(view)
                rect = self.na_rect_points
                unless self.na_base_valid?
                    view.line_stipple = '-'
                    view.line_width = 2
                    view.drawing_color = Na__ClipBox::NA_DRAW_PLANE_BORDER
                    view.draw(GL_LINE_LOOP, rect)
                    view.line_stipple = ''
                    return
                end
                lines = []
                suffix = self.na_display['suffix']
                if @state == :height && self.na_height_valid?
                    far = self.na_far_points(rect)
                    Na__ClipBox.na_draw_box(view, rect, far, Na__ClipBox::NA_DRAW_BOX_FILL, Na__ClipBox::NA_DRAW_BOX_BORDER)
                    self.na_draw_side_label(view, rect[1], far[1], 2)
                    lines << "#{self.na_size_text(0)} x #{self.na_size_text(1)} x #{self.na_size_text(2)} #{suffix}"
                    anchor = far[2]
                else
                    Na__ClipBox.na_draw_quad(view, rect, Na__ClipBox::NA_DRAW_PLANE_FILL, Na__ClipBox::NA_DRAW_PLANE_BORDER)
                    lines << "#{self.na_size_text(0)} x #{self.na_size_text(1)} #{suffix}"
                    lines << "#{NA_DRAW_PLANES[@plane]['label']} plane"
                    anchor = rect[2]
                end
                self.na_draw_side_label(view, rect[0], rect[1], 0)
                self.na_draw_side_label(view, rect[1], rect[2], 1)
                if Na__CloudSet.Na__Slots__Multi?(@session)
                    lines << "Clips #{Na__ClipBox.Na__Clip__Names(Na__ClipBox.Na__Clip__TargetSlots(@session))}"
                end
                Na__ClipBox.na_draw_label_at(view, anchor, lines, 14, -26 - 16 * (lines.length - 1))
            end

            def na_draw_side_label(view, a, b, slot)
                colour = self.na_pinned?(slot) ? Na__ClipBox::NA_DRAW_PINNED : Na__ClipBox::NA_DRAW_ACCENT
                Na__ClipBox.na_draw_edge_label(view, a, b, self.na_size_text(slot), colour)
            end

        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
