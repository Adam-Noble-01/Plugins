# =============================================================================
# NA NOBLE3D MODELLING TOOLS - CONVERT COMPONENTS TO GROUPS - CONVERTER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ConvertComponentsToGroups__Converter__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ConvertComponentsToGroups__Converter
# PURPOSE    : Convert component instances into equivalent grouped geometry
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ConvertComponentsToGroups__Converter

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_IDENTITY_TRANSFORM = Geom::Transformation.new
        NA_MAX_RECURSION_DEPTH = 100

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Conversion API
# -----------------------------------------------------------------------------

        # FUNCTION | Collect Unlocked Selected Component Instances
        # ------------------------------------------------------------
        def self.Na__ConvertComponentsToGroups__Converter__CollectSelectedComponents(model)
            return [] unless model

            model.selection.grep(Sketchup::ComponentInstance).select do |entity|
                na_convertible_component_instance?(entity)
            end
        end
        # ------------------------------------------------------------

        # FUNCTION | Convert One Component Instance to a Group
        # ------------------------------------------------------------
        def self.Na__ConvertComponentsToGroups__Converter__ConvertInstance(component_instance, recursion_depth = 0)
            return nil unless na_convertible_component_instance?(component_instance)
            return nil if recursion_depth >= NA_MAX_RECURSION_DEPTH

            owning_entities = Na__ConvertComponentsToGroups__EntityUtils.Na__ConvertComponentsToGroups__EntityUtils__GetOwningEntities(component_instance)
            properties = Na__ConvertComponentsToGroups__ComponentProps.Na__ConvertComponentsToGroups__ComponentProps__Extract(component_instance)
            source_definition = component_instance.definition

            group = owning_entities.add_group
            group.transformation = properties[:transformation]

            na_copy_component_definition_contents_to_group(group, source_definition)
            component_instance.erase!
            Na__ConvertComponentsToGroups__ComponentProps.Na__ConvertComponentsToGroups__ComponentProps__ApplyToGroup(group, properties)

            na_convert_nested_components(group.entities, recursion_depth + 1)
            group
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Check Component Instance Can Be Converted
        # ------------------------------------------------------------
        def self.na_convertible_component_instance?(entity)
            entity.is_a?(Sketchup::ComponentInstance) &&
                !entity.is_a?(Sketchup::Group) &&
                entity.valid? &&
                !entity.deleted? &&
                !entity.locked?
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Copy Component Definition Geometry into a Group
        # ------------------------------------------------------------
        def self.na_copy_component_definition_contents_to_group(group, source_definition)
            temporary_instance = group.entities.add_instance(source_definition, NA_IDENTITY_TRANSFORM)
            temporary_instance.explode
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Collect Direct Child Component Instances
        # ------------------------------------------------------------
        def self.na_collect_direct_components(entities)
            entities.grep(Sketchup::ComponentInstance).select do |entity|
                na_convertible_component_instance?(entity)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Convert Nested Component Instances in an Entities Collection
        # ------------------------------------------------------------
        def self.na_convert_nested_components(entities, recursion_depth)
            return [] if recursion_depth >= NA_MAX_RECURSION_DEPTH

            converted_groups = []

            na_collect_direct_components(entities).each do |component_instance|
                group = Na__ConvertComponentsToGroups__Converter__ConvertInstance(component_instance, recursion_depth)
                converted_groups << group if group&.valid?
            end

            converted_groups
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ConvertComponentsToGroups__Converter
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
