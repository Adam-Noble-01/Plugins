# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SELECT QUAD FACE RINGS - TOPOLOGY HELPERS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SelectQuadFaceRings__Topology__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SelectQuadFaceRings__Topology
# PURPOSE    : Quad-face topology and adjacency helper functions
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SelectQuadFaceRings__Topology

# -----------------------------------------------------------------------------
# REGION | Quad Topology Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Return Ordered Outer Edges for Face
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__OrderedOuterEdgesFromFace(face)
            face.outer_loop.edges
        end
        # ------------------------------------------------------------

        # FUNCTION | Validate Quad Face Topology
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__FaceIsQuadFace(face)
            self.Na__SelectQuadFaceRings__OrderedOuterEdgesFromFace(face).length == 4
        end
        # ------------------------------------------------------------

        # FUNCTION | Return Opposite Edge Pairs for Quad Face
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__OppositeEdgePairsFromQuadFace(face)
            ordered_edges = self.Na__SelectQuadFaceRings__OrderedOuterEdgesFromFace(face)
            return [] unless ordered_edges.length == 4

            [
                [ordered_edges[0], ordered_edges[2]],
                [ordered_edges[1], ordered_edges[3]]
            ]
        end
        # ------------------------------------------------------------

        # FUNCTION | Return Opposite Edge by Shared Edge Context
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__OppositeEdgeFromQuadFaceAndSharedEdge(face, shared_edge)
            ordered_edges = self.Na__SelectQuadFaceRings__OrderedOuterEdgesFromFace(face)
            return nil unless ordered_edges.length == 4

            shared_edge_index = ordered_edges.index(shared_edge)
            return nil if shared_edge_index.nil?

            ordered_edges[(shared_edge_index + 2) % 4]
        end
        # ------------------------------------------------------------

        # FUNCTION | Return Manifold Neighbour Face Across Edge
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__NeighbourFaceAcrossManifoldEdge(edge, current_face)
            neighbouring_faces = edge.faces.select { |candidate_face| candidate_face != current_face }
            return nil unless neighbouring_faces.length == 1

            neighbouring_faces.first
        end
        # ------------------------------------------------------------

        # FUNCTION | Return Average Edge Length from Edge Pair
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__AverageEdgeLengthAsFloat(edge_pair)
            edge_pair.map { |edge| edge.length.to_f }.sum / edge_pair.length.to_f
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SelectQuadFaceRings__Topology
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
