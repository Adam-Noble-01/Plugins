# =============================================================================
# NA SKETCHUP MCP - PYTHON SERVER - BRIDGE CLIENT
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Server__BridgeClient__.py
# PURPOSE    : Find running SketchUp bridges and send them requests over TCP
# CREATED    : 2026
#
# DISCOVERY (zero configuration):
# Each SketchUp process running the Na SketchUp MCP extension writes
# 91__UserConfig__LocalOnly/Connections/Na__SketchUpMcp__Connection__<pid>.json
# with its port and a fresh session token. This client lists those files,
# checks which are alive, deletes ones left by crashed processes, and targets
# the most recently started live SketchUp unless another pid was selected.
# Overrides for special setups: NA_SKETCHUP_MCP_PID, NA_SKETCHUP_MCP_PORT +
# NA_SKETCHUP_MCP_TOKEN, NA_SKETCHUP_MCP_CONNECTIONS_DIR.
#
# RETRY POLICY (never duplicate geometry):
# - Refused connection or an 'unauthorized' reply: the request never ran, so it
#   is re-sent once after re-reading the connection files.
# - Timeout or a connection lost mid-reply: the request MAY have run. It is
#   never retried; the caller is told to check the model first.
#
# WIRE FORMAT: one JSON object per line each way (see the Ruby
# Na__SketchUpMcp__BridgeCore__SocketServer__.rb header).
#
# =============================================================================

import ctypes
import glob
import json
import os
import socket
import sys
import threading
import uuid

NA_SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
NA_MODULES_ROOT = os.path.abspath(os.path.join(NA_SERVER_DIR, '..'))
NA_DEFAULT_CONNECTIONS_DIR = os.path.join(NA_MODULES_ROOT, '91__UserConfig__LocalOnly', 'Connections')
NA_CONNECT_TIMEOUT_S = 2.0
NA_PROBE_TIMEOUT_S = 0.3
NA_MAX_RESPONSE_BYTES = 256 * 1024 * 1024


# -----------------------------------------------------------------------------
# REGION | Errors
# -----------------------------------------------------------------------------

class Na__BridgeError(Exception):
    """A bridge failure with a message and a hint naming the fix."""

    def __init__(self, code, message, hint=None):
        super().__init__(message)
        self.na_code = code
        self.na_message = message
        self.na_hint = hint


class Na__BridgeUnavailable(Na__BridgeError):
    pass


class Na__BridgeTimeout(Na__BridgeError):
    pass


class Na__BridgeLost(Na__BridgeError):
    pass

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Process Liveness (never os.kill on Windows: it terminates the process)
# -----------------------------------------------------------------------------

def na_pid_running(pid):
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    if sys.platform == 'win32':
        process_query_limited_information = 0x1000
        still_active = 259
        kernel32 = ctypes.windll.kernel32
        handle = kernel32.OpenProcess(process_query_limited_information, False, pid)
        if not handle:
            return False
        try:
            exit_code = ctypes.c_ulong()
            if not kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code)):
                return False
            return exit_code.value == still_active
        finally:
            kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def na_port_open(host, port, timeout_s=NA_PROBE_TIMEOUT_S):
    try:
        with socket.create_connection((host, int(port)), timeout=timeout_s):
            return True
    except (OSError, ValueError):
        return False

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Bridge Client
# -----------------------------------------------------------------------------

class Na__BridgeClient:
    """Discovers SketchUp bridges and sends requests; remembers the selected SketchUp."""

    def __init__(self, logger=None):
        self.na_connections_dir = os.environ.get('NA_SKETCHUP_MCP_CONNECTIONS_DIR', NA_DEFAULT_CONNECTIONS_DIR)
        self.na_selected_pid = int(os.environ['NA_SKETCHUP_MCP_PID']) if os.environ.get('NA_SKETCHUP_MCP_PID', '').isdigit() else None
        self.na_logger = logger
        self.na_lock = threading.Lock()

    # --- discovery -------------------------------------------------------------

    def Na__BridgeClient__Instances(self, clean_stale=True):
        """Every connection file, newest first, each marked live or not."""
        instances = []
        for path in glob.glob(os.path.join(self.na_connections_dir, 'Na__SketchUpMcp__Connection__*.json')):
            try:
                with open(path, encoding='utf-8') as handle:
                    data = json.load(handle)
            except (OSError, ValueError):
                continue
            data['file'] = path
            data['live'] = na_port_open(data.get('host', '127.0.0.1'), data.get('port', 0))
            if not data['live'] and clean_stale and not na_pid_running(data.get('pid')):
                self.na_log('Removing stale connection file for pid %s' % data.get('pid'))
                try:
                    os.remove(path)
                except OSError:
                    pass
                continue
            instances.append(data)
        instances.sort(key=lambda item: item.get('started_at', ''), reverse=True)
        return instances

    def Na__BridgeClient__Select(self, pid):
        with self.na_lock:
            match = [item for item in self.Na__BridgeClient__Instances() if int(item.get('pid', -1)) == int(pid)]
            if not match or not match[0]['live']:
                raise Na__BridgeUnavailable('not_found', 'No live SketchUp bridge with pid %s.' % pid,
                                            'Call sketchup_status to list the running SketchUp windows.')
            self.na_selected_pid = int(pid)
            return match[0]

    def Na__BridgeClient__Target(self):
        manual_port = os.environ.get('NA_SKETCHUP_MCP_PORT')
        if manual_port:
            return {'host': os.environ.get('NA_SKETCHUP_MCP_HOST', '127.0.0.1'), 'port': int(manual_port),
                    'token': os.environ.get('NA_SKETCHUP_MCP_TOKEN', ''), 'pid': None, 'manual': True}

        live = [item for item in self.Na__BridgeClient__Instances() if item['live']]
        if self.na_selected_pid is not None:
            chosen = [item for item in live if int(item.get('pid', -1)) == self.na_selected_pid]
            if chosen:
                return chosen[0]
            raise Na__BridgeUnavailable('not_connected', 'The selected SketchUp (pid %s) is no longer running its bridge.' % self.na_selected_pid,
                                        'Call sketchup_status to choose another SketchUp window (select_pid).')
        if live:
            return live[0]
        raise Na__BridgeUnavailable(
            'not_connected',
            'SketchUp is not connected: no running SketchUp bridge was found.',
            'Open SketchUp 2026 with the Na SketchUp MCP extension (it starts the bridge by itself), or turn it on with '
            'Extensions > Na SketchUp MCP > Bridge Running. Connection files are read from: %s' % self.na_connections_dir)

    # --- requests --------------------------------------------------------------

    def Na__BridgeClient__Request(self, command, params, timeout_s=60.0):
        """Send one command; return the bridge's response envelope (dict with ok/result or error)."""
        for attempt in (1, 2):
            target = self.Na__BridgeClient__Target()
            payload = {'id': uuid.uuid4().hex, 'token': target.get('token', ''), 'command': command, 'params': params or {}}
            try:
                response = self.na_round_trip(target, payload, timeout_s)
            except ConnectionRefusedError:
                if attempt == 1:
                    continue  # never ran: the bridge restarted; re-read the connection files
                raise Na__BridgeUnavailable('not_connected', 'SketchUp refused the connection.',
                                            'The bridge may have just been stopped. Check Extensions > Na SketchUp MCP > Bridge Running.')
            error = response.get('error') or {}
            if not response.get('ok') and error.get('code') == 'unauthorized' and attempt == 1:
                continue  # never ran: token changed after a bridge restart
            return response
        return response

    def na_round_trip(self, target, payload, timeout_s):
        line = (json.dumps(payload, separators=(',', ':'), ensure_ascii=True) + '\n').encode('utf-8')
        try:
            sock = socket.create_connection((target['host'], int(target['port'])), timeout=NA_CONNECT_TIMEOUT_S)
        except ConnectionRefusedError:
            raise
        except OSError as error:
            raise Na__BridgeUnavailable('not_connected', 'Could not reach SketchUp at %s:%s (%s).' % (target['host'], target['port'], error),
                                        'Is SketchUp open with the bridge running?')
        try:
            sock.settimeout(timeout_s)
            sock.sendall(line)
            buffer = bytearray()
            while True:
                chunk = sock.recv(1024 * 1024)
                if not chunk:
                    break
                buffer.extend(chunk)
                if b'\n' in chunk:
                    break
                if len(buffer) > NA_MAX_RESPONSE_BYTES:
                    raise Na__BridgeLost('too_large', 'SketchUp sent more than 256 MB.', 'Ask for less (limit, response_format).')
        except socket.timeout:
            raise Na__BridgeTimeout(
                'timeout',
                'SketchUp did not answer %s within %.0f s.' % (payload['command'], timeout_s),
                'It may still be working (big model) or waiting on a dialog. Do NOT repeat a model-changing call blindly: '
                'check the model with entity_query or sketchup_status first.')
        except (ConnectionResetError, ConnectionAbortedError, BrokenPipeError) as error:
            raise Na__BridgeLost('connection_lost', 'The connection to SketchUp dropped during %s (%s).' % (payload['command'], error),
                                 'SketchUp may have closed or crashed. The call may or may not have run: check before repeating it.')
        finally:
            sock.close()

        text = bytes(buffer).split(b'\n', 1)[0].decode('utf-8', errors='replace').strip()
        if not text:
            raise Na__BridgeLost('empty_response', 'SketchUp closed the connection without answering %s.' % payload['command'],
                                 'Check SketchUp is responsive; the call may or may not have run.')
        try:
            return json.loads(text)
        except ValueError:
            raise Na__BridgeLost('bad_response', 'SketchUp sent an unreadable reply to %s.' % payload['command'],
                                 'Reload the plugin (Extensions > Na SketchUp MCP > Reload Plugin Data).')

    def na_log(self, text):
        if self.na_logger:
            self.na_logger(text)

# endregion -------------------------------------------------------------------

# =============================================================================
# END OF FILE
# =============================================================================
