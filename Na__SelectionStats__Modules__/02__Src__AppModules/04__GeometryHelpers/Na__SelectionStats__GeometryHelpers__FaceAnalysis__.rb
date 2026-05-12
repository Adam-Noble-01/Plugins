# frozen_string_literal: true

# =============================================================================
# NA SELECTION STATISTICS - GEOMETRY HELPERS · FACE ANALYSIS
# =============================================================================
#
# FILE       : Na__SelectionStats__GeometryHelpers__FaceAnalysis__.rb
# PURPOSE    : Polygon triangulation counts and native face shape checks.
#
# =============================================================================

require 'sketchup.rb'

module Na__SelectionStats
    module Na__GeometryHelpers
        module Na__FaceAnalysis
            extend self

# -----------------------------------------------------------------------------
# REGION | Triangulated Polygon Counting
# -----------------------------------------------------------------------------

            def na_count_triangulated_mesh_polygons(face)
                mesh = face.mesh(0)
                return 0 unless mesh

                mesh.polygons.reduce(0) do |total, polygon|
                    polygon_vertex_count = polygon.map { |index| index.to_i.abs }.uniq.length
                    total + (polygon_vertex_count <= 3 ? 1 : polygon_vertex_count - 2)
                end
            rescue StandardError
                0
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Native Loop Shape
# -----------------------------------------------------------------------------

            def na_face_is_simple_native_triangle?(face)
                face.loops.length == 1 && face.outer_loop.vertices.length == 3
            rescue StandardError
                false
            end

            def na_face_is_simple_native_quad?(face)
                face.loops.length == 1 && face.outer_loop.vertices.length == 4
            rescue StandardError
                false
            end

# endregion -------------------------------------------------------------------

        end
    end
end
