# =============================================================================
# NA PAINTERLYNPR ASSETS - NPR VIEWPORT - REMOTE FETCH
# =============================================================================
#
# FILE       : Na__PainterlyAssets__NprViewport__RemoteFetch__.py
# PURPOSE    : Bring PainterlyNPR's render engine down from its GitHub repo into
#              the plugin's remote cache (93__RemoteCache__CoreEngine): only the
#              files the engine reads when it runs, at the branch's latest
#              commit, in a folder of their own named by that commit.
# CREATED    : 01-Nov-2026
#
# DESCRIPTION:
# - THE ENGINE IS NEVER COPIED INTO THE PLUGIN (Adam, 01-Nov-2026: "Do not,
#   under any circumstance, copy the core render engine code into the SketchUp
#   plugin ... This SketchUp plugin is effectively just a wrapper that calls
#   all of that code from that repo"). This script only caches the repo's own
#   files; the plugin's local server serves them to the NPR windows.
# - git does the download, with the credentials this PC already holds for
#   GitHub (Git Credential Manager), so no token ever passes through the
#   plugin. A shallow, blob-less, sparse clone fetches only the commit's files
#   the patterns name (the AURA pin's selection plus the app page and its
#   icons), a few megabytes.
# - A failed fetch never touches the cache in use: the clone lands in a
#   staging folder, is checked (the app page, Init, the main config), and only
#   then renamed to PainterlyNPR__<commit> and named in the state file. The
#   previous commit's folder is kept until the next fetch, so an open window
#   never loses its files.
# - Run by the plugin as pythonw.exe -I -X utf8 (no console window); every git
#   call runs with CREATE_NO_WINDOW and no terminal prompt. The outcome goes
#   to --result as JSON, and the plugin reads that, never this script's output.
#
# USAGE:
#   pythonw -I -X utf8 Na__PainterlyAssets__NprViewport__RemoteFetch__.py
#       --url https://github.com/Adam-Noble-01/Na__PainterlyNPR.git --branch main
#       --cache-root <93__RemoteCache__CoreEngine> --patterns <json file>
#       --result <json file> [--git <git.exe>] [--force]
#
# =============================================================================

import argparse
import json
import os
import shutil
import stat
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

STATE_FILE      = 'Na__PainterlyAssets__RemoteCache__State__.json'           # <-- What the plugin and the server read: the folder in use
FOLDER_PREFIX   = 'PainterlyNPR__'                                           # <-- PainterlyNPR__<commit 7>
STAGING_PREFIX  = 'Staging__'

GIT_TIMEOUT_S   = 300
NO_WINDOW       = 0x08000000 if os.name == 'nt' else 0                       # <-- CREATE_NO_WINDOW: git is a console program
REQUIRED_FILES  = [                                                          # <-- A cache without these is not an engine
    'PainterlyNPR__App__.html',
    '02__Src__AppModules/01__AppCore/PainterlyNPR__AppCore__Init__.mjs',
    '02__Src__AppModules/02__AppData/PainterlyNPR__AppConfig__Main__.json',
]
MAIN_CONFIG     = '02__Src__AppModules/02__AppData/PainterlyNPR__AppConfig__Main__.json'
GIT_CANDIDATES  = [
    r'C:\Program Files\Git\cmd\git.exe',
    r'C:\Program Files\Git\bin\git.exe',
    r'C:\Program Files (x86)\Git\cmd\git.exe',
]

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

def iso_now():
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def long_path(path):
    """An absolute path Windows opens past 260 characters (the cache sits deep in SketchUp's Plugins folder)."""
    full = os.path.abspath(str(path))
    if os.name == 'nt' and not full.startswith('\\\\?\\'):
        full = '\\\\?\\' + full
    return Path(full)


def find_git(chosen):
    """The git to run: the one named, else on PATH, else Git for Windows' usual places."""
    for candidate in [chosen, shutil.which('git')] + GIT_CANDIDATES:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    return None


def git_env():
    env = dict(os.environ)
    env['GIT_TERMINAL_PROMPT'] = '0'                                         # <-- There is no terminal: never wait on one
    env.pop('GIT_DIR', None)
    env.pop('GIT_WORK_TREE', None)
    return env


def run_git(git, args, cwd=None, log=None):
    """One git command, no window, no prompt; raises with git's own words when it fails."""
    command = [git, '-c', 'core.longpaths=true', '-c', 'advice.detachedHead=false'] + args
    if log is not None:
        log.append('$ git ' + ' '.join(args))
    done = subprocess.run(command, cwd=cwd, env=git_env(), stdin=subprocess.DEVNULL, capture_output=True,
                          text=True, encoding='utf-8', errors='replace', timeout=GIT_TIMEOUT_S, creationflags=NO_WINDOW)
    if log is not None:
        for line in (done.stdout + done.stderr).splitlines():
            if line.strip():
                log.append('  ' + line.rstrip())
    if done.returncode != 0:
        detail = (done.stderr or done.stdout).strip().splitlines()
        raise RuntimeError(f"git {args[0]} failed ({done.returncode}): {detail[-1] if detail else 'no output'}")
    return done.stdout.strip()


def remove_tree(path):
    """rmtree that also takes git's read-only pack files."""
    def unlock(func, target, _info):
        os.chmod(target, stat.S_IWRITE)
        func(target)
    if Path(path).exists():
        shutil.rmtree(path, onerror=unlock)


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    part = path.with_name(path.name + '.part')
    part.write_text(json.dumps(data, indent=4, ensure_ascii=False) + '\n', encoding='utf-8')
    os.replace(part, path)


def read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding='utf-8-sig'))
    except (OSError, ValueError):
        return None

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | The Fetch
# -----------------------------------------------------------------------------

def fetch(args):
    started  = time.time()
    log      = []
    plain    = Path(os.path.abspath(args.cache_root))                        # <-- What git is given: it refuses a \\?\ path
    root     = long_path(plain)                                              # <-- What Python opens: the engine's deepest files pass 260 characters
    root.mkdir(parents=True, exist_ok=True)
    git = find_git(args.git)
    if not git:
        raise RuntimeError('git was not found. Install Git for Windows, or name git.exe in the plugin config (remoteEngine.git).')
    patterns = json.loads(Path(args.patterns).read_text(encoding='utf-8-sig'))
    if not isinstance(patterns, list) or not patterns:
        raise RuntimeError('The sparse patterns file is empty.')

    # The branch's commit on GitHub: nothing to download when the cache already holds it
    heads = run_git(git, ['ls-remote', args.url, f'refs/heads/{args.branch}'], log=log)
    if not heads:
        raise RuntimeError(f'GitHub has no branch {args.branch} at {args.url}.')
    commit = heads.split()[0]
    state  = read_json(root / STATE_FILE) or {}
    folder = root / f'{FOLDER_PREFIX}{commit[:7]}'
    if not args.force and state.get('Commit') == commit and all((folder / f).is_file() for f in REQUIRED_FILES):
        return {'ok': True, 'changed': False, 'commit': commit, 'folder': str(plain / folder.name), 'appVersion': state.get('AppVersion'),
                'message': f'The cache already holds {args.branch} at {commit[:7]} (PainterlyNPR {state.get("AppVersion")}).',
                'seconds': round(time.time() - started, 2), 'log': log}

    # A shallow, blob-less, sparse clone into staging: only the patterns' files are downloaded
    staging_name  = f'{STAGING_PREFIX}{datetime.now().strftime("%Y%m%d_%H%M%S")}'
    staging       = root / staging_name
    staging_plain = plain / staging_name
    remove_tree(staging)
    try:
        run_git(git, ['clone', '--depth', '1', '--branch', args.branch, '--filter=blob:none', '--no-checkout', '--sparse', args.url, str(staging_plain)], log=log)
        run_git(git, ['sparse-checkout', 'set', '--no-cone'] + patterns, cwd=staging_plain, log=log)
        run_git(git, ['checkout', args.branch], cwd=staging_plain, log=log)
        head = run_git(git, ['rev-parse', 'HEAD'], cwd=staging_plain, log=log)
        missing = [f for f in REQUIRED_FILES if not (staging / f).is_file()]
        if missing:
            raise RuntimeError('The download is missing ' + ', '.join(missing) + '.')
        config      = read_json(staging / MAIN_CONFIG) or {}
        app_version = find_key(config, 'AppVersion')
        remove_tree(staging / '.git')                                         # <-- A cache, not a clone: nobody works in it
        files = [p for p in staging.rglob('*') if p.is_file()]
        size  = sum(p.stat().st_size for p in files)
        folder = root / f'{FOLDER_PREFIX}{head[:7]}'
        if folder.exists():
            remove_tree(folder)
        os.replace(staging, folder)
    except Exception:
        remove_tree(staging)
        raise

    record = {
        'Schema'      : 'Na__PainterlyAssets__RemoteCache__State',
        'Url'         : args.url,
        'Branch'      : args.branch,
        'Commit'      : head,
        'CommitShort' : head[:7],
        'Folder'      : folder.name,
        'AppVersion'  : app_version,
        'Files'       : len(files),
        'Bytes'       : size,
        'FetchedIso'  : iso_now(),
        'Previous'    : state.get('Folder'),
        'Patterns'    : patterns,                                             # <-- What this cache holds: a plugin that asks for more tops it up
    }
    write_json(root / STATE_FILE, record)

    # Keep the folder in use and the one before it (an open window may still be reading it); older ones and stray staging folders go
    kept = {folder.name, state.get('Folder') or ''}
    for old in root.glob(f'{FOLDER_PREFIX}*'):
        if old.is_dir() and old.name not in kept:
            remove_tree(old)
    for stray in root.glob(f'{STAGING_PREFIX}*'):
        remove_tree(stray)

    return {'ok': True, 'changed': True, 'commit': head, 'folder': str(plain / folder.name), 'appVersion': app_version,
            'files': len(files), 'bytes': size,
            'message': f'Downloaded PainterlyNPR {app_version} ({args.branch} at {head[:7]}): {len(files)} files, {size / 1048576:.1f} MB.',
            'seconds': round(time.time() - started, 2), 'log': log}


def find_key(node, key):
    """The first value of key anywhere in a JSON document (the main config keeps AppVersion in a section)."""
    if isinstance(node, dict):
        if key in node and not isinstance(node[key], (dict, list)):
            return node[key]
        for value in node.values():
            found = find_key(value, key)
            if found is not None:
                return found
    elif isinstance(node, list):
        for value in node:
            found = find_key(value, key)
            if found is not None:
                return found
    return None

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Entry
# -----------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description='Cache PainterlyNPR from its GitHub repo for the NPR viewport.')
    parser.add_argument('--url', required=True)
    parser.add_argument('--branch', default='main')
    parser.add_argument('--cache-root', required=True)
    parser.add_argument('--patterns', required=True, help='a JSON list of sparse checkout patterns')
    parser.add_argument('--result', required=True)
    parser.add_argument('--git', default='')
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()
    try:
        result = fetch(args)
    except subprocess.TimeoutExpired:
        result = {'ok': False, 'message': f'git took longer than {GIT_TIMEOUT_S} seconds and was stopped. Check the network, then Reload Remote Plugin Files again.'}
    except Exception as error:                                                 # noqa: BLE001 - every failure goes back to the plugin in words
        result = {'ok': False, 'message': str(error)}
    write_json(args.result, result)
    return 0 if result.get('ok') else 1


if __name__ == '__main__':
    sys.exit(main())

# =============================================================================
# END OF FILE
# =============================================================================
