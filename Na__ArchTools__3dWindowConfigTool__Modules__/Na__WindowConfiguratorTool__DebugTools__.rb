# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - DEBUG TOOLS
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__DebugTools__.rb
# NAMESPACE  : Na__WindowConfiguratorTool
# MODULE     : Na__DebugTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Simplified Debug Logging for Window Configurator Tool
# CREATED    : 2026
#
# DESCRIPTION:
# - Provides simplified debug logging functions for window configurator
# - Offers convenient debug methods with prefixed output
# - Manages tool-specific debug output to Ruby console
# - Toggle debug mode on/off for development vs production
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
# - Distinguishes Noble Architecture code from third-party libraries
#
# =============================================================================

require 'sketchup'

module Na__WindowConfiguratorTool
    module Na__DebugTools

# -----------------------------------------------------------------------------
# REGION | Debug Configuration Constants
# -----------------------------------------------------------------------------

        # MODULE CONSTANTS | Debug Prefixes
        # ------------------------------------------------------------
        NA_PREFIX_WINDOW    = "NA_WINDOW"       # Window operations prefix
        NA_PREFIX_GEOMETRY  = "NA_GEOM"         # Geometry operations prefix
        NA_PREFIX_SERIAL    = "NA_SERIAL"       # Serializer operations prefix
        NA_PREFIX_UI        = "NA_UI"           # UI operations prefix
        NA_PREFIX_PLACEMENT = "NA_PLACE"        # Placement tool prefix
        NA_PREFIX_OBSERVER  = "NA_OBSERVE"      # Selection observer prefix
        # ---------------------------------------------------------------

        # MODULE VARIABLES | Debug State
        # ------------------------------------------------------------
        @na_debug_mode = false                   # Toggle for development (set false for production)
        @na_log_to_file = false                 # Optional file logging
        @na_log_timestamps = true               # Include timestamps in log output
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Core Debug Logging Functions
# -----------------------------------------------------------------------------

        # FUNCTION | General Debug Log
        # ------------------------------------------------------------
        def self.na_debug_log(message, prefix = NA_PREFIX_WINDOW)
            return unless @na_debug_mode
            
            timestamp = @na_log_timestamps ? "[#{Time.now.strftime('%H:%M:%S')}] " : ""
            formatted_message = "#{timestamp}[#{prefix}] #{message}"
            
            puts formatted_message
            na_log_to_file(formatted_message) if @na_log_to_file
        end
        # ---------------------------------------------------------------

        # FUNCTION | Window Operations Debug Log
        # ------------------------------------------------------------
        def self.na_debug_window(message)
            na_debug_log(message, NA_PREFIX_WINDOW)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Geometry Operations Debug Log
        # ------------------------------------------------------------
        def self.na_debug_geometry(message)
            na_debug_log(message, NA_PREFIX_GEOMETRY)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Serializer Operations Debug Log
        # ------------------------------------------------------------
        def self.na_debug_serializer(message)
            na_debug_log(message, NA_PREFIX_SERIAL)
        end
        # ---------------------------------------------------------------

        # FUNCTION | UI Operations Debug Log
        # ------------------------------------------------------------
        def self.na_debug_ui(message)
            na_debug_log(message, NA_PREFIX_UI)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Placement Tool Debug Log
        # ------------------------------------------------------------
        def self.na_debug_placement(message)
            na_debug_log(message, NA_PREFIX_PLACEMENT)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Selection Observer Debug Log
        # ------------------------------------------------------------
        def self.na_debug_observer(message)
            na_debug_log(message, NA_PREFIX_OBSERVER)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Error and Warning Logging
# -----------------------------------------------------------------------------

        # FUNCTION | Error Debug Log
        # ------------------------------------------------------------
        def self.na_debug_error(message, error = nil)
            error_text = error ? "#{message}: #{error.message}" : message
            na_debug_log("ERROR - #{error_text}", "NA_ERROR")
            
            # Log backtrace if error object provided
            if error && error.respond_to?(:backtrace) && error.backtrace
                na_debug_backtrace(error.backtrace)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Warning Debug Log
        # ------------------------------------------------------------
        def self.na_debug_warn(message)
            na_debug_log("WARNING - #{message}", "NA_WARN")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Info Debug Log
        # ------------------------------------------------------------
        def self.na_debug_info(message)
            na_debug_log("INFO - #{message}", "NA_INFO")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Success Debug Log
        # ------------------------------------------------------------
        def self.na_debug_success(message)
            na_debug_log("SUCCESS - #{message}", "NA_OK")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Backtrace Debug Log
        # ------------------------------------------------------------
        def self.na_debug_backtrace(backtrace, limit = 10)
            return unless @na_debug_mode && backtrace
            
            puts "  Backtrace (first #{limit} lines):"
            backtrace.first(limit).each_with_index do |line, index|
                puts "    [#{index}] #{line}"
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Debug Mode Control Functions
# -----------------------------------------------------------------------------

        # FUNCTION | Check Debug Mode Status
        # ------------------------------------------------------------
        def self.na_debug_mode?
            @na_debug_mode
        end
        # ---------------------------------------------------------------

        # FUNCTION | Enable Debug Mode
        # ------------------------------------------------------------
        def self.na_enable_debug
            @na_debug_mode = true
            puts "[NA_DEBUG] Debug mode ENABLED"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Disable Debug Mode
        # ------------------------------------------------------------
        def self.na_disable_debug
            @na_debug_mode = false
            puts "[NA_DEBUG] Debug mode DISABLED"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Toggle Debug Mode
        # ------------------------------------------------------------
        def self.na_toggle_debug
            @na_debug_mode = !@na_debug_mode
            status = @na_debug_mode ? "ENABLED" : "DISABLED"
            puts "[NA_DEBUG] Debug mode #{status}"
            return @na_debug_mode
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Utility Debug Functions
# -----------------------------------------------------------------------------

        # FUNCTION | Debug Method Entry (for tracing function calls)
        # ------------------------------------------------------------
        def self.na_debug_method(method_name, params = nil)
            return unless @na_debug_mode
            
            if params
                na_debug_log("-> #{method_name}(#{params})", "NA_METHOD")
            else
                na_debug_log("-> #{method_name}()", "NA_METHOD")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Debug Timing Information
        # ------------------------------------------------------------
        def self.na_debug_timing(operation_name, &block)
            return yield unless @na_debug_mode
            
            start_time = Time.now
            result = yield
            elapsed_time = ((Time.now - start_time) * 1000).round(2)
            
            na_debug_log("#{operation_name} completed in #{elapsed_time}ms", "NA_TIMING")
            return result
        end
        # ---------------------------------------------------------------

        # FUNCTION | Debug Component Selection Info
        # ------------------------------------------------------------
        def self.na_debug_selection(selection)
            return unless @na_debug_mode
            
            na_debug_log("Selection count: #{selection.length}")
            
            selection.each_with_index do |entity, index|
                if entity.is_a?(Sketchup::ComponentInstance)
                    na_debug_log("  [#{index}] Component: #{entity.name || 'Unnamed'} (ID: #{entity.entityID})")
                else
                    na_debug_log("  [#{index}] #{entity.class.name}")
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Debug Window Data Summary
        # ------------------------------------------------------------
        def self.na_debug_window_data(window_id, data)
            return unless @na_debug_mode
            
            na_debug_log("Window ID: #{window_id}")
            
            if data
                na_debug_log("  Metadata: #{data['windowMetadata']&.length || 0} items")
                na_debug_log("  Components: #{data['windowComponents']&.length || 0} items")
                na_debug_log("  Config keys: #{data['windowConfiguration']&.keys&.join(', ') || 'none'}")
            else
                na_debug_log("  No data found")
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | File Logging (Optional)
# -----------------------------------------------------------------------------

        # FUNCTION | Log to File (if enabled)
        # ------------------------------------------------------------
        def self.na_log_to_file(message)
            return unless @na_log_to_file
            
            begin
                log_dir = File.dirname(__FILE__)
                log_file = File.join(log_dir, "na_window_configurator_debug.log")
                
                File.open(log_file, 'a') do |file|
                    file.puts message
                end
            rescue => e
                puts "[NA_ERROR] Failed to write to log file: #{e.message}"
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Enable File Logging
        # ------------------------------------------------------------
        def self.na_enable_file_logging
            @na_log_to_file = true
            na_debug_log("File logging ENABLED")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Disable File Logging
        # ------------------------------------------------------------
        def self.na_disable_file_logging
            @na_log_to_file = false
            na_debug_log("File logging DISABLED")
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__DebugTools
end # module Na__WindowConfiguratorTool

# =============================================================================
# END OF FILE
# =============================================================================
