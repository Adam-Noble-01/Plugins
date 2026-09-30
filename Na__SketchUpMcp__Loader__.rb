# =============================================================================
# NA SKETCHUP MCP - ROOT LOADER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Loader__.rb
# NAMESPACE  : Na__SketchUpMcp (root bootstrap)
# PURPOSE    : Bootstrap the Na SketchUp MCP bridge from the Plugins root
# CREATED    : 2026
#
# WHAT IT IS:
# The SketchUp side of an MCP (Model Context Protocol) server that lets Claude,
# Codex / GPT, Cursor, Gemini and other agents inspect and model in this
# SketchUp window. The agent-facing MCP server is the Python program in
# Na__SketchUpMcp__Modules__/30__McpServer__Python; it talks to this bridge
# over 127.0.0.1 using the session token in 91__UserConfig__LocalOnly.
#
# CONFIG-FIRST DESIGN NOTE:
# Tools live in Na__SketchUpMcp__CoreAppData__ToolRegistry__.json, settings in
# Na__SketchUpMcp__CoreAppData__AppConfig__.json. Keep this bootstrap thin.
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)

# -----------------------------------------------------------------------------
# REGION | Path Setup
# -----------------------------------------------------------------------------

    plugin_root      = File.dirname(__FILE__)
    modules_root     = File.join(plugin_root, 'Na__SketchUpMcp__Modules__')
    core_loader_file = File.join(
        modules_root,
        '02__Plugin__CoreAppData',
        '01__CoreAppLoaders',
        'Na__SketchUpMcp__CoreAppLoaders__Main__.rb'
    )

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Core Loader Require and Registration
# -----------------------------------------------------------------------------

    if File.exist?(core_loader_file)
        begin
            require core_loader_file

            if defined?(Na__SketchUpMcp) &&
               Na__SketchUpMcp.respond_to?(:Na__SketchUpMcp__RegisterMenuAndAutoStart)
                Na__SketchUpMcp.Na__SketchUpMcp__RegisterMenuAndAutoStart
            else
                puts '[Na__SketchUpMcp] Register method unavailable'
            end
        rescue ScriptError, StandardError => error
            puts "[Na__SketchUpMcp] Loader error: #{error.class}: #{error.message}"
            puts error.backtrace.first(10).join("\n") if error.backtrace
        end
    else
        puts "[Na__SketchUpMcp] Core loader not found: #{core_loader_file}"
    end

# endregion -------------------------------------------------------------------

    file_loaded(__FILE__)
end

# =============================================================================
# END OF FILE
# =============================================================================
