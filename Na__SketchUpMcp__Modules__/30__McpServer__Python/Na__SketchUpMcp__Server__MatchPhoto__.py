# =============================================================================
# NA SKETCHUP MCP - PYTHON SERVER - MATCH PHOTO SOLVE
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Server__MatchPhoto__.py
# PURPOSE    : match_photo_solve (1.0.40): Adam's Match Photo done by numbers,
#              answered by the server alone (no SketchUp needed). It writes the
#              job, runs the vision worker as a child process and returns its
#              result with the marked-up photo as an image the agent can see.
# CREATED    : 25-Nov-2026 (1.0.40, Cooper 62712)
#
# WHY A CHILD PROCESS: the worker (35__VisionWorker__Python) needs numpy, OpenCV
# and SciPy; this server is standard library only and must stay so (AGENTS.md
# rule 6). The worker runs on the same Python as this server unless the
# AppConfig's defaults.vision_python names another, and says exactly what is
# missing when a module is.
#
# WHERE THE FILES GO: out_dir, or the job's own folder beside the photo
# (<job>/01__ReferenceFiles/12__Photos__MatchPhoto, as image_flatten uses
# 11__Photos__Flattened), else a MatchPhoto folder beside the photo. Nothing is
# ever written over: the worker adds __2, __3 to a name that exists.
#
# =============================================================================

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

NA_SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
NA_MODULES_ROOT = os.path.abspath(os.path.join(NA_SERVER_DIR, '..'))
NA_WORKER_PATH = os.path.join(NA_MODULES_ROOT, '35__VisionWorker__Python', 'Na__SketchUpMcp__VisionWorker__MatchPhoto__.py')
NA_APPCONFIG_PATH = os.path.join(NA_MODULES_ROOT, '02__Plugin__CoreAppData', 'Na__SketchUpMcp__CoreAppData__AppConfig__.json')
NA_FORMATS = ('.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff')
NA_SUBFOLDER = os.path.join('01__ReferenceFiles', '12__Photos__MatchPhoto')
NA_SERVER_ONLY = ('out_dir', 'name', 'timeout_s')


class Na__MatchPhotoError(Exception):
    """A refusal shaped like the bridge's: code, message and the fix."""

    def __init__(self, code, message, hint=None):
        super().__init__(message)
        self.na_code = code
        self.na_message = message
        self.na_hint = hint


# -----------------------------------------------------------------------------
# REGION | Settings
# -----------------------------------------------------------------------------

def na_defaults():
    try:
        with open(NA_APPCONFIG_PATH, 'r', encoding='utf-8') as handle:
            return (json.load(handle) or {}).get('defaults') or {}
    except (OSError, ValueError):
        return {}


def Na__MatchPhoto__Python():
    """The Python the worker runs on: defaults.vision_python, or this server's own."""
    named = str(na_defaults().get('vision_python') or '').strip()
    return named if named else sys.executable


def na_out_dir(photo, given):
    if given:
        folder = os.path.abspath(given)
        if not os.path.isdir(folder):
            parent = os.path.dirname(folder)
            if not os.path.isdir(parent):
                raise Na__MatchPhotoError('file_error', 'Folder does not exist: %s.' % parent, 'Give out_dir inside a folder that exists.')
        return folder
    here = os.path.dirname(os.path.abspath(photo))
    probe = here
    for _ in range(6):                                       # the job folder: the photo's ancestor holding 01__ReferenceFiles
        if os.path.basename(probe) == '01__ReferenceFiles':
            return os.path.join(os.path.dirname(probe), NA_SUBFOLDER)
        parent = os.path.dirname(probe)
        if parent == probe:
            break
        probe = parent
    return os.path.join(here, 'MatchPhoto')


def na_base_name(name, photo):
    stem = os.path.splitext(os.path.basename(photo))[0]
    text = name or stem
    keep = ''.join(ch if (ch.isalnum() or ch in '_-') else '-' for ch in text)
    while '--' in keep:
        keep = keep.replace('--', '-')
    return keep.strip('-_')[:90] or 'MatchPhoto'            # PM01__FrontRight__ -> PM01__FrontRight__MatchPhoto.jpg

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Solve
# -----------------------------------------------------------------------------

def Na__MatchPhoto__Solve(arguments, timeout_s=170):
    photo = os.path.abspath(str(arguments.get('photo') or ''))
    if not os.path.isfile(photo):
        raise Na__MatchPhotoError('file_error', 'No photo at %s.' % photo, 'Give the absolute path of the site photo (JPEG or PNG).')
    if os.path.splitext(photo)[1].lower() not in NA_FORMATS:
        raise Na__MatchPhotoError('invalid_params', '%s photos are not read here.' % os.path.splitext(photo)[1],
                                  'Convert it to JPEG or PNG first (SketchUp refuses WebP too).')
    if not os.path.isfile(NA_WORKER_PATH):
        raise Na__MatchPhotoError('unsupported', 'The vision worker is missing: %s.' % NA_WORKER_PATH, 'Restore 35__VisionWorker__Python from the plugin.')
    out_dir = na_out_dir(photo, arguments.get('out_dir'))
    job = {key: value for key, value in arguments.items() if key not in NA_SERVER_ONLY and value is not None}
    # the schema's single-typed options, in the worker's terms
    if arguments.get('lens_lambda') is not None:
        job['distortion'] = float(arguments['lens_lambda'])
    else:
        job['distortion'] = 'none' if arguments.get('lens') == 'none' else 'auto'
    job.pop('lens', None)
    job.pop('lens_lambda', None)
    for key in ('enhance', 'overlay'):
        spec = arguments.get(key)
        if isinstance(spec, dict) and spec.get('off'):
            job[key] = False
        elif isinstance(spec, dict):
            job[key] = {k: v for k, v in spec.items() if k != 'off'}
    job['photo'] = photo
    job['out_dir'] = out_dir
    job['base_name'] = na_base_name(arguments.get('name'), photo)
    work = tempfile.mkdtemp(prefix='na_matchphoto_')
    job_path = os.path.join(work, 'job.json')
    job['result_path'] = os.path.join(work, 'result.json')
    with open(job_path, 'w', encoding='utf-8') as handle:
        json.dump(job, handle)
    python = Na__MatchPhoto__Python()
    limit = float(arguments.get('timeout_s') or na_defaults().get('vision_timeout_s') or timeout_s)
    started = time.time()
    try:
        flags = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
        done = subprocess.run([python, NA_WORKER_PATH, job_path], capture_output=True, text=True, timeout=limit, creationflags=flags)
    except FileNotFoundError:
        raise Na__MatchPhotoError('unsupported', 'The vision worker\'s Python was not found: %s.' % python,
                                  'Set defaults.vision_python in the AppConfig to a Python with numpy, scipy and OpenCV.')
    except subprocess.TimeoutExpired:
        raise Na__MatchPhotoError('timeout', 'The vision worker ran past %.0f s.' % limit,
                                  'Use fewer refits (uncertainty.refits), a smaller uncertainty.max_seconds, or pass timeout_s.')
    try:
        with open(job['result_path'], 'r', encoding='utf-8') as handle:
            result = json.load(handle)
    except (OSError, ValueError):
        tail = (done.stderr or done.stdout or '').strip()[-1500:]
        raise Na__MatchPhotoError('operation_failed', 'The vision worker stopped without a result (exit %s).' % done.returncode,
                                  'Its last words: %s' % (tail or 'none'))
    shutil.rmtree(work, ignore_errors=True)                  # the job and result files; the outputs live in out_dir
    if not result.get('ok'):
        error = result.get('error') or {}
        raise Na__MatchPhotoError(error.get('code', 'operation_failed'), error.get('message', 'The vision worker failed.'), error.get('hint'))
    return na_shape(result, time.time() - started)


def na_shape(result, seconds):
    """The worker's result for the agent: a summary line first, the marked-up photo as an image, the rest as is."""
    camera = result.get('camera') or {}
    stop = result.get('accuracy_stop')
    checks = result.get('checks') or []
    worst = max([abs(v) for row in checks for v in (row.get('miss_mm') or {}).values()] or [0.0])
    summary = ('Solved Match Photo on %s: focal %s px (%s mm equivalent), eye %s, fit %s px rms over %d lines; lens %s; centre of view %s. %s'
               % (os.path.basename(result['photo']['source']), camera.get('f_px'), camera.get('f_equiv_mm'), camera.get('eye'),
                  (result.get('fit') or {}).get('rms_px'), len(result.get('lines') or []),
                  'taken out' if (result['photo'].get('lens') or {}).get('applied') else 'left in',
                  (camera.get('principal_point') or {}).get('mode', 'centre'),
                  ('ACCURACY STOP: %s. Ask Adam on the board, build nothing on it.' % '; '.join(result.get('accuracy_stop_reasons') or []))
                  if stop else ('Checks within 25 mm (worst %.0f).' % worst if checks else 'No checks were given: add features the fit did not use.')))
    payload = {'summary': summary, 'accuracy_stop': bool(stop)}
    payload.update({key: value for key, value in result.items() if key not in ('ok', 'accuracy_stop')})
    payload['seconds'] = round(seconds, 1)
    preview = (result.get('files') or {}).get('preview')
    if preview and os.path.isfile(preview):
        payload['preview_image'] = {'image_file': preview, 'mime_type': 'image/jpeg', 'keep_file': True,
                                    'note': 'The photo the scene will show, at most 1600 px wide: LOOK at it. Every dotted line must lie on '
                                            'its edge across the photo; a line on the wrong feature is the agent\'s mistake, not the camera\'s.'}
    payload['next'] = ('match_photo_edit {action: "create", name: "PM01__<View>__", ...scene_arguments} makes the native Match Photo scene '
                       'from scene_arguments (photo, camera, tests). It refuses a test point SketchUp projects more than 0.05 px off.')
    return payload

# endregion -------------------------------------------------------------------

# =============================================================================
# END OF FILE
# =============================================================================
