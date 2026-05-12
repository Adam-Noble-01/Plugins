# frozen_string_literal: true

# =============================================================================
# NA SELECTION STATISTICS - STATS BUILDER · NAME + DYNAMIC ATTRIBUTE COLLECTOR
# =============================================================================
#
# FILE       : Na__SelectionStats__StatsBuilder__NameAndDynamicAttributeCollector__.rb
# PURPOSE    : Collect SketchUp object names and Dynamic Component key/value rows.
#
# =============================================================================

# -----------------------------------------------------------------------------
# REGION | Dependencies
# -----------------------------------------------------------------------------

require 'sketchup.rb'

# endregion -------------------------------------------------------------------

module Na__SelectionStats
    module Na__NameAndDynamicAttributeCollector
        extend self

# -----------------------------------------------------------------------------
# REGION | SketchUp Name Rows
# -----------------------------------------------------------------------------

        def na_collect_entity_names(entity, owner_type, owner_label, target_array)
            return nil unless entity && target_array

            case entity
            when Sketchup::Group
                na_append_name_row(target_array, owner_label, owner_type, 'Group Name / Instance Name', na_safe_name(entity))
                na_collect_definition_name(entity.definition, "#{owner_label} > Definition", 'Group Definition', target_array)
            when Sketchup::ComponentInstance
                na_append_name_row(target_array, owner_label, owner_type, 'Component Instance Name / Instance Name', na_safe_name(entity))
                na_collect_definition_name(entity.definition, "#{owner_label} > Definition", 'Component Definition', target_array)
            else
                na_append_name_row(target_array, owner_label, owner_type, 'Instance Name', na_safe_name(entity)) if entity.respond_to?(:name)
            end

            nil
        rescue StandardError
            nil
        end

        def na_collect_definition_name(definition, owner_label, owner_type, target_array)
            return nil unless definition && target_array

            na_append_name_row(target_array, owner_label, owner_type, 'Component Name', na_safe_name(definition))
            nil
        rescue StandardError
            nil
        end

        def na_append_name_row(target_array, owner_label, owner_type, name_role, name_value)
            name = name_value.to_s.strip
            return nil if name.empty?

            target_array << {
                owner: owner_label.to_s,
                owner_type: owner_type.to_s,
                role: name_role.to_s,
                name: name
            }

            nil
        end

        def na_safe_name(owner)
            return '' unless owner && owner.respond_to?(:name)

            owner.name.to_s
        rescue StandardError
            ''
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dynamic Component Attribute Rows
# -----------------------------------------------------------------------------

        def na_collect_dynamic_component_attributes(owner, owner_type, owner_label, target_array)
            return nil unless owner && target_array
            return nil unless owner.respond_to?(:attribute_dictionaries)

            dictionaries = owner.attribute_dictionaries
            return nil unless dictionaries

            dictionaries.each do |dictionary|
                next unless na_dynamic_component_dictionary?(dictionary)

                keys = []
                dictionary.each_key { |key| keys << key.to_s }
                keys.sort.each do |key|
                    target_array << {
                        owner: owner_label.to_s,
                        owner_type: owner_type.to_s,
                        dictionary: dictionary.name.to_s,
                        key: key,
                        value: na_stringify_attribute_value(dictionary[key])
                    }
                end
            end

            nil
        rescue StandardError
            nil
        end

        def na_dynamic_component_dictionary?(dictionary)
            return false unless dictionary && dictionary.respond_to?(:name)

            dictionary_name = dictionary.name.to_s.downcase
            dictionary_name == 'dynamic_attributes' || dictionary_name == '_dynamic_attributes'
        rescue StandardError
            false
        end

        def na_stringify_attribute_value(value)
            case value
            when NilClass
                ''
            when Numeric, TrueClass, FalseClass
                value.to_s
            else
                value.to_s
            end
        rescue StandardError
            ''
        end

# endregion -------------------------------------------------------------------

    end
end
