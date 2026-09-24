# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TEXTURED PLANE TO IMAGE - PLACEMENT CONTEXT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__TexturedPlaneToImage__PlacementContext__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__TexturedPlaneToImage__PlacementContext
# PURPOSE    : Open the face's own editing context before reading or adding geometry
# CREATED    : 2026
#
# SketchUp reports coordinates in global inches while a group is open, and in
# that definition's local inches while it is closed. Reading a closed group's
# vertices and then adding an image without opening it mixes those two spaces.
# The same rule is written up in Insert Primitives' deep-pick hub.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__TexturedPlaneToImage__PlacementContext

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Run the Block While the Face's Parent Context Is Open
        # ------------------------------------------------------------
        def self.Na__TexturedPlaneToImage__PlacementContext__InContext(model, instance_chain)
            return yield(false) unless model.respond_to?(:active_path=)

            wanted = na_absolute_path(model, instance_chain)
            previous = model.active_path
            entered = false
            unless na_same_context?(previous, wanted)
                model.active_path = wanted
                entered = true
            end
            yield(entered)
        ensure
            na_restore_active_path(model, previous, entered)
        end
        # ------------------------------------------------------------

        # FUNCTION | Drop Cached Bounds After an Edit Made From Outside
        # ------------------------------------------------------------
        def self.Na__TexturedPlaneToImage__PlacementContext__Invalidate(instance_chain)
            return unless instance_chain

            instance_chain.reverse_each do |instance|
                definition = instance.respond_to?(:definition) ? instance.definition : nil
                definition.invalidate_bounds if definition && definition.respond_to?(:invalidate_bounds)
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Path Comparison
# -----------------------------------------------------------------------------

        def self.na_restore_active_path(model, previous, entered)
            return unless entered

            model.active_path = previous
        rescue StandardError
            model.active_path = nil
        end

        def self.na_absolute_path(model, instance_chain)
            active = model.active_path ? model.active_path.to_a : []
            full_path = active + Array(instance_chain)
            full_path.empty? ? nil : full_path
        end

        def self.na_same_context?(current, wanted)
            na_path_list(current) == na_path_list(wanted)
        end

        def self.na_path_list(path)
            return [] if path.nil?

            path.to_a
        end

# endregion -------------------------------------------------------------------

    end # module Na__TexturedPlaneToImage__PlacementContext
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
