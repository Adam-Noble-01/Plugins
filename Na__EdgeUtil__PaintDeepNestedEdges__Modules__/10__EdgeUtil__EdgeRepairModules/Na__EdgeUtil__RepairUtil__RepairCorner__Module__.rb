# =============================================================================
# NA EDGE UTIL - EDGE TOOLS - REPAIR EDGE CORNERS
# =============================================================================
#
# FILE       : Na__EdgeUtil__RepairUtil__RepairCorner__Module__.rb
# NAMESPACE  : Na__EdgeUtil__PaintDeepNestedEdges::Na__EdgeTools__RepairEdgeCorners
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Repair broken corner gaps by extending loose edge ends to intersections
# CREATED    : 16-Apr-2026
#
# =============================================================================

require 'sketchup.rb'

module Na__EdgeUtil__PaintDeepNestedEdges

# -----------------------------------------------------------------------------
# REGION | Repair Edge Corners Module
# -----------------------------------------------------------------------------

    module Na__EdgeTools__RepairEdgeCorners

# -----------------------------------------------------------------------------
# REGION | Module Constants and Preference Keys
# -----------------------------------------------------------------------------

        # MODULE CONSTANTS | UI Defaults and Preference Storage
        # ------------------------------------------------------------
        NA_DEFAULT_MAX_GAP_MM = 100.0
        NA_MIN_MAX_GAP_MM     = 1.0
        NA_PREF_KEY_MAX_GAP   = 'na_edge_tools_repair_corner_max_gap_mm'.freeze
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Max Gap Persistence (Read / Write / Sanitize)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Return Stored Max Corner Gap (millimetres)
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__RepairEdgeCorners__StoredMaxGapMm
            stored_value = Sketchup.read_default(
                Na__EdgeUtil__PaintDeepNestedEdges.na_dialog_preferences_key,
                NA_PREF_KEY_MAX_GAP,
                NA_DEFAULT_MAX_GAP_MM
            )

            Na__EdgeTools__RepairEdgeCorners__SanitizeMaxGapMm(stored_value)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Persist Max Corner Gap (millimetres)
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__RepairEdgeCorners__SetStoredMaxGapMm(max_gap_mm)
            sanitised_value = Na__EdgeTools__RepairEdgeCorners__SanitizeMaxGapMm(max_gap_mm)
            Sketchup.write_default(
                Na__EdgeUtil__PaintDeepNestedEdges.na_dialog_preferences_key,
                NA_PREF_KEY_MAX_GAP,
                sanitised_value
            )

            sanitised_value
        end
        # ---------------------------------------------------------------

        # PURE FUNCTION | Enforce Numeric and Minimum Value Rules for Max Gap
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__RepairEdgeCorners__SanitizeMaxGapMm(max_gap_mm)
            return NA_DEFAULT_MAX_GAP_MM if max_gap_mm.nil? || max_gap_mm.to_s.strip.empty?

            numeric_value = max_gap_mm.to_f
            numeric_value = NA_MIN_MAX_GAP_MM if numeric_value < NA_MIN_MAX_GAP_MM
            numeric_value
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Loose Ends and Intersection Candidates
# -----------------------------------------------------------------------------

        # PURE FUNCTION | Return Loose End Vertices from Selected Edges
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__RepairEdgeCorners__GetLooseEnds(selected_edges)
            loose_ends = []

            selected_edges.each do |edge|
                next unless edge&.valid?

                edge.vertices.each do |vertex|
                    loose_ends << vertex if vertex.edges.length == 1
                end
            end

            loose_ends.uniq
        end
        # ---------------------------------------------------------------

        # PURE FUNCTION | Return Valid Corner Intersection Candidates
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__RepairEdgeCorners__FindValidIntersections(loose_ends, max_gap_internal)
            valid_pairs = []

            loose_ends.combination(2).each do |vertex_a, vertex_b|
                next unless vertex_a&.valid? && vertex_b&.valid?

                edge_a = vertex_a.edges.first
                edge_b = vertex_b.edges.first
                next unless edge_a && edge_b
                next if edge_a == edge_b

                closest_points = Geom.closest_points(edge_a.line, edge_b.line)
                next unless closest_points
                next if closest_points[0].distance(closest_points[1]) > 0.001

                intersection_point = closest_points[0]
                distance_a         = vertex_a.position.distance(intersection_point)
                distance_b         = vertex_b.position.distance(intersection_point)
                next unless distance_a <= max_gap_internal && distance_b <= max_gap_internal

                valid_pairs << {
                    vertex_a:          vertex_a,
                    vertex_b:          vertex_b,
                    intersection_point: intersection_point,
                    score:             distance_a + distance_b
                }
            end

            valid_pairs.sort_by { |pair| pair[:score] }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point - Repair Edge Corners Execute
# -----------------------------------------------------------------------------

        # FUNCTION | Execute Corner Repair on Current Selection
        # ------------------------------------------------------------
        def self.Na__EdgeTools__RepairEdgeCorners__ExecuteRepair(max_gap_mm = nil)
            model = Sketchup.active_model
            return Na__EdgeTools__RepairEdgeCorners__Result(false, 'No active model.', 0, NA_DEFAULT_MAX_GAP_MM) unless model

            active_max_gap_mm = if max_gap_mm.nil?
                Na__EdgeTools__RepairEdgeCorners__StoredMaxGapMm
            else
                Na__EdgeTools__RepairEdgeCorners__SetStoredMaxGapMm(max_gap_mm)
            end

            selected_edges = model.selection.grep(Sketchup::Edge)
            if selected_edges.empty?
                return Na__EdgeTools__RepairEdgeCorners__Result(false, 'Repair Edge Corners: Select edges first.', 0, active_max_gap_mm)
            end

            max_gap_internal = active_max_gap_mm.mm
            model.start_operation('Na Edge Tools - Repair Edge Corners', true)

            begin
                loose_ends         = Na__EdgeTools__RepairEdgeCorners__GetLooseEnds(selected_edges)
                repair_candidates  = Na__EdgeTools__RepairEdgeCorners__FindValidIntersections(loose_ends, max_gap_internal)
                repaired_count     = Na__EdgeTools__RepairEdgeCorners__ApplyCornerRepairs(model, repair_candidates)
                Na__EdgeTools__RepairEdgeCorners__ForceGeometryHeal(model)
                model.commit_operation

                Na__EdgeTools__RepairEdgeCorners__Result(
                    true,
                    "Repair Edge Corners: Repaired #{repaired_count} corners within #{active_max_gap_mm.round(3)}mm.",
                    repaired_count,
                    active_max_gap_mm
                )
            rescue => error
                model.abort_operation
                Na__EdgeTools__RepairEdgeCorners__Result(false, "Repair Edge Corners failed: #{error.message}", 0, active_max_gap_mm)
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Apply Corner Repairs
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Apply Best Corner Repair Candidates
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__RepairEdgeCorners__ApplyCornerRepairs(model, repair_candidates)
            repaired_count      = 0
            processed_vertices  = []
            entities            = model.active_entities

            repair_candidates.each do |candidate|
                vertex_a = candidate[:vertex_a]
                vertex_b = candidate[:vertex_b]
                target   = candidate[:intersection_point]

                next unless vertex_a&.valid? && vertex_b&.valid?
                next if processed_vertices.include?(vertex_a) || processed_vertices.include?(vertex_b)

                vector_a = target - vertex_a.position
                entities.transform_entities(Geom::Transformation.translation(vector_a), [vertex_a]) if vector_a.length > 0

                if vertex_b.valid?
                    vector_b = target - vertex_b.position
                    entities.transform_entities(Geom::Transformation.translation(vector_b), [vertex_b]) if vector_b.length > 0
                end

                processed_vertices << vertex_a
                processed_vertices << vertex_b
                repaired_count += 1
            end

            repaired_count
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Geometry Healing Pass
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Trigger SketchUp Geometry Healing Pass
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__RepairEdgeCorners__ForceGeometryHeal(model)
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
        def self.Na__EdgeTools__RepairEdgeCorners__Result(success, message, repaired_count, max_gap_mm)
            puts "    [RepairEdgeCorners] #{message}"
            {
                success:        success,
                message:        message,
                repaired_count: repaired_count,
                max_gap_mm:     max_gap_mm
            }
        end
        # ---------------------------------------------------------------

    end # module Na__EdgeTools__RepairEdgeCorners

# endregion -------------------------------------------------------------------

end # module Na__EdgeUtil__PaintDeepNestedEdges

# =============================================================================
# END OF FILE
# =============================================================================
