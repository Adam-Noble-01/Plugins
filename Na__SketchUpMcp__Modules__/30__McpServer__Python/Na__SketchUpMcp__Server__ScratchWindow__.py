# =============================================================================
# NA SKETCHUP MCP - PYTHON SERVER - SCRATCH WINDOWS
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Server__ScratchWindow__.py
# PURPOSE    : sketchup_scratch_open - a blank SketchUp window that is nobody's
#              work, from a fresh copy of SketchUp's Simple template with its
#              scale figure erased; sketchup_scratch_close - close one again
#              without a prompt, refusing any window this tool did not open
# CREATED    : 25-Nov-2026 (1.0.42)
#
# WHY:
# Converters (ValeVision 3D's vv3d_furnishings_import_skp) and trials need an
# EMPTY window. On 25-Nov-2026 a WORKER made one by hand five times, about two
# minutes each with one hung close: copy the template, open the copy with the
# window launcher, erase the figure, then close it with Model#close(true) and
# Sketchup.quit from its own bridge, because sketchup_close_window refuses a
# window with unsaved changes (the 3D skill's lesson L1570).
#
# HOW (open):
# 1. Stale ledger entries (their SketchUp has gone) are cleared with their copies.
# 2. Temp01a - Simple.skp is found beside the SketchUp.exe this server belongs to
#    (resources\en-US\Templates, else any language folder) and copied to
#    91__UserConfig__LocalOnly\ScratchWindows\Na__SketchUpMcp__ScratchWindow__<stamp>.skp.
#    The template itself is never opened.
# 3. The copy opens through Na__WindowLauncher__Open (select false), and a
#    ledger file Na__SketchUpMcp__Scratch__<pid>.json records the pid, the
#    process's creation time and the copy's path at once.
# 4. That window's own bridge erases every root entity (the figure) and purges
#    the definitions and materials it leaves, in ONE undo step. The Ruby checks
#    the open model is the copy first, so it can never run in another model.
# 5. select (default true) switches this server to the window, so a later call
#    can never land in Adam's model by mistake.
#
# HOW (close):
# 1. Refused unless the ledger has the pid, the process's creation time is the
#    one recorded (a reused pid is someone else's), and the window's open model
#    is still the scratch copy (a model opened into it is someone's work).
# 2. Its bridge runs Model#close(true) then Sketchup.quit on a timer, guarded in
#    Ruby by the same path check. Never saved.
# 3. Once the process has gone, the copy and its ledger file are deleted, and
#    a server that was using the window goes back to the one it used before.
# 4. force: only when the window's bridge does not answer. The process is ended
#    (TerminateProcess) when the ledger proves it is the scratch window.
#
# CLI (the skill's fallback when the MCP client has not been restarted):
#   python Na__SketchUpMcp__Server__ScratchWindow__.py open [--timeout 240]
#   python Na__SketchUpMcp__Server__ScratchWindow__.py close <pid> [--force]
#   python Na__SketchUpMcp__Server__ScratchWindow__.py list
#
# =============================================================================

import ctypes
import glob
import json
import os
import shutil
import sys
import time
import uuid

import Na__SketchUpMcp__Server__BridgeClient__ as Na__BridgeClientModule
import Na__SketchUpMcp__Server__WindowLauncher__ as Na__WindowLauncher

NA_SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
NA_MODULES_ROOT = os.path.abspath(os.path.join(NA_SERVER_DIR, '..'))
NA_DEFAULT_SCRATCH_DIR = os.path.join(NA_MODULES_ROOT, '91__UserConfig__LocalOnly', 'ScratchWindows')
NA_TEMPLATE_NAME = 'Temp01a - Simple.skp'
NA_COPY_PREFIX = 'Na__SketchUpMcp__ScratchWindow__'
NA_LEDGER_PREFIX = 'Na__SketchUpMcp__Scratch__'
NA_DEFAULT_WAIT_S = 240
NA_PROCESS_TERMINATE = 0x0001
NA_PROCESS_QUERY_LIMITED_INFORMATION = 0x1000

Na__ScratchError = Na__WindowLauncher.Na__LaunchError


# -----------------------------------------------------------------------------
# REGION | Paths, Ledger and Processes
# -----------------------------------------------------------------------------

def Na__ScratchWindow__Dir():
    """The scratch folder (NA_SKETCHUP_MCP_SCRATCH_DIR overrides it, for tests)."""
    return os.environ.get('NA_SKETCHUP_MCP_SCRATCH_DIR') or NA_DEFAULT_SCRATCH_DIR


def na_ledger_path(pid):
    return os.path.join(Na__ScratchWindow__Dir(), '%s%d.json' % (NA_LEDGER_PREFIX, int(pid)))


def Na__ScratchWindow__Ledger(pid):
    """The ledger record for pid, or None when this tool did not open it."""
    try:
        with open(na_ledger_path(pid), 'r', encoding='utf-8') as handle:
            record = json.load(handle)
    except (OSError, ValueError, TypeError):
        return None
    if not isinstance(record, dict) or int(record.get('pid', -1)) != int(pid):
        return None
    return record


def Na__ScratchWindow__Ledgers():
    """Every ledger record in the scratch folder."""
    records = []
    for path in glob.glob(os.path.join(Na__ScratchWindow__Dir(), NA_LEDGER_PREFIX + '*.json')):
        try:
            with open(path, 'r', encoding='utf-8') as handle:
                record = json.load(handle)
        except (OSError, ValueError):
            continue
        if isinstance(record, dict) and record.get('pid'):
            records.append(record)
    return records


def na_write_ledger(record):
    path = na_ledger_path(record['pid'])
    temp = path + '.tmp'
    with open(temp, 'w', encoding='utf-8') as handle:
        json.dump(record, handle, indent=1)
    os.replace(temp, path)


def na_process_created(pid):
    """The process's creation time (a Windows FILETIME integer), or None when it cannot be read."""
    if sys.platform != 'win32':
        return None
    kernel32 = ctypes.windll.kernel32
    handle = kernel32.OpenProcess(NA_PROCESS_QUERY_LIMITED_INFORMATION, False, int(pid))
    if not handle:
        return None
    try:
        created, exited, kernel, user = (ctypes.c_ulonglong(), ctypes.c_ulonglong(), ctypes.c_ulonglong(), ctypes.c_ulonglong())
        if not kernel32.GetProcessTimes(handle, ctypes.byref(created), ctypes.byref(exited), ctypes.byref(kernel), ctypes.byref(user)):
            return None
        return int(created.value)
    finally:
        kernel32.CloseHandle(handle)


def na_same_process(record):
    """True when the pid in the record is still the very process this tool started."""
    pid = int(record['pid'])
    if not Na__BridgeClientModule.na_pid_running(pid):
        return False
    recorded = record.get('process_created')
    if recorded is None:
        return True                                     # not readable when it was opened: the model path check still guards it
    return na_process_created(pid) == int(recorded)


def na_terminate(pid):
    kernel32 = ctypes.windll.kernel32
    handle = kernel32.OpenProcess(NA_PROCESS_TERMINATE, False, int(pid))
    if not handle:
        return False
    try:
        return bool(kernel32.TerminateProcess(handle, 1))
    finally:
        kernel32.CloseHandle(handle)


def na_remove_files(record):
    """Delete the scratch copy (and anything SketchUp wrote beside it under its name) and the ledger file."""
    removed = []
    folder = Na__ScratchWindow__Dir()
    copy = record.get('model_path') or ''
    stem = os.path.splitext(os.path.basename(copy))[0]
    if stem.startswith(NA_COPY_PREFIX) and Na__WindowLauncher.na_same_file(os.path.dirname(copy), folder):
        for path in glob.glob(os.path.join(folder, '*' + stem + '*')):
            try:
                os.remove(path)
                removed.append(os.path.basename(path))
            except OSError:
                pass
    try:
        os.remove(na_ledger_path(record['pid']))
    except OSError:
        pass
    return removed


def Na__ScratchWindow__ClearStale():
    """Ledger entries whose SketchUp has gone (or whose pid is now another process): delete them and their copies."""
    cleared = []
    for record in Na__ScratchWindow__Ledgers():
        if not na_same_process(record):
            na_remove_files(record)
            cleared.append(int(record['pid']))
    return cleared


def Na__ScratchWindow__Template(exe):
    """Temp01a - Simple.skp beside SketchUp.exe: en-US first, else any language folder."""
    resources = os.path.join(os.path.dirname(exe), 'resources')
    preferred = os.path.join(resources, 'en-US', 'Templates', NA_TEMPLATE_NAME)
    if os.path.isfile(preferred):
        return preferred
    for path in sorted(glob.glob(os.path.join(resources, '*', 'Templates', NA_TEMPLATE_NAME))):
        return path
    return None


def na_ruby_string(text):
    """A single-quoted Ruby literal (no interpolation)."""
    return "'" + str(text).replace('\\', '\\\\').replace("'", "\\'") + "'"


def na_path_guard(path):
    """Ruby that is true only while the window's open model is this file."""
    return ("na_scratch_path = %s\n"
            "na_open_path = Sketchup.active_model.path.to_s\n"
            "na_is_scratch = !na_open_path.empty? && File.expand_path(na_open_path).downcase == File.expand_path(na_scratch_path).downcase\n"
            % na_ruby_string(path))


def na_erase_code(path):
    return (na_path_guard(path) +
            "raise 'This window is not the scratch copy; nothing was erased.' unless na_is_scratch\n"
            "model = Sketchup.active_model\n"
            "erased = model.entities.to_a\n"
            "names = erased.map { |e| e.respond_to?(:definition) ? e.definition.name : e.typename }\n"
            "model.entities.erase_entities(erased) unless erased.empty?\n"
            "model.definitions.purge_unused\n"
            "model.materials.purge_unused\n"
            "{ 'erased' => names, 'root_entities' => model.entities.size, 'definitions' => model.definitions.size, "
            "'materials' => model.materials.size, 'tags' => model.layers.size }")


def na_quit_code(path):
    return (na_path_guard(path) +
            "UI.start_timer(0.3, false) { Sketchup.active_model.close(true); Sketchup.quit } if na_is_scratch\n"
            "na_is_scratch")


def na_request(bridge, item, command, params, timeout_s):
    reply = Na__WindowLauncher.na_window_request(bridge, item, command, params, timeout_s)
    if not reply.get('ok'):
        error = reply.get('error') or {}
        raise Na__ScratchError(error.get('code') or 'operation_failed', error.get('message') or 'the bridge gave no reason',
                               error.get('hint') or 'Check the window with sketchup_status.')
    return reply.get('result') or {}


def na_live_item(bridge, pid):
    for item in bridge.Na__BridgeClient__Instances(clean_stale=False):
        if int(item.get('pid', -1)) == int(pid) and item.get('live'):
            return item
    return None

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Open (sketchup_scratch_open)
# -----------------------------------------------------------------------------

def Na__ScratchWindow__Open(bridge, arguments, poll_s=Na__WindowLauncher.NA_POLL_S):
    """Open a blank scratch window. Returns the result payload."""
    if sys.platform != 'win32':
        raise Na__ScratchError('unsupported', 'sketchup_scratch_open starts SketchUp on Windows only.',
                               'Open a new model in SketchUp by hand, then call sketchup_status with select_pid.')
    started = time.time()
    cleared = Na__ScratchWindow__ClearStale()
    windows = bridge.Na__BridgeClient__Windows()
    exe = Na__WindowLauncher.Na__WindowLauncher__SketchUpExe(windows)
    if not exe:
        raise Na__ScratchError('not_found', 'SketchUp.exe was not found for this server\'s SketchUp version.',
                               'Install or repair SketchUp, or open a new model by hand and select it with sketchup_status select_pid.')
    template = Na__ScratchWindow__Template(exe)
    if not template:
        raise Na__ScratchError('not_found', 'SketchUp\'s %s was not found under %s.' % (NA_TEMPLATE_NAME, os.path.join(os.path.dirname(exe), 'resources')),
                               'Repair the SketchUp installation (its templates are missing).')

    folder = Na__ScratchWindow__Dir()
    os.makedirs(folder, exist_ok=True)
    copy = os.path.join(folder, '%s%s__%s.skp' % (NA_COPY_PREFIX, time.strftime('%Y%m%d-%H%M%S'), uuid.uuid4().hex[:6]))
    shutil.copy2(template, copy)

    selected_before = bridge.na_selected_pid
    launch = Na__WindowLauncher.Na__WindowLauncher__Open(
        bridge, {'path': copy, 'select': False, 'timeout_s': arguments.get('timeout_s') or NA_DEFAULT_WAIT_S}, poll_s)
    pid = int(launch['pid'])
    record = {'pid': pid, 'process_created': na_process_created(pid), 'model_path': copy, 'template': template,
              'opened_at': time.strftime('%Y-%m-%dT%H:%M:%S'), 'selected_before': selected_before, 'prepared': False}
    na_write_ledger(record)

    result = {'pid': pid, 'model_path': copy, 'template': template, 'ready': False, 'selected': False,
              'seconds_to_open': launch.get('seconds')}
    if cleared:
        result['cleared_stale'] = cleared
    if launch.get('warnings'):
        result['warnings'] = launch['warnings']
    if not launch.get('ready'):
        result.update({'seconds': round(time.time() - started, 1),
                       'summary': 'SketchUp pid %s is still opening the scratch copy after %s s; its figure is not erased yet.' % (pid, launch.get('seconds')),
                       'next': 'Close it with sketchup_scratch_close pid %s (force:true if its bridge never answers), then open another.' % pid})
        return result

    item = na_live_item(bridge, pid)
    if item is None:
        raise Na__ScratchError('operation_failed', 'Scratch window pid %s stopped answering after it opened.' % pid,
                               'Close it with sketchup_scratch_close pid %s force:true.' % pid)
    erase_started = time.time()
    try:
        erased = na_request(bridge, item, 'ruby_eval', {'code': na_erase_code(copy), 'transaction': True,
                                                        'operation_name': 'Scratch Window: Erase Scale Figure'}, 30)
    except (Na__BridgeClientModule.Na__BridgeError, OSError) as error:
        raise Na__ScratchError(getattr(error, 'na_code', 'operation_failed'), 'Scratch window pid %s opened, but its scale figure was not erased: %s' % (
                                   pid, getattr(error, 'na_message', None) or error),
                               'Close it with sketchup_scratch_close pid %s (Ruby eval must be on in its bridge; force:true ends it otherwise).' % pid)
    counts = erased.get('value') or {}
    record['prepared'] = True
    na_write_ledger(record)

    select = arguments.get('select', True) is not False
    if select:
        bridge.Na__BridgeClient__Select(pid)
    result.update({'ready': True, 'port': item.get('port'), 'model_title': item.get('model_title'), 'selected': select,
                   'erased': counts.get('erased', []), 'left': {key: counts.get(key) for key in ('root_entities', 'definitions', 'materials', 'tags')},
                   'seconds_to_erase': round(time.time() - erase_started, 2), 'seconds': round(time.time() - started, 1),
                   'summary': 'Opened a blank scratch window (pid %s) in %s s: %s erased, %s root entities left%s.' % (
                       pid, round(time.time() - started, 1), ', '.join(counts.get('erased') or []) or 'nothing',
                       counts.get('root_entities'), '; this server now uses it' if select else ''),
                   'next': 'Work in it (pass pid %s to scripts), never save it, and close it with sketchup_scratch_close pid %s.' % (pid, pid)})
    return result

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Close (sketchup_scratch_close)
# -----------------------------------------------------------------------------

def Na__ScratchWindow__Close(bridge, arguments, poll_s=0.5):
    """Close a scratch window this tool opened, discarding its changes. Returns the result payload."""
    pid = int(arguments.get('pid'))
    force = arguments.get('force') is True
    record = Na__ScratchWindow__Ledger(pid)
    if record is None:
        raise Na__ScratchError('not_scratch', 'Window pid %s was not opened by sketchup_scratch_open, so it was left alone.' % pid,
                               'Close it with sketchup_close_window (which refuses unsaved changes), or leave it: it may be Adam\'s.')
    copy = record.get('model_path')

    if not Na__BridgeClientModule.na_pid_running(pid):
        removed = na_remove_files(record)
        return {'pid': pid, 'closed': True, 'already_closed': True, 'removed': removed,
                'summary': 'Scratch window pid %s had already closed; its copy and record were cleared.' % pid}
    if not na_same_process(record):
        na_remove_files(record)
        raise Na__ScratchError('not_scratch', 'pid %s now belongs to another process (the scratch window closed and Windows reused its pid); it was left alone.' % pid,
                               'Its scratch record was cleared. Nothing else to do.')

    started = time.time()
    method = None
    item = na_live_item(bridge, pid)
    if item is not None:
        try:
            pong = na_request(bridge, item, 'ping', {}, 10)
            if not Na__WindowLauncher.na_same_file(pong.get('model_path'), copy):
                raise Na__ScratchError('not_scratch', 'Scratch window pid %s now has another model open (%s), so it was left open.' % (
                    pid, pong.get('model_path') or pong.get('model_title') or 'an untitled model'),
                    'That model may be someone\'s work: tell the user, and close it by hand only on their word.')
            closing = na_request(bridge, item, 'ruby_eval', {'code': na_quit_code(copy), 'transaction': False,
                                                             'operation_name': 'Close scratch window'}, 15)
            if closing.get('value') is not True:
                raise Na__ScratchError('not_scratch', 'Scratch window pid %s said its open model is not the scratch copy; it was left open.' % pid,
                                       'Check it with sketchup_status select_pid %s.' % pid)
            method = 'bridge'
        except (Na__BridgeClientModule.Na__BridgeError, OSError) as error:
            unreachable = isinstance(error, (OSError, Na__BridgeClientModule.Na__BridgeTimeout,
                                             Na__BridgeClientModule.Na__BridgeUnavailable, Na__BridgeClientModule.Na__BridgeLost))
            if not unreachable:
                raise                                       # a refusal (not_scratch, eval_disabled, read_only): never forced
            if not force:
                raise Na__ScratchError('operation_failed', 'Scratch window pid %s did not answer (%s), so it is still open.' % (
                    pid, getattr(error, 'na_message', None) or error),
                    'Try again in a moment, or pass force:true to end the scratch process (nothing in it is kept).')
    elif not force:
        raise Na__ScratchError('operation_failed', 'Scratch window pid %s is running but its bridge is not listening.' % pid,
                               'Pass force:true to end the scratch process (nothing in it is kept).')

    if method is None:
        if not na_terminate(pid):
            raise Na__ScratchError('operation_failed', 'Windows refused to end scratch window pid %s.' % pid, 'Close it by hand (File > Exit, Don\'t Save).')
        method = 'force'

    wait_s = max(5, min(int(arguments.get('timeout_s') or 60), 300))
    while Na__BridgeClientModule.na_pid_running(pid) and time.time() - started < wait_s:
        time.sleep(poll_s)
    closed = not Na__BridgeClientModule.na_pid_running(pid)
    result = {'pid': pid, 'closed': closed, 'method': method, 'seconds': round(time.time() - started, 1)}
    if not closed:
        result['summary'] = 'Asked scratch window pid %s to close; it is still running after %s s.' % (pid, result['seconds'])
        result['next'] = 'Call sketchup_scratch_close pid %s again, with force:true if it stays.' % pid
        return result

    result['removed'] = na_remove_files(record)
    result['summary'] = 'Closed scratch window pid %s in %s s without saving%s.' % (pid, result['seconds'], ' (process ended)' if method == 'force' else '')
    if bridge.na_selected_pid == pid:
        before = record.get('selected_before')
        back = None
        if before and int(before) != pid:
            try:
                bridge.Na__BridgeClient__Select(before)
                back = int(before)
            except Na__BridgeClientModule.Na__BridgeError:
                back = None
        if back:
            result['selected_pid'] = back
            result['summary'] += '; this server is back on pid %s' % back
        else:
            result['next'] = 'This server was using that window: choose another with sketchup_status select_pid.'
    return result


def Na__ScratchWindow__IsScratch(pid):
    """True when the ledger holds pid (sketchup_status and sketchup_close_window mark it)."""
    try:
        return Na__ScratchWindow__Ledger(pid) is not None
    except (TypeError, ValueError):
        return False

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | CLI
# -----------------------------------------------------------------------------

def na_main(argv):
    import argparse
    parser = argparse.ArgumentParser(description='Open or close a blank scratch SketchUp window (Na SketchUp MCP).')
    parser.add_argument('action', choices=['open', 'close', 'list'])
    parser.add_argument('pid', nargs='?', type=int)
    parser.add_argument('--timeout', type=int, default=NA_DEFAULT_WAIT_S)
    parser.add_argument('--force', action='store_true', help='close: end the scratch process when its bridge does not answer')
    options = parser.parse_args(argv)
    client = Na__BridgeClientModule.Na__BridgeClient()
    try:
        if options.action == 'open':
            payload = Na__ScratchWindow__Open(client, {'timeout_s': options.timeout, 'select': False})
        elif options.action == 'close':
            if not options.pid:
                parser.error('close needs the pid')
            payload = Na__ScratchWindow__Close(client, {'pid': options.pid, 'force': options.force, 'timeout_s': min(options.timeout, 300)})
        else:
            payload = {'scratch_windows': Na__ScratchWindow__Ledgers(), 'ok': True}
    except Na__BridgeClientModule.Na__BridgeError as error:
        payload = {'error': error.na_code, 'message': error.na_message, 'hint': error.na_hint}
    sys.stderr.write(json.dumps(payload, indent=1) + '\n')
    return 0 if payload.get('ready') or payload.get('closed') or payload.get('ok') else 1


if __name__ == '__main__':
    sys.exit(na_main(sys.argv[1:]))

# endregion -------------------------------------------------------------------

# =============================================================================
# END OF FILE
# =============================================================================
