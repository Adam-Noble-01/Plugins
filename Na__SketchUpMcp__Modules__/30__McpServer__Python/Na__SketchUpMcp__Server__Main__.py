# =============================================================================
# NA SKETCHUP MCP - PYTHON SERVER - MAIN (ENTRY POINT)
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Server__Main__.py
# PURPOSE    : Start the Na SketchUp MCP server on stdio
# CREATED    : 2026
#
# WHAT RUNS WHERE:
#   AI client (Claude Code / Desktop, Codex, Cursor, VS Code, Gemini CLI ...)
#       |  MCP over stdio: this program
#       v
#   Na__SketchUpMcp__Server__*  (Python 3.9+, standard library only)
#       |  one JSON line per request over 127.0.0.1, session token
#       v
#   Na SketchUp MCP bridge inside SketchUp 2026 (Ruby, main thread)
#
# NO DEPENDENCIES: nothing to pip install. Any Python 3.9+ on PATH runs it.
#
# USAGE (the client starts it for you; see 85__Docs__AgentReference):
#   python Na__SketchUpMcp__Server__Main__.py [--toolset full|core] [--check]
#   --check   prints the tools and the SketchUp bridges it can see, then exits
#
# ENVIRONMENT:
#   NA_SKETCHUP_MCP_TOOLSET   full (default) | core
#   NA_SKETCHUP_MCP_PID       target this SketchUp process
#   NA_SKETCHUP_MCP_PORT / NA_SKETCHUP_MCP_TOKEN / NA_SKETCHUP_MCP_HOST   manual bridge address
#   NA_SKETCHUP_MCP_LOG       1 = log every call to stderr
#
# STDIO RULES: stdout carries only protocol messages (binary, UTF-8, "\n"
# framed, never a BOM); anything printed by mistake goes to stderr instead.
#
# =============================================================================

import argparse
import json
import os
import sys
import threading

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import Na__SketchUpMcp__Server__ApiIndex__ as Na__ApiIndexModule          # noqa: E402
import Na__SketchUpMcp__Server__BridgeClient__ as Na__BridgeClientModule  # noqa: E402
import Na__SketchUpMcp__Server__Protocol__ as Na__ProtocolModule          # noqa: E402
import Na__SketchUpMcp__Server__Resources__ as Na__ResourcesModule        # noqa: E402
import Na__SketchUpMcp__Server__ToolRegistry__ as Na__ToolRegistryModule  # noqa: E402
import Na__SketchUpMcp__Server__ToolRunner__ as Na__ToolRunnerModule      # noqa: E402

NA_MODULES_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))


# -----------------------------------------------------------------------------
# REGION | Stdio Plumbing
# -----------------------------------------------------------------------------

def Na__Main__MakeWriter(binary_stdout):
    lock = threading.Lock()

    def na_write(message):
        data = (json.dumps(message, ensure_ascii=True, separators=(',', ':')) + '\n').encode('utf-8')
        with lock:
            binary_stdout.write(data)
            binary_stdout.flush()

    return na_write


def Na__Main__MakeLogger(verbose):
    def na_log(text):
        if verbose:
            sys.stderr.write('[na-sketchup-mcp] %s\n' % text)
            sys.stderr.flush()

    return na_log

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Assembly
# -----------------------------------------------------------------------------

def Na__Main__BuildServices(toolset, logger):
    registry = Na__ToolRegistryModule.Na__ToolRegistry(toolset)
    bridge = Na__BridgeClientModule.Na__BridgeClient(logger)
    api_index = Na__ApiIndexModule.Na__ApiIndex()
    server_facts = Na__ToolRunnerModule.Na__ToolRunner__ServerFacts(registry, toolset)
    runner = Na__ToolRunnerModule.Na__ToolRunner(registry, bridge, api_index, server_facts)
    resources = Na__ResourcesModule.Na__Resources(registry, bridge, api_index)
    return registry, bridge, api_index, runner, resources


def Na__Main__ServerInfo(registry):
    server = registry.Na__ToolRegistry__Server()
    return {
        'name': server.get('name', 'sketchup'),
        'title': server.get('title', 'Na SketchUp MCP'),
        'version': server.get('version', '0.0.0'),
        'description': server.get('description', '')
    }


def Na__Main__Instructions(registry):
    relative = registry.Na__ToolRegistry__Server().get('instructions_file', '')
    try:
        with open(os.path.join(NA_MODULES_ROOT, relative.replace('/', os.sep)), encoding='utf-8') as handle:
            return handle.read().strip()[:2048]
    except OSError:
        return 'SketchUp MCP server. Call sketchup_status first. Lengths in mm, angles in degrees, world coordinates.'

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Check Mode (a quick self-test from a terminal)
# -----------------------------------------------------------------------------

def Na__Main__Check(toolset):
    registry, bridge, api_index, _runner, _resources = Na__Main__BuildServices(toolset, Na__Main__MakeLogger(True))
    print('Na SketchUp MCP %s, toolset %s: %d tools' % (Na__Main__ServerInfo(registry)['version'], toolset, len(registry.Na__ToolRegistry__Names())))
    facts = api_index.Na__ApiIndex__Facts()
    print('API index: %d classes, %d methods, up to %s; %d Ruby core names' % (
        facts['classes'], facts['methods'], facts['api_highest_version'], facts['ruby_core_names']))
    instances = bridge.Na__BridgeClient__Instances()
    if not instances:
        print('No SketchUp bridge found (is SketchUp open with the extension loaded?)')
        return 0
    for instance in instances:
        print('SketchUp pid %s on port %s: %s  live=%s' % (instance.get('pid'), instance.get('port'), instance.get('model_title'), instance.get('live')))
    try:
        response = bridge.Na__BridgeClient__Request('ping', {}, 10)
        print('Ping:', json.dumps(response.get('result') or response.get('error')))
    except Na__BridgeClientModule.Na__BridgeError as error:
        print('Ping failed: %s %s' % (error.na_message, error.na_hint or ''))
    return 0

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Main Loop
# -----------------------------------------------------------------------------

def na_main():
    parser = argparse.ArgumentParser(description='Na SketchUp MCP server (stdio).')
    parser.add_argument('--toolset', choices=['full', 'core'], default=os.environ.get('NA_SKETCHUP_MCP_TOOLSET', 'full'))
    parser.add_argument('--check', action='store_true', help='Print tools and visible SketchUp bridges, then exit.')
    arguments = parser.parse_args()

    if arguments.check:
        return Na__Main__Check(arguments.toolset)

    binary_stdout = sys.stdout.buffer
    sys.stdout = sys.stderr  # a stray print() must never corrupt the protocol stream
    logger = Na__Main__MakeLogger(os.environ.get('NA_SKETCHUP_MCP_LOG') == '1')
    registry, _bridge, _api_index, runner, resources = Na__Main__BuildServices(arguments.toolset, logger)
    protocol = Na__ProtocolModule.Na__McpProtocol(
        registry, runner, resources, Na__Main__ServerInfo(registry), Na__Main__Instructions(registry),
        Na__Main__MakeWriter(binary_stdout), logger)

    logger('Started (toolset %s, %d tools). Waiting for the client on stdin.' % (arguments.toolset, len(registry.Na__ToolRegistry__Names())))
    try:
        for raw_line in sys.stdin.buffer:
            line = raw_line.decode('utf-8', errors='replace').lstrip('﻿').strip()
            if line:
                protocol.Na__McpProtocol__HandleLine(line)
    except KeyboardInterrupt:
        pass
    finally:
        protocol.Na__McpProtocol__Shutdown()
        logger('stdin closed; exiting.')
    return 0


if __name__ == '__main__':
    sys.exit(na_main())

# =============================================================================
# END OF FILE
# =============================================================================
