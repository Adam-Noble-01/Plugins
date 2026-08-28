# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - SLIDING DOOR DATA SERIALIZER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSlide__DataSerializer__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem
# MODULE     : Na__DataSerializer
# AUTHOR     : Noble Architecture
# PURPOSE    : Serialises and deserialises sliding-door configuration JSON
#              onto SketchUp ComponentDefinition + ComponentInstance
#              attribute dictionaries. Mirrors the bifold + InteriorDoor
#              serializers so the SelectionCoordinator can route every
#              door type through identical handler contracts.
# CREATED    : 17-May-2026
#
# DESCRIPTION:
# - Stores three JSON-encoded blocks on the sliding door's ComponentDefinition:
#       * Na__SlidingDoorMetadata        (array of one metadata Hash)
#       * Na__SlidingDoorComponents      (array, reserved for future use)
#       * Na__SlidingDoorConfiguration   (Hash of sliding_door_* keys)
# - Stores a tiny pointer dictionary on the ComponentInstance:
#       Na__SlidingDoorConfiguratorInfo:
#           - DoorID                (e.g. "ADR043")
#           - SketchUpInstanceName  (current instance name)
#           - SketchUpDefinitionName(current definition name)
#
# ID GENERATION CONTRACT:
# - `na_generate_next_door_id` delegates to `Na__AssemblyComposer.na_allocate_adr_id`
#   so all door types (bifold, sliding, interior) share a single, globally
#   unique ADR id pool. The composer scanner already inspects bifold,
#   sliding, and legacy interior-door dictionaries.
#
# DEVELOPMENT LOG:
# 17-May-2026 - Version 0.2.0
# - Phase-3.5 implementation: full save / load / list / delete / id surface.
#
# 17-May-2026 - Version 0.1.0
# - Phase-1 scaffold (na_get_door_id_from_instance only).
#
# =============================================================================

require 'json'
require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__ComponentNameSuffix__'
require_relative 'Na__AssemblyStudio__ExtSlide__AssemblyComposer__'

module Na__AssemblyStudio
module Na__ExteriorSlidingDoorSystem
module Na__DataSerializer

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    DebugTools       = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools                                          # <-- Shared debug logger
    AssemblyComposer = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__AssemblyComposer                   # <-- ADR id allocator (model-wide scan)
    # @delegate: ../04__GeometryHelpers/Na__AssemblyStudio__ComponentNameSuffix__.rb
    ComponentNameSuffix = Na__AssemblyStudio::Na__GeometryHelpers::Na__ComponentNameSuffix

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Validation Functions
# -----------------------------------------------------------------------------

    def self.na_valid_door_id?(id)
        id.is_a?(String) && id.match?(Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_DOOR_ID_REGEX)
    end
    private_class_method :na_valid_door_id?

    def self.na_valid_structure?(hash)
        return false unless hash.is_a?(Hash)
        hash.key?(Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_METADATA) &&
            hash.key?(Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_CONFIGURATION)
    end
    private_class_method :na_valid_structure?

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Definition Lookup Helpers
# -----------------------------------------------------------------------------

    def self.na_find_component_definition_by_door_id(door_id)
        model = Sketchup.active_model
        return nil unless model

        instance = na_find_instance_with_door_id(model, door_id)
        return instance.definition if instance

        suffix = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_DEFINITION_SUFFIX_DOOR
        model.definitions.each do |definition|
            return definition if definition.name.start_with?("#{door_id}#{suffix}")
        end

        nil
    end
    private_class_method :na_find_component_definition_by_door_id

    def self.na_find_instance_with_door_id(model, door_id)
        info_dict = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_DOOR_INFO_DICT
        id_key    = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_ID

        model.entities.grep(Sketchup::ComponentInstance).each do |instance|
            stored = instance.get_attribute(info_dict, id_key)
            return instance if stored == door_id
        end

        model.definitions.each do |definition_container|
            definition_container.entities.grep(Sketchup::ComponentInstance).each do |instance|
                stored = instance.get_attribute(info_dict, id_key)
                return instance if stored == door_id
            end
        end

        nil
    end
    private_class_method :na_find_instance_with_door_id

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Save / Load Door Data
# -----------------------------------------------------------------------------

    def self.na_save_door_data(door_id, data_hash)
        return false unless na_valid_door_id?(door_id)
        return false unless na_valid_structure?(data_hash)

        definition = na_find_component_definition_by_door_id(door_id)
        unless definition
            DebugTools.na_debug_warn("[ExtSlide::Serializer] Could not find definition for door #{door_id}")
            return false
        end

        dict_name = "#{Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_DOOR_DEF_DICT_PREFIX}#{door_id}"
        dict      = definition.attribute_dictionary(dict_name, true)
        return false unless dict

        meta_key = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_METADATA
        comp_key = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_COMPONENTS
        cfg_key  = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_CONFIGURATION

        begin
            dict[meta_key] = JSON.generate(data_hash[meta_key] || [])
            dict[comp_key] = JSON.generate(data_hash[comp_key] || [])
            dict[cfg_key]  = JSON.generate(data_hash[cfg_key] || {})
            DebugTools.na_debug_success("[ExtSlide::Serializer] Saved sliding data for #{door_id}")
            true
        rescue StandardError => e
            DebugTools.na_debug_error("[ExtSlide::Serializer] Error saving sliding data for #{door_id}", e)
            false
        end
    end

    def self.na_load_door_data(door_id)
        return nil unless na_valid_door_id?(door_id)

        definition = na_find_component_definition_by_door_id(door_id)
        return nil unless definition

        na_load_door_data_from_definition(definition, door_id)
    end

    def self.na_load_door_data_from_instance(instance, door_id)
        return nil unless instance.is_a?(Sketchup::ComponentInstance)
        return nil unless na_valid_door_id?(door_id)
        na_load_door_data_from_definition(instance.definition, door_id)
    end

    def self.na_load_door_data_from_definition(definition, door_id)
        dict_name = "#{Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_DOOR_DEF_DICT_PREFIX}#{door_id}"
        dict      = definition.attribute_dictionary(dict_name)
        unless dict
            DebugTools.na_debug_warn("[ExtSlide::Serializer] Dict '#{dict_name}' not found on '#{definition.name}'")
            return nil
        end

        meta_key = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_METADATA
        comp_key = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_COMPONENTS
        cfg_key  = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_CONFIGURATION

        begin
            metadata_json   = dict[meta_key]
            components_json = dict[comp_key]
            config_json     = dict[cfg_key]

            if metadata_json.nil? || config_json.nil?
                DebugTools.na_debug_warn("[ExtSlide::Serializer] Missing required keys for door #{door_id}")
                return nil
            end

            {
                meta_key => JSON.parse(metadata_json),
                comp_key => components_json ? JSON.parse(components_json) : [],
                cfg_key  => JSON.parse(config_json)
            }
        rescue JSON::ParserError => e
            DebugTools.na_debug_error("[ExtSlide::Serializer] JSON parse error loading door #{door_id}", e)
            nil
        rescue StandardError => e
            DebugTools.na_debug_error("[ExtSlide::Serializer] Error loading door #{door_id}", e)
            nil
        end
    end
    private_class_method :na_load_door_data_from_definition

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Delete and List
# -----------------------------------------------------------------------------

    def self.na_delete_door_data(door_id)
        return false unless na_valid_door_id?(door_id)

        definition = na_find_component_definition_by_door_id(door_id)
        return false unless definition

        dict_name = "#{Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_DOOR_DEF_DICT_PREFIX}#{door_id}"
        begin
            definition.attribute_dictionaries.delete(dict_name)
            DebugTools.na_debug_serializer("[ExtSlide::Serializer] Deleted dictionary for door #{door_id}")
            true
        rescue StandardError => e
            DebugTools.na_debug_error("[ExtSlide::Serializer] Error deleting door data", e)
            false
        end
    end

    def self.na_list_all_doors
        model = Sketchup.active_model
        return [] unless model

        info_dict = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_DOOR_INFO_DICT
        id_key    = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_ID

        ids = []

        model.entities.grep(Sketchup::ComponentInstance).each do |instance|
            stored = instance.get_attribute(info_dict, id_key)
            ids << stored if stored && na_valid_door_id?(stored)
        end

        model.definitions.each do |definition|
            definition.entities.grep(Sketchup::ComponentInstance).each do |instance|
                stored = instance.get_attribute(info_dict, id_key)
                ids << stored if stored && na_valid_door_id?(stored)
            end
        end

        ids.uniq.sort
    end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | ID Generation and Naming
# -----------------------------------------------------------------------------

    def self.na_generate_next_door_id
        AssemblyComposer.na_allocate_adr_id
    end

    # FUNCTION | Build the Fixed Head of This Door's Component Name
    # ------------------------------------------------------------
    def self.na_door_definition_prefix(door_id)
        "#{door_id}#{Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_DEFINITION_SUFFIX_DOOR}"
    end

    # FUNCTION | Bind Door ID Onto Instance and Definition Names
    # ------------------------------------------------------------
    # @param component_name [String, Symbol] Optional user-authored name
    #     tail appended after the fixed `ADR###__SlidingDoor__` head.
    #     Defaults to NA_KEEP so a rebuild never un-names the component.
    def self.na_set_door_id_on_instance(instance, door_id, component_name = ComponentNameSuffix::NA_KEEP)
        return false unless instance.is_a?(Sketchup::ComponentInstance)
        return false unless na_valid_door_id?(door_id)

        full_name = ComponentNameSuffix.na_apply(instance, na_door_definition_prefix(door_id), component_name)
        return false unless full_name

        info_dict = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_DOOR_INFO_DICT
        instance.set_attribute(info_dict, Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_ID,            door_id)
        instance.set_attribute(info_dict, Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_SU_INSTANCE_NAME,   instance.name)
        instance.set_attribute(info_dict, Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_SU_DEFINITION_NAME, instance.definition.name)

        DebugTools.na_debug_serializer("[ExtSlide::Serializer] Set DoorID '#{door_id}' on instance '#{instance.name}'")
        true
    end

    def self.na_get_door_id_from_instance(instance)
        return nil unless instance.is_a?(Sketchup::ComponentInstance)
        info_dict = instance.attribute_dictionary(
            Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_DOOR_INFO_DICT, false
        )
        return nil unless info_dict
        candidate = info_dict[Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_KEY_DOOR_ID]
        return nil unless candidate.is_a?(String)
        na_valid_door_id?(candidate) ? candidate : nil
    end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Convenience Predicates
# -----------------------------------------------------------------------------

    def self.na_has_door_data?(instance)
        door_id = na_get_door_id_from_instance(instance)
        return false unless door_id

        dict_name = "#{Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_DOOR_DEF_DICT_PREFIX}#{door_id}"
        !instance.definition.attribute_dictionary(dict_name).nil?
    end

# endregion -------------------------------------------------------------------

end # module Na__DataSerializer
end # module Na__ExteriorSlidingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
