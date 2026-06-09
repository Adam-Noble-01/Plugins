# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SELECTED HIERARCHY TAG REPORTER - ENTITY TEXT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SelectedHierarchyTagReporter__EntityText__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SelectedHierarchyTagReporter__EntityText
# PURPOSE    : Text and identity helpers for SketchUp entity reporting
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SelectedHierarchyTagReporter__EntityText

# -----------------------------------------------------------------------------
# REGION | Entity Classification
# -----------------------------------------------------------------------------

        def self.Na__SelectedHierarchyTagReporter__EntityText__ContainerEntity?(entity)
            entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        end

        def self.Na__SelectedHierarchyTagReporter__EntityText__EntityTypeLabel(entity)
            return 'Group'     if entity.is_a?(Sketchup::Group)
            return 'Component' if entity.is_a?(Sketchup::ComponentInstance)

            nil
        rescue
            nil
        end

        def self.Na__SelectedHierarchyTagReporter__EntityText__IsSolid(entity)
            return nil unless entity.respond_to?(:definition)

            definition = entity.definition
            return nil unless definition

            definition.manifold?                                                     # <-- Use ComponentDefinition#manifold? (non-deprecated)
        rescue
            nil
        end

        def self.Na__SelectedHierarchyTagReporter__EntityText__ChildEntitiesForContainer(entity)
            if entity.is_a?(Sketchup::Group)
                entity.entities
            elsif entity.is_a?(Sketchup::ComponentInstance) && entity.definition
                entity.definition.entities
            else
                nil
            end
        rescue
            nil
        end

        def self.Na__SelectedHierarchyTagReporter__EntityText__EntityTypeName(entity)
            return entity.typename.to_s if entity.respond_to?(:typename)

            entity.class.name.to_s
        rescue
            'Unknown Entity'
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Entity Names and Tags
# -----------------------------------------------------------------------------

        def self.Na__SelectedHierarchyTagReporter__EntityText__EntityDescription(entity)
            tag_name = self.Na__SelectedHierarchyTagReporter__EntityText__TagNameForEntity(entity)

            if entity.is_a?(Sketchup::Group)
                group_name = self.Na__SelectedHierarchyTagReporter__EntityText__QuotedOrUnnamed(entity.name)
                return "Group | Name: #{group_name} | Tag: #{self.Na__SelectedHierarchyTagReporter__EntityText__QuotedOrUnnamed(tag_name)}"
            end

            if entity.is_a?(Sketchup::ComponentInstance)
                instance_name = self.Na__SelectedHierarchyTagReporter__EntityText__QuotedOrUnnamed(entity.name)
                definition_name = self.Na__SelectedHierarchyTagReporter__EntityText__DefinitionNameForEntity(entity)

                return "Component Instance | Instance Name: #{instance_name} | Definition Name: #{definition_name} | Tag: #{self.Na__SelectedHierarchyTagReporter__EntityText__QuotedOrUnnamed(tag_name)}"
            end

            entity_type_name = self.Na__SelectedHierarchyTagReporter__EntityText__EntityTypeName(entity)
            "#{entity_type_name} | Tag: #{self.Na__SelectedHierarchyTagReporter__EntityText__QuotedOrUnnamed(tag_name)}"
        end

        def self.Na__SelectedHierarchyTagReporter__EntityText__EntityNameForEntity(entity)
            return entity.name.to_s if entity.respond_to?(:name)

            ''
        rescue
            ''
        end

        def self.Na__SelectedHierarchyTagReporter__EntityText__DefinitionNameForEntity(entity)
            return '(no definition)' unless entity.respond_to?(:definition)

            definition = entity.definition
            return '(no definition)' unless definition

            self.Na__SelectedHierarchyTagReporter__EntityText__QuotedOrUnnamed(definition.name)
        rescue
            '(definition read error)'
        end

        def self.Na__SelectedHierarchyTagReporter__EntityText__RawDefinitionNameForEntity(entity)
            return '' unless entity.respond_to?(:definition)

            definition = entity.definition
            return '' unless definition

            definition.name.to_s
        rescue
            ''
        end

        def self.Na__SelectedHierarchyTagReporter__EntityText__TagNameForEntity(entity)
            return 'n/a' unless entity.respond_to?(:layer)

            layer = entity.layer
            return 'n/a' unless layer
            return layer.display_name.to_s if layer.respond_to?(:display_name)

            layer.name.to_s
        rescue
            'tag read error'
        end

        def self.Na__SelectedHierarchyTagReporter__EntityText__QuotedOrUnnamed(value)
            text = value.to_s.strip
            return '(unnamed)' if text.empty?

            text.inspect
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Stable Runtime Keys
# -----------------------------------------------------------------------------

        def self.Na__SelectedHierarchyTagReporter__EntityText__RuntimeEntityKey(entity)
            return "pid:#{entity.persistent_id}" if entity.respond_to?(:persistent_id) && entity.persistent_id
            return "eid:#{entity.entityID}" if entity.respond_to?(:entityID)

            "object:#{entity.object_id}"
        rescue
            "object:#{entity.object_id}"
        end

        def self.Na__SelectedHierarchyTagReporter__EntityText__DefinitionKeyForEntity(entity)
            return nil unless entity.respond_to?(:definition)

            definition = entity.definition
            return nil unless definition
            return definition.guid.to_s if definition.respond_to?(:guid)
            return definition.entityID.to_s if definition.respond_to?(:entityID)

            definition.object_id.to_s
        rescue
            nil
        end

# endregion -------------------------------------------------------------------

    end # module Na__SelectedHierarchyTagReporter__EntityText
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
