# =============================================================================
# ValeDesignSuite - Framework Tools SketchUp Logic
# =============================================================================
#
# NAMESPACE : ValeDesignSuite::Tools
# MODULE    : FrameworkToolsSketchUpLogic
# AUTHOR    : Adam Noble - Vale Garden Houses
# TYPE      : SketchUp 2026 Backend Logic Script
# PURPOSE   : Provides methods for creating and interacting with framework
#             assemblies within the SketchUp model. This script acts as a
#             bridge between UI interactions (from
#             ValeDesignSuite_Core_MainUserInterface.rb) and the underlying
#             data management for framework assemblies.
# CREATED   : 22-May-2025
#
# =============================================================================
# IMPORTANT NOTES - DYNAMIC CONFIGURATION SYSTEM
# =============================================================================
# 
# ⚠️  CRITICAL: This script uses DYNAMIC CONFIGURATION loading from external JSON files.
# 
# DEFAULT CONFIGURATION SOURCES:
# - Assembly defaults: "ValeDesignSuite_Config_FrameworkConfigurator_DefaultAssemblyConfig.json"
# - Node defaults: "ValeDesignSuite_Config_FrameworkConfigurator_DefaultNodeConfig.json"  
# - Panel defaults: "ValeDesignSuite_Config_FrameworkConfigurator_DefaultPanelConfig.json"
# - All JSON files are located in the same directory as this script
# 
# CONFIGURATION BEHAVIOR:
# - Framework assembly creation loads defaults from assembly config JSON
# - Node creation within assemblies loads defaults from node config JSON
# - Panel creation within assemblies loads defaults from panel config JSON
# - If any JSON file is missing, the script falls back to hardcoded defaults
# 
# CUSTOMIZATION:
# - To modify default assembly/node/panel settings, edit the respective JSON files
# - No code changes are required for basic configuration adjustments
# - JSON files support dimensions, materials, constraints, and UI settings
# 
# FRAMEWORK CREATION PROCESS:
# - New assemblies use assembly JSON for container properties
# - Nodes within assemblies use node JSON for structural properties
# - Panels within assemblies use panel JSON for infill properties
# - All configurations are merged and validated during creation
# 
# FALLBACK SAFETY:
# - If JSON parsing fails, the script uses safe fallback values
# - Error messages are logged through the debug system
# - The system remains functional even with corrupted configuration files
# 
# =============================================================================
#
# DESCRIPTION:
# - This module handles SketchUp-side logic for the Framework Configurator tool.
# - For specific framework assemblies (typically represented as SketchUp
#   Components), all data persistence (saving and loading configuration data
#   like metadata, nodes, and panel lines) is delegated to the
#   `ValeDesignSuite::DataUtils::FrameworkDataSerializer` module.
# - This script manages the creation of new framework component instances,
#   linking them to their serialized data via a unique assembly ID stored as
#   a component attribute.
# - It also provides methods to load data for a selected framework component
#   by using its stored assembly ID to retrieve data via the serializer.
# - Some methods (`save_framework_data`, `load_framework_data`) handle a
#   separate, global/default framework configuration that is stored directly
#   on the model using a different dictionary and is NOT processed by the
#   `FrameworkDataSerializer`. This is for general tool state or non-component-
#   specific configurations.
#
# IMPORTANT FILE LINKING DEPENDENCIES:
# Uses -  `ValeDesignSuite::DataUtils::FrameworkDataSerializer` (from
#           `ValeDesignSuite_Tools_FrameworkToolsDataSerializer.rb`) for data
#           persistence of individual framework assemblies.
# Called by - `ValeDesignSuite_Core_MainUserInterface.rb` for UI callbacks.
# Interacts with - `ValeDesignSuite_Tools_FrameworkConfigurator_Logic.js` via data
#                  passed through the UI.
#
# -----------------------------------------------------------------------------
# SYSTEM BREAKDOWN
# -----------------------------------------------------------------------------
# - The configurator is a two-part system:
# - A front-end HTML/JS interface that is powered by  `ValeDesignSuite_Tools_FrameworkConfigurator_Logic.js`
# - A back-end Ruby script that handles the saving and loading of persistence of data to and from the SketchUp model.
#
# DATA HANDLING FOR ASSEMBLIES (via FrameworkDataSerializer):
# - Each unique framework assembly (a SketchUp ComponentInstance) is assigned a unique
#   Assembly ID (e.g., "VFW001").
# - This Assembly ID is stored as an attribute on the ComponentInstance itself.
# - All other data for that assembly (metadata, nodes, panel lines) is
#   consolidated into JSON data by `FrameworkDataSerializer` and
#   stored on the component definition as a dictionary.
# - This script calls the serializer to perform these save and load operations.
#
# DATA HANDLING FOR GLOBAL/DEFAULT CONFIGURATION (direct, not serializer):
# - The UI Configurator can also work with a general, non-assembly-specific JSON.
# - This data is stored directly in the model's AttributeDictionary using
#   `ValeDesignSuite_FrameworkConfiguratorToolDataDictionary` by the
#   `save_framework_data` and `load_framework_data` methods in this file.
#   This data is NOT intended to be managed by the `FrameworkDataSerializer`.
# 
# FRAMEWORK ASSEMBLIES & COMPONENT DICTIONARY
# - Each time a new framework Assembly is created (as a Component), it's linked
#   to its data via the Assembly ID and the `FrameworkDataSerializer`.
# - When a user selects a component representing a framework assembly and triggers
#   an "edit" action in the UI, this script will use the component's Assembly ID
#   to load the relevant data via the serializer.
#
# DEVELOPMENT MODE - JSON VIEWER BUTTON
# - A View Json Button is provided to view the JSON data that will be stringified and saved to the dictionary.
#  - Eventually I will add a "Dev Mode User Config Item" to allow the user to toggle the display of the JSON data in the UI.
#  - For development purposes the Dev Buttons is hardcoded to the UI until full release is ready.
#
# Json Data Structure (Managed by FrameworkDataSerializer for assemblies)
# - The JSON data structure expected by the serializer is:
#  - {
#    "frameworkMetadata": [
#      {
#        "FrameworkUniqueId"  :   VFW001,              #<-- Note the values change from VFW001 Up To VFW999 
#        "FrameworkName"      :  "Framework-01",       #<-- User-defined name from the UI. This is used as the Sketchup::ComponentInstance.name.
#                                                      #<-- The Sketchup::ComponentDefinition.name is a constructed string (e.g., FrameworkAssembly_Framework-01_VFW001).
#                                                      #<-- Both instance and definition names are also stored in the ValeDesignSuite_FrameworkAssemblyInfo dictionary on the instance.
#        "FrameworkNotes"     :  "STRING",             #<-- User Defined Notes for special cases
#        "FrameworkLength"    :  "INTEGER",            #<-- This is the length of the framework in mm
#        "FrameworkWidth"     :  "INTEGER",            #<-- This is the width of the framework in mm
#        "FrameworkHeight"    :  "INTEGER",            #<-- This is the height of the framework in mm
#      },
#    "frameworkNodes": [
#      {
#        "NodeUniqueId"     :     ND001,              #<-- Note the values change from ND001 Up To ND999 
#        "NodeName"         : "Framework-Node-01",    #<-- Note: Can be renamed by the user to something more meaningful
#        "NodeType"         :    STRING,              #<-- Types: "Corner Column", "Dwarf Wall Column", "Door Column", "End Panel", "Scribe Panel", "Other Types To Follow"
#        "NodeStyle"        :    STRING,              #<-- Style: "290mm Column", "Other Types To Follow"
#        "NodeNotes"        :    STRING,              #<-- User Defined Notes for special cases
#        "NodePosX"         :   INTEGER,
#        "NodePosY"         :   INTEGER,
#        "NodePosZ"         :   INTEGER,
#        "NodeSizeX"        :   INTEGER,
#        "NodeSizeY"        :   INTEGER,
#        "NodeSizeZ"        :   INTEGER,
#        "NodeHeadHeight"   :   INTEGER,
#        "NodeUsCillHeight" :   INTEGER,
#        "NodeRotationX"    :   INTEGER,
#        "NodeRotationY"    :   INTEGER,
#        "NodeRotationZ"    :   INTEGER,
#        "NodeRotationW"    :   INTEGER,
#      },
#      {
#        "nodeUniqueId"   :     ND002,              #<-- Continues to suit the Graphical Representation or the Dictionary data when loaded into the UI
#      },
#    "frameworkPanelLines": [
#      {
#        "PanelUniqueId"     :     PL001,            #<-- Note the values change from PL001 Up To PL999 
#        "PanelName"         : "Framework-Panel-01", #<-- Note: Can be renamed by the user to something more meaningful
#        "PanelType"         :    STRING,            #<-- Types: "Window Panel", "Door Panel" "Blanking Panel"  "Other Types To Follow"
#        "PanelStyle"        :    STRING,            #<-- Style: "290mm Column", "Other Types To Follow"
#        "PanelDivisionsX"   :    INTEGER,           #<-- Defines how many glazed sections between glazed bars that the the panel is divided into horizontally, i.e window panes
#        "PanelDivisionsY"   :    INTEGER,           #<-- Defines how many glazed sections between glazed bars that the the panel is divided into vertically, i.e window panes
#        "PanelNotes"        :    STRING,            #<-- User Defined Notes for special cases
#        "PanelPosX"         :   INTEGER,
#        "PanelPosY"         :   INTEGER,
#        "PanelPosZ"         :   INTEGER,
#        "PanelSizeX"        :   INTEGER,
#        "PanelSizeY"        :   INTEGER,
#        "PanelSizeZ"        :   INTEGER,
#        "PanelHeadHeight"   :   INTEGER,
#        "PanelUsCillHeight" :   INTEGER,
#        "PanelRotationX"    :   INTEGER,
#        "PanelRotationY"    :   INTEGER,
#        "PanelRotationZ"    :   INTEGER,
#        "PanelRotationW"    :   INTEGER,
#      },
#      {
#        "panelUniqueId"   :     PL002,              #<-- Continues to suit the Graphical Representation or the Dictionary data when loaded into the UI
#      },
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 22-May-2025 - Version 0.1.0 - INITIAL IMPLEMENTATION
# - Created save_framework_data method to store JSON data in model attributes.
# - Created load_framework_data method to retrieve JSON data from model attributes.
# - Added basic error handling and console logging for these operations.
#
# 23-May-2025 - Version 0.1.1 - DATA STRUCTURE REFINEMENT (Anticipated)
# - Modified save_framework_data and load_framework_data to handle a hash 
#   containing both 'nodes' and 'lines' arrays, instead of just a single array.
#   This aligns with the data structure used by the JavaScript front-end.
#
# 24-May-2025 - Version 0.2.0 - INTEGRATE FRAMEWORK DATA SERIALIZER
# - Refactored `create_new_framework_assembly` and `load_framework_data_from_component`
#   to use `ValeDesignSuite::DataUtils::FrameworkDataSerializer` for data persistence.
# - Added `ASSEMBLY_INFO_DICT_NAME` and `ASSEMBLY_ID_KEY` constants for linking
#   component instances to their serialized data.
# - Clarified in comments the distinction between assembly-specific data (via serializer)
#   and global/default data (via direct model dictionary access in this file).
# - Added `require_relative` for the serializer.
#
# 26-May-2025 - Version 0.3.0 - COMPONENT DEFINITION STORAGE
# - Updated to use component definition dictionaries instead of model-level dictionaries
#   for framework assembly data storage, as per the design specifications.
# - Modified create_new_framework_assembly to properly link component instances and 
#   definitions with the appropriate dictionary structure.
# =============================================================================

require 'sketchup.rb'
require 'json'            # <-- This is for serialising Data to / from the SketchUp Components Dictionaries

# Require the FrameworkDataSerializer
# All files are now in the same directory (Tools_FrameworkTools)
require_relative 'ValeDesignSuite_Tools_FrameworkToolsDataSerializer.rb'
require_relative 'ValeDesignSuite_Tools_FrameworkNodeConfigurator'                  # <-- Node configurator
require_relative 'ValeDesignSuite_Tools_FrameworkIntegratedNodeConfigurator'        # <-- Integrated node configurator
require_relative 'ValeDesignSuite_Tools_FrameworkIntegratedWindowPanelConfigurator' # <-- Integrated window panel configurator
require_relative 'ValeDesignSuite_Tools_FrameworkCoordinationManager'               # <-- Coordination manager
require_relative 'ValeDesignSuite_Tools_FrameworkDebugTools'                        # <-- Debug tools

module ValeDesignSuite
  module Tools
    module FrameworkToolsSketchUpLogic

      # DEBUG TOOLS REFERENCE
      # ------------------------------------------------------------
      DebugTools = ValeDesignSuite::Tools::FrameworkDebugTools

      # #region ===============================================================
      # - - - - - - - - - - CONSTANTS & CONFIGURATION - - - - - - - - - - -
      # =======================================================================
      # DICTIONARY IDENTIFIERS for GLOBAL/DEFAULT framework data (NOT used by Serializer)
      # ---------------------------------------------------------------------------------
      GLOBAL_CONFIG_DICTIONARY_NAME =  "ValeDesignSuite_FrameworkConfiguratorToolDataDictionary"   # <-- Dictionary Name for global/default data
      GLOBAL_DATA_KEY_NODES         =  "FrameworkNodes"                                            # <-- Key for nodes array in global data
      GLOBAL_DATA_KEY_LINES         =  "FrameworkLines"                                            # <-- Key for lines array in global data
      GLOBAL_DATA_KEY_METADATA      =  "FrameworkMetadata"                                         # <-- Key for metadata array in global data
      
      # CONSTANTS for linking Component Instances to their Assembly ID (used WITH Serializer)
      # ---------------------------------------------------------------------------------
      ASSEMBLY_INFO_DICT_NAME       =  "ValeDesignSuite_FrameworkAssemblyInfo".freeze  # <-- Dictionary on ComponentInstance
      ASSEMBLY_ID_KEY               =  "AssemblyID".freeze                             # <-- Key for storing AssemblyID string
      SKETCHUP_INSTANCE_NAME_KEY    =  "SketchUpInstanceName".freeze                   # <-- Key for storing SketchUp Instance Name
      SKETCHUP_DEFINITION_NAME_KEY  =  "SketchUpDefinitionName".freeze                 # <-- Key for storing SketchUp Definition Name

      # MODULE CONSTANTS | Unit Conversion and Dictionary Keys
      # ------------------------------------------------------------
      MM_TO_INCH                    =   1.0 / 25.4                                    # <-- Millimeter to inch conversion factor
      FRAMEWORK_DICT_NAME           =   "FrameworkConfigurator_Config"                # <-- Dictionary name for storing framework configuration
      FRAMEWORK_DEPTH_MM            =   94                                            # <-- Standard framework depth in millimeters
      STANDARD_HEIGHT_MM            =   2000                                          # <-- Standard framework height in millimeters

      # MODULE CONFIG DATA | Node Type Configuration JSON
      # ------------------------------------------------------------
      NODE_TYPES_CONFIG_JSON = <<~JSON_STRING
      {
          "nodeTypeMetadata": [
              {
                  "ConfigVersion"                     :  "1.0.0",
                  "ConfigAuthor"                      :  "Adam Noble - Noble Architecture",
                  "ConfigDescription"                 :  "Vale Design Suite Framework Node Type Definitions",
                  "ConfigNotes"                       :  "Standard node types for Vale framework system with 94mm depth",
                  "ConfigCreatedDate"                 :  "30-May-2025",
                  "ConfigLastModified"                :  "30-May-2025"
              }
          ],
          "nodeTypes": [
              {
                  "NodeTypeId"                        :  "Column_CornerColumn",
                  "NodeTypeName"                      :  "Corner Column",
                  "NodeTypeDescription"               :  "Standard corner column for framework assemblies",
                  "NodeTypeCategory"                  :  "Structural",
                  "NodeTypeMaterial"                  :  "natural-wood",
                  "DefaultDimensions"                 :  { 
                      "Width_mm"                      :  290, 
                      "Depth_mm"                      :  94, 
                      "Height_mm"                     :  2000 
                  },
                  "ConstraintDimensions"              :  { 
                      "MinWidth_mm"                   :  290, 
                      "MaxWidth_mm"                   :  290,
                      "MinDepth_mm"                   :  94, 
                      "MaxDepth_mm"                   :  94,
                      "MinHeight_mm"                  :  1500, 
                      "MaxHeight_mm"                  :  3000 
                  },
                  "DisplayProperties"                 :  {
                      "UIDisplayName"                 :  "Corner Column",
                      "UIShortName"                   :  "Corner",
                      "UIColor"                       :  "#D2B48C",
                      "UIIcon"                        :  "corner-column"
                  }
              },
              {
                  "NodeTypeId"                        :  "Column_290mm",
                  "NodeTypeName"                      :  "290mm Column",
                  "NodeTypeDescription"               :  "Standard 290mm wide column for framework assemblies",
                  "NodeTypeCategory"                  :  "Structural",
                  "NodeTypeMaterial"                  :  "natural-wood",
                  "DefaultDimensions"                 :  { 
                      "Width_mm"                      :  290, 
                      "Depth_mm"                      :  94, 
                      "Height_mm"                     :  2000 
                  },
                  "ConstraintDimensions"              :  { 
                      "MinWidth_mm"                   :  290, 
                      "MaxWidth_mm"                   :  290,
                      "MinDepth_mm"                   :  94, 
                      "MaxDepth_mm"                   :  94,
                      "MinHeight_mm"                  :  1500, 
                      "MaxHeight_mm"                  :  3000 
                  },
                  "DisplayProperties"                 :  {
                      "UIDisplayName"                 :  "290mm Column",
                      "UIShortName"                   :  "290mm",
                      "UIColor"                       :  "#D2B48C",
                      "UIIcon"                        :  "standard-column"
                  }
              },
              {
                  "NodeTypeId"                        :  "Column_390mm",
                  "NodeTypeName"                      :  "390mm Column",
                  "NodeTypeDescription"               :  "Wide 390mm column for framework assemblies",
                  "NodeTypeCategory"                  :  "Structural",
                  "NodeTypeMaterial"                  :  "natural-wood",
                  "DefaultDimensions"                 :  { 
                      "Width_mm"                      :  390, 
                      "Depth_mm"                      :  94, 
                      "Height_mm"                     :  2000 
                  },
                  "ConstraintDimensions"              :  { 
                      "MinWidth_mm"                   :  390, 
                      "MaxWidth_mm"                   :  390,
                      "MinDepth_mm"                   :  94, 
                      "MaxDepth_mm"                   :  94,
                      "MinHeight_mm"                  :  1500, 
                      "MaxHeight_mm"                  :  3000 
                  },
                  "DisplayProperties"                 :  {
                      "UIDisplayName"                 :  "390mm Column",
                      "UIShortName"                   :  "390mm",
                      "UIColor"                       :  "#CD853F",
                      "UIIcon"                        :  "wide-column"
                  }
              },
              {
                  "NodeTypeId"                        :  "Column_100mm",
                  "NodeTypeName"                      :  "100mm Column",
                  "NodeTypeDescription"               :  "Narrow 100mm column for framework assemblies",
                  "NodeTypeCategory"                  :  "Structural",
                  "NodeTypeMaterial"                  :  "natural-wood",
                  "DefaultDimensions"                 :  { 
                      "Width_mm"                      :  100, 
                      "Depth_mm"                      :  94, 
                      "Height_mm"                     :  2000 
                  },
                  "ConstraintDimensions"              :  { 
                      "MinWidth_mm"                   :  100, 
                      "MaxWidth_mm"                   :  100,
                      "MinDepth_mm"                   :  94,
                      "MaxDepth_mm"                   :  94,
                      "MinHeight_mm"                  :  1500,
                      "MaxHeight_mm"                  :  3000
                  },
                  "DisplayProperties"                 :  {
                      "UIDisplayName"                 :  "100mm Column",
                      "UIShortName"                   :  "100mm",
                      "UIColor"                       :  "#D2B48C",
                      "UIIcon"                        :  "narrow-column"
                  }
              }
          ]
      }
      JSON_STRING

      # Parse the JSON configuration for use in Ruby
      NODE_TYPES_CONFIG = JSON.parse(NODE_TYPES_CONFIG_JSON)

      # #region ===============================================================
      # - - - - - - - - - - DATA PERSISTENCE METHODS (GLOBAL/DEFAULT) - - - - -
      # =======================================================================
      # DEPRECATED: These methods are no longer used as all data must be stored on component instances
      # -----------------------------------------------------------------------------

      # SAVE FRAMEWORK DATA (GLOBAL/DEFAULT) | DEPRECATED - Do not use
      # -----------------------------------------------------------------------------
      # @return [Boolean] Always returns false to indicate error/deprecation
      def self.save_framework_data(framework_data_hash)
        DebugTools.debug_warn("ERROR - Global save is deprecated and disabled.")
        DebugTools.debug_warn("All data must be stored on component instances for portability.")
        DebugTools.debug_warn("Please create a component using create_new_framework_assembly instead.")
        return false
      end

      # LOAD FRAMEWORK DATA (GLOBAL/DEFAULT) | DEPRECATED - Do not use
      # -----------------------------------------------------------------------------
      # @return [nil] Always returns nil to indicate error/deprecation
      def self.load_framework_data
        DebugTools.debug_warn("ERROR - Global load is deprecated and disabled.")
        DebugTools.debug_warn("All data must be loaded from component instances for portability.")
        DebugTools.debug_warn("Please select a component and use load_framework_data_from_component instead.")
        return nil
      end
      # #endregion

      # #region ===============================================================
      # - - - - - - - - - - ASSEMBLY DATA METHODS (USES SERIALIZER) - - - - - -
      # =======================================================================
      # These methods handle data for specific framework assemblies (SketchUp Components)
      # and utilize ValeDesignSuite::DataUtils::FrameworkDataSerializer for persistence.
      # --------------------------------------------------------------------------------

      # LOAD FRAMEWORK DATA FROM COMPONENT | Loads framework data for a specific component instance using the Serializer.
      # -------------------------------------------------------------------------------------------
      # @param entity_id [Integer] The entityID of the component instance.
      # @return [Hash, nil] A hash with "frameworkMetadata", "frameworkNodes", and "frameworkPanelLines" arrays 
      #                      (parsed by the serializer) if found and valid. Returns nil if the component is not found, 
      #                      not a component instance, no AssemblyID attribute, or if data loading fails.
      def self.load_framework_data_from_component(entity_id)
        model = Sketchup.active_model
        unless model
          DebugTools.debug_log("No active model found.")
          return nil
        end

        instance = model.entities.find { |e| e.entityID == entity_id }

        unless instance.is_a?(Sketchup::ComponentInstance)
          DebugTools.debug_log("Entity with ID #{entity_id} is not a ComponentInstance or not found.")
          return nil
        end

        assembly_id = instance.get_attribute(ASSEMBLY_INFO_DICT_NAME, ASSEMBLY_ID_KEY)
        unless assembly_id
          DebugTools.debug_log("No AssemblyID attribute found on component ID #{entity_id} ('#{instance.name}'). Cannot load data via serializer.")
          # Try falling back to old direct attribute reading for compatibility? Or just fail.
          # For now, strictly require AssemblyID for serializer.
          return nil 
        end

        DebugTools.debug_log("Attempting to load data for AssemblyID '#{assembly_id}' from component '#{instance.name}' (EntityID: #{entity_id}).")
        loaded_data_hash = ValeDesignSuite::DataUtils::FrameworkDataSerializer.load_assembly_data(assembly_id)

        if loaded_data_hash
          # CRITICAL FIX: Ensure the metadata has the correct FrameworkUniqueId
          # This prevents the "falling back to global save" issue when saving after loading
          if loaded_data_hash['frameworkMetadata'] && loaded_data_hash['frameworkMetadata'].is_a?(Array) && !loaded_data_hash['frameworkMetadata'].empty?
            if loaded_data_hash['frameworkMetadata'][0]['FrameworkUniqueId'] != assembly_id
              DebugTools.debug_log("Fixing mismatched FrameworkUniqueId in metadata. " +
                   "Was: #{loaded_data_hash['frameworkMetadata'][0]['FrameworkUniqueId']}, Should be: #{assembly_id}")
              loaded_data_hash['frameworkMetadata'][0]['FrameworkUniqueId'] = assembly_id
            end
          end

          # Retrieve and validate SketchUp names
          stored_instance_name = instance.get_attribute(ASSEMBLY_INFO_DICT_NAME, SKETCHUP_INSTANCE_NAME_KEY)
          stored_definition_name = instance.get_attribute(ASSEMBLY_INFO_DICT_NAME, SKETCHUP_DEFINITION_NAME_KEY)

          current_instance_name = instance.name
          current_definition_name = instance.definition.name

          if stored_instance_name != current_instance_name
            DebugTools.debug_log("Instance name mismatch. Stored: '#{stored_instance_name}', Current: '#{current_instance_name}'. Updating stored name.")
            instance.set_attribute(ASSEMBLY_INFO_DICT_NAME, SKETCHUP_INSTANCE_NAME_KEY, current_instance_name)
            stored_instance_name = current_instance_name
          end

          if stored_definition_name != current_definition_name
            DebugTools.debug_log("Definition name mismatch. Stored: '#{stored_definition_name}', Current: '#{current_definition_name}'. Updating stored name.")
            instance.set_attribute(ASSEMBLY_INFO_DICT_NAME, SKETCHUP_DEFINITION_NAME_KEY, current_definition_name)
            stored_definition_name = current_definition_name
          end

          # Add names to the returned hash
          loaded_data_hash['sketchup_instance_name'] = stored_instance_name
          loaded_data_hash['sketchup_definition_name'] = stored_definition_name
          
          DebugTools.debug_log("Data successfully loaded for AssemblyID '#{assembly_id}'.")
          return loaded_data_hash
        else
          DebugTools.debug_log("Failed to load data for AssemblyID '#{assembly_id}' via serializer.")
          return nil
        end
      end

      # CREATE NEW FRAMEWORK ASSEMBLY | Creates a new component, assigns it a new AssemblyID,
      #                                and saves default framework data using the Serializer.
      # -------------------------------------------------------------------------------------------
      # @param assembly_name [String] The name for the new framework assembly component.
      # @param ui_nodes [Array, nil] Optional array of node data from the UI.
      # @param ui_panel_lines [Array, nil] Optional array of panel line data from the UI.
      # @return [Sketchup::ComponentInstance, nil] The new component instance if successful, nil otherwise.
      def self.create_new_framework_assembly(assembly_name, ui_nodes = nil, ui_panel_lines = nil)
        model = Sketchup.active_model
        unless model
          DebugTools.debug_log("No active model found.")
          return nil
        end
        if assembly_name.nil? || assembly_name.strip.empty?
          DebugTools.debug_log("Assembly name cannot be empty.")
          return nil
        end

        # Generate a new unique VFWXXX Assembly ID
        all_ids = ValeDesignSuite::DataUtils::FrameworkDataSerializer.list_all_assemblies
        DebugTools.debug_log("Existing assembly IDs: #{all_ids.join(', ')}")
        
        max_num = 0
        all_ids.each do |id|
          if id.match?(/^VFW(\d{3})$/) # Ensure regex is correct for Ruby
            num = $1.to_i
            max_num = num if num > max_num
          end
        end
        new_assembly_numeric_id = max_num + 1
        # Ensure new_assembly_id is not regenerated if one already exists with that number,
        # though list_all_assemblies should prevent this if it's the source of truth.
        new_assembly_id = "VFW#{format('%03d', new_assembly_numeric_id)}"
        DebugTools.debug_log("Generated new assembly ID: #{new_assembly_id}")

        # Create a new component definition and instance
        definitions = model.definitions
        # Sanitize assembly_name for use in definition name
        sane_assembly_name = assembly_name.gsub(/[^0-9A-Za-z_-]/, '_')
        comp_def_name = "FrameworkAssembly_#{sane_assembly_name}_#{new_assembly_id}"
        comp_def = definitions.add(comp_def_name)
        DebugTools.debug_log("Created component definition: #{comp_def_name}")
        
        instance = model.active_entities.add_instance(comp_def, Geom::Transformation.new)
        instance.name = assembly_name # User-facing name can be less strict
        DebugTools.debug_log("Created component instance with name: #{assembly_name}, entityID: #{instance.entityID}")

        # Load default assembly configuration from external file
        default_assembly_config = load_default_assembly_configuration
        
        # Define default placeholder data for the serializer
        default_metadata = [
          {
            "FrameworkUniqueId" => new_assembly_id, # CRITICAL: This must match the assembly_id for the serializer
            "FrameworkName" => assembly_name,
            "FrameworkNotes" => default_assembly_config["description"] || "Newly created framework assembly.",
            "FrameworkLength" => default_assembly_config["dimensions"]["length_mm"] || 0,
            "FrameworkWidth" => default_assembly_config["dimensions"]["depth_mm"] || 0,
            "FrameworkHeight" => default_assembly_config["dimensions"]["height_mm"] || 0
          }
        ]
        
        # Use UI nodes if provided, otherwise use a default single node
        if ui_nodes && ui_nodes.is_a?(Array) && !ui_nodes.empty?
          DebugTools.debug_log("Using #{ui_nodes.size} nodes from UI")
          # Map UI nodes to ensure all required properties are present
          default_nodes = ui_nodes.map do |ui_node|
            # Get node type configuration
            node_type = ui_node['NodeType'] || 'Column_CornerColumn'
            node_type_config = get_node_type_config(node_type)
            
            # Get default node configuration from external file
            default_node_config = get_default_node_configuration
            default_dims = node_type_config ? node_type_config['DefaultDimensions'] : default_node_config["dimensions"]
            
            # Convert canvas coordinates to 3D positions
            canvas_x = ui_node['x'] || 0
            canvas_y = ui_node['y'] || 0
            
            # Map UI node data to complete node structure
            {
              "NodeUniqueId" => ui_node['NodeUniqueId'] || "ND_#{Time.now.to_i}_#{rand(1000)}",
              "NodeName" => ui_node['NodeName'] || default_node_config["name"] || "Framework Node",
              "NodeType" => node_type,
              "NodeStyle" => ui_node['NodeStyle'] || "",
              "NodeNotes" => ui_node['NodeNotes'] || "Node from UI",
              "x" => canvas_x,  # Keep canvas coordinates for reference
              "y" => 0,         # Framework canvas Y is always 0 (linear framework)
              "NodePosX" => canvas_x,  # Convert canvas X to 3D X position in mm
              "NodePosY" => 0,         # Framework Y is always 0 (depth axis)
              "NodePosZ" => 0,         # Z is height axis, nodes start at ground
              "NodeSizeX" => ui_node['NodeSizeX'] || default_dims['Width_mm'] || default_dims["width_mm"] || 290,
              "NodeSizeY" => ui_node['NodeSizeY'] || default_dims['Depth_mm'] || default_dims["depth_mm"] || 94,
              "NodeSizeZ" => ui_node['NodeSizeZ'] || default_dims['Height_mm'] || default_dims["height_mm"] || 2000,
              "NodeHeadHeight" => ui_node['NodeHeadHeight'] || default_dims['Height_mm'] || default_dims["height_mm"] || 2000,
              "NodeUsCillHeight" => ui_node['NodeUsCillHeight'] || 0,
              "NodeRotationX" => ui_node['NodeRotationX'] || 0,
              "NodeRotationY" => ui_node['NodeRotationY'] || 0,
              "NodeRotationZ" => ui_node['NodeRotationZ'] || 0,
              "NodeRotationW" => ui_node['NodeRotationW'] || 1
            }
          end
          DebugTools.debug_log("Mapped #{default_nodes.size} nodes with positions")
        else
          DebugTools.debug_log("No valid UI nodes provided, using default node")
          
          # Load default configurations from external files
          default_node_config = get_default_node_configuration
          default_assembly_config = load_default_assembly_configuration
          
          default_nodes = [ # Example node, adapt as needed for JS canvas defaults
            {
              "NodeUniqueId" => "ND_#{Time.now.to_i}_#{rand(1000)}", # Should be unique within this assembly
              "NodeName" => default_node_config["name"] || "Start Node",
              "NodeType" => default_node_config["node_type"] || "Column_CornerColumn", # Ensure this matches JS expectations
              "NodeStyle" => "",
              "NodeNotes" => "Initial node for #{assembly_name}",
              "x" => 100, "y" => 0, # Framework canvas coordinates - Y is always 0
              "NodePosX" => 100, "NodePosY" => 0, "NodePosZ" => 0, # Model coordinates
              "NodeSizeX" => default_node_config["dimensions"]["width_mm"] || 290, 
              "NodeSizeY" => default_node_config["dimensions"]["depth_mm"] || 94, 
              "NodeSizeZ" => default_node_config["dimensions"]["height_mm"] || 2400, # Example dimensions
              "NodeHeadHeight" => default_node_config["dimensions"]["height_mm"] || 2400, 
              "NodeUsCillHeight" => 0,
              "NodeRotationX" => 0, "NodeRotationY" => 0, "NodeRotationZ" => 0, "NodeRotationW" => 1 # Quaternion
            }
          ]
        end
        
        # Use UI panel lines if provided, otherwise use an empty array
        if ui_panel_lines && ui_panel_lines.is_a?(Array)
          DebugTools.debug_log("Using #{ui_panel_lines.size} panel lines from UI")
          
          # Load default panel configuration from external file
          default_panel_config = get_default_panel_configuration
          
          # Map UI panel lines to ensure all required properties are present
          default_panel_lines = ui_panel_lines.map do |ui_panel|
            # Find the connected nodes to calculate panel position
            from_node = default_nodes.find { |n| n["NodeUniqueId"] == ui_panel['from_node_id'] }
            to_node = default_nodes.find { |n| n["NodeUniqueId"] == ui_panel['to_node_id'] }
            
            # Calculate panel position and dimensions
            panel_x = from_node ? from_node["NodePosX"] : 0
            panel_y = 0  # Panels are at Y=0 in 3D space
            panel_z = 0  # Panels start at ground level
            panel_length = ui_panel['length_mm'] || default_panel_config["dimensions"]["length_mm"] || 1000
            panel_height = default_panel_config["dimensions"]["height_mm"] || 2000  # Default panel height from config
            
            # Map UI panel data to complete panel structure
            {
              "PanelUniqueId" => ui_panel['PanelUniqueId'] || ui_panel['id'] || "PL_#{Time.now.to_i}_#{rand(1000)}",
              "PanelName" => ui_panel['PanelName'] || default_panel_config["name"] || "Framework Panel",
              "PanelType" => ui_panel['PanelType'] || default_panel_config["panel_type"] || "Window Panel",
              "PanelStyle" => ui_panel['PanelStyle'] || "Standard",
              "PanelDivisionsX" => ui_panel['PanelDivisionsX'] || 3,
              "PanelDivisionsY" => ui_panel['PanelDivisionsY'] || 2,
              "PanelNotes" => ui_panel['PanelNotes'] || "Panel from UI",
              "PanelPosX" => panel_x,
              "PanelPosY" => panel_y,
              "PanelPosZ" => panel_z,
              "PanelSizeX" => panel_length,
              "PanelSizeY" => FRAMEWORK_DEPTH_MM,  # Use standard framework depth
              "PanelSizeZ" => panel_height,
              "PanelHeadHeight" => panel_height,
              "PanelUsCillHeight" => 0,
              "PanelRotationX" => 0,
              "PanelRotationY" => 0,
              "PanelRotationZ" => 0,
              "PanelRotationW" => 1,
              "from_node_id" => ui_panel['from_node_id'],
              "to_node_id" => ui_panel['to_node_id'],
              "length_mm" => panel_length
            }
          end
          DebugTools.debug_log("Mapped #{default_panel_lines.size} panel lines with positions")
        else
          DebugTools.debug_log("No valid UI panel lines provided, using empty array")
          default_panel_lines = []
        end

        # Prepare the hash for the serializer, using its defined keys
        data_to_save_via_serializer = {
          ValeDesignSuite::DataUtils::FrameworkDataSerializer::METADATA_KEY    => default_metadata,
          ValeDesignSuite::DataUtils::FrameworkDataSerializer::NODES_KEY       => default_nodes,
          ValeDesignSuite::DataUtils::FrameworkDataSerializer::PANEL_LINES_KEY => default_panel_lines
        }
        
        DebugTools.debug_log("Prepared data for serializer with #{default_nodes.size} nodes and #{default_panel_lines.size} panel lines")

        # First, set the AssemblyID on the ComponentInstance so the serializer can find it
        instance.set_attribute(ASSEMBLY_INFO_DICT_NAME, ASSEMBLY_ID_KEY, new_assembly_id)
        DebugTools.debug_log("Set assembly ID attribute on component: #{new_assembly_id}")
        
        # Store SketchUp specific names
        instance.set_attribute(ASSEMBLY_INFO_DICT_NAME, SKETCHUP_INSTANCE_NAME_KEY, instance.name)
        instance.set_attribute(ASSEMBLY_INFO_DICT_NAME, SKETCHUP_DEFINITION_NAME_KEY, instance.definition.name)
        DebugTools.debug_log("Stored SketchUp instance name: #{instance.name}")
        DebugTools.debug_log("Stored SketchUp definition name: #{instance.definition.name}")

        # Verify the attribute was set correctly
        verify_id = instance.get_attribute(ASSEMBLY_INFO_DICT_NAME, ASSEMBLY_ID_KEY)
        if verify_id == new_assembly_id
          DebugTools.debug_log("Verified assembly ID attribute is set correctly: #{verify_id}")
        else
          DebugTools.debug_log("WARNING - Assembly ID verification failed! Expected: #{new_assembly_id}, Got: #{verify_id}")
          instance.erase! if instance && instance.valid? && !instance.deleted?
          return nil
        end

        # Save data using the serializer
        save_successful = ValeDesignSuite::DataUtils::FrameworkDataSerializer.save_assembly_data(new_assembly_id, data_to_save_via_serializer)

        unless save_successful
          DebugTools.debug_log("Failed to save assembly data via serializer for '#{new_assembly_id}'.")
          instance.erase! if instance && instance.valid? && !instance.deleted? # Clean up instance if save failed
          return nil
        end
        
        DebugTools.debug_log("Successfully saved assembly data via serializer")
        
        # Create initial geometry for the framework
        if ui_nodes && ui_nodes.any? || ui_panel_lines && ui_panel_lines.any?
            DebugTools.debug_log("Creating initial geometry...")
            
            # Use a timer to ensure the component is fully initialized before creating geometry
            UI.start_timer(0.1, false) do
                geometry_created = create_framework_geometry(instance, data_to_save_via_serializer)
                if geometry_created
                    DebugTools.debug_log("Initial geometry created successfully")
                else
                    DebugTools.debug_log("Warning - Failed to create initial geometry")
                end
            end
        else
            DebugTools.debug_log("No nodes or panels to create geometry for")
        end
        
        # List all attribute dictionaries on the component for debugging
        if instance.attribute_dictionaries
          DebugTools.debug_log("All attribute dictionaries on new component: #{instance.attribute_dictionaries.map(&:name).join(', ')}")
        else
          DebugTools.debug_log("WARNING - No attribute dictionaries found on new component!")
        end
        
        DebugTools.debug_log("New framework assembly '#{assembly_name}' (ID: #{new_assembly_id}) created and data saved.")
        return instance
        
      rescue => e # Catch any other unexpected errors during creation
        DebugTools.debug_log("General error creating new assembly '#{assembly_name}': #{e.message}")
        DebugTools.debug_log(e.backtrace.join("\n"))
        instance.erase! if instance && instance.valid? && !instance.deleted? # Ensure cleanup
        return nil
      end
      
      # HELPER | Tests if a component has a valid framework assembly ID
      # ------------------------------------------------------------------
      # @param component [Sketchup::ComponentInstance] The component to test
      # @return [String, nil] The assembly ID if found, nil otherwise
      def self.get_assembly_id_from_component(component)
        return nil unless component.is_a?(Sketchup::ComponentInstance)
        
        assembly_id = component.get_attribute(ASSEMBLY_INFO_DICT_NAME, ASSEMBLY_ID_KEY)
        DebugTools.debug_log("Testing component '#{component.name}' (ID: #{component.entityID}) for assembly ID: #{assembly_id || 'NOT FOUND'}")
        
        if assembly_id && assembly_id.match?(/^VFW\d{3}$/)
          return assembly_id
        else
          return nil
        end
      end

      # #endregion

# -----------------------------------------------------------------------------
# REGION | Geometry Creation and Update Methods
# -----------------------------------------------------------------------------

      # FUNCTION | Create Framework Geometry from Data
      # ------------------------------------------------------------
      def self.create_framework_geometry(component_instance, framework_data)
          return false unless component_instance && component_instance.valid?     # <-- Validate component instance
          return false unless framework_data && framework_data.is_a?(Hash)        # <-- Validate framework data
          
          model = Sketchup.active_model                                           # <-- Get active model
          return false unless model                                               # <-- Validate model exists
          
          # Start operation for undo support
          model.start_operation("Create Framework Geometry", true)                # <-- Start operation
          
          begin
              # Clear existing geometry in the component definition
              component_instance.definition.entities.clear!                       # <-- Clear existing entities
              
              # Create geometry using the geometry generator
              entities = component_instance.definition.entities                   # <-- Get entities collection
              create_framework_geometry_in_entities(entities, framework_data, component_instance)     # <-- Create geometry
              
              model.commit_operation                                              # <-- Commit operation
              DebugTools.debug_log("Successfully created framework geometry")
              return true                                                         # <-- Return success
              
          rescue => e
              model.abort_operation                                               # <-- Abort on error
              DebugTools.debug_log("Error creating geometry: #{e.message}")
              DebugTools.debug_log(e.backtrace.join("\n"))
              return false                                                        # <-- Return failure
          end
      end
      # ---------------------------------------------------------------

      # SUB FUNCTION | Get Node Type Configuration from JSON
      # ---------------------------------------------------------------
      def self.get_node_type_config(node_type_id)
          return nil unless NODE_TYPES_CONFIG["nodeTypes"]                        # <-- Validate node types exist
          
          NODE_TYPES_CONFIG["nodeTypes"].each do |node_type|
              if node_type["NodeTypeId"] == node_type_id
                  return node_type                                                # <-- Return matching node type config
              end
          end
          
          # Return default corner column config if type not found
          DebugTools.debug_log("Node type '#{node_type_id}' not found, using default")
          return NODE_TYPES_CONFIG["nodeTypes"].first                            # <-- Return first (corner column) as default
      end
      # ---------------------------------------------------------------

      # SUB FUNCTION | Create Framework Geometry in Entities Collection
      # ---------------------------------------------------------------
      def self.create_framework_geometry_in_entities(entities, framework_data, component_instance = nil)
          # Validate data structure
          unless framework_data["frameworkNodes"] && framework_data["frameworkPanelLines"]
              DebugTools.debug_log("Invalid framework data structure")
              DebugTools.debug_log("frameworkNodes present: #{framework_data.key?("frameworkNodes")}")
              DebugTools.debug_log("frameworkPanelLines present: #{framework_data.key?("frameworkPanelLines")}")
              DebugTools.debug_log("Data keys: #{framework_data.keys.join(", ")}")
              return false                                                        # <-- Return if invalid data
          end
          
          DebugTools.debug_log("Starting geometry creation with #{framework_data["frameworkNodes"].size} nodes and #{framework_data["frameworkPanelLines"].size} panels")
          
          # Initialize coordination manager for this framework
          model = Sketchup.active_model
          framework_component = component_instance  # Use the passed component instance
          
          # If no component instance was passed, try to find it
          if framework_component.nil?
              model.entities.grep(Sketchup::ComponentInstance).each do |instance|
                  if instance.definition == entities.parent
                      framework_component = instance
                      break
                  end
              end
          end
          
          DebugTools.debug_log("Framework component: #{framework_component ? "Found (#{framework_component.name})" : "NOT FOUND"}")
          
          if framework_component
              # Initialize coordination manager
              ValeDesignSuite::Tools::FrameworkCoordinationManager.initialize_for_framework_assembly(framework_component)
              DebugTools.debug_log("Initialized coordination manager for framework")
          end
          
          # Process nodes using the new node configurator system
          framework_data["frameworkNodes"].each_with_index do |node_data, index|
              DebugTools.debug_log("Processing node #{index + 1}/#{framework_data["frameworkNodes"].size}: #{node_data['NodeUniqueId']}")
              DebugTools.debug_log("Node data keys: #{node_data.keys.join(", ")}")
              
              # Initialize integrated node configurator if not already done
              if framework_component
                  ValeDesignSuite::Tools::FrameworkIntegratedNodeConfigurator.initialize_for_framework_assembly(framework_component)
                  
                  # Configure node using the integrated configurator
                  node_config = ValeDesignSuite::Tools::FrameworkIntegratedNodeConfigurator.configure_node_from_framework_data(node_data)
                  
                  if node_config
                      DebugTools.debug_log("Node configuration created successfully")
                      # Create or update the node geometry using the configurator
                      ValeDesignSuite::Tools::FrameworkIntegratedNodeConfigurator.update_or_create_framework_node_geometry(
                          node_data['NodeUniqueId'], 
                          node_config
                      )
                      DebugTools.debug_log("✓ Node #{node_data['NodeUniqueId']} created successfully")
                  else
                      DebugTools.debug_log("✗ Failed to configure node #{node_data['NodeUniqueId']}")
                      DebugTools.debug_log("Node type: #{node_data['NodeType']}")
                  end
              else
                  DebugTools.debug_log("✗ No framework component found for node creation")
              end
          end
          
          # Process panels using the integrated window panel configurator
          framework_data["frameworkPanelLines"].each do |panel_data|
              DebugTools.debug_log("Creating panel #{panel_data['PanelUniqueId']} using panel configurator")
              
              if framework_component
                  # Initialize integrated window panel configurator if not already done
                  ValeDesignSuite::Tools::FrameworkIntegratedWindowPanelConfigurator.initialize_for_framework_assembly(framework_component)
                  
                  # Configure panel using the integrated configurator
                  panel_config = ValeDesignSuite::Tools::FrameworkIntegratedWindowPanelConfigurator.configure_panel_from_framework_data(panel_data)
                  
                  if panel_config
                      # Create or update the panel geometry using the configurator
                      ValeDesignSuite::Tools::FrameworkIntegratedWindowPanelConfigurator.update_or_create_framework_panel_window_geometry(
                          panel_data['PanelUniqueId'], 
                          panel_config
                      )
                      DebugTools.debug_log("✓ Panel #{panel_data['PanelUniqueId']} created successfully")
                  else
                      DebugTools.debug_log("✗ Failed to configure panel #{panel_data['PanelUniqueId']}")
                  end
              else
                  DebugTools.debug_log("✗ No framework component found for panel creation")
              end
          end
          
          # Synchronize positions using coordination manager
          if framework_component
              ValeDesignSuite::Tools::FrameworkCoordinationManager.synchronize_framework_positions
              DebugTools.debug_log("Synchronized framework positions")
          end
          
          return true                                                             # <-- Return success
      end
      # ---------------------------------------------------------------

      # FUNCTION | Update Framework Geometry (Called on Save)
      # ------------------------------------------------------------
      def self.update_framework_geometry(assembly_id)
          return false unless assembly_id                                         # <-- Validate assembly ID
          
          # Find the component instance with this assembly ID
          model = Sketchup.active_model
          return false unless model                                               # <-- Validate model exists
          
          component_instance = nil
          model.entities.grep(Sketchup::ComponentInstance).each do |instance|
              if get_assembly_id_from_component(instance) == assembly_id
                  component_instance = instance                                   # <-- Found matching component
                  break
              end
          end
          
          unless component_instance
              DebugTools.debug_log("No component found with assembly ID #{assembly_id}")
              return false                                                        # <-- Return if component not found
          end
          
          # Load the latest data
          framework_data = load_framework_data_from_component(component_instance.entityID)
          unless framework_data
              DebugTools.debug_log("Failed to load data for geometry update")
              return false                                                        # <-- Return if data load failed
          end
          
          # Update the geometry
          return create_framework_geometry(component_instance, framework_data)    # <-- Create/update geometry
      end
      # ---------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Incremental Geometry Update System
# -----------------------------------------------------------------------------

      # FUNCTION | Update Framework Geometry Incrementally
      # ------------------------------------------------------------
      def self.update_framework_geometry_incremental(assembly_id, changed_components = nil)
          DebugTools.debug_log("Starting incremental geometry update for #{assembly_id}")
          
          # Load enhanced data with transform cache
          enhanced_data = ValeDesignSuite::DataUtils::FrameworkDataSerializer.load_assembly_data_with_transforms(assembly_id)
          return false unless enhanced_data                                       # <-- Validate enhanced data
          
          framework_data = enhanced_data['framework_data']
          transform_cache = enhanced_data['transform_cache']
          geometry_state = enhanced_data['geometry_state']
          
          # Find framework component
          framework_component = find_framework_component_by_assembly_id(assembly_id)
          return false unless framework_component                                 # <-- Validate framework component
          
          # Initialize coordination manager with cached data
          ValeDesignSuite::Tools::FrameworkCoordinationManager.initialize_for_framework_assembly(framework_component)
          
          # Determine what needs updating
          components_to_update = changed_components || detect_changed_components(framework_data, geometry_state)
          
          if components_to_update.empty?
              DebugTools.debug_log("No components need updating")
              return true                                                         # <-- Nothing to update
          end
          
          DebugTools.debug_log("Updating #{components_to_update.size} components: #{components_to_update.join(', ')}")
          
          model = Sketchup.active_model
          model.start_operation("Incremental Framework Update", true)            # <-- Start operation
          
          begin
              # Update only the changed components
              components_to_update.each do |component_id|
                  if component_id.start_with?('ND_')
                      update_single_node_geometry(component_id, framework_data, framework_component)
                  elsif component_id.start_with?('PL_')
                      update_single_panel_geometry(component_id, framework_data, framework_component)
                  end
              end
              
              # Update transform cache
              ValeDesignSuite::Tools::FrameworkCoordinationManager.mark_transform_cache_dirty
              
              model.commit_operation                                              # <-- Commit operation
              DebugTools.debug_log("Incremental update completed successfully")
              return true                                                         # <-- Return success
              
          rescue => e
              model.abort_operation                                               # <-- Abort on error
              DebugTools.debug_log("Error during incremental update: #{e.message}")
              DebugTools.debug_log(e.backtrace.join("\n"))
              return false                                                        # <-- Return failure
          end
      end
      # ---------------------------------------------------------------

      # SUB FUNCTION | Find Framework Component by Assembly ID
      # ---------------------------------------------------------------
      def self.find_framework_component_by_assembly_id(assembly_id)
          model = Sketchup.active_model
          return nil unless model                                                 # <-- Validate model exists
          
          model.entities.grep(Sketchup::ComponentInstance).each do |instance|
              if get_assembly_id_from_component(instance) == assembly_id
                  return instance                                                 # <-- Return matching component
              end
          end
          
          return nil                                                              # <-- Return nil if not found
      end
      # ---------------------------------------------------------------

      # SUB FUNCTION | Detect Changed Components
      # ---------------------------------------------------------------
      def self.detect_changed_components(current_data, cached_geometry_state)
          changed_components = []                                                 # <-- Initialize changed components array
          
          # Check nodes for changes
          current_data["frameworkNodes"]&.each do |node_data|
              node_id = node_data["NodeUniqueId"]
              cached_state = cached_geometry_state['components']&.[](node_id)
              
              if !cached_state || node_data_changed?(node_data, cached_state)
                  changed_components << node_id                                   # <-- Add to changed list
                  DebugTools.debug_log("Node #{node_id} has changed")
              end
          end
          
          # Check panels for changes
          current_data["frameworkPanelLines"]&.each do |panel_data|
              panel_id = panel_data["PanelUniqueId"]
              cached_state = cached_geometry_state['components']&.[](panel_id)
              
              if !cached_state || panel_data_changed?(panel_data, cached_state)
                  changed_components << panel_id                                  # <-- Add to changed list
                  DebugTools.debug_log("Panel #{panel_id} has changed")
              end
          end
          
          return changed_components                                               # <-- Return changed components
      end
      # ---------------------------------------------------------------

      # SUB HELPER FUNCTION | Check if Node Data Changed
      # ---------------------------------------------------------------
      def self.node_data_changed?(node_data, cached_state)
          return true unless cached_state                                         # <-- Changed if no cached state
          
          current_hash = node_data.hash.to_s                                     # <-- Get current data hash
          cached_hash = cached_state['data_hash']                                # <-- Get cached data hash
          
          return current_hash != cached_hash                                      # <-- Compare hashes
      end
      # ---------------------------------------------------------------

      # SUB HELPER FUNCTION | Check if Panel Data Changed
      # ---------------------------------------------------------------
      def self.panel_data_changed?(panel_data, cached_state)
          return true unless cached_state                                         # <-- Changed if no cached state
          
          current_hash = panel_data.hash.to_s                                    # <-- Get current data hash
          cached_hash = cached_state['data_hash']                                # <-- Get cached data hash
          
          return current_hash != cached_hash                                      # <-- Compare hashes
      end
      # ---------------------------------------------------------------

      # SUB FUNCTION | Update Single Node Geometry
      # ---------------------------------------------------------------
      def self.update_single_node_geometry(node_id, framework_data, framework_component)
          DebugTools.debug_log("Updating geometry for node #{node_id}")
          
          # Find node data
          node_data = framework_data["frameworkNodes"]&.find { |node| node["NodeUniqueId"] == node_id }
          return false unless node_data                                           # <-- Return if node not found
          
          # Initialize integrated node configurator
          ValeDesignSuite::Tools::FrameworkIntegratedNodeConfigurator.initialize_for_framework_assembly(framework_component)
          
          # Configure node using the integrated configurator
          node_config = ValeDesignSuite::Tools::FrameworkIntegratedNodeConfigurator.configure_node_from_framework_data(node_data)
          
          if node_config
              # Update the node geometry using the configurator
              ValeDesignSuite::Tools::FrameworkIntegratedNodeConfigurator.update_or_create_framework_node_geometry(
                  node_id, 
                  node_config
              )
              DebugTools.debug_log("✓ Node #{node_id} updated successfully")
              return true                                                         # <-- Return success
          else
              DebugTools.debug_log("✗ Failed to configure node #{node_id}")
              return false                                                        # <-- Return failure
          end
      end
      # ---------------------------------------------------------------

      # SUB FUNCTION | Update Single Panel Geometry
      # ---------------------------------------------------------------
      def self.update_single_panel_geometry(panel_id, framework_data, framework_component)
          DebugTools.debug_log("Updating geometry for panel #{panel_id}")
          
          # Find panel data
          panel_data = framework_data["frameworkPanelLines"]&.find { |panel| panel["PanelUniqueId"] == panel_id }
          return false unless panel_data                                          # <-- Return if panel not found
          
          # Initialize integrated window panel configurator
          ValeDesignSuite::Tools::FrameworkIntegratedWindowPanelConfigurator.initialize_for_framework_assembly(framework_component)
          
          # Configure panel using the integrated configurator
          panel_config = ValeDesignSuite::Tools::FrameworkIntegratedWindowPanelConfigurator.configure_panel_from_framework_data(panel_data)
          
          if panel_config
              # Update the panel geometry using the configurator
              ValeDesignSuite::Tools::FrameworkIntegratedWindowPanelConfigurator.update_or_create_framework_panel_window_geometry(
                  panel_id, 
                  panel_config
              )
              DebugTools.debug_log("✓ Panel #{panel_id} updated successfully")
              return true                                                         # <-- Return success
          else
              DebugTools.debug_log("✗ Failed to configure panel #{panel_id}")
              return false                                                        # <-- Return failure
          end
      end
      # ---------------------------------------------------------------

      # FUNCTION | Update Framework Geometry with Smart Detection
      # ------------------------------------------------------------
      def self.update_framework_geometry_smart(assembly_id)
          DebugTools.debug_log("Starting smart geometry update for #{assembly_id}")
          
          # Check if assembly has transform cache
          if ValeDesignSuite::DataUtils::FrameworkDataSerializer.has_transform_cache?(assembly_id)
              DebugTools.debug_log("Using incremental update (transform cache available)")
              return update_framework_geometry_incremental(assembly_id)          # <-- Use incremental update
          else
              DebugTools.debug_log("Using full update (no transform cache)")
              return update_framework_geometry(assembly_id)                      # <-- Use full update
          end
      end
      # ---------------------------------------------------------------

      # FUNCTION | Get Node Types Configuration for JavaScript
      # ------------------------------------------------------------
      def self.get_node_types_config_for_javascript
          return NODE_TYPES_CONFIG_JSON                                          # <-- Return JSON string directly
      end
      # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Configuration Loading and Management
# -----------------------------------------------------------------------------

    # FUNCTION | Load Default Assembly Configuration from JSON File
    # ------------------------------------------------------------
    def self.load_default_assembly_configuration
        begin
            config_file_path = File.join(__dir__, "ValeDesignSuite_Config_FrameworkConfigurator_DefaultAssemblyConfig.json")
            
            if File.exist?(config_file_path)                                     # <-- Check if config file exists
                config_content = File.read(config_file_path)                     # <-- Read config file content
                config_data = JSON.parse(config_content)                         # <-- Parse JSON content
                
                # Extract assembly defaults
                assembly_defaults = config_data["assembly_defaults"]             # <-- Get assembly defaults section
                
                DebugTools.debug_log("Loaded default assembly configuration from external file")
                return assembly_defaults                                          # <-- Return assembly defaults
                
            else
                DebugTools.debug_log("Default assembly config file not found, using fallback configuration")
                return create_fallback_assembly_configuration                     # <-- Use fallback if file missing
            end
            
        rescue JSON::ParserError => e
            DebugTools.debug_log("Error parsing default assembly config file: #{e.message}")
            return create_fallback_assembly_configuration                        # <-- Use fallback on parse error
        rescue => e
            DebugTools.debug_log("Error loading default assembly config file: #{e.message}")
            return create_fallback_assembly_configuration                        # <-- Use fallback on any error
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Create Fallback Assembly Configuration
    # ---------------------------------------------------------------
    def self.create_fallback_assembly_configuration
        {
            "name" => "Framework_Assembly",
            "description" => "Standard Framework Assembly Container",
            "dimensions" => {
                "length_mm" => 2400,
                "height_mm" => 2100,
                "depth_mm" => 150,
                "min_length_mm" => 600,
                "max_length_mm" => 6000,
                "min_height_mm" => 600,
                "max_height_mm" => 3000,
                "min_depth_mm" => 50,
                "max_depth_mm" => 300
            },
            "material_properties" => {
                "default_material" => "Wood_Pine",
                "frame_thickness_mm" => 44,
                "frame_width_mm" => 70,
                "corner_joint_type" => "mortise_tenon",
                "surface_finish" => "natural"
            },
            "positioning" => {
                "origin_x" => 0.0,
                "origin_y" => 0.0,
                "origin_z" => 0.0,
                "rotation_degrees" => 0.0,
                "anchor_point" => "bottom_left"
            }
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Get Default Node Configuration from External File
    # ------------------------------------------------------------
    def self.get_default_node_configuration
        begin
            config_file_path = File.join(__dir__, "ValeDesignSuite_Config_FrameworkConfigurator_DefaultNodeConfig.json")
            
            if File.exist?(config_file_path)                                     # <-- Check if config file exists
                config_content = File.read(config_file_path)                     # <-- Read config file content
                config_data = JSON.parse(config_content)                         # <-- Parse JSON content
                
                return config_data["node_defaults"]                              # <-- Return node defaults
            else
                DebugTools.debug_log("Default node config file not found, using fallback")
                return { "dimensions" => { "width_mm" => 70, "depth_mm" => 44, "height_mm" => 70 } }
            end
            
        rescue => e
            DebugTools.debug_log("Error loading default node config: #{e.message}")
            return { "dimensions" => { "width_mm" => 70, "depth_mm" => 44, "height_mm" => 70 } }
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Get Default Panel Configuration from External File
    # ------------------------------------------------------------
    def self.get_default_panel_configuration
        begin
            config_file_path = File.join(__dir__, "ValeDesignSuite_Config_FrameworkConfigurator_DefaultPanelConfig.json")
            
            if File.exist?(config_file_path)                                     # <-- Check if config file exists
                config_content = File.read(config_file_path)                     # <-- Read config file content
                config_data = JSON.parse(config_content)                         # <-- Parse JSON content
                
                return config_data["panel_defaults"]                             # <-- Return panel defaults
            else
                DebugTools.debug_log("Default panel config file not found, using fallback")
                return { "dimensions" => { "length_mm" => 600, "height_mm" => 600, "thickness_mm" => 18 } }
            end
            
        rescue => e
            DebugTools.debug_log("Error loading default panel config: #{e.message}")
            return { "dimensions" => { "length_mm" => 600, "height_mm" => 600, "thickness_mm" => 18 } }
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module FrameworkToolsSketchUpLogic
  end # module Tools
end # module ValeDesignSuite
