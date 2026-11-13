# =============================================================================
# NA SKETCHUP MCP - PYTHON SERVER - TOOL RUNNER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Server__ToolRunner__.py
# PURPOSE    : Execute one tools/call: validate arguments, run server-side tools
#              locally, forward the rest to SketchUp, shape the MCP result
# CREATED    : 2026
#
# RESULT SHAPE (CallToolResult):
# - success: one compact JSON text block (the handler's result plus
#   "warnings" and "undo_step" when present) and, for view_capture, an image
#   block per picture. Text is capped at NA_MAX_TEXT_CHARS so a single call
#   can never flood the agent's context; the cap names how to narrow the query.
# - failure: isError true and a plain text "Error (code): message / Fix: hint",
#   so the model can read it and correct its next call (MCP 2025-11-25:
#   argument validation failures are tool errors, not protocol errors).
# - the Agent Outliner notice (1.0.28): while Adam's messages wait for an
#   agent, the bridge's response carries 'outliner'. It goes FIRST in the JSON
#   (seen before anything else, never cut by the text cap), or as a last line
#   of an error. A bridge before 1.0.28 sends none, and nothing is added.
#
# SERVER-SIDE WORK BEFORE SKETCHUP IS ASKED:
# - arguments are validated against the tool schema;
# - model_file export/import options are checked against SketchUp's
#   documented exporter/importer options;
# - ruby_eval code is linted against the API index (warnings, never blocking);
# - batch_execute steps are validated one by one (with $ref strings allowed).
#
# WAITING FOR ADAM (1.0.30):
# input_pick and proposal_preview {action: "wait"} wait HERE, never inside
# SketchUp: the server polls the bridge with short calls (result / status)
# until Adam finishes, cancels or answers, he writes in the Agent Outliner, or
# wait_s runs out. SketchUp keeps running between polls.
#
# =============================================================================

import base64
import json
import os
import platform
import sys
import time

import Na__SketchUpMcp__Server__BridgeClient__ as Na__BridgeClientModule
import Na__SketchUpMcp__Server__SchemaValidator__ as Na__SchemaValidator
import Na__SketchUpMcp__Server__WindowLauncher__ as Na__WindowLauncher

NA_MAX_TEXT_CHARS = 45000
NA_MAX_IMAGE_BYTES = 12 * 1024 * 1024

# Exporter / importer option groups in the API index, by file extension.
NA_EXPORT_FORMATS = {
    '.3ds': ['3ds Max (3DS)'], '.dwg': ['3D Autocad (DWG/DXF)'], '.dxf': ['3D Autocad (DWG/DXF)'],
    '.dae': ['Collada (DAE)'], '.fbx': ['Filmbox Autodesk (FBX)'], '.kmz': ['Google Earth (KMZ)'],
    '.glb': ['Graphics Library Transmission Format Binary File (GLB)'],
    '.ifc': ['Industry Foundation Classes (IFC) - Options for SketchUp 2026+', 'Industry Foundation Classes (IFC) - Options for older SketchUp versions'],
    '.pdf': ['Portable Document Format (PDF) - Windows', 'Portable Document Format (PDF) - Mac'],
    '.stl': ['STereoLithography (STL)'], '.xsi': ['Softimage XSI 3D Image (XSI)'],
    '.usdz': ['Universal Scene Description (USDZ)'], '.wrl': ['Virtual Reality Modeling Language (WRL)'],
    '.obj': ['Wavefront Object (OBJ)']
}
NA_IMPORT_FORMATS = {
    '.3ds': ['3ds Max (3DS)'], '.dae': ['Collada (DAE)'], '.dem': ['Digital Elevation Model (DEM/DDF)'],
    '.ddf': ['Digital Elevation Model (DEM/DDF)'], '.dwg': ['3D Autocad (DWG/DXF)'], '.dxf': ['3D Autocad (DWG/DXF)'],
    '.kmz': ['Google Earth (KMZ)'], '.stl': ['STereoLithography (STL)']
}
NA_BATCH_FORBIDDEN = {'batch_execute': 'batches cannot nest', 'model_file': 'call model_file on its own',
                      'input_pick': 'it hands SketchUp to Adam and waits for him; call it on its own',
                      'proposal_preview': 'it asks Adam in the Agent Outliner; call it on its own',
                      'point_cloud_ortho_plane': 'it captures in an undo operation it always aborts, then places the plane in its own; call it on its own'}

# Tools whose action "wait" is answered by polling: (poll action, default wait_s, seconds between polls).
NA_WAIT_TOOLS = {'input_pick': ('result', 180, 0.5), 'proposal_preview': ('status', 300, 2.0)}


class Na__UnknownTool(Exception):
    """tools/call named a tool this server does not have (a protocol error, -32602)."""


# -----------------------------------------------------------------------------
# REGION | Runner
# -----------------------------------------------------------------------------

class Na__ToolRunner:
    """Validates and executes tool calls; holds references to the shared services."""

    def __init__(self, registry, bridge, api_index, server_facts):
        self.na_registry = registry
        self.na_bridge = bridge
        self.na_api_index = api_index
        self.na_server_facts = server_facts

    def Na__ToolRunner__Call(self, name, arguments):
        tool = self.na_registry.Na__ToolRegistry__ByName(name)
        if tool is None:
            raise Na__UnknownTool(name)
        arguments = arguments if isinstance(arguments, dict) else {}

        problems = Na__SchemaValidator.Na__SchemaValidator__Validate(tool['input_schema'], arguments)
        if problems:
            return na_error_result('invalid_params', 'Invalid arguments for %s:\n- %s' % (name, '\n- '.join(problems)),
                                   'Correct the arguments to match the tool schema and call again.')
        try:
            if name == 'sketchup_status':
                return self.na_status(tool, arguments)
            if name == 'ruby_api_lookup':
                return self.na_api_lookup(arguments)
            if name == 'sketchup_open_window':
                return na_success_result(Na__WindowLauncher.Na__WindowLauncher__Open(self.na_bridge, arguments))
            if name == 'sketchup_close_window':
                return na_success_result(Na__WindowLauncher.Na__WindowLauncher__Close(self.na_bridge, arguments))
            if name == 'batch_execute':
                return self.na_batch(tool, arguments)
            if name == 'model_file':
                problem = self.na_check_file_options(arguments)
                if problem:
                    return problem
            if name == 'ruby_eval':
                return self.na_ruby_eval(tool, arguments)
            if name in NA_WAIT_TOOLS and arguments.get('action') == 'wait':
                return self.na_wait(tool, arguments)
            too_old = self.na_too_old([(name, arguments)])
            if too_old:
                return too_old
            return self.na_bridge_call(tool, arguments)
        except Na__BridgeClientModule.Na__BridgeError as error:
            return na_error_result(error.na_code, error.na_message, error.na_hint)

    # --- bridge ------------------------------------------------------------------

    def na_bridge_call(self, tool, arguments, timeout_s=None, extra=None):
        response = self.na_bridge.Na__BridgeClient__Request(tool['name'], arguments, timeout_s or tool.get('timeout_s', 60))
        return na_result_from_response(response, extra)

    def na_too_old(self, calls):
        """An error result when a call uses a parameter, or a value such as an action, newer than the window's bridge
        (registry property_since: "tool.parameter" or "tool.parameter=value"): that bridge would ignore the parameter and
        answer as if it were not there, or refuse the value without naming the fix. The version comes from a ping (what the
        window runs now: a data reload does not rewrite its connection file). None when all is well or unknown."""
        since = self.na_registry.Na__ToolRegistry__PropertySince()
        needed = []
        for name, arguments in calls:
            for key, value in (arguments or {}).items():
                version = since.get('%s.%s' % (name, key))
                if version and na_version(version):
                    needed.append(('%s %s' % (name, key), version))
                if isinstance(value, str):                       # a value added later, e.g. "agent_outliner.action=flags"
                    version = since.get('%s.%s=%s' % (name, key, value))
                    if version and na_version(version):
                        needed.append(('%s %s "%s"' % (name, key, value), version))
        if not needed:
            return None
        response = self.na_bridge.Na__BridgeClient__Request('ping', {}, 10)
        result = (response or {}).get('result') or {}
        have = result.get('bridge_version')
        if not response.get('ok') or not na_version(have):
            return None
        older = [(what, version) for what, version in needed if na_version(have) < na_version(version)]
        if not older:
            return None
        what, version = max(older, key=lambda item: na_version(item[1]))
        point_cloud = what.startswith('point_cloud')
        return na_error_result(
            'unsupported',
            "This SketchUp window (pid %s) runs bridge %s; %s needs %s, which that bridge does not know (it would ignore it and answer wrongly, "
            'or refuse it). Nothing was sent.' % (result.get('pid'), have, what, version),
            'In that window run Extensions > Na SketchUp MCP > Reload Plugin Data%s, then call again.'
            % (" (and the Point Cloud Viewer's Reload Plugin first)" if point_cloud else ''))

    # --- waiting for Adam (input_pick, proposal_preview) ---------------------------------

    def na_wait(self, tool, arguments):
        """Poll the bridge until Adam has finished (input_pick: status no longer 'waiting'; proposal_preview: answered),
        he writes in the Agent Outliner (the notice), or wait_s runs out. Each poll is a short call, so SketchUp keeps
        running: the waiting is here, never inside SketchUp."""
        name = tool['name']
        poll_action, default_wait, interval = NA_WAIT_TOOLS[name]
        wait_s = float(arguments.get('wait_s') or default_wait)
        deadline = time.monotonic() + wait_s
        poll = dict((key, value) for key, value in arguments.items() if key not in ('action', 'wait_s'))
        poll['action'] = poll_action
        polls = 0
        while True:
            response = self.na_bridge.Na__BridgeClient__Request(name, poll, 30)
            polls += 1
            if not response.get('ok'):
                return na_result_from_response(response)
            result = response.get('result') or {}
            done = result.get('status') != 'waiting' if name == 'input_pick' else bool(result.get('answered'))
            spoke = na_notice(response) is not None
            out_of_time = time.monotonic() >= deadline
            if done or spoke or out_of_time:
                extra = {'waited': {'polls': polls, 'seconds_allowed': wait_s}}
                if not done:
                    extra['waited']['stopped'] = 'Adam wrote in the Agent Outliner: read it first' if spoke else 'wait_s ran out'
                    extra['waited']['next'] = ('Ask Adam in chat whether he is still on it, then wait again or cancel.' if name == 'input_pick'
                                               else 'He may have answered in chat. Wait again, or ask him; build nothing until he says yes.')
                return na_result_from_response(response, extra)
            time.sleep(interval)

    # --- sketchup_status -------------------------------------------------------------

    def na_status(self, tool, arguments):
        if arguments.get('select_pid') is not None:
            self.na_bridge.Na__BridgeClient__Select(arguments['select_pid'])
        try:
            self.na_bridge.Na__BridgeClient__Target()       # settles the window in use, so the list below can mark it
        except Na__BridgeClientModule.Na__BridgeError:
            pass                                            # reported below, with the list

        windows = self.na_bridge.Na__BridgeClient__Windows()
        in_use = self.na_bridge.na_selected_pid
        instances = [{
            'pid': item.get('pid'), 'port': item.get('port'), 'model_title': item.get('model_title'),
            'model_path': item.get('model_path'), 'sketchup_version': item.get('sketchup_version'), 'live': item.get('live'),
            'selected': in_use == item.get('pid')
        } for item in windows]

        payload = {'server': self.na_server_facts, 'instances': instances}
        current = [item for item in windows if item['live'] and item.get('pid') == in_use]
        if current:
            payload['selected_pid'] = in_use
            open_count = sum(1 for item in windows if item['live'])
            if open_count > 1:
                payload['windows_note'] = ('%d SketchUp windows are open. This server is using pid %s (%s) and stays on it, whichever opens later. '
                                           'To use another, pass select_pid.' % (open_count, in_use, current[0].get('model_title') or 'untitled'))
        try:
            response = self.na_bridge.Na__BridgeClient__Request('sketchup_status', {'include_extensions': bool(arguments.get('include_extensions'))}, tool.get('timeout_s', 15))
        except Na__BridgeClientModule.Na__BridgeError as error:
            payload.update({'connected': False, 'message': error.na_message, 'how_to_fix': error.na_hint})
            return na_success_result(payload)
        if not response.get('ok'):
            return na_result_from_response(response)
        payload['connected'] = True
        payload.update(response.get('result', {}))
        if response.get('warnings'):
            payload['warnings'] = response['warnings']
        return na_success_result(na_with_notice(payload, response))

    # --- ruby_api_lookup -------------------------------------------------------------

    def na_api_lookup(self, arguments):
        if not arguments.get('query') and not arguments.get('code'):
            return na_error_result('invalid_params', 'Pass query or code.', 'query: "Face#pushpull", "Sketchup::Layer", "section plane"; code: Ruby to check.')
        payload = {'index': self.na_api_index.Na__ApiIndex__Facts()}
        if arguments.get('query'):
            payload['lookup'] = self.na_api_index.Na__ApiIndex__Lookup(arguments['query'], arguments.get('limit', 12), arguments.get('include_examples', True))
        if arguments.get('code'):
            payload['lint'] = self.na_api_index.Na__ApiIndex__Lint(arguments['code'])
        if arguments.get('live') and payload.get('lookup', {}).get('results'):
            signatures = self.na_api_index.Na__ApiIndex__Signatures(payload['lookup']['results'])
            if signatures:
                try:
                    response = self.na_bridge.Na__BridgeClient__Request('api_probe', {'signatures': signatures}, 15)
                    payload['live_in_running_sketchup'] = response.get('result', {}).get('results') if response.get('ok') else response.get('error')
                except Na__BridgeClientModule.Na__BridgeError as error:
                    payload['live_in_running_sketchup'] = 'SketchUp not connected: %s' % error.na_message
        return na_success_result(payload)

    # --- ruby_eval ---------------------------------------------------------------------

    def na_ruby_eval(self, tool, arguments):
        lint = self.na_api_index.Na__ApiIndex__Lint(arguments.get('code', ''))
        extra = None
        if lint['unknown_methods'] or lint['unknown_constants']:
            extra = {'api_lint': {'unknown_methods': lint['unknown_methods'], 'unknown_constants': lint['unknown_constants'], 'note': lint['note']}}
        return self.na_bridge_call(tool, arguments, extra=extra)

    # --- batch_execute -------------------------------------------------------------------

    def na_batch(self, tool, arguments):
        atomic = arguments.get('atomic', True)
        problems = []
        total_timeout = 0
        lint_notes = []
        for index, step in enumerate(arguments.get('steps', [])):
            step_name = step.get('tool')
            step_tool = self.na_registry.Na__ToolRegistry__AnyByName(step_name)
            if step_tool is None:
                problems.append('steps[%d]: unknown tool %r.' % (index, step_name))
                continue
            if step_tool.get('runs_on') == 'server' or step_name == 'sketchup_status':
                problems.append('steps[%d]: %s answers on its own; call it outside the batch.' % (index, step_name))
                continue
            if step_name in NA_BATCH_FORBIDDEN:
                problems.append('steps[%d]: %s is not allowed in a batch (%s).' % (index, step_name, NA_BATCH_FORBIDDEN[step_name]))
                continue
            if step_name == 'context_set' and atomic:
                problems.append('steps[%d]: context_set splits the undo operation; call it before the batch or pass atomic:false.' % index)
                continue
            problems.extend(Na__SchemaValidator.Na__SchemaValidator__Validate(
                step_tool['input_schema'], step.get('arguments', {}) or {}, 'steps[%d].arguments' % index, allow_references=True))
            total_timeout += step_tool.get('timeout_s', 60)
            if step_name == 'ruby_eval':
                lint = self.na_api_index.Na__ApiIndex__Lint((step.get('arguments') or {}).get('code', ''))
                if lint['unknown_methods'] or lint['unknown_constants']:
                    lint_notes.append({'step': index, 'unknown_methods': lint['unknown_methods'], 'unknown_constants': lint['unknown_constants']})
        if problems:
            return na_error_result('invalid_params', 'The batch was not run:\n- %s' % '\n- '.join(problems[:20]),
                                   'Fix those steps and send the whole batch again.')
        extra = {'api_lint': lint_notes} if lint_notes else None
        too_old = self.na_too_old([(step.get('tool'), step.get('arguments') or {}) for step in arguments.get('steps', [])])
        if too_old:
            return too_old
        return self.na_bridge_call(tool, arguments, timeout_s=min(max(total_timeout, 60), 1800), extra=extra)

    # --- model_file option check -----------------------------------------------------------

    def na_check_file_options(self, arguments):
        action = arguments.get('action')
        options = arguments.get('options') or {}
        if action not in ('export', 'import') or not options:
            return None
        extension = os.path.splitext(arguments.get('path', ''))[1].lower()
        formats = (NA_EXPORT_FORMATS if action == 'export' else NA_IMPORT_FORMATS).get(extension)
        if not formats:
            return None
        documented = self.na_api_index.Na__ApiIndex__Enumeration('exporter_options' if action == 'export' else 'importer_options') or {}
        valid = {'show_summary', 'selectionset_only'} if action == 'export' else {'show_summary'}
        for group in formats:
            valid |= set((documented.get(group) or {}).keys())
        if action == 'import':
            valid |= set((documented.get('All Importers') or {}).keys())
        unknown = sorted(key.lstrip(':') for key in options if key.lstrip(':') not in valid)
        if not unknown:
            return None
        return na_error_result('invalid_params',
                               '%s option(s) not documented for %s: %s. SketchUp silently ignores unknown options.' % (action.capitalize(), extension, ', '.join(unknown)),
                               'Valid options for %s: %s.' % (extension, ', '.join(sorted(valid))))

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Result Shaping
# -----------------------------------------------------------------------------

def na_version(text):
    """'1.0.19' -> (1, 0, 19); anything else -> None."""
    try:
        return tuple(int(part) for part in str(text).split('.'))
    except ValueError:
        return None


def na_result_from_response(response, extra=None):
    if response.get('ok'):
        payload = response.get('result')
        payload = dict(payload) if isinstance(payload, dict) else {'result': payload}
        if response.get('warnings'):
            payload['warnings'] = response['warnings']
        if response.get('undo'):
            payload['undo_step'] = response['undo']
        if extra:
            payload.update(extra)
        return na_success_result(na_with_notice(payload, response))
    error = response.get('error') or {}
    return na_error_result(error.get('code', 'error'), error.get('message', 'SketchUp reported an error.'), error.get('hint'), error.get('details'),
                           notice=na_notice(response))


def na_notice(response):
    """The Agent Outliner's waiting notice on a bridge response (1.0.28), or None."""
    notice = (response or {}).get('outliner')
    return notice if isinstance(notice, dict) and notice else None


def na_with_notice(payload, response):
    """The payload with the waiting notice first, so an agent reads it before the result and the text cap never cuts it."""
    notice = na_notice(response)
    if notice is None:
        return payload
    shaped = {'outliner': notice}
    shaped.update((key, value) for key, value in payload.items() if key != 'outliner')
    return shaped


def na_success_result(payload):
    images = na_extract_images(payload)
    text = json.dumps(payload, ensure_ascii=False, separators=(',', ':'), default=str)
    if len(text) > NA_MAX_TEXT_CHARS:
        text = text[:NA_MAX_TEXT_CHARS] + ' ...[truncated %d characters: narrow the request with limit/offset, response_format "concise", ' \
               'max_depth or a smaller parent_id]' % (len(text) - NA_MAX_TEXT_CHARS)
    return {'content': [{'type': 'text', 'text': text}] + images, 'isError': False}


def na_error_result(code, message, hint=None, details=None, notice=None):
    lines = ['Error (%s): %s' % (code, message)]
    if hint:
        lines.append('Fix: %s' % hint)
    if details:
        lines.append('Details: %s' % json.dumps(details, ensure_ascii=False, default=str)[:6000])
    if notice:
        lines.append('Outliner: %s' % json.dumps(notice, ensure_ascii=False, separators=(',', ':'), default=str))
    return {'content': [{'type': 'text', 'text': '\n'.join(lines)}], 'isError': True}


def na_extract_images(node):
    """Replace every {image_file, mime_type} in the result with an MCP image block (temp files are deleted)."""
    images = []

    def visit(item):
        if isinstance(item, dict):
            if 'image_file' in item and 'mime_type' in item:
                path = item['image_file']
                try:
                    size = os.path.getsize(path)
                    if size > NA_MAX_IMAGE_BYTES:
                        item['image_note'] = 'Image is %d bytes; too large to return inline. Saved at %s.' % (size, path)
                    else:
                        with open(path, 'rb') as handle:
                            images.append({'type': 'image', 'data': base64.b64encode(handle.read()).decode('ascii'), 'mimeType': item['mime_type']})
                        if not item.get('keep_file'):
                            os.remove(path)
                            item.pop('image_file', None)
                        else:
                            item['saved_to'] = item.pop('image_file')
                except OSError as error:
                    item['image_note'] = 'Could not read the capture: %s' % error
                item.pop('keep_file', None)
            for value in list(item.values()):
                visit(value)
        elif isinstance(item, list):
            for value in item:
                visit(value)

    visit(node)
    return images


def Na__ToolRunner__ServerFacts(registry, toolset):
    server = registry.Na__ToolRegistry__Server()
    return {
        'name': server.get('name', 'sketchup'),
        'version': server.get('version', '0.0.0'),
        'toolset': toolset,
        'tools': len(registry.Na__ToolRegistry__Names()),
        'python': platform.python_version(),
        'platform': sys.platform
    }

# endregion -------------------------------------------------------------------

# =============================================================================
# END OF FILE
# =============================================================================
