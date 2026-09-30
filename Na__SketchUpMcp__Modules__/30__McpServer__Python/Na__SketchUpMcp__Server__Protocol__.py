# =============================================================================
# NA SKETCHUP MCP - PYTHON SERVER - MCP PROTOCOL
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Server__Protocol__.py
# PURPOSE    : Model Context Protocol over stdio (JSON-RPC 2.0, one message per
#              line), serving both protocol eras from one process
# CREATED    : 2026
#
# TWO ERAS, ONE SERVER (MCP spec as of 2026-09):
# - Legacy (2024-11-05 .. 2025-11-25): the client sends initialize; the server
#   answers with the same version if it supports it, else its newest legacy
#   version (2025-11-25). Desktop clients still open stdio servers this way.
# - Modern (2026-07-28): no handshake. server/discover describes the server;
#   each request carries _meta["io.modelcontextprotocol/protocolVersion"];
#   results carry resultType, and cacheable results carry ttlMs + cacheScope.
#   An unknown version gets -32022 with the supported list.
# Claude Code may send initialize after a successful server/discover; both
# paths simply work.
#
# CONCURRENCY:
# The reader loop never blocks on SketchUp: tools/call runs on a worker thread
# so ping, cancellation and other requests are answered meanwhile. One lock
# guards stdout so messages never interleave. A cancelled call's late result
# is dropped, as the spec asks.
#
# ERRORS:
# Unknown tool / prompt, bad params -> JSON-RPC -32602. Unknown method ->
# -32601 "Method not found". Tool failures -> isError results (tool runner).
# Resource not found -> -32002 (legacy) / -32602 (modern).
#
# =============================================================================

import concurrent.futures
import json
import threading
import time

import Na__SketchUpMcp__Server__Resources__ as Na__ResourcesModule
import Na__SketchUpMcp__Server__ToolRunner__ as Na__ToolRunnerModule

NA_LEGACY_VERSIONS = ['2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05']
NA_MODERN_VERSIONS = ['2026-07-28']
NA_META_VERSION_KEY = 'io.modelcontextprotocol/protocolVersion'
NA_SERVER_INFO_KEY = 'io.modelcontextprotocol/serverInfo'
NA_STATIC_TTL_MS = 3600000
NA_LIST_TTL_MS = 300000


class Na__RpcError(Exception):
    def __init__(self, code, message, data=None):
        super().__init__(message)
        self.na_code = code
        self.na_message = message
        self.na_data = data


# -----------------------------------------------------------------------------
# REGION | Protocol
# -----------------------------------------------------------------------------

class Na__McpProtocol:
    """Dispatches MCP messages to the registry, tool runner and resources."""

    def __init__(self, registry, runner, resources, server_info, instructions, writer, logger):
        self.na_registry = registry
        self.na_runner = runner
        self.na_resources = resources
        self.na_server_info = server_info
        self.na_instructions = instructions
        self.na_write = writer
        self.na_log = logger
        self.na_negotiated_version = None
        self.na_initialized = False
        self.na_executor = concurrent.futures.ThreadPoolExecutor(max_workers=4, thread_name_prefix='na-tool')
        self.na_cancelled = set()
        self.na_lock = threading.Lock()
        self.na_stop = threading.Event()
        self.na_watcher = threading.Thread(target=self.na_watch_registry, name='na-registry-watch', daemon=True)
        self.na_watcher.start()

    # --- entry points -------------------------------------------------------------

    def Na__McpProtocol__HandleLine(self, line):
        try:
            message = json.loads(line)
        except ValueError:
            self.na_write({'jsonrpc': '2.0', 'id': None, 'error': {'code': -32700, 'message': 'Parse error'}})
            return
        if isinstance(message, list):
            responses = [response for response in (self.na_handle_message(item) for item in message) if response is not None]
            if responses:
                self.na_write(responses)
            return
        response = self.na_handle_message(message)
        if response is not None:
            self.na_write(response)

    def Na__McpProtocol__Shutdown(self):
        self.na_stop.set()
        self.na_executor.shutdown(wait=False, cancel_futures=True)

    # --- dispatch -----------------------------------------------------------------

    def na_handle_message(self, message):
        if not isinstance(message, dict) or message.get('jsonrpc') != '2.0':
            return self.na_error(message.get('id') if isinstance(message, dict) else None, -32600, 'Invalid Request')
        method = message.get('method')
        if method is None:
            return None  # a response to a request we never send
        has_id = 'id' in message
        request_id = message.get('id')
        params = message.get('params') if isinstance(message.get('params'), dict) else {}

        try:
            modern = self.na_era(params)
            if method == 'tools/call' and has_id:
                self.na_executor.submit(self.na_run_tool_call, request_id, params, modern)
                return None
            result = self.na_dispatch(method, params, modern, has_id)
        except Na__RpcError as error:
            return self.na_error(request_id, error.na_code, error.na_message, error.na_data) if has_id else None
        except Exception as error:  # a bug here must not kill the stdio loop
            self.na_log('Unhandled error in %s: %r' % (method, error))
            return self.na_error(request_id, -32603, 'Internal error: %s' % error) if has_id else None

        if not has_id:
            return None
        return {'jsonrpc': '2.0', 'id': request_id, 'result': self.na_decorate(method, result, modern)}

    def na_era(self, params):
        meta = params.get('_meta') if isinstance(params.get('_meta'), dict) else {}
        version = meta.get(NA_META_VERSION_KEY)
        if version is None or version in NA_LEGACY_VERSIONS:
            return False
        if version in NA_MODERN_VERSIONS:
            return True
        raise Na__RpcError(-32022, 'Unsupported protocol version',
                           {'supported': NA_MODERN_VERSIONS + NA_LEGACY_VERSIONS, 'requested': version})

    def na_dispatch(self, method, params, modern, has_id):
        if method == 'initialize':
            return self.na_initialize(params)
        if method == 'server/discover':
            return self.na_discover()
        if method == 'ping':
            return {}
        if method == 'tools/list':
            return {'tools': self.na_registry.Na__ToolRegistry__McpTools()}
        if method == 'resources/list':
            return {'resources': self.na_resources.Na__Resources__List()}
        if method == 'resources/templates/list':
            return {'resourceTemplates': self.na_resources.Na__Resources__Templates()}
        if method == 'resources/read':
            return self.na_read_resource(params, modern)
        if method == 'prompts/list':
            return {'prompts': self.na_resources.Na__Resources__Prompts()}
        if method == 'prompts/get':
            try:
                return self.na_resources.Na__Resources__PromptGet(params.get('name'), params.get('arguments'))
            except Na__ResourcesModule.Na__PromptNotFound as error:
                raise Na__RpcError(-32602, str(error))
        if method == 'logging/setLevel':
            return {}
        if method == 'notifications/initialized':
            self.na_initialized = True
            return None
        if method == 'notifications/cancelled':
            self.na_cancelled.add(str(params.get('requestId')))
            return None
        if method.startswith('notifications/'):
            return None
        raise Na__RpcError(-32601, 'Method not found')

    # --- lifecycle ------------------------------------------------------------------

    def na_capabilities(self, modern):
        capabilities = {'tools': {} if modern else {'listChanged': True}, 'resources': {}, 'prompts': {}}
        return capabilities

    def na_initialize(self, params):
        requested = params.get('protocolVersion')
        self.na_negotiated_version = requested if requested in NA_LEGACY_VERSIONS else NA_LEGACY_VERSIONS[0]
        client = params.get('clientInfo') or {}
        self.na_log('initialize: client %s %s asked %s, using %s' % (client.get('name'), client.get('version'), requested, self.na_negotiated_version))
        return {
            'protocolVersion': self.na_negotiated_version,
            'capabilities': self.na_capabilities(False),
            'serverInfo': self.na_server_info,
            'instructions': self.na_instructions
        }

    def na_discover(self):
        return {
            'supportedVersions': NA_MODERN_VERSIONS,
            'capabilities': self.na_capabilities(True),
            'instructions': self.na_instructions
        }

    def na_decorate(self, method, result, modern):
        if not modern or not isinstance(result, dict):
            return result
        result = dict(result)
        result['resultType'] = 'complete'
        meta = dict(result.get('_meta') or {})
        meta[NA_SERVER_INFO_KEY] = self.na_server_info
        result['_meta'] = meta
        if method in ('server/discover', 'prompts/list', 'resources/templates/list'):
            result.update({'ttlMs': NA_STATIC_TTL_MS, 'cacheScope': 'public'})
        elif method in ('tools/list', 'resources/list'):
            result.update({'ttlMs': NA_LIST_TTL_MS, 'cacheScope': 'public'})
        return result

    # --- resources ------------------------------------------------------------------

    def na_read_resource(self, params, modern):
        uri = params.get('uri', '')
        try:
            mime_type, text = self.na_resources.Na__Resources__Read(uri)
        except Na__ResourcesModule.Na__ResourceNotFound:
            raise Na__RpcError(-32602 if modern else -32002, 'Resource not found', {'uri': uri})
        result = {'contents': [{'uri': uri, 'mimeType': mime_type, 'text': text}]}
        if modern:
            live = self.na_resources.Na__Resources__IsLive(uri)
            result.update({'ttlMs': 0 if live else NA_STATIC_TTL_MS, 'cacheScope': 'private' if live else 'public'})
        return result

    # --- tools/call on a worker thread -------------------------------------------------

    def na_run_tool_call(self, request_id, params, modern):
        started = time.time()
        name = params.get('name', '')
        try:
            result = self.na_runner.Na__ToolRunner__Call(name, params.get('arguments') or {})
            response = {'jsonrpc': '2.0', 'id': request_id, 'result': self.na_decorate('tools/call', result, modern)}
        except Na__ToolRunnerModule.Na__UnknownTool:
            response = self.na_error(request_id, -32602, 'Unknown tool: %s' % name,
                                     {'available': self.na_registry.Na__ToolRegistry__Names()})
        except Exception as error:  # report, never crash the server
            self.na_log('Tool %s failed unexpectedly: %r' % (name, error))
            result = Na__ToolRunnerModule.na_error_result('internal_error', 'The MCP server hit an unexpected error: %s' % error,
                                                          'Try again; if it repeats, restart the MCP server and report it.')
            response = {'jsonrpc': '2.0', 'id': request_id, 'result': self.na_decorate('tools/call', result, modern)}

        if str(request_id) in self.na_cancelled:
            self.na_cancelled.discard(str(request_id))
            self.na_log('Dropped the result of cancelled request %s (%s)' % (request_id, name))
            return
        self.na_log('%s done in %.0f ms' % (name, (time.time() - started) * 1000.0))
        self.na_write(response)

    # --- registry hot reload ---------------------------------------------------------------

    def na_watch_registry(self):
        while not self.na_stop.wait(3.0):
            if self.na_registry.Na__ToolRegistry__ReloadIfChanged():
                self.na_log('Tool registry changed on disk; reloaded.')
                if self.na_initialized:
                    self.na_write({'jsonrpc': '2.0', 'method': 'notifications/tools/list_changed'})

    # --- helpers -----------------------------------------------------------------------------

    def na_error(self, request_id, code, message, data=None):
        error = {'code': code, 'message': message}
        if data is not None:
            error['data'] = data
        return {'jsonrpc': '2.0', 'id': request_id, 'error': error}

# endregion -------------------------------------------------------------------

# =============================================================================
# END OF FILE
# =============================================================================
