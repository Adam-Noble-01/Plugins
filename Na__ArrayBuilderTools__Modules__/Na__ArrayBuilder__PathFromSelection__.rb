# =============================================================================
# NA ARRAY BUILDER TOOLS - PATH FROM SELECTION
# =============================================================================
#
# FILE       : Na__ArrayBuilder__PathFromSelection__.rb
# NAMESPACE  : Na__ArrayBuilderTools::Na__ArrayBuilder__PathFromSelection
# AUTHOR     : Noble Architecture
# PURPOSE    : Builds an ordered array path from the user's current model
#              selection (edges, curves / arcs, or a face's outline) so
#              the array can follow existing geometry instead of a
#              hand-drawn path. Mirrors the Profile Path Tracer's
#              path-analysis behaviour (chain ordering, loop detection,
#              winding normalisation, reverse).
# CREATED    : 2026
# VERSION    : 0.1.0
#
# DESCRIPTION:
# - Pure stateless module: no SketchUp tool callbacks, no module state.
# - Accepts Sketchup::Edge entities directly plus anything exposing an
#   `edges` collection (curves, arcs, faces). Duplicate edges are
#   de-duplicated by persistent_id.
# - Validates the selection is one non-branching open chain or one
#   closed loop; anything else returns { valid: false, reason: '...' }.
# - Closed loops are normalised to a consistent (clockwise in their
#   dominant plane) winding - same rule as the Profile Path Tracer -
#   so the Reverse toggle behaves predictably.
# - Na__PathFromSelection__ReversePoints flips an ordered point list;
#   closed loops keep a stable start vertex while reversing traversal
#   direction (matching the tracer's behaviour).
#
# =============================================================================

require 'sketchup.rb'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__PathFromSelection

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build an Ordered Path From Selected Entities
        # ------------------------------------------------------------
        # @param entities [Array<Sketchup::Entity>] Typically model.selection.to_a
        # @return [Hash] { valid:, reason:, points: [Geom::Point3d],
        #                  closed: Boolean, edge_count: Integer }
        def self.Na__PathFromSelection__BuildFromEntities(entities)
            edges = self.Na__PathFromSelection__ExtractEdges(entities)

            if edges.empty?
                return {
                    valid:  false,
                    reason: 'Select edges, a curve or a face outline first'
                }
            end

            self.Na__PathFromSelection__OrderEdges(edges)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Reverse an Ordered Point List
        # ------------------------------------------------------------
        # Open chains simply reverse. Closed loops (first == last) keep
        # a stable ring while flipping traversal direction, matching the
        # Profile Path Tracer's reverse behaviour.
        def self.Na__PathFromSelection__ReversePoints(points, closed)
            pts = Array(points)
            return pts.reverse unless closed && pts.length > 2 && pts.first == pts.last

            head = pts[0...-1].reverse
            head + [head.first]
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edge Extraction
# -----------------------------------------------------------------------------

        # FUNCTION | Extract Unique Valid Edges From an Entity List
        # ------------------------------------------------------------
        def self.Na__PathFromSelection__ExtractEdges(entities)
            unique = {}

            Array(entities).each do |entity|
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
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Chain / Loop Ordering
# -----------------------------------------------------------------------------

        # FUNCTION | Order Edges Into a Single Chain or Loop
        # ------------------------------------------------------------
        # Walks the vertex adjacency from a deterministic start and
        # returns the ordered vertex positions. Branching (vertex degree
        # > 2), multiple endpoints, or disconnected islands are rejected
        # with a human-readable reason.
        def self.Na__PathFromSelection__OrderEdges(edges)
            degree_map    = Hash.new(0)
            adjacency_map = Hash.new { |hash, key| hash[key] = [] }

            edges.each do |edge|
                degree_map[edge.start] += 1
                degree_map[edge.end]   += 1
                adjacency_map[edge.start] << edge
                adjacency_map[edge.end]   << edge
            end

            if degree_map.any? { |_vertex, degree| degree > 2 }
                return {
                    valid:  false,
                    reason: 'Branching path detected - select one non-branching chain or loop'
                }
            end

            endpoints      = degree_map.select { |_vertex, degree| degree == 1 }.keys
            is_closed_loop = endpoints.empty?

            if !is_closed_loop && endpoints.length != 2
                return {
                    valid:  false,
                    reason: 'Path must be a single open chain or one closed loop'
                }
            end

            start_vertex =
                if is_closed_loop
                    degree_map.keys.min_by(&:persistent_id)
                else
                    endpoints.min_by(&:persistent_id)
                end

            used_edges     = {}
            ordered_points = [start_vertex.position]
            current_vertex = start_vertex
            walked_count   = 0

            loop do
                next_edge = adjacency_map[current_vertex].find { |edge| !used_edges.key?(edge.persistent_id) }
                break unless next_edge

                used_edges[next_edge.persistent_id] = true
                walked_count += 1
                current_vertex = (next_edge.start == current_vertex) ? next_edge.end : next_edge.start
                ordered_points << current_vertex.position
            end

            if walked_count != edges.length
                return {
                    valid:  false,
                    reason: 'Selection contains disconnected edge sets - select one continuous run'
                }
            end

            if is_closed_loop
                ordered_points = self.Na__PathFromSelection__NormaliseLoopWinding(ordered_points)
            end

            {
                valid:      true,
                reason:     nil,
                points:     ordered_points,
                closed:     is_closed_loop,
                edge_count: edges.length
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Closed-Loop Winding Normalisation
# -----------------------------------------------------------------------------

        # FUNCTION | Normalise a Closed Loop to Clockwise Winding
        # ------------------------------------------------------------
        # Projects the loop onto its dominant plane and forces clockwise
        # traversal (signed area <= 0), matching the Profile Path
        # Tracer, so the same loop always starts in the same direction
        # and the Reverse toggle is meaningful.
        def self.Na__PathFromSelection__NormaliseLoopWinding(ordered_points)
            return ordered_points if ordered_points.nil? || ordered_points.length < 3

            dominant_axis = self.Na__PathFromSelection__DominantPlaneAxis(ordered_points)
            signed_area   = self.Na__PathFromSelection__SignedAreaInPlane(ordered_points, dominant_axis)
            return ordered_points if signed_area <= 0                              # <-- Force CW traversal

            self.Na__PathFromSelection__ReversePoints(ordered_points, true)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Determine the Loop's Dominant Plane Axis
        # ------------------------------------------------------------
        def self.Na__PathFromSelection__DominantPlaneAxis(ordered_points)
            points = Array(ordered_points)
            return :z if points.length < 3

            centroid   = self.Na__PathFromSelection__Centroid(points)
            normal_sum = Geom::Vector3d.new(0, 0, 0)

            (0...points.length).each do |index|
                a = points[index] - centroid
                b = points[(index + 1) % points.length] - centroid
                normal_sum.x += (a.y * b.z) - (a.z * b.y)
                normal_sum.y += (a.z * b.x) - (a.x * b.z)
                normal_sum.z += (a.x * b.y) - (a.y * b.x)
            end

            abs_x = normal_sum.x.abs
            abs_y = normal_sum.y.abs
            abs_z = normal_sum.z.abs
            return :x if abs_x >= abs_y && abs_x >= abs_z
            return :y if abs_y >= abs_z
            :z
        end
        # ---------------------------------------------------------------

        # FUNCTION | Centroid of a Point List
        # ------------------------------------------------------------
        def self.Na__PathFromSelection__Centroid(points)
            total = points.length.to_f
            sum_x = points.inject(0.0) { |acc, point| acc + point.x }
            sum_y = points.inject(0.0) { |acc, point| acc + point.y }
            sum_z = points.inject(0.0) { |acc, point| acc + point.z }
            Geom::Point3d.new(sum_x / total, sum_y / total, sum_z / total)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Signed Area of the Loop in Its Dominant Plane
        # ------------------------------------------------------------
        def self.Na__PathFromSelection__SignedAreaInPlane(ordered_points, dominant_axis)
            return 0.0 if ordered_points.nil? || ordered_points.length < 3

            total = 0.0
            ordered_points.each_with_index do |point, index|
                next_point = ordered_points[(index + 1) % ordered_points.length]
                u_current, v_current = self.Na__PathFromSelection__ProjectToPlane(point, dominant_axis)
                u_next,    v_next    = self.Na__PathFromSelection__ProjectToPlane(next_point, dominant_axis)
                total += (u_current * v_next) - (u_next * v_current)
            end
            total * 0.5
        end
        # ---------------------------------------------------------------

        # FUNCTION | Project a Point Onto the Dominant Plane
        # ------------------------------------------------------------
        def self.Na__PathFromSelection__ProjectToPlane(point, dominant_axis)
            case dominant_axis
            when :x then [point.y, point.z]
            when :y then [point.z, point.x]
            else         [point.x, point.y]
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ArrayBuilder__PathFromSelection
end # module Na__ArrayBuilderTools

# =============================================================================
# END OF FILE
# =============================================================================
