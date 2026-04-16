# =============================================================================
# NA EDGE UTIL - EDGE TOOLS - CHAMFER EDGE CORNERS
# =============================================================================
#
# FILE       : Na__EdgeUtil__GeomUtil__ChamferEdgeCorners__Module__.rb
# NAMESPACE  : Na__EdgeUtil__PaintDeepNestedEdges::Na__EdgeTools__ChamferEdgeCorners
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Build optional missing corners then chamfer selected corner edges
# CREATED    : 16-Apr-2026
#
# =============================================================================

require 'sketchup.rb'

module Na__EdgeUtil__PaintDeepNestedEdges

# -----------------------------------------------------------------------------
# REGION | Chamfer Edge Corners Module
# -----------------------------------------------------------------------------

    module Na__EdgeTools__ChamferEdgeCorners

# -----------------------------------------------------------------------------
# REGION | Constants and Preference Keys
# -----------------------------------------------------------------------------

        NA_DEFAULT_CHAMFER_SIZE_MM        = 20.0
        NA_MIN_CHAMFER_SIZE_MM            = 0.0
        NA_PREF_KEY_CHAMFER_SIZE_MM       = 'na_edge_tools_chamfer_size_mm'.freeze

        NA_DEFAULT_BUILD_CORNERS_ENABLED  = false
        NA_PREF_KEY_BUILD_CORNERS_ENABLED = 'na_edge_tools_chamfer_build_corners_enabled'.freeze

        NA_DEFAULT_BUILD_MAX_GAP_MM       = 100.0
        NA_MIN_BUILD_MAX_GAP_MM           = 1.0
        NA_PREF_KEY_BUILD_MAX_GAP_MM      = 'na_edge_tools_chamfer_build_corner_max_gap_mm'.freeze

        NA_COLINEAR_ANGLE_TOLERANCE       = 0.005
        NA_MIN_SPLIT_LENGTH               = 0.001

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Chamfer Setting Persistence
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Read Stored Chamfer Size Millimetres
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__StoredChamferSizeMm
            stored_value = Sketchup.read_default(
                Na__EdgeUtil__PaintDeepNestedEdges.na_dialog_preferences_key,
                NA_PREF_KEY_CHAMFER_SIZE_MM,
                NA_DEFAULT_CHAMFER_SIZE_MM
            )
            Na__EdgeTools__ChamferEdgeCorners__SanitizeChamferSizeMm(stored_value)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Persist Chamfer Size Millimetres
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__SetStoredChamferSizeMm(chamfer_size_mm)
            sanitized_value = Na__EdgeTools__ChamferEdgeCorners__SanitizeChamferSizeMm(chamfer_size_mm)
            Sketchup.write_default(
                Na__EdgeUtil__PaintDeepNestedEdges.na_dialog_preferences_key,
                NA_PREF_KEY_CHAMFER_SIZE_MM,
                sanitized_value
            )
            sanitized_value
        end
        # ---------------------------------------------------------------

        # PURE FUNCTION | Sanitize Chamfer Size Value
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__SanitizeChamferSizeMm(chamfer_size_mm)
            return NA_DEFAULT_CHAMFER_SIZE_MM if chamfer_size_mm.nil? || chamfer_size_mm.to_s.strip.empty?

            numeric_value = chamfer_size_mm.to_f
            numeric_value = NA_MIN_CHAMFER_SIZE_MM if numeric_value < NA_MIN_CHAMFER_SIZE_MM
            numeric_value
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Read Stored Build Corner Toggle
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__StoredBuildCornersEnabled
            stored_value = Sketchup.read_default(
                Na__EdgeUtil__PaintDeepNestedEdges.na_dialog_preferences_key,
                NA_PREF_KEY_BUILD_CORNERS_ENABLED,
                NA_DEFAULT_BUILD_CORNERS_ENABLED
            )
            Na__EdgeTools__ChamferEdgeCorners__SanitizeBuildCornersEnabled(stored_value)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Persist Build Corner Toggle
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__SetStoredBuildCornersEnabled(build_corners_enabled)
            sanitized_value = Na__EdgeTools__ChamferEdgeCorners__SanitizeBuildCornersEnabled(build_corners_enabled)
            Sketchup.write_default(
                Na__EdgeUtil__PaintDeepNestedEdges.na_dialog_preferences_key,
                NA_PREF_KEY_BUILD_CORNERS_ENABLED,
                sanitized_value
            )
            sanitized_value
        end
        # ---------------------------------------------------------------

        # PURE FUNCTION | Sanitize Build Corner Toggle Value
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__SanitizeBuildCornersEnabled(build_corners_enabled)
            truthy_values = [true, 'true', '1', 1, 'yes', 'on']
            truthy_values.include?(build_corners_enabled)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Read Stored Build Corner Max Gap Millimetres
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__StoredBuildCornerMaxGapMm
            stored_value = Sketchup.read_default(
                Na__EdgeUtil__PaintDeepNestedEdges.na_dialog_preferences_key,
                NA_PREF_KEY_BUILD_MAX_GAP_MM,
                NA_DEFAULT_BUILD_MAX_GAP_MM
            )
            Na__EdgeTools__ChamferEdgeCorners__SanitizeBuildCornerMaxGapMm(stored_value)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Persist Build Corner Max Gap Millimetres
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__SetStoredBuildCornerMaxGapMm(build_corner_max_gap_mm)
            sanitized_value = Na__EdgeTools__ChamferEdgeCorners__SanitizeBuildCornerMaxGapMm(build_corner_max_gap_mm)
            Sketchup.write_default(
                Na__EdgeUtil__PaintDeepNestedEdges.na_dialog_preferences_key,
                NA_PREF_KEY_BUILD_MAX_GAP_MM,
                sanitized_value
            )
            sanitized_value
        end
        # ---------------------------------------------------------------

        # PURE FUNCTION | Sanitize Build Corner Max Gap Value
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__SanitizeBuildCornerMaxGapMm(build_corner_max_gap_mm)
            return NA_DEFAULT_BUILD_MAX_GAP_MM if build_corner_max_gap_mm.nil? || build_corner_max_gap_mm.to_s.strip.empty?

            numeric_value = build_corner_max_gap_mm.to_f
            numeric_value = NA_MIN_BUILD_MAX_GAP_MM if numeric_value < NA_MIN_BUILD_MAX_GAP_MM
            numeric_value
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Execute Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Execute Chamfer Edge Corners Tool
        # ------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__Execute(chamfer_size_mm = nil, build_corners_enabled = nil, build_corner_max_gap_mm = nil)
            model = Sketchup.active_model
            return Na__EdgeTools__ChamferEdgeCorners__Result(false, 'Chamfer Edge Corners: No active model.', 0, 0, 0) unless model

            active_chamfer_size_mm = if chamfer_size_mm.nil?
                Na__EdgeTools__ChamferEdgeCorners__StoredChamferSizeMm
            else
                Na__EdgeTools__ChamferEdgeCorners__SetStoredChamferSizeMm(chamfer_size_mm)
            end

            active_build_corners_enabled = if build_corners_enabled.nil?
                Na__EdgeTools__ChamferEdgeCorners__StoredBuildCornersEnabled
            else
                Na__EdgeTools__ChamferEdgeCorners__SetStoredBuildCornersEnabled(build_corners_enabled)
            end

            active_build_corner_max_gap_mm = if build_corner_max_gap_mm.nil?
                Na__EdgeTools__ChamferEdgeCorners__StoredBuildCornerMaxGapMm
            else
                Na__EdgeTools__ChamferEdgeCorners__SetStoredBuildCornerMaxGapMm(build_corner_max_gap_mm)
            end

            selected_edges = model.selection.grep(Sketchup::Edge)
            if selected_edges.empty?
                return Na__EdgeTools__ChamferEdgeCorners__Result(false, 'Chamfer Edge Corners: Select edges first.', 0, 0, 0)
            end
            selected_edges_for_chamfer = selected_edges.dup

            repair_result = Na__EdgeTools__ChamferEdgeCorners__MaybeBuildCorners(
                active_build_corners_enabled,
                active_build_corner_max_gap_mm
            )
            unless repair_result[:success]
                message = repair_result[:message] || 'Chamfer Edge Corners: Corner build pre-pass failed.'
                return Na__EdgeTools__ChamferEdgeCorners__Result(false, message, 0, 0, 0)
            end

            # Keep chamfer stage independent from post-repair selection side effects.
            selected_edges = selected_edges_for_chamfer.select { |edge| edge&.valid? }
            if selected_edges.empty?
                return Na__EdgeTools__ChamferEdgeCorners__Result(
                    false,
                    'Chamfer Edge Corners: Corner build succeeded but no valid selected edges remained for chamfer stage.',
                    0,
                    repair_result[:repaired_count],
                    0
                )
            end

            build_stage_message = if active_build_corners_enabled
                "Build pre-pass: success (#{repair_result[:repaired_count]} repaired)"
            else
                'Build pre-pass: skipped'
            end

            if active_chamfer_size_mm <= 0.0
                return Na__EdgeTools__ChamferEdgeCorners__Result(
                    true,
                    "Chamfer Edge Corners: #{build_stage_message}. Chamfer size is 0mm, so corners remain regular 90 degree corners.",
                    0,
                    repair_result[:repaired_count],
                    0
                )
            end

            chamfer_internal = active_chamfer_size_mm.mm
            candidates = Na__EdgeTools__ChamferEdgeCorners__CollectCornerCandidates(selected_edges)
            if candidates.empty?
                return Na__EdgeTools__ChamferEdgeCorners__Result(false, 'Chamfer Edge Corners: No valid corner candidates found.', 0, repair_result[:repaired_count], 0)
            end

            preflight_result = Na__EdgeTools__ChamferEdgeCorners__PreflightChamfer(candidates, chamfer_internal)
            unless preflight_result[:ok]
                UI.messagebox(preflight_result[:warning])
                return Na__EdgeTools__ChamferEdgeCorners__Result(false, preflight_result[:warning], 0, repair_result[:repaired_count], preflight_result[:short_edge_count])
            end

            model.start_operation('Na Edge Tools - Chamfer Edge Corners', true)

            begin
                chamfered_count = Na__EdgeTools__ChamferEdgeCorners__ApplyChamfers(model, candidates, chamfer_internal)
                Na__EdgeTools__ChamferEdgeCorners__ForceGeometryHeal(model)
                model.commit_operation

                Na__EdgeTools__ChamferEdgeCorners__Result(
                    true,
                    "Chamfer Edge Corners: #{build_stage_message}. Chamfered #{chamfered_count} corners at #{active_chamfer_size_mm.round(3)}mm.",
                    chamfered_count,
                    repair_result[:repaired_count],
                    0
                )
            rescue => error
                model.abort_operation
                Na__EdgeTools__ChamferEdgeCorners__Result(false, "Chamfer Edge Corners failed: #{error.message}", 0, repair_result[:repaired_count], 0)
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Corner Build Pre-Pass
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Optionally Build Missing Corners Before Chamfer
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__MaybeBuildCorners(build_corners_enabled, build_corner_max_gap_mm)
            return { success: true, repaired_count: 0 } unless build_corners_enabled

            repair_result = Na__EdgeTools__RepairEdgeCorners.Na__EdgeTools__RepairEdgeCorners__ExecuteRepair(build_corner_max_gap_mm)
            return { success: false, message: repair_result[:message], repaired_count: 0 } unless repair_result[:success]

            { success: true, repaired_count: repair_result[:repaired_count].to_i }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Candidate Discovery and Preflight
# -----------------------------------------------------------------------------

        # PURE FUNCTION | Collect Corner Candidate Vertices
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__CollectCornerCandidates(selected_edges)
            candidates = []
            selected_lookup = {}
            selected_edges.each { |edge| selected_lookup[edge] = true }

            selected_edges.flat_map(&:vertices).uniq.each do |vertex|
                next unless vertex&.valid?
                next unless vertex.edges.length == 2

                selected_incident_edges = vertex.edges.select { |edge| selected_lookup[edge] }
                next unless selected_incident_edges.length == 2

                edge_a, edge_b = selected_incident_edges
                next if edge_a.length <= NA_MIN_SPLIT_LENGTH || edge_b.length <= NA_MIN_SPLIT_LENGTH

                vector_a = edge_a.line && edge_a.line[1]
                vector_b = edge_b.line && edge_b.line[1]
                next unless vector_a&.valid? && vector_b&.valid?

                angle = vector_a.angle_between(vector_b)
                is_colinear = angle < NA_COLINEAR_ANGLE_TOLERANCE || (Math::PI - angle).abs < NA_COLINEAR_ANGLE_TOLERANCE
                next if is_colinear

                candidates << { vertex: vertex }
            end

            candidates
        end
        # ---------------------------------------------------------------

        # PURE FUNCTION | Validate Chamfer Feasibility Before Editing
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__PreflightChamfer(candidates, chamfer_internal)
            edge_usage_count = Hash.new(0)

            candidates.each do |candidate|
                vertex = candidate[:vertex]
                next unless vertex&.valid?
                next unless vertex.edges.length == 2

                vertex.edges.each { |edge| edge_usage_count[edge] += 1 if edge&.valid? }
            end

            short_edges = []
            edge_usage_count.each do |edge, usage_count|
                next unless edge&.valid?

                required_length = chamfer_internal * usage_count
                if edge.length <= required_length + NA_MIN_SPLIT_LENGTH
                    short_edges << { edge: edge, required_length: required_length }
                end
            end

            if short_edges.any?
                details = short_edges.first(5).map.with_index do |entry, index|
                    edge_number = index + 1
                    "Edge #{edge_number}: length #{entry[:edge].length.to_l}, requires > #{entry[:required_length].to_l}"
                end.join("\n")

                warning = <<~WARNING.strip
                Chamfer Edge Corners cannot continue.

                Chamfer size is too large for one or more edge lengths.
                Reduce chamfer size or edit geometry, then run again.

                #{details}
                WARNING

                return { ok: false, warning: warning, short_edge_count: short_edges.length }
            end

            { ok: true, warning: nil, short_edge_count: 0 }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Chamfer Geometry Operations
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Apply Chamfer to All Candidate Corners
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__ApplyChamfers(model, candidates, chamfer_internal)
            chamfered_count = 0
            entities = model.active_entities

            candidates.each do |candidate|
                vertex = candidate[:vertex]
                next unless vertex&.valid?
                next unless vertex.edges.length == 2

                edge_a, edge_b = vertex.edges
                split_vertex_a = Na__EdgeTools__ChamferEdgeCorners__SplitEdgeAtDistance(edge_a, vertex, chamfer_internal)
                split_vertex_b = Na__EdgeTools__ChamferEdgeCorners__SplitEdgeAtDistance(edge_b, vertex, chamfer_internal)
                next unless split_vertex_a&.valid? && split_vertex_b&.valid?

                Na__EdgeTools__ChamferEdgeCorners__RemoveCornerStubs(vertex, split_vertex_a, split_vertex_b)
                entities.add_line(split_vertex_a.position, split_vertex_b.position) unless Na__EdgeTools__ChamferEdgeCorners__EdgeExistsBetween(split_vertex_a, split_vertex_b)
                chamfered_count += 1
            end

            chamfered_count
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Split Edge at Chamfer Distance from Corner Vertex
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__SplitEdgeAtDistance(edge, corner_vertex, chamfer_internal)
            return nil unless edge&.valid? && corner_vertex&.valid?
            return nil if edge.length <= chamfer_internal + NA_MIN_SPLIT_LENGTH

            ratio_from_start = if edge.start == corner_vertex
                chamfer_internal / edge.length
            elsif edge.end == corner_vertex
                1.0 - (chamfer_internal / edge.length)
            else
                return nil
            end
            return nil unless ratio_from_start > 0.0 && ratio_from_start < 1.0

            new_edge = edge.split(ratio_from_start)
            return nil unless new_edge&.valid?

            (edge.vertices & new_edge.vertices).find(&:valid?)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Remove Short Stub Edges at Corner Vertex
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__RemoveCornerStubs(corner_vertex, split_vertex_a, split_vertex_b)
            return unless corner_vertex&.valid?

            target_vertices = [split_vertex_a, split_vertex_b]
            stub_edges = corner_vertex.edges.select do |edge|
                next false unless edge&.valid?
                target_vertices.include?(edge.other_vertex(corner_vertex))
            end

            stub_edges.each { |edge| edge.erase! if edge&.valid? }
        end
        # ---------------------------------------------------------------

        # PURE FUNCTION | Detect Existing Edge Between Two Vertices
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__EdgeExistsBetween(vertex_a, vertex_b)
            return false unless vertex_a&.valid? && vertex_b&.valid?

            vertex_a.edges.any? do |edge|
                next false unless edge&.valid?
                edge.other_vertex(vertex_a) == vertex_b
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Geometry Healing and Result Output
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Trigger SketchUp Geometry Healing Pass
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__ForceGeometryHeal(model)
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

        # HELPER FUNCTION | Standardized Chamfer Operation Result
        # ---------------------------------------------------------------
        def self.Na__EdgeTools__ChamferEdgeCorners__Result(success, message, chamfered_count, repaired_count, short_edge_count)
            puts "    [ChamferEdgeCorners] #{message}"
            {
                success:          success,
                message:          message,
                chamfered_count:  chamfered_count,
                repaired_count:   repaired_count,
                short_edge_count: short_edge_count
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__EdgeTools__ChamferEdgeCorners

# endregion -------------------------------------------------------------------

end # module Na__EdgeUtil__PaintDeepNestedEdges

# =============================================================================
# END OF FILE
# =============================================================================
