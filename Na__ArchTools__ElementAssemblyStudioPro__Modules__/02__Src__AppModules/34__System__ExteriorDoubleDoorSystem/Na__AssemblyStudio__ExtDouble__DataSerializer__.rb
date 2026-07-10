# frozen_string_literal: true

require 'json'
require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__DoorNamingContract__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__DataSerializer

    NamingContract = Na__AssemblyStudio::Na__GeometryHelpers::Na__DoorNamingContract
    NA_KNOWN_INSTANCE_DICTIONARIES = [
        'Na__ExteriorDoubleDoorConfiguratorInfo',
        'Na__DoorConfiguratorInfo',
        'Na__SlidingDoorConfiguratorInfo',
        'Na__BifoldDoorConfiguratorInfo'
    ].freeze

    def self.na_allocate_adr_id(model = Sketchup.active_model)
        used = na_collect_used_adr_numbers(model)
        NamingContract.na_format_adr_id(used.empty? ? 1 : used.max + 1)
    end

    def self.na_set_door_id_on_instance(instance, door_id)
        return false unless na_valid_instance?(instance) && na_valid_door_id?(door_id)

        name = "#{door_id}#{NA_DEFINITION_SUFFIX}"
        instance.name = name
        instance.definition.name = name
        instance.set_attribute(NA_DOOR_INFO_DICT, NA_KEY_DOOR_ID, door_id)
        instance.set_attribute(NA_DOOR_INFO_DICT, NA_KEY_INSTANCE_NAME, name)
        instance.set_attribute(NA_DOOR_INFO_DICT, NA_KEY_DEFINITION_NAME, name)
        true
    end

    def self.na_get_door_id_from_instance(instance)
        return nil unless na_valid_instance?(instance)
        dictionary = instance.attribute_dictionary(NA_DOOR_INFO_DICT, false)
        return nil unless dictionary
        candidate = dictionary[NA_KEY_DOOR_ID]
        na_valid_door_id?(candidate) ? candidate : nil
    end

    def self.na_has_door_data?(instance)
        door_id = na_get_door_id_from_instance(instance)
        return false unless door_id
        !instance.definition.attribute_dictionary("#{NA_DOOR_DEF_DICT_PREFIX}#{door_id}", false).nil?
    end

    def self.na_save(instance, configuration, metadata = nil, components = nil)
        door_id = na_get_door_id_from_instance(instance)
        return false unless door_id

        dictionary = instance.definition.attribute_dictionary(
            "#{NA_DOOR_DEF_DICT_PREFIX}#{door_id}", true
        )
        return false unless dictionary

        incoming_config = na_migrate_independent_rail_keys(na_string_key_hash(configuration))
        effective_config = Na__ExteriorDoubleDoorSystem.na_default_config.merge(incoming_config)
        existing_metadata = na_parse_json(dictionary[NA_KEY_METADATA], nil)
        existing_components = na_parse_json(dictionary[NA_KEY_COMPONENTS], nil)
        effective_metadata = metadata || existing_metadata || na_default_metadata(door_id)
        effective_components = components || existing_components || na_default_components
        dictionary[NA_KEY_METADATA] = JSON.generate(effective_metadata)
        dictionary[NA_KEY_COMPONENTS] = JSON.generate(effective_components)
        dictionary[NA_KEY_CONFIGURATION] = JSON.generate(effective_config)
        true
    rescue StandardError => error
        DebugTools.na_debug_error('ExtDouble serializer save failed', error)
        false
    end

    def self.na_load_from_instance(instance)
        door_id = na_get_door_id_from_instance(instance)
        return nil unless door_id
        dictionary = instance.definition.attribute_dictionary(
            "#{NA_DOOR_DEF_DICT_PREFIX}#{door_id}", false
        )
        return nil unless dictionary

        configuration = na_migrate_independent_rail_keys(
            na_parse_json(dictionary[NA_KEY_CONFIGURATION], {})
        )
        {
            NA_KEY_METADATA => na_parse_json(dictionary[NA_KEY_METADATA], na_default_metadata(door_id)),
            NA_KEY_COMPONENTS => na_parse_json(dictionary[NA_KEY_COMPONENTS], na_default_components),
            NA_KEY_CONFIGURATION => Na__ExteriorDoubleDoorSystem.na_default_config.merge(configuration)
        }
    end

    def self.na_load(door_id, model = Sketchup.active_model)
        instance = na_find_instance(door_id, model)
        instance ? na_load_from_instance(instance) : nil
    end

    def self.na_find_instance(door_id, model = Sketchup.active_model)
        return nil unless model && na_valid_door_id?(door_id)
        model.definitions.each do |definition|
            definition.instances.each do |instance|
                return instance if na_get_door_id_from_instance(instance) == door_id
            end
        end
        nil
    end

    def self.na_list_all_doors(model = Sketchup.active_model)
        return [] unless model
        ids = []
        model.definitions.each do |definition|
            definition.instances.each do |instance|
                door_id = na_get_door_id_from_instance(instance)
                ids << door_id if door_id
            end
        end
        ids.uniq.sort
    end

    def self.na_delete(instance)
        door_id = na_get_door_id_from_instance(instance)
        return false unless door_id
        dictionaries = instance.definition.attribute_dictionaries
        dictionaries.delete("#{NA_DOOR_DEF_DICT_PREFIX}#{door_id}") if dictionaries
        true
    rescue StandardError
        false
    end

    def self.na_collect_used_adr_numbers(model)
        return [] unless model
        used = []
        model.definitions.each do |definition|
            definition.instances.each do |instance|
                NA_KNOWN_INSTANCE_DICTIONARIES.each do |dictionary_name|
                    begin
                        value = instance.get_attribute(dictionary_name, 'DoorID')
                        number = NamingContract.na_extract_adr_number(value)
                        used << number if number
                    rescue StandardError
                        next
                    end
                end
            end
        end
        used.uniq
    end
    private_class_method :na_collect_used_adr_numbers

    def self.na_valid_door_id?(door_id)
        door_id.is_a?(String) && door_id.match?(NA_DOOR_ID_REGEX)
    end
    private_class_method :na_valid_door_id?

    def self.na_valid_instance?(instance)
        instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
    end
    private_class_method :na_valid_instance?

    def self.na_string_key_hash(value)
        return {} unless value.is_a?(Hash)
        value.each_with_object({}) { |(key, item), result| result[key.to_s] = item }
    end
    private_class_method :na_string_key_hash

    def self.na_migrate_independent_rail_keys(configuration)
        return {} unless configuration.is_a?(Hash)

        migrated = configuration.dup
        migrated['double_door_panel_top_rail_width_mm'] ||= 95
        migrated['double_door_panel_bottom_rail_width_mm'] ||=
            migrated['double_door_panel_rail_width_mm'] || 150
        unless migrated.key?('double_door_removed_glazebars')
            migrated['double_door_removed_glazebars'] =
                Array(migrated['removed_glazebars']).map(&:to_s)
        end
        migrated.delete('removed_glazebars')

        %w[left right].each do |side|
            prefix = "double_door_#{side}_"
            legacy_key = "#{prefix}panel_rail_width_mm"
            next unless migrated.key?(legacy_key)

            migrated["#{prefix}panel_top_rail_width_mm"] ||= 95
            migrated["#{prefix}panel_bottom_rail_width_mm"] ||= migrated[legacy_key]
        end

        migrated
    end
    private_class_method :na_migrate_independent_rail_keys

    def self.na_parse_json(value, fallback)
        return fallback if value.nil?
        JSON.parse(value)
    rescue JSON::ParserError, TypeError
        fallback
    end
    private_class_method :na_parse_json

    def self.na_default_metadata(door_id)
        [{
            'Na__ExteriorDoubleDoor__UniqueId' => door_id,
            'Na__ExteriorDoubleDoor__Name' => 'Exterior Double Door',
            'Na__ExteriorDoubleDoor__Description' => '',
            'Na__ExteriorDoubleDoor__Notes' => 'Created with Element Assembly Studio Pro'
        }]
    end
    private_class_method :na_default_metadata

    def self.na_default_components
        [
            { 'ComponentId' => 'MOD001', 'Role' => 'LeftLeaf' },
            { 'ComponentId' => 'ROT001', 'Role' => 'LeftPivot' },
            { 'ComponentId' => 'MOD002', 'Role' => 'RightLeaf' },
            { 'ComponentId' => 'ROT002', 'Role' => 'RightPivot' }
        ]
    end
    private_class_method :na_default_components

end
end
end
