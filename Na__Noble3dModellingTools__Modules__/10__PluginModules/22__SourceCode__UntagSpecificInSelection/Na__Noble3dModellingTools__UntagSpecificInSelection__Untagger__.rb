# =============================================================================
# NA NOBLE3D MODELLING TOOLS - UNTAG SPECIFIC IN SELECTION - UNTAGGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__UntagSpecificInSelection__Untagger__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__UntagSpecificInSelection__Untagger
# PURPOSE    : Recursively move entities with specified tags to the untagged layer
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__UntagSpecificInSelection__Untagger

# -----------------------------------------------------------------------------
# REGION | Untag Operation
# -----------------------------------------------------------------------------

        # FUNCTION | Untag Entities with Specified Tags Recursively
        # ------------------------------------------------------------
        # Recursively traverses entities and moves any entity whose tag
        # matches a name in tag_names_to_remove to the default untagged
        # layer (model.layers[0]).  All other tag assignments are untouched.
        #
        # @param entities         [Sketchup::Entities, Sketchup::Selection]
        # @param tag_names_to_remove [Array<String>] Tag names to clear
        # @param model            [Sketchup::Model] Active model
        # @return [Integer] Total number of entity assignments changed
        # ------------------------------------------------------------
        def self.Na__UntagSpecificInSelection__Untagger__UntagEntitiesRecursive(entities, tag_names_to_remove, model)
            untagged_layer = model.layers[0]
            count = 0

            entities.each do |entity|
                count += na_untag_entity_if_matched(entity, tag_names_to_remove, untagged_layer)
                count += na_recurse_into_container(entity, tag_names_to_remove, model)
            end

            count
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Untag Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Untag a Single Entity if Its Tag Matches
        # ------------------------------------------------------------
        def self.na_untag_entity_if_matched(entity, tag_names_to_remove, untagged_layer)
            return 0 unless entity.respond_to?(:layer) && entity.layer
            return 0 unless tag_names_to_remove.include?(entity.layer.name)

            entity.layer = untagged_layer
            1
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Recurse into a Group or ComponentInstance
        # ------------------------------------------------------------
        def self.na_recurse_into_container(entity, tag_names_to_remove, model)
            return 0 unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

            Na__UntagSpecificInSelection__Untagger.Na__UntagSpecificInSelection__Untagger__UntagEntitiesRecursive(
                entity.definition.entities,
                tag_names_to_remove,
                model
            )
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__UntagSpecificInSelection__Untagger
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
