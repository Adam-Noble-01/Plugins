# =============================================================================
# NA PROFILE TOOLS - APPLY PROFILE - SELECTION PREVIEW TOOL
# =============================================================================
#
# FILE       : Na__ProfileTools__ApplyProfile__SelectionPreviewTool__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__SelectionPreviewTool
# PURPOSE    : Selection mode's look-before-you-build step. Generate Profile
#              with edges selected no longer builds on the spot: it shows the
#              sweep along the selected run in the viewport, live, and builds
#              only when the user commits.
#
# WHY
#   Selection mode used to build the moment Generate was pressed. Which end a
#   selected run is swept from is whatever SketchUp's edge ids favour, and the
#   sweep direction decides which side of the line the profile lands on — so
#   the handing was a coin toss that could only be seen after the fact, and
#   fixing it meant undo, reselect, rerun. The Interactive tool never had the
#   problem because its ghost showed the result before the last click.
#
#   This tool is that ghost for a selected run. Nothing touches the model until
#   Commit, and every dialog control — the profile (Active Profile list or the
#   Gallery), Reverse, rotation, mirrors, insert point and the path offsets —
#   redraws the preview in place.
#
# CONTROLS
#   Enter / double-click / right-click > Commit   build the trace
#   TAB                                           reverse the profile
#   SHIFT+TAB                                     rotate 90 deg
#   Esc / right-click > Cancel                    leave; nothing is built
#   A single click only gives the viewport focus — it never builds.
#
# THE PREVIEW IS THE BUILD
#   The cage comes from Na__Geometry__BuildPreviewGeometry with the profile,
#   frame, offsets and reverse flip that Na__Engine__GenerateFromPathData uses,
#   and Commit builds from the very run captured here, so what is on screen is
#   what lands in the model.
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    class Na__SelectionPreviewTool
        include Na__ProfileTools__ProfilePathTracer::Na__LiveToolPlacementMixin

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_STATUS_PROMPT_KEY = SB_PROMPT
        NA_TAB_KEY           = 9
        NA_SHIFT_KEY         = CONSTRAIN_MODIFIER_KEY
        NA_INCH_TO_MM        = 25.4
        NA_UNDO_CANCEL       = 2
        NA_TOOL_KIND         = 'selectionPreview'.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Initialization
    # -------------------------------------------------------------------------

        # path_data is the run read from the selection at Generate —
        # { ordered_points:, ordered_edges:, is_closed_loop: } in traversal
        # order. It is kept as captured, so nothing done to the selection after
        # Generate can move the preview out from under the user.
        # path_offsets are in traversal order: 'start' is the end labelled Start.
        def initialize(profile_key:, profile_data:, path_data:, profile_source_mode: 'library',
                       toggle_states: {}, rotation_step: 0, reverse_direction: false,
                       origin_offset: nil, path_offsets: nil)
            @na_profile_key         = profile_key
            @na_profile_data        = profile_data || {}
            @na_profile_source_mode = profile_source_mode.to_s.empty? ? 'library' : profile_source_mode.to_s
            @na_path_data           = path_data || {}
            @na_toggle_states       = toggle_states || {}
            @na_rotation_step       = rotation_step.to_i % 4
            @na_reverse_direction   = reverse_direction == true
            @na_origin_offset       = origin_offset
            @na_path_offsets        = path_offsets
            @na_key_tab_held        = false
            @na_key_shift_held      = false

            @na_cache_sweep_segments   = []
            @na_cache_profile_polyline = []
            @na_cache_sweep_points     = []
            @na_cache_reason           = nil
            @na_last_status_text       = nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Tool Lifecycle
    # -------------------------------------------------------------------------

        def activate
            @na_key_tab_held   = false
            @na_key_shift_held = false
            Na__LiveToolRegistry.Na__LiveTool__Register(self)
            self.Na__SelectionPreview__RebuildPreviewCache
            self.Na__SelectionPreview__UpdateStatusText
            self.Na__SelectionPreview__PushToolStateToDialog(true)
            Sketchup.active_model.active_view.invalidate
        end

        def deactivate(view)
            Na__LiveToolRegistry.Na__LiveTool__Clear(self)
            self.Na__SelectionPreview__PushToolStateToDialog(false)
            view.invalidate
        end

        # Back from an orbit or pan: a key held when the camera tool took over
        # never reports its key-up, which would leave SHIFT stuck on.
        def resume(view)
            @na_key_tab_held     = false
            @na_key_shift_held   = false
            @na_last_status_text = nil
            self.Na__SelectionPreview__UpdateStatusText
            view.invalidate
        end

        # Esc — and anything else SketchUp cancels a tool for — leaves with
        # nothing built. An undo is included on purpose: it arrives before the
        # undo runs and can take away the very edges the preview was read from.
        def onCancel(reason, view)
            message = reason == NA_UNDO_CANCEL ? 'Selection preview closed by the undo — nothing was built.' : nil
            self.Na__LiveTool__Cancel(message)
            view.invalidate
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Mouse + Context Menu
    # -------------------------------------------------------------------------

        # The dialog holds focus after Generate, and clicking into the model is
        # how the user takes it back to use TAB or Enter — so a single click must
        # never build. It only restates the prompt.
        def onLButtonDown(_flags, _x, _y, _view)
            @na_last_status_text = nil
            self.Na__SelectionPreview__UpdateStatusText
        end

        def onLButtonDoubleClick(_flags, _x, _y, _view)
            self.Na__LiveTool__Commit
        end

        def onReturn(_view)
            self.Na__LiveTool__Commit
        end

        def getMenu(menu, _flags = nil, _x = nil, _y = nil, _view = nil)
            menu.add_item('Commit Profile  (Enter)') { self.Na__LiveTool__Commit }
            menu.add_item('Reverse Profile  (TAB)') { self.Na__SelectionPreview__ToggleReverse }
            menu.add_item('Rotate Profile 90°  (SHIFT+TAB)') { self.Na__SelectionPreview__RotateStep }
            menu.add_separator
            menu.add_item('Cancel Preview  (Esc)') { self.Na__LiveTool__Cancel }
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Keyboard
    # -------------------------------------------------------------------------

        # Same keys as the Interactive tool: TAB reverses — the handing is the
        # correction this preview exists to catch — and SHIFT+TAB rolls 90 deg.
        # Return is left to SketchUp, which routes it to onReturn.
        def onKeyDown(key, _repeat, _flags, _view)
            if key == NA_SHIFT_KEY
                @na_key_shift_held = true
                return false
            end

            if key == NA_TAB_KEY && !@na_key_tab_held
                @na_key_tab_held = true
                if @na_key_shift_held
                    self.Na__SelectionPreview__RotateStep
                else
                    self.Na__SelectionPreview__ToggleReverse
                end
            end
            false
        end

        def onKeyUp(key, _repeat, _flags, _view)
            @na_key_tab_held   = false if key == NA_TAB_KEY
            @na_key_shift_held = false if key == NA_SHIFT_KEY
            false
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Rendering
    # -------------------------------------------------------------------------

        def draw(view)
            path_points = self.Na__SelectionPreview__PathPoints
            return if path_points.length < 2

            Na__PreviewGraphics.Na__Preview__DrawPath(view, path_points)
            Na__PreviewGraphics.Na__Preview__DrawSweepSegments(view, @na_cache_sweep_segments)
            return if self.Na__SelectionPreview__ClosedLoop?

            # A loop's cap is mitred into its seam, so only an open run gets
            # the solid start section, the overshoot marks and the end tags.
            Na__PreviewGraphics.Na__Preview__DrawProfileFace(view, @na_cache_profile_polyline)
            Na__PreviewGraphics.Na__Preview__DrawPathExtensions(
                view, path_points, @na_cache_sweep_points, self.Na__SelectionPreview__Offsets
            )
            Na__PreviewGraphics.Na__Preview__DrawPathEndLabels(
                view, path_points.first, path_points.last,
                self.Na__SelectionPreview__EndLabel('Start', 'start'),
                self.Na__SelectionPreview__EndLabel('End', 'end')
            )
        end

        def getExtents
            bounds = Geom::BoundingBox.new
            self.Na__SelectionPreview__PathPoints.each { |point| bounds.add(point) }
            @na_cache_sweep_segments.each { |point| bounds.add(point) }
            @na_cache_profile_polyline.each { |point| bounds.add(point) }
            @na_cache_sweep_points.each { |point| bounds.add(point) }
            bounds
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Live Tool API (Na__LiveToolRegistry dispatch)
    # -------------------------------------------------------------------------

        def Na__LiveTool__Kind
            NA_TOOL_KIND
        end

        def Na__LiveTool__SetReverseDirection(reverse_direction)
            next_value = reverse_direction == true
            return @na_reverse_direction if next_value == @na_reverse_direction
            @na_reverse_direction = next_value
            self.Na__LiveTool__OnPlacementChanged
            @na_reverse_direction
        end

        # Na__LiveToolPlacementMixin hook — every settings change lands here.
        def Na__LiveTool__OnPlacementChanged
            self.Na__SelectionPreview__RebuildPreviewCache
            @na_last_status_text = nil
            self.Na__SelectionPreview__UpdateStatusText
            view = Sketchup.active_model.active_view
            view.invalidate if view
        end

        # Builds from the captured run with the settings on screen. A failed
        # build keeps the preview up, so the cause (a trim longer than the run,
        # say) can be fixed in place instead of starting over.
        def Na__LiveTool__Commit
            result = Na__ProfilePlacementEngine.Na__Engine__GenerateFromPathData(
                profile_key:       @na_profile_key,
                profile_data:      @na_profile_data,
                path_data:         @na_path_data,
                start_point:       self.Na__SelectionPreview__PathPoints.first,
                rotation_step:     @na_rotation_step,
                toggle_states:     @na_toggle_states,
                reverse_direction: @na_reverse_direction,
                origin_offset:     @na_origin_offset,
                path_offsets:      @na_path_offsets
            )

            message = result['statusMessage'].to_s
            if result['isBuilt']
                Sketchup.active_model.select_tool(nil)
                Sketchup::set_status_text(message, NA_STATUS_PROMPT_KEY)
            else
                UI.beep
                Sketchup::set_status_text(message, NA_STATUS_PROMPT_KEY)
                @na_last_status_text = message
            end
            self.Na__SelectionPreview__PushStatusToDialog(message)
            result
        rescue => error
            Na__DebugTools.Na__Debug__Error('Selection preview commit failed.', error)
            { 'isBuilt' => false, 'statusMessage' => "Generation failed: #{error.message}" }
        end

        def Na__LiveTool__Cancel(message = nil)
            text = message || 'Selection preview cancelled — nothing was built.'
            Sketchup.active_model.select_tool(nil)
            Sketchup::set_status_text(text, NA_STATUS_PROMPT_KEY)
            self.Na__SelectionPreview__PushStatusToDialog(text)
            true
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private Helpers
    # -------------------------------------------------------------------------

        private

        def Na__SelectionPreview__PathPoints
            Array(@na_path_data[:ordered_points]).compact
        end

        def Na__SelectionPreview__ClosedLoop?
            @na_path_data[:is_closed_loop] == true
        end

        def Na__SelectionPreview__Offsets
            Na__GeometryBuilders.Na__Geometry__NormalisePathOffsets(@na_path_offsets)
        end

        def Na__SelectionPreview__RebuildPreviewCache
            @na_cache_sweep_segments   = []
            @na_cache_profile_polyline = []
            @na_cache_sweep_points     = []
            @na_cache_reason           = nil

            path_points = self.Na__SelectionPreview__PathPoints
            return if path_points.length < 2

            preview_geometry = Na__GeometryBuilders.Na__Geometry__BuildPreviewGeometry(
                profile_data:      @na_profile_data,
                path_data:         @na_path_data,
                start_point:       path_points.first,
                rotation_step:     @na_rotation_step,
                toggle_states:     @na_toggle_states,
                reverse_direction: @na_reverse_direction,
                origin_offset:     @na_origin_offset,
                path_offsets:      @na_path_offsets
            )
            @na_cache_sweep_segments   = Array(preview_geometry[:sweep_segments])
            @na_cache_profile_polyline = Array(preview_geometry[:profile_polyline])
            @na_cache_sweep_points     = Array(preview_geometry[:sweep_points])
            @na_cache_reason           = preview_geometry[:reason]
        end

        def Na__SelectionPreview__ToggleReverse
            self.Na__LiveTool__SetReverseDirection(!@na_reverse_direction)
            return unless defined?(Na__DialogManager)
            Na__DialogManager.Na__Dialog__PushReverseDirectionState(@na_reverse_direction)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Selection preview reverse push warning: #{error.message}")
        end

        def Na__SelectionPreview__RotateStep
            @na_rotation_step = (@na_rotation_step.to_i + 1) % 4
            self.Na__LiveTool__OnPlacementChanged
            return unless defined?(Na__DialogManager)
            Na__DialogManager.Na__Dialog__PushRotationState(@na_rotation_step)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Selection preview rotation push warning: #{error.message}")
        end

        # "Start +150mm" once an offset is set on that end, plain "Start"
        # otherwise. Loops never get here: they have no ends to label.
        def Na__SelectionPreview__EndLabel(label, offset_key)
            offsets   = self.Na__SelectionPreview__Offsets
            offset_mm = offsets ? offsets[offset_key].to_f : 0.0
            return label if offset_mm.zero?
            "#{label} #{format('%+g', offset_mm.round(1))}mm"
        end

        def Na__SelectionPreview__PathSummary
            points        = self.Na__SelectionPreview__PathPoints
            segment_count = [points.length - 1, 0].max
            length_mm     = (Na__GeometryBuilders.Na__Geometry__PolylineLength(points) * NA_INCH_TO_MM).round
            shape         = self.Na__SelectionPreview__ClosedLoop? ? 'closed loop' : 'open run'
            "#{segment_count} segment#{segment_count == 1 ? '' : 's'}, #{shape}, #{self.Na__SelectionPreview__GroupDigits(length_mm)}mm"
        rescue
            'selected path'
        end

        def Na__SelectionPreview__GroupDigits(integer_value)
            digits = integer_value.to_i.abs.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
            integer_value.to_i < 0 ? "-#{digits}" : digits
        end

        def Na__SelectionPreview__UpdateStatusText
            rotation_degrees = @na_rotation_step.to_i * 90
            reverse_suffix   = @na_reverse_direction ? ' | REVERSED' : ''
            lead =
                if @na_cache_reason
                    "Profile Path Tracer PREVIEW — #{@na_cache_reason}"
                else
                    "Profile Path Tracer PREVIEW (#{self.Na__SelectionPreview__PathSummary})"
                end

            next_status = "#{lead} | Enter / double-click commit | TAB reverse | " \
                          "SHIFT+TAB rotate (#{rotation_degrees} deg) | Esc cancel#{reverse_suffix}"
            return if next_status == @na_last_status_text
            Sketchup.status_text = next_status
            @na_last_status_text = next_status
        end

        def Na__SelectionPreview__PushToolStateToDialog(is_active)
            return unless defined?(Na__DialogManager)
            Na__DialogManager.Na__Dialog__PushInteractiveToolState(
                is_active, @na_reverse_direction,
                'toolKind' => NA_TOOL_KIND, 'pathSummary' => self.Na__SelectionPreview__PathSummary
            )
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Selection preview state push warning: #{error.message}")
        end

        def Na__SelectionPreview__PushStatusToDialog(message)
            return unless defined?(Na__DialogManager)
            Na__DialogManager.Na__Dialog__SetStatusFromRuby(message)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Selection preview status push warning: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
