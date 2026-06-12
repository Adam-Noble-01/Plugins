# =============================================================================
# NA NOBLE3D MODELLING TOOLS - PNG TO LINEWORK - GEOMETRY BUILDER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__PngToLinework__GeometryBuilder__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__PngToLinework__GeometryBuilder
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Convert traced polylines (millimetres) into a SketchUp component
#              of plain segmented edges, centred on the component origin.
# CREATED    : 2026
#
# DESCRIPTION:
# - Input polylines arrive already centred on their bounding-box centre, in
#   millimetres, from the dialog's JS trace engine (model Y-up convention).
# - Vertical plane maps (x, y) -> (X, 0, Z) so elevations (trees, people) stand up.
# - Ground plane maps (x, y) -> (X, Y, 0) for plan linework.
# - Geometry is built inside an OPEN model operation which the placement tool
#   commits on click (one undo step) or aborts on ESC (clean cancel).
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__PngToLinework__GeometryBuilder

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_BUILD_OPERATION_NAME = 'PNG To Linework'.freeze
        NA_MM_PER_INCH          = 25.4
        NA_MAX_EDGE_COUNT       = 50_000                                      # <-- Hard crash-guard mirrored in the dialog JS

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Build a Centred Linework Component Inside an Open Operation
        # ------------------------------------------------------------
        def self.Na__PngToLinework__BuildLineworkComponent(polylines_mm, plane_mode, component_name)
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model
            return na_result(false, 'No traced polylines to build.') if polylines_mm.nil? || polylines_mm.empty?

            segment_count = polylines_mm.sum { |polyline| [polyline.length - 1, 0].max }
            if segment_count > NA_MAX_EDGE_COUNT
                return na_result(false, "Trace produces #{segment_count} edges (limit #{NA_MAX_EDGE_COUNT}). Increase the minimum segment length.")
            end

            su_polylines = na_convert_polylines_to_points(polylines_mm, plane_mode)
            su_polylines = su_polylines.reject { |polyline| polyline.length < 2 }
            return na_result(false, 'No usable polylines after conversion.') if su_polylines.empty?

            model.start_operation(NA_BUILD_OPERATION_NAME, true)

            definition = model.definitions.add(component_name)
            edge_count = na_add_polyline_edges(definition.entities, su_polylines)

            if edge_count.zero?
                model.abort_operation
                return na_result(false, 'SketchUp could not create any edges from the traced paths.')
            end

            instance      = model.active_entities.add_instance(definition, IDENTITY)
            instance.name = component_name

            na_result(
                true,
                "Built #{edge_count} edge(s) from #{su_polylines.length} path(s).",
                instance:   instance,
                edge_count: edge_count,
                path_count: su_polylines.length
            )
        rescue => error
            model.abort_operation if model
            na_result(false, "Geometry build failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Coordinate Conversion
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert Millimetre Polylines to SketchUp Inch Points
        # ------------------------------------------------------------
        def self.na_convert_polylines_to_points(polylines_mm, plane_mode)
            vertical = (plane_mode.to_s != 'ground')

            polylines_mm.map do |polyline|
                polyline.map do |point_mm|
                    x_in = point_mm[0].to_f / NA_MM_PER_INCH
                    y_in = point_mm[1].to_f / NA_MM_PER_INCH
                    if vertical
                        Geom::Point3d.new(x_in, 0.0, y_in)                    # <-- Elevation linework stands on the X-Z plane
                    else
                        Geom::Point3d.new(x_in, y_in, 0.0)                    # <-- Plan linework lies on the ground plane
                    end
                end
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edge Creation
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Add One Run of Edges per Polyline
        # ------------------------------------------------------------
        def self.na_add_polyline_edges(entities, polylines)
            total_edges = 0
            polylines.each do |points|
                next if points.length < 2
                begin
                    created = entities.add_edges(points)
                    total_edges += created.length if created
                rescue ArgumentError, TypeError, RuntimeError
                    next                                                      # <-- Skip degenerate path, keep building
                end
            end
            total_edges
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helper
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text, extra = {})
            { success: !!success_flag, message: message_text.to_s }.merge(extra)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PngToLinework__GeometryBuilder
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
