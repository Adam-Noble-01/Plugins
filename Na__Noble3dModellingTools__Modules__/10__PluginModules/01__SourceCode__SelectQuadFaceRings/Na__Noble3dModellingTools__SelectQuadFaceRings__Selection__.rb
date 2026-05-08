# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SELECT QUAD FACE RINGS - SELECTION HELPERS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SelectQuadFaceRings__Selection__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SelectQuadFaceRings__Selection
# PURPOSE    : Selection extraction, validation, and replacement helpers
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SelectQuadFaceRings__Selection

# -----------------------------------------------------------------------------
# REGION | Selection Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Return Selected Faces from Active Selection
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__SelectedFacesFromSelection(selection)
            selection.to_a.select { |entity| entity.is_a?(Sketchup::Face) }
        end
        # ------------------------------------------------------------

        # FUNCTION | Return Non-Quad Faces from Face Collection
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__NonQuadFacesFromFaces(faces)
            faces.reject do |face|
                Na__SelectQuadFaceRings__Topology.Na__SelectQuadFaceRings__FaceIsQuadFace(face)
            end
        end
        # ------------------------------------------------------------

        # FUNCTION | Replace Selection with Provided Face Collection
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__ReplaceSelectionWithFaces(selection, faces)
            selection.clear
            selection.add(faces)
            faces.length
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SelectQuadFaceRings__Selection
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
