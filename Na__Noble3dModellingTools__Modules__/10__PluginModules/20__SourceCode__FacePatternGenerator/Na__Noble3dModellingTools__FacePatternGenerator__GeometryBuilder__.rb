# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FACE PATTERN GENERATOR - GEOMETRY BUILDER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__FacePatternGenerator__GeometryBuilder__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__FacePatternGenerator__GeometryBuilder
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Convert dialog polylines (local millimetres) into SketchUp edges
#              on the selected face plane inside a named undo-safe group.
# CREATED    : 2026
#
# DESCRIPTION:
# - Input polylines arrive in local 2D millimetres from the dialog JavaScript.
# - The face basis (origin + orthonormal axes) is round-tripped in the apply payload.
# - lift_mm offsets geometry along the face normal (positive-Z side).
# - close_paths adds a closing edge when the first and last points differ.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__FacePatternGenerator__GeometryBuilder

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OPERATION_NAME = 'Face Pattern Generator - Apply Pattern'.freeze
        NA_MAX_SEGMENTS   = 75_000

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Apply Edge-Based Pattern Polylines to the Active Model
        # ------------------------------------------------------------
        def self.Na__FacePatternGenerator__ApplyPolylines(payload_hash)
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            polylines = payload_hash['polylines']
            return na_result(false, 'No polyline geometry was provided by the dialog.') if !polylines.is_a?(Array) || polylines.empty?

            basis = payload_hash['basis']
            return na_result(false, 'Missing local face basis in payload.') unless basis.is_a?(Hash)

            segment_count = polylines.sum { |polyline| [polyline.length - 1, 0].max }
            return na_result(false, "Pattern has #{segment_count} segments (limit #{NA_MAX_SEGMENTS}).") if segment_count > NA_MAX_SEGMENTS

            lift_mm     = payload_hash.fetch('lift_mm', 0.0).to_f
            close_paths = payload_hash.fetch('close_paths', true)
            group_name  = payload_hash.fetch('group_name', 'Na Face Pattern').to_s

            model.start_operation(NA_OPERATION_NAME, true)
            pattern_group = model.active_entities.add_group
            pattern_group.name = group_name

            edge_total = 0
            polylines.each do |polyline|
                edge_total += na_add_polyline_edges(pattern_group.entities, polyline, basis, lift_mm, close_paths)
            end

            if edge_total.zero?
                model.abort_operation
                return na_result(false, 'No valid edges were created from the generated pattern.')
            end

            model.commit_operation
            na_result(true, "Pattern applied with #{edge_total} edge(s).", edge_count: edge_total)
        rescue => error
            model.abort_operation if model
            na_result(false, "Pattern apply failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edge Creation
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Add One Run of Edges for a Single Polyline
        # ------------------------------------------------------------
        def self.na_add_polyline_edges(entities, polyline, basis_hash, lift_mm, close_paths)
            return 0 unless polyline.is_a?(Array) && polyline.length >= 2

            points = polyline.map { |point| na_local_mm_to_world_point(point, basis_hash, lift_mm) }.compact
            return 0 if points.length < 2

            edge_count = 0
            (0...(points.length - 1)).each do |index|
                edge = entities.add_line(points[index], points[index + 1])
                edge_count += 1 if edge
            end

            if close_paths
                first_point = points.first
                last_point  = points.last
                unless first_point.distance(last_point) < 0.001
                    edge = entities.add_line(last_point, first_point)
                    edge_count += 1 if edge
                end
            end

            edge_count
        rescue ArgumentError, TypeError, RuntimeError
            0                                                                       # <-- Skip degenerate path, keep building
        end
        private_class_method :na_add_polyline_edges
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Coordinate Conversion
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert Local [x_mm, y_mm] to a World Point3d
        # ------------------------------------------------------------
        def self.na_local_mm_to_world_point(point_mm, basis_hash, lift_mm)
            return nil unless point_mm.is_a?(Array) && point_mm.length >= 2

            origin = basis_hash['origin']
            x_axis = basis_hash['x_axis']
            y_axis = basis_hash['y_axis']
            z_axis = basis_hash['z_axis']
            return nil unless origin && x_axis && y_axis && z_axis

            world_point = Geom::Point3d.new(origin[0].to_f, origin[1].to_f, origin[2].to_f)
                .offset(Geom::Vector3d.new(x_axis[0].to_f, x_axis[1].to_f, x_axis[2].to_f), point_mm[0].to_f.mm)
                .offset(Geom::Vector3d.new(y_axis[0].to_f, y_axis[1].to_f, y_axis[2].to_f), point_mm[1].to_f.mm)

            return world_point if lift_mm.to_f.zero?

            world_point.offset(Geom::Vector3d.new(z_axis[0].to_f, z_axis[1].to_f, z_axis[2].to_f), lift_mm.to_f.mm)
        end
        private_class_method :na_local_mm_to_world_point
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
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__FacePatternGenerator__GeometryBuilder
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
