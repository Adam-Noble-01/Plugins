# =============================================================================
# NA SKETCHUP MCP - TESTS - PYTHON MCP SERVER (PROTOCOL + BRIDGE CLIENT)
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Tests__PythonServer__.py
# PURPOSE    : Drive the real MCP server over stdio against a fake SketchUp
#              bridge and check the protocol, validation and safety rules
# CREATED    : 2026
#
# THE FAKE BRIDGE:
# A real TCP server on 127.0.0.1 that speaks the bridge wire format (one JSON
# line each way), checks the session token, and answers a few commands. A
# connection file in a temp folder points the MCP server at it
# (NA_SKETCHUP_MCP_CONNECTIONS_DIR), exactly as a running SketchUp would.
#
# USAGE: python Na__SketchUpMcp__Tests__PythonServer__.py   (unittest; exit 1 on failure)
#
# =============================================================================

import base64
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

sys.dont_write_bytecode = True
NA_TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
NA_MODULES_ROOT = os.path.abspath(os.path.join(NA_TESTS_DIR, '..'))
NA_SERVER_DIR = os.path.join(NA_MODULES_ROOT, '30__McpServer__Python')
NA_SERVER_MAIN = os.path.join(NA_SERVER_DIR, 'Na__SketchUpMcp__Server__Main__.py')
sys.path.insert(0, NA_SERVER_DIR)

import Na__SketchUpMcp__Server__BridgeClient__ as Na__BridgeClientModule  # noqa: E402

NA_PNG_1X1 = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')


# -----------------------------------------------------------------------------
# REGION | Fake Bridge
# -----------------------------------------------------------------------------

class NaFakeBridge:
    """A stand-in for the Ruby bridge: same framing, same token check, canned answers."""

    def __init__(self, connections_dir, token='test-token-0001'):
        self.connections_dir = connections_dir
        self.token = token
        self.requests = []
        self.reject_next_as_unauthorized = False
        self.delay_seconds = 0.0
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.bind(('127.0.0.1', 0))
        self.server.listen(8)
        self.port = self.server.getsockname()[1]
        self.running = True
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()
        self.write_connection_file()

    def write_connection_file(self):
        path = os.path.join(self.connections_dir, 'Na__SketchUpMcp__Connection__%d.json' % os.getpid())
        with open(path, 'w', encoding='utf-8') as handle:
            json.dump({'pid': os.getpid(), 'host': '127.0.0.1', 'port': self.port, 'token': self.token,
                       'model_title': 'Fake Model', 'sketchup_version': '26.2.243', 'started_at': '2026-09-30T10:00:00Z'}, handle)

    def serve(self):
        while self.running:
            try:
                client, _address = self.server.accept()
            except OSError:
                return
            threading.Thread(target=self.handle, args=(client,), daemon=True).start()

    def handle(self, client):
        with client:
            buffer = b''
            while b'\n' not in buffer:
                chunk = client.recv(65536)
                if not chunk:
                    return
                buffer += chunk
            request = json.loads(buffer.split(b'\n', 1)[0])
            self.requests.append(request)
            if self.delay_seconds:
                time.sleep(self.delay_seconds)
            response = self.answer(request)
            try:
                client.sendall((json.dumps(response) + '\n').encode('utf-8'))
            except OSError:
                pass

    def answer(self, request):
        rid = request.get('id')
        if self.reject_next_as_unauthorized or request.get('token') != self.token:
            self.reject_next_as_unauthorized = False
            return {'id': rid, 'ok': False, 'error': {'code': 'unauthorized', 'message': 'Session token missing or wrong.'}}
        command = request['command']
        params = request.get('params', {})
        if command == 'ping':
            return {'id': rid, 'ok': True, 'result': {'pong': True}}
        if command == 'sketchup_status':
            return {'id': rid, 'ok': True, 'result': {'sketchup': {'version': '26.2.243'}, 'model': {'title': 'Fake Model'}}}
        if command == 'view_capture':
            path = os.path.join(self.connections_dir, 'capture.png')
            with open(path, 'wb') as handle:
                handle.write(NA_PNG_1X1)
            return {'id': rid, 'ok': True, 'result': {'image_file': path, 'mime_type': 'image/png', 'width': 1, 'height': 1}}
        if command == 'entity_get':
            return {'id': rid, 'ok': False, 'error': {'code': 'not_found', 'message': 'No entity with id 5.', 'hint': 'Query again.'}}
        return {'id': rid, 'ok': True, 'result': {'echo_command': command, 'echo_params': params}, 'warnings': ['fake warning'], 'undo': 'MCP: Fake'}

    def stop(self):
        self.running = False
        self.server.close()

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | MCP Session Over Stdio
# -----------------------------------------------------------------------------

class NaMcpSession:
    def __init__(self, env, extra_args=()):
        self.process = subprocess.Popen([sys.executable, '-B', NA_SERVER_MAIN] + list(extra_args), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL, env=env)
        self.next_id = 100

    def send(self, message):
        self.process.stdin.write((json.dumps(message) + '\n').encode('utf-8'))
        self.process.stdin.flush()

    def read(self):
        line = self.process.stdout.readline()
        if not line:
            raise AssertionError('server closed stdout')
        return json.loads(line)

    def request(self, method, params=None):
        self.next_id += 1
        message = {'jsonrpc': '2.0', 'id': self.next_id, 'method': method}
        if params is not None:
            message['params'] = params
        self.send(message)
        while True:
            response = self.read()
            if response.get('id') == self.next_id:
                return response

    def call(self, name, arguments):
        return self.request('tools/call', {'name': name, 'arguments': arguments})

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=10)
        self.process.stdout.close()

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Tests
# -----------------------------------------------------------------------------

class NaMcpServerTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp(prefix='na_mcp_test_')
        cls.bridge = NaFakeBridge(cls.temp_dir)
        cls.env = dict(os.environ, NA_SKETCHUP_MCP_CONNECTIONS_DIR=cls.temp_dir, PYTHONUTF8='1')
        cls.env.pop('NA_SKETCHUP_MCP_PORT', None)
        cls.session = NaMcpSession(cls.env)
        cls.init = cls.session.request('initialize', {'protocolVersion': '2025-11-25', 'capabilities': {}, 'clientInfo': {'name': 'tests', 'version': '1'}})
        cls.session.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})

    @classmethod
    def tearDownClass(cls):
        cls.session.close()
        cls.bridge.stop()
        shutil.rmtree(cls.temp_dir, ignore_errors=True)

    def text(self, response):
        return response['result']['content'][0]['text']

    # --- lifecycle and listing -------------------------------------------------------

    def test_initialize_legacy(self):
        result = self.init['result']
        self.assertEqual(result['protocolVersion'], '2025-11-25')
        self.assertIn('tools', result['capabilities'])
        self.assertEqual(result['serverInfo']['name'], 'sketchup')
        self.assertLessEqual(len(result['instructions']), 2048)

    def test_initialize_unknown_version_falls_back(self):
        session = NaMcpSession(self.env)
        try:
            response = session.request('initialize', {'protocolVersion': '2099-01-01', 'capabilities': {}, 'clientInfo': {'name': 't'}})
            self.assertEqual(response['result']['protocolVersion'], '2025-11-25')
        finally:
            session.close()

    def test_tools_list(self):
        tools = self.session.request('tools/list')['result']['tools']
        self.assertEqual(len(tools), 44)
        for tool in tools:
            self.assertEqual(tool['inputSchema']['type'], 'object')
            self.assertNotIn('$use', json.dumps(tool['inputSchema']))
            self.assertIn('readOnlyHint', tool['annotations'])

    def test_core_toolset(self):
        session = NaMcpSession(self.env, ['--toolset', 'core'])
        try:
            session.request('initialize', {'protocolVersion': '2025-06-18', 'capabilities': {}, 'clientInfo': {'name': 't'}})
            self.assertEqual(len(session.request('tools/list')['result']['tools']), 22)
        finally:
            session.close()

    def test_modern_era(self):
        meta = {'_meta': {'io.modelcontextprotocol/protocolVersion': '2026-07-28', 'io.modelcontextprotocol/clientCapabilities': {}}}
        discover = self.session.request('server/discover', meta)['result']
        self.assertEqual(discover['resultType'], 'complete')
        self.assertIn('2026-07-28', discover['supportedVersions'])
        self.assertIn('ttlMs', discover)
        listing = self.session.request('tools/list', meta)['result']
        self.assertEqual(listing['cacheScope'], 'public')
        self.assertIn('io.modelcontextprotocol/serverInfo', listing['_meta'])

    def test_unsupported_modern_version(self):
        response = self.session.request('tools/list', {'_meta': {'io.modelcontextprotocol/protocolVersion': '1900-01-01'}})
        self.assertEqual(response['error']['code'], -32022)

    def test_ping_and_unknown_method(self):
        self.assertEqual(self.session.request('ping')['result'], {})
        self.assertEqual(self.session.request('does/not/exist')['error']['code'], -32601)

    def test_parse_error(self):
        self.session.process.stdin.write(b'{not json\n')
        self.session.process.stdin.flush()
        self.assertEqual(self.session.read()['error']['code'], -32700)

    def test_jsonrpc_batch_array(self):
        self.session.send([{'jsonrpc': '2.0', 'id': 'a', 'method': 'ping'}, {'jsonrpc': '2.0', 'id': 'b', 'method': 'ping'}])
        responses = self.session.read()
        self.assertEqual(sorted(item['id'] for item in responses), ['a', 'b'])

    # --- tools/call ---------------------------------------------------------------------

    def test_status_connected(self):
        payload = json.loads(self.text(self.session.call('sketchup_status', {})))
        self.assertTrue(payload['connected'])
        self.assertEqual(payload['model']['title'], 'Fake Model')

    def test_bridge_success_shape(self):
        response = self.session.call('entity_query', {'types': ['Face'], 'limit': 5})
        payload = json.loads(self.text(response))
        self.assertFalse(response['result']['isError'])
        self.assertEqual(payload['echo_command'], 'entity_query')
        self.assertEqual(payload['warnings'], ['fake warning'])
        self.assertEqual(payload['undo_step'], 'MCP: Fake')

    def test_bridge_error_shape(self):
        response = self.session.call('entity_get', {'ids': [5]})
        self.assertTrue(response['result']['isError'])
        self.assertIn('Error (not_found)', self.text(response))
        self.assertIn('Fix: Query again.', self.text(response))

    def test_argument_validation(self):
        response = self.session.call('geometry_create_solid', {'shape': 'box', 'size': [1, 2], 'colour': 'red'})
        self.assertTrue(response['result']['isError'])
        text = self.text(response)
        self.assertIn('at least 3 item', text)
        self.assertIn("unknown argument(s) colour", text)

    def test_unknown_tool_is_protocol_error(self):
        self.assertEqual(self.session.call('make_coffee', {})['error']['code'], -32602)

    def test_view_capture_returns_image_and_deletes_file(self):
        response = self.session.call('view_capture', {'width': 64, 'height': 64})
        blocks = response['result']['content']
        images = [block for block in blocks if block['type'] == 'image']
        self.assertEqual(len(images), 1)
        self.assertEqual(base64.b64decode(images[0]['data']), NA_PNG_1X1)
        self.assertFalse(os.path.exists(os.path.join(self.temp_dir, 'capture.png')))

    def test_export_option_check(self):
        response = self.session.call('model_file', {'action': 'export', 'path': 'C:/tmp/a.obj', 'options': {'units': 'mm', 'make_it_nice': True}})
        self.assertTrue(response['result']['isError'])
        self.assertIn('make_it_nice', self.text(response))
        self.assertIn('triangulated_faces', self.text(response))

    def test_batch_validation(self):
        bad = self.session.call('batch_execute', {'steps': [{'tool': 'model_file', 'arguments': {'action': 'save'}},
                                                            {'tool': 'geometry_create_solid', 'arguments': {'shape': 'cube'}},
                                                            {'tool': 'context_set', 'arguments': {'action': 'close_all'}}]})
        self.assertTrue(bad['result']['isError'])
        text = self.text(bad)
        self.assertIn('model_file is not allowed', text)
        self.assertIn("'cube'", text)
        self.assertIn('context_set splits the undo operation', text)
        good = self.session.call('batch_execute', {'steps': [{'tool': 'geometry_create_solid', 'arguments': {'shape': 'box', 'size': [1, 1, 1]}},
                                                             {'tool': 'entity_transform', 'arguments': {'ids': ['$0.id'], 'operations': [{'type': 'translate', 'vector': [1, 0, 0]}]}}]})
        self.assertFalse(good['result']['isError'])

    def test_ruby_eval_lint(self):
        payload = json.loads(self.text(self.session.call('ruby_eval', {'code': 'model.entities.add_cube(3)'})))
        self.assertEqual(payload['api_lint']['unknown_methods'][0]['name'], 'add_cube')

    def test_api_lookup(self):
        payload = json.loads(self.text(self.session.call('ruby_api_lookup', {'query': 'Face#offset'})))
        self.assertFalse(payload['lookup']['found'])
        payload = json.loads(self.text(self.session.call('ruby_api_lookup', {'query': 'Sketchup::Face#pushpull'})))
        self.assertEqual(payload['lookup']['results'][0]['method'], 'Sketchup::Face#pushpull')

    # --- resources and prompts --------------------------------------------------------------

    def test_resources(self):
        uris = [item['uri'] for item in self.session.request('resources/list')['result']['resources']]
        self.assertIn('sketchup://guide/agent', uris)
        guide = self.session.request('resources/read', {'uri': 'sketchup://guide/agent'})['result']['contents'][0]['text']
        self.assertIn('coordinate', guide.lower())
        face = json.loads(self.session.request('resources/read', {'uri': 'sketchup://api/class/Face'})['result']['contents'][0]['text'])
        self.assertEqual(face['class'], 'Sketchup::Face')
        self.assertEqual(self.session.request('resources/read', {'uri': 'sketchup://nope'})['error']['code'], -32002)

    def test_prompts(self):
        names = [item['name'] for item in self.session.request('prompts/list')['result']['prompts']]
        self.assertIn('sketchup_build_from_brief', names)
        self.assertEqual(self.session.request('prompts/get', {'name': 'sketchup_build_from_brief', 'arguments': {}})['error']['code'], -32602)


class NaBridgeClientTests(unittest.TestCase):

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp(prefix='na_mcp_client_')
        os.environ['NA_SKETCHUP_MCP_CONNECTIONS_DIR'] = self.temp_dir
        self.bridge = NaFakeBridge(self.temp_dir)
        self.client = Na__BridgeClientModule.Na__BridgeClient()

    def tearDown(self):
        self.bridge.stop()
        os.environ.pop('NA_SKETCHUP_MCP_CONNECTIONS_DIR', None)
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_unauthorized_is_retried_once(self):
        self.bridge.reject_next_as_unauthorized = True
        response = self.client.Na__BridgeClient__Request('ping', {}, 5)
        self.assertTrue(response['ok'])
        self.assertEqual(len(self.bridge.requests), 2)

    def test_timeout_is_never_retried(self):
        self.bridge.delay_seconds = 1.5
        with self.assertRaises(Na__BridgeClientModule.Na__BridgeTimeout):
            self.client.Na__BridgeClient__Request('geometry_create_solid', {'shape': 'box'}, 0.5)
        time.sleep(1.6)
        self.assertEqual(len(self.bridge.requests), 1)

    def test_no_bridge(self):
        self.bridge.stop()
        for name in os.listdir(self.temp_dir):
            os.remove(os.path.join(self.temp_dir, name))
        with self.assertRaises(Na__BridgeClientModule.Na__BridgeUnavailable):
            self.client.Na__BridgeClient__Request('ping', {}, 1)

# endregion -------------------------------------------------------------------


if __name__ == '__main__':
    unittest.main(verbosity=1)

# =============================================================================
# END OF FILE
# =============================================================================
