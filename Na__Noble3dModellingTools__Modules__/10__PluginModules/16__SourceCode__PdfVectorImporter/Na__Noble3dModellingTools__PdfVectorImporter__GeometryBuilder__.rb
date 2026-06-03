# =============================================================================
# NA NOBLE3D MODELLING TOOLS - PDF VECTOR IMPORTER - GEOMETRY BUILDER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__PdfVectorImporter__GeometryBuilder__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__PdfVectorImporter__GeometryBuilder
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Convert parsed PDF polylines into SketchUp edges, flattened to the
#              XY plane with the combined bounding box centred on the origin.
# CREATED    : 2026
#
# DESCRIPTION:
# - Input polylines are point pairs expressed in PDF points (1/72 inch).
# - Points are scaled to SketchUp inches, all placed on the XY plane (Z = 0).
# - The combined bounding box is translated so its centre sits at 0,0,0.
# - All linework is added to one named group inside a single undo operation.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__PdfVectorImporter__GeometryBuilder

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_POINTS_PER_INCH       = 72.0        # PDF user-space units per inch
        NA_DEDUPE_TOLERANCE      = 1.0e-6       # Minimum spacing between kept points
        NA_BUILD_OPERATION_NAME  = 'Import PDF Vector Lines'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Build a Centred Group of Edges from Parsed Polylines
        # ------------------------------------------------------------
        def self.Na__PdfVectorImporter__BuildCenteredGroup(polylines, scale_factor, group_name)
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model
            return na_result(false, 'No vector lines to import.') if polylines.nil? || polylines.empty?

            su_polylines = na_convert_polylines_to_inches(polylines, scale_factor)
            su_polylines = su_polylines.reject { |polyline| polyline.length < 2 }
            return na_result(false, 'No usable vector lines after conversion.') if su_polylines.empty?

            offset       = na_centering_offset(su_polylines)
            su_polylines = na_translate_polylines(su_polylines, offset)

            operation_started = false
            model.start_operation(NA_BUILD_OPERATION_NAME, true)
            operation_started = true

            group      = model.active_entities.add_group
            group.name = group_name
            edge_count = na_add_polyline_edges(group.entities, su_polylines)

            if edge_count.zero?
                model.abort_operation
                return na_result(false, 'SketchUp could not create any edges from the PDF paths.')
            end

            model.selection.clear
            model.selection.add(group) if group.valid?
            model.commit_operation
            operation_started = false

            na_result(
                true,
                "Imported #{edge_count} edge(s) from #{su_polylines.length} path(s).",
                group:      group,
                edge_count: edge_count,
                path_count: su_polylines.length
            )
        rescue => error
            model.abort_operation if model && operation_started
            na_result(false, "Geometry build failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Coordinate Conversion
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert PDF-Point Polylines to SketchUp Inch Points
        # ------------------------------------------------------------
        def self.na_convert_polylines_to_inches(polylines, scale_factor)
            factor         = scale_factor.to_f
            factor         = 1.0 if factor <= 0.0
            inch_per_point = (1.0 / NA_POINTS_PER_INCH) * factor

            polylines.map do |polyline|
                points = polyline.map do |x, y|
                    Geom::Point3d.new(x * inch_per_point, y * inch_per_point, 0.0)
                end
                na_dedupe_consecutive(points)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Remove Consecutive Duplicate Points
        # ------------------------------------------------------------
        def self.na_dedupe_consecutive(points)
            result = []
            points.each do |point|
                last_point = result.last
                if last_point.nil? || last_point.distance(point) > NA_DEDUPE_TOLERANCE
                    result << point
                end
            end
            result
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Centering Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build Translation Vector to Centre Bounds at Origin
        # ------------------------------------------------------------
        def self.na_centering_offset(polylines)
            bounds = Geom::BoundingBox.new
            polylines.each { |polyline| polyline.each { |point| bounds.add(point) } }
            return Geom::Vector3d.new(0, 0, 0) unless bounds.valid?

            centre = bounds.center
            Geom::Vector3d.new(-centre.x, -centre.y, -centre.z)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Translate All Polyline Points by an Offset Vector
        # ------------------------------------------------------------
        def self.na_translate_polylines(polylines, offset)
            transformation = Geom::Transformation.translation(offset)
            polylines.map do |polyline|
                polyline.map { |point| point.transform(transformation) }
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edge Creation
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Add One Polyline of Edges per Path
        # ------------------------------------------------------------
        def self.na_add_polyline_edges(entities, polylines)
            total_edges = 0
            polylines.each do |points|
                next if points.length < 2
                begin
                    created = entities.add_edges(points)
                    total_edges += created.length if created
                rescue ArgumentError, TypeError, RuntimeError
                    next                                                  # <-- Skip degenerate path, keep importing
                end
            end
            total_edges
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text, extra = {})
            { success: !!success_flag, message: message_text.to_s }.merge(extra)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PdfVectorImporter__GeometryBuilder
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
