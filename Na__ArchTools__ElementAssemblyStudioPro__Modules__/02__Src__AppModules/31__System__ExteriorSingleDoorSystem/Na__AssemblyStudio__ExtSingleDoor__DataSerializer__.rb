# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR - DATA SERIALIZER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSingleDoor__DataSerializer__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSingleDoorSystem
# MODULE     : Na__DataSerializer
# AUTHOR     : Noble Architecture
# PURPOSE    : ADR id allocation + attribute-dictionary persistence for the
#              standalone exterior single door. Mirrors the double-door
#              serializer with single-door dictionary names.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'json'
require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__DoorNamingContract__'

module Na__AssemblyStudio
module Na__ExteriorSingleDoorSystem
module Na__DataSerializer

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    NamingContract = Na__AssemblyStudio::Na__GeometryHelpers::Na__DoorNamingContract

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_KNOWN_INSTANCE_DICTIONARIES = [
        'Na__ExteriorSingleDoorConfiguratorInfo',
        'Na__ExteriorDoubleDoorConfiguratorInfo',
        'Na__DoorConfiguratorInfo',
        'Na__SlidingDoorConfiguratorInfo',
        'Na__BifoldDoorConfiguratorInfo'
    ].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - ADR ID Allocation + Instance Binding
# -----------------------------------------------------------------------------

    # FUNCTION | Allocate the Next Unused ADR Door ID
    # ------------------------------------------------------------
    def self.na_allocate_adr_id(model = Sketchup.active_model)
        used = na_collect_used_adr_numbers(model)
        NamingContract.na_format_adr_id(used.empty? ? 1 : used.max + 1)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Bind Door ID Onto Instance and Definition Names
    # ------------------------------------------------------------
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
    # ---------------------------------------------------------------

    # FUNCTION | Read Door ID From Instance Attribute Dictionary
    # ------------------------------------------------------------
    def self.na_get_door_id_from_instance(instance)
        return nil unless na_valid_instance?(instance)
        dictionary = instance.attribute_dictionary(NA_DOOR_INFO_DICT, false)
        return nil unless dictionary
        candidate = dictionary[NA_KEY_DOOR_ID]
        na_valid_door_id?(candidate) ? candidate : nil
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Save / Load / Find
# -----------------------------------------------------------------------------

    # FUNCTION | Persist Configuration Onto the Door Definition Dictionary
    # ------------------------------------------------------------
    def self.na_save(instance, configuration, metadata = nil, components = nil)
        door_id = na_get_door_id_from_instance(instance)
        return false unless door_id
        dictionary = instance.definition.attribute_dictionary("#{NA_DOOR_DEF_DICT_PREFIX}#{door_id}", true)
        return false unless dictionary

        incoming_config = na_string_key_hash(configuration)
        effective_config = Na__ExteriorSingleDoorSystem.na_default_config.merge(incoming_config)
        existing_metadata = na_parse_json(dictionary[NA_KEY_METADATA], nil)
        existing_components = na_parse_json(dictionary[NA_KEY_COMPONENTS], nil)
        dictionary[NA_KEY_METADATA] = JSON.generate(metadata || existing_metadata || na_default_metadata(door_id))
        dictionary[NA_KEY_COMPONENTS] = JSON.generate(components || existing_components || na_default_components)
        dictionary[NA_KEY_CONFIGURATION] = JSON.generate(effective_config)
        true
    rescue StandardError => error
        DebugTools.na_debug_error('ExtSingleDoor serializer save failed', error) if defined?(DebugTools)
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Load Persisted Payload From an Instance
    # ------------------------------------------------------------
    def self.na_load_from_instance(instance)
        door_id = na_get_door_id_from_instance(instance)
        return nil unless door_id
        dictionary = instance.definition.attribute_dictionary("#{NA_DOOR_DEF_DICT_PREFIX}#{door_id}", false)
        return nil unless dictionary
        configuration = na_parse_json(dictionary[NA_KEY_CONFIGURATION], {})
        {
            NA_KEY_METADATA => na_parse_json(dictionary[NA_KEY_METADATA], na_default_metadata(door_id)),
            NA_KEY_COMPONENTS => na_parse_json(dictionary[NA_KEY_COMPONENTS], na_default_components),
            NA_KEY_CONFIGURATION => Na__ExteriorSingleDoorSystem.na_default_config.merge(configuration)
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Find an Instance by Door ID in the Active Model
    # ------------------------------------------------------------
    def self.na_find_instance(door_id, model = Sketchup.active_model)
        return nil unless model && na_valid_door_id?(door_id)
        model.definitions.each do |definition|
            definition.instances.each do |instance|
                return instance if na_get_door_id_from_instance(instance) == door_id
            end
        end
        nil
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - ID Scanning + Validation
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Collect Used ADR Numbers Across Known Door Dictionaries
    # ------------------------------------------------------------
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
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Validate Door ID Against ADR Regex Contract
    # ------------------------------------------------------------
    def self.na_valid_door_id?(door_id)
        door_id.is_a?(String) && door_id.match?(NA_DOOR_ID_REGEX)
    end
    private_class_method :na_valid_door_id?
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Validate a Live ComponentInstance
    # ------------------------------------------------------------
    def self.na_valid_instance?(instance)
        instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
    end
    private_class_method :na_valid_instance?
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - JSON + Defaults
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Coerce Hash Keys to Strings
    # ------------------------------------------------------------
    def self.na_string_key_hash(value)
        return {} unless value.is_a?(Hash)
        value.each_with_object({}) { |(key, item), result| result[key.to_s] = item }
    end
    private_class_method :na_string_key_hash
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Parse a JSON String with Fallback
    # ------------------------------------------------------------
    def self.na_parse_json(value, fallback)
        return fallback if value.nil?
        JSON.parse(value)
    rescue JSON::ParserError, TypeError
        fallback
    end
    private_class_method :na_parse_json
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Default Metadata Block for a New Door
    # ------------------------------------------------------------
    def self.na_default_metadata(door_id)
        [{
            'Na__ExteriorSingleDoor__UniqueId' => door_id,
            'Na__ExteriorSingleDoor__Name' => 'Exterior Single Door',
            'Na__ExteriorSingleDoor__Description' => '',
            'Na__ExteriorSingleDoor__Notes' => 'Created with Element Assembly Studio Pro'
        }]
    end
    private_class_method :na_default_metadata
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Default Components Block for a New Door
    # ------------------------------------------------------------
    def self.na_default_components
        [
            { 'ComponentId' => 'MOD001', 'Role' => 'Leaf' },
            { 'ComponentId' => 'ROT001', 'Role' => 'Pivot' }
        ]
    end
    private_class_method :na_default_components
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__DataSerializer
end # module Na__ExteriorSingleDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
