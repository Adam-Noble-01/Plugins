# =============================================================================
# NA NOBLE3D MODELLING TOOLS - MATERIAL SWAP IN SELECTION - MATERIAL COLLECTOR
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__MaterialSwapInSelection__MaterialCollector__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__MaterialSwapInSelection__MaterialCollector
# PURPOSE    : Recursively collect all unique materials present in a set of entities
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__MaterialSwapInSelection__MaterialCollector

# -----------------------------------------------------------------------------
# REGION | Material Collection
# -----------------------------------------------------------------------------

        # FUNCTION | Collect Unique Materials from Entities Recursively
        # ------------------------------------------------------------
        # Traverses all entities and nested group/component definitions,
        # building a hash of unique materials with combined application counts.
        # Covers front materials on all entity types, back materials on Faces,
        # and container materials on Groups and ComponentInstances.
        #
        # @param entities     [Sketchup::Entities, Sketchup::Selection] Entities to scan
        # @param materials_hash [Hash] Accumulator { name => { material:, count: } }
        # @return [Hash] Populated materials hash
        # ------------------------------------------------------------
        def self.Na__MaterialSwapInSelection__MaterialCollector__CollectMaterialsRecursive(entities, materials_hash = {})
            entities.each do |entity|
                na_record_entity_front_material(entity, materials_hash)
                na_record_face_back_material(entity, materials_hash)
                na_recurse_into_container(entity, materials_hash)
            end

            materials_hash
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Recording Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Record the Front / Container Material of an Entity
        # ------------------------------------------------------------
        def self.na_record_entity_front_material(entity, materials_hash)
            return unless entity.respond_to?(:material) && entity.material

            na_accumulate_material(entity.material, materials_hash)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Record the Back Material of a Face Entity
        # ------------------------------------------------------------
        def self.na_record_face_back_material(entity, materials_hash)
            return unless entity.is_a?(Sketchup::Face) && entity.back_material

            na_accumulate_material(entity.back_material, materials_hash)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Add or Increment a Material Entry in the Accumulator
        # ------------------------------------------------------------
        def self.na_accumulate_material(material, materials_hash)
            name = material.name
            if materials_hash[name]
                materials_hash[name][:count] += 1
            else
                materials_hash[name] = { material: material, count: 1 }
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Recurse into a Group or ComponentInstance Definition
        # ------------------------------------------------------------
        def self.na_recurse_into_container(entity, materials_hash)
            return unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

            Na__MaterialSwapInSelection__MaterialCollector.Na__MaterialSwapInSelection__MaterialCollector__CollectMaterialsRecursive(
                entity.definition.entities,
                materials_hash
            )
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__MaterialSwapInSelection__MaterialCollector
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
