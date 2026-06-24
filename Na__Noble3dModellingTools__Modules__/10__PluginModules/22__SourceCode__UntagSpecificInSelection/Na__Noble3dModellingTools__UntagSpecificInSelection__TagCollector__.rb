# =============================================================================
# NA NOBLE3D MODELLING TOOLS - UNTAG SPECIFIC IN SELECTION - TAG COLLECTOR
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__UntagSpecificInSelection__TagCollector__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__UntagSpecificInSelection__TagCollector
# PURPOSE    : Recursively collect all unique tags present in a set of entities
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__UntagSpecificInSelection__TagCollector

# -----------------------------------------------------------------------------
# REGION | Tag Collection
# -----------------------------------------------------------------------------

        # FUNCTION | Collect Unique Tags from Entities Recursively
        # ------------------------------------------------------------
        # Traverses entities and all nested group/component definitions,
        # building a hash of unique tag names with entity counts.
        # Skips the default untagged layer by object identity rather than
        # hardcoded name, ensuring compatibility with SketchUp 2020+ where
        # the default layer is named "Untagged" (not the legacy "Layer0").
        #
        # @param entities [Sketchup::Entities, Sketchup::Selection] Entities to scan
        # @param model    [Sketchup::Model] Active model (used to resolve default layer)
        # @param tags_hash [Hash] Accumulator { tag_name => { layer:, count: } }
        # @return [Hash] Populated tags hash
        # ------------------------------------------------------------
        def self.Na__UntagSpecificInSelection__TagCollector__CollectTagsRecursive(entities, model, tags_hash = {})
            untagged_layer = model.layers[0]

            entities.each do |entity|
                na_record_entity_tag(entity, untagged_layer, tags_hash)
                na_recurse_into_container(entity, model, tags_hash)
            end

            tags_hash
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Recursion Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Record the Entity's Tag in the Accumulator
        # ------------------------------------------------------------
        # Tag recording is kept separate from recursion so that containers
        # sitting on the Untagged layer are still descended into — their
        # children may carry tags even though the container itself does not.
        # ------------------------------------------------------------
        def self.na_record_entity_tag(entity, untagged_layer, tags_hash)
            return unless entity.respond_to?(:layer) && entity.layer

            layer = entity.layer
            return if layer == untagged_layer

            layer_name = layer.name
            if tags_hash[layer_name]
                tags_hash[layer_name][:count] += 1
            else
                tags_hash[layer_name] = { layer: layer, count: 1 }
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Recurse into Group or ComponentInstance Definition
        # ------------------------------------------------------------
        def self.na_recurse_into_container(entity, model, tags_hash)
            return unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

            Na__UntagSpecificInSelection__TagCollector.Na__UntagSpecificInSelection__TagCollector__CollectTagsRecursive(
                entity.definition.entities,
                model,
                tags_hash
            )
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__UntagSpecificInSelection__TagCollector
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
