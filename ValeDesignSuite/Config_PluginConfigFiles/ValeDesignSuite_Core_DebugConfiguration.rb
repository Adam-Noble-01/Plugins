# =============================================================================
# VALEDESIGNSUITE - DEBUG CONFIGURATION
# =============================================================================
#
# FILE       : ValeDesignSuite_Core_DebugConfiguration.rb
# NAMESPACE  : ValeDesignSuite::Config
# MODULE     : DebugConfiguration
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Global Debug Configuration and Management
# CREATED    : 26-May-2025
#
# DESCRIPTION:
# - Manages global debug settings for ValeDesignSuite
# - Loads debug configuration from JSON file
# - Provides centralized debug logging functionality
# - Controls debug output to prevent console spam
# - Manages real-time update delays and minimum panel lengths
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 26-May-2025 - Version 1.0.0
# - Initial Release
# - Global debug configuration implementation
#
# =============================================================================

require 'json'
require 'sketchup'

module ValeDesignSuite
  module Config
    module DebugConfiguration

# -----------------------------------------------------------------------------
# REGION | Module Constants and Configuration Loading
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Default Debug Settings
    # ------------------------------------------------------------
    DEFAULT_DEBUG_MODE              =   false                                 # <-- Default debug mode state
    DEFAULT_REALTIME_UPDATE_DELAY   =   500                                  # <-- Default delay in milliseconds
    DEFAULT_MIN_PANEL_LENGTH        =   100                                  # <-- Default minimum panel length in mm
    CONFIG_FILE_NAME                =   "Config_FrameworkConfigurator_DebugSettings.json"  # <-- Configuration file name
    # ---------------------------------------------------------------

    # MODULE VARIABLES | Configuration Storage
    # ------------------------------------------------------------
    @debug_settings                 =   nil                                  # <-- Cached debug settings
    @config_loaded                  =   false                                # <-- Configuration load status
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Configuration File Management
# -----------------------------------------------------------------------------

    # FUNCTION | Load Debug Configuration from File
    # ------------------------------------------------------------
    def self.load_debug_configuration
        return @debug_settings if @config_loaded                             # Return cached settings if already loaded
        
        config_path = File.join(File.dirname(__FILE__), CONFIG_FILE_NAME)   # Build configuration file path
        
        if File.exist?(config_path)                                         # Check if configuration file exists
            begin
                file_content = File.read(config_path)                       # Read configuration file
                config_data = JSON.parse(file_content)                      # Parse JSON content
                
                # Extract debug settings from configuration
                if config_data["FrameworkConfig"] && config_data["FrameworkConfig"]["DebugSettings"]
                    @debug_settings = config_data["FrameworkConfig"]["DebugSettings"]
                    @config_loaded = true                                    # Mark configuration as loaded
                    return @debug_settings                                   # Return loaded settings
                end
            rescue JSON::ParserError => e
                puts "[DEBUG CONFIG ERROR] Failed to parse debug configuration: #{e.message}"
            rescue => e
                puts "[DEBUG CONFIG ERROR] Failed to load debug configuration: #{e.message}"
            end
        end
        
        # Return default settings if file not found or error occurred
        @debug_settings = {
            "DEBUG_MODE"             => DEFAULT_DEBUG_MODE,
            "REALTIME_UPDATE_DELAY"  => DEFAULT_REALTIME_UPDATE_DELAY,
            "MIN_PANEL_LENGTH"       => DEFAULT_MIN_PANEL_LENGTH
        }
        @config_loaded = true                                                # Mark defaults as loaded
        return @debug_settings                                               # Return default settings
    end
    # ---------------------------------------------------------------

    # FUNCTION | Save Debug Configuration to File
    # ------------------------------------------------------------
    def self.save_debug_configuration(settings)
        config_path = File.join(File.dirname(__FILE__), CONFIG_FILE_NAME)   # Build configuration file path
        
        config_data = {
            "FileMetaData" => {
                "FileName"        => CONFIG_FILE_NAME,
                "FileDescription" => "This file contains the debug settings for the framework configurator",
                "FileCreated"     => "26-May-2025",
                "FileUpdated"     => Time.now.strftime("%d-%b-%Y")
            },
            "FrameworkConfig" => {
                "DebugSettings" => settings,
                "Description" => {
                    "DEBUG_MODE"             => "Set to true for developer debugging, diagnostic and logging without spamming the console",
                    "REALTIME_UPDATE_DELAY"  => "Delay in milliseconds for real-time updates",
                    "MIN_PANEL_LENGTH"       => "Minimum panel length in millimeters"
                }
            }
        }
        
        begin
            File.write(config_path, JSON.pretty_generate(config_data))      # Write configuration to file
            @debug_settings = settings                                       # Update cached settings
            return true                                                      # Return success
        rescue => e
            puts "[DEBUG CONFIG ERROR] Failed to save debug configuration: #{e.message}"
            return false                                                     # Return failure
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Debug Mode Accessors and Control
# -----------------------------------------------------------------------------

    # FUNCTION | Check if Debug Mode is Enabled
    # ------------------------------------------------------------
    def self.debug_mode?
        load_debug_configuration unless @config_loaded                      # Load configuration if not loaded
        @debug_settings["DEBUG_MODE"] || DEFAULT_DEBUG_MODE                 # Return debug mode state
    end
    # ---------------------------------------------------------------

    # FUNCTION | Enable Debug Mode
    # ------------------------------------------------------------
    def self.enable_debug_mode
        load_debug_configuration unless @config_loaded                      # Load configuration if not loaded
        @debug_settings["DEBUG_MODE"] = true                                # Enable debug mode
        save_debug_configuration(@debug_settings)                           # Save updated configuration
        puts "[DEBUG MODE] Debug mode ENABLED"                              # Notify user
    end
    # ---------------------------------------------------------------

    # FUNCTION | Disable Debug Mode
    # ------------------------------------------------------------
    def self.disable_debug_mode
        load_debug_configuration unless @config_loaded                      # Load configuration if not loaded
        @debug_settings["DEBUG_MODE"] = false                               # Disable debug mode
        save_debug_configuration(@debug_settings)                           # Save updated configuration
        puts "[DEBUG MODE] Debug mode DISABLED"                             # Notify user
    end
    # ---------------------------------------------------------------

    # FUNCTION | Toggle Debug Mode
    # ------------------------------------------------------------
    def self.toggle_debug_mode
        if debug_mode?                                                       # Check current debug mode
            disable_debug_mode                                               # Disable if currently enabled
        else
            enable_debug_mode                                                # Enable if currently disabled
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Configuration Value Accessors
# -----------------------------------------------------------------------------

    # FUNCTION | Get Real-time Update Delay
    # ------------------------------------------------------------
    def self.realtime_update_delay
        load_debug_configuration unless @config_loaded                      # Load configuration if not loaded
        @debug_settings["REALTIME_UPDATE_DELAY"] || DEFAULT_REALTIME_UPDATE_DELAY
    end
    # ---------------------------------------------------------------

    # FUNCTION | Get Minimum Panel Length
    # ------------------------------------------------------------
    def self.min_panel_length
        load_debug_configuration unless @config_loaded                      # Load configuration if not loaded
        @debug_settings["MIN_PANEL_LENGTH"] || DEFAULT_MIN_PANEL_LENGTH
    end
    # ---------------------------------------------------------------

    # FUNCTION | Update Configuration Value
    # ------------------------------------------------------------
    def self.update_setting(key, value)
        load_debug_configuration unless @config_loaded                      # Load configuration if not loaded
        
        if @debug_settings.key?(key)                                        # Check if key exists
            @debug_settings[key] = value                                    # Update setting value
            save_debug_configuration(@debug_settings)                       # Save updated configuration
            return true                                                      # Return success
        else
            puts "[DEBUG CONFIG ERROR] Unknown setting key: #{key}"
            return false                                                     # Return failure
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Debug Logging Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Debug Log with Conditional Output
    # ------------------------------------------------------------
    def self.debug_log(message, prefix = "DEBUG")
        return unless debug_mode?                                            # Exit if debug mode disabled
        
        timestamp = Time.now.strftime("%H:%M:%S")                           # Get current timestamp
        puts "[#{timestamp}] [#{prefix}] #{message}"                        # Output debug message
    end
    # ---------------------------------------------------------------

    # FUNCTION | Debug Error Log
    # ------------------------------------------------------------
    def self.debug_error(message, error = nil)
        return unless debug_mode?                                            # Exit if debug mode disabled
        
        timestamp = Time.now.strftime("%H:%M:%S")                           # Get current timestamp
        puts "[#{timestamp}] [ERROR] #{message}"                            # Output error message
        
        if error                                                             # If error object provided
            puts "[#{timestamp}] [ERROR] #{error.class}: #{error.message}"  # Output error details
            puts error.backtrace.first(5).join("\n") if error.backtrace     # Output backtrace
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Debug Warning Log
    # ------------------------------------------------------------
    def self.debug_warn(message)
        return unless debug_mode?                                            # Exit if debug mode disabled
        
        timestamp = Time.now.strftime("%H:%M:%S")                           # Get current timestamp
        puts "[#{timestamp}] [WARN] #{message}"                             # Output warning message
    end
    # ---------------------------------------------------------------

    # FUNCTION | Debug Info Log
    # ------------------------------------------------------------
    def self.debug_info(message)
        return unless debug_mode?                                            # Exit if debug mode disabled
        
        timestamp = Time.now.strftime("%H:%M:%S")                           # Get current timestamp
        puts "[#{timestamp}] [INFO] #{message}"                             # Output info message
    end
    # ---------------------------------------------------------------

    # FUNCTION | Debug Method Entry Log
    # ------------------------------------------------------------
    def self.debug_method(method_name, params = nil)
        return unless debug_mode?                                            # Exit if debug mode disabled
        
        timestamp = Time.now.strftime("%H:%M:%S")                           # Get current timestamp
        if params                                                            # If parameters provided
            puts "[#{timestamp}] [METHOD] #{method_name} called with: #{params.inspect}"
        else
            puts "[#{timestamp}] [METHOD] #{method_name} called"
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Menu Integration for Debug Control
# -----------------------------------------------------------------------------

    # FUNCTION | Add Debug Menu Items
    # ------------------------------------------------------------
    def self.add_debug_menu_items
        plugins_menu = UI.menu("Plugins")                                   # Get plugins menu
        
        if plugins_menu                                                      # If menu exists
            vale_menu = plugins_menu.add_submenu("Vale Design Suite")       # Get or create Vale submenu
            debug_menu = vale_menu.add_submenu("Debug Tools")               # Create debug submenu
            
            # Add toggle debug mode menu item
            debug_menu.add_item("Toggle Debug Mode") do
                toggle_debug_mode                                            # Toggle debug mode
            end
            
            # Add separator
            debug_menu.add_separator
            
            # Add debug status menu item
            debug_menu.add_item("Show Debug Status") do
                status = debug_mode? ? "ENABLED" : "DISABLED"               # Get current status
                UI.messagebox("Debug Mode: #{status}\n" +
                            "Update Delay: #{realtime_update_delay}ms\n" +
                            "Min Panel Length: #{min_panel_length}mm")
            end
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module DebugConfiguration
  end # module Config
end # module ValeDesignSuite

# =============================================================================
# END OF FILE
# ============================================================================= 