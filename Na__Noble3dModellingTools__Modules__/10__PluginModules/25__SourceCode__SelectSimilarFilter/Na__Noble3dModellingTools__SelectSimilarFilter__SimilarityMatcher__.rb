# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SELECT SIMILAR FILTER - SIMILARITY MATCHER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SelectSimilarFilter__SimilarityMatcher__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SelectSimilarFilter__SimilarityMatcher
# PURPOSE    : Shape-signature based face/edge similarity matching within a threshold
# CREATED    : 2026
#
# MATCHING STRATEGY:
# Faces are matched by an orientation-invariant shape signature (outer vertex
# count, loop count, sorted outer-edge lengths, area) rather than a single area
# number, so that same-area/different-shape faces never cross-match and panels
# that vary slightly in both width and height are still caught. Curved faces
# (circles/arcs) fall back to an equivalent-side-length (sqrt(area)) compare,
# since edge-count comparison is not meaningful for tessellated curves. Edges
# are matched directly on length, which is already orientation-invariant.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SelectSimilarFilter__SimilarityMatcher

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        # Relative area tolerance used only as an anti-shear guard once edge
        # lengths already match; prevents a sheared parallelogram with the same
        # edge lengths as a rectangle from being treated as a match.
        NA_AREA_RELATIVE_TOLERANCE = 0.15

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Find All Faces and Edges Similar to the Current Reference Selection
        # ------------------------------------------------------------
        # @param active_entities    [Sketchup::Entities] Current editing-context entities (local scope only)
        # @param reference_entities [Array<Object>] Entities used as the match seed (typically the current selection)
        # @param match_faces        [Boolean] Whether faces are matched
        # @param match_edges        [Boolean] Whether edges are matched
        # @param threshold_internal [Length] Similarity tolerance in SketchUp internal units (inches)
        # @return [Hash] { faces: [Sketchup::Face, ...], edges: [Sketchup::Edge, ...] }
        # ------------------------------------------------------------
        def self.Na__SelectSimilarFilter__SimilarityMatcher__FindMatches(active_entities, reference_entities, match_faces, match_edges, threshold_internal)
            reference_faces = match_faces ? reference_entities.grep(Sketchup::Face) : []
            reference_edges = match_edges ? reference_entities.grep(Sketchup::Edge) : []

            {
                faces: na_matching_faces(active_entities, reference_faces, threshold_internal),
                edges: na_matching_edges(active_entities, reference_edges, threshold_internal)
            }
        end
        # ------------------------------------------------------------

        # FUNCTION | Summarize Reference Entity Counts from a Selection
        # ------------------------------------------------------------
        # @param selection [Sketchup::Selection]
        # @return [Hash] { face_count:, edge_count: }
        # ------------------------------------------------------------
        def self.Na__SelectSimilarFilter__SimilarityMatcher__ReferenceSummary(selection)
            {
                face_count: selection.grep(Sketchup::Face).length,
                edge_count: selection.grep(Sketchup::Edge).length
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Face Matching
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Find Faces in Active Entities Matching Any Reference Face
        # ------------------------------------------------------------
        def self.na_matching_faces(active_entities, reference_faces, threshold_internal)
            return [] if reference_faces.empty?

            reference_signatures = reference_faces.map { |face| na_face_signature(face) }

            na_visible_entities(active_entities.grep(Sketchup::Face)).select do |face|
                next false if face.area <= 0

                candidate_signature = na_face_signature(face)
                reference_signatures.any? do |reference_signature|
                    na_face_signatures_match?(reference_signature, candidate_signature, threshold_internal)
                end
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build an Orientation-Invariant Shape Signature for a Face
        # ------------------------------------------------------------
        def self.na_face_signature(face)
            outer_edges = face.outer_loop.edges
            {
                vertex_count: outer_edges.length,
                loop_count:   face.loops.length,
                lengths:      outer_edges.map(&:length).sort,
                area:         face.area,
                curved:       outer_edges.any? { |edge| edge.curve }
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Test Whether Two Face Signatures Match Within Threshold
        # ------------------------------------------------------------
        def self.na_face_signatures_match?(reference_signature, candidate_signature, threshold_internal)
            if reference_signature[:curved] || candidate_signature[:curved]
                return na_curved_faces_match?(reference_signature, candidate_signature, threshold_internal)
            end

            return false unless candidate_signature[:vertex_count] == reference_signature[:vertex_count]
            return false unless candidate_signature[:loop_count] == reference_signature[:loop_count]
            return false unless na_edge_length_sets_match?(reference_signature[:lengths], candidate_signature[:lengths], threshold_internal)

            na_areas_within_relative_tolerance?(reference_signature[:area], candidate_signature[:area])
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Compare Curved Faces by Equivalent Side Length (sqrt of Area)
        # ------------------------------------------------------------
        def self.na_curved_faces_match?(reference_signature, candidate_signature, threshold_internal)
            reference_size = Math.sqrt(reference_signature[:area])
            candidate_size = Math.sqrt(candidate_signature[:area])
            (candidate_size - reference_size).abs <= threshold_internal
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Compare Two Sorted Edge-Length Sets Pairwise Within Threshold
        # ------------------------------------------------------------
        def self.na_edge_length_sets_match?(reference_lengths, candidate_lengths, threshold_internal)
            return false unless reference_lengths.length == candidate_lengths.length

            reference_lengths.each_index.all? do |index|
                (candidate_lengths[index] - reference_lengths[index]).abs <= threshold_internal
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Guard Against Sheared Shapes with Matching Edge Lengths
        # ------------------------------------------------------------
        def self.na_areas_within_relative_tolerance?(reference_area, candidate_area)
            return true if reference_area <= 0 || candidate_area <= 0

            larger_area  = [reference_area, candidate_area].max
            smaller_area = [reference_area, candidate_area].min

            (larger_area - smaller_area) <= (larger_area * NA_AREA_RELATIVE_TOLERANCE)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edge Matching
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Find Edges in Active Entities Matching Any Reference Edge Length
        # ------------------------------------------------------------
        def self.na_matching_edges(active_entities, reference_edges, threshold_internal)
            return [] if reference_edges.empty?

            reference_lengths = reference_edges.map(&:length)

            na_visible_entities(active_entities.grep(Sketchup::Edge)).select do |edge|
                next false if edge.length <= 0

                reference_lengths.any? { |reference_length| (edge.length - reference_length).abs <= threshold_internal }
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Visibility Filtering
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Reject Hidden Entities and Entities on Hidden Tags
        # ------------------------------------------------------------
        def self.na_visible_entities(entities)
            entities.reject do |entity|
                entity.hidden? || (entity.layer && !entity.layer.visible?)
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SelectSimilarFilter__SimilarityMatcher
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
