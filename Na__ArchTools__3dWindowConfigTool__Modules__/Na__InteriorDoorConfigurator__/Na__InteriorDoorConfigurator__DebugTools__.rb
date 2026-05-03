# =============================================================================
# NA INTERIOR DOOR CONFIGURATOR - DEBUG TOOLS
# =============================================================================
#
# FILE       : Na__InteriorDoorConfigurator__DebugTools__.rb
# NAMESPACE  : Na__InteriorDoorConfigurator
# MODULE     : Na__DebugTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Simplified Debug Logging for Interior Door Configurator
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Provides simplified debug logging functions for the Interior Door tab
# - Mirrors the Window Configurator DebugTools pattern with door-specific prefixes
# - Toggle debug mode on/off for development vs production
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
#
# =============================================================================

require 'sketchup'

module Na__InteriorDoorConfigurator
    module Na__DebugTools

# -----------------------------------------------------------------------------
# REGION | Debug Configuration Constants
# -----------------------------------------------------------------------------

        # MODULE CONSTANTS | Debug Prefixes
        # ------------------------------------------------------------
        NA_PREFIX_DOOR        = "NA_DOOR"           # <-- Door operations prefix
        NA_PREFIX_GEOMETRY    = "NA_DOOR_GEOM"      # <-- Door geometry prefix
        NA_PREFIX_SERIAL      = "NA_DOOR_SERIAL"    # <-- Door serializer prefix
        NA_PREFIX_UI          = "NA_DOOR_UI"        # <-- Door UI prefix
        NA_PREFIX_MEASURE     = "NA_DOOR_MEASURE"   # <-- 3-point measure tool prefix
        NA_PREFIX_ASSET       = "NA_DOOR_ASSET"     # <-- Asset library prefix
        NA_PREFIX_TAG         = "NA_DOOR_TAG"       # <-- Tag manager prefix
        NA_PREFIX_ARCHITRAVE  = "NA_DOOR_ARCH"      # <-- Architrave builder prefix
        # ---------------------------------------------------------------

        # MODULE VARIABLES | Debug State
        # ------------------------------------------------------------
        @na_debug_mode      = false                                    # <-- Toggle for development
        @na_log_timestamps  = true                                     # <-- Include timestamps in log output
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Core Debug Logging Functions
# -----------------------------------------------------------------------------

        # FUNCTION | General Debug Log
        # ------------------------------------------------------------
        def self.na_debug_log(message, prefix = NA_PREFIX_DOOR)
            return unless @na_debug_mode

            timestamp = @na_log_timestamps ? "[#{Time.now.strftime('%H:%M:%S')}] " : ""
            puts "#{timestamp}[#{prefix}] #{message}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Door Operations Debug Log
        # ------------------------------------------------------------
        def self.na_debug_door(message)
            na_debug_log(message, NA_PREFIX_DOOR)
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

        # FUNCTION | Measure Tool Debug Log
        # ------------------------------------------------------------
        def self.na_debug_measure(message)
            na_debug_log(message, NA_PREFIX_MEASURE)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Asset Library Debug Log
        # ------------------------------------------------------------
        def self.na_debug_asset(message)
            na_debug_log(message, NA_PREFIX_ASSET)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Tag Manager Debug Log
        # ------------------------------------------------------------
        def self.na_debug_tag(message)
            na_debug_log(message, NA_PREFIX_TAG)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Architrave Debug Log
        # ------------------------------------------------------------
        def self.na_debug_architrave(message)
            na_debug_log(message, NA_PREFIX_ARCHITRAVE)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Error and Status Logging
# -----------------------------------------------------------------------------

        # FUNCTION | Error Debug Log
        # ------------------------------------------------------------
        def self.na_debug_error(message, error = nil)
            error_text = error ? "#{message}: #{error.message}" : message
            na_debug_log("ERROR - #{error_text}", "NA_DOOR_ERROR")

            if error && error.respond_to?(:backtrace) && error.backtrace
                puts "  Backtrace (first 10 lines):"
                error.backtrace.first(10).each_with_index do |line, index|
                    puts "    [#{index}] #{line}"
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Warning Debug Log
        # ------------------------------------------------------------
        def self.na_debug_warn(message)
            na_debug_log("WARNING - #{message}", "NA_DOOR_WARN")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Info Debug Log
        # ------------------------------------------------------------
        def self.na_debug_info(message)
            na_debug_log("INFO - #{message}", "NA_DOOR_INFO")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Success Debug Log
        # ------------------------------------------------------------
        def self.na_debug_success(message)
            na_debug_log("SUCCESS - #{message}", "NA_DOOR_OK")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Method Trace Debug Log
        # ------------------------------------------------------------
        def self.na_debug_method(method_name, params = nil)
            return unless @na_debug_mode

            if params
                na_debug_log("-> #{method_name}(#{params})", "NA_DOOR_METHOD")
            else
                na_debug_log("-> #{method_name}()", "NA_DOOR_METHOD")
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Debug Mode Control
# -----------------------------------------------------------------------------

        # FUNCTION | Enable Debug Mode
        # ------------------------------------------------------------
        def self.na_enable_debug
            @na_debug_mode = true
            puts "[NA_DOOR_DEBUG] Debug mode ENABLED"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Disable Debug Mode
        # ------------------------------------------------------------
        def self.na_disable_debug
            @na_debug_mode = false
            puts "[NA_DOOR_DEBUG] Debug mode DISABLED"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Check Debug Mode Status
        # ------------------------------------------------------------
        def self.na_debug_mode?
            @na_debug_mode
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__DebugTools
end # module Na__InteriorDoorConfigurator

# =============================================================================
# END OF FILE
# =============================================================================
