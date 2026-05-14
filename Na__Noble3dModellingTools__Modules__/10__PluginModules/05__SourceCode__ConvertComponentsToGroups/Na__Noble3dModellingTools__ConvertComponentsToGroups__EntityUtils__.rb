# =============================================================================
# NA NOBLE3D MODELLING TOOLS - CONVERT COMPONENTS TO GROUPS - ENTITY UTILS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ConvertComponentsToGroups__EntityUtils__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ConvertComponentsToGroups__EntityUtils
# PURPOSE    : Shared entity helpers for component-to-group conversion
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ConvertComponentsToGroups__EntityUtils

# -----------------------------------------------------------------------------
# REGION | Owning Entities
# -----------------------------------------------------------------------------

        # FUNCTION | Get the Entities Collection Owning an Entity
        # ------------------------------------------------------------
        def self.Na__ConvertComponentsToGroups__EntityUtils__GetOwningEntities(entity)
            parent = entity.parent

            return parent.entities if parent.respond_to?(:entities)
            return parent if parent.is_a?(Sketchup::Entities)
            return Sketchup.active_model.entities if parent.is_a?(Sketchup::Model)

            Sketchup.active_model.active_entities
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Attribute Dictionaries
# -----------------------------------------------------------------------------

        # FUNCTION | Extract Attribute Dictionary Data from an Entity
        # ------------------------------------------------------------
        def self.Na__ConvertComponentsToGroups__EntityUtils__ExtractAttributeDictionaries(entity)
            dictionary_data = {}
            dictionaries = entity.attribute_dictionaries
            return dictionary_data unless dictionaries

            dictionaries.each do |dictionary|
                next unless dictionary

                dictionary_data[dictionary.name] = na_dictionary_key_value_pairs(dictionary)
            end

            dictionary_data
        end
        # ------------------------------------------------------------

        # FUNCTION | Apply Attribute Dictionary Data to an Entity
        # ------------------------------------------------------------
        def self.Na__ConvertComponentsToGroups__EntityUtils__ApplyAttributeDictionaries(entity, dictionary_data)
            return unless dictionary_data.is_a?(Hash)

            dictionary_data.each do |dictionary_name, key_value_pairs|
                next unless key_value_pairs.is_a?(Hash)

                key_value_pairs.each do |key, value|
                    na_set_attribute_safely(entity, dictionary_name, key, value)
                end
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert an Attribute Dictionary to a Hash
        # ------------------------------------------------------------
        def self.na_dictionary_key_value_pairs(dictionary)
            key_value_pairs = {}

            dictionary.each_pair do |key, value|
                key_value_pairs[key] = value
            end

            key_value_pairs
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Set an Attribute while Ignoring Protected Keys
        # ------------------------------------------------------------
        def self.na_set_attribute_safely(entity, dictionary_name, key, value)
            entity.set_attribute(dictionary_name, key, value)
        rescue
            nil
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ConvertComponentsToGroups__EntityUtils
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
