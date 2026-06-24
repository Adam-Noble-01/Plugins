# =============================================================================
# NA NOBLE3D MODELLING TOOLS - MATERIAL SWAP IN SELECTION - MATERIAL SWAPPER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__MaterialSwapInSelection__MaterialSwapper__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__MaterialSwapInSelection__Swapper
# PURPOSE    : Recursively replace specific material assignments with a new material
# CREATED    : 2026
#
# =============================================================================

require 'set'

module Na__Noble3dModellingTools
    module Na__MaterialSwapInSelection__Swapper

# -----------------------------------------------------------------------------
# REGION | Swap Operation
# -----------------------------------------------------------------------------

        # FUNCTION | Swap Materials Recursively
        # ------------------------------------------------------------
        # Traverses all entities and nested definitions, replacing every
        # front or back material assignment that is a member of
        # old_materials_set with new_material.
        #
        # Uses a Set for O(1) membership tests when the list of materials
        # to replace is large.
        #
        # @param entities          [Sketchup::Entities, Sketchup::Selection]
        # @param old_materials_set [Set<Sketchup::Material>] Materials to replace
        # @param new_material      [Sketchup::Material] Replacement material
        # @return [Integer] Total number of material assignments changed
        # ------------------------------------------------------------
        def self.Na__MaterialSwapInSelection__Swapper__SwapMaterialsRecursive(entities, old_materials_set, new_material)
            count = 0

            entities.each do |entity|
                count += na_swap_entity_front_material(entity, old_materials_set, new_material)
                count += na_swap_face_back_material(entity, old_materials_set, new_material)
                count += na_recurse_into_container(entity, old_materials_set, new_material)
            end

            count
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Swap Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Swap the Front Material of an Entity if It Matches
        # ------------------------------------------------------------
        def self.na_swap_entity_front_material(entity, old_materials_set, new_material)
            return 0 unless entity.respond_to?(:material) && entity.material
            return 0 unless old_materials_set.include?(entity.material)

            entity.material = new_material
            1
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Swap the Back Material of a Face if It Matches
        # ------------------------------------------------------------
        def self.na_swap_face_back_material(entity, old_materials_set, new_material)
            return 0 unless entity.is_a?(Sketchup::Face) && entity.back_material
            return 0 unless old_materials_set.include?(entity.back_material)

            entity.back_material = new_material
            1
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Recurse into a Group or ComponentInstance Definition
        # ------------------------------------------------------------
        def self.na_recurse_into_container(entity, old_materials_set, new_material)
            return 0 unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

            Na__MaterialSwapInSelection__Swapper.Na__MaterialSwapInSelection__Swapper__SwapMaterialsRecursive(
                entity.definition.entities,
                old_materials_set,
                new_material
            )
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__MaterialSwapInSelection__Swapper
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
