# =============================================================================
# VALEDESIGNSUITE - FRAMEWORK DEBUG TOOLS
# =============================================================================
#
# FILE       : ValeDesignSuite_Tools_FrameworkDebugTools.rb
# NAMESPACE  : ValeDesignSuite::Tools
# MODULE     : FrameworkDebugTools
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Simplified Debug Logging for Framework Tools
# CREATED    : 26-May-2025
#
# DESCRIPTION:
# - Provides simplified debug logging functions for framework tools
# - Wraps the core debug configuration for easy access
# - Offers convenient debug methods without namespace complexity
# - Manages framework-specific debug output
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 26-May-2025 - Version 1.0.0
# - Initial Release
# - Simplified debug wrapper implementation
#
# =============================================================================

require 'sketchup'
require_relative '../Config_PluginConfigFiles/ValeDesignSuite_Core_DebugConfiguration'

module ValeDesignSuite
  module Tools
    module FrameworkDebugTools

# -----------------------------------------------------------------------------
# REGION | Debug Configuration Shortcuts
# -----------------------------------------------------------------------------

    # MODULE REFERENCE | Link to Debug Configuration
    # ------------------------------------------------------------
    DebugConfig = ValeDesignSuite::Config::DebugConfiguration               # <-- Reference to debug configuration
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Framework-Specific Debug Constants
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Debug Prefixes
    # ------------------------------------------------------------
    PREFIX_FRAMEWORK    =   "FW"                                             # <-- Framework general prefix
    PREFIX_NODE         =   "NODE"                                           # <-- Node operations prefix
    PREFIX_PANEL        =   "PANEL"                                          # <-- Panel operations prefix
    PREFIX_ASSEMBLY     =   "ASSEMBLY"                                       # <-- Assembly operations prefix
    PREFIX_SERIALIZER   =   "SERIAL"                                         # <-- Serializer operations prefix
    PREFIX_UI           =   "UI"                                             # <-- UI operations prefix
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Simplified Debug Logging Functions
# -----------------------------------------------------------------------------

    # FUNCTION | General Debug Log
    # ------------------------------------------------------------
    def self.debug_log(message)
        DebugConfig.debug_log(message, PREFIX_FRAMEWORK)                     # Log with framework prefix
    end
    # ---------------------------------------------------------------

    # FUNCTION | Node Operations Debug Log
    # ------------------------------------------------------------
    def self.debug_node(message)
        DebugConfig.debug_log(message, PREFIX_NODE)                          # Log with node prefix
    end
    # ---------------------------------------------------------------

    # FUNCTION | Panel Operations Debug Log
    # ------------------------------------------------------------
    def self.debug_panel(message)
        DebugConfig.debug_log(message, PREFIX_PANEL)                         # Log with panel prefix
    end
    # ---------------------------------------------------------------

    # FUNCTION | Assembly Operations Debug Log
    # ------------------------------------------------------------
    def self.debug_assembly(message)
        DebugConfig.debug_log(message, PREFIX_ASSEMBLY)                      # Log with assembly prefix
    end
    # ---------------------------------------------------------------

    # FUNCTION | Serializer Operations Debug Log
    # ------------------------------------------------------------
    def self.debug_serializer(message)
        DebugConfig.debug_log(message, PREFIX_SERIALIZER)                    # Log with serializer prefix
    end
    # ---------------------------------------------------------------

    # FUNCTION | UI Operations Debug Log
    # ------------------------------------------------------------
    def self.debug_ui(message)
        DebugConfig.debug_log(message, PREFIX_UI)                            # Log with UI prefix
    end
    # ---------------------------------------------------------------

    # FUNCTION | Error Debug Log
    # ------------------------------------------------------------
    def self.debug_error(message, error = nil)
        DebugConfig.debug_error(message, error)                              # Pass to debug config
    end
    # ---------------------------------------------------------------

    # FUNCTION | Warning Debug Log
    # ------------------------------------------------------------
    def self.debug_warn(message)
        DebugConfig.debug_warn(message)                                      # Pass to debug config
    end
    # ---------------------------------------------------------------

    # FUNCTION | Info Debug Log
    # ------------------------------------------------------------
    def self.debug_info(message)
        DebugConfig.debug_info(message)                                      # Pass to debug config
    end
    # ---------------------------------------------------------------

    # FUNCTION | Method Entry Debug Log
    # ------------------------------------------------------------
    def self.debug_method(method_name, params = nil)
        DebugConfig.debug_method(method_name, params)                        # Pass to debug config
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Debug Mode Control Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Check Debug Mode Status
    # ------------------------------------------------------------
    def self.debug_mode?
        DebugConfig.debug_mode?                                              # Return debug mode status
    end
    # ---------------------------------------------------------------

    # FUNCTION | Enable Debug Mode
    # ------------------------------------------------------------
    def self.enable_debug
        DebugConfig.enable_debug_mode                                        # Enable debug mode
    end
    # ---------------------------------------------------------------

    # FUNCTION | Disable Debug Mode
    # ------------------------------------------------------------
    def self.disable_debug
        DebugConfig.disable_debug_mode                                       # Disable debug mode
    end
    # ---------------------------------------------------------------

    # FUNCTION | Toggle Debug Mode
    # ------------------------------------------------------------
    def self.toggle_debug
        DebugConfig.toggle_debug_mode                                        # Toggle debug mode
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Configuration Value Accessors
# -----------------------------------------------------------------------------

    # FUNCTION | Get Real-time Update Delay
    # ------------------------------------------------------------
    def self.update_delay
        DebugConfig.realtime_update_delay                                    # Return update delay
    end
    # ---------------------------------------------------------------

    # FUNCTION | Get Minimum Panel Length
    # ------------------------------------------------------------
    def self.min_panel_length
        DebugConfig.min_panel_length                                         # Return minimum panel length
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Framework-Specific Debug Utilities
# -----------------------------------------------------------------------------

    # FUNCTION | Debug Framework Assembly Data
    # ------------------------------------------------------------
    def self.debug_assembly_data(assembly_id, data)
        return unless debug_mode?                                            # Exit if debug mode disabled
        
        debug_assembly("Assembly ID: #{assembly_id}")                       # Log assembly ID
        
        if data                                                              # If data exists
            debug_assembly("  Metadata: #{data['frameworkMetadata']&.size || 0} items")
            debug_assembly("  Nodes: #{data['nodes']&.size || 0} items")
            debug_assembly("  Panels: #{data['panelLines']&.size || 0} items")
        else
            debug_assembly("  No data found")                                # Log no data
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Debug Component Selection
    # ------------------------------------------------------------
    def self.debug_selection(selection)
        return unless debug_mode?                                            # Exit if debug mode disabled
        
        debug_log("Selection count: #{selection.size}")                     # Log selection count
        
        selection.each_with_index do |entity, index|                        # Iterate through selection
            if entity.is_a?(Sketchup::ComponentInstance)                    # Check if component
                debug_log("  [#{index}] Component: #{entity.name || 'Unnamed'}")
            else
                debug_log("  [#{index}] #{entity.class.name}")              # Log entity type
            end
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Debug Timing Information
    # ------------------------------------------------------------
    def self.debug_timing(operation_name, &block)
        return yield unless debug_mode?                                      # Execute block if debug disabled
        
        start_time = Time.now                                                # Record start time
        result = yield                                                       # Execute block
        elapsed_time = ((Time.now - start_time) * 1000).round(2)           # Calculate elapsed time in ms
        
        debug_log("#{operation_name} completed in #{elapsed_time}ms")       # Log timing information
        return result                                                        # Return block result
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module FrameworkDebugTools
  end # module Tools
end # module ValeDesignSuite

# =============================================================================
# END OF FILE
# ============================================================================= 