# =============================================================================
# NA ARRAY BUILDER TOOLS - PREVIEW RENDER MIXIN
# =============================================================================
#
# FILE       : Na__ArrayBuilder__PreviewRenderMixin__.rb
# NAMESPACE  : Na__ArrayBuilderTools::Na__ArrayBuilder__PreviewRenderMixin
# AUTHOR     : Noble Architecture
# PURPOSE    : Shared array-preview engine `include`d into both the
#              draw-path tool (Na__ArrayBuilder__PathTool) and the
#              selection-review tool (Na__ArrayBuilder__SelectionArrayTool).
#              Owns config-state resolution, distribution routing, and
#              the batched wireframe preview + info-text overlay.
# CREATED    : 2026
# VERSION    : 0.1.0
#
# DESCRIPTION:
# - Host tools call na_init_unit_config_state(config) from initialize.
#   It populates @array_type, @anchor_mode, @keep_upright, @spacing,
#   @distribution, @inset, @unit_width/@unit_depth/@unit_height and (for
#   object mode) @na_obj_envelope.
# - Preview boxes are drawn with the SAME anchor convention the
#   geometry builder places with: the unit's leading bbox face sits at
#   the computed position, and for object mode the lateral / vertical
#   envelope comes from the real scaled bbox offsets (so what you see
#   is exactly what gets built, including offset component origins).
# - Position + spacing math delegates to Na__ArrayBuilder__Distribution
#   so the preview, the placed geometry and the reported actual spacing
#   share one implementation.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__ArrayBuilder__Distribution__'
require_relative 'Na__ArrayBuilder__ObjectRegistry__'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__PreviewRenderMixin

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_INCH_TO_MM     = 25.4
        NA_PREVIEW_COLOR  = Sketchup::Color.new(0, 200, 180, 160)
        NA_TEXT_COLOR     = Sketchup::Color.new(255, 255, 255)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Config State Resolution
# -----------------------------------------------------------------------------

        # FUNCTION | Initialise Shared Unit / Distribution State From Config
        # ------------------------------------------------------------
        def na_init_unit_config_state(config)
            @array_type   = config['type'] || 'dentil'
            @anchor_mode  = config['anchor_mode'] || 'local_axis'
            @keep_upright = config['keep_upright'] == true                         # <-- Locks unit +Z to world +Z when true
            @spacing      = (config['spacing_mm'] || 115).to_f.mm

            # Distribution mode: 'fixed' (default) | 'normalise' | 'inset'.
            # Falls back to the legacy `normalise_distance` boolean so
            # any in-flight cached config stays compatible.
            @distribution = config['distribution']
            @distribution ||= (config['normalise_distance'] ? 'normalise' : 'fixed')
            @inset        = (config['inset_mm'] || 200).to_f.mm

            na_resolve_unit_dimensions(config)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Unit Dimensions for Current Array Type
        # ------------------------------------------------------------
        # In 'object' mode the per-step unit width, the preview envelope
        # and the anchor offsets are derived from the picked definition's
        # scaled bounding box. For dentil / dogtooth they come straight
        # from the dialog config. Falls back to the dialog-provided
        # values if no object has been picked yet (validation in
        # DialogManager prevents this in practice).
        def na_resolve_unit_dimensions(config)
            @na_obj_envelope = nil

            if @array_type == 'object'
                info = Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetPlacementInfo
                if info
                    @unit_width      = info[:width]
                    @unit_depth      = info[:depth]
                    @unit_height     = info[:height]
                    @na_obj_envelope = na_build_object_envelope(info)
                    return
                end
            end

            @unit_width  = (config['unit_width_mm']  || 110).to_f.mm
            @unit_depth  = (config['unit_depth_mm']   || 30).to_f.mm
            @unit_height = (config['unit_height_mm']  || 75).to_f.mm
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build the Object Preview Envelope (Unit-Local Extents)
        # ------------------------------------------------------------
        # Extents relative to the path point, matching GeometryBuilder's
        # anchor offset exactly. Forward is always [0, width] (leading
        # face pinned); lateral / vertical depend on the anchor mode.
        def na_build_object_envelope(info)
            if @anchor_mode == 'centre'
                {
                    lat_min: -info[:depth]  * 0.5,
                    lat_max:  info[:depth]  * 0.5,
                    up_min:  -info[:height] * 0.5,
                    up_max:   info[:height] * 0.5
                }
            else
                {
                    lat_min: info[:scaled_min_y],
                    lat_max: info[:scaled_max_y],
                    up_min:  info[:scaled_min_z],
                    up_max:  info[:scaled_max_z]
                }
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Distribution Routing
# -----------------------------------------------------------------------------

        # FUNCTION | Calculate Unit Positions Along Path
        # ------------------------------------------------------------
        def na_calculate_preview_positions(path_points)
            Na__ArrayBuilder__Distribution.Na__Distribution__CalculatePositions(
                path_points, @distribution, @unit_width, @spacing, @inset
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Calculate Average Actual Spacing in mm (Mode-Aware)
        # ------------------------------------------------------------
        def na_calculate_actual_spacing_mm(path_points)
            Na__ArrayBuilder__Distribution.Na__Distribution__CalculateActualSpacingMm(
                path_points, @distribution, @unit_width, @spacing, @inset
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Calculate Total Path Length in mm
        # ------------------------------------------------------------
        def na_path_length_mm(path_points)
            total = 0.0
            (0...path_points.length - 1).each do |i|
                total += path_points[i].distance(path_points[i + 1])
            end
            total * NA_INCH_TO_MM
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Preview Unit Drawing
# -----------------------------------------------------------------------------

        # FUNCTION | Draw All Preview Units (Batched)
        # ------------------------------------------------------------
        # Collects every preview-unit wireframe segment into one flat
        # array, then issues a single view.draw(GL_LINES, ...) call so
        # N units = 1 GL call instead of 12*N.
        def na_draw_preview_units(view, positions)
            return if positions.empty?

            segments = []
            positions.each do |pos|
                na_collect_preview_unit_segments(pos[:point], pos[:direction], segments)
            end

            return if segments.empty?

            view.line_width    = 1
            view.drawing_color = NA_PREVIEW_COLOR
            view.draw(GL_LINES, segments)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Collect Wireframe Segments for One Preview Unit
        # ------------------------------------------------------------
        # Computes the 8 oriented corners of one preview envelope and
        # pushes 24 points (12 line segments) onto the shared segments
        # array. Object mode uses the real scaled bbox offsets so the
        # preview matches the placed geometry exactly.
        def na_collect_preview_unit_segments(origin, direction, segments)
            basis     = na_unit_basis_vectors(direction)
            forward   = basis[:forward]
            lateral   = basis[:lateral]
            actual_up = basis[:up]

            if @array_type == 'dogtooth'
                rot = Geom::Transformation.rotation(origin, forward, 45.degrees)
                lateral   = lateral.transform(rot)
                actual_up = actual_up.transform(rot)
            end

            if @na_obj_envelope
                env = @na_obj_envelope
                corners = na_compute_envelope_corners(
                    origin, forward, lateral, actual_up,
                    0.0, @unit_width,
                    env[:lat_min], env[:lat_max],
                    env[:up_min],  env[:up_max]
                )
            else
                half_d = @unit_depth * 0.5
                corners = na_compute_envelope_corners(
                    origin, forward, lateral, actual_up,
                    0.0, @unit_width,
                    -half_d, half_d,
                    0.0, @unit_height
                )
            end

            na_collect_wireframe_box_segments(corners, segments)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build the Per-Unit Orthonormal Basis
        # ------------------------------------------------------------
        # Mirrors GeometryBuilder's basis construction exactly (both the
        # follow-path and keep-upright branches) so the preview can never
        # drift from the placed geometry.
        def na_unit_basis_vectors(direction)
            if @keep_upright
                forward = na_horizontal_forward_for_preview(direction)
                lateral = forward.cross(Z_AXIS)
                lateral.length = 1.0 if lateral.length > 0
                { forward: forward, lateral: lateral, up: Z_AXIS.clone }           # <-- Preview must mirror placement: locked to world +Z
            else
                forward = direction.nil? ? X_AXIS.clone : direction.clone
                forward.length = 1.0 if forward.length > 0

                lateral = forward.cross(Z_AXIS)
                if lateral.length < 0.001
                    lateral = Y_AXIS.clone
                else
                    lateral.length = 1.0
                end

                up = lateral.cross(forward)
                up.length = 1.0 if up.length > 0

                { forward: forward, lateral: lateral, up: up }
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Horizontally-Projected Forward For Keep-Upright Preview
        # ------------------------------------------------------------
        # Mirrors GeometryBuilder.na_horizontal_forward_or_default so the
        # live wireframe preview matches the placed geometry exactly.
        # Falls back to X_AXIS when the segment is (near-)vertical and
        # projection would collapse to zero length.
        def na_horizontal_forward_for_preview(direction)
            return X_AXIS.clone if direction.nil?

            horiz = Geom::Vector3d.new(direction.x, direction.y, 0.0)
            return X_AXIS.clone if horiz.length < 0.001

            horiz.length = 1.0
            horiz
        end
        # ---------------------------------------------------------------

        # FUNCTION | Compute 8 Corners of an Oriented Envelope
        # ------------------------------------------------------------
        # Generalised oriented box: extents are given per local axis
        # (f0..f1 forward, l0..l1 lateral, u0..u1 up) relative to the
        # origin. Corner ordering matches
        # na_collect_wireframe_box_segments (0-3 bottom, 4-7 top).
        def na_compute_envelope_corners(origin, fwd, lat, up, f0, f1, l0, l1, u0, u1)
            corners = []
            [u0, u1].each do |u|
                [[f0, l0], [f1, l0], [f1, l1], [f0, l1]].each do |f, l|
                    corners << origin.offset(fwd, f).offset(lat, l).offset(up, u)
                end
            end
            corners
        end
        # ---------------------------------------------------------------

        # FUNCTION | Append the 12 Edges of an Oriented Box to a Segments Array
        # ------------------------------------------------------------
        # Each segment is two consecutive points. SketchUp's GL_LINES
        # treats every pair of points as one segment.
        def na_collect_wireframe_box_segments(c, segments)
            # Bottom face
            segments << c[0] << c[1]
            segments << c[1] << c[2]
            segments << c[2] << c[3]
            segments << c[3] << c[0]

            # Top face
            segments << c[4] << c[5]
            segments << c[5] << c[6]
            segments << c[6] << c[7]
            segments << c[7] << c[4]

            # Verticals
            segments << c[0] << c[4]
            segments << c[1] << c[5]
            segments << c[2] << c[6]
            segments << c[3] << c[7]
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Info Text Overlay
# -----------------------------------------------------------------------------

        # FUNCTION | Draw Array Info Text Near an Anchor Point
        # ------------------------------------------------------------
        # @param anchor_point [Geom::Point3d] World point the label hangs off
        def na_draw_array_info_text(view, positions, path_points, anchor_point)
            return if anchor_point.nil?

            total_mm          = na_path_length_mm(path_points)
            count             = positions.length
            target_spacing_mm = (@spacing * NA_INCH_TO_MM).round
            inset_mm          = (@inset   * NA_INCH_TO_MM).round
            actual_mm         = na_calculate_actual_spacing_mm(path_points)

            label =
                case @distribution
                when 'inset'
                    if actual_mm
                        "#{count} units | Inset: #{inset_mm}mm | Actual: #{actual_mm}mm (target: #{target_spacing_mm}mm) | Length: #{total_mm.round}mm"
                    else
                        "#{count} units | Inset: #{inset_mm}mm | Length: #{total_mm.round}mm"
                    end
                when 'normalise'
                    if actual_mm
                        "#{count} units | Actual: #{actual_mm}mm (target: #{target_spacing_mm}mm) | Length: #{total_mm.round}mm"
                    else
                        "#{count} units | Normalised | Length: #{total_mm.round}mm"
                    end
                else
                    "#{count} units | Spacing: #{target_spacing_mm}mm | Length: #{total_mm.round}mm"
                end

            screen_pt  = view.screen_coords(anchor_point)
            text_point = Geom::Point3d.new(screen_pt.x + 20, screen_pt.y - 30, 0)

            view.drawing_color = NA_TEXT_COLOR
            view.draw_text(text_point, label)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ArrayBuilder__PreviewRenderMixin
end # module Na__ArrayBuilderTools

# =============================================================================
# END OF FILE
# =============================================================================
