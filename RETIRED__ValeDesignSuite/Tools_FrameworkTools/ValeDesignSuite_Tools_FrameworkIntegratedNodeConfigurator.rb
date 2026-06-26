# =============================================================================
# VALEDESIGNSUITE - FRAMEWORK INTEGRATED NODE CONFIGURATOR
# =============================================================================
#
# FILE       : ValeDesignSuite_Tools_FrameworkIntegratedNodeConfigurator.rb
# NAMESPACE  : ValeDesignSuite::Tools
# MODULE     : FrameworkIntegratedNodeConfigurator
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Integrated Node Configurator for Framework System
# CREATED    : 2025
#
# DESCRIPTION:
# - This module integrates the node configurator with the framework configurator system.
# - It allows for configuration of individual nodes within framework assemblies.
# - Node dimensions and types can be configured through the framework interface.
# - Each node maintains its own configuration while being part of the framework assembly.
# - Supports clicking on individual nodes in the framework configurator for configuration.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 27-Jan-2025 - Version 1.0.0
# - Initial implementation of integrated node configurator
# - Framework node configuration support added
# - Individual node configuration within assemblies
#
# =============================================================================

require 'sketchup.rb'
require 'json'

# Require the NodeConfigurator from the same directory
require_relative 'ValeDesignSuite_Tools_FrameworkNodeConfigurator'
require_relative 'ValeDesignSuite_Tools_FrameworkDebugTools'

module ValeDesignSuite
  module Tools
    module FrameworkIntegratedNodeConfigurator

# -----------------------------------------------------------------------------
# REGION | Module Constants and Configuration
# -----------------------------------------------------------------------------

    # DEBUG TOOLS REFERENCE
    # ------------------------------------------------------------
    DebugTools = ValeDesignSuite::Tools::FrameworkDebugTools

    # MODULE CONSTANTS | Integration and Dictionary Keys
    # ------------------------------------------------------------
    INTEGRATED_NODE_DICT_NAME   =   "ValeDesignSuite_IntegratedNodes"            # <-- Dictionary for integrated node data
    NODE_CONFIG_KEY_PREFIX      =   "NodeConfig_"                               # <-- Prefix for node configuration keys
    FRAMEWORK_NODE_TYPE         =   "Framework_Node"                             # <-- Framework node type identifier
    # endregion ----------------------------------------------------

    # MODULE VARIABLES | Component References and State
    # ------------------------------------------------------------
    @active_framework_component =   nil                                          # <-- Current framework component
    @active_node_configs        =   {}                                           # <-- Hash of node ID to node config
    @framework_assembly_id      =   nil                                          # <-- Current framework assembly ID
    # endregion ----------------------------------------------------

    # MODULE CONSTANTS | Node Configuration Constants
    # ------------------------------------------------------------
    NODE_DICT_NAME          =   ValeDesignSuite::Tools::FrameworkNodeConfigurator::NODE_DICT_NAME      # <-- Use node configurator dictionary name
    MM_TO_INCH              =   ValeDesignSuite::Tools::FrameworkNodeConfigurator::MM_TO_INCH          # <-- Use node configurator conversion factor
    # endregion ----------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Framework Integration Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Initialize Node Configurator for Framework Assembly
    # ------------------------------------------------------------
    def self.initialize_for_framework_assembly(framework_component)
        return false unless framework_component && framework_component.valid?    # <-- Validate framework component
        
        @active_framework_component = framework_component                        # <-- Set active framework component
        @framework_assembly_id = get_assembly_id_from_component(framework_component)  # <-- Get assembly ID
        
        return false unless @framework_assembly_id                               # <-- Validate assembly ID exists
        
        load_existing_node_configurations                                        # <-- Load existing node configs
        return true                                                              # <-- Return success
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Get Assembly ID from Framework Component
    # ---------------------------------------------------------------
    def self.get_assembly_id_from_component(component)
        return nil unless component.is_a?(Sketchup::ComponentInstance)           # <-- Validate component type
        
        assembly_info_dict = component.attribute_dictionary(
            ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic::ASSEMBLY_INFO_DICT_NAME, 
            false
        )
        return nil unless assembly_info_dict                                     # <-- Return nil if no dictionary
        
        return assembly_info_dict[ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic::ASSEMBLY_ID_KEY]  # <-- Return assembly ID
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Load Existing Node Configurations
    # ---------------------------------------------------------------
    def self.load_existing_node_configurations
        return unless @active_framework_component && @framework_assembly_id      # <-- Validate prerequisites
        
        @active_node_configs = {}                                                # <-- Reset node configs
        
        # Get integrated node dictionary from component
        node_dict = @active_framework_component.attribute_dictionary(INTEGRATED_NODE_DICT_NAME, false)
        return unless node_dict                                                  # <-- Return if no node dictionary
        
        # Load each node configuration
        node_dict.each do |key, value|
            next unless key.start_with?(NODE_CONFIG_KEY_PREFIX)                  # <-- Skip non-node keys
            
            node_id = key.sub(NODE_CONFIG_KEY_PREFIX, "")                        # <-- Extract node ID
            
            begin
                node_config = JSON.parse(value)                                  # <-- Parse node configuration
                @active_node_configs[node_id] = node_config                      # <-- Store node configuration
            rescue JSON::ParserError => e
                DebugTools.debug_node("Error loading node config for #{node_id}: #{e.message}")  # <-- Log parsing errors
            end
        end
        
        DebugTools.debug_node("Loaded #{@active_node_configs.size} node configurations for assembly #{@framework_assembly_id}")
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Node Configuration Management
# -----------------------------------------------------------------------------

    # FUNCTION | Configure Node from Framework Node Data
    # ------------------------------------------------------------
    def self.configure_node_from_framework_data(node_data)
        return nil unless node_data && node_data.is_a?(Hash)                     # <-- Validate node data
        return nil unless @active_framework_component && @framework_assembly_id  # <-- Validate framework context
        
        node_id = node_data["NodeUniqueId"]                                      # <-- Get node unique ID
        return nil unless node_id                                                # <-- Validate node ID exists
        
        # Extract node dimensions and type from framework data
        node_width_mm = node_data["NodeSizeX"] || 290                            # <-- Get node width
        node_depth_mm = node_data["NodeSizeY"] || 94                             # <-- Get node depth
        node_height_mm = node_data["NodeSizeZ"] || 2000                          # <-- Get node height
        node_type = node_data["NodeType"] || "Column_290mm"                      # <-- Get node type
        node_material = node_data["NodeMaterial"] || "natural-wood"              # <-- Get node material
        
        # Create node configuration using FrameworkNodeConfigurator format
        node_config = ValeDesignSuite::Tools::FrameworkNodeConfigurator.prepare_config_for_creation(
            node_width_mm, 
            node_depth_mm, 
            node_height_mm, 
            node_type, 
            node_material
        )
        
        # Update metadata with framework context
        if node_config["nodeMetadata"] && node_config["nodeMetadata"][0]
            node_config["nodeMetadata"][0]["NodeUniqueId"] = node_id            # <-- Set specific node ID
            node_config["nodeMetadata"][0]["NodeName"] = node_data["NodeName"] || "FrameworkNode_#{node_id}"
            node_config["nodeMetadata"][0]["NodeDescription"] = "Node integrated with framework assembly #{@framework_assembly_id}"
            node_config["nodeMetadata"][0]["NodeNotes"] = node_data["NodeNotes"] || ""
        end
        
        # Update component IDs with node ID
        ValeDesignSuite::Tools::FrameworkNodeConfigurator.update_component_ids_with_node_id(node_config, node_id)
        
        # Store configuration
        @active_node_configs[node_id] = node_config                              # <-- Store node configuration
        save_node_configuration(node_id, node_config)                           # <-- Save to component dictionary
        
        return node_config                                                       # <-- Return created configuration
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Save Node Configuration to Component Dictionary
    # ---------------------------------------------------------------
    def self.save_node_configuration(node_id, config)
        return unless @active_framework_component && node_id && config           # <-- Validate prerequisites
        
        # Get or create integrated node dictionary
        node_dict = @active_framework_component.attribute_dictionary(INTEGRATED_NODE_DICT_NAME, true)
        
        # Save configuration as JSON string
        config_key = "#{NODE_CONFIG_KEY_PREFIX}#{node_id}"                       # <-- Create configuration key
        node_dict[config_key] = JSON.generate(config)                           # <-- Save configuration as JSON
        
        DebugTools.debug_node("Saved node configuration for #{node_id} in framework assembly #{@framework_assembly_id}")
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Node Geometry Creation and Update
# -----------------------------------------------------------------------------

    # FUNCTION | Update or Create Framework Node Geometry
    # ------------------------------------------------------------
    def self.update_or_create_framework_node_geometry(node_id, node_config)
        return unless @active_framework_component && node_config                 # <-- Validate prerequisites
        
        # Check if node already exists within the framework
        existing_node_group = find_existing_node_group(node_id)
        
        if existing_node_group && existing_node_group.valid?
            # Update existing node group
            update_existing_framework_node_group(existing_node_group, node_config)
            DebugTools.debug_node("Updated existing node group for node #{node_id}")
        else
            # Create new node group within framework
            node_group = create_framework_node_group(node_id, node_config)
            DebugTools.debug_node("Created new node group for node #{node_id}")
        end
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Find Existing Node Group
    # ---------------------------------------------------------------
    def self.find_existing_node_group(node_id)
        return nil unless @active_framework_component                            # <-- Validate framework component
        
        # Search through the framework component's entities for a node group
        @active_framework_component.definition.entities.grep(Sketchup::Group).each do |group|
            if group.name && group.name.include?(node_id) && group.name.include?("Node")
                return group                                                     # <-- Return matching node group
            end
        end
        
        return nil                                                               # <-- Return nil if not found
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Update Existing Framework Node Group
    # ---------------------------------------------------------------
    def self.update_existing_framework_node_group(node_group, node_config)
        return unless node_group && node_group.valid? && node_config            # <-- Validate prerequisites
        
        model = Sketchup.active_model
        model.start_operation("Update Framework Node", true)                    # <-- Start operation
        
        begin
            # Clear existing geometry in the group
            node_group.entities.clear!                                          # <-- Clear existing entities
            
            # Create new node geometry within the group
            ValeDesignSuite::Tools::FrameworkNodeConfigurator.create_all_node_subcomponents(node_group, node_config)
            
            # Apply materials
            node_config_obj = node_config["nodeConfiguration"]
            material = node_config_obj["Component_Default_Material"] || "natural-wood"
            ValeDesignSuite::Tools::FrameworkNodeConfigurator.add_materials(node_group.entities, material)
            
            # Save configuration to group
            save_node_configuration_to_group(node_group, node_config)
            
            model.commit_operation                                               # <-- Commit operation
            DebugTools.debug_node("Successfully updated node group geometry")
            
        rescue => e
            model.abort_operation                                                # <-- Abort on error
            DebugTools.debug_node("Error updating node group: #{e.message}")
            DebugTools.debug_node(e.backtrace.join("\n"))
        end
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create Framework Node Group
    # ---------------------------------------------------------------
    def self.create_framework_node_group(node_id, node_config)
        return nil unless @active_framework_component && node_config             # <-- Validate prerequisites
        
        model = Sketchup.active_model
        model.start_operation("Create Framework Node", true)                     # <-- Start operation
        
        begin
            # Create node group within framework component definition
            node_group = @active_framework_component.definition.entities.add_group
            node_group.name = "#{node_id}_Node"                                 # <-- Set descriptive name
            
            # Create node geometry within the group
            ValeDesignSuite::Tools::FrameworkNodeConfigurator.create_all_node_subcomponents(node_group, node_config)
            
            # Apply materials
            node_config_obj = node_config["nodeConfiguration"]
            material = node_config_obj["Component_Default_Material"] || "natural-wood"
            ValeDesignSuite::Tools::FrameworkNodeConfigurator.add_materials(node_group.entities, material)
            
            # Position node group based on framework data
            position_node_group_in_framework(node_id, node_group, node_config)
            
            # Save configuration to group
            save_node_configuration_to_group(node_group, node_config)
            
            model.commit_operation                                               # <-- Commit operation
            DebugTools.debug_node("Successfully created node group for node #{node_id}")
            return node_group                                                    # <-- Return created group
            
        rescue => e
            model.abort_operation                                                # <-- Abort on error
            DebugTools.debug_node("Error creating node group: #{e.message}")
            DebugTools.debug_node(e.backtrace.join("\n"))
            return nil                                                           # <-- Return nil on error
        end
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Position Node Group in Framework
    # ---------------------------------------------------------------
    def self.position_node_group_in_framework(node_id, node_group, node_config)
        return unless @active_framework_component && node_group                  # <-- Validate prerequisites
        
        # Get position from node configuration
        if node_config["nodeComponents"] && node_config["nodeComponents"][0]
            position_data = node_config["nodeComponents"][0]["Position"]
            
            if position_data
                # Convert millimeters to model units (inches)
                x = (position_data["PosX_mm"] || 0) * MM_TO_INCH
                y = (position_data["PosY_mm"] || 0) * MM_TO_INCH
                z = (position_data["PosZ_mm"] || 0) * MM_TO_INCH
                
                transformation = Geom::Transformation.new([x, y, z])
                node_group.transformation = transformation
                
                DebugTools.debug_node("Positioned node group for #{node_id} at (#{position_data["PosX_mm"]}, #{position_data["PosY_mm"]}, #{position_data["PosZ_mm"]}) mm")
            end
        end
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Save Node Configuration to Group
    # ---------------------------------------------------------------
    def self.save_node_configuration_to_group(node_group, node_config)
        return unless node_group && node_group.valid? && node_config            # <-- Validate prerequisites
        
        # Save configuration directly to the node group
        dict = node_group.attribute_dictionary(NODE_DICT_NAME, true)
        config_json = JSON.generate(node_config)
        dict["node_config"] = config_json
        dict["node_config_formatted"] = JSON.pretty_generate(node_config)
        
        DebugTools.debug_node("Saved node configuration to group")
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Node Interaction and UI Integration
# -----------------------------------------------------------------------------

    # FUNCTION | Handle Node Click from Framework Configurator
    # ------------------------------------------------------------
    def self.handle_node_click(node_id, framework_component = nil)
        # Initialize for framework if component provided
        if framework_component
            success = initialize_for_framework_assembly(framework_component)     # <-- Initialize framework context
            return false unless success                                          # <-- Return false if initialization failed
        end
        
        return false unless @active_framework_component && @framework_assembly_id  # <-- Validate framework context
        
        # Load existing configuration or create new one
        node_config = @active_node_configs[node_id]
        
        unless node_config
            # Create default configuration for this node
            DebugTools.debug_node("No existing config for node #{node_id}, creating default")
            node_config = configure_node_from_framework_data({
                "NodeUniqueId" => node_id,
                "NodeName" => "Node #{node_id}",
                "NodeSizeX" => 290,
                "NodeSizeY" => 94,
                "NodeSizeZ" => 2000,
                "NodeType" => "Column_290mm"
            })
        end
        
        return false unless node_config                                          # <-- Validate configuration created
        
        # Show node configurator dialog
        show_node_configurator_for_framework(node_id, node_config)              # <-- Show configurator dialog
        
        return true                                                              # <-- Return success
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Show Node Configurator for Framework Context
    # ---------------------------------------------------------------
    def self.show_node_configurator_for_framework(node_id, node_config)
        # For now, we'll use the standard node configurator
        # In the future, this could be a specialized dialog for framework nodes
        ValeDesignSuite::Tools::FrameworkNodeConfigurator.init
        
        # Set the configuration in the node configurator
        if ValeDesignSuite::Tools::FrameworkNodeConfigurator.respond_to?(:set_node_component)
            # Find the actual node group if it exists
            node_group = find_existing_node_group(node_id)
            if node_group
                ValeDesignSuite::Tools::FrameworkNodeConfigurator.set_node_component(node_group, node_config)
            end
        end
        
        DebugTools.debug_node("Opened node configurator for framework node #{node_id}")
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Interface Methods
# -----------------------------------------------------------------------------

    # FUNCTION | Get Node Configuration for Node ID
    # ------------------------------------------------------------
    def self.get_node_configuration(node_id)
        return @active_node_configs[node_id] if @active_node_configs.key?(node_id)  # <-- Return existing config
        return nil                                                               # <-- Return nil if not found
    end
    # ---------------------------------------------------------------

    # FUNCTION | Check if Framework Component has Integrated Nodes
    # ------------------------------------------------------------
    def self.has_integrated_nodes?(framework_component)
        return false unless framework_component && framework_component.valid?    # <-- Validate component
        
        node_dict = framework_component.attribute_dictionary(INTEGRATED_NODE_DICT_NAME, false)
        return false unless node_dict                                            # <-- Return false if no dictionary
        
        # Check if any node configurations exist
        node_dict.each do |key, value|
            return true if key.start_with?(NODE_CONFIG_KEY_PREFIX)               # <-- Return true if node configs found
        end
        
        return false                                                             # <-- Return false if no node configs
    end
    # ---------------------------------------------------------------

    # FUNCTION | List All Node IDs for Framework Component
    # ---------------------------------------------------------------
    def self.list_node_ids_for_framework(framework_component)
        return [] unless framework_component && framework_component.valid?       # <-- Return empty array if invalid
        
        node_dict = framework_component.attribute_dictionary(INTEGRATED_NODE_DICT_NAME, false)
        return [] unless node_dict                                               # <-- Return empty array if no dictionary
        
        node_ids = []                                                            # <-- Initialize node IDs array
        node_dict.each do |key, value|
            if key.start_with?(NODE_CONFIG_KEY_PREFIX)                           # <-- Check if node configuration key
                node_id = key.sub(NODE_CONFIG_KEY_PREFIX, "")                    # <-- Extract node ID
                node_ids << node_id                                              # <-- Add to node IDs array
            end
        end
        
        return node_ids                                                          # <-- Return node IDs array
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module FrameworkIntegratedNodeConfigurator
  end # module Tools
end # module ValeDesignSuite 