# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - DATA SERIALIZER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__DataSerializer__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem
# MODULE     : Na__DataSerializer
# AUTHOR     : Noble Architecture
# PURPOSE    : Serializes and deserializes window configuration data to/from
#              SketchUp component definition attribute dictionaries using JSON.
# CREATED    : 2026
#
# DESCRIPTION:
# - This utility module provides a dedicated handler for serializing window data
#   (metadata, components, configuration) into JSON strings and writing them to
#   SketchUp component definition attribute dictionaries.
# - It also deserializes stored JSON strings from the dictionary, validates them,
#   and returns native Ruby Hashes for use in the main plugin logic.
# - Data is stored on ComponentDefinition (not model level) for portability.
# - This class is stateless and can be safely required by other tool scripts.
#
# DICTIONARY STRUCTURE:
# - Dictionary on ComponentInstance: "Na__WindowConfiguratorInfo" 
#   - Key: "WindowID" (e.g., "AWN001")
# - Dictionary on ComponentDefinition: "Na__WindowConfigurator_[WindowID]"
#   - Key: "windowMetadata"
#   - Key: "windowComponents"
#   - Key: "windowConfiguration"
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
# - Distinguishes Noble Architecture code from third-party libraries
#
# ADAPTED FROM:
# - ValeDesignSuite_Tools_FrameworkToolsDataSerializer.rb
#
# =============================================================================

require 'json'
require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__ComponentNameSuffix__'

module Na__AssemblyStudio
module Na__WindowSystem
    module Na__DataSerializer

# -----------------------------------------------------------------------------
# REGION | Debug Tools Reference
# -----------------------------------------------------------------------------

        # MODULE REFERENCE | Link to Debug Tools
        # ------------------------------------------------------------
        DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        # ---------------------------------------------------------------

        # MODULE REFERENCE | Shared Component-Name Suffix Authority
        # ------------------------------------------------------------
        # @delegate: ../04__GeometryHelpers/Na__AssemblyStudio__ComponentNameSuffix__.rb
        ComponentNameSuffix = Na__AssemblyStudio::Na__GeometryHelpers::Na__ComponentNameSuffix
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        # CONSTANTS | Dictionary Identifiers
        # ------------------------------------------------------------
        NA_DICTIONARY_PREFIX     = "Na__WindowConfigurator_".freeze     # Prefix for definition dictionaries
        NA_METADATA_KEY          = "windowMetadata".freeze              # Key for metadata array
        NA_COMPONENTS_KEY        = "windowComponents".freeze            # Key for window components
        NA_CONFIG_KEY            = "windowConfiguration".freeze         # Key for configuration hash
        
        # CONSTANTS | Instance Attribute Dictionary
        # ------------------------------------------------------------
        NA_WINDOW_INFO_DICT      = "Na__WindowConfiguratorInfo".freeze  # Dictionary on ComponentInstance
        NA_WINDOW_ID_KEY         = "WindowID".freeze                    # Key for storing WindowID string
        NA_SKETCHUP_INSTANCE_KEY = "SketchUpInstanceName".freeze        # Key for SketchUp instance name
        NA_SKETCHUP_DEF_KEY      = "SketchUpDefinitionName".freeze      # Key for SketchUp definition name
        NA_COMPONENT_NAME_KEY    = "ComponentName".freeze               # Key for the user-authored name tail (never parsed downstream)
        # ---------------------------------------------------------------

        # CONSTANT | Fixed Definition-Name Head
        # ------------------------------------------------------------
        # `AWN019` + this = the machine-read half of every window name.
        # TrueVision / ValeVision match on it, so its value is frozen.
        # ------------------------------------------------------------
        NA_DEFINITION_NAME_SUFFIX = "__Window__".freeze
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Validation Functions
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Validate Window Data Structure
        # ------------------------------------------------------------
        def self.na_valid_structure?(hash)
            hash.is_a?(Hash) &&
            hash.key?(NA_METADATA_KEY) &&
            hash.key?(NA_CONFIG_KEY)
        end
        private_class_method :na_valid_structure?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Validate Window ID Format (AWNxxx)
        # ------------------------------------------------------------
        def self.na_valid_window_id?(id)
            id.is_a?(String) && id.match?(/^AWN\d{3}$/)
        end
        private_class_method :na_valid_window_id?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Find Component Definition by Window ID
        # ------------------------------------------------------------
        def self.na_find_component_definition_by_window_id(window_id)
            model = Sketchup.active_model
            return nil unless model

            DebugTools.na_debug_serializer("Searching for definition with window ID: #{window_id}")
            
            # Priority 1: Find an instance with this WindowID and use its definition
            all_instances_with_id = []
            
            # Search in top-level entities
            model.entities.grep(Sketchup::ComponentInstance).each do |instance|
                stored_id = instance.get_attribute(NA_WINDOW_INFO_DICT, NA_WINDOW_ID_KEY)
                if stored_id == window_id
                    DebugTools.na_debug_serializer("Found instance with WindowID '#{window_id}': '#{instance.name}' (EntityID: #{instance.entityID})")
                    all_instances_with_id << instance
                end
            end
            
            # Also search in nested entities (component instances inside other component definitions)
            model.definitions.each do |definition_container|
                definition_container.entities.grep(Sketchup::ComponentInstance).each do |instance|
                    next if all_instances_with_id.any? { |i| i.entityID == instance.entityID }
                    stored_id = instance.get_attribute(NA_WINDOW_INFO_DICT, NA_WINDOW_ID_KEY)
                    if stored_id == window_id
                        DebugTools.na_debug_serializer("Found nested instance with WindowID '#{window_id}': '#{instance.name}'")
                        all_instances_with_id << instance
                    end
                end
            end
            
            if !all_instances_with_id.empty?
                instance = all_instances_with_id.first
                definition = instance.definition
                DebugTools.na_debug_serializer("Found definition '#{definition.name}' via component instance")
                return definition
            end

            DebugTools.na_debug_serializer("No component instance found with WindowID '#{window_id}'")
            
            # Priority 2 (Fallback): Try to find by component definition name pattern
            model.definitions.each do |definition_item|
                if definition_item.name.start_with?(na_window_definition_prefix(window_id))
                    DebugTools.na_debug_serializer("Found definition by name pattern: '#{definition_item.name}'")
                    return definition_item
                end
            end
            
            DebugTools.na_debug_serializer("No definition found for window ID: #{window_id}")
            return nil
        end
        private_class_method :na_find_component_definition_by_window_id
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Main Public Functions - Save Data
# -----------------------------------------------------------------------------

        # FUNCTION | Save Window Data to Component Dictionary
        # ------------------------------------------------------------
        # @param window_id [String] The window ID (e.g., "AWN001")
        # @param data_hash [Hash] Hash containing windowMetadata, windowComponents, windowConfiguration
        # @return [Boolean] True if save successful, false otherwise
        def self.na_save_window_data(window_id, data_hash)
            return false unless na_valid_window_id?(window_id)
            return false unless na_valid_structure?(data_hash)

            model = Sketchup.active_model
            return false unless model
            
            # Find the component definition associated with this window ID
            definition = na_find_component_definition_by_window_id(window_id)
            unless definition
                DebugTools.na_debug_serializer("Could not find component definition for window ID: #{window_id}")
                return false
            end

            # Get or create the dictionary for this specific window on the component definition
            dict_name = "#{NA_DICTIONARY_PREFIX}#{window_id}"
            dict = definition.attribute_dictionary(dict_name, true) # true ensures creation if not exists
            
            unless dict
                DebugTools.na_debug_serializer("Failed to create dictionary '#{dict_name}' on component definition")
                return false
            end

            DebugTools.na_debug_serializer("Saving window data for #{window_id}")

            begin
                # Save each key separately to the component definition's dictionary
                dict[NA_METADATA_KEY]   = JSON.generate(data_hash[NA_METADATA_KEY] || [])
                dict[NA_COMPONENTS_KEY] = JSON.generate(data_hash[NA_COMPONENTS_KEY] || [])
                dict[NA_CONFIG_KEY]     = JSON.generate(data_hash[NA_CONFIG_KEY] || {})
                
                # Verify save
                if dict[NA_METADATA_KEY] && dict[NA_CONFIG_KEY]
                    DebugTools.na_debug_success("Successfully saved data for window #{window_id}")
                    return true
                else
                    DebugTools.na_debug_error("Verification failed after save for #{window_id}")
                    return false
                end
                
            rescue => e
                DebugTools.na_debug_error("Error saving data for window #{window_id}", e)
                return false
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Main Public Functions - Load Data
# -----------------------------------------------------------------------------

        # FUNCTION | Load Window Data from Component Dictionary
        # ------------------------------------------------------------
        # @param window_id [String] The window ID (e.g., "AWN001")
        # @return [Hash, nil] Hash with windowMetadata, windowComponents, windowConfiguration or nil
        def self.na_load_window_data(window_id)
            return nil unless na_valid_window_id?(window_id)

            model = Sketchup.active_model
            return nil unless model
            
            # Find the component definition associated with this window ID
            definition = na_find_component_definition_by_window_id(window_id)
            unless definition
                DebugTools.na_debug_serializer("Could not find component definition for window ID: #{window_id}")
                return nil
            end

            # Get the dictionary for this specific window
            dict_name = "#{NA_DICTIONARY_PREFIX}#{window_id}"
            dict = definition.attribute_dictionary(dict_name)
            
            if dict.nil?
                DebugTools.na_debug_serializer("Dictionary '#{dict_name}' not found on component definition")
                return nil
            end

            DebugTools.na_debug_serializer("Loading data for window #{window_id}")

            begin
                # Load and parse each key from the component definition's dictionary
                metadata_json   = dict[NA_METADATA_KEY]
                components_json = dict[NA_COMPONENTS_KEY]
                config_json     = dict[NA_CONFIG_KEY]
                
                if !metadata_json || !config_json
                    DebugTools.na_debug_serializer("Missing required data keys for window #{window_id}")
                    return nil
                end
                
                metadata   = JSON.parse(metadata_json)
                components = components_json ? JSON.parse(components_json) : []
                config     = JSON.parse(config_json)
                
                loaded_hash = {
                    NA_METADATA_KEY   => metadata,
                    NA_COMPONENTS_KEY => components,
                    NA_CONFIG_KEY     => config
                }
                
                DebugTools.na_debug_success("Loaded data for window #{window_id}")
                return loaded_hash
                
            rescue JSON::ParserError => e
                DebugTools.na_debug_error("JSON Parse Error loading window #{window_id}", e)
                return nil
            rescue => e
                DebugTools.na_debug_error("Error loading window data for #{window_id}", e)
                return nil
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Load Window Data Directly from Component Instance
        # ------------------------------------------------------------
        # Bypasses the model-wide search in na_find_component_definition_by_window_id
        # by reading the dictionary directly from the instance's definition.
        # Use this when the caller already has the correct ComponentInstance
        # (e.g., from the SelectionObserver).
        #
        # @param instance [Sketchup::ComponentInstance] The window component instance
        # @param window_id [String] The window ID (e.g., "AWN001")
        # @return [Hash, nil] Hash with windowMetadata, windowComponents, windowConfiguration or nil
        def self.na_load_window_data_from_instance(instance, window_id)
            return nil unless instance.is_a?(Sketchup::ComponentInstance)
            return nil unless na_valid_window_id?(window_id)

            definition = instance.definition
            dict_name = "#{NA_DICTIONARY_PREFIX}#{window_id}"
            dict = definition.attribute_dictionary(dict_name)

            if dict.nil?
                DebugTools.na_debug_serializer("Dictionary '#{dict_name}' not found on definition '#{definition.name}'")
                return nil
            end

            DebugTools.na_debug_serializer("Loading data for window #{window_id} from instance definition '#{definition.name}'")

            begin
                metadata_json   = dict[NA_METADATA_KEY]
                components_json = dict[NA_COMPONENTS_KEY]
                config_json     = dict[NA_CONFIG_KEY]

                if !metadata_json || !config_json
                    DebugTools.na_debug_serializer("Missing required data keys for window #{window_id} on definition '#{definition.name}'")
                    return nil
                end

                metadata   = JSON.parse(metadata_json)
                components = components_json ? JSON.parse(components_json) : []
                config     = JSON.parse(config_json)

                loaded_hash = {
                    NA_METADATA_KEY   => metadata,
                    NA_COMPONENTS_KEY => components,
                    NA_CONFIG_KEY     => config
                }

                DebugTools.na_debug_success("Loaded data for window #{window_id} from instance")
                return loaded_hash

            rescue JSON::ParserError => e
                DebugTools.na_debug_error("JSON Parse Error loading window #{window_id} from instance", e)
                return nil
            rescue => e
                DebugTools.na_debug_error("Error loading window data for #{window_id} from instance", e)
                return nil
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Main Public Functions - Delete and List
# -----------------------------------------------------------------------------

        # FUNCTION | Delete Window Data from Component
        # ------------------------------------------------------------
        def self.na_delete_window_data(window_id)
            return false unless na_valid_window_id?(window_id)

            model = Sketchup.active_model
            return false unless model
            
            definition = na_find_component_definition_by_window_id(window_id)
            return false unless definition

            dict_name = "#{NA_DICTIONARY_PREFIX}#{window_id}"
            
            begin
                definition.attribute_dictionaries.delete(dict_name)
                DebugTools.na_debug_serializer("Deleted dictionary for window #{window_id}")
                return true
            rescue => e
                DebugTools.na_debug_error("Error deleting window data", e)
                return false
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | List All Window IDs in Model
        # ------------------------------------------------------------
        def self.na_list_all_windows
            model = Sketchup.active_model
            return [] unless model

            window_ids = []
            
            # Search through all component instances for WindowID values
            model.entities.grep(Sketchup::ComponentInstance).each do |instance|
                window_id = instance.get_attribute(NA_WINDOW_INFO_DICT, NA_WINDOW_ID_KEY)
                if window_id && na_valid_window_id?(window_id)
                    window_ids << window_id
                end
            end
            
            # Also search nested instances
            model.definitions.each do |definition|
                definition.entities.grep(Sketchup::ComponentInstance).each do |instance|
                    window_id = instance.get_attribute(NA_WINDOW_INFO_DICT, NA_WINDOW_ID_KEY)
                    if window_id && na_valid_window_id?(window_id)
                        window_ids << window_id
                    end
                end
            end
            
            return window_ids.uniq
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Window ID Management
# -----------------------------------------------------------------------------

        # FUNCTION | Generate Next Available Window ID
        # ------------------------------------------------------------
        def self.na_generate_next_window_id
            all_ids = na_list_all_windows
            
            max_num = 0
            all_ids.each do |id|
                m = id.match(/^AWN(\d{3})$/)
                if m
                    num = m[1].to_i
                    max_num = num if num > max_num
                end
            end
            
            new_id = "AWN#{format('%03d', max_num + 1)}"
            DebugTools.na_debug_serializer("Generated new window ID: #{new_id}")
            return new_id
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build the Fixed Head of a Window's Component Name
        # ------------------------------------------------------------
        # `AWN019__Window__`. Everything downstream (TrueVision,
        # ValeVision, the definition-name fallback lookup above) matches
        # on this head, so it is composed in exactly one place.
        def self.na_window_definition_prefix(window_id)
            "#{window_id}#{NA_DEFINITION_NAME_SUFFIX}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read the User-Authored Name Tail Off an Instance
        # ------------------------------------------------------------
        # Returns "" for an unnamed window. Read from the live component
        # name rather than the dictionary so a hand-rename in the
        # Outliner is reported honestly back to the dialog.
        def self.na_get_component_name_from_instance(instance)
            window_id = na_get_window_id_from_instance(instance)
            return "" unless window_id
            ComponentNameSuffix.na_current_suffix(instance, na_window_definition_prefix(window_id))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Set Window ID on Component Instance
        # ------------------------------------------------------------
        # Names the component `<WindowID>__Window__<ComponentName>`. The
        # head is fixed; only the optional tail comes from the user.
        #
        # @param instance       [Sketchup::ComponentInstance] The component instance
        # @param window_id      [String] The window ID (e.g., "AWN001")
        # @param component_name [String, Symbol] User-authored name tail
        #     (e.g. "GroundFloor__BayWindow"). Defaults to NA_KEEP, which
        #     preserves whatever tail the component already carries - every
        #     rebuild path relies on that so an Update never un-names a
        #     component the user has already labelled.
        def self.na_set_window_id_on_instance(instance, window_id, component_name = ComponentNameSuffix::NA_KEEP)
            return false unless instance.is_a?(Sketchup::ComponentInstance)
            return false unless na_valid_window_id?(window_id)

            base_prefix = na_window_definition_prefix(window_id)
            full_name   = ComponentNameSuffix.na_apply(instance, base_prefix, component_name)
            return false unless full_name

            # Store window ID and names in attribute dictionary
            instance.set_attribute(NA_WINDOW_INFO_DICT, NA_WINDOW_ID_KEY, window_id)
            instance.set_attribute(NA_WINDOW_INFO_DICT, NA_SKETCHUP_INSTANCE_KEY, instance.name)
            instance.set_attribute(NA_WINDOW_INFO_DICT, NA_SKETCHUP_DEF_KEY, instance.definition.name)
            instance.set_attribute(NA_WINDOW_INFO_DICT, NA_COMPONENT_NAME_KEY,
                                   ComponentNameSuffix.na_extract(full_name, base_prefix))

            DebugTools.na_debug_serializer("Set WindowID '#{window_id}' on instance '#{instance.name}'")
            return true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Window ID from Component Instance
        # ------------------------------------------------------------
        def self.na_get_window_id_from_instance(instance)
            return nil unless instance.is_a?(Sketchup::ComponentInstance)
            
            window_id = instance.get_attribute(NA_WINDOW_INFO_DICT, NA_WINDOW_ID_KEY)
            
            if window_id && na_valid_window_id?(window_id)
                return window_id
            else
                return nil
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Utility Functions
# -----------------------------------------------------------------------------

        # FUNCTION | Check if Component has Window Data
        # ------------------------------------------------------------
        def self.na_has_window_data?(instance)
            window_id = na_get_window_id_from_instance(instance)
            return false unless window_id
            
            definition = instance.definition
            dict_name = "#{NA_DICTIONARY_PREFIX}#{window_id}"
            dict = definition.attribute_dictionary(dict_name)
            
            return dict != nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Export Window Data as JSON String (for debugging)
        # ------------------------------------------------------------
        def self.na_export_window_data_json(window_id)
            data = na_load_window_data(window_id)
            return nil unless data
            
            return JSON.pretty_generate(data)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Import Window Data from JSON String
        # ------------------------------------------------------------
        def self.na_import_window_data_json(window_id, json_string)
            begin
                data = JSON.parse(json_string)
                return na_save_window_data(window_id, data)
            rescue JSON::ParserError => e
                DebugTools.na_debug_error("Invalid JSON for import", e)
                return false
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__DataSerializer
end # module Na__WindowSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
