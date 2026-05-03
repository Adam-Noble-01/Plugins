# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - DATA SERIALIZER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__DataSerializer__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__DataSerializer
# AUTHOR     : Noble Architecture
# PURPOSE    : Serializes/deserializes interior door configuration data to and
#              from SketchUp component definition AttributeDictionaries via JSON.
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Mirrors the window-side serializer (Na__AssemblyStudio::Na__WindowSystem::Na__DataSerializer)
#   for interior doors, using ADR-series IDs and door-specific dictionary keys.
# - Stores three JSON-encoded blocks on the door's ComponentDefinition:
#       * Na__DoorMetadata        (array of one metadata Hash)
#       * Na__DoorComponents      (array, reserved for future use)
#       * Na__DoorConfiguration   (Hash of Na__DoorConfig__* keys)
# - Stores a tiny pointer dictionary on the ComponentInstance:
#       Na__DoorConfiguratorInfo:
#           - DoorID                (e.g. "ADR001")
#           - SketchUpInstanceName  (current instance name)
#           - SketchUpDefinitionName(current definition name)
# - Provides ID generation, save, load (model-wide and direct-from-instance),
#   delete, list, and naming helpers.
#
# DICTIONARY STRUCTURE:
# - Dictionary on ComponentInstance: "Na__DoorConfiguratorInfo"
#       Key: "DoorID" -> "ADR001"
# - Dictionary on ComponentDefinition: "Na__DoorConfigurator_ADR001"
#       Key: "Na__DoorMetadata"
#       Key: "Na__DoorComponents"
#       Key: "Na__DoorConfiguration"
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'json'
require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem
    module Na__DataSerializer

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants (mirror Na__AssemblyStudio::Na__InteriorDoorSystem constants)
# -----------------------------------------------------------------------------

        # CONSTANTS | Dictionary Identifiers
        # ------------------------------------------------------------
        NA_DICTIONARY_PREFIX     = "Na__DoorConfigurator_".freeze              # <-- Definition dict prefix
        NA_DOOR_INFO_DICT        = "Na__DoorConfiguratorInfo".freeze           # <-- Instance dict
        NA_DOOR_ID_KEY           = "DoorID".freeze                             # <-- Instance attribute key
        NA_SU_INSTANCE_NAME_KEY  = "SketchUpInstanceName".freeze
        NA_SU_DEFINITION_NAME_KEY= "SketchUpDefinitionName".freeze
        # ---------------------------------------------------------------

        # CONSTANTS | Definition Dictionary Block Keys
        # ------------------------------------------------------------
        NA_KEY_METADATA          = "Na__DoorMetadata".freeze
        NA_KEY_COMPONENTS        = "Na__DoorComponents".freeze
        NA_KEY_CONFIGURATION     = "Na__DoorConfiguration".freeze
        # ---------------------------------------------------------------

        # CONSTANTS | ID Format
        # ------------------------------------------------------------
        NA_DOOR_ID_REGEX         = /^ADR\d{3}$/.freeze                         # <-- Validation pattern
        NA_DOOR_ID_FORMAT        = "ADR%03d".freeze                            # <-- sprintf format
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Validation Functions
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Validate Door Data Structure
        # ------------------------------------------------------------
        def self.na_valid_structure?(hash)
            hash.is_a?(Hash) &&
                hash.key?(NA_KEY_METADATA) &&
                hash.key?(NA_KEY_CONFIGURATION)
        end
        private_class_method :na_valid_structure?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Validate Door ID Format (ADRxxx)
        # ------------------------------------------------------------
        def self.na_valid_door_id?(id)
            id.is_a?(String) && id.match?(NA_DOOR_ID_REGEX)
        end
        private_class_method :na_valid_door_id?
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Definition Lookup Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Find Component Definition by Door ID
        # ------------------------------------------------------------
        # Priority 1: Find an instance carrying the DoorID and use its definition.
        # Priority 2: Match a definition by the "<DoorID>__InteriorDoor__" name pattern.
        #
        # @param door_id [String] The door ID to find
        # @return [Sketchup::ComponentDefinition, nil]
        def self.na_find_component_definition_by_door_id(door_id)
            model = Sketchup.active_model
            return nil unless model

            DebugTools.na_debug_serializer("Searching for definition with door ID: #{door_id}")

            instance = na_find_instance_with_door_id(model, door_id)
            if instance
                DebugTools.na_debug_serializer("Found instance with DoorID '#{door_id}': '#{instance.name}'")
                return instance.definition
            end

            DebugTools.na_debug_serializer("No instance carrying DoorID '#{door_id}', falling back to name pattern")
            model.definitions.each do |definition|
                if definition.name.start_with?("#{door_id}__InteriorDoor__")
                    DebugTools.na_debug_serializer("Found definition by name pattern: '#{definition.name}'")
                    return definition
                end
            end

            DebugTools.na_debug_serializer("No definition found for door ID: #{door_id}")
            nil
        end
        private_class_method :na_find_component_definition_by_door_id
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Find Any Component Instance Carrying the Given DoorID
        # ------------------------------------------------------------
        def self.na_find_instance_with_door_id(model, door_id)
            model.entities.grep(Sketchup::ComponentInstance).each do |instance|
                stored = instance.get_attribute(NA_DOOR_INFO_DICT, NA_DOOR_ID_KEY)
                return instance if stored == door_id
            end

            model.definitions.each do |definition_container|
                definition_container.entities.grep(Sketchup::ComponentInstance).each do |instance|
                    stored = instance.get_attribute(NA_DOOR_INFO_DICT, NA_DOOR_ID_KEY)
                    return instance if stored == door_id
                end
            end

            nil
        end
        private_class_method :na_find_instance_with_door_id
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Save / Load Door Data
# -----------------------------------------------------------------------------

        # FUNCTION | Save Door Data to the Component Definition's Dictionary
        # ------------------------------------------------------------
        # @param door_id   [String] e.g. "ADR001"
        # @param data_hash [Hash]   keys: Na__DoorMetadata, Na__DoorComponents, Na__DoorConfiguration
        # @return [Boolean] True on success
        def self.na_save_door_data(door_id, data_hash)
            return false unless na_valid_door_id?(door_id)
            return false unless na_valid_structure?(data_hash)

            definition = na_find_component_definition_by_door_id(door_id)
            unless definition
                DebugTools.na_debug_warn("Could not find definition for door #{door_id}")
                return false
            end

            dict_name = "#{NA_DICTIONARY_PREFIX}#{door_id}"
            dict      = definition.attribute_dictionary(dict_name, true)
            return false unless dict

            begin
                dict[NA_KEY_METADATA]      = JSON.generate(data_hash[NA_KEY_METADATA] || [])
                dict[NA_KEY_COMPONENTS]    = JSON.generate(data_hash[NA_KEY_COMPONENTS] || [])
                dict[NA_KEY_CONFIGURATION] = JSON.generate(data_hash[NA_KEY_CONFIGURATION] || {})
                DebugTools.na_debug_success("Saved door data for #{door_id}")
                true
            rescue => e
                DebugTools.na_debug_error("Error saving door data for #{door_id}", e)
                false
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Load Door Data from the Component Definition's Dictionary
        # ------------------------------------------------------------
        # @param door_id [String] e.g. "ADR001"
        # @return [Hash, nil]
        def self.na_load_door_data(door_id)
            return nil unless na_valid_door_id?(door_id)

            definition = na_find_component_definition_by_door_id(door_id)
            return nil unless definition

            na_load_door_data_from_definition(definition, door_id)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Load Door Data Directly from a Component Instance
        # ------------------------------------------------------------
        # Avoids the model-wide search by reading the dictionary directly
        # from the supplied instance's definition.
        #
        # @param instance [Sketchup::ComponentInstance]
        # @param door_id  [String]
        # @return [Hash, nil]
        def self.na_load_door_data_from_instance(instance, door_id)
            return nil unless instance.is_a?(Sketchup::ComponentInstance)
            return nil unless na_valid_door_id?(door_id)
            na_load_door_data_from_definition(instance.definition, door_id)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Internal Loader - Read JSON Blocks from a Definition
        # ------------------------------------------------------------
        def self.na_load_door_data_from_definition(definition, door_id)
            dict_name = "#{NA_DICTIONARY_PREFIX}#{door_id}"
            dict      = definition.attribute_dictionary(dict_name)
            unless dict
                DebugTools.na_debug_warn("Dict '#{dict_name}' not found on definition '#{definition.name}'")
                return nil
            end

            begin
                metadata_json   = dict[NA_KEY_METADATA]
                components_json = dict[NA_KEY_COMPONENTS]
                config_json     = dict[NA_KEY_CONFIGURATION]

                if !metadata_json || !config_json
                    DebugTools.na_debug_warn("Missing required keys for door #{door_id}")
                    return nil
                end

                {
                    NA_KEY_METADATA      => JSON.parse(metadata_json),
                    NA_KEY_COMPONENTS    => components_json ? JSON.parse(components_json) : [],
                    NA_KEY_CONFIGURATION => JSON.parse(config_json)
                }
            rescue JSON::ParserError => e
                DebugTools.na_debug_error("JSON parse error loading door #{door_id}", e)
                nil
            rescue => e
                DebugTools.na_debug_error("Error loading door #{door_id}", e)
                nil
            end
        end
        private_class_method :na_load_door_data_from_definition
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Delete and List
# -----------------------------------------------------------------------------

        # FUNCTION | Delete Door Data from a Component Definition
        # ------------------------------------------------------------
        def self.na_delete_door_data(door_id)
            return false unless na_valid_door_id?(door_id)

            definition = na_find_component_definition_by_door_id(door_id)
            return false unless definition

            dict_name = "#{NA_DICTIONARY_PREFIX}#{door_id}"
            begin
                definition.attribute_dictionaries.delete(dict_name)
                DebugTools.na_debug_serializer("Deleted dictionary for door #{door_id}")
                true
            rescue => e
                DebugTools.na_debug_error("Error deleting door data", e)
                false
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | List All Door IDs in the Active Model
        # ------------------------------------------------------------
        # @return [Array<String>] Sorted, unique door IDs
        def self.na_list_all_doors
            model = Sketchup.active_model
            return [] unless model

            ids = []

            model.entities.grep(Sketchup::ComponentInstance).each do |instance|
                door_id = instance.get_attribute(NA_DOOR_INFO_DICT, NA_DOOR_ID_KEY)
                ids << door_id if door_id && na_valid_door_id?(door_id)
            end

            model.definitions.each do |definition|
                definition.entities.grep(Sketchup::ComponentInstance).each do |instance|
                    door_id = instance.get_attribute(NA_DOOR_INFO_DICT, NA_DOOR_ID_KEY)
                    ids << door_id if door_id && na_valid_door_id?(door_id)
                end
            end

            ids.uniq.sort
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | ID Generation and Naming
# -----------------------------------------------------------------------------

        # FUNCTION | Generate the Next Available Door ID (ADR###)
        # ------------------------------------------------------------
        def self.na_generate_next_door_id
            existing = na_list_all_doors
            max_num  = 0
            existing.each do |id|
                match = id.match(/^ADR(\d{3})$/)
                if match
                    num     = match[1].to_i
                    max_num = num if num > max_num
                end
            end

            new_id = format(NA_DOOR_ID_FORMAT, max_num + 1)
            DebugTools.na_debug_serializer("Generated new door ID: #{new_id}")
            new_id
        end
        # ---------------------------------------------------------------

        # FUNCTION | Apply DoorID and Naming to a Component Instance
        # ------------------------------------------------------------
        # Sets both the instance and definition names to "<DoorID>__InteriorDoor__<Description>"
        # and writes the DoorID + name pointers to the instance dictionary.
        #
        # @param instance    [Sketchup::ComponentInstance]
        # @param door_id     [String]
        # @param description [String, nil] Optional suffix
        # @return [Boolean]
        def self.na_set_door_id_on_instance(instance, door_id, description = nil)
            return false unless instance.is_a?(Sketchup::ComponentInstance)
            return false unless na_valid_door_id?(door_id)

            full_name = "#{door_id}__InteriorDoor__"
            full_name += description if description && !description.strip.empty?

            instance.name             = full_name
            instance.definition.name  = full_name

            instance.set_attribute(NA_DOOR_INFO_DICT, NA_DOOR_ID_KEY, door_id)
            instance.set_attribute(NA_DOOR_INFO_DICT, NA_SU_INSTANCE_NAME_KEY,   instance.name)
            instance.set_attribute(NA_DOOR_INFO_DICT, NA_SU_DEFINITION_NAME_KEY, instance.definition.name)

            DebugTools.na_debug_serializer("Set DoorID '#{door_id}' on instance '#{instance.name}'")
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read DoorID from a Component Instance (or nil)
        # ------------------------------------------------------------
        def self.na_get_door_id_from_instance(instance)
            return nil unless instance.is_a?(Sketchup::ComponentInstance)
            stored = instance.get_attribute(NA_DOOR_INFO_DICT, NA_DOOR_ID_KEY)
            (stored && na_valid_door_id?(stored)) ? stored : nil
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Convenience Predicates
# -----------------------------------------------------------------------------

        # FUNCTION | Check Whether an Instance Carries Door Data
        # ------------------------------------------------------------
        def self.na_has_door_data?(instance)
            door_id = na_get_door_id_from_instance(instance)
            return false unless door_id

            dict_name = "#{NA_DICTIONARY_PREFIX}#{door_id}"
            !instance.definition.attribute_dictionary(dict_name).nil?
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__DataSerializer
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
