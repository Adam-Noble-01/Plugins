# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - SERIALIZER BASE
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AppData__SerializerBase__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AppData
# MODULE     : Na__SerializerBase
# AUTHOR     : Noble Architecture
# PURPOSE    : Parameterised serializer base used by every system that needs to
#              persist configurator data on a SketchUp ComponentDefinition.
#              Replaces the two near-duplicate Ruby DataSerializer modules in
#              the original Window and Interior Door tools.
#
# CONFIG SOURCE
# - Each system passes a config hash describing its dictionary names, key
#   names, ID regex/format and definition name suffix. The same shape lives
#   in AppConfig.attributeDictionaries for declarative discovery.
#
# =============================================================================

require 'json'
require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
    module Na__AppData
        module Na__SerializerBase

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

            # -----------------------------------------------------------------
            # REGION | Validation
            # -----------------------------------------------------------------

            def self.na_valid_id?(config, id)
                id.is_a?(String) && id.match?(Regexp.new(config[:id_regex]))
            end

            def self.na_valid_structure?(config, hash)
                hash.is_a?(Hash) &&
                hash.key?(config[:metadata_key]) &&
                hash.key?(config[:configuration_key])
            end

            # -----------------------------------------------------------------
            # REGION | Definition Resolution
            # -----------------------------------------------------------------

            def self.na_find_definition_by_id(config, item_id)
                model = Sketchup.active_model
                return nil unless model

                instance_dict = config[:instance_dict_name]
                id_attr       = config[:instance_id_attribute]

                instances = []
                model.entities.grep(Sketchup::ComponentInstance).each do |inst|
                    instances << inst if inst.get_attribute(instance_dict, id_attr) == item_id
                end

                model.definitions.each do |def_container|
                    def_container.entities.grep(Sketchup::ComponentInstance).each do |inst|
                        next if instances.any? { |i| i.entityID == inst.entityID }
                        instances << inst if inst.get_attribute(instance_dict, id_attr) == item_id
                    end
                end

                return instances.first.definition unless instances.empty?

                fallback_prefix = "#{item_id}#{config[:definition_name_suffix]}"
                model.definitions.each do |definition|
                    return definition if definition.name.start_with?(fallback_prefix)
                end

                nil
            end

            # -----------------------------------------------------------------
            # REGION | Save / Load / Delete
            # -----------------------------------------------------------------

            def self.na_save(config, item_id, data_hash)
                return false unless na_valid_id?(config, item_id)
                return false unless na_valid_structure?(config, data_hash)

                definition = na_find_definition_by_id(config, item_id)
                unless definition
                    DebugTools.na_debug_serializer("SerializerBase: no definition for #{item_id}")
                    return false
                end

                dict_name = "#{config[:definition_dict_prefix]}#{item_id}"
                dict      = definition.attribute_dictionary(dict_name, true)
                return false unless dict

                begin
                    dict[config[:metadata_key]]      = JSON.generate(data_hash[config[:metadata_key]]      || [])
                    dict[config[:components_key]]    = JSON.generate(data_hash[config[:components_key]]    || [])
                    dict[config[:configuration_key]] = JSON.generate(data_hash[config[:configuration_key]] || {})
                    DebugTools.na_debug_success("SerializerBase: saved #{item_id}")
                    true
                rescue StandardError => e
                    DebugTools.na_debug_error("SerializerBase: save #{item_id} failed", e)
                    false
                end
            end

            def self.na_load(config, item_id)
                return nil unless na_valid_id?(config, item_id)

                definition = na_find_definition_by_id(config, item_id)
                return nil unless definition

                na_load_from_definition(config, item_id, definition)
            end

            def self.na_load_from_instance(config, instance, item_id)
                return nil unless instance.is_a?(Sketchup::ComponentInstance)
                return nil unless na_valid_id?(config, item_id)
                na_load_from_definition(config, item_id, instance.definition)
            end

            def self.na_load_from_definition(config, item_id, definition)
                dict_name = "#{config[:definition_dict_prefix]}#{item_id}"
                dict      = definition.attribute_dictionary(dict_name)
                return nil if dict.nil?

                begin
                    metadata_json   = dict[config[:metadata_key]]
                    components_json = dict[config[:components_key]]
                    config_json     = dict[config[:configuration_key]]
                    return nil if metadata_json.nil? || config_json.nil?

                    {
                        config[:metadata_key]      => JSON.parse(metadata_json),
                        config[:components_key]    => components_json ? JSON.parse(components_json) : [],
                        config[:configuration_key] => JSON.parse(config_json)
                    }
                rescue JSON::ParserError => e
                    DebugTools.na_debug_error("SerializerBase: JSON parse failed for #{item_id}", e)
                    nil
                end
            end

            def self.na_delete(config, item_id)
                return false unless na_valid_id?(config, item_id)
                definition = na_find_definition_by_id(config, item_id)
                return false unless definition

                dict_name = "#{config[:definition_dict_prefix]}#{item_id}"
                begin
                    definition.attribute_dictionaries.delete(dict_name)
                    DebugTools.na_debug_serializer("SerializerBase: deleted #{item_id}")
                    true
                rescue StandardError => e
                    DebugTools.na_debug_error("SerializerBase: delete #{item_id} failed", e)
                    false
                end
            end

            def self.na_has_data?(config, instance)
                item_id = na_get_id_from_instance(config, instance)
                return false unless item_id
                dict_name = "#{config[:definition_dict_prefix]}#{item_id}"
                !instance.definition.attribute_dictionary(dict_name).nil?
            end

            # -----------------------------------------------------------------
            # REGION | Listing & ID Management
            # -----------------------------------------------------------------

            def self.na_list_all(config)
                model = Sketchup.active_model
                return [] unless model

                instance_dict = config[:instance_dict_name]
                id_attr       = config[:instance_id_attribute]
                ids           = []

                model.entities.grep(Sketchup::ComponentInstance).each do |inst|
                    id = inst.get_attribute(instance_dict, id_attr)
                    ids << id if id && na_valid_id?(config, id)
                end

                model.definitions.each do |definition|
                    definition.entities.grep(Sketchup::ComponentInstance).each do |inst|
                        id = inst.get_attribute(instance_dict, id_attr)
                        ids << id if id && na_valid_id?(config, id)
                    end
                end

                ids.uniq
            end

            def self.na_generate_next_id(config)
                regex   = Regexp.new(config[:id_regex])
                max_num = 0
                na_list_all(config).each do |id|
                    next unless id.match?(regex)
                    digits = id.scan(/\d+/).first
                    next unless digits
                    n = digits.to_i
                    max_num = n if n > max_num
                end
                format(config[:id_format], max_num + 1)
            end

            def self.na_set_id_on_instance(config, instance, item_id, description = nil)
                return false unless instance.is_a?(Sketchup::ComponentInstance)
                return false unless na_valid_id?(config, item_id)

                full_name  = "#{item_id}#{config[:definition_name_suffix]}"
                full_name += description if description && !description.strip.empty?

                instance.name            = full_name
                instance.definition.name = full_name

                instance.set_attribute(config[:instance_dict_name], config[:instance_id_attribute], item_id)
                instance.set_attribute(config[:instance_dict_name], "SketchUpInstanceName",   instance.name)
                instance.set_attribute(config[:instance_dict_name], "SketchUpDefinitionName", instance.definition.name)
                true
            end

            def self.na_get_id_from_instance(config, instance)
                return nil unless instance.is_a?(Sketchup::ComponentInstance)
                id = instance.get_attribute(config[:instance_dict_name], config[:instance_id_attribute])
                (id && na_valid_id?(config, id)) ? id : nil
            end

            # -----------------------------------------------------------------
            # REGION | Optional JSON Round-Trip
            # -----------------------------------------------------------------

            def self.na_export_json(config, item_id)
                data = na_load(config, item_id)
                data ? JSON.pretty_generate(data) : nil
            end

            def self.na_import_json(config, item_id, json_string)
                data = JSON.parse(json_string)
                na_save(config, item_id, data)
            rescue JSON::ParserError => e
                DebugTools.na_debug_error("SerializerBase: import JSON failed for #{item_id}", e)
                false
            end

            # -----------------------------------------------------------------
            # REGION | Convenience Builder
            # -----------------------------------------------------------------

            def self.na_config_from_app_config(system_key)
                cfg_node = nil
                if defined?(Na__AssemblyStudio::Na__AppData::Na__ConfigLoader)
                    cfg_node = Na__AssemblyStudio::Na__AppData::Na__ConfigLoader.na_get('attributeDictionaries', system_key)
                end
                return nil unless cfg_node.is_a?(Hash)
                {
                    :instance_dict_name        => cfg_node['instanceDictName'],
                    :instance_id_attribute     => cfg_node['instanceIdAttribute'],
                    :definition_dict_prefix    => cfg_node['definitionDictPrefix'],
                    :metadata_key              => cfg_node['metadataKey'],
                    :components_key            => cfg_node['componentsKey'],
                    :configuration_key         => cfg_node['configurationKey'],
                    :id_regex                  => cfg_node['idRegex'],
                    :id_format                 => cfg_node['idFormat'],
                    :definition_name_suffix    => cfg_node['definitionNameSuffix']
                }
            end

        end
    end
end
