# =============================================================================
# NA SKETCHUP MCP - CORE RELOAD MANAGER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__CoreAppLogic__ReloadManager__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__ReloadManager
# PURPOSE    : Reload Plugin Data: re-load every bridge .rb and the JSON config
#              without restarting SketchUp or dropping the running bridge
# CREATED    : 2026
#
# THE BRIDGE KEEPS RUNNING THROUGH A RELOAD:
# The socket server, its timer and the session token live in module instance
# variables, which Kernel#load does not reset. The timer block calls
# Na__SocketServer__Pump by name, so the next tick already runs the new code.
#
# KNOWN LIMIT (same as every Na__ plugin reload):
# load re-opens modules but never deletes a method or constant that a file no
# longer defines. If a change works by deleting something, restart SketchUp.
# The Python MCP server reads the tool registry at start: after changing tool
# definitions, restart the MCP server (or it will notice the file change and
# tell its client the tool list changed).
#
# =============================================================================

module Na__SketchUpMcp
    module Na__ReloadManager

# -----------------------------------------------------------------------------
# REGION | Public Reload API
# -----------------------------------------------------------------------------

        def self.Na__ReloadManager__ReloadPluginData
            loaded = 0
            errors = []
            # Re-loading a file re-assigns its constants; Ruby's "already initialized constant"
            # warnings are expected here, so they are silenced for the duration of the reload.
            original_verbose = $VERBOSE
            $VERBOSE = nil
            begin
                na_module_rb_files.each do |rb_file|
                    begin
                        load rb_file
                        loaded += 1
                    rescue ScriptError, StandardError => error
                        errors << "#{File.basename(rb_file)}: #{error.class}: #{error.message}"
                        puts "[Na__SketchUpMcp] Reload error in #{File.basename(rb_file)}: #{error.class}: #{error.message}"
                    end
                end
            ensure
                $VERBOSE = original_verbose
            end

            Na__ConfigLoader.Na__ConfigLoader__InvalidateCache
            Na__ApiSelfTest.Na__ApiSelfTest__Run
            Na__DialogManager.Na__DialogManager__ResetDialog
            message = "Reloaded #{loaded} Ruby file(s), #{errors.length} error(s). Bridge #{Na__SocketServer.Na__SocketServer__Running ? 'still running' : 'stopped'}."
            Na__ActivityLog.Na__ActivityLog__Record('reload', 0, errors.empty?, message)
            { success: errors.empty?, message: message, errors: errors }
        rescue StandardError => error
            { success: false, message: "Reload failed: #{error.class}: #{error.message}", errors: [error.message] }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # Helpers before core before handlers so constants exist before they are read.
        def self.na_module_rb_files
            root = Na__PathResolver.Na__PathResolver__ModulesRoot
            ordered_folders = %w[03__Plugin__CoreAppLogic 04__Plugin__BridgeCore 06__Plugin__BridgeHelpers 10__BridgeHandlers]
            files = ordered_folders.flat_map { |folder| Dir.glob(File.join(root, folder, '*.rb')).sort }
            files + Dir.glob(File.join(root, '02__Plugin__CoreAppData', '**', '*.rb')).sort
        end

# endregion -------------------------------------------------------------------

    end # module Na__ReloadManager
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
