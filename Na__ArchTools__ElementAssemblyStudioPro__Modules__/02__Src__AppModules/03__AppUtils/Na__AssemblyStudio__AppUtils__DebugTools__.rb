# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - UNIFIED DEBUG TOOLS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AppUtils__DebugTools__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AppUtils
# MODULE     : Na__DebugTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Single app-wide logging API consolidating Window and Interior
#              Door legacy channels. Includes file logging, diagnostics, timing,
#              and SketchUp-console output behind a configurable gate.
#
# DESCRIPTION:
# - All output flows through na_debug_log(message, prefix); domain helpers only
#   choose the channel prefix constant.
# - na_sync_with_config merges AppConfig Loader `debug` once per load when
#   Na__AssemblyStudio::Na__AppData::Na__ConfigLoader is defined.
#
# DESIGN     : Safe no-op paths when disabled; errors can still optionally
#              print even when callers force na_debug_error.
#
# NAMING CONVENTION:
# - Na__DebugTools singleton methods use na_debug_* / na_enable_* prefixes.
#
# =============================================================================

require 'sketchup'

module Na__AssemblyStudio
    module Na__AppUtils
        module Na__DebugTools

# -----------------------------------------------------------------------------
# REGION | Channel Prefix Registry
# -----------------------------------------------------------------------------

            NA_PREFIX_WINDOW    = 'NA_WINDOW'
            NA_PREFIX_DOOR      = 'NA_DOOR'
            NA_PREFIX_GEOM      = 'NA_GEOM'
            NA_PREFIX_DOOR_GEOM = 'NA_DOOR_GEOM'
            NA_PREFIX_SERIAL    = 'NA_SERIAL'
            NA_PREFIX_DOOR_SER  = 'NA_DOOR_SERIAL'
            NA_PREFIX_UI        = 'NA_UI'
            NA_PREFIX_PLACEMENT = 'NA_PLACE'
            NA_PREFIX_OBSERVER  = 'NA_OBSERVE'
            NA_PREFIX_MEASURE   = 'NA_DOOR_MEASURE'
            NA_PREFIX_ASSET     = 'NA_DOOR_ASSET'
            NA_PREFIX_TAG       = 'NA_DOOR_TAG'
            NA_PREFIX_ARCH      = 'NA_DOOR_ARCH'
            NA_PREFIX_ERROR     = 'NA_ERROR'
            NA_PREFIX_WARN      = 'NA_WARN'
            NA_PREFIX_INFO      = 'NA_INFO'
            NA_PREFIX_OK        = 'NA_OK'
            NA_PREFIX_METHOD    = 'NA_METHOD'
            NA_PREFIX_TIMING    = 'NA_TIMING'
            NA_PREFIX_DEBUG     = 'NA_DEBUG'

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module State & Config Sync
# -----------------------------------------------------------------------------

            @na_debug_mode      = false
            @na_log_to_file     = false
            @na_log_timestamps  = true
            @na_log_basename    = 'na_assembly_studio_debug.log'
            @na_config_synced   = false

            # FUNCTION | Merge debug flags from Na__ConfigLoader when available
            # ------------------------------------------------------------
            def self.na_sync_with_config
                return if @na_config_synced
                cfg = na_safe_config
                if cfg
                    @na_debug_mode      = cfg['enabled']        unless cfg['enabled'].nil?
                    @na_log_to_file     = cfg['fileLogging']    unless cfg['fileLogging'].nil?
                    @na_log_timestamps  = cfg['logTimestamps']  unless cfg['logTimestamps'].nil?
                    @na_log_basename    = cfg['logFileBasename'] || @na_log_basename
                end
                @na_config_synced = true
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Read `debug` hash from Loader without raising
            # ------------------------------------------------------------
            def self.na_safe_config
                return nil unless defined?(Na__AssemblyStudio::Na__AppData::Na__ConfigLoader)
                Na__AssemblyStudio::Na__AppData::Na__ConfigLoader.na_get('debug')
            rescue StandardError
                nil
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Core Logging
# -----------------------------------------------------------------------------

            # FUNCTION | Route a single line through console (+ optional file)
            # ------------------------------------------------------------
            def self.na_debug_log(message, prefix = NA_PREFIX_WINDOW)
                na_sync_with_config
                return unless @na_debug_mode
                timestamp          = @na_log_timestamps ? "[#{Time.now.strftime('%H:%M:%S')}] " : ''
                formatted_message  = "#{timestamp}[#{prefix}] #{message}"
                puts formatted_message
                na_log_to_file(formatted_message) if @na_log_to_file
            end
            # ---------------------------------------------------------------

            def self.na_debug_window(message);     na_debug_log(message, NA_PREFIX_WINDOW);      end
            def self.na_debug_door(message);       na_debug_log(message, NA_PREFIX_DOOR);       end
            def self.na_debug_geometry(message);  na_debug_log(message, NA_PREFIX_GEOM);       end
            def self.na_debug_door_geom(message);  na_debug_log(message, NA_PREFIX_DOOR_GEOM);  end
            def self.na_debug_serializer(message); na_debug_log(message, NA_PREFIX_SERIAL);      end
            def self.na_debug_door_ser(message);   na_debug_log(message, NA_PREFIX_DOOR_SER);    end
            def self.na_debug_ui(message);         na_debug_log(message, NA_PREFIX_UI);         end
            def self.na_debug_placement(message); na_debug_log(message, NA_PREFIX_PLACEMENT);   end
            def self.na_debug_observer(message);   na_debug_log(message, NA_PREFIX_OBSERVER);    end
            def self.na_debug_measure(message);    na_debug_log(message, NA_PREFIX_MEASURE);     end
            def self.na_debug_asset(message);      na_debug_log(message, NA_PREFIX_ASSET);       end
            def self.na_debug_tag(message);        na_debug_log(message, NA_PREFIX_TAG);         end
            def self.na_debug_architrave(message); na_debug_log(message, NA_PREFIX_ARCH);        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Status Helpers (Error / Warn / Info / Success)
# -----------------------------------------------------------------------------

            # FUNCTION | Log an error variant with optional Ruby exception
            # ------------------------------------------------------------
            def self.na_debug_error(message, error = nil)
                error_text = error ? "#{message}: #{error.message}" : message
                na_debug_log("ERROR - #{error_text}", NA_PREFIX_ERROR)
                na_debug_backtrace(error.backtrace) if error && error.respond_to?(:backtrace) && error.backtrace
            end
            # ---------------------------------------------------------------

            # FUNCTION | Log a guarded warning without raising
            # ------------------------------------------------------------
            def self.na_debug_warn(message)
                na_debug_log("WARNING - #{message}", NA_PREFIX_WARN)
            end
            # ---------------------------------------------------------------

            # FUNCTION | Log informational text
            # ------------------------------------------------------------
            def self.na_debug_info(message)
                na_debug_log("INFO - #{message}", NA_PREFIX_INFO)
            end
            # ---------------------------------------------------------------

            # FUNCTION | Log lifecycle / success breadcrumbs
            # ------------------------------------------------------------
            def self.na_debug_success(message)
                na_debug_log("SUCCESS - #{message}", NA_PREFIX_OK)
            end
            # ---------------------------------------------------------------

            # FUNCTION | Echo the first `limit` backtrace frames to stdout
            # ------------------------------------------------------------
            def self.na_debug_backtrace(backtrace, limit = 10)
                na_sync_with_config
                return unless @na_debug_mode && backtrace
                puts "  Backtrace (first #{limit} lines):"
                backtrace.first(limit).each_with_index do |line, index|
                    puts "    [#{index}] #{line}"
                end
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Mode Control
# -----------------------------------------------------------------------------

            # FUNCTION | Cached read of `@na_debug_mode`
            # ------------------------------------------------------------
            def self.na_debug_mode?
                na_sync_with_config
                @na_debug_mode
            end
            # ---------------------------------------------------------------

            # FUNCTION | Force debug output on regardless of YAML gate
            # ------------------------------------------------------------
            def self.na_enable_debug
                @na_debug_mode       = true
                @na_config_synced = true
                puts "[#{NA_PREFIX_DEBUG}] Debug mode ENABLED"
            end
            # ---------------------------------------------------------------

            # FUNCTION | Silence debug helpers until re-enabled
            # ------------------------------------------------------------
            def self.na_disable_debug
                @na_debug_mode       = false
                @na_config_synced = true
                puts "[#{NA_PREFIX_DEBUG}] Debug mode DISABLED"
            end
            # ---------------------------------------------------------------

            # FUNCTION | Toggle debug writes and persist override flag
            # ------------------------------------------------------------
            def self.na_toggle_debug
                @na_debug_mode       = !@na_debug_mode
                @na_config_synced = true
                status = @na_debug_mode ? 'ENABLED' : 'DISABLED'
                puts "[#{NA_PREFIX_DEBUG}] Debug mode #{status}"
                @na_debug_mode
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tracing, Timing & Selection Diagnostics
# -----------------------------------------------------------------------------

            # FUNCTION | Optional method-enter trace when params present
            # ------------------------------------------------------------
            def self.na_debug_method(method_name, params = nil)
                na_sync_with_config
                return unless @na_debug_mode
                if params
                    na_debug_log("-> #{method_name}(#{params})", NA_PREFIX_METHOD)
                else
                    na_debug_log("-> #{method_name}()", NA_PREFIX_METHOD)
                end
            end
            # ---------------------------------------------------------------

            # FUNCTION | Yield block and log wall-clock elapsed in ms
            # ------------------------------------------------------------
            def self.na_debug_timing(operation_name, &block)
                na_sync_with_config
                return yield unless @na_debug_mode
                start_time = Time.now
                result     = yield
                elapsed_ms = ((Time.now - start_time) * 1000).round(2)
                na_debug_log("#{operation_name} completed in #{elapsed_ms}ms", NA_PREFIX_TIMING)
                result
            end
            # ---------------------------------------------------------------

            # FUNCTION | Summarise SketchUp selection entities in order
            # ------------------------------------------------------------
            def self.na_debug_selection(selection)
                na_sync_with_config
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

            # FUNCTION | Lightweight dump of hydrated window-configuration hash
            # ------------------------------------------------------------
            def self.na_debug_window_data(window_id, data)
                na_sync_with_config
                return unless @na_debug_mode
                na_debug_log("Window ID: #{window_id}")
                if data
                    na_debug_log("  Metadata: #{data['windowMetadata']&.length || 0} items")
                    na_debug_log("  Components: #{data['windowComponents']&.length || 0} items")
                    na_debug_log("  Config keys: #{data['windowConfiguration']&.keys&.join(', ') || 'none'}")
                else
                    na_debug_log('  No data found')
                end
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Optional File Logging
# -----------------------------------------------------------------------------

            # FUNCTION | Append one line beside this source tree
            # ------------------------------------------------------------
            def self.na_log_to_file(message)
                return unless @na_log_to_file
                begin
                    log_file = File.join(File.dirname(__FILE__), @na_log_basename)
                    File.open(log_file, 'a') { |file| file.puts(message) }
                rescue StandardError => e
                    puts "[#{NA_PREFIX_ERROR}] Failed to write to log file: #{e.message}"
                end
            end
            # ---------------------------------------------------------------

            # FUNCTION | Turn on mirrored file sink for na_debug_log
            # ------------------------------------------------------------
            def self.na_enable_file_logging
                @na_log_to_file       = true
                @na_config_synced = true
                na_debug_log('File logging ENABLED')
            end
            # ---------------------------------------------------------------

            # FUNCTION | Disable mirrored file writes
            # ------------------------------------------------------------
            def self.na_disable_file_logging
                @na_log_to_file       = false
                @na_config_synced = true
                na_debug_log('File logging DISABLED')
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        end
    end
end
