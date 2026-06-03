# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FLATTEN 3D TO 2D - FLATTEN BUILDER (LINEWORK)
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__Flatten3dTo2d__FlattenBuilder__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__Flatten3dTo2d
# PURPOSE    : Build the flattened all-linework 2D group from collected edges
# CREATED    : 2026
#
# DESCRIPTION:
# - Projects every collected edge onto the front plane and rebuilds it inside a
#   new group, preserving soft/smooth/hidden state so curved surfaces still read.
# - Any faces that SketchUp auto-creates from closed coplanar loops are stripped
#   afterwards so the result is pure linework.
# - Also provides na_strip_faces, shared with the Silhouette builder.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__Flatten3dTo2d

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        NA_FLATTEN2D_LINEWORK_GROUP_NAME = 'Na__Flatten2D__Linework' unless const_defined?(:NA_FLATTEN2D_LINEWORK_GROUP_NAME)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Builder API
# -----------------------------------------------------------------------------

        # FUNCTION | Build a Flattened Linework Group From Collected Edges
        # ------------------------------------------------------------
        # edges and view_normal are in world space; edit_inverse maps the finished
        # world points back into the active edit context for creation.
        # ------------------------------------------------------------
        def self.na_build_linework_group(active_entities, edges, view_normal, edit_inverse)
            points      = edges.flat_map { |edge_data| [edge_data[:start], edge_data[:end]] }
            plane_value = na_min_projection(points, view_normal)
            return nil if plane_value.nil?

            group          = active_entities.add_group
            group.name     = NA_FLATTEN2D_LINEWORK_GROUP_NAME
            group_entities = group.entities

            edges.each do |edge_data|
                na_add_projected_edge(group_entities, edge_data, plane_value, view_normal, edit_inverse)
            end

            na_strip_faces(group_entities)                                # <-- Keep linework only
            group
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edge Construction Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Project and Add a Single Edge Into the Group
        # ------------------------------------------------------------
        def self.na_add_projected_edge(group_entities, edge_data, plane_value, view_normal, edit_inverse)
            start_point = na_to_local(na_project_point(edge_data[:start], plane_value, view_normal), edit_inverse)
            end_point   = na_to_local(na_project_point(edge_data[:end],   plane_value, view_normal), edit_inverse)
            return if start_point == end_point                            # <-- Skip edges seen exactly end-on

            new_edges = group_entities.add_edges(start_point, end_point)
            na_apply_edge_flags(new_edges.first, edge_data) if new_edges && new_edges.first
        rescue StandardError
            nil                                                           # <-- Ignore a single degenerate edge
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Re-apply Soft / Smooth / Hidden Edge Flags
        # ------------------------------------------------------------
        def self.na_apply_edge_flags(edge, edge_data)
            return unless edge && edge.valid?
            edge.soft   = edge_data[:soft]   if edge.respond_to?(:soft=)
            edge.smooth = edge_data[:smooth] if edge.respond_to?(:smooth=)
            edge.hidden = edge_data[:hidden] if edge.respond_to?(:hidden=)
        rescue StandardError
            nil                                                           # <-- Flag application is best-effort
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Shared Face Stripping Helper
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Erase All Faces While Preserving Their Edges
        # ------------------------------------------------------------
        # Sketchup::Face#erase! removes only the face; its bounding edges remain
        # as standalone linework, which is exactly what both builders need.
        # ------------------------------------------------------------
        def self.na_strip_faces(group_entities)
            faces = group_entities.grep(Sketchup::Face)
            faces.each { |face| face.erase! if face.valid? }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__Flatten3dTo2d
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
