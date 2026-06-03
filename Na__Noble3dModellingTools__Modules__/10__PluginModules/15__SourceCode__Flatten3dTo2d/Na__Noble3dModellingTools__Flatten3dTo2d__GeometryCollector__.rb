# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FLATTEN 3D TO 2D - GEOMETRY COLLECTOR
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__Flatten3dTo2d__GeometryCollector__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__Flatten3dTo2d
# PURPOSE    : Recursively collect selection geometry in active-context space
# CREATED    : 2026
#
# DESCRIPTION:
# - Walks the active selection, descending into groups and component instances
#   while baking their transformations.
# - Returns edge segments (with soft/smooth/hidden flags) and face outer loops
#   expressed in the active drawing context's coordinate space, which is exactly
#   where the new flattened group will be created.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__Flatten3dTo2d

# -----------------------------------------------------------------------------
# REGION | Public Collection API
# -----------------------------------------------------------------------------

        # FUNCTION | Collect World-Space Edge Segments from a Selection
        # ------------------------------------------------------------
        # base_transform maps the active edit context into world space (pass
        # model.edit_transform). Returns an array of hashes:
        # { :start, :end, :soft, :smooth, :hidden }.
        # ------------------------------------------------------------
        def self.na_collect_world_edges(selection, base_transform = nil)
            base      = base_transform || Geom::Transformation.new        # <-- Default to identity (top level)
            collected = []
            selection.each { |entity| na_collect_edges_recursive(entity, base, collected) }
            collected
        end
        # ------------------------------------------------------------

        # FUNCTION | Collect World-Space Face Loops from a Selection
        # ------------------------------------------------------------
        # base_transform maps the active edit context into world space (pass
        # model.edit_transform). Returns an array of hashes:
        # { :outer => [Point3d], :inners => [[Point3d]] }.
        # ------------------------------------------------------------
        def self.na_collect_world_faces(selection, base_transform = nil)
            base      = base_transform || Geom::Transformation.new        # <-- Default to identity (top level)
            collected = []
            selection.each { |entity| na_collect_faces_recursive(entity, base, collected) }
            collected
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Recursive Edge Traversal
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Recursively Collect Edges With Baked Transform
        # ------------------------------------------------------------
        def self.na_collect_edges_recursive(entity, transform, collected)
            return unless entity && entity.valid?

            case entity
            when Sketchup::Edge
                collected << na_edge_record(entity, transform)
            when Sketchup::Group
                child_transform = transform * entity.transformation
                entity.entities.each { |child| na_collect_edges_recursive(child, child_transform, collected) }
            when Sketchup::ComponentInstance
                child_transform = transform * entity.transformation
                entity.definition.entities.each { |child| na_collect_edges_recursive(child, child_transform, collected) }
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build a Single Transformed Edge Record
        # ------------------------------------------------------------
        def self.na_edge_record(edge, transform)
            {
                :start  => edge.start.position.transform(transform),
                :end    => edge.end.position.transform(transform),
                :soft   => edge.soft?,
                :smooth => edge.smooth?,
                :hidden => edge.hidden?
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Recursive Face Traversal
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Recursively Collect Face Loops With Baked Transform
        # ------------------------------------------------------------
        def self.na_collect_faces_recursive(entity, transform, collected)
            return unless entity && entity.valid?

            case entity
            when Sketchup::Face
                collected << na_face_record(entity, transform)
            when Sketchup::Group
                child_transform = transform * entity.transformation
                entity.entities.each { |child| na_collect_faces_recursive(child, child_transform, collected) }
            when Sketchup::ComponentInstance
                child_transform = transform * entity.transformation
                entity.definition.entities.each { |child| na_collect_faces_recursive(child, child_transform, collected) }
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build a Single Transformed Face Record
        # ------------------------------------------------------------
        def self.na_face_record(face, transform)
            outer  = face.outer_loop.vertices.map { |vertex| vertex.position.transform(transform) }
            inners = []

            face.loops.each do |loop|
                next if loop.outer?
                inners << loop.vertices.map { |vertex| vertex.position.transform(transform) }
            end

            { :outer => outer, :inners => inners }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__Flatten3dTo2d
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
