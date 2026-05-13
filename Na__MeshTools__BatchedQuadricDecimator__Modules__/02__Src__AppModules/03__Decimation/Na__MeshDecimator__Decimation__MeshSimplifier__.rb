# =============================================================================
# NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - MESH SIMPLIFIER
# =============================================================================
#
# FILE       : Na__MeshDecimator__Decimation__MeshSimplifier__.rb
# NAMESPACE  : Na__MeshDecimator::Na__Decimation::Na__MeshSimplifier
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : Batched Quadric Error Metric (QEM) mesh simplification loop.
#              Drives the multi-pass collapse pipeline:
#
#              na_simplify_mesh
#                -> na_build_initial_quadrics          (accumulate per-vertex Q)
#                -> na_build_edge_data                 (edge -> adjacent triangles)
#                -> na_build_sorted_collapse_candidates (score + sort edges)
#                -> na_choose_non_conflicting_batch     (greedy conflict-free set)
#                -> na_apply_collapse_batch             (rewrite vertex positions)
#                -> Na__MeshCompactor.na_compact_mesh   (strip degenerates)
#
# @delegate: 02__Geometry/Na__MeshDecimator__Geometry__VectorMath__.rb
# @delegate: 02__Geometry/Na__MeshDecimator__Geometry__QuadricMath__.rb
# @delegate: 03__Decimation/Na__MeshDecimator__Decimation__MeshCompactor__.rb
#
# =============================================================================

module Na__MeshDecimator
    module Na__Decimation
        module Na__MeshSimplifier

            VectorMath   = Na__MeshDecimator::Na__Geometry::Na__VectorMath
            QuadricMath  = Na__MeshDecimator::Na__Geometry::Na__QuadricMath
            MeshCompactor = Na__MeshDecimator::Na__Decimation::Na__MeshCompactor

            # -----------------------------------------------------------------
            # REGION | Target Triangle Count
            # -----------------------------------------------------------------

            def self.na_calculate_target_triangle_count(source_count, percentage_decimation)
                keep_ratio = 1.0 - (percentage_decimation.to_f / 100.0)
                target     = (source_count.to_f * keep_ratio).round
                [[target, 4].max, source_count].min
            end

            # -----------------------------------------------------------------
            # REGION | Main Simplification Loop
            # -----------------------------------------------------------------

            def self.na_simplify_mesh(mesh_data, target_triangles, options)
                mesh_data   = MeshCompactor.na_compact_mesh(mesh_data)
                start_time  = Time.now
                stopped_early = false
                pass_index  = 0

                while mesh_data[:triangles].length > target_triangles
                    if (Time.now - start_time) > options[:max_seconds_per_group]
                        stopped_early = true
                        break
                    end

                    if pass_index >= options[:max_passes_per_group]
                        stopped_early = true
                        break
                    end

                    na_build_initial_quadrics(mesh_data[:vertices], mesh_data[:triangles])

                    edge_data  = na_build_edge_data(mesh_data[:triangles])
                    candidates = na_build_sorted_collapse_candidates(mesh_data, edge_data, options)

                    if candidates.empty?
                        stopped_early = true
                        break
                    end

                    batch_size = na_calculate_batch_size(mesh_data[:triangles].length, target_triangles, candidates.length)

                    chosen = na_choose_non_conflicting_batch(candidates, batch_size)

                    if chosen.empty?
                        stopped_early = true
                        break
                    end

                    collapsed = na_apply_collapse_batch(mesh_data, chosen)

                    mesh_data = MeshCompactor.na_compact_mesh(mesh_data)

                    if collapsed <= 0
                        stopped_early = true
                        break
                    end

                    pass_index += 1
                end

                mesh_data[:stopped_early] = stopped_early
                mesh_data
            end

            # -----------------------------------------------------------------
            # REGION | Quadric Initialisation
            # -----------------------------------------------------------------

            def self.na_build_initial_quadrics(vertices, triangles)
                vertices.each { |v| v[:quadric] = QuadricMath.na_create_zero_quadric }

                triangles.each do |triangle|
                    a, b, c = triangle[:vertices]
                    quadric  = QuadricMath.na_create_plane_quadric_from_triangle(
                        vertices[a][:point],
                        vertices[b][:point],
                        vertices[c][:point]
                    )
                    next unless quadric

                    triangle[:vertices].each do |vi|
                        vertices[vi][:quadric] = QuadricMath.na_add_quadrics(vertices[vi][:quadric], quadric)
                    end
                end
            end
            private_class_method :na_build_initial_quadrics

            # -----------------------------------------------------------------
            # REGION | Edge Data Construction
            # -----------------------------------------------------------------

            def self.na_build_edge_data(triangles)
                edges = Hash.new { |h, k| h[k] = [] }

                triangles.each_with_index do |triangle, tri_index|
                    a, b, c = triangle[:vertices]
                    [[a, b], [b, c], [c, a]].each do |u, v|
                        key = u < v ? [u, v] : [v, u]
                        edges[key] << tri_index
                    end
                end

                edges
            end
            private_class_method :na_build_edge_data

            # -----------------------------------------------------------------
            # REGION | Collapse Candidate Scoring
            # -----------------------------------------------------------------

            def self.na_build_sorted_collapse_candidates(mesh_data, edge_data, options)
                vertices   = mesh_data[:vertices]
                triangles  = mesh_data[:triangles]
                candidates = []
                limit      = options[:max_candidate_edges_per_pass]

                edge_data.each do |edge, tri_indices|
                    break if candidates.length >= limit

                    a, b = edge

                    if options[:maintain_border_edges] && tri_indices.length != 2
                        next
                    end

                    if options[:preserve_material_boundary_edges]
                        mat_ids = tri_indices.map { |i| triangles[i][:material].object_id }.uniq
                        next if mat_ids.length > 1
                    end

                    combined_q = QuadricMath.na_add_quadrics(vertices[a][:quadric], vertices[b][:quadric])

                    collapse_point = QuadricMath.na_find_best_collapse_point(
                        combined_q, vertices[a][:point], vertices[b][:point]
                    )

                    next if MeshCompactor.na_collapse_would_invert_triangles(
                        vertices, triangles, a, b, collapse_point
                    )

                    error = QuadricMath.na_calculate_quadric_error(combined_q, collapse_point)

                    candidates << {
                        :keep          => a,
                        :remove        => b,
                        :point         => collapse_point,
                        :quadric       => combined_q,
                        :error         => error
                    }
                end

                candidates.sort_by { |c| c[:error] }
            end
            private_class_method :na_build_sorted_collapse_candidates

            # -----------------------------------------------------------------
            # REGION | Batch Size Calculation
            # -----------------------------------------------------------------

            def self.na_calculate_batch_size(current_triangle_count, target_triangles, candidate_count)
                triangles_to_remove   = current_triangle_count - target_triangles
                collapses_needed      = [(triangles_to_remove.to_f / 2.0).ceil, 1].max
                candidate_percentage  = [(candidate_count.to_f * 0.25).ceil, 1].max
                [collapses_needed, candidate_percentage].min
            end
            private_class_method :na_calculate_batch_size

            # -----------------------------------------------------------------
            # REGION | Conflict-Free Batch Selection
            # -----------------------------------------------------------------

            def self.na_choose_non_conflicting_batch(candidates, batch_limit)
                chosen       = []
                used_vertices = {}

                candidates.each do |candidate|
                    keep_i   = candidate[:keep]
                    remove_i = candidate[:remove]

                    next if used_vertices[keep_i]
                    next if used_vertices[remove_i]

                    chosen << candidate
                    used_vertices[keep_i]   = true
                    used_vertices[remove_i] = true

                    break if chosen.length >= batch_limit
                end

                chosen
            end
            private_class_method :na_choose_non_conflicting_batch

            # -----------------------------------------------------------------
            # REGION | Collapse Application
            # -----------------------------------------------------------------

            def self.na_apply_collapse_batch(mesh_data, chosen_candidates)
                vertices     = mesh_data[:vertices]
                triangles    = mesh_data[:triangles]
                collapse_map = {}
                count        = 0

                chosen_candidates.each do |candidate|
                    keep_i   = candidate[:keep]
                    remove_i = candidate[:remove]

                    collapse_map[remove_i] = keep_i

                    vertices[keep_i][:point]   = candidate[:point]
                    vertices[keep_i][:quadric] = candidate[:quadric]

                    count += 1
                end

                triangles.each do |triangle|
                    triangle[:vertices] = triangle[:vertices].map do |i|
                        collapse_map[i] || i
                    end
                end

                count
            end
            private_class_method :na_apply_collapse_batch

        end
    end
end
