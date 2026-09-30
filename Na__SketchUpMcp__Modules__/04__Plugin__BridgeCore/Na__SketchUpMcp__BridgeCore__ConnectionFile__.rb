# =============================================================================
# NA SKETCHUP MCP - BRIDGE CORE - CONNECTION FILE
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeCore__ConnectionFile__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__ConnectionFile
# PURPOSE    : Publish this SketchUp process's bridge address and session token
#              so the Python MCP server can find it with zero configuration
# CREATED    : 2026
#
# ONE FILE PER PROCESS:
# On Windows every SketchUp window is its own process with its own bridge, so
# each writes 91__UserConfig__LocalOnly/Connections/Na__SketchUpMcp__Connection__<pid>.json.
# The Python server lists them, pings each, and targets the most recently
# started live one unless told otherwise (sketchup_status select_pid).
# The file is removed when the bridge stops or SketchUp quits; a file left by a
# crash is detected as stale by the Python side (port refuses, pid gone).
#
# =============================================================================

require 'json'
require 'time'

module Na__SketchUpMcp
    module Na__ConnectionFile

# -----------------------------------------------------------------------------
# REGION | Write / Remove / Refresh
# -----------------------------------------------------------------------------

        def self.Na__ConnectionFile__Write(host, port, token)
            @na_host = host
            @na_port = port
            @na_token = token
            @na_started_at = Time.now.utc.iso8601
            na_write_payload
        end

        # Called when the model changes so the file names the model this process has open.
        def self.Na__ConnectionFile__Refresh
            return false unless @na_port && Na__SocketServer.Na__SocketServer__Running

            na_write_payload
        end

        def self.Na__ConnectionFile__Remove
            path = Na__PathResolver.Na__PathResolver__ConnectionFilePath(Process.pid)
            File.delete(path) if File.exist?(path)
            true
        rescue SystemCallError => error
            puts "[Na__SketchUpMcp] Connection file remove warning: #{error.message}"
            false
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        def self.na_write_payload
            model = Sketchup.active_model
            payload = {
                'protocol'         => 'na-sketchup-mcp-bridge/1',
                'pid'              => Process.pid,
                'host'             => @na_host,
                'port'             => @na_port,
                'token'            => @na_token,
                'bridge_version'   => Na__ConfigLoader.Na__ConfigLoader__BridgeVersion,
                'sketchup_version' => Sketchup.version.to_s,
                'model_title'      => model ? model.title.to_s : '',
                'model_path'       => model ? model.path.to_s : '',
                'started_at'       => @na_started_at,
                'updated_at'       => Time.now.utc.iso8601
            }

            directory = Na__PathResolver.Na__PathResolver__EnsureDirectory(Na__PathResolver.Na__PathResolver__ConnectionsDirectory)
            final_path = Na__PathResolver.Na__PathResolver__ConnectionFilePath(Process.pid)
            temporary_path = File.join(directory, ".tmp__#{Process.pid}.json")
            File.write(temporary_path, JSON.pretty_generate(payload))
            File.delete(final_path) if File.exist?(final_path)
            File.rename(temporary_path, final_path)
            true
        rescue SystemCallError, IOError => error
            puts "[Na__SketchUpMcp] Connection file write warning: #{error.message}"
            false
        end

# endregion -------------------------------------------------------------------

    end # module Na__ConnectionFile
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
