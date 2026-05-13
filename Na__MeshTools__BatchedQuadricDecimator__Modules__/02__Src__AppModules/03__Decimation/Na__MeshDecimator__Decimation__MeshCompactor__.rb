# =============================================================================
# NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - MESH COMPACTOR
# =============================================================================
#
# FILE       : Na__MeshDecimator__Decimation__MeshCompactor__.rb
# NAMESPACE  : Na__MeshDecimator::Na__Decimation::Na__MeshCompactor
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : Two related operations that operate on the flat mesh Hash:
#
#   na_compact_mesh        — strips collapsed/degenerate vertices and triangles,
#                            remaps indices, resets quadric accumulators.
#
#   na_collapse_would_invert_triangles — pre-collapse normal-flip guard;
#                            rejects any collapse that would flip or degenerate
#                            a triangle adjacent to either endpoint.
#
# @delegate: 02__Geometry/Na__MeshDecimator__Geometry__VectorMath__.rb
# @delegate: 02__Geometry/Na__MeshDecimator__Geometry__QuadricMath__.rb
#
# =============================================================================

module Na__MeshDecimator
    module Na__Decimation
        module Na__MeshCompactor

            VectorMath  = Na__MeshDecimator::Na__Geometry::Na__VectorMath
            QuadricMath = Na__MeshDecimator::Na__Geometry::Na__QuadricMath

            EPSILON = Na__MeshDecimator::Na__Geometry::Na__QuadricMath::EPSILON

            # -----------------------------------------------------------------
            # REGION | Mesh Compaction
            # -----------------------------------------------------------------

            # Removes degenerate and zero-area triangles, rebuilds a dense
            # vertex array, and remaps all triangle vertex indices.
            # Quadric accumulators are reset to zero — callers must rebuild
            # them (via Na__MeshSimplifier) before the next pass.
            def self.na_compact_mesh(mesh_data)
                old_vertices  = mesh_data[:vertices]
                old_triangles = mesh_data[:triangles]

                used_lookup     = {}
                compact_triangles = []

                old_triangles.each do |triangle|
                    a, b, c = triangle[:vertices]
                    next if a == b || b == c || c == a

                    p0 = old_vertices[a][:point]
                    p1 = old_vertices[b][:point]
                    p2 = old_vertices[c][:point]

                    next if VectorMath.na_triangle_area_twice(p0, p1, p2) <= EPSILON

                    used_lookup[a] = true
                    used_lookup[b] = true
                    used_lookup[c] = true
                    compact_triangles << triangle
                end

                remap            = {}
                compact_vertices = []

                used_lookup.keys.each do |old_index|
                    remap[old_index] = compact_vertices.length
                    compact_vertices << {
                        :point   => old_vertices[old_index][:point],
                        :quadric => QuadricMath.na_create_zero_quadric
                    }
                end

                compact_triangles.each do |triangle|
                    triangle[:vertices] = triangle[:vertices].map { |i| remap[i] }
                end

                {
                    :vertices    => compact_vertices,
                    :triangles   => compact_triangles,
                    :stopped_early => mesh_data[:stopped_early] || false
                }
            end

            # -----------------------------------------------------------------
            # REGION | Normal-Flip Guard
            # -----------------------------------------------------------------

            # Returns true when moving keep_index and remove_index to
            # collapse_point would flip or zero any adjacent triangle normal.
            def self.na_collapse_would_invert_triangles(vertices, triangles, keep_index, remove_index, collapse_point)
                triangles.each do |triangle|
                    next unless triangle[:vertices].include?(keep_index) ||
                                triangle[:vertices].include?(remove_index)

                    old_points = triangle[:vertices].map { |i| vertices[i][:point] }

                    new_indices = triangle[:vertices].map { |i| i == remove_index ? keep_index : i }
                    next if new_indices.uniq.length < 3

                    new_points = triangle[:vertices].map do |i|
                        (i == keep_index || i == remove_index) ? collapse_point : vertices[i][:point]
                    end

                    old_normal = VectorMath.na_cross_product(
                        VectorMath.na_subtract_points(old_points[1], old_points[0]),
                        VectorMath.na_subtract_points(old_points[2], old_points[0])
                    )

                    new_normal = VectorMath.na_cross_product(
                        VectorMath.na_subtract_points(new_points[1], new_points[0]),
                        VectorMath.na_subtract_points(new_points[2], new_points[0])
                    )

                    return true if VectorMath.na_vector_length(new_normal) <= EPSILON
                    return true if VectorMath.na_dot_product(old_normal, new_normal) < 0.0
                end

                false
            end

        end
    end
end
