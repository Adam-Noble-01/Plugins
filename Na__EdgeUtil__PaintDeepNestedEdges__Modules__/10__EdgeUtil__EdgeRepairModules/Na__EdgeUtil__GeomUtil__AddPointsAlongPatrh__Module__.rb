# =============================================================================
# NA EDGE UTIL - EDGE TOOLS - INSERT POINTS ALONG PATHS
# =============================================================================
#
# FILE       : Na__EdgeUtil__GeomUtil__AddPointsAlongPatrh__Module__.rb
# NAMESPACE  : Na__EdgeUtil__PaintDeepNestedEdges::Na__EdgeTools__InsertPointsAlongPaths
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Rebuild selected path edges with evenly distributed subdivision points
# CREATED    : 16-Apr-2026
#
# =============================================================================

require 'sketchup.rb'

module Na__EdgeUtil__PaintDeepNestedEdges

# -----------------------------------------------------------------------------
# REGION | Insert Points Along Paths Module
# -----------------------------------------------------------------------------

    module Na__EdgeTools__InsertPointsAlongPaths

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        # MODULE CONSTANTS | UI Defaults
        # ------------------------------------------------------------
        NA_DEFAULT_TARGET_SPACING = 110.0
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point - Insert Points Along Path
# -----------------------------------------------------------------------------

        # FUNCTION | Execute Path Subdivision for Current Selection
        # ------------------------------------------------------------
        def self.Na__EdgeTools__InsertPointsAlongPaths__Execute(target_spacing = nil)
            model = Sketchup.active_model
            return Na__EdgeTools__InsertPointsAlongPaths__Result(false, 'No active model.', 0, 0) unless model

            selected_edges = model.selection.grep(Sketchup::Edge)
            return Na__EdgeTools__InsertPointsAlongPaths__Result(false, 'Insert Points: Select a continuous edge path first.', 0, 0) if selected_edges.empty?

            ordered_vertices = Na__EdgeTools__InsertPointsAlongPaths__OrderEdges(selected_edges)
            return Na__EdgeTools__InsertPointsAlongPaths__Result(false, 'Insert Points: Selection is not one continuous path.', 0, 0) unless ordered_vertices

            points        = ordered_vertices.map(&:position)
            target_length = Na__EdgeTools__InsertPointsAlongPaths__ResolveTargetSpacing(target_spacing)
            return Na__EdgeTools__InsertPointsAlongPaths__Result(false, 'Insert Points cancelled.', 0, 0) unless target_length
            return Na__EdgeTools__InsertPointsAlongPaths__Result(false, 'Insert Points: Spacing must be greater than zero.', 0, 0) if target_length <= 0

            model.start_operation('Na Edge Tools - Insert Points Along Path', true)

            begin
                result        = Na__EdgeTools__InsertPointsAlongPaths__BuildSubdivisionPoints(points, target_length)
                new_points    = result[:points]
                segment_count = result[:total_segments]
                Na__EdgeTools__InsertPointsAlongPaths__DrawSubdividedPath(model, new_points)
                model.commit_operation

                Na__EdgeTools__InsertPointsAlongPaths__Result(
                    true,
                    "Insert Points: Created #{new_points.length - 2} interior points across #{segment_count} segments.",
                    new_points.length - 2,
                    segment_count
                )
            rescue => error
                model.abort_operation
                Na__EdgeTools__InsertPointsAlongPaths__Result(false, "Insert Points failed: #{error.message}", 0, 0)
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Target Spacing Resolution (Prompt and Validation)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve Target Spacing from Input or Prompt
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__InsertPointsAlongPaths__ResolveTargetSpacing(target_spacing)
            return target_spacing.to_f if target_spacing && target_spacing.to_f > 0

            prompts  = ['Target Spacing:']
            defaults = [NA_DEFAULT_TARGET_SPACING.to_l]
            input    = UI.inputbox(prompts, defaults, 'Insert Points Along Path')
            return nil unless input

            input[0].to_f
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Path Geometry - Length, Ordering, Subdivision Points
# -----------------------------------------------------------------------------

        # PURE FUNCTION | Calculate Total Path Length from Ordered Points
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__InsertPointsAlongPaths__PathLength(points)
            total_length = 0.0
            (0...(points.length - 1)).each do |index|
                total_length += points[index].distance(points[index + 1])
            end
            total_length
        end
        # ---------------------------------------------------------------

        # PURE FUNCTION | Build Ordered Vertex List from Selected Edges
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__InsertPointsAlongPaths__OrderEdges(edges)
            adjacency = Hash.new { |hash, key| hash[key] = [] }
            edges.each do |edge|
                adjacency[edge.vertices[0]] << edge
                adjacency[edge.vertices[1]] << edge
            end

            start_vertex = adjacency.keys.find { |vertex| adjacency.fetch(vertex).length == 1 }
            start_vertex ||= adjacency.keys.first
            return nil unless start_vertex

            ordered_vertices = [start_vertex]
            current_vertex   = start_vertex
            used_edges       = []

            while used_edges.length < edges.length
                available_edges = adjacency.fetch(current_vertex) - used_edges
                break if available_edges.empty?

                next_edge   = available_edges.first
                used_edges << next_edge
                next_vertex = (next_edge.vertices - [current_vertex]).first
                return nil unless next_vertex

                ordered_vertices << next_vertex
                current_vertex = next_vertex
            end

            return nil if used_edges.length < edges.length
            ordered_vertices
        end
        # ---------------------------------------------------------------

        # PURE FUNCTION | Build Subdivision Points Per Edge (preserves corners)
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__InsertPointsAlongPaths__BuildSubdivisionPoints(points, target_length)
            new_points     = [points.first]
            total_segments = 0

            (0...(points.length - 1)).each do |i|
                edge_start  = points[i]
                edge_end    = points[i + 1]
                edge_length = edge_start.distance(edge_end)

                num_segments    = [1, (edge_length / target_length).round].max
                total_segments += num_segments

                if num_segments == 1
                    new_points << edge_end
                    next
                end

                direction = edge_start.vector_to(edge_end)
                next unless direction.valid?

                step_size = edge_length / num_segments.to_f

                (1...num_segments).each do |j|
                    step_vector        = direction.clone
                    step_vector.length = step_size * j
                    new_points << edge_start.offset(step_vector)
                end

                new_points << edge_end
            end

            { points: new_points, total_segments: total_segments }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Model Output - Draw Subdivided Path
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Draw New Path in a Dedicated Group
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__InsertPointsAlongPaths__DrawSubdividedPath(model, points)
            group = model.active_entities.add_group
            (0...(points.length - 1)).each do |index|
                group.entities.add_line(points[index], points[index + 1])
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Operation Result
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Standardized Operation Result Hash
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__InsertPointsAlongPaths__Result(success, message, inserted_points, segment_count)
            puts "    [InsertPointsAlongPaths] #{message}"
            {
                success:         success,
                message:         message,
                inserted_points: inserted_points,
                segment_count:   segment_count
            }
        end
        # ---------------------------------------------------------------

    end # module Na__EdgeTools__InsertPointsAlongPaths

# endregion -------------------------------------------------------------------

end # module Na__EdgeUtil__PaintDeepNestedEdges

# =============================================================================
# END OF FILE
# =============================================================================
