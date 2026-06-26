# =============================================================================
# VALEDESIGNSUITE - FRAMEWORK COORDINATION MANAGER
# =============================================================================
#
# FILE       : ValeDesignSuite_Tools_FrameworkCoordinationManager.rb
# NAMESPACE  : ValeDesignSuite::Tools
# MODULE     : FrameworkCoordinationManager
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Coordinate transformation and positioning for framework components
# CREATED    : 2025
#
# DESCRIPTION:
# - This module manages coordinate transformations between framework canvas and 3D model space.
# - It handles positioning of nodes and panels within framework assemblies.
# - Provides real-time update coordination for framework geometry.
# - Manages transform caches for efficient incremental updates.
# - Synchronizes positions when framework data changes.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 27-Jan-2025 - Version 1.0.0
# - Initial implementation of coordination manager
# - Transform cache system implemented
# - Real-time update triggers added
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative 'ValeDesignSuite_Tools_FrameworkDebugTools'

module ValeDesignSuite
  module Tools
    module FrameworkCoordinationManager

# -----------------------------------------------------------------------------
# REGION | Module Constants and Configuration
# -----------------------------------------------------------------------------

    # DEBUG TOOLS REFERENCE
    # ------------------------------------------------------------
    DebugTools = ValeDesignSuite::Tools::FrameworkDebugTools

    # MODULE CONSTANTS | Conversion and Timing
    # ------------------------------------------------------------
    MM_TO_INCH                  =   1.0 / 25.4                                    # <-- Millimeter to inch conversion factor
    REALTIME_UPDATE_DELAY       =   0.5                                          # <-- Delay in seconds for real-time updates
    MIN_UPDATE_INTERVAL         =   0.1                                          # <-- Minimum time between updates
    # endregion ----------------------------------------------------

    # MODULE VARIABLES | State Management
    # ------------------------------------------------------------
    @active_framework_component =   nil                                          # <-- Current framework component
    @transform_cache            =   {}                                           # <-- Cache of coordinate transformations
    @last_update_time           =   0                                            # <-- Time of last update
    @update_timer               =   nil                                          # <-- Timer for delayed updates
    @transform_cache_dirty      =   true                                         # <-- Flag indicating cache needs refresh
    # endregion ----------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Initialization and Setup
# -----------------------------------------------------------------------------

    # FUNCTION | Initialize Coordination Manager for Framework Assembly
    # ------------------------------------------------------------
    def self.initialize_for_framework_assembly(framework_component)
        return false unless framework_component && framework_component.valid?    # <-- Validate framework component
        
        @active_framework_component = framework_component                        # <-- Set active framework component
        @transform_cache = {}                                                    # <-- Reset transform cache
        @transform_cache_dirty = true                                            # <-- Mark cache as dirty
        
        DebugTools.debug_log("Initialized coordination manager for framework assembly")
        return true                                                              # <-- Return success
    end
    # ---------------------------------------------------------------

    # FUNCTION | Mark Transform Cache as Dirty
    # ------------------------------------------------------------
    def self.mark_transform_cache_dirty
        @transform_cache_dirty = true                                            # <-- Mark cache as needing refresh
        DebugTools.debug_log("Transform cache marked as dirty")
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Coordinate Transformation Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Get Coordinate Transformation for Component
    # ------------------------------------------------------------
    def self.get_coordinate_transformation(component_id)
        # Rebuild cache if dirty
        rebuild_transform_cache if @transform_cache_dirty                        # <-- Rebuild if needed
        
        # Return cached transformation
        return @transform_cache[component_id]                                    # <-- Return transformation data
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Rebuild Transform Cache
    # ---------------------------------------------------------------
    def self.rebuild_transform_cache
        return unless @active_framework_component                                # <-- Validate component exists
        
        DebugTools.debug_log("Rebuilding transform cache")
        @transform_cache = {}                                                    # <-- Clear existing cache
        
        # Load framework data
        framework_data = load_framework_data_for_component                       # <-- Load current data
        return unless framework_data                                             # <-- Return if no data
        
        # Process nodes
        nodes = framework_data["frameworkNodes"] || []
        nodes.each do |node_data|
            node_id = node_data["NodeUniqueId"]
            next unless node_id                                                  # <-- Skip if no ID
            
            # Calculate model coordinates from canvas coordinates
            canvas_x = node_data["x"] || node_data["NodePosX"] || 0
            canvas_y = node_data["y"] || node_data["NodePosY"] || 0
            
            # Transform canvas to model coordinates
            model_x = canvas_x.mm                                               # <-- Canvas X to model X (mm to inches)
            model_y = 0.mm                                                      # <-- Framework Y is always 0
            model_z = 0.mm                                                      # <-- Framework Z starts at ground
            
            @transform_cache[node_id] = {
                canvas: { x: canvas_x, y: canvas_y },
                model: { x: model_x, y: model_y, z: model_z }
            }
        end
        
        # Process panels
        panels = framework_data["frameworkPanelLines"] || []
        panels.each do |panel_data|
            panel_id = panel_data["PanelUniqueId"]
            next unless panel_id                                                 # <-- Skip if no ID
            
            # Get connected nodes
            from_node_id = panel_data["from_node_id"]
            to_node_id = panel_data["to_node_id"]
            
            # Find node positions
            from_node = nodes.find { |n| n["NodeUniqueId"] == from_node_id }
            to_node = nodes.find { |n| n["NodeUniqueId"] == to_node_id }
            
            if from_node && to_node
                # Calculate panel position (at from node's right edge)
                from_node_x = from_node["x"] || 0
                from_node_width = from_node["NodeSizeX"] || 290
                
                panel_x = from_node_x + from_node_width                         # <-- Panel starts at node's right edge
                
                # Transform to model coordinates
                model_x = panel_x.mm                                            # <-- Convert to model units
                model_y = 0.mm                                                  # <-- Framework Y is always 0
                model_z = 0.mm                                                  # <-- Framework Z starts at ground
                
                @transform_cache[panel_id] = {
                    canvas: { x: panel_x, y: 0 },
                    model: { x: model_x, y: model_y, z: model_z }
                }
            end
        end
        
        @transform_cache_dirty = false                                           # <-- Mark cache as clean
        DebugTools.debug_log("Transform cache rebuilt with #{@transform_cache.size} entries")
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Load Framework Data for Component
    # ---------------------------------------------------------------
    def self.load_framework_data_for_component
        return nil unless @active_framework_component                            # <-- Validate component exists
        
        # Use the SketchUp logic module to load data
        require_relative 'ValeDesignSuite_Tools_FrameworkToolsSketchUpLogic'
        
        framework_data = ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic.load_framework_data_from_component(
            @active_framework_component.entityID
        )
        
        return framework_data                                                    # <-- Return loaded data
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Position Synchronization Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Synchronize Framework Positions
    # ------------------------------------------------------------
    def self.synchronize_framework_positions
        return unless @active_framework_component                                # <-- Validate component exists
        
        DebugTools.debug_log("Synchronizing framework positions")
        
        # Rebuild cache if needed
        rebuild_transform_cache if @transform_cache_dirty                        # <-- Ensure cache is current
        
        # Apply transformations to all components
        @transform_cache.each do |component_id, transform_data|
            apply_transformation_to_component(component_id, transform_data)      # <-- Apply each transformation
        end
        
        DebugTools.debug_log("Framework positions synchronized")
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Apply Transformation to Component
    # ---------------------------------------------------------------
    def self.apply_transformation_to_component(component_id, transform_data)
        return unless @active_framework_component && transform_data              # <-- Validate prerequisites
        
        model_coords = transform_data[:model]
        return unless model_coords                                               # <-- Validate model coordinates exist
        
        # Find the component group within the framework
        target_group = find_component_group(component_id)
        return unless target_group && target_group.valid?                       # <-- Validate group exists
        
        # Create transformation
        transformation = Geom::Transformation.new([
            model_coords[:x], 
            model_coords[:y], 
            model_coords[:z]
        ])
        
        # Apply transformation
        target_group.transformation = transformation                             # <-- Set group transformation
        
        DebugTools.debug_log("Applied transformation to #{component_id}")
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Find Component Group
    # ---------------------------------------------------------------
    def self.find_component_group(component_id)
        return nil unless @active_framework_component                            # <-- Validate component exists
        
        # Search through framework entities for matching group
        @active_framework_component.definition.entities.grep(Sketchup::Group).each do |group|
            if group.name && group.name.include?(component_id)
                return group                                                     # <-- Return matching group
            end
        end
        
        return nil                                                               # <-- Return nil if not found
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Real-time Update Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Trigger Real-time Update
    # ------------------------------------------------------------
    def self.trigger_realtime_update
        # Cancel existing timer if present
        if @update_timer
            UI.stop_timer(@update_timer)                                         # <-- Stop existing timer
            @update_timer = nil
        end
        
        # Check minimum update interval
        current_time = Time.now.to_f
        time_since_last = current_time - @last_update_time
        
        if time_since_last < MIN_UPDATE_INTERVAL
            # Schedule update after minimum interval
            delay = MIN_UPDATE_INTERVAL - time_since_last
            @update_timer = UI.start_timer(delay, false) do
                perform_realtime_update                                          # <-- Perform update after delay
            end
        else
            # Schedule update after standard delay
            @update_timer = UI.start_timer(REALTIME_UPDATE_DELAY, false) do
                perform_realtime_update                                          # <-- Perform update after delay
            end
        end
        
        DebugTools.debug_log("Real-time update scheduled")
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Perform Real-time Update
    # ---------------------------------------------------------------
    def self.perform_realtime_update
        @last_update_time = Time.now.to_f                                       # <-- Update last update time
        @update_timer = nil                                                      # <-- Clear timer reference
        
        # Mark cache as dirty and synchronize
        mark_transform_cache_dirty                                               # <-- Mark cache for rebuild
        synchronize_framework_positions                                          # <-- Synchronize positions
        
        DebugTools.debug_log("Real-time update performed")
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Interface Methods
# -----------------------------------------------------------------------------

    # FUNCTION | Get Current Framework Component
    # ------------------------------------------------------------
    def self.current_framework_component
        return @active_framework_component                                       # <-- Return active component
    end
    # ---------------------------------------------------------------

    # FUNCTION | Check if Coordination Manager is Active
    # ------------------------------------------------------------
    def self.active?
        return @active_framework_component && @active_framework_component.valid? # <-- Check if active and valid
    end
    # ---------------------------------------------------------------

    # FUNCTION | Clear Coordination Manager State
    # ------------------------------------------------------------
    def self.clear
        @active_framework_component = nil                                        # <-- Clear component reference
        @transform_cache = {}                                                    # <-- Clear transform cache
        @transform_cache_dirty = true                                            # <-- Mark cache as dirty
        
        # Cancel any pending updates
        if @update_timer
            UI.stop_timer(@update_timer)                                         # <-- Stop timer
            @update_timer = nil                                                  # <-- Clear timer reference
        end
        
        DebugTools.debug_log("Coordination manager state cleared")
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module FrameworkCoordinationManager
  end # module Tools
end # module ValeDesignSuite 