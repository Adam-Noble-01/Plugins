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
        NA_ROTATION_KEY                   = 9
        NA_VK_BACKSPACE                   = 8
        NA_VK_RETURN                      = 13
        NA_POINT_MERGE_TOLERANCE          = 0.001
        NA_LOOP_CLOSE_SCREEN_TOLERANCE_PX = 14.0
        NA_LOOP_CLOSE_WORLD_TOLERANCE     = 5.mm

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Initialization / State
    # -------------------------------------------------------------------------

        def initialize(profile_key, profile_data, toggle_states = {}, initial_rotation_step = 0)
            @na_profile_key = profile_key
            @na_profile_data = profile_data || {}
            @na_toggle_states = toggle_states || {}
            @na_rotation_step = initial_rotation_step.to_i % 4
            @na_key_tab_held = false
            @na_crosshair_size = NA_DEFAULT_CROSSHAIR_SIZE

            @na_input_point = Sketchup::InputPoint.new
            @na_previous_input_point = Sketchup::InputPoint.new
            @na_cursor_point = nil
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
            @na_previous_input_point = Sketchup::InputPoint.new
            self.Na__AxisLock__InitState
            self.Na__PathSelectionTool__ResetPreviewCache
            self.Na__PathSelectionTool__UpdateStatusText
            Sketchup.active_model.active_view.invalidate
        end

        def resume(view)
            self.Na__PathSelectionTool__UpdateStatusText
            view.invalidate
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Mouse Interaction
    # -------------------------------------------------------------------------

        def onMouseMove(_flags, x, y, view)
            if @na_state == :picking_path && !@na_waypoints.empty? && !self.Na__AxisLock__Active?
                @na_input_point.pick(view, x, y, @na_previous_input_point)
            else
                @na_input_point.pick(view, x, y)
            end
            return unless @na_input_point.valid?

            raw_cursor_point = self.Na__PathSelectionTool__RoundToGrid(@na_input_point.position)
            @na_cursor_point = self.Na__PathSelectionTool__ResolveLoopClosureSnap(raw_cursor_point, view, x, y)
            self.Na__PathSelectionTool__RebuildPreviewCache
            self.Na__PathSelectionTool__UpdateStatusText
            view.invalidate
        end

        def onLButtonDown(_flags, x, y, view)
            @na_input_point.pick(view, x, y)
            return unless @na_input_point.valid?

            clicked_point = self.Na__PathSelectionTool__RoundToGrid(@na_input_point.position)
            clicked_point = self.Na__PathSelectionTool__ResolveLoopClosureSnap(clicked_point, view, x, y)
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
            return unless @na_state == :picking_path
            return if @na_cache_path.nil? || @na_cache_path.empty?

            Na__PreviewGraphics.Na__Preview__DrawPath(view, @na_cache_path)
            Na__PreviewGraphics.Na__Preview__DrawWaypointMarkers(view, @na_waypoints, @na_crosshair_size * 0.15)
            Na__PreviewGraphics.Na__Preview__DrawSweepSegments(view, @na_cache_sweep_segments)
            Na__PreviewGraphics.Na__Preview__DrawProfileGhost(view, @na_cache_profile_polyline)
        end

        def getExtents
            bounds = Geom::BoundingBox.new
            @na_waypoints.each { |point| bounds.add(point) }
            bounds.add(@na_cursor_point) if @na_cursor_point
            @na_cache_sweep_segments.each { |point| bounds.add(point) } if @na_cache_sweep_segments
            bounds
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Deactivate / Cleanup
    # -------------------------------------------------------------------------

        def deactivate(view)
            self.Na__AxisLock__Clear(view)
            Sketchup.status_text = ''
        end

        def onCancel(_reason, view)
            self.Na__AxisLock__Clear(view)
            Sketchup::set_status_text('Interactive profile drawing cancelled.', NA_STATUS_PROMPT_KEY)
            Sketchup.active_model.select_tool(nil)
            view.invalidate
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Keyboard + VCB
    # -------------------------------------------------------------------------

        def onKeyDown(key, _repeat, _flags, view)
            if key == NA_VK_RETURN
                self.Na__PathSelectionTool__FinishPathIfReady(view, true)
                return false
            end

            if key == NA_VK_BACKSPACE || key == VK_DELETE
                self.Na__PathSelectionTool__UndoLastWaypoint(view)
                return false
            end

            if key == NA_ROTATION_KEY && !@na_key_tab_held
                @na_key_tab_held = true
                @na_rotation_step = (@na_rotation_step.to_i + 1) % 4
                self.Na__PathSelectionTool__RebuildPreviewCache
                self.Na__PathSelectionTool__UpdateStatusText
                view.invalidate
                return false
            end

            if self.Na__AxisLock__OnKeyDown(key, view)
                self.Na__PathSelectionTool__UpdateStatusText
                view.invalidate
            end
            false
        end

        def onKeyUp(key, _repeat, _flags, _view)
            @na_key_tab_held = false if key == NA_ROTATION_KEY
            self.Na__AxisLock__OnKeyUp(key)
            false
        end

        def enableVCB?
            true
        end

        def onUserText(text, view)
            return if text.to_s.strip.empty?
            parsed = text.to_f
            return if parsed.zero?

            @na_crosshair_size = parsed.mm
            self.Na__PathSelectionTool__UpdateStatusText
            view.invalidate
        rescue
            UI.beep
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private Helpers
    # -------------------------------------------------------------------------

        private

        def Na__PathSelectionTool__ResetPreviewCache
            @na_cache_path = nil
            @na_cache_sweep_segments = []
            @na_cache_profile_polyline = []
            @na_cache_total_length_mm = 0.0
            @na_last_status_text = nil
        end

        def Na__PathSelectionTool__RebuildPreviewCache
            unless @na_cursor_point && @na_state == :picking_path && !@na_waypoints.empty?
                self.Na__PathSelectionTool__ResetPreviewCache
                return
            end

            preview_path = @na_waypoints + [@na_cursor_point]
            path_data = Na__ProfilePlacementEngine.Na__Engine__BuildPathDataFromInteractivePoints(preview_path)
            unless path_data
                self.Na__PathSelectionTool__ResetPreviewCache
                return
            end

            @na_cache_path = preview_path
            @na_cache_total_length_mm = self.Na__PathSelectionTool__PathLengthMm(preview_path)
            @na_cache_profile_polyline = Na__GeometryBuilders.Na__Geometry__BuildPreviewProfilePolyline(
                profile_data: @na_profile_data,
                path_data: path_data,
                start_point: @na_cursor_point,
                rotation_step: @na_rotation_step,
                toggle_states: @na_toggle_states
            )
            @na_cache_sweep_segments = Na__GeometryBuilders.Na__Geometry__BuildPreviewSweepSegments(
                profile_data: @na_profile_data,
                path_data: path_data,
                rotation_step: @na_rotation_step,
                toggle_states: @na_toggle_states
            )
        end

        def Na__PathSelectionTool__FinishPathIfReady(view, include_cursor_point)
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
                toggle_states: @na_toggle_states
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
            rotation_degrees = @na_rotation_step.to_i * 90
            lock_suffix = self.Na__AxisLock__StatusSuffix

            next_status =
                if @na_state == :picking_start
                    if @na_cursor_point
                        coords = self.Na__PathSelectionTool__PointToMmString(@na_cursor_point)
                        "Profile Path Tracer: Click to set start point at #{coords} | TAB rotate (#{rotation_degrees} deg) | ESC cancel#{lock_suffix}"
                    else
                        "Profile Path Tracer: Click to set start point | TAB rotate (#{rotation_degrees} deg) | ESC cancel#{lock_suffix}"
                    end
                else
                    if @na_cache_path && !@na_cache_path.empty?
                        "Profile Path Tracer: Click add waypoint (click start to close) | Enter/Right-click/Double-click finish | Backspace undo | TAB rotate (#{rotation_degrees} deg) | #{@na_cache_total_length_mm.round}mm#{lock_suffix}"
                    else
                        "Profile Path Tracer: Click add waypoint (click start to close) | Enter/Right-click/Double-click finish | Backspace undo | TAB rotate (#{rotation_degrees} deg)#{lock_suffix}"
                    end
                end

            return if next_status == @na_last_status_text
            Sketchup.status_text = next_status
            @na_last_status_text = next_status
        end

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
            return point if point.nil?
            return point unless @na_state == :picking_path
            return point unless @na_waypoints.is_a?(Array) && @na_waypoints.length >= 3

            start_point = @na_waypoints.first
            return point unless start_point
            return start_point if point.distance(start_point) <= NA_LOOP_CLOSE_WORLD_TOLERANCE

            screen_distance = self.Na__PathSelectionTool__ScreenDistancePx(view, x, y, start_point)
            return start_point if screen_distance && screen_distance <= NA_LOOP_CLOSE_SCREEN_TOLERANCE_PX

            point
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

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
