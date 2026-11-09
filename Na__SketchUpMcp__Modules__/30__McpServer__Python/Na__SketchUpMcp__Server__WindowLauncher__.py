# =============================================================================
# NA SKETCHUP MCP - PYTHON SERVER - WINDOW LAUNCHER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Server__WindowLauncher__.py
# PURPOSE    : sketchup_open_window - open a .skp in a NEW SketchUp window, so
#              every window already open keeps its model and its unsaved work;
#              sketchup_close_window - close one again, as File > Exit does
# CREATED    : 09-Nov-2026 (1.0.18)
#
# WHY:
# model_file open replaces the model in the window in use. Reading another
# project's model must never cost the user the one they have open, so this
# starts another SketchUp process with the file instead.
#
# HOW:
# 1. Only an existing .skp is accepted. copy_to copies it first (a folder keeps
#    the file name; never over an existing file unless overwrite) and opens the
#    COPY, so the original is never open and can never be saved over.
# 2. A live window that already has the file open is used as it is: SketchUp
#    would otherwise hold the same file in two windows.
# 3. SketchUp.exe: the version whose Plugins folder this server runs from
#    (...\SketchUp 2026\SketchUp\Plugins\...), else the image of a running window.
# 4. Started detached, stdin/stdout/stderr to NUL (stdout is the MCP channel).
#    Inside a Windows job the process breaks away when the job allows it, so
#    the window outlives this server.
# 5. The bridge starts with SketchUp (auto_start). Wait until THAT process's
#    bridge answers ping with this file as its open model.
# 6. select (default true): this server switches to it, as sketchup_status
#    select_pid does.
#
# CLI (tests and the skill's fallback when the server has not been restarted):
#   python Na__SketchUpMcp__Server__WindowLauncher__.py <file.skp> [--copy-to DIR] [--overwrite] [--timeout 240]
#   python Na__SketchUpMcp__Server__WindowLauncher__.py --close <pid>
#
# =============================================================================

import ctypes
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid

import Na__SketchUpMcp__Server__BridgeClient__ as Na__BridgeClientModule

NA_SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
NA_DEFAULT_WAIT_S = 240
NA_POLL_S = 1.0
NA_DETACHED_PROCESS = 0x00000008
NA_CREATE_NEW_PROCESS_GROUP = 0x00000200
NA_CREATE_BREAKAWAY_FROM_JOB = 0x01000000


class Na__LaunchError(Na__BridgeClientModule.Na__BridgeError):
    """A launch failure with a message and a hint naming the fix."""


# -----------------------------------------------------------------------------
# REGION | Files and Processes
# -----------------------------------------------------------------------------

def na_same_file(first, second):
    """True when two paths name one file (case, slashes and 8.3 short names ignored)."""
    if not first or not second:
        return False
    try:
        return os.path.normcase(os.path.realpath(first)) == os.path.normcase(os.path.realpath(second))
    except (OSError, ValueError):
        return False


def na_copy_target(source, copy_to):
    """copy_to is a .skp path, or a folder that keeps the source's file name."""
    copy_to = os.path.abspath(str(copy_to))
    if copy_to.lower().endswith('.skp'):
        return copy_to
    return os.path.join(copy_to, os.path.basename(source))


def na_process_image(pid):
    """Full path of a running process's executable (Windows), else None."""
    if sys.platform != 'win32':
        return None
    try:
        kernel32 = ctypes.windll.kernel32
        handle = kernel32.OpenProcess(0x1000, False, int(pid))          # PROCESS_QUERY_LIMITED_INFORMATION
    except (OSError, ValueError, TypeError):
        return None
    if not handle:
        return None
    try:
        size = ctypes.c_ulong(32768)
        buffer = ctypes.create_unicode_buffer(size.value)
        if kernel32.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
            return buffer.value
        return None
    finally:
        kernel32.CloseHandle(handle)


def na_in_job():
    """True when this server runs inside a Windows job (its children would share its fate)."""
    if sys.platform != 'win32':
        return False
    try:
        kernel32 = ctypes.windll.kernel32
        result = ctypes.c_int(0)
        kernel32.IsProcessInJob(kernel32.GetCurrentProcess(), None, ctypes.byref(result))
        return bool(result.value)
    except (OSError, AttributeError):
        return False


def Na__WindowLauncher__SketchUpExe(windows):
    """SketchUp.exe of the version this server belongs to, else that of a running window."""
    candidates = []
    match = re.search(r'SketchUp (20\d\d)', NA_SERVER_DIR)
    if match:
        for root in (os.environ.get('ProgramW6432'), os.environ.get('ProgramFiles'), r'C:\Program Files'):
            if root:
                candidates.append(os.path.join(root, 'SketchUp', 'SketchUp %s' % match.group(1), 'SketchUp', 'SketchUp.exe'))
    for item in windows:
        if item.get('live'):
            image = na_process_image(item.get('pid'))
            if image:
                candidates.append(image)
    for path in candidates:
        if path and os.path.isfile(path):
            return path
    return None


def na_start(exe, target):
    """Start SketchUp with the file, detached, never sharing the MCP channel. Returns (process, warning)."""
    flags = NA_DETACHED_PROCESS | NA_CREATE_NEW_PROCESS_GROUP
    common = {'stdin': subprocess.DEVNULL, 'stdout': subprocess.DEVNULL, 'stderr': subprocess.DEVNULL,
              'close_fds': True, 'cwd': os.path.dirname(target)}
    if na_in_job():
        try:
            return subprocess.Popen([exe, target], creationflags=flags | NA_CREATE_BREAKAWAY_FROM_JOB, **common), None
        except OSError:
            warning = ('This server runs inside a Windows job that does not allow breakaway, so the new window may close '
                       'when the server stops. Save any work in it before ending the session.')
            return subprocess.Popen([exe, target], creationflags=flags, **common), warning
    return subprocess.Popen([exe, target], creationflags=flags, **common), None

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Open
# -----------------------------------------------------------------------------

def Na__WindowLauncher__Open(bridge, arguments, poll_s=NA_POLL_S):
    """Open arguments['path'] (or a copy of it) in its own SketchUp window. Returns the result payload."""
    if sys.platform != 'win32':
        raise Na__LaunchError('unsupported', 'sketchup_open_window starts SketchUp on Windows only.',
                              'Open the file in SketchUp by hand, then call sketchup_status with select_pid.')

    source = os.path.abspath(str(arguments.get('path') or ''))
    if not source.lower().endswith('.skp'):
        raise Na__LaunchError('invalid_params', 'path must be a .skp file: %s' % source, 'Pass the absolute path of a SketchUp model.')
    if not os.path.isfile(source):
        raise Na__LaunchError('not_found', 'No file at %s.' % source, 'Check the path (find the file first; never guess it).')

    target = na_copy_target(source, arguments['copy_to']) if arguments.get('copy_to') else source
    copying = target != source
    if copying and na_same_file(target, source):
        raise Na__LaunchError('invalid_params', 'copy_to points at the file itself.', 'Give another folder or file name for the copy.')

    windows = bridge.Na__BridgeClient__Windows()
    live = [item for item in windows if item.get('live')]
    holding = [item for item in live if na_same_file(item.get('model_path'), target)]
    select = arguments.get('select', True) is not False
    warnings = []

    if holding:
        item = holding[0]
        if copying:
            raise Na__LaunchError('in_use', 'The copy %s is open in SketchUp window pid %s.' % (target, item.get('pid')),
                                  'Use that window (sketchup_status select_pid), or pass another copy_to.')
        if select:
            bridge.Na__BridgeClient__Select(item.get('pid'))
        return {'opened': target, 'already_open': True, 'pid': item.get('pid'), 'port': item.get('port'),
                'model_title': item.get('model_title'), 'selected': select,
                'summary': '%s was already open in window pid %s%s.' % (os.path.basename(target), item.get('pid'),
                                                                      '; this server now uses it' if select else '')}

    if copying:
        if os.path.exists(target) and not arguments.get('overwrite'):
            raise Na__LaunchError('already_exists', 'A file is already at %s.' % target,
                                  'Pass overwrite:true to replace that copy, or another copy_to.')
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(source, target)

    exe = Na__WindowLauncher__SketchUpExe(windows)
    if not exe:
        raise Na__LaunchError('not_found', 'SketchUp.exe was not found for this server\'s SketchUp version.',
                              'Open the file in SketchUp by hand, then call sketchup_status with select_pid.')

    process, job_warning = na_start(exe, target)
    if job_warning:
        warnings.append(job_warning)
    pid = process.pid
    started = time.time()
    wait_s = max(10, min(int(arguments.get('timeout_s') or NA_DEFAULT_WAIT_S), 900))
    found = None
    while time.time() - started < wait_s:
        time.sleep(poll_s)
        if process.poll() is not None:
            raise Na__LaunchError('operation_failed', 'SketchUp (pid %s) closed before its bridge started.' % pid,
                                  'Open %s by hand to see why (a dialog, a damaged file or a licence prompt).' % target)
        for item in bridge.Na__BridgeClient__Instances(clean_stale=False):
            if int(item.get('pid', -1)) != pid or not item.get('live'):
                continue
            bridge.na_read_open_model(item)
            if na_same_file(item.get('model_path'), target):
                found = item
            break
        if found:
            break

    seconds = round(time.time() - started, 1)
    result = {'opened': target, 'pid': pid, 'seconds': seconds, 'sketchup_exe': exe}
    if copying:
        result['copied_from'] = source
    if not found:
        result.update({'ready': False, 'selected': False,
                       'summary': 'SketchUp pid %s is still opening %s after %s s.' % (pid, os.path.basename(target), seconds),
                       'next': 'Call sketchup_status; when pid %s lists this model, select it with select_pid.' % pid})
        if warnings:
            result['warnings'] = warnings
        return result

    if select:
        bridge.Na__BridgeClient__Select(pid)
    result.update({'ready': True, 'port': found.get('port'), 'model_title': found.get('model_title'), 'selected': select,
                   'summary': 'Opened %s%s in a new SketchUp window (pid %s) in %s s%s.' % (
                       os.path.basename(target), ' (a copy)' if copying else '', pid, seconds,
                       '; this server now uses it' if select else '')})
    if warnings:
        result['warnings'] = warnings
    return result

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Close (sketchup_close_window)
# -----------------------------------------------------------------------------
#
# The way File > Exit closes it: that window's own bridge runs Sketchup.quit on a
# timer, so the reply comes back before SketchUp goes. Unsaved changes are refused
# unless discard_unsaved_changes, which first runs Model#close(true) (on Windows a
# File > New that ignores the changes) so Exit has nothing to ask about.
# =============================================================================

NA_QUIT_CODE = 'UI.start_timer(0.3, false) { Sketchup.quit }\ntrue'
NA_DISCARD_AND_QUIT_CODE = 'UI.start_timer(0.3, false) { Sketchup.active_model.close(true); Sketchup.quit }\ntrue'


def na_window_request(bridge, item, command, params, timeout_s):
    payload = {'id': uuid.uuid4().hex, 'token': item.get('token', ''), 'command': command, 'params': params}
    return bridge.na_round_trip(item, payload, timeout_s)


def Na__WindowLauncher__Close(bridge, arguments, poll_s=0.5):
    """Close the SketchUp window with arguments['pid']. Returns the result payload."""
    pid = int(arguments.get('pid'))
    discard = arguments.get('discard_unsaved_changes') is True
    live = [item for item in bridge.Na__BridgeClient__Instances() if item.get('live')]
    matches = [item for item in live if int(item.get('pid', -1)) == pid]
    if not matches:
        raise Na__LaunchError('not_found', 'No running SketchUp window with pid %s.' % pid, 'Call sketchup_status to list the windows.')
    item = matches[0]

    status = na_window_request(bridge, item, 'sketchup_status', {}, 15)
    model = (status.get('result') or {}).get('model') or {}
    title = model.get('title') or item.get('model_title') or 'untitled'
    modified = model.get('modified')
    if modified is None:
        raise Na__LaunchError('operation_failed', 'Window pid %s did not say whether %s has unsaved changes, so it was left open.' % (pid, title),
                              'Check it with sketchup_status (select_pid %s) and close it by hand if need be.' % pid)
    if modified and not discard:
        raise Na__LaunchError('unsaved_changes', '%s (pid %s) has unsaved changes; it was left open.' % (title, pid),
                              'Save it (model_file save), or pass discard_unsaved_changes:true only if the user agreed to lose them.')

    reply = na_window_request(bridge, item, 'ruby_eval', {'code': NA_DISCARD_AND_QUIT_CODE if modified else NA_QUIT_CODE,
                                                          'transaction': False, 'operation_name': 'Close window'}, 15)
    if not reply.get('ok'):
        error = reply.get('error') or {}
        raise Na__LaunchError('operation_failed', 'Window pid %s refused to close: %s' % (pid, error.get('message', 'no reason given')),
                              'Close it by hand (File > Exit). Read-only mode or Ruby eval switched off in its bridge stops this tool.')

    started = time.time()
    wait_s = max(5, min(int(arguments.get('timeout_s') or 60), 300))
    while Na__BridgeClientModule.na_pid_running(pid) and time.time() - started < wait_s:
        time.sleep(poll_s)
    closed = not Na__BridgeClientModule.na_pid_running(pid)
    result = {'pid': pid, 'model_title': title, 'closed': closed, 'discarded_changes': bool(modified),
              'seconds': round(time.time() - started, 1)}
    was_selected = bridge.na_selected_pid == pid
    if closed:
        result['summary'] = 'Closed %s (pid %s)%s.' % (title, pid, ', discarding its unsaved changes' if modified else '')
        if was_selected:
            result['next'] = 'This server was using that window: choose another with sketchup_status select_pid.'
    else:
        result['summary'] = 'Asked %s (pid %s) to close; it is still running after %s s (a dialog may be open).' % (title, pid, result['seconds'])
    return result

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | CLI
# -----------------------------------------------------------------------------

def na_main(argv):
    import argparse
    parser = argparse.ArgumentParser(description='Open a .skp in a new SketchUp window, or close one (Na SketchUp MCP).')
    parser.add_argument('path', nargs='?')
    parser.add_argument('--copy-to')
    parser.add_argument('--overwrite', action='store_true')
    parser.add_argument('--timeout', type=int, default=NA_DEFAULT_WAIT_S)
    parser.add_argument('--close', type=int, metavar='PID', help='close this window instead (refused when it has unsaved changes)')
    options = parser.parse_args(argv)
    client = Na__BridgeClientModule.Na__BridgeClient()
    try:
        if options.close:
            payload = Na__WindowLauncher__Close(client, {'pid': options.close, 'timeout_s': min(options.timeout, 300)})
        else:
            arguments = {'path': options.path, 'overwrite': options.overwrite, 'timeout_s': options.timeout, 'select': False}
            if options.copy_to:
                arguments['copy_to'] = options.copy_to
            payload = Na__WindowLauncher__Open(client, arguments)
    except Na__BridgeClientModule.Na__BridgeError as error:
        payload = {'error': error.na_code, 'message': error.na_message, 'hint': error.na_hint}
    sys.stderr.write(json.dumps(payload, indent=1) + '\n')
    return 0 if payload.get('ready') or payload.get('already_open') or payload.get('closed') else 1


if __name__ == '__main__':
    sys.exit(na_main(sys.argv[1:]))

# endregion -------------------------------------------------------------------

# =============================================================================
# END OF FILE
# =============================================================================
