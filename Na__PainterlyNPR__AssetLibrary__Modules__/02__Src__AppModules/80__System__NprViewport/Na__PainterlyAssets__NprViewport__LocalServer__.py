# =============================================================================
# NA PAINTERLYNPR ASSETS - NPR VIEWPORT - LOCAL SERVER
# =============================================================================
#
# FILE       : Na__PainterlyAssets__NprViewport__LocalServer__.py
# PURPOSE    : The plugin's own web server on 127.0.0.1: PainterlyNPR's app from
#              the remote cache, the plugin's host scripts beside it, and each
#              project's GLB cache, so the NPR Viewport and NPR Parameters
#              windows can run the engine's ES modules (which never load from a
#              file:// page).
# CREATED    : 01-Nov-2026
#
# DESCRIPTION:
# - ROUTES:
#     /npr/<commit>/<path>   the engine, from 93__RemoteCache__CoreEngine/
#                            PainterlyNPR__<commit> (the repo's own files, never
#                            the plugin's). <commit> in the path keeps a window
#                            on the files it opened with until it reloads.
#                            'local' serves the engine.localOverrideFolder a
#                            developer chose instead (no-store).
#     /host/<path>           the plugin's host scripts, styles and icons (three
#                            folders only)
#     /cache/<key>/<file>    a project's cached GLBs and its scene file
#     /api/...               404: the app's saves fall back to its own storage
#     /__na/ping             is it up (the plugin asks before it opens a window)
#     /__na/shutdown         POST with the token: stop
#     /__na/export           POST with the token (v1.1.0): one picture NPR Export
#                            drew, written into the outbox folder as
#                            <job>__<item>.<png|jpg|pdf>; the plugin moves it to
#                            where it belongs. SketchUp's browser cannot
#                            download a file, so the page hands it here.
# - THE APP'S OWN PAGE, WITH THE HOST ADDED: PainterlyNPR__App__.html?na-host=
#   viewport (or parameters) is the repo's page byte for byte plus an import
#   map in its head (PainterlyNPR/ is the engine's modules, as ValeVision
#   AURA's) and, after the app's own Init module, the plugin's host module for
#   that window. Module scripts run in document order, so the host runs once
#   the engine has booted.
# - The service worker is never served: it would keep a stale copy of the
#   engine in SketchUp's browser after Reload Remote Plugin Files.
# - Only loopback; only GET and HEAD, and the two token-guarded POSTs (the
#   export writes one file of a fixed shape into the one outbox folder, never a
#   path the page names). A path that leaves its root is refused. Files are
#   opened with the \\?\ prefix: the engine's deepest files sit past 260
#   characters in the Plugins folder.
# - Stops by itself when SketchUp exits (its process id is watched), so it never
#   outlives the session that started it.
# - ITS PORT IS ITS OWN (1.1.0): on Windows a socket with SO_REUSEADDR (Python's
#   default for an HTTP server) can bind a port another server already listens
#   on, and then either one answers. Two SketchUps each ran a 1.0.0 server on
#   8147 that way (found 01-Nov-2026). So the port is taken exclusively, and a
#   second SketchUp's server is given another by the system.
#
# USAGE:
#   pythonw -I -X utf8 Na__PainterlyAssets__NprViewport__LocalServer__.py
#       --engine-root <93__RemoteCache__CoreEngine> --host-root <plugin modules folder>
#       --projects-root <92__UserProjects__ProjectCache> --parent-pid <SketchUp pid>
#       --ready-file <json> --token <random> [--override <folder>] [--log <file>]
#       [--outbox <folder>]
#
# =============================================================================

import argparse
import ctypes
import json
import mimetypes
import os
import re
import socket
import sys
import threading
import time
import urllib.parse
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

SERVER_VERSION  = '1.1.0'                                                    # <-- 1.1.0 (plugin 0.3.0): /__na/export; the plugin restarts an older server
APP_PAGE        = 'PainterlyNPR__App__.html'
EXPORT_NAME     = re.compile(r'\A[0-9a-f]{12}__[0-9]{1,4}\.(png|jpg|pdf)\Z')
EXPORT_MAX      = 2 * 1024 * 1024 * 1024                                     # <-- 2 GB: past a 600 dpi A3 PNG many times
EXPORT_CHUNK    = 1024 * 1024
DISCARD_MAX     = 64 * 1024 * 1024                                           # <-- A refused body up to this is read, so the reason reaches the page
NEVER_SERVED    = {'Na__Pwa__ServiceWorker__.js'}                            # <-- A worker would pin a stale engine in SketchUp's browser
HOST_FOLDERS    = ('02__Src__AppModules/80__System__NprViewport/', '03__Style__AppStylesheets/', '01__AppAssets__PainterlyAssets/')
CACHE_TYPES     = {'.glb', '.json'}
HOST_ROLES      = {                                                          # <-- role: (host module, its stylesheet, the page's classes from the first paint)
    'viewport'   : ('Na__PainterlyAssets__NprViewport__HostViewport__.mjs', 'Na__PainterlyAssets__UiFeature__Styles__NprViewport__.css', 'Na__NprHost Na__NprHost--Viewport Na__NprHost--Waiting'),
    'parameters' : ('Na__PainterlyAssets__NprViewport__HostParameters__.mjs', 'Na__PainterlyAssets__UiFeature__Styles__NprParameters__.css', 'Na__NprHost Na__NprHost--Parameters'),
}
WATCH_SECONDS   = 2.0
MIME_TYPES      = {
    '.mjs': 'text/javascript; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8',
    '.css': 'text/css; charset=utf-8', '.html': 'text/html; charset=utf-8', '.svg': 'image/svg+xml', '.webp': 'image/webp',
    '.png': 'image/png', '.jpg': 'image/jpeg', '.glb': 'model/gltf-binary', '.wasm': 'application/wasm', '.woff2': 'font/woff2',
    '.woff': 'font/woff', '.ttf': 'font/ttf', '.webmanifest': 'application/manifest+json', '.ico': 'image/x-icon', '.md': 'text/plain; charset=utf-8',
}

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Paths
# -----------------------------------------------------------------------------

def long_path(path):
    """An absolute path Windows opens past 260 characters."""
    full = os.path.abspath(str(path))
    if os.name == 'nt' and not full.startswith('\\\\?\\'):
        full = '\\\\?\\' + full
    return full


def inside(root, relative):
    """root/relative, or None when relative would leave root (.., a drive, a stray backslash)."""
    clean = urllib.parse.unquote(relative).replace('\\', '/')
    if not clean or clean.startswith('/') or ':' in clean or any(part in ('', '.', '..') for part in clean.split('/')):
        return None
    target = os.path.abspath(os.path.join(root, *clean.split('/')))
    base   = os.path.abspath(root)
    return target if target.lower().startswith(base.lower() + os.sep) else None

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | The Server
# -----------------------------------------------------------------------------

class Settings:
    engine_root   = ''
    host_root     = ''
    projects_root = ''
    override      = ''
    outbox        = ''
    token         = ''
    log_path      = ''
    lock          = threading.Lock()


def log(message):
    if not Settings.log_path:
        return
    with Settings.lock:
        try:
            with open(Settings.log_path, 'a', encoding='utf-8') as handle:
                handle.write(f'{datetime.now().strftime("%H:%M:%S")} {message}\n')
        except OSError:
            pass


class Server(ThreadingHTTPServer):
    """A port no other server shares: never SO_REUSEADDR on Windows, SO_EXCLUSIVEADDRUSE instead."""
    allow_reuse_address = os.name != 'nt'
    daemon_threads = True

    def server_bind(self):
        if os.name == 'nt' and hasattr(socket, 'SO_EXCLUSIVEADDRUSE'):
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()


class Handler(BaseHTTPRequestHandler):
    server_version = f'NaPainterlyNprViewport/{SERVER_VERSION}'
    protocol_version = 'HTTP/1.1'

    def log_message(self, fmt, *args):                                         # noqa: A003 - quiet: errors only, in the plugin's log
        return

    # -- Answers ---------------------------------------------------------------

    def send_bytes(self, status, body, content_type, cache='no-store', head=False):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', cache)
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        if not head:
            self.wfile.write(body)

    def send_json(self, status, data, head=False):
        self.send_bytes(status, json.dumps(data).encode('utf-8'), MIME_TYPES['.json'], head=head)

    def send_file(self, path, cache, head=False):
        try:
            with open(long_path(path), 'rb') as handle:
                body = handle.read()
        except FileNotFoundError:
            return self.send_json(404, {'error': 'not found', 'path': self.path}, head)
        except OSError as error:
            log(f'READ FAILED {path}: {error}')
            return self.send_json(500, {'error': str(error)}, head)
        mime = MIME_TYPES.get(Path(path).suffix.lower()) or mimetypes.guess_type(str(path))[0] or 'application/octet-stream'
        self.send_bytes(200, body, mime, cache, head)

    # -- Routes ----------------------------------------------------------------

    def do_HEAD(self):                                                         # noqa: N802 - http.server's name
        self.route(head=True)

    def do_GET(self):                                                          # noqa: N802
        self.route(head=False)

    def do_POST(self):                                                         # noqa: N802
        url = urllib.parse.urlsplit(self.path)
        token_ok = bool(Settings.token) and self.headers.get('X-Na-Token') == Settings.token
        if url.path == '/__na/shutdown' and token_ok:
            self.send_json(200, {'ok': True, 'stopping': True})
            log('Shutdown asked for by the plugin.')
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        if url.path == '/__na/export' and token_ok:
            return self.receive_export()
        self.discard_body()
        self.send_json(403 if url.path in ('/__na/shutdown', '/__na/export') else 405, {'error': 'refused'})

    def discard_body(self):
        """A refused request's body read and dropped (up to DISCARD_MAX), so the page hears why, not a reset connection."""
        self.close_connection = True
        try:
            remaining = int(self.headers.get('Content-Length', '0') or 0)
        except ValueError:
            return
        if remaining > DISCARD_MAX:
            return
        while remaining > 0:
            chunk = self.rfile.read(min(EXPORT_CHUNK, remaining))
            if not chunk:
                return
            remaining -= len(chunk)

    def receive_export(self):
        """One picture into the outbox: <job>__<item>.<png|jpg|pdf>, written whole or not at all."""
        name = self.headers.get('X-Na-File', '')
        try:
            size = int(self.headers.get('Content-Length', ''))
        except ValueError:
            size = -1
        problem = None
        if not Settings.outbox:
            problem = (503, 'This server has no outbox for exports.')
        elif not EXPORT_NAME.match(name):
            problem = (400, 'An export file is named <job>__<item>.<png|jpg|pdf>.')
        elif size <= 0 or size > EXPORT_MAX:
            problem = (413 if size > EXPORT_MAX else 411, 'An export needs its length, at most 2 GB.')
        if problem:
            self.discard_body()
            return self.send_json(problem[0], {'error': problem[1]})
        target = os.path.join(Settings.outbox, name)
        part   = target + '.part'
        try:
            os.makedirs(long_path(Settings.outbox), exist_ok=True)
            remaining = size
            with open(long_path(part), 'wb') as handle:
                while remaining > 0:
                    chunk = self.rfile.read(min(EXPORT_CHUNK, remaining))
                    if not chunk:
                        break
                    handle.write(chunk)
                    remaining -= len(chunk)
            if remaining:
                os.remove(long_path(part))
                self.close_connection = True
                return self.send_json(400, {'error': f'The picture arrived short by {remaining} bytes.'})
            os.replace(long_path(part), long_path(target))
        except OSError as error:
            log(f'EXPORT FAILED {name}: {error}')
            try:
                os.remove(long_path(part))
            except OSError:
                pass
            self.close_connection = True
            return self.send_json(500, {'error': str(error)})
        log(f'Export {name}: {size} bytes.')
        self.send_json(200, {'ok': True, 'file': name, 'bytes': size})

    def route(self, head):
        url   = urllib.parse.urlsplit(self.path)
        parts = url.path.split('/', 3)                                         # <-- ['', 'npr', '<commit>', '<rest>']
        try:
            if url.path == '/__na/ping':
                return self.send_json(200, {'ok': True, 'pid': os.getpid(), 'version': SERVER_VERSION}, head)
            if url.path.startswith('/api/'):
                return self.send_json(404, {'error': 'The SketchUp NPR viewport keeps no saves on this server.'}, head)
            if len(parts) >= 4 and parts[1] == 'npr':
                return self.serve_engine(parts[2], parts[3], url.query, head)
            if url.path.startswith('/host/'):
                return self.serve_host(url.path[len('/host/'):], head)
            if len(parts) >= 4 and parts[1] == 'cache':
                return self.serve_cache(parts[2], parts[3], head)
            self.send_json(404, {'error': 'not found', 'path': url.path}, head)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass

    def serve_engine(self, commit, relative, query, head):
        if commit == 'local' and Settings.override:
            root, cache = Settings.override, 'no-store'
        elif commit and all(c in '0123456789abcdef' for c in commit.lower()):
            root, cache = os.path.join(Settings.engine_root, f'PainterlyNPR__{commit}'), 'public, max-age=31536000, immutable'
        else:
            return self.send_json(404, {'error': 'no such engine cache', 'commit': commit}, head)
        if Path(relative).name in NEVER_SERVED:
            return self.send_json(404, {'error': 'The service worker is not served inside SketchUp.'}, head)
        target = inside(root, relative)
        if target is None:
            return self.send_json(403, {'error': 'refused'}, head)
        role = urllib.parse.parse_qs(query).get('na-host', [''])[0]
        if relative == APP_PAGE and role in HOST_ROLES:
            return self.serve_app_page(target, role, head)
        self.send_file(target, cache, head)

    def serve_app_page(self, target, role, head):
        """The repo's own page, plus the import map and this window's host (nothing of the page is changed)."""
        try:
            with open(long_path(target), 'r', encoding='utf-8') as handle:
                page = handle.read()
        except OSError as error:
            return self.send_json(404, {'error': f'The engine page is not in the cache: {error}'}, head)
        module, style, classes = HOST_ROLES[role]
        class_list = ', '.join(f"'{name}'" for name in classes.split())
        head_add = (
            '\n    <!-- Na PainterlyNPR Assets (SketchUp): the engine\'s modules under the PainterlyNPR/ prefix, and this window\'s look from the first paint -->\n'
            '    <script type="importmap">{"imports": {"PainterlyNPR/": "./02__Src__AppModules/"}}</script>\n'
            f'    <script>document.documentElement.classList.add({class_list});</script>\n'
            f'    <link rel="stylesheet" href="/host/03__Style__AppStylesheets/{style}">\n'
        )
        body_add = (
            '\n    <!-- Na PainterlyNPR Assets (SketchUp): this window\'s host, after the app\'s own Init (module scripts run in order) -->\n'
            f'    <script type="module" src="/host/02__Src__AppModules/80__System__NprViewport/{module}"></script>\n'
        )
        if '</head>' not in page or '</body>' not in page:
            return self.send_json(500, {'error': 'The engine page has no head or body to add the host to.'}, head)
        page = page.replace('</head>', head_add + '</head>', 1)
        index = page.rfind('</body>')
        page = page[:index] + body_add + page[index:]
        self.send_bytes(200, page.encode('utf-8'), MIME_TYPES['.html'], 'no-store', head)

    def serve_host(self, relative, head):
        clean = urllib.parse.unquote(relative)
        if not any(clean.startswith(folder) for folder in HOST_FOLDERS):
            return self.send_json(403, {'error': 'refused'}, head)
        target = inside(Settings.host_root, clean)
        if target is None:
            return self.send_json(403, {'error': 'refused'}, head)
        self.send_file(target, 'no-store', head)

    def serve_cache(self, key, relative, head):
        folder = urllib.parse.unquote(key)
        safe   = folder and not any(bad in folder for bad in ('/', '\\', '..', ':'))
        target = inside(os.path.join(Settings.projects_root, folder), relative) if safe else None
        if target is None or Path(target).suffix.lower() not in CACHE_TYPES:
            return self.send_json(403, {'error': 'refused'}, head)
        self.send_file(target, 'no-store', head)

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | SketchUp's Process
# -----------------------------------------------------------------------------

def process_alive(pid):
    """True while the process runs. Never os.kill(pid, 0): on Windows that TERMINATES it."""
    if os.name != 'nt':
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False
    kernel = ctypes.windll.kernel32
    handle = kernel.OpenProcess(0x1000, False, pid)                            # <-- PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:
        return False
    try:
        code = ctypes.c_ulong()
        ok = kernel.GetExitCodeProcess(handle, ctypes.byref(code))
        return bool(ok) and code.value == 259                                  # <-- STILL_ACTIVE
    finally:
        kernel.CloseHandle(handle)


def watch_parent(server, pid):
    while True:
        time.sleep(WATCH_SECONDS)
        if not process_alive(pid):
            log(f'SketchUp ({pid}) has gone: stopping.')
            server.shutdown()
            return

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Entry
# -----------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Serve PainterlyNPR to the plugin's NPR windows.")
    parser.add_argument('--engine-root', required=True)
    parser.add_argument('--host-root', required=True)
    parser.add_argument('--projects-root', required=True)
    parser.add_argument('--parent-pid', type=int, required=True)
    parser.add_argument('--ready-file', required=True)
    parser.add_argument('--token', required=True)
    parser.add_argument('--override', default='')
    parser.add_argument('--log', default='')
    parser.add_argument('--port', type=int, default=0)
    parser.add_argument('--outbox', default='')
    args = parser.parse_args()

    Settings.engine_root   = os.path.abspath(args.engine_root)
    Settings.host_root     = os.path.abspath(args.host_root)
    Settings.projects_root = os.path.abspath(args.projects_root)
    Settings.override      = os.path.abspath(args.override) if args.override else ''
    Settings.outbox        = os.path.abspath(args.outbox) if args.outbox else ''
    Settings.token         = args.token
    Settings.log_path      = args.log
    if args.log:
        try:
            Path(args.log).write_text('', encoding='utf-8')
        except OSError:
            Settings.log_path = ''

    try:
        server = Server(('127.0.0.1', args.port), Handler)                     # <-- The usual port keeps the windows' browser storage from one day to the next
    except OSError as error:
        log(f'Port {args.port} is taken ({error}): the system chooses one.')
        server = Server(('127.0.0.1', 0), Handler)
    port = server.server_address[1]
    ready = {'ok': True, 'port': port, 'pid': os.getpid(), 'version': SERVER_VERSION, 'started': datetime.now().isoformat(timespec='seconds')}
    part = Path(args.ready_file + '.part')
    part.write_text(json.dumps(ready), encoding='utf-8')
    os.replace(part, args.ready_file)
    log(f'Serving on 127.0.0.1:{port} for SketchUp {args.parent_pid}; engine {Settings.engine_root}; override {Settings.override or "none"}.')
    threading.Thread(target=watch_parent, args=(server, args.parent_pid), daemon=True).start()
    try:
        server.serve_forever(poll_interval=0.5)
    finally:
        server.server_close()
        try:
            os.remove(args.ready_file)
        except OSError:
            pass
        log('Stopped.')
    return 0


if __name__ == '__main__':
    sys.exit(main())

# =============================================================================
# END OF FILE
# =============================================================================
