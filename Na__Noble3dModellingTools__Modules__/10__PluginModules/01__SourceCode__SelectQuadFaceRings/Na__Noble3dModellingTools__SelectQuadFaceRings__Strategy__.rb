# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SELECT QUAD FACE RINGS - STRATEGY HELPERS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SelectQuadFaceRings__Strategy__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SelectQuadFaceRings__Strategy
# PURPOSE    : Choose preferred ring candidate strategy and aggregate results
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SelectQuadFaceRings__Strategy

# -----------------------------------------------------------------------------
# REGION | Direction Strategy Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Return Preferred Candidate Ring by Strategy
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__PreferredCandidateFaceRing(candidate_face_rings, preferred_direction_strategy)
            return nil if candidate_face_rings.empty?

            case preferred_direction_strategy
            when :shortest_opposite_edges
                candidate_face_rings.min_by do |candidate_face_ring|
                    [
                        candidate_face_ring[:average_seed_edge_length],
                        -candidate_face_ring[:faces].length
                    ]
                end

            when :longest_opposite_edges
                candidate_face_rings.min_by do |candidate_face_ring|
                    [
                        -candidate_face_ring[:average_seed_edge_length],
                        -candidate_face_ring[:faces].length
                    ]
                end

            when :largest_face_count
                candidate_face_rings.max_by { |candidate_face_ring| candidate_face_ring[:faces].length }

            else
                candidate_face_rings.min_by do |candidate_face_ring|
                    [
                        candidate_face_ring[:average_seed_edge_length],
                        -candidate_face_ring[:faces].length
                    ]
                end
            end
        end
        # ------------------------------------------------------------

        # FUNCTION | Return Preferred Ring for Single Seed Face
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__PreferredFaceRingFromSeedFace(seed_face, preferred_direction_strategy, maximum_step_count)
            candidate_face_rings = Na__SelectQuadFaceRings__Traversal.Na__SelectQuadFaceRings__CandidateFaceRingsFromSeedFace(
                seed_face,
                maximum_step_count
            )

            preferred_candidate_face_ring = self.Na__SelectQuadFaceRings__PreferredCandidateFaceRing(
                candidate_face_rings,
                preferred_direction_strategy
            )

            return [] if preferred_candidate_face_ring.nil?

            preferred_candidate_face_ring[:faces]
        end
        # ------------------------------------------------------------

        # FUNCTION | Return Preferred Rings for Multiple Seed Faces
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__PreferredFaceRingsFromSeedFaces(seed_faces, preferred_direction_strategy, maximum_step_count)
            all_ring_faces = []

            seed_faces.each do |seed_face|
                ring_faces = self.Na__SelectQuadFaceRings__PreferredFaceRingFromSeedFace(
                    seed_face,
                    preferred_direction_strategy,
                    maximum_step_count
                )
                all_ring_faces.concat(ring_faces)
            end

            Na__SelectQuadFaceRings__Traversal.Na__SelectQuadFaceRings__UniqueFacesPreservingOrder(all_ring_faces)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SelectQuadFaceRings__Strategy
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
