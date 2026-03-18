# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - PATH SELECTION TOOL
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__PathSelectionTool__.rb
# PURPOSE    : Interactive path picking tool (scaffold placeholder)
# CREATED    : 2026
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    class Na__PathSelectionTool
        include Na__ProfileTools__ProfilePathTracer::Na__KeyboardHandlers

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_VERTEX_PICK_TOLERANCE = Na__PathAnalysis::NA_VERTEX_PICK_TOLERANCE
        NA_DEFAULT_CROSSHAIR_SIZE = 300.mm
        NA_STATUS_PROMPT_KEY      = SB_PROMPT

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Initialization / State
    # -------------------------------------------------------------------------

        def initialize(profile_key, profile_data, path_data)
            @na_profile_key      = profile_key
            @na_profile_data     = profile_data || {}
            @na_path_data        = path_data || {}
            @na_ordered_points   = @na_path_data[:ordered_points] || @na_path_data['ordered_points'] || []

            @na_input_point      = Sketchup::InputPoint.new
            @na_cursor_point     = nil
            @na_candidate_vertex = nil
            @na_rotation_step    = 0
            @na_key_tab_held     = false
            @na_crosshair_size   = NA_DEFAULT_CROSSHAIR_SIZE
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Tool Lifecycle
    # -------------------------------------------------------------------------

        def activate
            self.Na__Keyboard__UpdateStatusText
        end

        def resume(view)
            self.Na__Keyboard__UpdateStatusText
            view.invalidate
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Mouse Interaction
    # -------------------------------------------------------------------------

        def onMouseMove(_flags, x, y, view)
            @na_input_point.pick(view, x, y)
            @na_cursor_point = @na_input_point.position
            @na_candidate_vertex = Na__PathAnalysis.Na__Path__FindNearestVertex(
                @na_ordered_points,
                @na_cursor_point,
                NA_VERTEX_PICK_TOLERANCE
            )
            view.invalidate
        end

        def onLButtonDown(_flags, x, y, view)
            @na_input_point.pick(view, x, y)
            click_point = @na_input_point.position
            start_vertex = Na__PathAnalysis.Na__Path__FindNearestVertex(@na_ordered_points, click_point, NA_VERTEX_PICK_TOLERANCE)

            unless start_vertex
                UI.beep
                Sketchup::set_status_text('Click a vertex on the selected path.', NA_STATUS_PROMPT_KEY)
                return
            end

            result = Na__ProfilePlacementEngine.Na__Engine__GenerateFromPathData(
                profile_key: @na_profile_key,
                profile_data: @na_profile_data,
                path_data: @na_path_data,
                start_point: start_vertex,
                rotation_step: @na_rotation_step
            )

            Sketchup::set_status_text(result['statusMessage'].to_s, NA_STATUS_PROMPT_KEY)
            view.invalidate
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Tool Rendering
    # -------------------------------------------------------------------------

        def draw(view)
            return unless @na_cursor_point

            @na_input_point.draw(view)
            Na__PreviewGraphics.Na__Preview__DrawCrosshair(view, @na_cursor_point, @na_crosshair_size)
            Na__PreviewGraphics.Na__Preview__DrawPath(view, @na_ordered_points)
            Na__PreviewGraphics.Na__Preview__DrawCandidateVertex(view, @na_candidate_vertex)

            return unless @na_candidate_vertex
            preview_polyline = Na__GeometryBuilders.Na__Geometry__BuildPreviewProfilePolyline(
                profile_data: @na_profile_data,
                path_data: @na_path_data,
                start_point: @na_candidate_vertex,
                rotation_step: @na_rotation_step
            )
            Na__PreviewGraphics.Na__Preview__DrawProfileGhost(view, preview_polyline)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Deactivate / Cleanup
    # -------------------------------------------------------------------------

        def deactivate(_view)
            Sketchup.status_text = ''
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
