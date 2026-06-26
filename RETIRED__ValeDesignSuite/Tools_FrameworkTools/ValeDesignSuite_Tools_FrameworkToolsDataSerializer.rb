# =============================================================================
# ValeDesignSuite - Framework Data Serializer
# =============================================================================
#
# FILE       :  ValeDesignSuite_Tools_FrameworkToolsDataSerializer.rb
# NAMESPACE  :  ValeDesignSuite::Utils
# MODULE     :  FrameworkDataSerializer
# AUTHOR     :  Adam Noble - Vale Garden Houses
# PURPOSE    :  Serialises and deserialises framework configuration data to/from
#               SketchUp model dictionaries using structured JSON.
# VERSION    :  1.1.0
# CREATED    :  22-May-2025
#
# DESCRIPTION:
# - This utility module provides a dedicated handler for serialising framework data
#   (nodes, panels, metadata) into JSON strings and writing them to SketchUp component
#   definition attribute dictionaries.
# - It also deserialises stored JSON strings from the dictionary, validates them,
#   and returns native Ruby Hashes for use in the main plugin logic.
# - Enhanced with transform caching and geometry state tracking for improved performance.
# - This class is stateless and can be safely required by other tool or core scripts.
#
# DICTIONARY STRUCTURE:
# - Dictionary Name on ComponentDefinition: "ValeDesignSuite_FrameworkAssemblies_[FrameworkUniqueId]"
# - Keys per assembly:
#     - "frameworkMetadata"
#     - "frameworkNodes"
#     - "frameworkPanelLines"
#     - "frameworkTransforms" (NEW: Cached transformations)
#     - "frameworkGeometryState" (NEW: Geometry state tracking)
#
# EXAMPLE USAGE:
#   FrameworkDataSerializer.save_assembly_data("VFW001", framework_data_hash)
#   FrameworkDataSerializer.load_assembly_data("VFW001")
#   FrameworkDataSerializer.save_assembly_data_with_transforms("VFW001", data, transforms, state)
# =============================================================================

require 'json'
require 'sketchup.rb'
require_relative 'ValeDesignSuite_Tools_FrameworkDebugTools'

module ValeDesignSuite
    module DataUtils

        module FrameworkDataSerializer

            # ---------------------------------------------
            # DEBUG TOOLS REFERENCE
            # ---------------------------------------------
            DebugTools = ValeDesignSuite::Tools::FrameworkDebugTools

            # ---------------------------------------------
            # CONSTANTS |  Module Constants
            # ---------------------------------------------
            DICTIONARY_PREFIX       =    "ValeDesignSuite_FrameworkAssemblies_".freeze
            METADATA_KEY            =    "frameworkMetadata".freeze
            NODES_KEY               =    "frameworkNodes".freeze
            PANEL_LINES_KEY         =    "frameworkPanelLines".freeze
            TRANSFORMS_KEY          =    "frameworkTransforms".freeze              # <-- NEW: Cached transformations
            GEOMETRY_STATE_KEY      =    "frameworkGeometryState".freeze           # <-- NEW: Geometry state tracking
            # ---------------------------------------------


            # ---------------------------------------------
            # HELPER FUNCTION |  Validate Structure - Private Scope
            # ---------------------------------------------
            def self.valid_structure?(hash)
                hash.is_a?(Hash) &&
                hash.key?(METADATA_KEY) &&
                hash.key?(NODES_KEY) &&
                hash.key?(PANEL_LINES_KEY)
            end
            private_class_method :valid_structure?
            # ---------------------------------------------


            # ---------------------------------------------
            # HELPER FUNCTION |  Validate ID - Private Scope
            # ---------------------------------------------
            def self.valid_assembly_id?(id)
                id.is_a?(String) && id.match?(/^VFW\d{3}$/)
            end
            private_class_method :valid_assembly_id?
            # ---------------------------------------------

            # ---------------------------------------------
            # HELPER FUNCTION |  Find Component Definition By AssemblyID - Private Scope
            # ---------------------------------------------
            def self.find_component_definition_by_assembly_id(assembly_id)
                model = Sketchup.active_model
                return nil unless model

                DebugTools.debug_serializer("Searching for definition with assembly ID: #{assembly_id}")
                
                # Priority 1: Find an instance with this AssemblyID and use its definition.
                # This is more reliable if multiple definitions might share a similar name pattern
                # or if an instance is explicitly tagged.
                all_instances_with_id = []
                
                DebugTools.debug_serializer("Searching top-level entities for AssemblyID '#{assembly_id}'...")
                # Search in top-level entities
                model.entities.grep(Sketchup::ComponentInstance).each do |instance|
                    stored_id = instance.get_attribute("ValeDesignSuite_FrameworkAssemblyInfo", "AssemblyID")
                    if stored_id == assembly_id
                        DebugTools.debug_serializer("Found instance with AssemblyID '#{assembly_id}': '#{instance.name}' (EntityID: #{instance.entityID})")
                        all_instances_with_id << instance
                    end
                end
                
                # Also search in nested entities (component instances inside other components definitions)
                # This ensures we find components even if they are part of a larger assembly.
                DebugTools.debug_serializer("Searching nested entities for AssemblyID '#{assembly_id}'...")
                model.definitions.each do |definition_container|
                    definition_container.entities.grep(Sketchup::ComponentInstance).each do |instance|
                        # Check if already found to avoid duplicates if instance is in model.entities and a definition
                        next if all_instances_with_id.any? { |i| i.entityID == instance.entityID }
                        stored_id = instance.get_attribute("ValeDesignSuite_FrameworkAssemblyInfo", "AssemblyID")
                        if stored_id == assembly_id
                            DebugTools.debug_serializer("Found nested instance with AssemblyID '#{assembly_id}': '#{instance.name}' (EntityID: #{instance.entityID})")
                            all_instances_with_id << instance
                        end
                    end
                end
                
                if !all_instances_with_id.empty?
                    # If multiple instances have this ID (could be instances of the same definition, or different ones - ideally should be same def)
                    # For now, use the definition of the first one found.
                    # A more robust system might involve checking if all these instances share the same definition.
                    instance = all_instances_with_id.first
                    definition = instance.definition
                    DebugTools.debug_serializer("Found definition '#{definition.name}' via component instance '#{instance.name}' (EntityID: #{instance.entityID}) having AssemblyID '#{assembly_id}'.")
                    
                    # Verify the definition is valid
                    if definition.valid?
                        DebugTools.debug_serializer("Definition '#{definition.name}' is valid.")
                    else
                        DebugTools.debug_warn("Definition '#{definition.name}' is NOT valid!")
                    end
                    
                    return definition
                end

                DebugTools.debug_serializer("No component instance found with AssemblyID '#{assembly_id}'. Falling back to name search on definitions.")

                # Priority 2 (Fallback): Try to find by component definition name pattern
                # This was the original primary method.
                DebugTools.debug_serializer("Searching definitions by name pattern '_#{assembly_id}'...")
                potential_definitions_by_name = []
                model.definitions.each do |definition_item|
                    if definition_item.name.include?("_#{assembly_id}")
                        DebugTools.debug_serializer("Found definition by name: '#{definition_item.name}'")
                        potential_definitions_by_name << definition_item
                    end
                end
                
                if !potential_definitions_by_name.empty?
                    # If multiple definitions match by name, this is ambiguous.
                    # The original code took the first. We'll stick to that for now but warn.
                    if potential_definitions_by_name.size > 1
                        DebugTools.debug_warn("Found #{potential_definitions_by_name.size} definitions by name containing '_#{assembly_id}'. Using the first: '#{potential_definitions_by_name.first.name}'.")
                    end
                    definition = potential_definitions_by_name.first
                    DebugTools.debug_serializer("Found definition '#{definition.name}' by name pattern.")
                    return definition
                end
                
                DebugTools.debug_serializer("No definition found by instance attribute or by name pattern for assembly ID: #{assembly_id}")
                
                # ADDITIONAL DIAGNOSTIC: List all definitions to help troubleshoot
                return unless DebugTools.debug_mode?  # Only show this detailed info in debug mode
                
                DebugTools.debug_serializer("Available definitions in model:")
                model.definitions.each_with_index do |def_item, index|
                    # Limit to first 20 to avoid excessive output
                    break if index >= 20
                    DebugTools.debug_serializer("  - #{def_item.name}")
                end
                if model.definitions.size > 20
                    DebugTools.debug_serializer("  - ... and #{model.definitions.size - 20} more definitions")
                end
                
                return nil
            end
            private_class_method :find_component_definition_by_assembly_id
            # ---------------------------------------------

            # = = = = = = = MAIN FUNCTIONS = = = = = = = = 

            # ---------------------------------------------
            # FUNCTION |  Save Complete Assembly - Public Scope
            # ---------------------------------------------
            def self.save_assembly_data(assembly_id, data_hash)
                return false unless valid_assembly_id?(assembly_id)
                return false unless valid_structure?(data_hash)

                model = Sketchup.active_model
                return false unless model
                
                # Find the component definition associated with this assembly ID
                definition = find_component_definition_by_assembly_id(assembly_id)
                unless definition
                    DebugTools.debug_serializer("Could not find component definition for assembly ID: #{assembly_id}")
                    
                    # FALLBACK: Look directly for instances with this AssemblyID and use the first one's definition
                    # This is a more direct approach if the complex search in find_component_definition_by_assembly_id fails
                    DebugTools.debug_serializer("Attempting direct fallback search for component with AssemblyID: #{assembly_id}")
                    direct_instance = nil
                    
                    model.entities.grep(Sketchup::ComponentInstance).each do |instance|
                        if instance.get_attribute("ValeDesignSuite_FrameworkAssemblyInfo", "AssemblyID") == assembly_id
                            direct_instance = instance
                            DebugTools.debug_serializer("Found direct instance with AssemblyID '#{assembly_id}': '#{instance.name}' (EntityID: #{instance.entityID})")
                            break
                        end
                    end
                    
                    if direct_instance
                        definition = direct_instance.definition
                        DebugTools.debug_serializer("Using definition '#{definition.name}' from direct instance search")
                    else
                        DebugTools.debug_serializer("No instances found in direct fallback search. Cannot save data.")
                        return false
                    end
                end

                # Get or create the dictionary for this specific assembly on the component definition
                dict_name = "#{DICTIONARY_PREFIX}#{assembly_id}"
                
                # Debug existing dictionaries on component definition
                if definition.attribute_dictionaries
                    DebugTools.debug_serializer("Existing dictionaries on component definition before save:")
                    definition.attribute_dictionaries.each do |dict|
                        DebugTools.debug_serializer("  - #{dict.name}")
                    end
                else
                    DebugTools.debug_serializer("No dictionaries found on component definition before save")
                end
                
                # CRITICAL FIX: Ensure we can actually create dictionaries on this definition
                begin
                    # First try with a test dictionary to verify dictionary creation works
                    test_dict_name = "ValeDesignSuite_TestDictionary"
                    test_dict = definition.attribute_dictionary(test_dict_name, true)
                    if test_dict
                        DebugTools.debug_serializer("Successfully created test dictionary on definition")
                        # Instead of deleting the dictionary (which isn't supported), 
                        # just leave it as it won't hurt anything
                        # Note: ComponentDefinition doesn't have delete_attribute_dictionary method
                    else
                        DebugTools.debug_serializer("CRITICAL ERROR - Failed to create test dictionary on definition")
                        return false
                    end
                rescue => e
                    DebugTools.debug_serializer("CRITICAL ERROR - Exception when testing dictionary creation: #{e.message}")
                    DebugTools.debug_backtrace(e.backtrace)
                    return false
                end
                
                # Now create the actual dictionary
                dict = definition.attribute_dictionary(dict_name, true) # true ensures creation if not exists
                unless dict
                    DebugTools.debug_serializer("Failed to create dictionary '#{dict_name}' on component definition")
                    return false
                end

                # Debug the metadata content
                if data_hash[METADATA_KEY].is_a?(Array) && !data_hash[METADATA_KEY].empty?
                  DebugTools.debug_serializer("Saving metadata for assembly #{assembly_id}:")
                  DebugTools.debug_serializer("  Framework Name: #{data_hash[METADATA_KEY][0]['FrameworkName'] || 'N/A'}")
                  DebugTools.debug_serializer("  Framework Unique ID: #{data_hash[METADATA_KEY][0]['FrameworkUniqueId'] || 'N/A'}")
                  DebugTools.debug_serializer("  Nodes Count: #{data_hash[NODES_KEY].size}")
                  DebugTools.debug_serializer("  Panel Lines Count: #{data_hash[PANEL_LINES_KEY].size}")
                end

                begin
                  # Ensure FrameworkUniqueId in metadata matches the assembly_id
                  if data_hash[METADATA_KEY] && data_hash[METADATA_KEY].is_a?(Array) && !data_hash[METADATA_KEY].empty?
                    if data_hash[METADATA_KEY][0]['FrameworkUniqueId'] != assembly_id
                      DebugTools.debug_serializer("Correcting FrameworkUniqueId in metadata to match AssemblyID")
                      data_hash[METADATA_KEY][0]['FrameworkUniqueId'] = assembly_id
                    end
                  end
                
                  # Save each key separately to the component definition's dictionary
                  begin
                    DebugTools.debug_serializer("Saving METADATA_KEY...")
                    metadata_json = JSON.generate(data_hash[METADATA_KEY])
                    dict[METADATA_KEY] = metadata_json
                    
                    DebugTools.debug_serializer("Saving NODES_KEY...")
                    nodes_json = JSON.generate(data_hash[NODES_KEY])
                    dict[NODES_KEY] = nodes_json
                    
                    DebugTools.debug_serializer("Saving PANEL_LINES_KEY...")
                    panel_lines_json = JSON.generate(data_hash[PANEL_LINES_KEY])
                    dict[PANEL_LINES_KEY] = panel_lines_json
                  rescue => e
                    DebugTools.debug_serializer("Error saving to dictionary: #{e.message}")
                    DebugTools.debug_backtrace(e.backtrace)
                    return false
                  end
                  
                  # Verify that the data was saved
                  saved_dict = definition.attribute_dictionary(dict_name)
                  if saved_dict
                      DebugTools.debug_serializer("Verified dictionary exists after save: #{saved_dict.name}")
                      DebugTools.debug_serializer("Keys in saved dictionary:")
                      saved_dict.each_key do |key|
                          DebugTools.debug_serializer("  - #{key}")
                      end
                      
                      # Additional verification - check the saved data
                      saved_metadata = saved_dict[METADATA_KEY]
                      saved_nodes = saved_dict[NODES_KEY]
                      saved_panel_lines = saved_dict[PANEL_LINES_KEY]
                      
                      if saved_metadata && saved_nodes && saved_panel_lines
                          DebugTools.debug_serializer("All data keys verified in dictionary.")
                          
                          # Parse saved data to verify it's valid JSON
                          begin
                              metadata_obj = JSON.parse(saved_metadata)
                              nodes_obj = JSON.parse(saved_nodes)
                              panel_lines_obj = JSON.parse(saved_panel_lines)
                              
                              DebugTools.debug_serializer("Verified metadata has #{metadata_obj.size} items")
                              DebugTools.debug_serializer("Verified nodes has #{nodes_obj.size} items")
                              DebugTools.debug_serializer("Verified panel lines has #{panel_lines_obj.size} items")
                          rescue JSON::ParserError => e
                              DebugTools.debug_warn("WARNING - Saved data is not valid JSON: #{e.message}")
                          end
                      else
                          DebugTools.debug_warn("WARNING - Missing expected keys in saved dictionary!")
                          DebugTools.debug_serializer("  - metadata: #{saved_metadata ? 'present' : 'MISSING'}")
                          DebugTools.debug_serializer("  - nodes: #{saved_nodes ? 'present' : 'MISSING'}")
                          DebugTools.debug_serializer("  - panel lines: #{saved_panel_lines ? 'present' : 'MISSING'}")
                      end
                  else
                      DebugTools.debug_warn("WARNING - Dictionary not found after save!")
                  end
                  
                  # Force model operations to complete if needed
                  begin
                    if model.respond_to?(:start_operation)
                      # Only start a new operation if we are not already inside one
                      if model.respond_to?(:active_operation) && 
                         (model.active_operation.nil? || 
                          (model.active_operation.respond_to?(:empty?) && model.active_operation.empty?))
                        operation = model.start_operation("ValeDesignSuite Dictionary Update", true)
                        model.commit_operation if operation
                      end
                    end
                  rescue => e
                    DebugTools.debug_warn("Warning - Error handling model operations: #{e.message}")
                    # Non-fatal error, continue anyway
                  end
                  
                  DebugTools.debug_serializer("Successfully saved data for assembly #{assembly_id} to component definition")
                  return true
                rescue => e
                  DebugTools.debug_serializer("Error saving data for assembly #{assembly_id}: #{e.message}")
                  DebugTools.debug_backtrace(e.backtrace)
                  return false
                end
            end
            # ---------------------------------------------

            # ---------------------------------------------
            # FUNCTION |  Load Complete Assembly - Public Scope
            # ---------------------------------------------            
            def self.load_assembly_data(assembly_id)
                return nil unless valid_assembly_id?(assembly_id)

                model = Sketchup.active_model
                return nil unless model
                
                # Find the component definition associated with this assembly ID
                definition = find_component_definition_by_assembly_id(assembly_id)
                unless definition
                    DebugTools.debug_serializer("Could not find component definition for assembly ID: #{assembly_id}")
                    
                    # FALLBACK: Look directly for instances with this AssemblyID and use the first one's definition
                    DebugTools.debug_serializer("Attempting direct fallback search for component with AssemblyID: #{assembly_id}")
                    direct_instance = nil
                    
                    model.entities.grep(Sketchup::ComponentInstance).each do |instance|
                        if instance.get_attribute("ValeDesignSuite_FrameworkAssemblyInfo", "AssemblyID") == assembly_id
                            direct_instance = instance
                            DebugTools.debug_serializer("Found direct instance with AssemblyID '#{assembly_id}': '#{instance.name}' (EntityID: #{instance.entityID})")
                            break
                        end
                    end
                    
                    if direct_instance
                        definition = direct_instance.definition
                        DebugTools.debug_serializer("Using definition '#{definition.name}' from direct instance search")
                    else
                        DebugTools.debug_serializer("No instances found in direct fallback search. Cannot load data.")
                        return nil
                    end
                end

                # Get the dictionary for this specific assembly
                dict_name = "#{DICTIONARY_PREFIX}#{assembly_id}"
                dict = definition.attribute_dictionary(dict_name)
                
                # Debug info about dictionaries on the component definition
                if definition.attribute_dictionaries
                    DebugTools.debug_serializer("Dictionaries on component definition:")
                    definition.attribute_dictionaries.each do |dict|
                        DebugTools.debug_serializer("  - #{dict.name}")
                    end
                else
                    DebugTools.debug_serializer("No dictionaries found on component definition")
                end
                
                # Try to create the dictionary if it doesn't exist (though it should already exist)
                if dict.nil?
                    DebugTools.debug_serializer("Dictionary '#{dict_name}' not found on component definition")
                    
                    # Create a new empty dictionary rather than using global data
                    dict = definition.attribute_dictionary(dict_name, true) # Create it if it doesn't exist
                    
                    # Initialize with empty structures
                    dict[METADATA_KEY] = JSON.generate([])
                    dict[NODES_KEY] = JSON.generate([])
                    dict[PANEL_LINES_KEY] = JSON.generate([])
                    
                    DebugTools.debug_serializer("Created new empty dictionary '#{dict_name}'")
                    
                    # Return an empty data structure
                    return {
                        METADATA_KEY => [],
                        NODES_KEY => [],
                        PANEL_LINES_KEY => []
                    }
                end

                DebugTools.debug_serializer("Loading data for assembly #{assembly_id}")

                begin
                    # Load and parse each key from the component definition's dictionary
                    metadata_json = dict[METADATA_KEY]
                    nodes_json = dict[NODES_KEY]
                    panel_lines_json = dict[PANEL_LINES_KEY]
                    
                    # Debug info about keys in the dictionary
                    DebugTools.debug_serializer("Keys in dictionary '#{dict_name}':")
                    dict.each_key do |key|
                        DebugTools.debug_serializer("  - #{key}")
                    end
                    
                    if !metadata_json || !nodes_json || !panel_lines_json
                        DebugTools.debug_serializer("Missing required data keys for assembly #{assembly_id}")
                        DebugTools.debug_serializer("  - metadata_json: #{metadata_json ? 'present' : 'missing'}")
                        DebugTools.debug_serializer("  - nodes_json: #{nodes_json ? 'present' : 'missing'}")
                        DebugTools.debug_serializer("  - panel_lines_json: #{panel_lines_json ? 'present' : 'missing'}")
                        return nil
                    end
                    
                    metadata = JSON.parse(metadata_json)
                    nodes = JSON.parse(nodes_json)
                    panel_lines = JSON.parse(panel_lines_json)
                    
                    # Ensure the loaded structure is what we expect
                    loaded_hash = {
                        METADATA_KEY => metadata,
                        NODES_KEY => nodes,
                        PANEL_LINES_KEY => panel_lines
                    }
                    
                    DebugTools.debug_serializer("Loaded metadata for assembly #{assembly_id}:")
                    DebugTools.debug_serializer("  Framework Name: #{metadata[0]['FrameworkName'] || 'N/A'}")
                    DebugTools.debug_serializer("  Framework Unique ID: #{metadata[0]['FrameworkUniqueId'] || 'N/A'}")
                    DebugTools.debug_serializer("  Nodes Count: #{nodes.size}")
                    DebugTools.debug_serializer("  Panel Lines Count: #{panel_lines.size}")
                    
                    return loaded_hash
                rescue JSON::ParserError => e
                    DebugTools.debug_serializer("JSON Parse Error loading assembly #{assembly_id}: #{e.message}")
                    nil
                rescue => e
                    DebugTools.debug_serializer("Error loading assembly data for #{assembly_id}: #{e.message}")
                    DebugTools.debug_backtrace(e.backtrace)
                    nil
                end
            end
            # ---------------------------------------------

            # ---------------------------------------------
            # FUNCTION |  Delete an Assembly - Public Scope
            # ---------------------------------------------
            def self.delete_assembly_data(assembly_id)
                return unless valid_assembly_id?(assembly_id)

                model = Sketchup.active_model
                return unless model
                
                # Find the component definition associated with this assembly ID
                definition = find_component_definition_by_assembly_id(assembly_id)
                return unless definition

                # Remove the dictionary for this specific assembly
                dict_name = "#{DICTIONARY_PREFIX}#{assembly_id}"
                definition.delete_attribute_dictionary(dict_name)
                DebugTools.debug_serializer("Deleted dictionary for assembly #{assembly_id}")
            end
            # ---------------------------------------------


            # ---------------------------------------------
            # FUNCTION |  List All Assemblies - Public Scope
            # ---------------------------------------------
            def self.list_all_assemblies
                model = Sketchup.active_model
                return [] unless model

                assembly_ids = []
                
                # Search through all component instances for AssemblyID values
                model.entities.grep(Sketchup::ComponentInstance).each do |instance|
                    assembly_id = instance.get_attribute("ValeDesignSuite_FrameworkAssemblyInfo", "AssemblyID")
                    if assembly_id && valid_assembly_id?(assembly_id)
                        assembly_ids << assembly_id
                    end
                end
                
                assembly_ids.uniq
            end
            # ---------------------------------------------


            # ---------------------------------------------
            # FUNCTION |  Save Assembly Data with Transform Cache
            # ---------------------------------------------
            def self.save_assembly_data_with_transforms(assembly_id, data_hash, transform_cache = nil, geometry_state = nil)
                return false unless valid_assembly_id?(assembly_id)                 # <-- Validate assembly ID
                return false unless valid_structure?(data_hash)                     # <-- Validate basic structure
                
                # Enhance the data hash with transform cache
                enhanced_data = data_hash.dup                                       # <-- Create copy of data
                
                if transform_cache && !transform_cache.empty?
                    enhanced_data[TRANSFORMS_KEY] = transform_cache                 # <-- Add transform cache
                    DebugTools.debug_serializer("Adding #{transform_cache.size} cached transformations")
                end
                
                if geometry_state && !geometry_state.empty?
                    enhanced_data[GEOMETRY_STATE_KEY] = geometry_state              # <-- Add geometry state
                    DebugTools.debug_serializer("Adding geometry state with #{geometry_state['components']&.size || 0} components")
                end
                
                # Use existing save method with enhanced data
                return save_assembly_data_enhanced(assembly_id, enhanced_data)      # <-- Save enhanced data
            end
            # ---------------------------------------------------------------

            # ---------------------------------------------
            # FUNCTION |  Load Assembly Data with Transform Cache
            # ---------------------------------------------
            def self.load_assembly_data_with_transforms(assembly_id)
                return nil unless valid_assembly_id?(assembly_id)                   # <-- Validate assembly ID
                
                # Load using enhanced method
                loaded_data = load_assembly_data_enhanced(assembly_id)              # <-- Load enhanced data
                return nil unless loaded_data                                       # <-- Return nil if load failed
                
                # Extract transform cache if available
                transform_cache = loaded_data[TRANSFORMS_KEY] || {}                 # <-- Get transform cache
                geometry_state = loaded_data[GEOMETRY_STATE_KEY] || {}              # <-- Get geometry state
                
                DebugTools.debug_serializer("Loaded #{transform_cache.size} cached transformations")
                DebugTools.debug_serializer("Loaded geometry state with #{geometry_state['components']&.size || 0} components")
                
                return {
                    'framework_data' => loaded_data,                                # <-- Return framework data
                    'transform_cache' => transform_cache,                           # <-- Return transform cache
                    'geometry_state' => geometry_state                              # <-- Return geometry state
                }
            end
            # ---------------------------------------------------------------

            # ---------------------------------------------
            # FUNCTION |  Check if Assembly has Transform Cache
            # ---------------------------------------------
            def self.has_transform_cache?(assembly_id)
                return false unless valid_assembly_id?(assembly_id)                 # <-- Validate assembly ID
                
                loaded_data = load_assembly_data_enhanced(assembly_id)              # <-- Load enhanced data
                return false unless loaded_data                                     # <-- Return false if load failed
                
                transform_cache = loaded_data[TRANSFORMS_KEY]                       # <-- Get transform cache
                return transform_cache && !transform_cache.empty?                   # <-- Return true if cache exists
            end
            # ---------------------------------------------------------------

            # ---------------------------------------------
            # HELPER FUNCTION |  Validate Enhanced Structure - Private Scope
            # ---------------------------------------------
            def self.valid_enhanced_structure?(hash)
                return false unless hash.is_a?(Hash)                                # <-- Validate hash type
                
                # Check required keys
                required_keys = [METADATA_KEY, NODES_KEY, PANEL_LINES_KEY]
                required_keys.all? { |key| hash.key?(key) }                        # <-- Check all required keys exist
            end
            private_class_method :valid_enhanced_structure?
            # ---------------------------------------------

            # ---------------------------------------------
            # FUNCTION |  Save Complete Assembly Enhanced - Public Scope
            # ---------------------------------------------
            def self.save_assembly_data_enhanced(assembly_id, data_hash)
                return false unless valid_assembly_id?(assembly_id)                 # <-- Validate assembly ID
                return false unless valid_enhanced_structure?(data_hash)            # <-- Validate enhanced structure

                model = Sketchup.active_model
                return false unless model                                           # <-- Validate model exists
                
                # Find the component definition associated with this assembly ID
                definition = find_component_definition_by_assembly_id(assembly_id)
                unless definition
                    DebugTools.debug_serializer("Could not find component definition for assembly ID: #{assembly_id}")
                    
                    # FALLBACK: Look directly for instances with this AssemblyID and use the first one's definition
                    DebugTools.debug_serializer("Attempting direct fallback search for component with AssemblyID: #{assembly_id}")
                    direct_instance = nil
                    
                    model.entities.grep(Sketchup::ComponentInstance).each do |instance|
                        if instance.get_attribute("ValeDesignSuite_FrameworkAssemblyInfo", "AssemblyID") == assembly_id
                            direct_instance = instance
                            DebugTools.debug_serializer("Found direct instance with AssemblyID '#{assembly_id}': '#{instance.name}' (EntityID: #{instance.entityID})")
                            break
                        end
                    end
                    
                    if direct_instance
                        definition = direct_instance.definition
                        DebugTools.debug_serializer("Using definition '#{definition.name}' from direct instance search")
                    else
                        DebugTools.debug_serializer("No instances found in direct fallback search. Cannot save data.")
                        return false
                    end
                end

                # Get or create the dictionary for this specific assembly on the component definition
                dict_name = "#{DICTIONARY_PREFIX}#{assembly_id}"
                dict = definition.attribute_dictionary(dict_name, true)             # <-- Create dictionary if needed
                unless dict
                    DebugTools.debug_serializer("Failed to create dictionary '#{dict_name}' on component definition")
                    return false
                end

                # Debug the enhanced data content
                if data_hash[METADATA_KEY].is_a?(Array) && !data_hash[METADATA_KEY].empty?
                  DebugTools.debug_serializer("Saving enhanced data for assembly #{assembly_id}:")
                  DebugTools.debug_serializer("  Framework Name: #{data_hash[METADATA_KEY][0]['FrameworkName'] || 'N/A'}")
                  DebugTools.debug_serializer("  Framework Unique ID: #{data_hash[METADATA_KEY][0]['FrameworkUniqueId'] || 'N/A'}")
                  DebugTools.debug_serializer("  Nodes Count: #{data_hash[NODES_KEY].size}")
                  DebugTools.debug_serializer("  Panel Lines Count: #{data_hash[PANEL_LINES_KEY].size}")
                  DebugTools.debug_serializer("  Transform Cache: #{data_hash[TRANSFORMS_KEY] ? 'YES' : 'NO'}")
                  DebugTools.debug_serializer("  Geometry State: #{data_hash[GEOMETRY_STATE_KEY] ? 'YES' : 'NO'}")
                end

                begin
                  # Ensure FrameworkUniqueId in metadata matches the assembly_id
                  if data_hash[METADATA_KEY] && data_hash[METADATA_KEY].is_a?(Array) && !data_hash[METADATA_KEY].empty?
                    if data_hash[METADATA_KEY][0]['FrameworkUniqueId'] != assembly_id
                      DebugTools.debug_serializer("Correcting FrameworkUniqueId in metadata to match AssemblyID")
                      data_hash[METADATA_KEY][0]['FrameworkUniqueId'] = assembly_id
                    end
                  end
                
                  # Save each key separately to the component definition's dictionary
                  begin
                    DebugTools.debug_serializer("Saving enhanced data keys...")
                    
                    # Save core data
                    dict[METADATA_KEY] = JSON.generate(data_hash[METADATA_KEY])
                    dict[NODES_KEY] = JSON.generate(data_hash[NODES_KEY])
                    dict[PANEL_LINES_KEY] = JSON.generate(data_hash[PANEL_LINES_KEY])
                    
                    # Save enhanced data if present
                    if data_hash[TRANSFORMS_KEY]
                        dict[TRANSFORMS_KEY] = JSON.generate(data_hash[TRANSFORMS_KEY])
                        DebugTools.debug_serializer("Saved transform cache")
                    end
                    
                    if data_hash[GEOMETRY_STATE_KEY]
                        dict[GEOMETRY_STATE_KEY] = JSON.generate(data_hash[GEOMETRY_STATE_KEY])
                        DebugTools.debug_serializer("Saved geometry state")
                    end
                    
                  rescue => e
                    DebugTools.debug_serializer("Error saving enhanced data to dictionary: #{e.message}")
                    DebugTools.debug_backtrace(e.backtrace)
                    return false
                  end
                  
                  DebugTools.debug_serializer("Successfully saved enhanced data for assembly #{assembly_id} to component definition")
                  return true
                rescue => e
                  DebugTools.debug_serializer("Error saving enhanced data for assembly #{assembly_id}: #{e.message}")
                  DebugTools.debug_backtrace(e.backtrace)
                  return false
                end
            end
            # ---------------------------------------------

            # ---------------------------------------------
            # FUNCTION |  Load Complete Assembly Enhanced - Public Scope
            # ---------------------------------------------            
            def self.load_assembly_data_enhanced(assembly_id)
                return nil unless valid_assembly_id?(assembly_id)                   # <-- Validate assembly ID

                model = Sketchup.active_model
                return nil unless model                                             # <-- Validate model exists
                
                # Find the component definition associated with this assembly ID
                definition = find_component_definition_by_assembly_id(assembly_id)
                unless definition
                    DebugTools.debug_serializer("Could not find component definition for assembly ID: #{assembly_id}")
                    return nil
                end

                # Get the dictionary for this specific assembly
                dict_name = "#{DICTIONARY_PREFIX}#{assembly_id}"
                dict = definition.attribute_dictionary(dict_name)
                
                if dict.nil?
                    DebugTools.debug_serializer("Dictionary '#{dict_name}' not found on component definition")
                    return nil
                end

                DebugTools.debug_serializer("Loading enhanced data for assembly #{assembly_id}")

                begin
                    # Load and parse each key from the component definition's dictionary
                    metadata_json = dict[METADATA_KEY]
                    nodes_json = dict[NODES_KEY]
                    panel_lines_json = dict[PANEL_LINES_KEY]
                    transforms_json = dict[TRANSFORMS_KEY]                          # <-- Load transform cache
                    geometry_state_json = dict[GEOMETRY_STATE_KEY]                  # <-- Load geometry state
                    
                    if !metadata_json || !nodes_json || !panel_lines_json
                        DebugTools.debug_serializer("Missing required data keys for assembly #{assembly_id}")
                        return nil
                    end
                    
                    # Parse core data
                    metadata = JSON.parse(metadata_json)
                    nodes = JSON.parse(nodes_json)
                    panel_lines = JSON.parse(panel_lines_json)
                    
                    # Parse enhanced data if present
                    transforms = transforms_json ? JSON.parse(transforms_json) : {}
                    geometry_state = geometry_state_json ? JSON.parse(geometry_state_json) : {}
                    
                    # Ensure the loaded structure includes enhanced data
                    loaded_hash = {
                        METADATA_KEY => metadata,
                        NODES_KEY => nodes,
                        PANEL_LINES_KEY => panel_lines,
                        TRANSFORMS_KEY => transforms,
                        GEOMETRY_STATE_KEY => geometry_state
                    }
                    
                    DebugTools.debug_serializer("Loaded enhanced data for assembly #{assembly_id}:")
                    DebugTools.debug_serializer("  Framework Name: #{metadata[0]['FrameworkName'] || 'N/A'}")
                    DebugTools.debug_serializer("  Framework Unique ID: #{metadata[0]['FrameworkUniqueId'] || 'N/A'}")
                    DebugTools.debug_serializer("  Nodes Count: #{nodes.size}")
                    DebugTools.debug_serializer("  Panel Lines Count: #{panel_lines.size}")
                    DebugTools.debug_serializer("  Transform Cache: #{transforms.empty? ? 'NO' : "YES (#{transforms.size} items)"}")
                    DebugTools.debug_serializer("  Geometry State: #{geometry_state.empty? ? 'NO' : "YES (#{geometry_state['components']&.size || 0} components)"}")
                    
                    return loaded_hash
                rescue JSON::ParserError => e
                    DebugTools.debug_serializer("JSON Parse Error loading enhanced assembly #{assembly_id}: #{e.message}")
                    nil
                rescue => e
                    DebugTools.debug_serializer("Error loading enhanced assembly data for #{assembly_id}: #{e.message}")
                    DebugTools.debug_backtrace(e.backtrace)
                    nil
                end
            end
            # ---------------------------------------------

        end  #<-- Closure of Module FrameworkDataSerializer
    end      #<-- Closure of Module DataUtils 
end          #<-- Closure of Module ValeDesignSuite