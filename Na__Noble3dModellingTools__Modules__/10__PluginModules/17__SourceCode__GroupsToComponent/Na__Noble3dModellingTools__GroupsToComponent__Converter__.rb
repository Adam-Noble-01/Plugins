# =============================================================================
# NA NOBLE3D MODELLING TOOLS - GROUPS TO COMPONENT - CONVERTER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__GroupsToComponent__Converter__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__GroupsToComponent__Converter
# PURPOSE    : Convert groups into shared component instances in place
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__GroupsToComponent__Converter

# -----------------------------------------------------------------------------
# REGION | Public Conversion API
# -----------------------------------------------------------------------------

        # FUNCTION | Extract Mutable Group Data Before Conversion
        # ------------------------------------------------------------
        def self.Na__GroupsToComponent__Converter__ExtractGroupData(groups)
            groups.map do |group|
                {
                    group:            group,
                    persistent_id:    group.persistent_id,
                    transform:        group.transformation,
                    owning_entities:  na_owning_entities_for(group)
                }
            end
        end
        # ------------------------------------------------------------

        # FUNCTION | Convert Inference Group to Component Definition
        # ------------------------------------------------------------
        def self.Na__GroupsToComponent__Converter__ConvertInferenceGroup(inference_group)
            return nil unless inference_group&.valid?

            component_instance = inference_group.to_component
            return nil unless component_instance&.valid?

            component_instance.definition
        end
        # ------------------------------------------------------------

        # FUNCTION | Replace One Group with a Component Instance
        # ------------------------------------------------------------
        def self.Na__GroupsToComponent__Converter__ReplaceGroupWithInstance(group_data, definition)
            return nil unless group_data.is_a?(Hash)
            return nil unless definition.is_a?(Sketchup::ComponentDefinition)

            group = group_data[:group]
            return nil unless group&.valid?

            instance = group_data[:owning_entities].add_instance(definition, group_data[:transform])
            group.erase!
            instance&.valid? ? instance : nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Run Full Conversion for Selected Groups
        # ------------------------------------------------------------
        def self.Na__GroupsToComponent__Converter__RunConversion(model, groups, inference_group)
            return [] unless model
            return [] if groups.nil? || groups.empty?
            return [] unless inference_group&.valid?

            inference_persistent_id = inference_group.persistent_id
            group_data_list         = Na__GroupsToComponent__Converter__ExtractGroupData(groups)
            inference_data          = group_data_list.find { |data| data[:persistent_id] == inference_persistent_id }
            return [] unless inference_data

            converted_instances = []
            operation_started   = false

            model.start_operation('Groups To Component', true)
            operation_started = true

            inference_component = inference_data[:group].to_component
            unless inference_component&.valid?
                model.abort_operation
                return []
            end

            definition = inference_component.definition
            converted_instances << inference_component

            group_data_list.each do |group_data|
                next if group_data[:persistent_id] == inference_persistent_id

                instance = Na__GroupsToComponent__Converter__ReplaceGroupWithInstance(group_data, definition)
                converted_instances << instance if instance&.valid?
            end

            model.selection.clear
            converted_instances.each { |instance| model.selection.add(instance) if instance&.valid? }

            model.commit_operation
            converted_instances
        rescue => error
            model.abort_operation if model && operation_started
            raise error
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Get the Entities Collection Owning a Group
        # ------------------------------------------------------------
        def self.na_owning_entities_for(entity)
            parent = entity.parent

            return parent.entities if parent.respond_to?(:entities)
            return parent if parent.is_a?(Sketchup::Entities)
            return Sketchup.active_model.entities if parent.is_a?(Sketchup::Model)

            Sketchup.active_model.active_entities
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GroupsToComponent__Converter
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
