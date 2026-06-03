# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FLATTEN 3D TO 2D - SILHOUETTE BUILDER (OUTLINE)
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__Flatten3dTo2d__SilhouetteBuilder__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__Flatten3dTo2d
# PURPOSE    : Build the flattened outline-only 2D group from collected faces
# CREATED    : 2026
#
# DESCRIPTION:
# - Projects each face's outer loop onto the front plane and adds it as a face.
#   Coplanar overlapping faces auto-merge into a single planar subdivision.
# - Interior edges (shared by two faces) are erased, collapsing the subdivision
#   into the union outline. Remaining edges border exactly one face: the outer
#   perimeter plus any genuine interior holes (true stencil behaviour).
# - The fill faces are then stripped so only the outline linework remains.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__Flatten3dTo2d

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        NA_FLATTEN2D_SILHOUETTE_GROUP_NAME = 'Na__Flatten2D__Silhouette' unless const_defined?(:NA_FLATTEN2D_SILHOUETTE_GROUP_NAME)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Builder API
# -----------------------------------------------------------------------------

        # FUNCTION | Build a Flattened Silhouette Outline Group From Faces
        # ------------------------------------------------------------
        # faces and view_normal are in world space; edit_inverse maps the finished
        # world points back into the active edit context for creation.
        # Returns { :group => Sketchup::Group, :face_count => Integer }.
        # ------------------------------------------------------------
        def self.na_build_silhouette_group(active_entities, faces, view_normal, edit_inverse)
            points      = faces.flat_map { |face_data| face_data[:outer] }
            plane_value = na_min_projection(points, view_normal)
            return { :group => nil, :face_count => 0 } if plane_value.nil?

            group          = active_entities.add_group
            group.name     = NA_FLATTEN2D_SILHOUETTE_GROUP_NAME
            group_entities = group.entities

            added_face_count = 0
            faces.each do |face_data|
                added_face_count += 1 if na_add_projected_face(group_entities, face_data[:outer], plane_value, view_normal, edit_inverse)
            end

            if added_face_count > 0
                na_remove_interior_edges(group_entities)                  # <-- Collapse subdivision to the union
                na_strip_faces(group_entities)                            # <-- Leave outline linework only
            end

            { :group => group, :face_count => added_face_count }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Face Construction Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Project and Add a Single Outer Loop as a Face
        # ------------------------------------------------------------
        # Edge-on faces project to near-zero area and raise inside add_face; these
        # are skipped so they simply do not contribute to the silhouette.
        # ------------------------------------------------------------
        def self.na_add_projected_face(group_entities, outer_points, plane_value, view_normal)
            return false unless outer_points && outer_points.length >= 3

            projected = outer_points.map { |point| na_project_point(point, plane_value, view_normal) }
            face      = group_entities.add_face(projected)
            !face.nil? && face.valid?
        rescue StandardError
            false                                                         # <-- Skip degenerate / edge-on faces
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Erase Interior Edges Shared by Two or More Faces
        # ------------------------------------------------------------
        def self.na_remove_interior_edges(group_entities)
            interior_edges = group_entities.grep(Sketchup::Edge).select do |edge|
                edge.valid? && edge.faces.length >= 2
            end
            group_entities.erase_entities(interior_edges) unless interior_edges.empty?
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__Flatten3dTo2d
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
