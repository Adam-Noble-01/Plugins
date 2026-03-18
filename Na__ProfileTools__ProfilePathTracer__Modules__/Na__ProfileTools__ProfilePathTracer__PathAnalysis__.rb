# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - PATH ANALYSIS
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__PathAnalysis__.rb
# PURPOSE    : Analyze user-selected path entities for profile tracing
# CREATED    : 2026
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__PathAnalysis

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_VERTEX_PICK_TOLERANCE = 120.mm

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Edge Extraction
    # -------------------------------------------------------------------------

        def self.Na__Path__ExtractEdges(path_entities)
            unique = {}

            Array(path_entities).each do |entity|
                if entity.is_a?(Sketchup::Edge)
                    unique[entity.persistent_id] = entity if entity.valid?
                elsif entity.respond_to?(:edges)
                    entity.edges.each do |edge|
                        unique[edge.persistent_id] = edge if edge && edge.valid?
                    end
                end
            end

            unique.values
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Graph Helpers (Degree / Adjacency)
    # -------------------------------------------------------------------------

        def self.Na__Path__BuildVertexDegreeMap(edges)
            degree_map = Hash.new(0)
            adjacency_map = Hash.new { |hash, key| hash[key] = [] }

            edges.each do |edge|
                start_vertex = edge.start
                end_vertex = edge.end
                degree_map[start_vertex] += 1
                degree_map[end_vertex] += 1
                adjacency_map[start_vertex] << edge
                adjacency_map[end_vertex] << edge
            end

            { degree_map: degree_map, adjacency_map: adjacency_map }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Vertex/Point Proximity
    # -------------------------------------------------------------------------

        def self.Na__Path__FindNearestVertex(vertices, target_point, tolerance)
            return nil if vertices.nil? || vertices.empty? || target_point.nil?

            nearest_vertex = nil
            nearest_distance = nil

            vertices.each do |vertex|
                distance = vertex.distance(target_point)
                next if nearest_distance && distance >= nearest_distance
                nearest_distance = distance
                nearest_vertex = vertex
            end

            return nil unless nearest_vertex
            return nil if nearest_distance > tolerance
            nearest_vertex
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Path Ordering (Open Chain or Closed Loop)
    # -------------------------------------------------------------------------

        def self.Na__Path__OrderEdges(edges, preferred_start_point = nil)
            maps = self.Na__Path__BuildVertexDegreeMap(edges)
            degree_map = maps[:degree_map]
            adjacency_map = maps[:adjacency_map]

            invalid_vertex = degree_map.find { |_vertex, degree| degree > 2 }
            if invalid_vertex
                return { isValid: false, reason: 'Branching path detected. Select one non-branching chain or loop.' }
            end

            endpoints = degree_map.select { |_vertex, degree| degree == 1 }.keys
            is_closed_loop = endpoints.empty?

            if !is_closed_loop && endpoints.length != 2
                return { isValid: false, reason: 'Path must be a single open chain or a closed loop.' }
            end

            start_vertex =
                if is_closed_loop
                    self.Na__Path__FindNearestVertex(degree_map.keys, preferred_start_point, NA_VERTEX_PICK_TOLERANCE) || degree_map.keys.min_by(&:persistent_id)
                else
                    self.Na__Path__FindNearestVertex(endpoints, preferred_start_point, NA_VERTEX_PICK_TOLERANCE) || endpoints.min_by(&:persistent_id)
                end

            used_edges = {}
            ordered_edges = []
            ordered_points = [start_vertex.position]
            current_vertex = start_vertex

            loop do
                next_edge = adjacency_map[current_vertex].find { |edge| !used_edges.key?(edge.persistent_id) }
                break unless next_edge

                used_edges[next_edge.persistent_id] = true
                ordered_edges << next_edge
                current_vertex = (next_edge.start == current_vertex) ? next_edge.end : next_edge.start
                ordered_points << current_vertex.position
            end

            if ordered_edges.length != edges.length
                return { isValid: false, reason: 'Selection contains disconnected edge sets.' }
            end

            {
                isValid: true,
                reason: nil,
                isClosedLoop: is_closed_loop,
                orderedEdges: ordered_edges,
                orderedPoints: ordered_points,
                startVertex: start_vertex
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface - Build + Validate
    # -------------------------------------------------------------------------

        def self.Na__Path__BuildSegments(path_entities)
            edges = self.Na__Path__ExtractEdges(path_entities)
            return { isValid: false, reason: 'No edges selected.' } if edges.empty?
            self.Na__Path__OrderEdges(edges)
        end

        def self.Na__Path__Validate(path_entities)
            result = self.Na__Path__BuildSegments(path_entities)
            return { 'isValid' => false, 'reason' => result[:reason] } unless result[:isValid]

            {
                'isValid' => true,
                'reason' => nil,
                'segmentCount' => result[:orderedEdges].length,
                'isClosedLoop' => result[:isClosedLoop]
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Path Reordering From User Pick (Scaffold)
    # -------------------------------------------------------------------------

        def self.Na__Path__ReorderPathFromStart(path_data, start_point)
            ordered_points = Array(path_data[:ordered_points] || path_data['ordered_points'])
            ordered_edges = Array(path_data[:ordered_edges] || path_data['ordered_edges'])
            is_closed_loop = path_data[:is_closed_loop] || path_data['is_closed_loop']
            return { isValid: false, reason: 'Path data is empty.' } if ordered_points.length < 2

            nearest_vertex = self.Na__Path__FindNearestVertex(ordered_points, start_point, NA_VERTEX_PICK_TOLERANCE)
            return { isValid: false, reason: 'Click must be on a path vertex.' } unless nearest_vertex

            if is_closed_loop
                start_index = ordered_points.index(nearest_vertex) || 0
                rotated_points = ordered_points[start_index..-1] + ordered_points[0...start_index]
                rotated_points << rotated_points.first unless rotated_points.first == rotated_points.last

                return {
                    isValid: true,
                    reason: nil,
                    pathData: {
                        ordered_points: rotated_points,
                        ordered_edges: ordered_edges,
                        is_closed_loop: true
                    }
                }
            end

            first_vertex = ordered_points.first
            last_vertex = ordered_points.last

            if nearest_vertex == first_vertex
                return { isValid: true, reason: nil, pathData: path_data }
            end

            if nearest_vertex == last_vertex
                reversed_points = ordered_points.reverse
                reversed_edges = ordered_edges.reverse
                return {
                    isValid: true,
                    reason: nil,
                    pathData: {
                        ordered_points: reversed_points,
                        ordered_edges: reversed_edges,
                        is_closed_loop: false
                    }
                }
            end

            { isValid: false, reason: 'For open paths, start must be one of the two end vertices.' }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
