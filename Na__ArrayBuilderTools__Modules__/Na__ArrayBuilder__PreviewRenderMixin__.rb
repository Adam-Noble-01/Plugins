# =============================================================================
# NA ARRAY BUILDER TOOLS - PREVIEW RENDER MIXIN
# =============================================================================
# FILE       : Na__ArrayBuilder__PreviewRenderMixin__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Shared live preview using the geometry engine's exact transforms.
# =============================================================================

require_relative 'Na__ArrayBuilder__LayoutEngine__'
require_relative 'Na__ArrayBuilder__ObjectRegistry__'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__PreviewRenderMixin

        NA_PREVIEW_EDGES = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].freeze

        # FUNCTION | Resolve New Controls Without Discarding the Drawn Path
        # ------------------------------------------------------------
        def na_init_unit_config_state(na_config)
            @config = Na__ArrayBuilder__Configuration.Na__Config__Resolve(na_config)
            @array_type = @config['type']
            @na_source = @array_type == 'object' ? Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetPlacementInfo : nil
            @na_plan = nil
        end

        def na_calculate_preview_positions(na_points)
            na_transform = @config['path_source'] == 'draw' ? @dialog_manager.Na__Dialog__PreviewFrame : Geom::Transformation.new
            na_inverse = na_transform.inverse
            na_local = na_points.map { |na_point| na_point.transform(na_inverse) }
            @na_plan = Na__ArrayBuilder__LayoutEngine.Na__Layout__Resolve(@config, na_local, @na_source)
            @dialog_manager.na_send_preview_info(@na_plan[:positions].length, @na_plan[:length_mm], @na_plan[:gap_mm])
            @dialog_manager.Na__Dialog__QueuePreview(@na_plan)
            @na_plan[:positions]
        rescue ArgumentError => na_error
            @na_plan = nil
            @dialog_manager.na_send_preview_info(0, 0, nil)
            @dialog_manager.na_send_status_to_dialog('warning', na_error.message)
            []
        end

        def na_calculate_actual_spacing_mm(_na_points)
            @na_plan && @na_plan[:gap_mm]
        end

        def na_path_length_mm(na_points)
            return @na_plan[:length_mm] if @na_plan
            na_points.each_cons(2).sum { |na_a, na_b| na_a.distance(na_b) * 25.4 }
        end

        # FUNCTION | Draw Every Envelope in One View Call
        # ------------------------------------------------------------
        def na_draw_preview_units(na_view, na_positions)
            return unless @na_plan && !na_positions.empty?
            na_segments = []
            na_transform = @dialog_manager.Na__Dialog__PreviewFrame
            na_positions.each do |na_position|
                na_corners = Na__ArrayBuilder__LayoutEngine.Na__Layout__Corners(na_position, @na_plan[:config], @na_source)
                na_corners.map! { |na_point| na_point.transform(na_transform) }
                NA_PREVIEW_EDGES.each { |na_a, na_b| na_segments << na_corners[na_a] << na_corners[na_b] }
            end
            na_view.line_width = 2
            na_view.drawing_color = Sketchup::Color.new(26, 115, 232, 200)
            na_view.draw(GL_LINES, na_segments)
        end

        def na_draw_array_info_text(na_view, na_positions, _na_points, _na_anchor)
            return unless @na_plan
            na_label = "#{na_positions.length} units  |  #{@na_plan[:length_mm].round} mm path  |  #{@na_plan[:gap_mm].round(1)} mm gap"
            na_view.draw_text([20, 30], na_label, color: Sketchup::Color.new(26, 80, 140), size: 12)
        end

    end # module Na__ArrayBuilder__PreviewRenderMixin
end # module Na__ArrayBuilderTools
