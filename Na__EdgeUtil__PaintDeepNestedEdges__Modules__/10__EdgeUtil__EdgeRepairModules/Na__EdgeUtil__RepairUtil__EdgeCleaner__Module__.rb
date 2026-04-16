# =============================================================================
# NA EDGE UTIL - EDGE TOOLS - EDGE CLEANER
# =============================================================================
#
# FILE       : Na__EdgeUtil__RepairUtil__EdgeCleaner__Module__.rb
# NAMESPACE  : Na__EdgeUtil__PaintDeepNestedEdges::Na__EdgeTools__EdgeCleaner
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Remove redundant colinear interior vertices from selected edges
# CREATED    : 16-Apr-2026
#
# =============================================================================

require 'sketchup.rb'

module Na__EdgeUtil__PaintDeepNestedEdges

# -----------------------------------------------------------------------------
# REGION | Edge Cleaner Module
# -----------------------------------------------------------------------------

    module Na__EdgeTools__EdgeCleaner

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        # MODULE CONSTANTS | Geometry Tolerances
        # ------------------------------------------------------------
        NA_MIN_EDGE_LENGTH          = 0.001
        NA_COLINEAR_ANGLE_TOLERANCE = 0.005
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Colinear Interior Vertex Detection
# -----------------------------------------------------------------------------

        # PURE FUNCTION | Identify Interior Vertices That Are Colinear
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__EdgeCleaner__FindInteriorVertices(edges)
            interior_vertices = []
            all_vertices      = edges.flat_map(&:vertices).uniq

            all_vertices.each do |vertex|
                next unless vertex&.valid?

                connected_edges = vertex.edges
                next unless connected_edges.length == 2

                edge_a, edge_b = connected_edges
                next unless edges.include?(edge_a) && edges.include?(edge_b)
                next if edge_a.length < NA_MIN_EDGE_LENGTH || edge_b.length < NA_MIN_EDGE_LENGTH

                vector_a = edge_a.line && edge_a.line[1]
                vector_b = edge_b.line && edge_b.line[1]
                next unless vector_a&.valid? && vector_b&.valid?

                angle       = vector_a.angle_between(vector_b)
                is_colinear = angle < NA_COLINEAR_ANGLE_TOLERANCE || (Math::PI - angle).abs < NA_COLINEAR_ANGLE_TOLERANCE
                interior_vertices << vertex if is_colinear
            end

            interior_vertices
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Interior Vertex Chains
# -----------------------------------------------------------------------------

        # PURE FUNCTION | Build Sequential Chains of Interior Vertices
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__EdgeCleaner__BuildChains(interior_vertices)
            chains             = []
            visited_interiors  = []

            interior_vertices.each do |start_vertex|
                next if visited_interiors.include?(start_vertex)

                current_vertex = start_vertex
                current_edge   = current_vertex.edges[0]
                visited_trace  = []

                loop do
                    break unless current_edge

                    visited_trace << current_vertex
                    next_vertex = current_edge.other_vertex(current_vertex)

                    if interior_vertices.include?(next_vertex)
                        break if visited_trace.include?(next_vertex)
                        current_edge   = next_vertex.edges.find { |edge| edge != current_edge }
                        current_vertex = next_vertex
                    else
                        break
                    end
                end

                edge_to_endpoint_a = current_edge
                forward_edge       = current_vertex.edges.find { |edge| edge != edge_to_endpoint_a }
                chain_vertices     = []
                trace_vertex       = current_vertex
                endpoint_b         = nil

                loop do
                    chain_vertices << trace_vertex
                    visited_interiors << trace_vertex
                    break unless forward_edge

                    next_vertex = forward_edge.other_vertex(trace_vertex)
                    if interior_vertices.include?(next_vertex) && !visited_interiors.include?(next_vertex)
                        forward_edge = next_vertex.edges.find { |edge| edge != forward_edge }
                        trace_vertex = next_vertex
                    else
                        endpoint_b = next_vertex
                        break
                    end
                end

                endpoint_b ||= chain_vertices.first
                chains << { interiors: chain_vertices, target_endpoint: endpoint_b }
            end

            chains
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point - Edge Cleaner Execute
# -----------------------------------------------------------------------------

        # FUNCTION | Execute Edge Cleaner on Current Selection
        # ------------------------------------------------------------
        def self.Na__EdgeTools__EdgeCleaner__Execute
            model = Sketchup.active_model
            return Na__EdgeTools__EdgeCleaner__Result(false, 'No active model.', 0, 0) unless model

            selection_edges = model.selection.grep(Sketchup::Edge)
            return Na__EdgeTools__EdgeCleaner__Result(false, 'Edge Cleaner: Select edges first.', 0, 0) if selection_edges.empty?

            model.start_operation('Na Edge Tools - Edge Cleaner', true)

            begin
                exploded_curves = Na__EdgeTools__EdgeCleaner__ExplodeCurves(selection_edges)
                refreshed_edges = model.selection.grep(Sketchup::Edge)
                interior_vertices = Na__EdgeTools__EdgeCleaner__FindInteriorVertices(refreshed_edges)

                if interior_vertices.empty?
                    model.abort_operation
                    return Na__EdgeTools__EdgeCleaner__Result(false, 'Edge Cleaner: No colinear interior vertices found.', exploded_curves, 0)
                end

                chains        = Na__EdgeTools__EdgeCleaner__BuildChains(interior_vertices)
                cleaned_count = Na__EdgeTools__EdgeCleaner__CollapseChains(model, chains)
                Na__EdgeTools__EdgeCleaner__ForceGeometryHeal(model)
                model.commit_operation

                Na__EdgeTools__EdgeCleaner__Result(
                    true,
                    "Edge Cleaner: Exploded #{exploded_curves} curves and removed #{cleaned_count} redundant vertices.",
                    exploded_curves,
                    cleaned_count
                )
            rescue => error
                model.abort_operation
                Na__EdgeTools__EdgeCleaner__Result(false, "Edge Cleaner failed: #{error.message}", 0, 0)
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Curve Explosion and Chain Collapse
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Explode Selected Curves for Vertex Access
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__EdgeCleaner__ExplodeCurves(edges)
            exploded_curves = 0

            edges.each do |edge|
                next unless edge&.valid?
                next unless edge.curve

                edge.explode_curve
                exploded_curves += 1
            end

            exploded_curves
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Collapse Interior Vertices Toward Endpoints
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__EdgeCleaner__CollapseChains(model, chains)
            cleaned_count = 0
            entities      = model.active_entities

            chains.each do |chain|
                target_endpoint = chain[:target_endpoint]
                next unless target_endpoint&.valid?

                target_point = target_endpoint.position
                chain[:interiors].reverse_each do |vertex|
                    next unless vertex&.valid?
                    translation = Geom::Transformation.translation(target_point - vertex.position)
                    entities.transform_entities(translation, [vertex])
                    cleaned_count += 1
                end
            end

            cleaned_count
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Geometry Healing Pass
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Trigger SketchUp Geometry Healing Pass
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__EdgeCleaner__ForceGeometryHeal(model)
            dummy_group = model.active_entities.add_group
            dummy_edge  = dummy_group.entities.add_line(
                [100_000, 100_000, 100_000],
                [100_000, 100_000, 100_001]
            )

            dummy_group.entities.transform_entities(
                Geom::Transformation.translation([0, 0, -1]),
                [dummy_edge.end]
            )

            dummy_group.explode
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Operation Result
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Standardized Operation Result Hash
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__EdgeCleaner__Result(success, message, exploded_curves, cleaned_vertices)
            puts "    [EdgeCleaner] #{message}"
            {
                success:          success,
                message:          message,
                exploded_curves:  exploded_curves,
                cleaned_vertices: cleaned_vertices
            }
        end
        # ---------------------------------------------------------------

    end # module Na__EdgeTools__EdgeCleaner

# endregion -------------------------------------------------------------------

end # module Na__EdgeUtil__PaintDeepNestedEdges

# =============================================================================
# END OF FILE
# =============================================================================
