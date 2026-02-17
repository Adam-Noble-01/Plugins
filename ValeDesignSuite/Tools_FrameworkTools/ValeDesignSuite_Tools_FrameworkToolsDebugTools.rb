# =============================================================================
# VALEDESIGNSUITE - FRAMEWORK TOOLS DEBUG TOOLS
# =============================================================================
#
# FILE       : ValeDesignSuite_Tools_FrameworkToolsDebugTools.rb
# NAMESPACE  : ValeDesignSuite::Tools::FrameworkToolsDebugTools
# MODULE     : FrameworkToolsDebugTools
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Comprehensive Framework Assembly Debug Reporting
# CREATED    : 29-May-2025
#
# DESCRIPTION:
# - Provides detailed diagnostic functions for inspecting framework assemblies
# - Generates comprehensive reports about framework data structures
# - Analyzes framework assemblies in component definitions
# - Performs deep dives into framework nodes, panels, and metadata
# - Maintains separation of debugging logic from main framework tools
# - Uses global debug configuration to control output
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 29-May-2025 - Version 1.0.0
# - Initial Release
# - Comprehensive framework debug reporting implementation
#
# 26-May-2025 - Version 1.1.0
# - Updated to use global debug configuration system
# - Added conditional debug output based on DEBUG_MODE
#
# =============================================================================

require 'sketchup'
require 'json'
require 'stringio'
require_relative 'ValeDesignSuite_Tools_FrameworkDebugTools'

module ValeDesignSuite
  module Tools
    module FrameworkToolsDebugTools

# -----------------------------------------------------------------------------
# REGION | Debug Configuration Reference
# -----------------------------------------------------------------------------

    # MODULE REFERENCE | Link to Framework Debug Tools
    # ------------------------------------------------------------
    DebugTools = ValeDesignSuite::Tools::FrameworkDebugTools                 # <-- Reference to debug tools
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Model Level Diagnostics
# -----------------------------------------------------------------------------

    # FUNCTION | Check Model Level Attribute Dictionaries
    # ------------------------------------------------------------
    def self.check_model_level_dictionaries(model)
        return unless DebugTools.debug_mode?                                 # Exit if debug mode disabled
        
        DebugTools.debug_log("============================================================")
        DebugTools.debug_log("PHASE 01 - CHECK ALL MODEL-LEVEL ATTRIBUTE DICTIONARIES")
        DebugTools.debug_log("============================================================")
        
        model_dicts = model.attribute_dictionaries
        if model_dicts.nil? || model_dicts.count == 0
            DebugTools.debug_log("No attribute dictionaries found at the model level.")
        else
            model_dicts.each do |dict|
                next if dict.name == "GeoReference"                         # <-- Skip GeoReference
                
                DebugTools.debug_log("Dictionary Name: #{dict.name}")
                DebugTools.debug_log("----------------------------------------")
                dict.each_pair do |key, value|
                    DebugTools.debug_log("  #{key.inspect} => #{value.inspect}")
                end
                DebugTools.debug_log("")
            end
        end
    end
    # ------------------------------------------------------------

    # FUNCTION | Check Framework Assemblies in Definitions
    # ------------------------------------------------------------
    def self.check_framework_assemblies_in_definitions(model)
        return unless DebugTools.debug_mode?                                 # Exit if debug mode disabled
        
        DebugTools.debug_log("FRAMEWORK ASSEMBLIES IN COMPONENT DEFINITIONS:")
        DebugTools.debug_log("----------------------------------------")
        found_model_assembly_dicts = false
        prefix = ValeDesignSuite::DataUtils::FrameworkDataSerializer::DICTIONARY_PREFIX
        
        if model.definitions && model.definitions.respond_to?(:each)
            model.definitions.each do |definition_item|
                assembly_dicts_on_def = definition_item.attribute_dictionaries&.select { |d| d.name.start_with?(prefix) }
                if assembly_dicts_on_def && !assembly_dicts_on_def.empty?
                    found_model_assembly_dicts = true
                    assembly_dicts_on_def.each do |dict_on_def|
                        assembly_id_from_def_dict = dict_on_def.name.sub(prefix, '')
                        DebugTools.debug_log("Found assembly '#{assembly_id_from_def_dict}' on definition '#{definition_item.name}'")
                        
                        metadata_json_str = dict_on_def[ValeDesignSuite::DataUtils::FrameworkDataSerializer::METADATA_KEY]
                        nodes_json_str = dict_on_def[ValeDesignSuite::DataUtils::FrameworkDataSerializer::NODES_KEY]
                        panel_lines_json_str = dict_on_def[ValeDesignSuite::DataUtils::FrameworkDataSerializer::PANEL_LINES_KEY]
                        
                        if metadata_json_str
                            begin
                                metadata_parsed = JSON.parse(metadata_json_str)
                                if metadata_parsed.is_a?(Array) && !metadata_parsed.empty?
                                    DebugTools.debug_log("  - Framework Name: #{metadata_parsed[0]['FrameworkName']}")
                                    DebugTools.debug_log("  - Framework UID: #{metadata_parsed[0]['FrameworkUniqueId']}")
                                end
                                nodes_count = nodes_json_str ? JSON.parse(nodes_json_str || '[]').size : 0
                                panel_lines_count = panel_lines_json_str ? JSON.parse(panel_lines_json_str || '[]').size : 0
                                DebugTools.debug_log("  - Nodes Count: #{nodes_count}")
                                DebugTools.debug_log("  - Panel Lines Count: #{panel_lines_count}")
                                DebugTools.debug_log("")
                            rescue JSON::ParserError => e
                                DebugTools.debug_error("Error parsing framework assembly data for '#{assembly_id_from_def_dict}' on definition '#{definition_item.name}'", e)
                            end
                        else
                            DebugTools.debug_log("  - Metadata JSON string not found for assembly '#{assembly_id_from_def_dict}' on definition '#{definition_item.name}'")
                            DebugTools.debug_log("")
                        end
                    end
                end
            end
        end
        
        DebugTools.debug_log("No framework assemblies found in component definitions.") unless found_model_assembly_dicts
        DebugTools.debug_log("")
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Component Level Diagnostics
# -----------------------------------------------------------------------------

    # FUNCTION | Check Selected Component Dictionaries
    # ------------------------------------------------------------
    def self.check_selected_component_dictionaries(selection)
        return unless DebugTools.debug_mode?                                 # Exit if debug mode disabled
        
        DebugTools.debug_log("================================================================")
        DebugTools.debug_log("PHASE 02 - CHECK SELECTED COMPONENT-LEVEL ATTRIBUTE DICTIONARIES")
        DebugTools.debug_log("================================================================")
        
        if selection.nil? || selection.empty?
            DebugTools.debug_log("No items selected.")
            return
        end
        
        DebugTools.debug_log("No. items  :  #{selection.size} selected")
        selection.each_with_index do |entity, index|
            item_query_id = "Item #{format('%02d', index + 1)}"
            
            unless entity.is_a?(Sketchup::ComponentInstance)
                DebugTools.debug_log("---------------------------------------")
                DebugTools.debug_log("<#{item_query_id}>")
                DebugTools.debug_log("Query ID   :  #{item_query_id}")
                DebugTools.debug_log("Item is not a ComponentInstance, it is a #{entity.class.name}")
                DebugTools.debug_log("---------------------------------------")
                next
            end
            
            DebugTools.debug_log("---------------------------------------")
            DebugTools.debug_log("<#{item_query_id}>")
            DebugTools.debug_log("Query ID   :  #{item_query_id}")
            DebugTools.debug_log("Component  :  '#{entity.name}'")
            DebugTools.debug_log("EntityID   :  #{entity.entityID}")
            
            DebugTools.debug_log("Item #{format('%02d', index + 1)} Breakdown:")
            assembly_info_dict = entity.attribute_dictionary(ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic::ASSEMBLY_INFO_DICT_NAME, false)
            if assembly_info_dict
                DebugTools.debug_log("Has assembly dict.  :  YES")
                DebugTools.debug_log("Dict. keys          :  #{assembly_info_dict.keys.join(', ')}")
                assembly_id = assembly_info_dict[ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic::ASSEMBLY_ID_KEY]
                if assembly_id
                    cleaned_assembly_id = assembly_id.is_a?(String) ? assembly_id.strip : assembly_id
                    DebugTools.debug_log("Assembly ID         :  #{cleaned_assembly_id} (Original: #{assembly_id.inspect})")
                    is_valid_format = cleaned_assembly_id.is_a?(String) && cleaned_assembly_id.match?(/^VFW\d{3}$/)
                    DebugTools.debug_log("Valid format        :  #{is_valid_format ? 'YES' : 'NO'}")
                    
                    if is_valid_format
                        analyze_assembly_data(entity, cleaned_assembly_id, index)
                    end
                else
                    DebugTools.debug_log("Assembly ID         :  NOT FOUND")
                end
            else
                DebugTools.debug_log("Has assembly dict.  :  NO")
            end
            DebugTools.debug_log(". . . . . . . . . . . . . . . . . . . .")
            DebugTools.debug_log("---------------------------------------")
        end
    end
    # ------------------------------------------------------------

    # SUB FUNCTION | Analyze Assembly Data
    # ------------------------------------------------------------
    def self.analyze_assembly_data(entity, cleaned_assembly_id, index)
        return unless DebugTools.debug_mode?                                 # Exit if debug mode disabled
        
        DebugTools.debug_log(". . . . . . . . . . . . . . . . . . . .")
        DebugTools.debug_log("<SERIALIZER DIAGNOSTICS FOR #{cleaned_assembly_id}>")
        
        comp_def = entity.definition
        serializer_dict_name = "#{ValeDesignSuite::DataUtils::FrameworkDataSerializer::DICTIONARY_PREFIX}#{cleaned_assembly_id}"
        serializer_dict = comp_def.attribute_dictionary(serializer_dict_name)
        
        DebugTools.debug_log(". . . . . . . . . . . . . . . . . . . .")
        DebugTools.debug_log("<ITEM #{format('%02d', index + 1)} SERIALISED DATA AS SAVED IN THE ATTRIBUTE DICTIONARY>")
        if serializer_dict
            DebugTools.debug_log("Raw data from dictionary: '#{serializer_dict_name}' on definition '#{comp_def.name}':")
            metadata_raw = serializer_dict[ValeDesignSuite::DataUtils::FrameworkDataSerializer::METADATA_KEY]
            nodes_raw = serializer_dict[ValeDesignSuite::DataUtils::FrameworkDataSerializer::NODES_KEY]
            panel_lines_raw = serializer_dict[ValeDesignSuite::DataUtils::FrameworkDataSerializer::PANEL_LINES_KEY]
            
            DebugTools.debug_log("  \"#{ValeDesignSuite::DataUtils::FrameworkDataSerializer::METADATA_KEY}\": #{metadata_raw.inspect}")
            DebugTools.debug_log("  \"#{ValeDesignSuite::DataUtils::FrameworkDataSerializer::NODES_KEY}\": #{nodes_raw.inspect}")
            DebugTools.debug_log("  \"#{ValeDesignSuite::DataUtils::FrameworkDataSerializer::PANEL_LINES_KEY}\": #{panel_lines_raw.inspect}")
        else
            DebugTools.debug_log("No serializer dictionary ('#{serializer_dict_name}') found on definition '#{comp_def.name}'.")
        end
        
        analyze_reconstructed_data(cleaned_assembly_id, index)
    end
    # ------------------------------------------------------------

    # SUB FUNCTION | Analyze Reconstructed Data
    # ------------------------------------------------------------
    def self.analyze_reconstructed_data(cleaned_assembly_id, index)
        return unless DebugTools.debug_mode?                                 # Exit if debug mode disabled
        
        DebugTools.debug_log(". . . . . . . . . . . . . . . . . . . .")
        DebugTools.debug_log("<ITEM #{format('%02d', index + 1)} RECONSTRUCTED DATA (AS JSON OBJECT)>")
        
        original_stdout = $stdout
        $stdout = StringIO.new
        
        loaded_data_hash = ValeDesignSuite::DataUtils::FrameworkDataSerializer.load_assembly_data(cleaned_assembly_id)
        
        $stdout = original_stdout
        
        if loaded_data_hash
            if loaded_data_hash[ValeDesignSuite::DataUtils::FrameworkDataSerializer::METADATA_KEY]&.is_a?(Array) &&
               !loaded_data_hash[ValeDesignSuite::DataUtils::FrameworkDataSerializer::METADATA_KEY].empty? &&
               loaded_data_hash[ValeDesignSuite::DataUtils::FrameworkDataSerializer::METADATA_KEY][0]['FrameworkUniqueId'] != cleaned_assembly_id
                
                DebugTools.debug_log("  NOTE: Corrected 'FrameworkUniqueId' in loaded data to match AssemblyID ('#{cleaned_assembly_id}'). This ensures data integrity if there was a mismatch.")
                loaded_data_hash[ValeDesignSuite::DataUtils::FrameworkDataSerializer::METADATA_KEY][0]['FrameworkUniqueId'] = cleaned_assembly_id
            end
            DebugTools.debug_log("```json")
            DebugTools.debug_log(JSON.pretty_generate(loaded_data_hash))
            DebugTools.debug_log("```")
            
            analyze_nodes_data(loaded_data_hash, index)
            analyze_panels_data(loaded_data_hash, index)
            analyze_metadata(loaded_data_hash, index)
        else
            DebugTools.debug_log("Could not load/reconstruct data for Assembly ID '#{cleaned_assembly_id}' via serializer.")
        end
    end
    # ------------------------------------------------------------

    # SUB FUNCTION | Analyze Nodes Data
    # ------------------------------------------------------------
    def self.analyze_nodes_data(loaded_data_hash, index)
        return unless DebugTools.debug_mode?                                 # Exit if debug mode disabled
        
        DebugTools.debug_log(". . . . . . . . . . . . . . . . . . . .")
        DebugTools.debug_log("<ITEM #{format('%02d', index + 1)} DETAILED NODE DICTIONARIES BREAKDOWN>")
        
        nodes_data = loaded_data_hash[ValeDesignSuite::DataUtils::FrameworkDataSerializer::NODES_KEY]
        if nodes_data && nodes_data.is_a?(Array) && !nodes_data.empty?
            DebugTools.debug_log("Total Nodes Found: #{nodes_data.size}")
            DebugTools.debug_log("----------------------------------------")
            
            nodes_data.each_with_index do |node, node_index|
                DebugTools.debug_log("NODE #{format('%02d', node_index + 1)} | #{node['NodeUniqueId'] || 'NO_ID'}")
                DebugTools.debug_log("  Node Name           : #{node['NodeName'] || 'N/A'}")
                DebugTools.debug_log("  Node Type           : #{node['NodeType'] || 'N/A'}")
                DebugTools.debug_log("  Node Style          : #{node['NodeStyle'] || 'N/A'}")
                DebugTools.debug_log("  Node Notes          : #{node['NodeNotes'] || 'N/A'}")
                DebugTools.debug_log("  Canvas Position     : X=#{node['x'] || 'N/A'}, Y=#{node['y'] || 'N/A'}")
                DebugTools.debug_log("  Model Position      : X=#{node['NodePosX'] || 'N/A'}, Y=#{node['NodePosY'] || 'N/A'}, Z=#{node['NodePosZ'] || 'N/A'}")
                DebugTools.debug_log("  Node Dimensions     : X=#{node['NodeSizeX'] || 'N/A'}, Y=#{node['NodeSizeY'] || 'N/A'}, Z=#{node['NodeSizeZ'] || 'N/A'}")
                DebugTools.debug_log("  Head Height         : #{node['NodeHeadHeight'] || 'N/A'}")
                DebugTools.debug_log("  Cill Height         : #{node['NodeUsCillHeight'] || 'N/A'}")
                DebugTools.debug_log("  Rotation (XYZW)     : X=#{node['NodeRotationX'] || 'N/A'}, Y=#{node['NodeRotationY'] || 'N/A'}, Z=#{node['NodeRotationZ'] || 'N/A'}, W=#{node['NodeRotationW'] || 'N/A'}")
                
                standard_keys = ['NodeUniqueId', 'NodeName', 'NodeType', 'NodeStyle', 'NodeNotes', 'x', 'y', 
                               'NodePosX', 'NodePosY', 'NodePosZ', 'NodeSizeX', 'NodeSizeY', 'NodeSizeZ',
                               'NodeHeadHeight', 'NodeUsCillHeight', 'NodeRotationX', 'NodeRotationY', 'NodeRotationZ', 'NodeRotationW']
                additional_keys = node.keys - standard_keys
                if additional_keys.any?
                    DebugTools.debug_log("  Additional Properties:")
                    additional_keys.each do |key|
                        DebugTools.debug_log("    #{key} : #{node[key]}")
                    end
                end
                DebugTools.debug_log("  ----------------------------------------")
            end
        else
            DebugTools.debug_log("No nodes found or nodes data is invalid.")
        end
    end
    # ------------------------------------------------------------

    # SUB FUNCTION | Analyze Panels Data
    # ------------------------------------------------------------
    def self.analyze_panels_data(loaded_data_hash, index)
        return unless DebugTools.debug_mode?                                 # Exit if debug mode disabled
        
        DebugTools.debug_log(". . . . . . . . . . . . . . . . . . . .")
        DebugTools.debug_log("<ITEM #{format('%02d', index + 1)} DETAILED PANEL DICTIONARIES BREAKDOWN>")
        
        panels_data = loaded_data_hash[ValeDesignSuite::DataUtils::FrameworkDataSerializer::PANEL_LINES_KEY]
        if panels_data && panels_data.is_a?(Array) && !panels_data.empty?
            DebugTools.debug_log("Total Panels Found: #{panels_data.size}")
            DebugTools.debug_log("----------------------------------------")
            
            panels_data.each_with_index do |panel, panel_index|
                DebugTools.debug_log("PANEL #{format('%02d', panel_index + 1)} | #{panel['PanelUniqueId'] || 'NO_ID'}")
                DebugTools.debug_log("  Panel Name          : #{panel['PanelName'] || 'N/A'}")
                DebugTools.debug_log("  Panel Type          : #{panel['PanelType'] || 'N/A'}")
                DebugTools.debug_log("  Panel Style         : #{panel['PanelStyle'] || 'N/A'}")
                DebugTools.debug_log("  Panel Notes         : #{panel['PanelNotes'] || 'N/A'}")
                DebugTools.debug_log("  Connection          : From=#{panel['from_node_id'] || 'N/A'} → To=#{panel['to_node_id'] || 'N/A'}")
                DebugTools.debug_log("  Panel Length        : #{panel['length_mm'] || 'N/A'} mm")
                DebugTools.debug_log("  Divisions           : X=#{panel['PanelDivisionsX'] || 'N/A'}, Y=#{panel['PanelDivisionsY'] || 'N/A'}")
                DebugTools.debug_log("  Model Position      : X=#{panel['PanelPosX'] || 'N/A'}, Y=#{panel['PanelPosY'] || 'N/A'}, Z=#{panel['PanelPosZ'] || 'N/A'}")
                DebugTools.debug_log("  Panel Dimensions    : X=#{panel['PanelSizeX'] || 'N/A'}, Y=#{panel['PanelSizeY'] || 'N/A'}, Z=#{panel['PanelSizeZ'] || 'N/A'}")
                DebugTools.debug_log("  Head Height         : #{panel['PanelHeadHeight'] || 'N/A'}")
                DebugTools.debug_log("  Cill Height         : #{panel['PanelUsCillHeight'] || 'N/A'}")
                DebugTools.debug_log("  Rotation (XYZW)     : X=#{panel['PanelRotationX'] || 'N/A'}, Y=#{panel['PanelRotationY'] || 'N/A'}, Z=#{panel['PanelRotationZ'] || 'N/A'}, W=#{panel['PanelRotationW'] || 'N/A'}")
                
                standard_keys = ['PanelUniqueId', 'PanelName', 'PanelType', 'PanelStyle', 'PanelNotes', 
                               'from_node_id', 'to_node_id', 'length_mm', 'PanelDivisionsX', 'PanelDivisionsY',
                               'PanelPosX', 'PanelPosY', 'PanelPosZ', 'PanelSizeX', 'PanelSizeY', 'PanelSizeZ',
                               'PanelHeadHeight', 'PanelUsCillHeight', 'PanelRotationX', 'PanelRotationY', 'PanelRotationZ', 'PanelRotationW']
                additional_keys = panel.keys - standard_keys
                if additional_keys.any?
                    DebugTools.debug_log("  Additional Properties:")
                    additional_keys.each do |key|
                        DebugTools.debug_log("    #{key} : #{panel[key]}")
                    end
                end
                DebugTools.debug_log("  ----------------------------------------")
            end
        else
            DebugTools.debug_log("No panels found or panels data is invalid.")
        end
    end
    # ------------------------------------------------------------

    # SUB FUNCTION | Analyze Metadata
    # ------------------------------------------------------------
    def self.analyze_metadata(loaded_data_hash, index)
        return unless DebugTools.debug_mode?                                 # Exit if debug mode disabled
        
        DebugTools.debug_log(". . . . . . . . . . . . . . . . . . . .")
        DebugTools.debug_log("<ITEM #{format('%02d', index + 1)} FRAMEWORK METADATA BREAKDOWN>")
        
        metadata = loaded_data_hash[ValeDesignSuite::DataUtils::FrameworkDataSerializer::METADATA_KEY]
        if metadata && metadata.is_a?(Array) && !metadata.empty?
            DebugTools.debug_log("Framework Metadata Found: #{metadata.size} entries")
            DebugTools.debug_log("----------------------------------------")
            
            metadata.each_with_index do |meta, meta_index|
                DebugTools.debug_log("METADATA #{format('%02d', meta_index + 1)}")
                DebugTools.debug_log("  Framework Unique ID : #{meta['FrameworkUniqueId'] || 'N/A'}")
                DebugTools.debug_log("  Framework Name      : #{meta['FrameworkName'] || 'N/A'}")
                DebugTools.debug_log("  Framework Notes     : #{meta['FrameworkNotes'] || 'N/A'}")
                DebugTools.debug_log("  Framework Length    : #{meta['FrameworkLength'] || 'N/A'}")
                DebugTools.debug_log("  Framework Width     : #{meta['FrameworkWidth'] || 'N/A'}")
                DebugTools.debug_log("  Framework Height    : #{meta['FrameworkHeight'] || 'N/A'}")
                
                standard_keys = ['FrameworkUniqueId', 'FrameworkName', 'FrameworkNotes', 
                               'FrameworkLength', 'FrameworkWidth', 'FrameworkHeight']
                additional_keys = meta.keys - standard_keys
                if additional_keys.any?
                    DebugTools.debug_log("  Additional Properties:")
                    additional_keys.each do |key|
                        DebugTools.debug_log("    #{key} : #{meta[key]}")
                    end
                end
                DebugTools.debug_log("  ----------------------------------------")
            end
        else
            DebugTools.debug_log("No framework metadata found or metadata is invalid.")
        end
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Main Report Generation
# -----------------------------------------------------------------------------

    # FUNCTION | Generate Comprehensive Report
    # ------------------------------------------------------------
    def self.generate_comprehensive_report(model, selection)
        return unless DebugTools.debug_mode?                                 # Exit if debug mode disabled
        
        DebugTools.debug_log("")                                             # Two line breaks for separation
        DebugTools.debug_log("")
        check_model_level_dictionaries(model)
        check_framework_assemblies_in_definitions(model)
        check_selected_component_dictionaries(selection)
        DebugTools.debug_log("")                                             # Two line breaks for separation
        DebugTools.debug_log("")
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module FrameworkToolsDebugTools
  end # module Tools
end # module ValeDesignSuite

# =============================================================================
# END OF FILE
# ============================================================================= 