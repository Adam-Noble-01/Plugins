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

    def __init__(self, connections_dir, token='test-token-0001', pid=None, started_at='2026-09-30T10:00:00Z', file_title='Fake Model', live_title=None, model_path='',
                 modified=False, bridge_version=None):
        self.bridge_version = bridge_version        # what ping reports (None: not reported)
        self.connections_dir = connections_dir
        self.token = token
        self.pid = os.getpid() if pid is None else pid
        self.started_at = started_at
        self.file_title = file_title        # what the connection file says
        self.live_title = file_title if live_title is None else live_title      # what SketchUp has open now
        self.model_path = model_path        # the open model's file (sketchup_open_window looks for it)
        self.modified = modified            # unsaved changes (sketchup_close_window refuses them)
        self.requests = []
        self.outliner = None                # 1.0.28: the Agent Outliner notice put on every answer but ping (None: an older bridge)
        self.reject_next_as_unauthorized = False
        self.delay_seconds = 0.0
        self.pick_polls = 0                 # 1.0.30: looks at a waiting input_pick
        self.pick_never = False
        self.proposal_polls = 0
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.bind(('127.0.0.1', 0))
        self.server.listen(8)
        self.port = self.server.getsockname()[1]
        self.running = True
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()
        self.write_connection_file()

    def write_connection_file(self):
        path = os.path.join(self.connections_dir, 'Na__SketchUpMcp__Connection__%d.json' % self.pid)
        with open(path, 'w', encoding='utf-8') as handle:
            json.dump({'pid': self.pid, 'host': '127.0.0.1', 'port': self.port, 'token': self.token,
                       'model_title': self.file_title, 'sketchup_version': '26.2.243', 'started_at': self.started_at}, handle)

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
            if self.outliner and request.get('command') != 'ping' and (response.get('error') or {}).get('code') != 'unauthorized':
                response['outliner'] = self.outliner
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
            pong = {'pong': True, 'pid': self.pid, 'model_title': self.live_title, 'model_path': self.model_path}
            if self.bridge_version:
                pong['bridge_version'] = self.bridge_version
            return {'id': rid, 'ok': True, 'result': pong}
        if command == 'sketchup_status':
            return {'id': rid, 'ok': True, 'result': {'sketchup': {'version': '26.2.243'}, 'model': {'title': self.live_title, 'modified': self.modified}}}
        if command == 'view_capture':
            path = os.path.join(self.connections_dir, 'capture.png')
            with open(path, 'wb') as handle:
                handle.write(NA_PNG_1X1)
            return {'id': rid, 'ok': True, 'result': {'image_file': path, 'mime_type': 'image/png', 'width': 1, 'height': 1}}
        if command == 'entity_get':
            return {'id': rid, 'ok': False, 'error': {'code': 'not_found', 'message': 'No entity with id 5.', 'hint': 'Query again.'}}
        if command == 'input_pick':
            # 1.0.30: Adam finishes on the third look (or never, when pick_never is set).
            self.pick_polls += 1
            done = not self.pick_never and self.pick_polls >= 3
            return {'id': rid, 'ok': True, 'result': {'pick_id': 'pick_1', 'status': 'done' if done else 'waiting',
                                                       'points': [[10.0, 20.0, 0.0]] if done else [], 'seen_action': params.get('action')}}
        if command == 'proposal_preview' and params.get('action') == 'status':
            self.proposal_polls += 1
            answered = self.proposal_polls >= 2
            return {'id': rid, 'ok': True, 'result': {'name': 'PROPOSAL__Bed', 'answered': answered,
                                                       'replies': [{'text': 'Yes, go'}] if answered else []}}
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
        self.assertEqual(len(tools), 76)
        for tool in tools:
            self.assertEqual(tool['inputSchema']['type'], 'object')
            self.assertNotIn('$use', json.dumps(tool['inputSchema']))
            self.assertIn('readOnlyHint', tool['annotations'])

    def test_agent_outliner_tools(self):
        tools = {tool['name']: tool for tool in self.session.request('tools/list')['result']['tools']}
        for name in ('agent_outliner', 'agent_outliner_edit'):
            self.assertIn(name, tools)
            self.assertLessEqual(len(tools[name]['description']), 2048)
            self.assertEqual(tools[name]['inputSchema']['required'], ['action'])
        self.assertTrue(tools['agent_outliner']['annotations']['readOnlyHint'])
        self.assertFalse(tools['agent_outliner_edit']['annotations']['readOnlyHint'])
        # 1.0.23: threads, flags and strip, with their own filters.
        read = tools['agent_outliner']['inputSchema']['properties']
        self.assertIn('threads', read['action']['enum'])
        self.assertIn('flags', read['action']['enum'])
        self.assertEqual(read['waiting_on']['enum'], ['agent', 'user'])
        self.assertEqual(read['status']['enum'], ['open', 'resolved'])
        self.assertIn('strip', tools['agent_outliner_edit']['inputSchema']['properties']['action']['enum'])
        # 1.0.25: every tag for agents, and putting objects on one.
        self.assertIn('tags', tools['agent_outliner']['inputSchema']['properties']['action']['enum'])
        edit = tools['agent_outliner_edit']['inputSchema']['properties']
        self.assertIn('tag', edit['action']['enum'])
        self.assertEqual(edit['tag']['type'], 'string')
        self.assertEqual(edit['create']['type'], 'boolean')
        # 1.0.26: pictures on comments and replies.
        self.assertEqual(edit['images']['type'], 'array')
        self.assertEqual(edit['images']['items']['type'], 'string')
        # 1.0.31: Adam's Tree by Tag view for agents, one card and how deep.
        self.assertIn('tag_tree', read['action']['enum'])
        self.assertEqual(read['tag']['type'], 'string')
        self.assertEqual((read['depth']['type'], read['depth']['minimum'], read['depth']['maximum']), ('integer', 0, 8))
        self.assertIn('tag_tree', tools['agent_outliner']['description'])
        # 1.0.32: his Group by Category view for agents, one prefix's card.
        self.assertIn('category_tree', read['action']['enum'])
        self.assertEqual(read['prefix']['type'], 'string')
        self.assertIn('category_tree', tools['agent_outliner']['description'])
        self.assertLessEqual(len(tools['agent_outliner']['description']), 2048)

    def test_profile_tracer_tools(self):
        # 1.0.24: Adam's Na Profile Path Tracer, read / edit (batchable, own undo step) / library (files).
        tools = {tool['name']: tool for tool in self.session.request('tools/list')['result']['tools']}
        for name in ('profile_tracer', 'profile_tracer_edit', 'profile_tracer_library'):
            self.assertIn(name, tools)
            self.assertLessEqual(len(tools[name]['description']), 2048)
            self.assertEqual(tools[name]['inputSchema']['required'], ['action'])
            self.assertFalse(tools[name]['inputSchema']['additionalProperties'])
        self.assertTrue(tools['profile_tracer']['annotations']['readOnlyHint'])
        self.assertFalse(tools['profile_tracer_edit']['annotations']['readOnlyHint'])
        self.assertTrue(tools['profile_tracer_library']['annotations']['destructiveHint'])
        edit = tools['profile_tracer_edit']['inputSchema']['properties']
        self.assertIn('create', edit['action']['enum'])
        self.assertEqual(edit['profile_edit']['properties']['stretch']['items']['required'], ['axis', 'at', 'by'])
        self.assertEqual(edit['wrapper']['required'], ['name'])
        self.assertIn('near', tools['profile_tracer']['inputSchema']['properties'])
        self.assertIn('confirm', tools['profile_tracer_library']['inputSchema']['properties'])

    def test_truevision_glb_builder_tools(self):
        tools = {tool['name']: tool for tool in self.session.request('tools/list')['result']['tools']}
        for name in ('truevision_export', 'truevision_export_edit', 'truevision_publish'):
            self.assertIn(name, tools)
            self.assertLessEqual(len(tools[name]['description']), 2048)
        self.assertTrue(tools['truevision_export']['annotations']['readOnlyHint'])
        self.assertTrue(tools['truevision_publish']['annotations']['openWorldHint'])
        self.assertIn('confirm', tools['truevision_publish']['description'])
        # Scenes go by name or persistent id, mixed in one list, and reach the bridge as sent.
        sent = self.session.call('truevision_export_edit', {'action': 'switch_scenes', 'scenes': ['Front', 1234], 'on': True})
        self.assertFalse(sent['result']['isError'])
        self.assertEqual(json.loads(self.text(sent))['echo_params']['scenes'], ['Front', 1234])
        # The server refuses what the schemas do not allow before SketchUp is asked.
        bad_type = self.session.call('truevision_export_edit', {'action': 'set_scene_type', 'scene': 'Front', 'type': 'perspective'})
        self.assertTrue(bad_type['result']['isError'])
        self.assertIn("'perspective'", self.text(bad_type))
        bad_action = self.session.call('truevision_publish', {'action': 'export_project', 'confirm': 'SK02'})
        self.assertTrue(bad_action['result']['isError'])
        stray = self.session.call('truevision_publish', {'action': 'push', 'confirm': 'SK02', 'force': True})
        self.assertTrue(stray['result']['isError'])
        self.assertIn('force', self.text(stray))

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

    # --- the Agent Outliner notice (1.0.28) ---------------------------------------------

    NOTICE = {'waiting': 2, 'from': 'Adam', 'at': '2026-11-11T13:15:02+00:00', 'ago': '3 min', 'where': 'model chat',
              'text': 'Can you widen the rear door to 900?', 'pictures': 1, 'read': 'agent_outliner {action: "inbox"}'}

    def test_the_outliner_notice_leads_every_result_while_adam_waits(self):
        self.bridge.outliner = dict(self.NOTICE)
        try:
            response = self.session.call('entity_query', {'types': ['Face'], 'limit': 5})
            text = self.text(response)
            payload = json.loads(text)
            self.assertFalse(response['result']['isError'])
            self.assertTrue(text.startswith('{"outliner":'), text[:80])
            self.assertEqual(payload['outliner'], self.NOTICE)
            self.assertEqual(payload['echo_command'], 'entity_query')
            status = json.loads(self.text(self.session.call('sketchup_status', {})))
            self.assertEqual(status['outliner']['from'], 'Adam')
            batch = json.loads(self.text(self.session.call('batch_execute', {'steps': [{'tool': 'model_info', 'arguments': {}}]})))
            self.assertEqual(list(batch)[0], 'outliner')
        finally:
            self.bridge.outliner = None

    def test_the_outliner_notice_ends_an_error(self):
        self.bridge.outliner = dict(self.NOTICE)
        try:
            response = self.session.call('entity_get', {'ids': [5]})
            text = self.text(response)
            self.assertTrue(response['result']['isError'])
            self.assertIn('Error (not_found)', text)
            last = text.splitlines()[-1]
            self.assertTrue(last.startswith('Outliner: '), last)
            self.assertEqual(json.loads(last[len('Outliner: '):])['text'], 'Can you widen the rear door to 900?')
        finally:
            self.bridge.outliner = None

    def test_the_outliner_notice_survives_the_text_cap(self):
        self.bridge.outliner = dict(self.NOTICE)
        try:
            text = self.text(self.session.call('ruby_eval', {'code': '# ' + 'x' * 60000}))
            self.assertIn('[truncated', text)
            self.assertTrue(text.startswith('{"outliner":{"waiting":2'), text[:80])
        finally:
            self.bridge.outliner = None

    def test_requests_say_this_server_shows_the_notice_itself(self):
        # 1.0.29: without it the bridge also writes the notice into warnings, for servers before 1.0.28.
        self.session.call('entity_query', {'types': ['Face'], 'limit': 1})
        last = [request for request in self.bridge.requests if request.get('command') == 'entity_query'][-1]
        self.assertEqual(last.get('features'), ['outliner'])

    def test_no_notice_from_a_bridge_before_1_0_28_and_no_error(self):
        self.assertIsNone(self.bridge.outliner)
        response = self.session.call('entity_query', {'types': ['Face'], 'limit': 5})
        self.assertFalse(response['result']['isError'])
        self.assertNotIn('outliner', json.loads(self.text(response)))
        self.assertNotIn('Outliner:', self.text(self.session.call('entity_get', {'ids': [5]})))

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
        trial = self.session.call('batch_execute', {'rollback': True,
                                                    'steps': [{'tool': 'geometry_create_solid', 'arguments': {'shape': 'box', 'size': [1, 1, 1]}}]})
        self.assertFalse(trial['result']['isError'])
        typo = self.session.call('batch_execute', {'rollback': 'yes', 'steps': [{'tool': 'model_info', 'arguments': {}}]})
        self.assertTrue(typo['result']['isError'])

    # --- 1.0.30: waiting for Adam happens in the server, never inside SketchUp -------------

    def test_input_pick_wait_polls_the_bridge_until_adam_finishes(self):
        self.bridge.pick_polls = 0
        self.bridge.pick_never = False
        before = len(self.bridge.requests)
        payload = json.loads(self.text(self.session.call('input_pick', {'action': 'wait', 'pick_id': 'pick_1', 'wait_s': 20})))
        self.assertEqual(payload['status'], 'done')
        self.assertEqual(payload['points'], [[10.0, 20.0, 0.0]])
        self.assertEqual(payload['waited']['polls'], 3)
        sent = [request for request in self.bridge.requests[before:] if request['command'] == 'input_pick']
        self.assertEqual([request['params']['action'] for request in sent], ['result'] * 3)
        self.assertTrue(all('wait_s' not in request['params'] for request in sent))

    def test_input_pick_wait_gives_up_after_wait_s(self):
        self.bridge.pick_polls = 0
        self.bridge.pick_never = True
        try:
            payload = json.loads(self.text(self.session.call('input_pick', {'action': 'wait', 'wait_s': 1})))
        finally:
            self.bridge.pick_never = False
        self.assertEqual(payload['status'], 'waiting')
        self.assertEqual(payload['waited']['stopped'], 'wait_s ran out')

    def test_proposal_wait_returns_when_adam_answers(self):
        self.bridge.proposal_polls = 0
        payload = json.loads(self.text(self.session.call('proposal_preview', {'action': 'wait', 'name': 'Bed', 'wait_s': 30})))
        self.assertTrue(payload['answered'])
        self.assertEqual(payload['replies'][0]['text'], 'Yes, go')
        self.assertEqual(payload['waited']['polls'], 2)

    def test_pick_and_proposal_are_refused_in_a_batch(self):
        response = self.session.call('batch_execute', {'steps': [{'tool': 'input_pick', 'arguments': {'prompt': 'x'}},
                                                                {'tool': 'proposal_preview', 'arguments': {'action': 'list'}}]})
        self.assertTrue(response['result']['isError'])
        self.assertIn('input_pick is not allowed', self.text(response))
        self.assertIn('proposal_preview is not allowed', self.text(response))

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


class NaBridgeVersionTests(unittest.TestCase):
    """A parameter added later (registry property_since) is refused on a window whose bridge predates it (1.0.19)."""

    def start(self, version):
        self.temp_dir = tempfile.mkdtemp(prefix='na_mcp_version_')
        self.bridge = NaFakeBridge(self.temp_dir, bridge_version=version)
        env = dict(os.environ, NA_SKETCHUP_MCP_CONNECTIONS_DIR=self.temp_dir, PYTHONUTF8='1')
        env.pop('NA_SKETCHUP_MCP_PORT', None)
        env.pop('NA_SKETCHUP_MCP_PID', None)
        self.session = NaMcpSession(env)
        self.session.request('initialize', {'protocolVersion': '2025-11-25', 'capabilities': {}, 'clientInfo': {'name': 'tests', 'version': '1'}})
        self.session.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})

    def tearDown(self):
        self.session.close()
        self.bridge.stop()
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def work(self):
        return [request['command'] for request in self.bridge.requests if request['command'] != 'ping']

    FRAMED = {'action': 'count', 'min': [0, 0, 0], 'max': [1, 1, 1], 'frame': {'angle': 30}}

    def test_an_older_bridge_is_refused_a_frame_and_nothing_is_sent(self):
        self.start('1.0.18')
        response = self.session.call('point_cloud_slice', self.FRAMED)
        text = response['result']['content'][0]['text']
        self.assertTrue(response['result']['isError'])
        self.assertIn('needs 1.0.19', text)
        self.assertIn('Reload Plugin Data', text)
        batch = self.session.call('batch_execute', {'steps': [{'tool': 'point_cloud_slice', 'arguments': self.FRAMED}]})
        self.assertTrue(batch['result']['isError'])
        self.assertEqual(self.work(), [])
        plain = self.session.call('point_cloud_slice', {'action': 'count', 'min': [0, 0, 0], 'max': [1, 1, 1]})
        self.assertFalse(plain['result']['isError'])
        self.assertEqual(self.work(), ['point_cloud_slice'])

    def test_a_current_bridge_takes_the_frame(self):
        self.start('1.0.19')
        response = self.session.call('point_cloud_slice', self.FRAMED)
        self.assertFalse(response['result']['isError'])
        self.assertEqual(self.work(), ['point_cloud_slice'])

    def test_an_older_bridge_is_refused_a_new_action_with_the_fix(self):
        # 1.0.23: property_since also lists values ("agent_outliner.action=flags"); a 1.0.22 window would refuse
        # the action without saying Reload Plugin Data.
        self.start('1.0.22')
        for name, arguments, value in (('agent_outliner', {'action': 'flags'}, 'flags'),
                                       ('agent_outliner', {'action': 'threads'}, 'threads'),
                                       ('agent_outliner_edit', {'action': 'strip', 'ids': [1]}, 'strip')):
            response = self.session.call(name, arguments)
            text = response['result']['content'][0]['text']
            self.assertTrue(response['result']['isError'], name)
            self.assertIn('"%s" needs 1.0.23' % value, text)
            self.assertIn('Reload Plugin Data', text)
        self.assertEqual(self.work(), [])
        older = self.session.call('agent_outliner', {'action': 'summary'})
        self.assertFalse(older['result']['isError'])
        self.assertEqual(self.work(), ['agent_outliner'])

    def test_a_current_bridge_takes_the_new_actions(self):
        self.start('1.0.23')
        response = self.session.call('agent_outliner', {'action': 'threads', 'waiting_on': 'agent'})
        self.assertFalse(response['result']['isError'])
        self.assertEqual(self.work(), ['agent_outliner'])
    def test_an_older_bridge_is_refused_the_entity_studio_additions_with_the_fix(self):
        # 1.0.27: Element Assembly Studio Pro for every product (openings, parameters, build into an opening).
        self.start('1.0.26')
        for name, arguments in (('entity_studio', {'action': 'openings', 'wall_id': 1}),
                                ('entity_studio', {'action': 'parameters', 'type': 'bifold'}),
                                ('entity_studio_edit', {'action': 'build', 'type': 'casement', 'opening': {'wall_id': 1, 'index': 0}})):
            response = self.session.call(name, arguments)
            text = response['result']['content'][0]['text']
            self.assertTrue(response['result']['isError'], name)
            self.assertIn('needs 1.0.27', text)
            self.assertIn('Reload Plugin Data', text)
        self.assertEqual(self.work(), [])
        older = self.session.call('entity_studio', {'action': 'status'})
        self.assertFalse(older['result']['isError'])
        self.assertEqual(self.work(), ['entity_studio'])

    def test_a_current_bridge_takes_the_entity_studio_additions(self):
        self.start('1.0.27')
        response = self.session.call('entity_studio_edit', {'action': 'build', 'type': 'bifold', 'opening': {'wall_id': 1, 'index': 0}, 'dry_run': True})
        self.assertFalse(response['result']['isError'])
        self.assertEqual(self.work(), ['entity_studio_edit'])



class NaWindowChoiceTests(unittest.TestCase):
    """The server stays on the window it is using: opening another never moves later calls."""

    # Odd numbers: no Windows process has one, so a stopped fake reads as a closed window.
    FIRST, SECOND, THIRD = 3999991, 3999993, 3999995

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp(prefix='na_mcp_windows_')
        os.environ['NA_SKETCHUP_MCP_CONNECTIONS_DIR'] = self.temp_dir
        os.environ.pop('NA_SKETCHUP_MCP_PID', None)
        self.bridges = []
        self.sessions = []
        self.first = self.window(self.FIRST, '09', 'First Model')
        self.client = Na__BridgeClientModule.Na__BridgeClient()

    def tearDown(self):
        for session in self.sessions:
            session.close()
        for bridge in self.bridges:
            bridge.stop()
        os.environ.pop('NA_SKETCHUP_MCP_CONNECTIONS_DIR', None)
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def window(self, pid, hour, title, **options):
        bridge = NaFakeBridge(self.temp_dir, pid=pid, started_at='2026-11-05T%s:00:00Z' % hour, file_title=title, **options)
        self.bridges.append(bridge)
        return bridge

    def commands(self, bridge):
        return [request['command'] for request in bridge.requests]

    def work(self, bridge):
        """Everything sent to a window except the pings that read its title."""
        return [command for command in self.commands(bridge) if command != 'ping']

    def call(self, command='model_info'):
        return self.client.Na__BridgeClient__Request(command, {}, 5)

    def session(self):
        env = dict(os.environ, NA_SKETCHUP_MCP_CONNECTIONS_DIR=self.temp_dir, PYTHONUTF8='1')
        env.pop('NA_SKETCHUP_MCP_PORT', None)
        session = NaMcpSession(env)
        session.request('initialize', {'protocolVersion': '2025-11-25', 'capabilities': {}, 'clientInfo': {'name': 'tests', 'version': '1'}})
        session.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
        self.sessions.append(session)
        return session

    def status(self, session, **arguments):
        return json.loads(session.call('sketchup_status', arguments)['result']['content'][0]['text'])

    # --- the fault: a new window took every later call ---------------------------------

    def test_a_new_window_does_not_take_over(self):
        self.call('ping')
        second = self.window(self.SECOND, '10', 'Second Model')
        self.call('geometry_create_solid')
        self.assertEqual(self.commands(self.first), ['ping', 'geometry_create_solid'])
        self.assertEqual(second.requests, [])

    def test_with_two_open_the_first_call_takes_the_newest_and_stays(self):
        second = self.window(self.SECOND, '10', 'Second Model')
        self.call()
        third = self.window(self.THIRD, '11', 'Third Model')
        self.call()
        self.assertEqual(self.commands(second), ['model_info', 'model_info'])
        self.assertEqual(self.first.requests + third.requests, [])

    # --- when the window goes: refuse, never pick another --------------------------------

    def test_a_closed_window_refuses_and_lists_the_others(self):
        self.call()
        second = self.window(self.SECOND, '10', 'Second Model')
        self.first.stop()
        with self.assertRaises(Na__BridgeClientModule.Na__BridgeUnavailable) as caught:
            self.call('geometry_create_solid')
        self.assertEqual(caught.exception.na_code, 'not_connected')
        self.assertIn(str(self.FIRST), caught.exception.na_message)
        self.assertIn(str(self.SECOND), caught.exception.na_message)
        self.assertIn('Second Model', caught.exception.na_message)
        self.assertIn('select_pid', caught.exception.na_hint)
        self.assertEqual(self.work(second), [])

    def test_a_closed_window_with_none_left_says_so(self):
        self.call()
        self.first.stop()
        with self.assertRaises(Na__BridgeClientModule.Na__BridgeUnavailable) as caught:
            self.call()
        self.assertIn(str(self.FIRST), caught.exception.na_message)
        self.assertIn('No other', caught.exception.na_message)

    def test_a_window_opened_after_the_close_is_not_picked_either(self):
        self.call()
        self.first.stop()
        reopened = self.window(self.SECOND, '10', 'Reopened Model')
        with self.assertRaises(Na__BridgeClientModule.Na__BridgeUnavailable):
            self.call('geometry_create_solid')
        self.assertEqual(self.work(reopened), [])
        self.client.Na__BridgeClient__Select(self.SECOND)
        self.call('geometry_create_solid')
        self.assertEqual(self.work(reopened), ['geometry_create_solid'])

    # --- what must not change ------------------------------------------------------------

    def test_select_moves_it_and_it_stays_there(self):
        self.call()
        second = self.window(self.SECOND, '10', 'Second Model')
        self.client.Na__BridgeClient__Select(self.SECOND)
        self.call()
        third = self.window(self.THIRD, '11', 'Third Model')
        self.call()
        self.assertEqual(self.commands(self.first), ['model_info'])
        self.assertEqual(self.commands(second), ['model_info', 'model_info'])
        self.assertEqual(third.requests, [])

    def test_a_restarted_bridge_in_the_same_window_is_still_reached(self):
        self.call()
        self.first.stop()
        restarted = self.window(self.FIRST, '12', 'First Model', token='token-after-reload')
        self.call()
        self.assertEqual(self.commands(restarted), ['model_info'])

    def test_the_pid_variable_still_chooses_the_window(self):
        second = self.window(self.SECOND, '10', 'Second Model')
        os.environ['NA_SKETCHUP_MCP_PID'] = str(self.FIRST)
        try:
            client = Na__BridgeClientModule.Na__BridgeClient()
            client.Na__BridgeClient__Request('model_info', {}, 5)
        finally:
            os.environ.pop('NA_SKETCHUP_MCP_PID', None)
        self.assertEqual(self.commands(self.first), ['model_info'])
        self.assertEqual(second.requests, [])

    # --- sketchup_status, through the real server ----------------------------------------

    def test_status_names_the_window_in_use_before_any_selection(self):
        self.window(self.SECOND, '10', 'Second Model')
        status = self.status(self.session())
        marked = {item['pid']: item['selected'] for item in status['instances']}
        self.assertEqual(marked, {self.FIRST: False, self.SECOND: True})
        self.assertEqual(status['selected_pid'], self.SECOND)
        self.assertEqual(status['model']['title'], 'Second Model')

    def test_status_says_when_more_than_one_window_is_open(self):
        session = self.session()
        self.assertNotIn('windows_note', self.status(session))
        self.window(self.SECOND, '10', 'Second Model')
        note = self.status(session).get('windows_note', '')
        self.assertIn(str(self.FIRST), note)
        self.assertIn('select_pid', note)

    def test_status_stays_on_the_window_when_another_opens(self):
        session = self.session()
        self.status(session)
        self.window(self.SECOND, '10', 'Second Model')
        status = self.status(session)
        self.assertEqual(status['selected_pid'], self.FIRST)
        self.assertEqual(status['model']['title'], 'First Model')

    def test_status_titles_are_the_models_open_now(self):
        self.window(self.SECOND, '10', '', live_title='Opened After The Bridge Started')
        titles = {item['pid']: item['model_title'] for item in self.status(self.session())['instances']}
        self.assertEqual(titles[self.SECOND], 'Opened After The Bridge Started')
        self.assertEqual(titles[self.FIRST], 'First Model')

    def test_status_and_tools_after_the_window_closes(self):
        session = self.session()
        self.status(session)
        second = self.window(self.SECOND, '10', 'Second Model')
        self.first.stop()
        status = self.status(session)
        self.assertFalse(status['connected'])
        self.assertIn('Second Model', status['message'])
        self.assertIn('select_pid', status['how_to_fix'])
        self.assertEqual([(item['pid'], item['selected']) for item in status['instances']], [(self.SECOND, False)])
        tool = session.call('entity_query', {})['result']
        self.assertTrue(tool['isError'])
        self.assertIn('Second Model', tool['content'][0]['text'])
        self.assertEqual(self.work(second), [])
        status = self.status(session, select_pid=self.SECOND)
        self.assertTrue(status['connected'])
        self.assertEqual(status['model']['title'], 'Second Model')

    # --- 1.0.18: a closed window's file on a port another window took ---------------------

    def test_a_stale_file_on_a_port_another_window_took_is_not_live(self):
        stale = os.path.join(self.temp_dir, 'Na__SketchUpMcp__Connection__%d.json' % self.THIRD)
        with open(stale, 'w', encoding='utf-8') as handle:
            json.dump({'pid': self.THIRD, 'host': '127.0.0.1', 'port': self.first.port, 'token': 'an-old-token',
                       'model_title': 'Closed Long Ago', 'started_at': '2026-11-05T12:00:00Z'}, handle)
        live = {item['pid']: item['live'] for item in self.client.Na__BridgeClient__Instances()}
        self.assertEqual(live, {self.FIRST: True})
        self.assertFalse(os.path.exists(stale))

    # --- 1.0.18: sketchup_open_window (never launches SketchUp here) ----------------------

    def open_window(self, session, **arguments):
        return session.call('sketchup_open_window', arguments)['result']

    def test_open_window_refuses_what_is_not_a_skp(self):
        result = self.open_window(self.session(), path=os.path.join(self.temp_dir, 'notes.txt'))
        self.assertTrue(result['isError'])
        self.assertIn('invalid_params', result['content'][0]['text'])

    def test_open_window_refuses_a_missing_file(self):
        result = self.open_window(self.session(), path=os.path.join(self.temp_dir, 'Missing__Model.skp'))
        self.assertTrue(result['isError'])
        self.assertIn('not_found', result['content'][0]['text'])

    def test_open_window_uses_the_window_that_has_it_open(self):
        model = os.path.join(self.temp_dir, 'RB05__Model.skp')
        with open(model, 'wb') as handle:
            handle.write(b'skp')
        self.window(self.SECOND, '10', 'RB05__Model', model_path=model)
        session = self.session()
        result = self.open_window(session, path=model)
        self.assertFalse(result['isError'])
        payload = json.loads(result['content'][0]['text'])
        self.assertTrue(payload['already_open'])
        self.assertEqual(payload['pid'], self.SECOND)
        self.assertEqual(self.status(session)['selected_pid'], self.SECOND)

    def test_open_window_never_copies_over_a_copy_that_is_open(self):
        source = os.path.join(self.temp_dir, 'NP03__Model.skp')
        copy_dir = os.path.join(self.temp_dir, 'survey')
        os.makedirs(copy_dir)
        for path in (source, os.path.join(copy_dir, 'NP03__Model.skp')):
            with open(path, 'wb') as handle:
                handle.write(b'skp')
        self.window(self.SECOND, '10', 'NP03__Model', model_path=os.path.join(copy_dir, 'NP03__Model.skp'))
        result = self.open_window(self.session(), path=source, copy_to=copy_dir, overwrite=True)
        self.assertTrue(result['isError'])
        self.assertIn('in_use', result['content'][0]['text'])

    def test_open_window_never_replaces_an_existing_copy_unasked(self):
        source = os.path.join(self.temp_dir, 'EB03__Model.skp')
        target = os.path.join(self.temp_dir, 'EB03__Copy.skp')
        for path in (source, target):
            with open(path, 'wb') as handle:
                handle.write(b'skp')
        result = self.open_window(self.session(), path=source, copy_to=target)
        self.assertTrue(result['isError'])
        self.assertIn('already_exists', result['content'][0]['text'])

    # --- 1.0.18: sketchup_close_window ----------------------------------------------------

    def close_window(self, session, **arguments):
        return session.call('sketchup_close_window', arguments)['result']

    def test_close_window_refuses_an_unknown_pid(self):
        result = self.close_window(self.session(), pid=self.THIRD)
        self.assertTrue(result['isError'])
        self.assertIn('not_found', result['content'][0]['text'])

    def test_close_window_refuses_unsaved_changes(self):
        second = self.window(self.SECOND, '10', 'Changed Model', modified=True)
        result = self.close_window(self.session(), pid=self.SECOND)
        self.assertTrue(result['isError'])
        self.assertIn('unsaved_changes', result['content'][0]['text'])
        self.assertNotIn('ruby_eval', self.commands(second))

    def test_close_window_quits_a_saved_window_through_its_own_bridge(self):
        second = self.window(self.SECOND, '10', 'Saved Model')
        result = self.close_window(self.session(), pid=self.SECOND)
        self.assertFalse(result['isError'])
        self.assertTrue(json.loads(result['content'][0]['text'])['closed'])
        quit_calls = [request for request in second.requests if request['command'] == 'ruby_eval']
        self.assertEqual(len(quit_calls), 1)
        self.assertIn('Sketchup.quit', quit_calls[0]['params']['code'])
        self.assertNotIn('close(true)', quit_calls[0]['params']['code'])

    def test_close_window_discards_only_when_told(self):
        second = self.window(self.SECOND, '10', 'Changed Model', modified=True)
        result = self.close_window(self.session(), pid=self.SECOND, discard_unsaved_changes=True)
        self.assertFalse(result['isError'])
        quit_calls = [request for request in second.requests if request['command'] == 'ruby_eval']
        self.assertIn('close(true)', quit_calls[0]['params']['code'])

# endregion -------------------------------------------------------------------


if __name__ == '__main__':
    unittest.main(verbosity=1)

# =============================================================================
# END OF FILE
# =============================================================================
