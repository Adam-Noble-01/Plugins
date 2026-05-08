# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SELECT QUAD FACE RINGS - TRAVERSAL HELPERS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SelectQuadFaceRings__Traversal__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SelectQuadFaceRings__Traversal
# PURPOSE    : Traverse quad rings and build candidate ring collections
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SelectQuadFaceRings__Traversal

# -----------------------------------------------------------------------------
# REGION | Ring Traversal Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Follow Ring Across One Start Edge Direction
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__FollowFaceRingFromSeedFaceAcrossStartEdge(seed_face, start_edge, maximum_step_count)
            collected_faces = []
            visited_faces = { seed_face => true }

            current_face = seed_face
            exit_edge = start_edge
            step_count = 0

            while step_count < maximum_step_count
                step_count += 1

                next_face = Na__SelectQuadFaceRings__Topology.Na__SelectQuadFaceRings__NeighbourFaceAcrossManifoldEdge(
                    exit_edge,
                    current_face
                )
                break if next_face.nil?
                break if visited_faces[next_face]
                break unless Na__SelectQuadFaceRings__Topology.Na__SelectQuadFaceRings__FaceIsQuadFace(next_face)

                collected_faces << next_face
                visited_faces[next_face] = true

                next_exit_edge = Na__SelectQuadFaceRings__Topology.Na__SelectQuadFaceRings__OppositeEdgeFromQuadFaceAndSharedEdge(
                    next_face,
                    exit_edge
                )
                break if next_exit_edge.nil?

                current_face = next_face
                exit_edge = next_exit_edge
            end

            collected_faces
        end
        # ------------------------------------------------------------

        # FUNCTION | Return Unique Faces Preserving Encounter Order
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__UniqueFacesPreservingOrder(faces)
            seen_faces = {}
            unique_faces = []

            faces.each do |face|
                next if seen_faces[face]

                unique_faces << face
                seen_faces[face] = true
            end

            unique_faces
        end
        # ------------------------------------------------------------

        # FUNCTION | Build Candidate Ring for One Opposite Edge Pair
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__CandidateFaceRingFromSeedFaceAndOppositeEdgePair(seed_face, opposite_edge_pair, maximum_step_count)
            faces_in_first_direction = self.Na__SelectQuadFaceRings__FollowFaceRingFromSeedFaceAcrossStartEdge(
                seed_face,
                opposite_edge_pair[0],
                maximum_step_count
            )

            faces_in_second_direction = self.Na__SelectQuadFaceRings__FollowFaceRingFromSeedFaceAcrossStartEdge(
                seed_face,
                opposite_edge_pair[1],
                maximum_step_count
            )

            ring_faces = self.Na__SelectQuadFaceRings__UniqueFacesPreservingOrder(
                [seed_face] + faces_in_first_direction + faces_in_second_direction
            )

            {
                faces: ring_faces,
                opposite_edge_pair: opposite_edge_pair,
                average_seed_edge_length: Na__SelectQuadFaceRings__Topology.Na__SelectQuadFaceRings__AverageEdgeLengthAsFloat(
                    opposite_edge_pair
                )
            }
        end
        # ------------------------------------------------------------

        # FUNCTION | Build Candidate Rings from Seed Face
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__CandidateFaceRingsFromSeedFace(seed_face, maximum_step_count)
            opposite_edge_pairs = Na__SelectQuadFaceRings__Topology.Na__SelectQuadFaceRings__OppositeEdgePairsFromQuadFace(seed_face)

            opposite_edge_pairs.map do |opposite_edge_pair|
                self.Na__SelectQuadFaceRings__CandidateFaceRingFromSeedFaceAndOppositeEdgePair(
                    seed_face,
                    opposite_edge_pair,
                    maximum_step_count
                )
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SelectQuadFaceRings__Traversal
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
