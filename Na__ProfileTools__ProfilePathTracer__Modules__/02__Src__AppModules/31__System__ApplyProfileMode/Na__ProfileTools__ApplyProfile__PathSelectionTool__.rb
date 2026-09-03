# =============================================================================
# NA PROFILE TOOLS - APPLY PROFILE - PATH SELECTION TOOL
# =============================================================================
#
# FILE       : Na__ProfileTools__ApplyProfile__PathSelectionTool__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__PathSelectionTool
# PURPOSE    : Interactive free-draw path tool with live profile sweep preview
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    class Na__PathSelectionTool
        include Na__ProfileTools__ProfilePathTracer::Na__AxisLockMixin

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_STATUS_PROMPT_KEY              = SB_PROMPT
        NA_DEFAULT_CROSSHAIR_SIZE         = 300.mm
        NA_GRID_SIZE                      = 1.mm
        NA_INCH_TO_MM                     = 25.4
        NA_TAB_KEY                        = 9
        NA_SHIFT_KEY                      = CONSTRAIN_MODIFIER_KEY
        NA_VK_BACKSPACE                   = 8
        NA_POINT_MERGE_TOLERANCE          = 0.001
        NA_LOOP_CLOSE_SCREEN_TOLERANCE_PX = 14.0
        NA_LOOP_CLOSE_WORLD_TOLERANCE     = 5.mm
        NA_SQUARE_SNAP_SCREEN_TOLERANCE_PX = 12.0
        NA_LOOP_CLOSE_DYNAMIC_PX          = 16.0
        NA_LOOP_CLOSE_SIZE_FRACTION       = 0.01
        NA_LOOP_CLOSE_MAX_FRACTION        = 0.10

        # Windows virtual-key codes that plausibly begin a VCB entry: main-row
        # digits, the numeric keypad (digits + operators + decimal), and the OEM
        # =/+ , - . keys. Seeing one of these arms typing mode, which is what
        # keeps Backspace editing the typed value instead of deleting waypoints.
        NA_VCB_ENTRY_KEYS                 = ((48..57).to_a + (96..111).to_a + [187, 188, 189, 190]).freeze

        # Cursor further than this from the last waypoint (in screen pixels)
        # means the user is tracking a direction, so typed lengths apply to the
        # live segment; anything closer reads as "still on the point I just
        # clicked" and typed lengths adjust the last committed segment instead.
        NA_VCB_DIRECTION_MIN_PX           = 10.0

        # Mouse travel (px) that disarms revise mode after a typed placement.
        NA_VCB_REVISE_DISARM_PX           = 8.0

        # Length of the synthetic one-segment path used to orient the datum face
        # before any waypoint exists. Only its direction matters — the segment is
        # never drawn and never reaches the build.
        NA_DATUM_PROBE_LENGTH             = 1000.mm

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Live Tool Registry
    # -------------------------------------------------------------------------

        # The dialog's Reverse button has to reach the tool instance that is
        # already running, and SketchUp exposes no way to fetch the active tool
        # object back from the model. The class keeps its own reference instead.
        # Guarded so a hot reload mid-draw cannot orphan a live tool.
        @na_active_tool = nil unless defined?(@na_active_tool)

        def self.Na__PathSelectionTool__RegisterActiveTool(tool)
            @na_active_tool = tool
        end

        def self.Na__PathSelectionTool__ClearActiveTool(tool)
            @na_active_tool = nil if @na_active_tool.equal?(tool)
        end

        # Dialog -> tool. Returns false when no interactive tool is running, in
        # which case the dialog's own state is the only thing that needed updating.
        def self.Na__PathSelectionTool__ApplyReverseDirection(reverse_direction)
            tool = @na_active_tool
            return false unless tool
            tool.Na__PathSelectionTool__SetReverseDirection(reverse_direction)
            true
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Initialization / State
    # -------------------------------------------------------------------------

        def initialize(profile_key, profile_data, toggle_states = {}, initial_rotation_step = 0, reverse_direction = false, origin_offset = nil)
            @na_profile_key = profile_key
            @na_profile_data = profile_data || {}
            @na_toggle_states = toggle_states || {}
            @na_rotation_step = initial_rotation_step.to_i % 4
            @na_reverse_direction = reverse_direction == true
            @na_origin_offset = origin_offset
            @na_key_tab_held = false
            @na_key_shift_held = false
            @na_crosshair_size = NA_DEFAULT_CROSSHAIR_SIZE

            @na_vcb_typing_active = false
            @na_vcb_revise_active = false
            @na_vcb_revise_anchor_x = nil
            @na_vcb_revise_anchor_y = nil
            @na_last_mouse_x = nil
            @na_last_mouse_y = nil
            @na_last_vcb_value_text = nil

            @na_input_point = Sketchup::InputPoint.new
            @na_previous_input_point = Sketchup::InputPoint.new
            @na_cursor_point = nil
            @na_square_snap_reference = nil
            @na_loop_close_armed = false
            @na_waypoints = []
            @na_state = :picking_start

            @na_cache_path = nil
            @na_cache_sweep_segments = []
            @na_cache_profile_polyline = []
            @na_cache_total_length_mm = 0.0
            @na_last_status_text = nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Tool Lifecycle
    # -------------------------------------------------------------------------

        def activate
            @na_state = :picking_start
            @na_waypoints = []
            @na_cursor_point = nil
            @na_square_snap_reference = nil
            @na_loop_close_armed = false
            @na_key_tab_held = false
            @na_key_shift_held = false
            @na_vcb_typing_active = false
            @na_vcb_revise_active = false
            @na_previous_input_point = Sketchup::InputPoint.new
            self.Na__AxisLock__InitState
            self.Na__PathSelectionTool__ResetPreviewCache
            Sketchup::set_status_text('Length', SB_VCB_LABEL)
            self.Na__PathSelectionTool__UpdateStatusText
            self.class.Na__PathSelectionTool__RegisterActiveTool(self)
            self.Na__PathSelectionTool__PushToolStateToDialog(true)
            Sketchup.active_model.active_view.invalidate
        end

        def resume(view)
            # Key-up never arrives for a key that was still held when the tool
            # was suspended, which would leave SHIFT stuck on and turn TAB into
            # a rotate.
            @na_key_tab_held = false
            @na_key_shift_held = false
            @na_vcb_typing_active = false

            # An orbit can carry the camera across a 45-degree boundary, and the
            # datum face snaps to the nearest model axis until a waypoint fixes
            # a real path direction.
            Sketchup::set_status_text('Length', SB_VCB_LABEL)
            @na_last_vcb_value_text = nil
            self.Na__PathSelectionTool__RebuildPreviewCache
            self.Na__PathSelectionTool__UpdateStatusText
            view.invalidate
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Tool API (dialog-driven state changes)
    # -------------------------------------------------------------------------

        # Applies a Reverse state change from any source — the dialog button or
        # the TAB hotkey — and refreshes the viewport immediately, which matters
        # because the dialog holds focus and no mouse move is coming.
        def Na__PathSelectionTool__SetReverseDirection(reverse_direction)
            next_value = reverse_direction == true
            return @na_reverse_direction if next_value == @na_reverse_direction

            @na_reverse_direction = next_value
            self.Na__PathSelectionTool__RebuildPreviewCache
            self.Na__PathSelectionTool__UpdateStatusText

            view = Sketchup.active_model.active_view
            view.invalidate if view
            @na_reverse_direction
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Mouse Interaction
    # -------------------------------------------------------------------------

        def onMouseMove(_flags, x, y, view)
            @na_last_mouse_x = x
            @na_last_mouse_y = y
            self.Na__PathSelectionTool__DisarmReviseIfMoved(x, y)

            if @na_state == :picking_path && !@na_waypoints.empty? && !self.Na__AxisLock__Active?
                @na_input_point.pick(view, x, y, @na_previous_input_point)
            else
                @na_input_point.pick(view, x, y)
            end
            return unless @na_input_point.valid?

            raw_cursor_point = self.Na__PathSelectionTool__RoundToGrid(@na_input_point.position)
            @na_cursor_point = self.Na__PathSelectionTool__ResolveLoopClosureSnap(raw_cursor_point, view, x, y)
            @na_cursor_point = self.Na__PathSelectionTool__ResolveLockedSquareSnap(@na_cursor_point, view)
            view.tooltip = @na_loop_close_armed ? 'Close Loop' : ''
            self.Na__PathSelectionTool__RebuildPreviewCache
            self.Na__PathSelectionTool__UpdateStatusText
            view.invalidate
        end

        def onLButtonDown(_flags, x, y, view)
            @na_last_mouse_x = x
            @na_last_mouse_y = y
            @na_vcb_typing_active = false
            @na_vcb_revise_active = false

            @na_input_point.pick(view, x, y)
            return unless @na_input_point.valid?

            clicked_point = self.Na__PathSelectionTool__RoundToGrid(@na_input_point.position)
            clicked_point = self.Na__PathSelectionTool__ResolveLoopClosureSnap(clicked_point, view, x, y)
            clicked_point = self.Na__PathSelectionTool__ResolveLockedSquareSnap(clicked_point, view)
            if @na_state == :picking_start
                @na_waypoints = [clicked_point]
                @na_state = :picking_path
            else
                if self.Na__PathSelectionTool__IsLoopClosurePoint?(clicked_point)
                    self.Na__PathSelectionTool__AppendWaypointIfUnique(clicked_point)
                    @na_previous_input_point.copy!(@na_input_point)
                    self.Na__AxisLock__Reanchor(view)
                    self.Na__PathSelectionTool__RebuildPreviewCache
                    self.Na__PathSelectionTool__UpdateStatusText
                    self.Na__PathSelectionTool__FinishPathIfReady(view, false)
                    return
                end
                self.Na__PathSelectionTool__AppendWaypointIfUnique(clicked_point)
            end

            @na_previous_input_point.copy!(@na_input_point)
            self.Na__AxisLock__Reanchor(view)
            self.Na__PathSelectionTool__RebuildPreviewCache
            self.Na__PathSelectionTool__UpdateStatusText
            view.invalidate
        end

        def onRButtonDown(_flags, _x, _y, view)
            self.Na__PathSelectionTool__FinishPathIfReady(view, true)
        end

        def onLButtonDoubleClick(_flags, x, y, view)
            @na_input_point.pick(view, x, y)
            if @na_input_point.valid?
                clicked_point = self.Na__PathSelectionTool__RoundToGrid(@na_input_point.position)
                self.Na__PathSelectionTool__AppendWaypointIfUnique(clicked_point)
            end
            self.Na__PathSelectionTool__FinishPathIfReady(view, true)
        end

        def onReturn(view)
            self.Na__PathSelectionTool__FinishPathIfReady(view, true)
        end

        def getMenu(_menu, *_args)
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Tool Rendering
    # -------------------------------------------------------------------------

        def draw(view)
            return unless @na_cursor_point

            @na_input_point.draw(view)
            Na__PreviewGraphics.Na__Preview__DrawCrosshair(view, @na_cursor_point, @na_crosshair_size)

            # No path yet — the start point is unpicked, or the cursor still sits
            # on it. Show the cross-section on its own so the profile's roll and
            # its side of the line can be judged (and reversed) before committing.
            if @na_cache_path.nil? || @na_cache_path.empty?
                Na__PreviewGraphics.Na__Preview__DrawProfileFace(view, @na_cache_profile_polyline)
                return
            end

            Na__PreviewGraphics.Na__Preview__DrawPath(view, @na_cache_path)
            Na__PreviewGraphics.Na__Preview__DrawWaypointMarkers(view, @na_waypoints, @na_crosshair_size * 0.15)
            Na__PreviewGraphics.Na__Preview__DrawSweepSegments(view, @na_cache_sweep_segments)
            Na__PreviewGraphics.Na__Preview__DrawProfileGhost(view, @na_cache_profile_polyline)
            if @na_square_snap_reference && @na_cursor_point
                Na__PreviewGraphics.Na__Preview__DrawSquareSnapTie(view, @na_cursor_point, @na_square_snap_reference)
            end
            if @na_loop_close_armed && !@na_waypoints.empty?
                Na__PreviewGraphics.Na__Preview__DrawCloseLoopCue(view, @na_waypoints.first)
            end
        end

        def getExtents
            bounds = Geom::BoundingBox.new
            @na_waypoints.each { |point| bounds.add(point) }
            bounds.add(@na_cursor_point) if @na_cursor_point
            @na_cache_sweep_segments.each { |point| bounds.add(point) } if @na_cache_sweep_segments
            @na_cache_profile_polyline.each { |point| bounds.add(point) } if @na_cache_profile_polyline
            bounds
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Deactivate / Cleanup
    # -------------------------------------------------------------------------

        def deactivate(view)
            self.class.Na__PathSelectionTool__ClearActiveTool(self)
            self.Na__PathSelectionTool__PushToolStateToDialog(false)
            self.Na__AxisLock__Clear(view)
            Sketchup.status_text = ''
            Sketchup::set_status_text('', SB_VCB_LABEL)
            Sketchup::set_status_text('', SB_VCB_VALUE)
        end

        def onCancel(_reason, view)
            @na_vcb_typing_active = false
            @na_vcb_revise_active = false
            self.Na__AxisLock__Clear(view)
            Sketchup::set_status_text('Interactive profile drawing cancelled.', NA_STATUS_PROMPT_KEY)
            Sketchup::set_status_text('', SB_VCB_VALUE)
            Sketchup.active_model.select_tool(nil)
            view.invalidate
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Keyboard + VCB
    # -------------------------------------------------------------------------

        def onKeyDown(key, _repeat, _flags, view)
            if key == NA_SHIFT_KEY
                @na_key_shift_held = true
                return false
            end

            # Return is deliberately NOT handled here. With typed VCB text
            # pending, SketchUp routes Enter to onUserText; with an empty box it
            # routes to onReturn — acting on the raw key here would finish the
            # path before a typed length ever arrived.

            if key == NA_VK_BACKSPACE || key == VK_DELETE
                # Mid-entry, Backspace is the user fixing a typo in the VCB —
                # eating it as waypoint-undo would be infuriating.
                return false if @na_vcb_typing_active
                self.Na__PathSelectionTool__UndoLastWaypoint(view)
                return false
            end

            # TAB flips the profile, SHIFT+TAB rolls it 90 deg. Reverse is the
            # correction that is actually needed mid-draw, so it gets the bare key.
            if key == NA_TAB_KEY && !@na_key_tab_held
                @na_key_tab_held = true
                if @na_key_shift_held
                    @na_rotation_step = (@na_rotation_step.to_i + 1) % 4
                    self.Na__PathSelectionTool__RebuildPreviewCache
                    self.Na__PathSelectionTool__UpdateStatusText
                    view.invalidate
                else
                    self.Na__PathSelectionTool__SetReverseDirection(!@na_reverse_direction)
                    self.Na__PathSelectionTool__PushReverseStateToDialog
                end
                return false
            end

            # Digits and numeric operators flow on to the measurements box;
            # remembering that an entry is in progress is what arms the
            # Backspace guard above.
            if NA_VCB_ENTRY_KEYS.include?(key)
                @na_vcb_typing_active = true
                return false
            end

            if self.Na__AxisLock__OnKeyDown(key, view)
                self.Na__PathSelectionTool__UpdateStatusText
                view.invalidate
            end
            false
        end

        def onKeyUp(key, _repeat, _flags, _view)
            @na_key_tab_held = false if key == NA_TAB_KEY
            @na_key_shift_held = false if key == NA_SHIFT_KEY
            self.Na__AxisLock__OnKeyUp(key)
            false
        end

        def enableVCB?
            true
        end

        # Typed lengths, native-Line-tool style. `2500` sets the segment being
        # tracked to exactly that length; `+100` / `-100` are relative — to the
        # live tracked length while the cursor is off drawing, or to the last
        # committed segment when the cursor still sits on the point just placed
        # (the gutter-overshoot case: click the wall corner, type +100).
        # Parsing goes through String#to_l so units, feet/inch marks and the
        # locale decimal separator behave exactly as they do in native tools.
        def onUserText(text, view)
            @na_vcb_typing_active = false
            input_text = text.to_s.strip
            return if input_text.empty?

            unless @na_state == :picking_path && !@na_waypoints.empty?
                UI.beep
                Sketchup::set_status_text('Click a start point before typing a length.', NA_STATUS_PROMPT_KEY)
                return
            end

            relative_sign = 0
            relative_sign = 1  if input_text.start_with?('+')
            relative_sign = -1 if input_text.start_with?('-')
            magnitude_text = relative_sign.zero? ? input_text : input_text[1..-1].to_s.strip

            parsed_length =
                begin
                    magnitude_text.to_l
                rescue StandardError
                    nil
                end
            if parsed_length.nil? || parsed_length.to_f <= 0.0
                UI.beep
                Sketchup::set_status_text("Could not read '#{input_text}' as a length. Type e.g. 2500, 2.5m or +100.", NA_STATUS_PROMPT_KEY)
                self.Na__PathSelectionTool__RearmVcbDisplay
                return
            end

            if self.Na__PathSelectionTool__LiveDirectionAvailable?(view)
                self.Na__PathSelectionTool__CommitTypedWaypoint(parsed_length, relative_sign, view)
            else
                self.Na__PathSelectionTool__ReviseLastSegment(parsed_length, relative_sign, view)
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private Helpers
    # -------------------------------------------------------------------------

        private

        def Na__PathSelectionTool__ResetPreviewCache
            self.Na__PathSelectionTool__ClearPreviewGeometryCache
            @na_last_status_text = nil
        end

        # Geometry only. A rebuild starts from a clean cache on every mouse move,
        # and must not drop the last-status memo with it or the status bar would
        # be rewritten on every single move.
        def Na__PathSelectionTool__ClearPreviewGeometryCache
            @na_cache_path = nil
            @na_cache_sweep_segments = []
            @na_cache_profile_polyline = []
            @na_cache_total_length_mm = 0.0
        end

        def Na__PathSelectionTool__RebuildPreviewCache
            self.Na__PathSelectionTool__ClearPreviewGeometryCache
            return unless @na_cursor_point

            if @na_state == :picking_path && !@na_waypoints.empty?
                # After a typed placement the cursor is wherever the mouse was
                # left, usually behind the new waypoint — previewing the
                # committed waypoints alone keeps a backward rubber-band tail
                # from muddying the exact length just entered.
                preview_path =
                    if @na_vcb_revise_active
                        @na_waypoints.dup
                    else
                        @na_waypoints + [@na_cursor_point]
                    end
                path_data = Na__ProfilePlacementEngine.Na__Engine__BuildPathDataFromInteractivePoints(preview_path)

                if path_data
                    @na_cache_path = preview_path
                    @na_cache_total_length_mm = self.Na__PathSelectionTool__PathLengthMm(preview_path)

                    # One call builds ghost + cage together so the reverse flip is derived
                    # from a single shared bounding box, exactly as the real build does.
                    preview_geometry = Na__GeometryBuilders.Na__Geometry__BuildPreviewGeometry(
                        profile_data: @na_profile_data,
                        path_data: path_data,
                        start_point: @na_cursor_point,
                        rotation_step: @na_rotation_step,
                        toggle_states: @na_toggle_states,
                        reverse_direction: @na_reverse_direction,
                        origin_offset: @na_origin_offset
                    )
                    @na_cache_profile_polyline = preview_geometry[:profile_polyline]
                    @na_cache_sweep_segments = preview_geometry[:sweep_segments]
                    return
                end
            end

            self.Na__PathSelectionTool__RebuildDatumFaceCache
        end

        # Cross-section preview for the states that have no path to sweep along:
        # before the start point is clicked, and while the cursor is still sitting
        # on it. The path direction is genuinely unknown at that moment, so the
        # face is locked to the crosshair and presented true-to-dialog — the
        # WYSIWYG frame guarantees the sweep ghost and the built solid carry the
        # same handedness, and Reverse flips all of them the same way.
        def Na__PathSelectionTool__RebuildDatumFaceCache
            anchor_point = @na_waypoints.empty? ? @na_cursor_point : @na_waypoints.last
            return unless anchor_point

            probe_tangent = self.Na__PathSelectionTool__DatumProbeTangent
            probe_path_data = {
                ordered_points: [anchor_point, anchor_point.offset(probe_tangent, NA_DATUM_PROBE_LENGTH)],
                ordered_edges: [],
                is_closed_loop: false
            }

            preview_geometry = Na__GeometryBuilders.Na__Geometry__BuildPreviewGeometry(
                profile_data: @na_profile_data,
                path_data: probe_path_data,
                start_point: anchor_point,
                rotation_step: @na_rotation_step,
                toggle_states: @na_toggle_states,
                reverse_direction: @na_reverse_direction,
                origin_offset: @na_origin_offset
            )
            @na_cache_profile_polyline = preview_geometry[:profile_polyline]
        end

        # Fixed -X probe for the pre-click crosshair face. This used to orient
        # itself to the camera, which made the face flip as you orbited and
        # promise a handedness the build rule no longer consults — the open-run
        # traversal is now canonical by axis sign (see
        # Na__Engine__AlignOpenRunToCanonicalDirection), with no camera in the
        # decision. The canonical traversal for an X-dominant run is -X, so the
        # crosshair shows that frame: stable under orbit, and exactly what an X
        # run builds as. From the first click onward the live ghost takes over,
        # and it runs through the same alignment as the real build, so
        # everything after the start point is WYSIWYG by construction.
        def Na__PathSelectionTool__DatumProbeTangent
            X_AXIS.reverse
        end

        def Na__PathSelectionTool__FinishPathIfReady(view, include_cursor_point)
            # A typed placement leaves the cursor stranded behind the waypoint
            # it created — folding that stale position into the finish would
            # append a phantom backward segment.
            include_cursor_point = false if @na_vcb_revise_active

            path_points = @na_waypoints.dup
            if include_cursor_point && @na_cursor_point
                self.Na__PathSelectionTool__AppendPointToPathIfUnique(path_points, @na_cursor_point)
            end

            if path_points.length < 2
                UI.beep
                Sketchup::set_status_text('Add at least one more waypoint before finishing.', NA_STATUS_PROMPT_KEY)
                return
            end

            result = Na__ProfilePlacementEngine.Na__Engine__GenerateFromInteractivePath(
                profile_key: @na_profile_key,
                profile_data: @na_profile_data,
                path_points: path_points,
                rotation_step: @na_rotation_step,
                toggle_states: @na_toggle_states,
                reverse_direction: @na_reverse_direction,
                origin_offset: @na_origin_offset
            )

            Sketchup::set_status_text(result['statusMessage'].to_s, NA_STATUS_PROMPT_KEY)
            if result['isBuilt']
                Sketchup.active_model.select_tool(nil)
            else
                UI.beep
            end
            view.invalidate
        end

        def Na__PathSelectionTool__UndoLastWaypoint(view)
            return if @na_waypoints.empty?

            @na_waypoints.pop
            if @na_waypoints.empty?
                @na_state = :picking_start
                @na_previous_input_point = Sketchup::InputPoint.new
            else
                @na_previous_input_point = Sketchup::InputPoint.new(@na_waypoints.last)
            end

            self.Na__AxisLock__Reanchor(view)
            self.Na__PathSelectionTool__RebuildPreviewCache
            self.Na__PathSelectionTool__UpdateStatusText
            view.invalidate
        end

        def Na__PathSelectionTool__UpdateStatusText
            self.Na__PathSelectionTool__UpdateVcbDisplay

            rotation_degrees = @na_rotation_step.to_i * 90
            lock_suffix = self.Na__AxisLock__StatusSuffix
            reverse_suffix = @na_reverse_direction ? ' | REVERSED' : ''
            key_hints = "TAB reverse | SHIFT+TAB rotate (#{rotation_degrees} deg)"

            next_status =
                if @na_state == :picking_start
                    if @na_cursor_point
                        coords = self.Na__PathSelectionTool__PointToMmString(@na_cursor_point)
                        "Profile Path Tracer: Click to set start point at #{coords} | #{key_hints} | ESC cancel#{reverse_suffix}#{lock_suffix}"
                    else
                        "Profile Path Tracer: Click to set start point | #{key_hints} | ESC cancel#{reverse_suffix}#{lock_suffix}"
                    end
                else
                    if @na_cache_path && !@na_cache_path.empty?
                        "Profile Path Tracer: Click add waypoint (click start to close) | Type length (+/- adjusts) | Enter/Right-click/Double-click finish | Backspace undo | #{key_hints} | #{@na_cache_total_length_mm.round}mm#{reverse_suffix}#{lock_suffix}"
                    else
                        "Profile Path Tracer: Click add waypoint (click start to close) | Type length (+/- adjusts) | Enter/Right-click/Double-click finish | Backspace undo | #{key_hints}#{reverse_suffix}#{lock_suffix}"
                    end
                end

            return if next_status == @na_last_status_text
            Sketchup.status_text = next_status
            @na_last_status_text = next_status
        end

        # Writes a one-off confirmation into the prompt and keeps the memo in
        # step so the next routine refresh does not immediately repaint over it
        # with an identical-looking standard line.
        def Na__PathSelectionTool__SetTransientPrompt(prompt_text)
            Sketchup::set_status_text(prompt_text, NA_STATUS_PROMPT_KEY)
            @na_last_status_text = prompt_text
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | VCB Typed Length Input
    # -------------------------------------------------------------------------

        # The measurements box mirrors what a typed value would act on: the live
        # tracked length while drawing, otherwise the last committed segment —
        # which is exactly the base a relative +/- entry adds to.
        def Na__PathSelectionTool__UpdateVcbDisplay
            next_value_text =
                if @na_state == :picking_path && !@na_waypoints.empty?
                    if !@na_vcb_revise_active && @na_cursor_point &&
                       @na_cursor_point.distance(@na_waypoints.last) > NA_POINT_MERGE_TOLERANCE
                        @na_cursor_point.distance(@na_waypoints.last).to_s
                    elsif @na_waypoints.length >= 2
                        @na_waypoints[-1].distance(@na_waypoints[-2]).to_s
                    else
                        ''
                    end
                else
                    ''
                end

            return if next_value_text == @na_last_vcb_value_text
            Sketchup::set_status_text(next_value_text, SB_VCB_VALUE)
            @na_last_vcb_value_text = next_value_text
        end

        # SketchUp wipes the measurements box once onUserText has been handled,
        # so the refreshed value has to be pushed a beat later from a timer.
        def Na__PathSelectionTool__RearmVcbDisplay
            UI.start_timer(0.1, false) do
                begin
                    Sketchup::set_status_text('Length', SB_VCB_LABEL)
                    @na_last_vcb_value_text = nil
                    self.Na__PathSelectionTool__UpdateVcbDisplay
                rescue StandardError
                    nil
                end
            end
        end

        # True when the cursor is deliberately off the last waypoint defining a
        # direction to measure along. The screen-pixel test keeps a one-pixel
        # twitch after a click from being mistaken for a new direction — typed
        # values then adjust the segment just drawn instead of firing off a new
        # one along the jitter.
        def Na__PathSelectionTool__LiveDirectionAvailable?(view)
            return false if @na_vcb_revise_active
            return false unless @na_cursor_point && @na_waypoints.last
            return false if @na_cursor_point.distance(@na_waypoints.last) <= NA_POINT_MERGE_TOLERANCE
            return false unless @na_last_mouse_x && @na_last_mouse_y

            screen_distance = self.Na__PathSelectionTool__ScreenDistancePx(
                view, @na_last_mouse_x, @na_last_mouse_y, @na_waypoints.last
            )
            return true if screen_distance.nil?
            screen_distance > NA_VCB_DIRECTION_MIN_PX
        end

        # `2500` places the pending waypoint at exactly that length along the
        # tracked direction; `+100` places it at the live tracked length plus
        # 100 — the "snap to the wall corner, overshoot by 100" move done
        # without committing the corner first.
        def Na__PathSelectionTool__CommitTypedWaypoint(parsed_length, relative_sign, view)
            last_waypoint = @na_waypoints.last
            direction = @na_cursor_point - last_waypoint
            live_length = direction.length.to_f
            if live_length <= NA_POINT_MERGE_TOLERANCE
                UI.beep
                return
            end
            direction.normalize!

            target_length = relative_sign.zero? ? parsed_length.to_f : live_length + (relative_sign * parsed_length.to_f)
            if target_length <= NA_POINT_MERGE_TOLERANCE
                UI.beep
                self.Na__PathSelectionTool__SetTransientPrompt('That adjustment would collapse the segment.')
                self.Na__PathSelectionTool__RearmVcbDisplay
                return
            end

            new_waypoint = last_waypoint.offset(direction, target_length)
            self.Na__PathSelectionTool__AppendWaypointIfUnique(new_waypoint)
            @na_previous_input_point = Sketchup::InputPoint.new(new_waypoint)
            self.Na__AxisLock__Reanchor(view)
            self.Na__PathSelectionTool__ArmReviseMode
            self.Na__PathSelectionTool__RebuildPreviewCache
            self.Na__PathSelectionTool__SetTransientPrompt(
                "Segment placed at #{target_length.to_l}. Keep drawing, type again to adjust, or press Enter to finish."
            )
            self.Na__PathSelectionTool__UpdateVcbDisplay
            self.Na__PathSelectionTool__RearmVcbDisplay
            view.invalidate
        end

        # With no direction being tracked — the cursor still sits on the point
        # just placed — typed values act on the last committed segment. `2500`
        # re-lengths it exactly (fix a sloppy click after the fact), `+100`
        # pushes it further along its own direction: the gutter overshoot.
        def Na__PathSelectionTool__ReviseLastSegment(parsed_length, relative_sign, view)
            if @na_waypoints.length < 2
                UI.beep
                self.Na__PathSelectionTool__SetTransientPrompt('Draw a segment first — then type to adjust it.')
                self.Na__PathSelectionTool__RearmVcbDisplay
                return
            end

            base_waypoint = @na_waypoints[-2]
            direction = @na_waypoints[-1] - base_waypoint
            segment_length = direction.length.to_f
            if segment_length <= NA_POINT_MERGE_TOLERANCE
                UI.beep
                return
            end
            direction.normalize!

            target_length = relative_sign.zero? ? parsed_length.to_f : segment_length + (relative_sign * parsed_length.to_f)
            if target_length <= NA_POINT_MERGE_TOLERANCE
                UI.beep
                self.Na__PathSelectionTool__SetTransientPrompt('That adjustment would collapse the segment.')
                self.Na__PathSelectionTool__RearmVcbDisplay
                return
            end

            revised_waypoint = base_waypoint.offset(direction, target_length)
            @na_waypoints[-1] = revised_waypoint
            @na_previous_input_point = Sketchup::InputPoint.new(revised_waypoint)
            self.Na__AxisLock__Reanchor(view)
            self.Na__PathSelectionTool__ArmReviseMode
            self.Na__PathSelectionTool__RebuildPreviewCache
            self.Na__PathSelectionTool__SetTransientPrompt(
                "Last segment adjusted to #{target_length.to_l}. Type again to adjust, or keep drawing."
            )
            self.Na__PathSelectionTool__UpdateVcbDisplay
            self.Na__PathSelectionTool__RearmVcbDisplay
            view.invalidate
        end

        # Revise mode: typed values keep applying to the segment just placed
        # until the mouse makes a deliberate move (or a click commits it).
        def Na__PathSelectionTool__ArmReviseMode
            @na_vcb_revise_active = true
            @na_vcb_revise_anchor_x = @na_last_mouse_x
            @na_vcb_revise_anchor_y = @na_last_mouse_y
        end

        def Na__PathSelectionTool__DisarmReviseIfMoved(x, y)
            return unless @na_vcb_revise_active
            unless @na_vcb_revise_anchor_x && @na_vcb_revise_anchor_y
                @na_vcb_revise_active = false
                return
            end
            moved_px = (x.to_f - @na_vcb_revise_anchor_x.to_f).abs +
                       (y.to_f - @na_vcb_revise_anchor_y.to_f).abs
            @na_vcb_revise_active = false if moved_px > NA_VCB_REVISE_DISARM_PX
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Sync (tool -> dialog)
    # -------------------------------------------------------------------------

        # TAB changes state the dialog owns, so the Reverse button has to be told
        # or it would sit there claiming the opposite of what the preview shows.
        def Na__PathSelectionTool__PushReverseStateToDialog
            return unless defined?(Na__DialogManager)
            Na__DialogManager.Na__Dialog__PushReverseDirectionState(@na_reverse_direction)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Reverse state push warning: #{error.message}")
        end

        # Lets the dialog arm its own TAB handler only while a trace is live, so
        # the key keeps its normal focus-traversal job the rest of the time.
        def Na__PathSelectionTool__PushToolStateToDialog(is_active)
            return unless defined?(Na__DialogManager)
            Na__DialogManager.Na__Dialog__PushInteractiveToolState(is_active, @na_reverse_direction)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Tool state push warning: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Path Point Helpers
    # -------------------------------------------------------------------------

        def Na__PathSelectionTool__AppendWaypointIfUnique(point)
            return if point.nil?
            if @na_waypoints.empty?
                @na_waypoints << point
                return
            end
            return if @na_waypoints.last.distance(point) <= NA_POINT_MERGE_TOLERANCE
            @na_waypoints << point
        end

        def Na__PathSelectionTool__AppendPointToPathIfUnique(path_points, point)
            return if !path_points.is_a?(Array) || point.nil?
            if path_points.empty?
                path_points << point
                return
            end
            return if path_points.last.distance(point) <= NA_POINT_MERGE_TOLERANCE
            path_points << point
        end

        def Na__PathSelectionTool__PathLengthMm(path_points)
            total = 0.0
            (0...(path_points.length - 1)).each do |index|
                total += path_points[index].distance(path_points[index + 1])
            end
            total * NA_INCH_TO_MM
        end

        def Na__PathSelectionTool__RoundToGrid(point)
            Geom::Point3d.new(
                (point.x / NA_GRID_SIZE).round * NA_GRID_SIZE,
                (point.y / NA_GRID_SIZE).round * NA_GRID_SIZE,
                (point.z / NA_GRID_SIZE).round * NA_GRID_SIZE
            )
        end

        def Na__PathSelectionTool__PointToMmString(point)
            x_mm = (point.x * NA_INCH_TO_MM).round
            y_mm = (point.y * NA_INCH_TO_MM).round
            z_mm = (point.z * NA_INCH_TO_MM).round
            "X:#{x_mm}mm Y:#{y_mm}mm Z:#{z_mm}mm"
        end

        def Na__PathSelectionTool__ResolveLoopClosureSnap(point, view, x, y)
            @na_loop_close_armed = false
            return point if point.nil?
            return point unless @na_state == :picking_path
            return point unless @na_waypoints.is_a?(Array) && @na_waypoints.length >= 3

            start_point = @na_waypoints.first
            return point unless start_point

            # World-space catch, sized by LoopCloseTolerance rather than a fixed
            # 5mm - see that method for the scaling contract. Testing the
            # RESOLVED point (already constrained by any armed lock) keeps this
            # compatible with the v1.6.8 rule below: the raw mouse never
            # overrides a lock, but a constrained point that genuinely comes
            # within the catch of the start closes - overshoot included, since
            # the catch is a ball around the start, not a gate before it.
            if point.distance(start_point) <= self.Na__PathSelectionTool__LoopCloseTolerance(view, start_point)
                @na_loop_close_armed = true
                return start_point
            end

            # (v1.6.8) An armed arrow-key lock is an explicit direction
            # constraint, and the screen test below reads the raw MOUSE position
            # - which, in the standard SketchUp close-a-loop move, is parked ON
            # the start vertex to reference its position for the final segment's
            # length. Snapping then would teleport the cursor off the locked
            # line and fold the preview shut. While locked, only the world
            # check above may close the loop.
            return point if self.Na__AxisLock__Active?

            screen_distance = self.Na__PathSelectionTool__ScreenDistancePx(view, x, y, start_point)
            if screen_distance && screen_distance <= NA_LOOP_CLOSE_SCREEN_TOLERANCE_PX
                @na_loop_close_armed = true
                return start_point
            end

            point
        end

        # How close counts as "at the start". A fixed 5mm was the answer, and it
        # made closing a building-scale loop a pixel-hunt: at working zoom one
        # pixel IS several millimetres, so a fraction under refused to close and
        # a fraction over kinked the loop instead. The radius now scales with
        # the two things hit-precision actually depends on:
        #
        #   zoom  - NA_LOOP_CLOSE_DYNAMIC_PX worth of model distance at the
        #           start point (pixels_to_model), so the catch is the same
        #           size ON SCREEN whatever the zoom;
        #   size  - at least NA_LOOP_CLOSE_SIZE_FRACTION of the drawn path's
        #           bounding diagonal, so an 11-metre loop keeps a usable catch
        #           even zoomed right in on the corner.
        #
        # Capped at NA_LOOP_CLOSE_MAX_FRACTION of that diagonal so a far-out
        # zoom cannot swallow the last waypoint of a small loop, and floored at
        # the old 5mm so it is never LESS forgiving than before.
        def Na__PathSelectionTool__LoopCloseTolerance(view, start_point)
            zoom_component = 0.0
            if view && start_point
                begin
                    zoom_component = view.pixels_to_model(NA_LOOP_CLOSE_DYNAMIC_PX, start_point).to_f
                rescue
                    zoom_component = 0.0
                end
            end

            diagonal       = self.Na__PathSelectionTool__WaypointsDiagonal
            size_component = diagonal * NA_LOOP_CLOSE_SIZE_FRACTION
            size_cap       = diagonal * NA_LOOP_CLOSE_MAX_FRACTION

            tolerance = [zoom_component, size_component].max
            tolerance = size_cap if size_cap > 0.0 && tolerance > size_cap
            [tolerance, NA_LOOP_CLOSE_WORLD_TOLERANCE.to_f].max
        end

        def Na__PathSelectionTool__WaypointsDiagonal
            return 0.0 unless @na_waypoints.is_a?(Array) && @na_waypoints.length >= 2
            bounds = Geom::BoundingBox.new
            @na_waypoints.each { |waypoint| bounds.add(waypoint) }
            bounds.diagonal.to_f
        rescue
            0.0
        end

        def Na__PathSelectionTool__ScreenDistancePx(view, x, y, target_point)
            return nil unless view && target_point

            target_screen = view.screen_coords(target_point)
            dx = target_screen.x.to_f - x.to_f
            dy = target_screen.y.to_f - y.to_f
            Math.sqrt((dx * dx) + (dy * dy))
        rescue
            nil
        end

        def Na__PathSelectionTool__IsLoopClosurePoint?(point)
            return false unless point
            return false unless @na_state == :picking_path
            return false unless @na_waypoints.is_a?(Array) && @na_waypoints.length >= 3

            start_point = @na_waypoints.first
            return false unless start_point
            point.distance(start_point) <= NA_POINT_MERGE_TOLERANCE
        end

        # While an arrow-key lock is armed, offer the one inference the lock
        # cannot express on its own: the point on the locked line SQUARE to the
        # path's start vertex. Closing a rectangle needs the current segment to
        # stop exactly level with the start, and v1.6.8 deliberately stopped the
        # closure snap teleporting the cursor there - this is the assist that
        # replaces it. The cursor snaps to the perpendicular foot of the start
        # on the locked line whenever it passes within a few pixels of it, and
        # the draw hook ties it back to the start with a dotted line so the
        # catch reads as an inference rather than a jump. The snapped point
        # stays ON the locked line by construction.
        def Na__PathSelectionTool__ResolveLockedSquareSnap(point, view)
            @na_square_snap_reference = nil
            return point unless point && view
            return point unless @na_state == :picking_path
            return point unless self.Na__AxisLock__Active?
            return point unless @na_waypoints.is_a?(Array) && @na_waypoints.length >= 2

            anchor        = @na_waypoints.last
            start_point   = @na_waypoints.first
            lock_endpoint = self.Na__AxisLock__LockEndpoint(anchor)
            return point unless lock_endpoint

            direction = lock_endpoint - anchor
            return point if direction.length <= 0.001
            direction.normalize!

            offset_along = (start_point - anchor).dot(direction)
            square_point = anchor.offset(direction, offset_along)

            # A square point on the anchor itself means the start projects onto
            # the segment's own origin - a zero-length catch with nothing to
            # offer. And one within closure range of the start means the lock
            # line runs THROUGH the start, where the world-tolerance closure in
            # ResolveLoopClosureSnap already owns the catch.
            return point if square_point.distance(anchor) <= NA_POINT_MERGE_TOLERANCE
            return point if square_point.distance(start_point) <= self.Na__PathSelectionTool__LoopCloseTolerance(view, start_point)

            cursor_screen = view.screen_coords(point)
            screen_distance = self.Na__PathSelectionTool__ScreenDistancePx(
                view, cursor_screen.x, cursor_screen.y, square_point
            )
            return point unless screen_distance && screen_distance <= NA_SQUARE_SNAP_SCREEN_TOLERANCE_PX

            @na_square_snap_reference = start_point
            square_point
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Square snap skipped: #{error.message}")
            point
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
