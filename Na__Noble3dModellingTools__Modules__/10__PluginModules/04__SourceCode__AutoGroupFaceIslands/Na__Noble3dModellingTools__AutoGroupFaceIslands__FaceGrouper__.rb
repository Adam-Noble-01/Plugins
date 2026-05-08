# =============================================================================
# NA NOBLE3D MODELLING TOOLS - AUTO GROUP FACE ISLANDS - FACE GROUPER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__AutoGroupFaceIslands__FaceGrouper__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__AutoGroupFaceIslands__FaceGrouper
# PURPOSE    : Helper operations for filtering, grouping, validating, and
#              fixing selection display for individual face island groups
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__AutoGroupFaceIslands__FaceGrouper

# -----------------------------------------------------------------------------
# REGION | Selection Filtering
# -----------------------------------------------------------------------------

        # FUNCTION | Filter Selection to Faces Only and Update Model Selection
        # ------------------------------------------------------------
        def self.Na__AutoGroupFaceIslands__FilterToFacesOnly(model, selection)
            faces = selection.grep(Sketchup::Face)

            if faces.any? && selection.length > faces.length
                model.selection.clear
                model.selection.add(faces)
            end

            faces
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Group Creation
# -----------------------------------------------------------------------------

        # FUNCTION | Create a Group from One Face and Its Bounding Edges
        # ------------------------------------------------------------
        def self.Na__AutoGroupFaceIslands__CreateFaceGroup(entities, face, group_number)
            face_with_edges = [face] + face.edges
            group           = entities.add_group(face_with_edges)
            group.name      = "FaceIsland_#{group_number.to_s.rjust(3, '0')}"
            group
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Manifold Validation
# -----------------------------------------------------------------------------

        # FUNCTION | Validate a Group as a Manifold Solid
        # ------------------------------------------------------------
        def self.Na__AutoGroupFaceIslands__ValidateManifold(group)
            group.manifold?
        rescue StandardError
            false
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Selection Display Fix
# -----------------------------------------------------------------------------

        # FUNCTION | Clear and Restore Selection to Fix SketchUp Display Bug
        # ------------------------------------------------------------
        def self.Na__AutoGroupFaceIslands__ApplySelectionDisplayFix(model)
            current_selection = model.selection.to_a
            model.selection.clear
            model.selection.add(current_selection)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__AutoGroupFaceIslands__FaceGrouper
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
