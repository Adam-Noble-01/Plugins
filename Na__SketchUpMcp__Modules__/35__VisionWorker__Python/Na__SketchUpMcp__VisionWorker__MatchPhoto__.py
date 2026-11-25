# =============================================================================
# NA SKETCHUP MCP - VISION WORKER - MATCH PHOTO
# =============================================================================
#
# FILE       : Na__SketchUpMcp__VisionWorker__MatchPhoto__.py
# PURPOSE    : The computer-vision half of match_photo_solve (1.0.40). The Python
#              server runs it as a child process, so the server itself stays
#              standard library only: this file needs numpy, OpenCV (cv2) and
#              SciPy, and says exactly which is missing when one is.
# CREATED    : 25-Nov-2026 (1.0.40, Cooper 62712)
#
# ADAM'S METHOD (25-Nov-2026): in SketchUp's Match Photo he drags two red-axis and
# two green-axis bars onto "as far part per axis as possible and ... the longest
# lines i can see", puts the origin on a known corner and scales the photo to the
# mass he has. SketchUp's API cannot drive those bars, but it can be handed a
# finished camera (Pages#add_matchphoto_page). This worker finds that camera.
#
# WHAT IT DOES, IN ORDER:
#  1. Reads the photo upright (EXIF rotation applied: SketchUp's ImageRep would
#     ignore it) and its 35 mm focal length when the EXIF has one.
#  2. Enhances it for computer vision (Adam, 25-Nov-2026: "edge sharpening, edge
#     feature contrast enhancement, noisy element dampening"): mild non-local
#     means denoising, an edge-preserving guided filter that damps foliage and
#     brick texture, CLAHE local contrast on lightness and an unsharp mask. None
#     of them moves an edge, so the lines are snapped on the enhanced image.
#  3. Snaps every rough axis line to the strongest edge of its sign, sub-pixel,
#     and checks it against OpenCV's line segment detector.
#  4. Measures the lens's barrel distortion from those straight lines
#     (plumb-line, one-parameter division model) and keeps it only when it
#     clearly straightens them. The photo for SketchUp is undistorted with it,
#     so SketchUp's pinhole Match Photo camera fits the whole frame.
#  5. Solves Match Photo by numbers: the vanishing points of the red, green and
#     blue lines, the focal length, the rotation, then the eye from the origin
#     and the known size; then refines the camera on every line (world-known
#     CAD lines fix it, the unknown face's lines add their direction), robustly,
#     naming and dropping outliers by their source.
#  6. Reads checks and measures through the camera, each with its plus or minus
#     from refits with every line and every hand-read pixel jittered.
#  7. Writes the photo for the scene: enhanced, undistorted, with the agent's
#     fitted lines on it as transparent dotted lines (solid where they were
#     measured), the vanishing directions, the origin, the scale point, the
#     horizon and a small legend (Adam: "it gives an active way for adam to see
#     the agents exact input and interpretation").
#
# COORDINATES: photo pixels are the UPRIGHT photo's, u right and v down, with the
# image spanning 0..W and 0..H (a pixel's centre is at +0.5), as image_flatten
# and SketchUp's texture mapping read them. Results are in the UNDISTORTED
# photo's pixels, which is the photo the scene shows. World lengths are mm.
#
# JOB AND RESULT: one JSON file in (written by the server), one JSON file out
# (job['result_path']): {"ok": true, ...} or {"ok": false, "error": {"code",
# "message", "hint"}}.
#
#   python Na__SketchUpMcp__VisionWorker__MatchPhoto__.py <job.json>
#   python Na__SketchUpMcp__VisionWorker__MatchPhoto__.py --deps
#   python Na__SketchUpMcp__VisionWorker__MatchPhoto__.py --selftest
#
# =============================================================================

import json
import math
import os
import sys
import time
import traceback

NA_WORKER_VERSION = '1.0.40'
NA_DIAG_12MP = math.hypot(4032, 3024)       # 5040: the photo size the kit's pixel gates were set on
NA_AXES = {'x': (1.0, 0.0, 0.0), 'y': (0.0, 1.0, 0.0), 'z': (0.0, 0.0, 1.0)}
NA_OTHER = {'x': 'yz', 'y': 'xz', 'z': 'xy'}
NA_AXIS_BGR = {'x': (45, 45, 230), 'y': (40, 175, 40), 'z': (235, 120, 35)}     # SketchUp's red, green, blue
NA_STOP_MM = 25.0                           # the ACCURACY STOP line (3D skill, precise-vs-reference-inputs 3d)

np = None
cv2 = None


class Na__VisionError(Exception):
    """A refusal the server passes to the agent: code, message and the fix."""

    def __init__(self, code, message, hint=None):
        super().__init__(message)
        self.na_code = code
        self.na_message = message
        self.na_hint = hint


# -----------------------------------------------------------------------------
# REGION | Dependencies
# -----------------------------------------------------------------------------

def Na__VisionWorker__Deps():
    out = {'python': sys.executable, 'worker': NA_WORKER_VERSION}
    for name in ('numpy', 'cv2', 'scipy', 'PIL'):
        try:
            module = __import__(name)
            out[name] = getattr(module, '__version__', 'present')
        except Exception:                                   # noqa: BLE001 - any import failure means missing
            out[name] = None
    if out.get('cv2'):
        import cv2 as _cv2
        out['cv2_contrib'] = hasattr(_cv2, 'ximgproc')
        out['cv2_lsd'] = hasattr(_cv2, 'createLineSegmentDetector')
    return out


def na_import():
    global np, cv2
    deps = Na__VisionWorker__Deps()
    missing = [name for name in ('numpy', 'cv2', 'scipy') if not deps.get(name)]
    if missing:
        raise Na__VisionError(
            'unsupported', 'The match photo vision worker needs %s, which %s does not have.' % (' and '.join(missing), sys.executable),
            'Install them for that Python: "%s" -m pip install numpy scipy opencv-contrib-python-headless '
            '(or set defaults.vision_python in the AppConfig to a Python that has them).' % sys.executable)
    import numpy as _np
    import cv2 as _cv2
    np = _np
    cv2 = _cv2
    return deps

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Camera maths
# -----------------------------------------------------------------------------
# The camera is the kit's: p = [rotation vector (3), eye (3, mm), focal (px)];
# R = rod(p[:3]) maps world to camera, its rows are right, down and forward in
# world coordinates; the principal point is the photo's centre (W/2, H/2).

def rod(r):
    r = np.asarray(r, float)
    th = float(np.linalg.norm(r))
    if th < 1e-12:
        return np.eye(3)
    k = r / th
    K = np.array([[0.0, -k[2], k[1]], [k[2], 0.0, -k[0]], [-k[1], k[0], 0.0]])
    return np.eye(3) + math.sin(th) * K + (1.0 - math.cos(th)) * (K @ K)


def from_R(R):
    from scipy.spatial.transform import Rotation
    return Rotation.from_matrix(np.asarray(R, float)).as_rotvec()


def project(p, X, W, H):
    p = np.asarray(p, float)
    R, C, f = rod(p[:3]), p[3:6], p[6]
    Xc = (np.atleast_2d(np.asarray(X, float)) - C) @ R.T
    z = Xc[:, 2]
    safe = np.where(np.abs(z) < 1e-9, 1e-9, z)
    return np.column_stack([f * Xc[:, 0] / safe + W / 2.0, f * Xc[:, 1] / safe + H / 2.0]), z


def kinv(f, pp):
    return np.array([[1.0 / f, 0.0, -pp[0] / f], [0.0, 1.0 / f, -pp[1] / f], [0.0, 0.0, 1.0]])


def ray_world(p, px, W, H):
    p = np.asarray(p, float)
    R, f = rod(p[:3]), p[6]
    d = R.T @ (kinv(f, (W / 2.0, H / 2.0)) @ np.array([px[0], px[1], 1.0]))
    return d / np.linalg.norm(d)


def pose_angles(p):
    R = rod(np.asarray(p, float)[:3])
    right, fwd = R[0], R[2]
    clip = lambda v: max(-1.0, min(1.0, float(v)))
    return (math.degrees(math.asin(clip(fwd[2]))), math.degrees(math.asin(clip(right[2]))),
            math.degrees(math.atan2(fwd[1], fwd[0])))


def backproject(p, px, plane, W, H):
    """A photo pixel onto a plane (normal n, n.X = k): the world point, or None behind the camera."""
    p = np.asarray(p, float)
    C = p[3:6]
    n, k = plane
    b = ray_world(p, px, W, H)
    den = float(n @ b)
    if abs(den) < 1e-12:
        return None
    t = (k - float(n @ C)) / den
    return C + t * b if t > 0 else None


def parse_plane(spec):
    """{"axis": "x", "value": 17015.3} | {"point": [..], "normal": [..]} | "x=17015.3" -> (unit normal, k)."""
    if isinstance(spec, str):
        text = spec.replace(' ', '')
        if len(text) > 2 and text[0] in 'xyz' and text[1] == '=':
            return np.array(NA_AXES[text[0]]), float(text[2:])
        raise Na__VisionError('invalid_params', 'Plane "%s" is not "x=<mm>", "y=<mm>" or "z=<mm>".' % spec, None)
    if isinstance(spec, dict) and spec.get('axis') in NA_AXES and 'value' in spec:
        return np.array(NA_AXES[spec['axis']]), float(spec['value'])
    if isinstance(spec, dict) and 'point' in spec and 'normal' in spec:
        n = np.array(spec['normal'], float)
        n = n / np.linalg.norm(n)
        return n, float(n @ np.array(spec['point'], float))
    raise Na__VisionError('invalid_params', 'A plane needs {"axis": "x|y|z", "value": mm} or {"point": [x, y, z], "normal": [x, y, z]}.', None)

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Photo: upright, EXIF, enhancement
# -----------------------------------------------------------------------------

def na_read_upright(path):
    """The photo as BGR, turned by its EXIF orientation (OpenCV told to ignore it, then turned here, so the
    behaviour never depends on the OpenCV build), and the EXIF 35 mm focal length or None."""
    data = np.fromfile(path, dtype=np.uint8)
    flags = cv2.IMREAD_COLOR | getattr(cv2, 'IMREAD_IGNORE_ORIENTATION', 0)
    img = cv2.imdecode(data, flags)
    if img is None:
        raise Na__VisionError('file_error', 'OpenCV could not read %s.' % path, 'Use a JPEG or PNG photo.')
    orientation, f35 = 1, None
    try:
        from PIL import Image
        with Image.open(path) as im:
            exif = im.getexif()
            orientation = int(exif.get(0x0112, 1) or 1)
            sub = exif.get_ifd(0x8769) if hasattr(exif, 'get_ifd') else {}
            value = sub.get(0xA405) if sub else None
            f35 = float(value) if value else None
    except Exception:                                       # noqa: BLE001 - no EXIF is normal
        pass
    turn = {2: lambda a: a[:, ::-1], 3: lambda a: a[::-1, ::-1], 4: lambda a: a[::-1, :],
            5: lambda a: np.transpose(a, (1, 0, 2)), 6: lambda a: np.rot90(a, -1),
            7: lambda a: np.transpose(a, (1, 0, 2))[::-1, ::-1],
            8: lambda a: np.rot90(a, 1)}
    if orientation in turn:
        img = np.ascontiguousarray(turn[orientation](img))
    return img, orientation, f35


def na_enhance(bgr, opts):
    """Computer-vision legibility (and what Adam sees in the scene): denoise, damp texture, local contrast,
    sharpen. Each step is optional; none moves an edge. Returns the shown image, the steps, and the image lines are
    measured on (every step but the sharpening, which rings at edges and lifts noise in flat walling)."""
    out = bgr.copy()
    diag = math.hypot(out.shape[1], out.shape[0])
    done = []
    denoise = float(opts.get('denoise', 4.0))
    mp = out.shape[0] * out.shape[1] / 1e6
    if denoise > 0 and mp <= float(opts.get('denoise_max_mp', 6.0)):
        out = cv2.fastNlMeansDenoisingColored(out, None, denoise, denoise, 7, 21)
        done.append('non-local means denoise h %.1f' % denoise)
    elif denoise > 0:
        out = cv2.bilateralFilter(out, 5, 18, 5)
        done.append('bilateral denoise (photo over %.0f MP)' % float(opts.get('denoise_max_mp', 6.0)))
    damp = float(opts.get('texture_damping', 0.5))
    if damp > 0:
        radius = max(2, int(round(diag / 700.0)))
        eps = (0.01 + 0.03 * min(damp, 1.0)) ** 2 * 255.0 ** 2
        if hasattr(cv2, 'ximgproc') and hasattr(cv2.ximgproc, 'guidedFilter'):
            smooth = cv2.ximgproc.guidedFilter(out, out, radius, eps)
            done.append('guided filter r %d' % radius)
        else:
            smooth = cv2.bilateralFilter(out, 2 * radius + 1, 30, radius)
            done.append('bilateral texture damping r %d' % radius)
        out = cv2.addWeighted(smooth, min(damp, 1.0), out, 1.0 - min(damp, 1.0), 0)
    clip = float(opts.get('clahe', 2.0))
    if clip > 0:
        lab = cv2.cvtColor(out, cv2.COLOR_BGR2LAB)
        tiles = max(4, int(round(diag / 180.0)))
        lab[:, :, 0] = cv2.createCLAHE(clipLimit=clip, tileGridSize=(tiles, tiles)).apply(lab[:, :, 0])
        out = cv2.cvtColor(lab, cv2.COLOR_LAB2BGR)
        done.append('CLAHE clip %.1f, %d x %d tiles' % (clip, tiles, tiles))
    measure = out.copy()                                    # lines are snapped here: sharpening rings and lifts noise
    amount = float(opts.get('sharpen', 0.8))
    if amount > 0:
        sigma = max(0.8, diag / 1600.0)
        blur = cv2.GaussianBlur(out, (0, 0), sigma)
        out = cv2.addWeighted(out, 1.0 + amount, blur, -amount, 0)
        done.append('unsharp mask %.1f at sigma %.1f (shown, not measured)' % (amount, sigma))
    return out, done, measure

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Lines: snapping, detector support
# -----------------------------------------------------------------------------
# Internally pixels are sampled at index coordinates (a pixel's centre at an
# integer); everything handed out is in image coordinates (+0.5).

def na_bilinear(img, xs, ys):
    h, w = img.shape
    xs = np.clip(xs, 0.0, w - 1.001)
    ys = np.clip(ys, 0.0, h - 1.001)
    x0 = np.floor(xs).astype(int)
    y0 = np.floor(ys).astype(int)
    fx = xs - x0
    fy = ys - y0
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
            + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)


def na_tls(P):
    P = np.asarray(P, float)
    m = P.mean(axis=0)
    _, _, vt = np.linalg.svd(P - m, full_matrices=False)
    d = vt[0]
    n = np.array([-d[1], d[0]])
    return n, float(-n @ m), m, d


def na_line_stats(P):
    P = np.asarray(P, float)
    n, c, m, d = na_tls(P)
    r = P @ n + c
    t = (P - m) @ d
    return {'n': n, 'c': c, 'mid': m, 'dir': d, 'rms': float(np.sqrt((r ** 2).mean())),
            'length': float(t.max() - t.min()), 'tmin': float(t.min()), 'tmax': float(t.max()), 'count': len(P)}


def na_snap_segment(gray, rough, sign, w, step, ds=0.25):
    p0 = np.array(rough[0], float) - 0.5                    # image -> index coordinates
    p1 = np.array(rough[-1], float) - 0.5
    L = float(np.linalg.norm(p1 - p0))
    if L < 4:
        raise Na__VisionError('invalid_params', 'A rough line %s is under 4 px long.' % (rough,), 'Click its two ends further apart.')
    d = (p1 - p0) / L
    n = np.array([-d[1], d[0]])
    if (abs(d[0]) >= abs(d[1]) and n[1] < 0) or (abs(d[0]) < abs(d[1]) and n[0] < 0):
        n = -n                                              # +n is down on a near-horizontal line, right on a near-vertical one
    offs = np.arange(-w, w + 1e-9, ds)
    k = np.array([1.0, 2.0, 3.0, 2.0, 1.0])
    k /= k.sum()
    got = []
    for t in np.arange(0.0, L + 1e-9, step):
        c = p0 + d * t
        prof = np.convolve(na_bilinear(gray, c[0] + n[0] * offs, c[1] + n[1] * offs), k, mode='same')
        g = np.gradient(prof, ds)
        g[:4] = 0.0
        g[-4:] = 0.0
        score = g if sign > 0 else (-g if sign < 0 else np.abs(g))
        i = int(np.argmax(score))
        if score[i] <= 0 or i < 1 or i >= len(score) - 1:
            continue
        a, b, cc = score[i - 1], score[i], score[i + 1]
        den = a - 2.0 * b + cc
        sub = 0.5 * (a - cc) / den if abs(den) > 1e-12 else 0.0
        got.append((c + n * (offs[i] + sub * ds) + 0.5, float(b)))
    return got


def na_robust_line(P, floor=0.6):
    """Inliers of an edge's samples. They are tested against a gentle curve (a quadratic across the line's own
    chord), never a straight line: a lens bends a straight edge by a pixel or two, and a straight-line test would
    throw away exactly the samples that show it (the self-test's lens read 40 % low that way)."""
    P = np.asarray(P, float)
    n, _, m, d = na_tls(P)
    tt = (P - m) @ d
    ee = (P - m) @ n
    span = max(float(np.abs(tt).max()), 1.0)
    x = tt / span
    keep = np.ones(len(P), bool)
    for _ in range(6):
        A = np.column_stack([np.ones(keep.sum()), x[keep], x[keep] ** 2])
        coef, *_ = np.linalg.lstsq(A, ee[keep], rcond=None)
        r = np.abs(ee - (coef[0] + coef[1] * x + coef[2] * x ** 2))
        mad = 1.4826 * float(np.median(r[keep]))
        new = r <= max(3.0 * mad, floor)
        if new.sum() < max(3, 0.5 * len(P)) or (new == keep).all():
            break
        keep = new
    return keep


def na_snap(gray, ln):
    segs = ln.get('segments') or [ln['rough']]
    sign = int(ln.get('sign', 0))
    w = float(ln.get('w', 6))
    step = float(ln.get('step', 2))
    got = []
    for sg in segs:
        got += na_snap_segment(gray, sg, sign, w, step)
    if len(got) < 3:
        raise Na__VisionError('invalid_params', 'Line %s: under 3 edge samples were found along it.' % ln['id'],
                              'Check its sign (+1 dark to light going down or right, -1 the reverse, 0 either) and widen w.')
    P = np.array([g[0] for g in got])
    strength = np.array([g[1] for g in got])
    ref = float(np.median(np.sort(strength)[len(strength) // 2:]))     # the line's real edge: its stronger half
    strong = strength >= float(ln.get('min_strength', 0.35)) * ref
    if strong.sum() < 3:
        raise Na__VisionError('invalid_params', 'Line %s: under 3 samples have a clear edge.' % ln['id'], 'Move the rough line onto the edge, or check its sign.')
    keep = np.zeros(len(P), bool)
    idx = np.flatnonzero(strong)
    keep[idx[na_robust_line(P[strong])]] = True
    st = na_line_stats(P[keep])
    r0, r1 = np.array(segs[0][0], float), np.array(segs[-1][-1], float)
    rv = r1 - r0
    if float(np.linalg.norm(rv)) < 4.0:
        best_seg = max(segs, key=lambda sg: float(np.linalg.norm(np.array(sg[-1], float) - np.array(sg[0], float))))
        rv = np.array(best_seg[-1], float) - np.array(best_seg[0], float)
    rv = rv / max(float(np.linalg.norm(rv)), 1e-12)
    drift_deg = math.degrees(math.acos(min(1.0, abs(float(rv @ st['dir'])))))
    if drift_deg > 25.0 and not ln.get('allow_drift'):
        raise Na__VisionError(
            'invalid_params',
            'Line %s snapped %.1f deg off its rough click (likely grabbed a crossing edge).' % (ln['id'], drift_deg),
            'Tighten w, pass sign (+1/-1) or adjust the rough endpoints onto the edge (pass allow_drift: true to bypass).')
    info = {'n_in': int(keep.sum()), 'n_all': len(P), 'weak_dropped': int((~strong).sum()), 'rms_px': round(st['rms'], 3),
            'length_px': round(st['length'], 1), 'angle_deg': round(math.degrees(math.atan2(st['dir'][1], st['dir'][0])), 3),
            'angle_drift_deg': round(drift_deg, 2), 'strength': round(float(strength[keep].mean()), 1)}
    if drift_deg > 8.0:
        info['snap_warning'] = 'drifted %.1f deg from rough click' % drift_deg
    return P[keep], info


def na_lsd(gray8):
    try:
        det = cv2.createLineSegmentDetector(cv2.LSD_REFINE_STD)
        segs = det.detect(gray8)[0]
    except Exception:                                       # noqa: BLE001 - LSD is a check, never a blocker
        return None
    if segs is None:
        return np.zeros((0, 4))
    return segs.reshape(-1, 4).astype(float) + 0.5          # image coordinates


def na_lsd_support(st, segs, near=3.0, max_deg=2.0):
    """How much of OpenCV's detected segments lie on a snapped line: total overlapping length and mean offset."""
    if segs is None or not len(segs):
        return None
    a, b = segs[:, :2], segs[:, 2:]
    dirs = b - a
    lens = np.linalg.norm(dirs, axis=1)
    ok = lens > 3
    cosang = np.abs((dirs[ok] / lens[ok, None]) @ st['dir'])
    ang_ok = cosang >= math.cos(math.radians(max_deg))
    A, B = a[ok][ang_ok], b[ok][ang_ok]
    da, db = A @ st['n'] + st['c'], B @ st['n'] + st['c']
    near_ok = (np.abs(da) <= near) & (np.abs(db) <= near)
    if not near_ok.any():
        return {'length_px': 0.0, 'offset_px': None, 'segments': 0}
    ta, tb = (A[near_ok] - st['mid']) @ st['dir'], (B[near_ok] - st['mid']) @ st['dir']
    lo, hi = np.minimum(ta, tb), np.maximum(ta, tb)
    overlap = np.clip(np.minimum(hi, st['tmax']) - np.maximum(lo, st['tmin']), 0, None)
    total = float(overlap.sum())
    offset = float(((da[near_ok] + db[near_ok]) / 2 * overlap).sum() / total) if total > 0 else None
    return {'length_px': round(total, 1), 'offset_px': None if offset is None else round(offset, 2), 'segments': int((overlap > 0).sum())}

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Lens distortion (plumb-line, division model)
# -----------------------------------------------------------------------------
# undistorted = c + (distorted - c) / (1 + lambda r^2), r = |distorted - c| / s,
# s = half the photo's diagonal. Barrel distortion (wide lenses) is lambda < 0.

def na_undistort_pts(P, lam, c, s):
    P = np.asarray(P, float)
    if lam == 0:
        return P.copy()
    d = (P - c) / s
    r2 = (d * d).sum(axis=1)
    return c + (P - c) / (1.0 + lam * r2)[:, None]


def na_to_camera(P, lam, shift, c, s):
    """The photo's own pixels into the camera frame: the lens taken out about the centre of view (the photo's middle
    less the principal point's shift), then the shift added, so the camera's principal point is the photo's middle."""
    sh = np.asarray(shift, float)
    return na_undistort_pts(P, lam, np.asarray(c, float) - sh, s) + sh


def na_distort_pts(P, lam, c, s):
    P = np.asarray(P, float)
    if lam == 0:
        return P.copy()
    du = (P - c) / s
    ru = np.linalg.norm(du, axis=1)
    disc = np.clip(1.0 - 4.0 * lam * ru ** 2, 0.0, None)
    with np.errstate(divide='ignore', invalid='ignore'):
        rd = np.where(ru > 1e-12, (1.0 - np.sqrt(disc)) / (2.0 * lam * np.where(ru > 1e-12, ru, 1.0)), 0.0)
        scale = np.where(ru > 1e-12, rd / np.where(ru > 1e-12, ru, 1.0), 1.0)
    return c + (P - c) * scale[:, None]


def na_straightness_rms(line_pts, lam, c, s):
    """Mean RMS straightness across usable lines at division-model lambda, or None under three usable lines."""
    usable = [P for P in line_pts if len(P) >= 5 and na_line_stats(P)['length'] >= 0.04 * s]
    if len(usable) < 3:
        return None
    count = sum(len(P) for P in usable)
    total = 0.0
    for P in usable:
        U = na_undistort_pts(P, lam, c, s)
        n, cc, _, _ = na_tls(U)
        total += float(((U @ n + cc) ** 2).sum())
    return math.sqrt(total / count)


def na_estimate_lambda(line_pts, c, s):
    """The division-model lambda that makes the straight lines straightest, with its uncertainty, and whether it
    is clear enough to take out (it must straighten them by a quarter in rms and stand three sigma off zero)."""
    from scipy.optimize import minimize_scalar
    usable = [P for P in line_pts if len(P) >= 5 and na_line_stats(P)['length'] >= 0.04 * s]
    if len(usable) < 3:
        return {'lambda': 0.0, 'applied': False, 'why': 'under three lines long enough to show the lens'}
    count = sum(len(P) for P in usable)

    def cost(lam):
        total = 0.0
        for P in usable:
            U = na_undistort_pts(P, lam, c, s)
            n, cc, _, _ = na_tls(U)
            total += float(((U @ n + cc) ** 2).sum())
        return total / count

    res = minimize_scalar(cost, bounds=(-0.35, 0.25), method='bounded', options={'xatol': 1e-6})
    lam, best, base = float(res.x), float(res.fun), cost(0.0)
    h = 1e-3
    curv = (cost(lam + h) - 2 * best + cost(lam - h)) / h ** 2
    dof = max(count - 2 * len(usable) - 1, 1)
    sigma = math.sqrt(max(2.0 * best * count / dof / max(curv * count, 1e-18), 0.0)) if curv > 0 else float('inf')
    gain = math.sqrt(base / best) if best > 0 else 1.0
    applied = gain >= 1.25 and abs(lam) >= 3.0 * sigma and abs(lam) >= 0.005
    why = ('taken out: it straightens the lines %.0f %% in rms' % (100 * (1 - 1 / gain)) if applied else
           'left in: %s' % ('it barely straightens the lines (%.0f %%)' % (100 * (1 - 1 / gain)) if gain < 1.25 else
                            'it is within three sigma of zero'))
    return {'lambda': round(lam, 5) if applied else 0.0, 'lambda_fitted': round(lam, 5), 'sigma': round(sigma, 5) if math.isfinite(sigma) else None,
            'straightness_rms_px': {'before': round(math.sqrt(base), 3), 'after': round(math.sqrt(best), 3)},
            'applied': applied, 'why': why, 'lines_used': len(usable)}


def na_undistort_image(img, lam, c, s):
    if lam == 0:
        return img
    h, w = img.shape[:2]
    xs, ys = np.meshgrid(np.arange(w, dtype=np.float32) + 0.5, np.arange(h, dtype=np.float32) + 0.5)
    du = (xs - c[0]) / s
    dv = (ys - c[1]) / s
    ru = np.sqrt(du * du + dv * dv)
    disc = np.clip(1.0 - 4.0 * lam * ru * ru, 0.0, None)
    safe = np.where(ru > 1e-9, ru, 1.0)
    scale = np.where(ru > 1e-9, (1.0 - np.sqrt(disc)) / (2.0 * lam * safe) / safe, 1.0).astype(np.float32)
    mapx = (c[0] + (xs - c[0]) * scale - 0.5).astype(np.float32)
    mapy = (c[1] + (ys - c[1]) * scale - 0.5).astype(np.float32)
    return cv2.remap(img, mapx, mapy, cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT, borderValue=(255, 255, 255))

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Vanishing points: Adam's Match Photo by numbers
# -----------------------------------------------------------------------------

def na_vanishing_point(stats, W, H):
    s, cx, cy = max(W, H) / 2.0, W / 2.0, H / 2.0
    rows = []
    for st in stats:
        n, c = st['n'], st['c']
        a = np.array([s * n[0], s * n[1], n[0] * cx + n[1] * cy + c])
        a /= np.linalg.norm(a[:2])
        rows.append(a * math.sqrt(max(st['length'], 1.0)))
    _, _, vt = np.linalg.svd(np.array(rows))
    v = vt[-1]
    vh = np.array([s * v[0] + cx * v[2], s * v[1] + cy * v[2], v[2]])
    miss = []
    for st in stats:
        to = vh[:2] / vh[2] - st['mid'] if abs(vh[2]) > 1e-12 else vh[:2]
        to = to / (np.linalg.norm(to) + 1e-18)
        miss.append(round(math.degrees(math.asin(max(-1.0, min(1.0, float(st['dir'][0] * to[1] - st['dir'][1] * to[0]))))), 3))
    return vh, miss


def na_finite(vh):
    return abs(vh[2]) > 1e-9 * max(1.0, float(np.linalg.norm(vh[:2])))


def na_intersect(sa, sb):
    A = np.array([sa['n'], sb['n']])
    if abs(np.linalg.det(A)) < 1e-12:
        raise Na__VisionError('invalid_params', 'Two lines named to cross are parallel in the photo.', 'Name a red or green line and a blue one.')
    return np.linalg.solve(A, -np.array([sa['c'], sb['c']]))


def na_vp_camera(lines, origin, scale, W, H):
    fam = {a: [ln for ln in lines if ln['axis'] == a] for a in 'xyz'}
    if len(fam['x']) < 2 or len(fam['y']) < 2:
        raise Na__VisionError('invalid_params', 'Match Photo needs two or more red (x) lines and two or more green (y) lines.',
                              'Give each face at least two long, far-apart lines, as you would drag the axis bars.')
    stats = {ln['id']: na_line_stats(ln['u']) for ln in lines}
    vps, misses = {}, {}
    for a in 'xyz':
        if len(fam[a]) >= 2:
            vps[a], misses[a] = na_vanishing_point([stats[ln['id']] for ln in fam[a]], W, H)
    if not (na_finite(vps['x']) and na_finite(vps['y'])):
        raise Na__VisionError('invalid_params', 'The red or green lines are parallel in the photo: that face is seen square-on, so its vanishing '
                              'point is at infinity and Match Photo cannot find the focal length from it.',
                              'Use pe_camera_fit fitlines (world-known lines only), or a photo taken at an angle to both faces.')
    vx, vy = vps['x'][:2] / vps['x'][2], vps['y'][:2] / vps['y'][2]
    pp = np.array([W / 2.0, H / 2.0])
    f2 = -float((vx - pp) @ (vy - pp))
    if f2 <= 0:
        raise Na__VisionError('invalid_params', 'The red and green vanishing points lie on the same side of the photo\'s centre: a line is on the '
                              'wrong axis, or two faces are not square to each other.',
                              'Check every red line runs along x and every green one along y (line_miss_deg names the worst).')
    f = math.sqrt(f2)
    pairs = {'xy': round(f, 1)}
    pp_orth = None
    if 'z' in vps and na_finite(vps['z']):
        vz = vps['z'][:2] / vps['z'][2]
        for name, va in (('xz', vx), ('yz', vy)):
            g2 = -float((va - pp) @ (vz - pp))
            pairs[name] = round(math.sqrt(g2), 1) if g2 > 0 else None
        try:
            A = np.array([vy - vz, vz - vx])
            pp_orth = np.linalg.solve(A, np.array([vx @ (vy - vz), vy @ (vz - vx)]))
        except np.linalg.LinAlgError:
            pp_orth = None
    dirs = {}
    for a in vps:
        dv = kinv(f, pp) @ vps[a]
        if dv[2] < 0:
            dv = -dv
        dirs[a] = dv / np.linalg.norm(dv)
    o_px = na_intersect(stats[origin['lines'][0]], stats[origin['lines'][1]])
    s_px = na_intersect(stats[scale['lines'][0]], stats[scale['lines'][1]])
    O, S = np.array(origin['world'], float), np.array(scale['world'], float)
    best = None
    for sx in (1.0, -1.0):
        for sy in (1.0, -1.0):
            rx, ry = sx * dirs['x'], sy * dirs['y']
            rz = np.cross(rx, ry)
            if rz[1] >= 0:                                  # +z points up the photo (camera y is down)
                continue
            U, _, Vt = np.linalg.svd(np.column_stack([rx, ry, rz]))
            R = U @ Vt
            if np.linalg.det(R) < 0:
                continue
            a = R.T @ (kinv(f, pp) @ np.array([o_px[0], o_px[1], 1.0]))
            b = R.T @ (kinv(f, pp) @ np.array([s_px[0], s_px[1], 1.0]))
            a /= np.linalg.norm(a)
            b /= np.linalg.norm(b)
            sol, *_ = np.linalg.lstsq(np.column_stack([-a, b]), S - O, rcond=None)
            k, t = float(sol[0]), float(sol[1])
            if k <= 0 or t <= 0:
                continue
            miss = float(np.linalg.norm(O - k * a + t * b - S))
            if best is None or miss < best[0]:
                best = (miss, R, O - k * a)
    if best is None:
        raise Na__VisionError('invalid_params', 'No orientation puts the origin and the scale point in front of the camera.',
                              'Check the origin and scale lines cross where their world points are, and the world points themselves.')
    miss, R, C = best
    p = np.concatenate([from_R(R), C, [f]])
    report = {'vp_px': {a: ([round(float(v), 1) for v in vps[a][:2] / vps[a][2]] if na_finite(vps[a]) else 'infinity') for a in vps},
              'line_miss_deg': {a: dict(zip([ln['id'] for ln in fam[a]], misses[a])) for a in misses},
              'focal_px_by_pair': pairs, 'f_px': round(f, 1), 'orthocentre_px': None if pp_orth is None else [round(float(v), 1) for v in pp_orth],
              'origin_px': [round(float(v), 2) for v in o_px], 'scale_px': [round(float(v), 2) for v in s_px],
              'scale_ray_miss_mm': round(miss, 1)}
    return p, report, dirs

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Refine: every line, robustly (the kit's fitlines, vectorised)
# -----------------------------------------------------------------------------

def na_constraints(lines, points, p_vp, W, H, depth):
    """Lines as constraints, on the photo's own (distorted) pixels 'd': the refine takes the lens out with its own
    lambda. A world-known line keeps its anchor (and its free axes); a direction-only line is anchored on the VP
    camera's ray through its middle, at the origin's depth, with both other axes free."""
    out = []
    for ln in lines:
        D = np.array(NA_AXES[ln['axis']])
        if ln.get('through') is not None:
            A = np.array(ln['through'], float)
            free = ln.get('free') or ''
        else:
            mid = na_line_stats(ln['u'])['mid']
            A = np.asarray(p_vp[3:6], float) + ray_world(p_vp, mid, W, H) * depth
            free = NA_OTHER[ln['axis']]
        out.append({'id': ln['id'], 'source': ln.get('source', 'photo'), 'kind': 'line', 'A': A, 'D': D, 'free': free,
                    'd': np.asarray(ln['d'], float), '_world_known': ln.get('through') is not None,
                    'range': ln.get('range') if isinstance(ln.get('range'), dict) else {}})
    for pt in points:
        out.append({'id': pt['id'], 'source': pt.get('source', 'cad'), 'kind': 'point', 'X': np.array(pt['world'], float),
                    'd': np.asarray(pt['d'], float).reshape(1, 2), '_world_known': True})
    return out


def na_refine(cons, W, H, f_prior, prior, start, robust, drop=(), max_nfev=None, start_q=None, lens=None):
    """One least-squares fit of the camera (and the free anchors, and the lens's lambda when lens['free']) to the
    constraints. Residuals are pixels: across each line, or both ways at a point, on the undistorted photo."""
    from scipy.optimize import least_squares
    use = [c for c in cons if c['id'] not in drop]
    free = [(i, 'xyz'.index(ax)) for i, c in enumerate(use) if c['kind'] == 'line' for ax in c['free']]
    lens = dict({'lam0': 0.0, 'free': False, 'c': np.array([W / 2.0, H / 2.0]), 's': math.hypot(W, H) / 2.0,
                 'pp_free': False, 'shift0': [0.0, 0.0]}, **(lens or {}))
    shift0 = [float(v) for v in lens.get('shift0', [0.0, 0.0])]
    q0 = (list(np.asarray(start, float)[:7]) + [use[i]['A'][ax] for i, ax in free] + ([float(lens['lam0'])] if lens['free'] else [])
          + (shift0 if lens['pp_free'] else []))
    q0 = np.array(q0, float)
    if start_q is not None and len(start_q) == len(q0):
        q0 = np.asarray(start_q, float).copy()               # a refit starts from the solved anchors and lens too
    lo = np.full(len(q0), -np.inf)
    hi = np.full(len(q0), np.inf)
    for k, (i, ax) in enumerate(free):                       # an allowed range, e.g. a fascia 0 to 600 in front of its wall
        span = (use[i].get('range') or {}).get('xyz'[ax])
        if isinstance(span, (list, tuple)) and len(span) == 2:
            lo[7 + k], hi[7 + k] = float(min(span)), float(max(span))
    scale = max(1.0, 8.0 * math.hypot(W, H) / NA_DIAG_12MP)
    nk = len(free)
    i_lam = 7 + nk
    i_pp = i_lam + (1 if lens['free'] else 0)
    if lens['free']:
        lo[i_lam], hi[i_lam] = -0.35, 0.25                   # physical lens distortion bounds (matches plumb-line)
    if np.isfinite(lo).any() or np.isfinite(hi).any():
        q0 = np.clip(q0, np.where(np.isfinite(lo), lo + 1e-6, lo), np.where(np.isfinite(hi), hi - 1e-6, hi))

    def unpack(q):
        anchors = [c['A'].copy() if c['kind'] == 'line' else None for c in use]
        for k, (i, ax) in enumerate(free):
            anchors[i][ax] = q[7 + k]
        lam = float(q[i_lam]) if lens['free'] else float(lens['lam0'])
        shift = np.array(q[i_pp:i_pp + 2], float) if lens['pp_free'] else np.array(shift0, float)
        return q[:7], anchors, lam, shift

    def per(q):
        P, anchors, lam, shift = unpack(q)
        R, C, f = rod(P[:3]), P[3:6], P[6]
        res = []
        for c, A in zip(use, anchors):
            obs = na_to_camera(c['d'], lam, shift, lens['c'], lens['s'])
            if c['kind'] == 'line':
                ends = np.array([A - 1500.0 * c['D'], A + 1500.0 * c['D']])
                Xc = (ends - C) @ R.T
                if (Xc[:, 2] <= 1e-6).any():
                    res.append(np.full(len(obs), 1e3))
                    continue
                uv = np.column_stack([f * Xc[:, 0] / Xc[:, 2] + W / 2.0, f * Xc[:, 1] / Xc[:, 2] + H / 2.0])
                tv = uv[1] - uv[0]
                n = np.array([-tv[1], tv[0]]) / (np.linalg.norm(tv) + 1e-12)
                res.append((obs - uv[0]) @ n)
            else:
                Xc = (c['X'] - C) @ R.T
                if Xc[2] <= 1e-6:
                    res.append(np.array([1e3, 1e3]))
                    continue
                res.append(np.array([f * Xc[0] / Xc[2] + W / 2.0, f * Xc[1] / Xc[2] + H / 2.0]) - obs[0])
        return res, P, lam, shift

    def resid(q):
        res, P, lam, shift = per(q)
        extra = [(P[6] - f_prior) / (prior * f_prior)]
        if lens['free']:
            extra.append(lam / 0.25)                         # a weak pull to no distortion
        if lens['pp_free']:
            extra += [shift[0] / (0.15 * W), shift[1] / (0.15 * H)]    # and to the photo's centre
        return np.concatenate(res + [np.array(extra)])

    kw = {'loss': 'soft_l1', 'f_scale': scale} if robust else {}
    sol = least_squares(resid, q0, x_scale='jac', max_nfev=max_nfev, bounds=(lo, hi), **kw)
    res, P, lam, shift = per(sol.x)
    _, anchors, _, _ = unpack(sol.x)
    rows = []
    for c, r in zip(use, res):
        rms = float(np.sqrt(np.mean(np.square(r)))) if c['kind'] == 'line' else float(np.hypot(*r))
        rows.append({'id': c['id'], 'source': c['source'], 'kind': c['kind'], 'rms_px': round(rms, 3),
                     'samples': int(len(r) if c['kind'] == 'line' else 1)})
    allr = np.concatenate([np.ravel(r) for r in res]) if res else np.zeros(1)
    lam_sd, shift_sd = None, None
    if (lens['free'] or lens['pp_free']) and not robust:
        try:
            J = sol.jac
            dof = max(len(sol.fun) - len(sol.x), 1)
            cov = np.linalg.pinv(J.T @ J) * float((sol.fun ** 2).sum()) / dof
            if lens['free']:
                lam_sd = float(math.sqrt(max(cov[i_lam, i_lam], 0.0)))
            if lens['pp_free']:
                shift_sd = [float(math.sqrt(max(cov[i_pp + k, i_pp + k], 0.0))) for k in range(2)]
        except Exception:                                    # noqa: BLE001 - no spread is reported then
            lam_sd, shift_sd = None, None
    solved = {}
    for i, ax in free:
        if use[i].get('_world_known'):
            solved['%s %s' % (use[i]['id'], 'xyz'[ax])] = round(float(anchors[i][ax]), 1)
    return {'p': P, 'q': sol.x, 'lam': lam, 'lam_sd': lam_sd, 'shift': [float(v) for v in shift], 'shift_sd': shift_sd, 'rows': rows,
            'rms': float(np.sqrt(np.mean(allr ** 2))), 'solved_free': solved, 'use': use}


def na_fit_all(cons, W, H, f_prior, prior, start, lens=None):
    """fitlines' recipe: a robust (soft L1) fit finds the camera most constraints agree on; every constraint far off
    it is named as an outlier, dropped, and the camera refitted without it."""
    first = na_refine(cons, W, H, f_prior, prior, start, robust=True, lens=lens)
    med = float(np.median([r['rms_px'] for r in first['rows']]))
    gate = max(12.0 * math.hypot(W, H) / NA_DIAG_12MP, 3.0 * med, 1.0)
    outliers = [r for r in first['rows'] if r['rms_px'] > gate]
    lens2 = dict(lens, lam0=first['lam'], shift0=first['shift']) if lens else None
    final = na_refine(cons, W, H, f_prior, prior, first['p'], robust=False, drop=tuple(r['id'] for r in outliers), lens=lens2)
    final['outliers'] = [dict(r, dropped=True, gate_px=round(gate, 2)) for r in outliers]
    final['gate_px'] = round(gate, 2)
    return final

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Readings: checks, measures, derived, and their plus or minus
# -----------------------------------------------------------------------------

def na_reading_px(spec, stats):
    if spec.get('lines'):
        a, b = spec['lines']
        if a not in stats or b not in stats:
            raise Na__VisionError('invalid_params', '%s names line %s, which is not given.' % (spec.get('id'), a if a not in stats else b), None)
        return na_intersect(stats[a], stats[b])
    if spec.get('px') is not None:
        return np.array(spec['px'], float)
    raise Na__VisionError('invalid_params', 'Reading %s needs px [u, v] or lines [id, id] (where two lines cross).' % spec.get('id'), None)


def na_readings(p, specs, stats, W, H, lam, c, s, pick=None, rng=None, shift=(0.0, 0.0)):
    out = {}
    for spec in specs:
        px = na_reading_px(spec, stats)
        if spec.get('px') is not None and not spec.get('lines'):
            px = na_to_camera([px], lam, shift, c, s)[0]     # a hand-read pixel on the original photo
            if pick and rng is not None:
                px = px + rng.normal(0.0, pick, 2)
        X = backproject(p, px, parse_plane(spec['plane']), W, H)
        out[spec['id']] = (X, px)
    return out


def na_jitter_lines(lines, rng, floor=0.3):
    """Each line moved as a whole on the photo: an offset across it and a turn about its middle, by its own
    scatter (an edge's position is uncertain as a line, not sample by sample)."""
    out = []
    for ln in lines:
        st = na_line_stats(ln['d'])
        n = max(st['count'], 2)
        sig_o = max(st['rms'] / math.sqrt(n), floor)
        sig_t = math.sqrt(12.0) * max(st['rms'], floor) / (max(st['length'], 1.0) * math.sqrt(n))
        o, th = rng.normal(0.0, sig_o), rng.normal(0.0, sig_t)
        along = (ln['d'] - st['mid']) @ st['dir']
        out.append(dict(ln, d=ln['d'] + np.outer(o + along * th, st['n'])))
    return out


def na_monte_carlo(lines, points, cons_builder, fit, W, H, f_prior, prior, specs, lens, opts):
    refits = int(opts.get('refits', 60))
    budget = float(opts.get('max_seconds', 30))
    pick = float(opts.get('pick_sigma_px', 0.7))
    rng = np.random.default_rng(int(opts.get('seed', 1)))
    drop = tuple(r['id'] for r in fit.get('outliers', []))
    t0 = time.time()
    samples = []
    for _ in range(refits):
        if time.time() - t0 > budget:
            break
        jl = na_jitter_lines(lines, rng)
        jp = [dict(pt, d=np.asarray(pt['d'], float) + rng.normal(0.0, pick, 2)) for pt in points]
        try:
            r = na_refine(cons_builder(jl, jp), W, H, f_prior, prior, fit['p'], robust=False, drop=drop, max_nfev=200,
                          start_q=fit['q'], lens=dict(lens, lam0=fit['lam'], shift0=fit['shift']))
        except Exception:                                    # noqa: BLE001 - a failed refit is skipped
            continue
        for ln in jl:
            ln['u'] = na_to_camera(ln['d'], r['lam'], r['shift'], lens['c'], lens['s'])
        stats = {ln['id']: na_line_stats(ln['u']) for ln in jl}
        read = na_readings(r['p'], specs, stats, W, H, r['lam'], lens['c'], lens['s'], pick, rng, r['shift'])
        samples.append({'p': r['p'], 'lam': r['lam'], 'read': {k: v[0] for k, v in read.items()}})
    return samples, round(time.time() - t0, 1)


def na_summary(values):
    a = np.array([v for v in values if v is not None and np.all(np.isfinite(v))], float)
    if len(a) < 3:
        return None
    return {'sd': round(float(a.std(ddof=1)), 1), 'p2_5': round(float(np.percentile(a, 2.5)), 1),
            'p97_5': round(float(np.percentile(a, 97.5)), 1), 'n': int(len(a))}


def na_derived_value(spec, read):
    a, b = read.get(spec['a']), read.get(spec['b'])
    if a is None or b is None:
        return None
    if spec.get('axis', 'distance') == 'distance':
        return float(np.linalg.norm(b - a))
    return float(b['xyz'.index(spec['axis'])] - a['xyz'.index(spec['axis'])])

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | The photo for the scene: the agent's lines, dotted
# -----------------------------------------------------------------------------

def na_clip_line(a, d, W, H):
    """The infinite line a + t d clipped to the photo's rectangle, or None."""
    ts = []
    for k, lim in ((0, 0.0), (0, float(W)), (1, 0.0), (1, float(H))):
        if abs(d[k]) > 1e-12:
            t = (lim - a[k]) / d[k]
            q = a + t * d
            if -1e-6 <= q[0] <= W + 1e-6 and -1e-6 <= q[1] <= H + 1e-6:
                ts.append(t)
    if len(ts) < 2:
        return None
    return a + min(ts) * d, a + max(ts) * d


def na_dashed(img, p0, p1, colour, thick, dash, gap):
    v = p1 - p0
    L = float(np.linalg.norm(v))
    if L < 1:
        return
    u = v / L
    t = 0.0
    while t < L:
        a = p0 + u * t
        b = p0 + u * min(t + dash, L)
        cv2.line(img, (int(round(a[0] * 16 - 8)), int(round(a[1] * 16 - 8))), (int(round(b[0] * 16 - 8)), int(round(b[1] * 16 - 8))),
                 colour, thick, cv2.LINE_AA, shift=4)
        t += dash + gap


def na_text(img, text, at, scale, colour):
    x, y = int(round(at[0])), int(round(at[1]))
    th = max(1, int(round(scale * 2)))
    cv2.putText(img, text, (x, y), cv2.FONT_HERSHEY_SIMPLEX, scale, (0, 0, 0), th + 2, cv2.LINE_AA)
    cv2.putText(img, text, (x, y), cv2.FONT_HERSHEY_SIMPLEX, scale, colour, th, cv2.LINE_AA)


def na_overlay(img, lines, stats, report, o_px, s_px, opts, legend):
    """The agent's interpretation drawn on the photo: each fitted line dotted across the whole frame (towards its
    vanishing point), solid over the stretch it was measured on, labelled; the origin, the scale point, the
    horizon; a legend. Transparent, so the photo stays readable under it."""
    H, W = img.shape[:2]
    diag = math.hypot(W, H)
    alpha = float(opts.get('opacity', 0.6))
    thick = max(1, int(round(diag / 1100.0)))
    dash = max(5.0, diag / 230.0)
    layer = img.copy()
    for ln in lines:
        st = stats[ln['id']]
        col = NA_AXIS_BGR[ln['axis']]
        clipped = na_clip_line(st['mid'], st['dir'], W, H)
        if clipped and opts.get('extend', True):
            na_dashed(layer, clipped[0], clipped[1], col, thick, dash, dash * 0.8)
        a = st['mid'] + st['dir'] * st['tmin']
        b = st['mid'] + st['dir'] * st['tmax']
        cv2.line(layer, (int(round(a[0] * 16 - 8)), int(round(a[1] * 16 - 8))), (int(round(b[0] * 16 - 8)), int(round(b[1] * 16 - 8))),
                 col, thick + 1, cv2.LINE_AA, shift=4)
    if opts.get('horizon', True):
        final = report.get('vp_px_final') or report['vp_px']
        vx, vy = final.get('x'), final.get('y')
        if isinstance(vx, list) and isinstance(vy, list):
            a, b = np.array(vx, float), np.array(vy, float)
            clipped = na_clip_line(a, (b - a) / (np.linalg.norm(b - a) + 1e-12), W, H)
            if clipped:
                na_dashed(layer, clipped[0], clipped[1], (255, 255, 255), thick, dash * 0.5, dash * 0.9)
    blended = cv2.addWeighted(layer, alpha, img, 1.0 - alpha, 0)
    scale = max(0.4, diag / 2600.0)
    if opts.get('labels', True):
        for ln in lines:
            st = stats[ln['id']]
            end = st['mid'] + st['dir'] * st['tmax']
            na_text(blended, ln['id'], end + np.array([4.0, -4.0]), scale, NA_AXIS_BGR[ln['axis']])
    r = max(4, int(round(diag / 250.0)))
    for px, label in ((o_px, 'O'), (s_px, 'S')):
        if px is not None:
            centre = (int(round(px[0])), int(round(px[1])))
            cv2.circle(blended, centre, r, (0, 0, 0), thick + 2, cv2.LINE_AA)
            cv2.circle(blended, centre, r, (0, 255, 255), thick, cv2.LINE_AA)
            na_text(blended, label, (px[0] + r + 2, px[1] - r - 2), scale * 1.1, (0, 255, 255))
    if opts.get('legend', True) and legend:
        pad = int(round(10 * scale / 0.45))
        lh = int(round(22 * scale / 0.45))
        room = W - 4 * pad
        wrapped = []
        for text in legend:                                  # wrap at ' | ' (then spaces) to fit the photo's width
            line = ''
            for part in text.replace(' | ', ' |\n').split('\n'):
                for word in part.split(' '):
                    trial = (line + ' ' + word).strip() if line else word
                    if line and cv2.getTextSize(trial, cv2.FONT_HERSHEY_SIMPLEX, scale, 1)[0][0] > room:
                        wrapped.append(line)
                        line = word
                    else:
                        line = trial
            if line:
                wrapped.append(line)
        legend = wrapped
        width = int(min(W - 2 * pad, max(cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, scale, 1)[0][0] for t in legend) + 2 * pad))
        top = H - pad - lh * len(legend) - pad
        box = blended.copy()
        cv2.rectangle(box, (pad, top), (pad + width, H - pad), (20, 20, 20), -1)
        blended = cv2.addWeighted(box, 0.6, blended, 0.4, 0)
        for i, text in enumerate(legend):
            na_text(blended, text, (2 * pad, top + pad + lh * (i + 1) - lh // 4), scale, (235, 235, 235))
    return blended

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Suggested lines (OpenCV's detector, classified by vanishing point)
# -----------------------------------------------------------------------------

def na_suggest(segs, report, stats, lam, c, s, W, H, opts, shift=(0.0, 0.0)):
    if segs is None or not len(segs):
        return {}
    min_len = float(opts.get('min_length_px', 0.04 * math.hypot(W, H)))
    max_deg = float(opts.get('max_angle_deg', 0.6))
    per_axis = int(opts.get('max_per_axis', 8))
    A = na_to_camera(segs[:, :2], lam, shift, c, s)
    B = na_to_camera(segs[:, 2:], lam, shift, c, s)
    lens = np.linalg.norm(B - A, axis=1)
    out = {a: [] for a in 'xyz'}
    for i in np.argsort(-lens):
        if lens[i] < min_len:
            break
        mid, d = (A[i] + B[i]) / 2, (B[i] - A[i]) / lens[i]
        if any(abs((mid - st['mid']) @ st['n']) < 4 and abs(float(d @ st['dir'])) > 0.999 for st in stats.values()):
            continue
        best = None
        for a in 'xyz':
            vp = report['vp_px'].get(a)
            if vp is None:
                continue
            to = (np.array(vp, float) - mid) if isinstance(vp, list) else None
            if to is None:
                continue
            ang = math.degrees(math.acos(min(1.0, abs(float(d @ (to / (np.linalg.norm(to) + 1e-12)))))))
            if ang <= max_deg and (best is None or ang < best[1]):
                best = (a, ang)
        if best and len(out[best[0]]) < per_axis:
            out[best[0]].append({'rough': [[round(float(v), 1) for v in segs[i, :2]], [round(float(v), 1) for v in segs[i, 2:]]],
                                 'length_px': round(float(lens[i]), 1), 'angle_to_vp_deg': round(best[1], 3)})
    return {a: v for a, v in out.items() if v}

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | The job
# -----------------------------------------------------------------------------

def na_unique(path):
    if not os.path.exists(path):
        return path
    stem, ext = os.path.splitext(path)
    k = 2
    while os.path.exists('%s__%d%s' % (stem, k, ext)):
        k += 1
    return '%s__%d%s' % (stem, k, ext)


def na_write_image(path, img, quality=95):
    ext = os.path.splitext(path)[1].lower()
    params = [cv2.IMWRITE_JPEG_QUALITY, int(quality)] if ext in ('.jpg', '.jpeg') else []
    ok, buf = cv2.imencode(ext, img, params)
    if not ok:
        raise Na__VisionError('file_error', 'OpenCV could not encode %s.' % path, None)
    buf.tofile(path)


def na_round(v, nd=1):
    return [round(float(x), nd) for x in v]


def Na__VisionWorker__Run(job):
    deps = na_import()
    t_start = time.time()
    photo = job['photo']
    raw, orientation, f35 = na_read_upright(photo)
    H, W = raw.shape[:2]
    c = np.array([W / 2.0, H / 2.0])
    s = math.hypot(W, H) / 2.0
    enh_opts = job.get('enhance') if isinstance(job.get('enhance'), dict) else ({} if job.get('enhance', True) else None)
    if enh_opts is None:
        enhanced, steps, measured = raw.copy(), ['none'], raw
    else:
        enhanced, steps, measured = na_enhance(raw, enh_opts)
    gray = cv2.cvtColor(measured, cv2.COLOR_BGR2GRAY).astype(np.float32)

    lines, snaps = [], {}
    for ln in job['lines']:
        if not ln.get('id') or ln.get('axis') not in NA_AXES:
            raise Na__VisionError('invalid_params', 'Every line needs an id and an axis (x red, y green, z blue).', None)
        if ln.get('px'):
            P = np.array(ln['px'], float)
            info = {'given_px': True, 'n_in': len(P)}
        elif ln.get('rough') or ln.get('segments'):
            P, info = na_snap(gray, ln)
        else:
            raise Na__VisionError('invalid_params', 'Line %s needs rough (two clicks), segments or px.' % ln['id'], None)
        snaps[ln['id']] = info
        lines.append(dict(ln, d=P))
    ids = [ln['id'] for ln in lines]
    if len(set(ids)) != len(ids):
        raise Na__VisionError('invalid_params', 'Two lines share an id.', 'Give every line its own id (R1, R2, G1, B1 ...).')

    dist_spec = job.get('distortion', 'auto')
    plumb = na_estimate_lambda([ln['d'] for ln in lines], c, s)
    if isinstance(dist_spec, (int, float)) and not isinstance(dist_spec, bool):
        mode, lam_seed = 'given', float(dist_spec)
    elif dist_spec == 'none':
        mode, lam_seed = 'none', 0.0
    else:
        mode, lam_seed = 'auto', float(plumb.get('lambda_fitted', 0.0) or 0.0)
    for ln in lines:
        ln['u'] = na_undistort_pts(ln['d'], lam_seed, c, s)

    segs = na_lsd(cv2.cvtColor(enhanced, cv2.COLOR_BGR2GRAY))
    stats_d = {ln['id']: na_line_stats(ln['d']) for ln in lines}
    for ln in lines:
        snaps[ln['id']]['detector'] = na_lsd_support(stats_d[ln['id']], segs)

    points = []
    for i, pt in enumerate(job.get('points') or []):
        points.append({'id': pt.get('id') or 'P%d' % (i + 1), 'source': pt.get('source', 'cad'), 'world': pt['world'],
                       'd': np.array(pt['px'], float)})

    origin, scale = job['origin'], job['scale']
    for key, spec in (('origin', origin), ('scale', scale)):
        for lid in spec.get('lines', []):
            if lid not in stats_d:
                raise Na__VisionError('invalid_params', '%s names line %s, which is not given.' % (key, lid), None)
    p_vp, report, dirs = na_vp_camera(lines, origin, scale, W, H)
    depth = float(np.linalg.norm(np.array(origin['world'], float) - p_vp[3:6]))

    f_prior = f35 * math.hypot(W, H) / 43.27 if (job.get('f_equiv_mm') is None and f35) else (
        float(job['f_equiv_mm']) * math.hypot(W, H) / 43.27 if job.get('f_equiv_mm') else float(p_vp[6]))
    prior = float(job.get('focal_prior', 0.05 if (job.get('f_equiv_mm') or f35) else 1.0))

    def builder(ls, ps):
        return na_constraints(ls, ps, p_vp, W, H, depth)

    pp_mode = job.get('principal_point', 'centre')
    if pp_mode not in ('centre', 'solve'):
        raise Na__VisionError('invalid_params', 'principal_point is "centre" or "solve".', None)
    lensspec = {'c': c, 's': s, 'lam0': lam_seed, 'free': mode == 'auto', 'pp_free': pp_mode == 'solve', 'shift0': [0.0, 0.0]}
    cons = builder(lines, points)
    fit = na_fit_all(cons, W, H, f_prior, prior, p_vp, lens=lensspec)
    lens = dict(plumb, mode=mode)
    diag = math.hypot(W, H)
    dropped_terms = []
    raw_line_pts = [ln['d'] for ln in lines]
    straight_zero = na_straightness_rms(raw_line_pts, 0.0, c, s)
    for _ in range(3):                                       # backward elimination: keep only what stands at 3 sigma
        weak = []
        if lensspec['free']:
            sd = fit['lam_sd']
            z = abs(fit['lam']) / sd if sd else 0.0
            straight_lam = na_straightness_rms(raw_line_pts, fit['lam'], c - np.array(fit['shift'], float), s)
            if not (sd is not None and abs(fit['lam']) >= max(3.0 * sd, 0.005)):
                weak.append(('lens', z, 'lambda %.4f +- %s' % (fit['lam'], 'n/a' if sd is None else '%.4f' % sd)))
            elif straight_zero is not None and straight_lam is not None and straight_lam > 1.15 * straight_zero:
                weak.append(('lens', -1.0, 'lambda %.4f bends straight lines (rms %.2f -> %.2f px)' % (fit['lam'], straight_zero, straight_lam)))
            elif abs(fit['lam']) > 0.15 and not (straight_zero is not None and straight_lam is not None and straight_lam <= 0.95 * straight_zero):
                weak.append(('lens', -1.0, 'lambda %.4f over 0.15 without straightening lines (likely an off-axis line on a rectilinear photo)' % fit['lam']))
        if lensspec['pp_free']:
            sd = fit['shift_sd']
            size = float(np.linalg.norm(fit['shift']))
            z = size / max(sd) if sd else 0.0
            if not (sd is not None and size >= max(3.0 * max(sd), 0.01 * diag)):
                weak.append(('centre of view', z, '%.0f px off the middle, +- %s' % (size, 'n/a' if sd is None else '%.0f' % max(sd))))
        if not weak:
            break
        term = min(weak, key=lambda item: item[1])
        dropped_terms.append({'term': term[0], 'at': term[2]})
        if term[0] == 'lens':
            lensspec = dict(lensspec, free=False, lam0=0.0, shift0=fit['shift'])
        else:
            lensspec = dict(lensspec, pp_free=False, shift0=[0.0, 0.0], lam0=fit['lam'])
        fit = na_fit_all(cons, W, H, f_prior, prior, fit['p'], lens=lensspec)
    if mode == 'auto':
        kept = lensspec['free']
        lens.update({'applied': kept, 'lambda_joint': round(fit['lam'], 5) if kept else None,
                     'sigma_joint': round(fit['lam_sd'], 5) if kept and fit['lam_sd'] is not None else None,
                     'why': ('taken out: fitted with the camera at %.4f +- %.4f' % (fit['lam'], fit['lam_sd'] or 0.0)) if kept else
                            'left in: %s' % next((d['at'] for d in dropped_terms if d['term'] == 'lens'), 'not clearly off zero')})
    else:
        lens.update({'applied': lam_seed != 0.0, 'why': 'given' if mode == 'given' else 'not asked for'})
    centre_note = {'mode': 'centre', 'why': 'SketchUp\'s Match Photo assumption (principal_point "solve" tests it)'}
    if pp_mode == 'solve':
        if lensspec['pp_free']:
            size = float(np.linalg.norm(fit['shift']))
            centre_note = {'mode': 'solved', 'offset_px': [round(-float(v), 2) for v in fit['shift']],
                           'sd_px': None if fit['shift_sd'] is None else [round(float(v), 2) for v in fit['shift_sd']],
                           'why': 'the photo looks cropped: its centre of view sits %.0f px off the middle (three sigma or more); '
                                  'the photo for SketchUp is padded so it lands in the middle' % size}
        else:
            centre_note = {'mode': 'centre', 'why': 'tested and kept at the middle: %s'
                           % next((d['at'] for d in dropped_terms if d['term'] == 'centre of view'), 'not clearly off it')}
    lens['dropped_terms'] = dropped_terms
    lensspec = dict(lensspec, lam0=fit['lam'], shift0=fit['shift'])
    lam = float(fit['lam'])
    shift = np.array(fit['shift'], float)
    lens['lambda'] = round(lam, 5)
    for ln in lines:
        ln['u'] = na_to_camera(ln['d'], lam, shift, c, s)

    auto_used = []
    sugg_opts = job.get('suggest') if isinstance(job.get('suggest'), dict) else {}
    stats_u = {ln['id']: na_line_stats(ln['u']) for ln in lines}
    suggestions = na_suggest(segs, report, stats_u, lam, c, s, W, H, sugg_opts, shift)
    if job.get('auto_lines') and suggestions:
        for a, items in suggestions.items():
            for k, item in enumerate(items):
                ends = np.array(item['rough'], float)
                pts_d = np.linspace(ends[0], ends[1], max(3, int(item['length_px'] // 4)))
                lines.append({'id': 'A%s%d' % (a.upper(), k + 1), 'axis': a, 'source': 'auto', 'd': pts_d,
                              'u': na_to_camera(pts_d, lam, shift, c, s)})
                auto_used.append('A%s%d' % (a.upper(), k + 1))
        cons = builder(lines, points)
        fit = na_fit_all(cons, W, H, f_prior, prior, fit['p'], lens=lensspec)
        lam = float(fit['lam'])
        shift = np.array(fit['shift'], float)
        for ln in lines:
            ln['u'] = na_to_camera(ln['d'], lam, shift, c, s)
        stats_u = {ln['id']: na_line_stats(ln['u']) for ln in lines}

    p = fit['p']
    specs = []
    for kind in ('checks', 'measures'):
        for i, spec in enumerate(job.get(kind) or []):
            specs.append(dict(spec, id=spec.get('id') or '%s%d' % ('K' if kind == 'checks' else 'M', i + 1), _kind=kind))
    reads = na_readings(p, specs, stats_u, W, H, lam, c, s, shift=shift)
    derived = job.get('derived') or []
    unc_opts = job.get('uncertainty') if isinstance(job.get('uncertainty'), dict) else {}
    mc, mc_seconds = ([], 0.0)
    if int(unc_opts.get('refits', 60)) > 0 and (specs or derived):
        mc, mc_seconds = na_monte_carlo(lines, points, builder, fit, W, H, f_prior, prior, specs, lensspec, unc_opts)

    gates, stop = [], []

    def gate(level, what, detail):
        gates.append({'level': level, 'what': what, 'detail': detail})

    rms_gate = 6.0 * math.hypot(W, H) / NA_DIAG_12MP
    gate('OK' if fit['rms'] <= rms_gate else ('WARN' if fit['rms'] <= 1.7 * rms_gate else 'FAIL'), 'camera rms',
         '%.2f px over %d constraints (OK under %.2f px for a %d x %d photo)' % (fit['rms'], len(fit['rows']), rms_gate, W, H))
    if job.get('f_equiv_mm') or f35:
        dev = abs(p[6] / f_prior - 1)
        gate('OK' if dev <= 0.10 else ('WARN' if dev <= 0.20 else 'FAIL'), 'focal vs EXIF', '%.0f px against %.0f (%+.1f %%)' % (p[6], f_prior, 100 * (p[6] / f_prior - 1)))
    else:
        png_note = '; PNG carries no EXIF (phone ultra-wide PNGs are usually rectilinear)' if photo.lower().endswith('.png') else ''
        gate('WARN', 'focal', 'no EXIF focal length: the focal comes from the lines alone (%.0f px, %.1f mm equivalent%s)'
             % (p[6], p[6] * 43.27 / math.hypot(W, H), png_note))
    for ln in lines:
        sw = snaps.get(ln['id'], {}).get('snap_warning')
        if sw:
            gate('WARN', 'snap drift %s' % ln['id'], '%s: verify the dotted line on the preview' % sw)
    zs = [float(cc['A'][2]) for cc in cons if cc['kind'] == 'line' and cc.get('_world_known')] + [float(pt['world'][2]) for pt in points]
    if zs and p[5] < min(zs) - 500:
        gate('FAIL', 'camera height', 'the eye is %.0f mm below the lowest known line: impossible, check the world points' % (min(zs) - p[5]))
    if not any(ln['axis'] == 'z' for ln in lines):
        gate('WARN', 'verticals', 'no blue (z) lines: nothing checks the focal length; add corners, jambs or pipes')
    for r in fit.get('outliers', []):
        why = 'the CAD disagrees with the photo: overlay it through the scene and ask Adam' if r['source'] == 'cad' else 'a wrong pick or the wrong axis'
        gate('FAIL' if r['source'] == 'cad' else 'WARN', 'outlier %s' % r['id'], '%.1f px against a gate of %.1f: dropped (%s)' % (r['rms_px'], r['gate_px'], why))
    if not job.get('checks'):
        gate('WARN', 'checks', 'no checks: the ACCURACY STOP needs features the fit did not use, with what the CAD says they are')

    def summ(key, axis_index):
        return na_summary([smp['read'][key][axis_index] if smp['read'].get(key) is not None else None for smp in mc]) if mc else None

    checks_out, measures_out = [], []
    for spec in specs:
        X, px = reads[spec['id']]
        row = {'id': spec['id'], 'note': spec.get('note', ''), 'plane': spec['plane'], 'px': na_round(px, 2), 'read': None if X is None else na_round(X)}
        if X is not None:
            row['plus_minus'] = {ax: summ(spec['id'], i) for i, ax in enumerate('xyz')} if mc else None
        if spec['_kind'] == 'checks':
            if X is not None:
                miss = {ax: round(float(X['xyz'.index(ax)] - float(v)), 1) for ax, v in (spec.get('expect') or {}).items()}
                row['miss_mm'] = miss
                worst = max([abs(v) for v in miss.values()] or [0.0])
                lvl = 'OK' if worst <= 15 else ('WARN' if worst <= NA_STOP_MM else 'FAIL')
                gate(lvl, 'check %s' % spec['id'], '%s: misses by %.0f mm' % (spec.get('note', ''), worst))
                if worst > NA_STOP_MM:
                    stop.append('check %s misses by %.0f mm (over %d)' % (spec['id'], worst, NA_STOP_MM))
            checks_out.append(row)
        else:
            if mc and X is not None:
                sds = [v['sd'] for v in row['plus_minus'].values() if v]
                if sds and max(sds) > NA_STOP_MM and spec.get('critical', True):
                    stop.append('%s is only good to +-%.0f mm (1 sd)' % (spec['id'], max(sds)))
            measures_out.append(row)
    derived_out = []
    base_read = {k: v[0] for k, v in reads.items()}
    for spec in derived:
        val = na_derived_value(spec, base_read)
        row = {'id': spec.get('id', ''), 'note': spec.get('note', ''), 'of': [spec['a'], spec['b']], 'axis': spec.get('axis', 'distance'),
               'value': None if val is None else round(val, 1)}
        if mc:
            row['plus_minus'] = na_summary([na_derived_value(spec, smp['read']) for smp in mc])
            if row['plus_minus'] and row['plus_minus']['sd'] > NA_STOP_MM and spec.get('critical', True):
                stop.append('%s is only good to +-%.0f mm (1 sd)' % (row['id'] or 'a derived reading', row['plus_minus']['sd']))
        derived_out.append(row)
    if stop:
        gate('FAIL', 'ACCURACY STOP', '; '.join(stop))

    # --- the photo for the scene -------------------------------------------------
    out_dir = job['out_dir']
    os.makedirs(out_dir, exist_ok=True)
    base = job.get('base_name') or os.path.splitext(os.path.basename(photo))[0]
    fmt = '.png' if job.get('format') == 'png' else '.jpg'
    pad = (int(math.ceil(abs(shift[0]))), int(math.ceil(abs(shift[1]))))
    W2, H2 = W + 2 * pad[0], H + 2 * pad[1]
    offset = np.array(pad, float)                            # camera-frame pixel + offset = output pixel
    clean = na_undistort_image(enhanced, lam, c - shift, s)
    if pad != (0, 0) or float(np.abs(shift).max()) > 1e-9:
        M = np.array([[1.0, 0.0, shift[0] + offset[0]], [0.0, 1.0, shift[1] + offset[1]]])
        clean = cv2.warpAffine(clean, M, (W2, H2), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT, borderValue=(255, 255, 255))
    ow, _ = project(p, [origin['world'], scale['world']], W, H)
    o_px, s_px = ow[0] + offset, ow[1] + offset
    Rf = rod(p[:3])
    for a in ('x', 'y'):
        dv = Rf @ np.array(NA_AXES[a])
        if abs(dv[2]) > 1e-9:
            report.setdefault('vp_px_final', {})[a] = [round(float(p[6] * dv[0] / dv[2] + W / 2.0 + offset[0]), 1),
                                                     round(float(p[6] * dv[1] / dv[2] + H / 2.0 + offset[1]), 1)]
    stats_out = {ln['id']: na_line_stats(ln['u'] + offset) for ln in lines}
    legend = ['MATCH PHOTO (agent): red x, green y, blue z lines; dotted = fitted, solid = measured',
              'focal %.0f px (%.1f mm equiv) | rms %.2f px | lens lambda %s | %s' % (
                  p[6], p[6] * 43.27 / math.hypot(W, H), fit['rms'], ('%.4f' % lam) if lam else '0 (none taken out)',
                  ('ACCURACY STOP: ' + stop[0]) if stop else 'checks within %d mm' % NA_STOP_MM if job.get('checks') else 'no checks given'),
              'O origin %s | S scale point %s | enhanced: %s' % (na_round(origin['world'], 0), na_round(scale['world'], 0), ', '.join(step.split(' ')[0] for step in steps))]
    ov_opts = job.get('overlay') if isinstance(job.get('overlay'), dict) else ({} if job.get('overlay', True) else None)
    marked = na_overlay(clean, lines, stats_out, report, o_px, s_px, ov_opts, legend) if ov_opts is not None else clean
    scene_path = na_unique(os.path.join(out_dir, base + '__MatchPhoto' + fmt))
    clean_path = na_unique(os.path.join(out_dir, base + '__Enhanced' + fmt))
    preview_path = na_unique(os.path.join(out_dir, base + '__Preview.jpg'))
    na_write_image(scene_path, marked)
    na_write_image(clean_path, clean)
    pw = min(1600, W2)
    na_write_image(preview_path, cv2.resize(marked, (pw, int(round(H2 * pw / W2))), interpolation=cv2.INTER_AREA) if pw < W2 else marked, 88)

    R = rod(p[:3])
    eye = p[3:6]
    fwd, up = R[2], -R[1]
    fov_v = 2 * math.degrees(math.atan(H2 / 2.0 / p[6]))
    pitch, roll, yaw = pose_angles(p)
    tests = [list(map(float, origin['world'])), list(map(float, scale['world']))]
    tests += [na_round(row['read']) for row in checks_out if row['read']]
    tuv, _ = project(p, tests, W2, H2)
    camera = {'eye': na_round(eye), 'target': na_round(eye + fwd * 10000.0), 'up': [round(float(v), 6) for v in up],
              'fov_v_deg': round(fov_v, 4), 'aspect': round(W2 / H2, 6), 'f_px': round(float(p[6]), 2),
              'f_equiv_mm': round(float(p[6]) * 43.27 / math.hypot(W, H), 1), 'width_px': W2, 'height_px': H2,
              'pitch_deg': round(pitch, 2), 'roll_deg': round(roll, 2), 'yaw_deg': round(yaw, 2),
              'p': [float(v) for v in p], 'principal_point': dict(centre_note, canvas_pad_px=list(pad)), 'lens_lambda': lam,
              'note': 'for the photo for SketchUp (files.scene_photo): undistorted%s' % (', padded so the centre of view is its middle' if pad != (0, 0) else '')}
    stds = None
    if mc:
        P = np.array([smp['p'] for smp in mc])
        stds = {'f_px': round(float(P[:, 6].std(ddof=1)), 2), 'eye_mm': na_round(P[:, 3:6].std(axis=0, ddof=1)),
                'lens_lambda': round(float(np.std([smp['lam'] for smp in mc], ddof=1)), 5)}
    rows = sorted(fit['rows'], key=lambda r: -r['rms_px'])
    result = {
        'ok': True, 'worker': NA_WORKER_VERSION, 'deps': {k: v for k, v in deps.items() if k in ('numpy', 'cv2', 'scipy', 'cv2_contrib')},
        'photo': {'source': photo, 'width_px': W, 'height_px': H, 'scene_photo_px': [W2, H2], 'exif_orientation': orientation, 'exif_f35_mm': f35,
                  'enhancement': steps, 'lens': lens},
        'lines': [{'id': ln['id'], 'axis': ln['axis'], 'source': ln.get('source', 'photo'), **{k: v for k, v in snaps.get(ln['id'], {'auto': True}).items()}}
                  for ln in lines],
        'vanishing': report, 'camera': camera, 'camera_sd': stds,
        'fit': {'rms_px': round(fit['rms'], 3), 'constraints': rows, 'outliers': fit.get('outliers', []), 'solved_free': fit['solved_free'],
                'auto_lines': auto_used},
        'checks': checks_out, 'measures': measures_out, 'derived': derived_out,
        'uncertainty': {'refits': len(mc), 'seconds': mc_seconds} if mc else {'refits': 0},
        'gates': gates, 'accuracy_stop': bool(stop), 'accuracy_stop_reasons': stop,
        'suggested_lines': suggestions,
        'files': {'scene_photo': scene_path, 'clean_photo': clean_path, 'preview': preview_path},
        'scene_arguments': {'photo': scene_path, 'camera': {k: camera[k] for k in ('eye', 'target', 'up', 'fov_v_deg')},
                            'tests': [{'world': na_round(X), 'px': na_round(uv, 3)} for X, uv in zip(tests, tuv)],
                            'record': {'source_photo': photo, 'f_px': camera['f_px'], 'rms_px': round(fit['rms'], 3), 'lens_lambda': lam,
                                       'accuracy_stop': bool(stop), 'width_px': W2, 'height_px': H2}},
        'seconds': round(time.time() - t_start, 1)}
    record_path = na_unique(os.path.join(out_dir, base + '__Record.json'))
    with open(record_path, 'w', encoding='utf-8') as handle:
        json.dump(dict(result, job=job), handle, indent=1, default=str)
    result['files']['record'] = record_path
    return result

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Self-test: a synthetic house, rendered through a known camera and lens
# -----------------------------------------------------------------------------

def na_selftest():
    na_import()
    import tempfile
    rng = np.random.default_rng(5)
    W, H = 1600, 1000
    yaw = math.radians(35.0)
    C = np.array([9000.0, -14000.0, 4200.0])
    tgt = np.array([-3000.0, 2500.0, 3200.0])
    fwd = (tgt - C) / np.linalg.norm(tgt - C)
    right = np.cross(fwd, [0, 0, 1.0])
    right /= np.linalg.norm(right)
    down = np.cross(fwd, right)
    p_true = np.concatenate([from_R(np.array([right, down, fwd])), C, [1150.0]])
    lam_true = -0.06
    c, s = np.array([W / 2.0, H / 2.0]), math.hypot(W, H) / 2.0

    def px_of(X):
        uv, _ = project(p_true, X, W, H)
        return na_distort_pts(uv, lam_true, c, s)

    # Rendered at 4x and averaged down: OpenCV's polygon fill covers every pixel whose centre is on the boundary,
    # which drew each face and window about 0.6 px too big at 1x (a test-image error, not a snapping one).
    SS = 4
    img = np.full((H * SS, W * SS, 3), 205, np.uint8)
    img[: H * SS // 2] = (235, 225, 215)
    noise = rng.normal(0, 6, (H, W, 3))

    def poly(pts3, colour):
        dense = []
        for a, b in zip(pts3, pts3[1:] + pts3[:1]):
            for t in np.linspace(0, 1, 60, endpoint=False):
                dense.append(np.array(a) * (1 - t) + np.array(b) * t)
        q = px_of(np.array(dense)) * SS - 0.5
        cv2.fillPoly(img, [np.round(q * 16).astype(np.int32)], colour, cv2.LINE_8, shift=4)

    front = [[-12000, 0, 0], [0, 0, 0], [0, 0, 6000], [-12000, 0, 6000]]
    side = [[0, 0, 0], [0, 9000, 0], [0, 9000, 6000], [0, 0, 6000]]
    poly(front, (95, 120, 150))
    poly(side, (150, 175, 200))
    for x0 in (-10500, -7000, -3500):
        for z0 in (900, 3700):
            poly([[x0, 0, z0], [x0 + 1500, 0, z0], [x0 + 1500, 0, z0 + 1500], [x0, 0, z0 + 1500]], (245, 245, 245))
    for y0 in (1500, 5500):
        for z0 in (900, 3700):
            poly([[0, y0, z0], [0, y0 + 1400, z0], [0, y0 + 1400, z0 + 1500], [0, y0, z0 + 1500]], (250, 250, 250))
    img = cv2.resize(img, (W, H), interpolation=cv2.INTER_AREA)
    img = np.clip(cv2.GaussianBlur(img.astype(float), (0, 0), 0.7) + noise, 0, 255).astype(np.uint8)
    tmp = tempfile.mkdtemp(prefix='na_mp_selftest_')
    photo = os.path.join(tmp, 'synthetic.png')
    na_write_image(photo, img)

    def rough(X0, X1, jitter=1.5):
        a, b = px_of(np.array([X0, X1], float))
        return [list(a + rng.normal(0, jitter, 2)), list(b + rng.normal(0, jitter, 2))]

    lines = [
        {'id': 'R1', 'axis': 'x', 'source': 'cad', 'rough': rough([-11000, 0, 6000], [-800, 0, 6000]), 'sign': -1, 'w': 7, 'through': [0, 0, 6000]},
        {'id': 'R2', 'axis': 'x', 'source': 'cad', 'rough': rough([-10200, 0, 900], [-2200, 0, 900]), 'sign': -1, 'w': 7, 'through': [0, 0, 900]},
        {'id': 'G1', 'axis': 'y', 'rough': rough([0, 800, 6000], [0, 8200, 6000]), 'sign': -1, 'w': 7},
        {'id': 'G2', 'axis': 'y', 'rough': rough([0, 1700, 2400], [0, 2700, 2400]), 'sign': 1, 'w': 7},
        {'id': 'G3', 'axis': 'y', 'rough': rough([0, 5700, 900], [0, 6700, 900]), 'sign': -1, 'w': 7},
        {'id': 'B1', 'axis': 'z', 'source': 'cad', 'rough': rough([0, 0, 300], [0, 0, 5700]), 'sign': 0, 'w': 7, 'through': [0, 0, 0]},
        {'id': 'B2', 'axis': 'z', 'source': 'cad', 'rough': rough([-12000, 0, 300], [-12000, 0, 5700]), 'sign': 0, 'w': 7, 'through': [-12000, 0, 0]},
        {'id': 'B3', 'axis': 'z', 'rough': rough([0, 9000, 300], [0, 9000, 5700]), 'sign': 0, 'w': 7}]
    job = {'photo': photo, 'lines': lines, 'origin': {'world': [0, 0, 6000], 'lines': ['R1', 'B1']},
           'scale': {'world': [-12000, 0, 6000], 'lines': ['R1', 'B2']},
           'checks': [{'id': 'K1', 'px': list(px_of(np.array([[0, 9000, 6000]]))[0]), 'plane': 'x=0', 'expect': {'y': 9000}}],
           'measures': [{'id': 'M1', 'lines': ['B3', 'G1'], 'plane': 'x=0'}],
           'uncertainty': {'refits': 20, 'max_seconds': 20}, 'out_dir': tmp, 'base_name': 'PM01__Selftest__'}
    res = Na__VisionWorker__Run(job)
    cam = res['camera']
    f_err = abs(cam['f_px'] / 1150.0 - 1)
    e_err = float(np.linalg.norm(np.array(cam['eye']) - C) / np.linalg.norm(C - [0, 0, 6000]))
    l_err = abs(res['photo']['lens']['lambda'] - lam_true)
    m1 = res['measures'][0]['read'][1] if res['measures'][0]['read'] else float('nan')
    ok1 = f_err < 0.02 and e_err < 0.02
    ok2 = res['photo']['lens']['applied'] and l_err < 0.015
    pm = (res['measures'][0].get('plus_minus') or {}).get('y') or {}
    sd = pm.get('sd') or 0.0
    ok3 = abs(m1 - 9000) <= max(3.0 * sd, 30.0) and res['fit']['rms_px'] < 1.0
    ok4 = os.path.exists(res['files']['scene_photo']) and os.path.exists(res['files']['record'])
    print('synthetic house, lens lambda %.3f, 1.5 px rough clicks: focal %.1f px (1150, %.2f %%), eye off %.2f %% of its distance  %s'
          % (lam_true, cam['f_px'], 100 * f_err, 100 * e_err, 'OK' if ok1 else 'FAIL'))
    print('lens: lambda %.4f taken out (%s; the plumb-line alone said %s)  %s' % (res['photo']['lens']['lambda'], res['photo']['lens']['why'],
          res['photo']['lens'].get('lambda_fitted'), 'OK' if ok2 else 'FAIL'))
    print('far corner read at y %.0f +- %.0f (9000: within three sd), rms %.2f px, %d refits  %s'
          % (m1, sd, res['fit']['rms_px'], res['uncertainty'].get('refits', 0), 'OK' if ok3 else 'FAIL'))
    print('scene photo and record written  %s' % ('OK' if ok4 else 'FAIL'))
    # A cropped photo (estate agents crop): 220 px off the left, 90 off the top, so the centre of view sits
    # (-110, -45) px from the cropped photo's middle. principal_point "solve" must find it and pad the scene photo.
    crop = img[90:, 220:]
    photo2 = os.path.join(tmp, 'synthetic_cropped.png')
    na_write_image(photo2, crop)
    shifted = []
    for ln in lines:
        moved = dict(ln, rough=[[u - 220.0, v - 90.0] for u, v in ln['rough']])
        shifted.append(moved)
    job2 = dict(job, photo=photo2, lines=shifted, principal_point='solve', base_name='PM02__SelftestCropped__',
                checks=[dict(job['checks'][0], px=[job['checks'][0]['px'][0] - 220.0, job['checks'][0]['px'][1] - 90.0])])
    res2 = Na__VisionWorker__Run(job2)
    pp = res2['camera']['principal_point']
    off = np.array(pp.get('offset_px', [0, 0]), float)
    ok5 = pp['mode'] == 'solved' and float(np.linalg.norm(off - [-110.0, -45.0])) < 12.0
    cam2 = res2['camera']
    f2_err = abs(cam2['f_px'] / 1150.0 - 1)
    e2_err = float(np.linalg.norm(np.array(cam2['eye']) - C) / np.linalg.norm(C - [0, 0, 6000]))
    ok6 = f2_err < 0.02 and e2_err < 0.02 and cam2['width_px'] > crop.shape[1]
    print('cropped photo: centre of view found at %s px from the middle (-110, -45)  %s' % (na_round(off, 1), 'OK' if ok5 else 'FAIL'))
    print('cropped photo: focal %.1f px (%.2f %%), eye off %.2f %%, scene photo padded to %d x %d  %s'
          % (cam2['f_px'], 100 * f2_err, 100 * e2_err, cam2['width_px'], cam2['height_px'], 'OK' if ok6 else 'FAIL'))
    # Rectilinear guard: a zero-distortion photo must not receive runaway lens distortion when lens='auto'.
    img_rect = np.full((H * SS, W * SS, 3), 205, np.uint8)
    img_rect[: H * SS // 2] = (235, 225, 215)
    def px_rect(X):
        uv, _ = project(p_true, X, W, H)
        return uv
    def poly_rect(pts3, colour):
        dense = []
        for a, b in zip(pts3, pts3[1:] + pts3[:1]):
            for t in np.linspace(0, 1, 60, endpoint=False):
                dense.append(np.array(a) * (1 - t) + np.array(b) * t)
        q = px_rect(np.array(dense)) * SS - 0.5
        cv2.fillPoly(img_rect, [np.round(q * 16).astype(np.int32)], colour, cv2.LINE_8, shift=4)
    poly_rect(front, (95, 120, 150))
    poly_rect(side, (150, 175, 200))
    for x0 in (-10500, -7000, -3500):
        for z0 in (900, 3700):
            poly_rect([[x0, 0, z0], [x0 + 1500, 0, z0], [x0 + 1500, 0, z0 + 1500], [x0, 0, z0 + 1500]], (245, 245, 245))
    for y0 in (1500, 5500):
        for z0 in (900, 3700):
            poly_rect([[0, y0, z0], [0, y0 + 1400, z0], [0, y0 + 1400, z0 + 1500], [0, y0, z0 + 1500]], (250, 250, 250))
    img_rect = cv2.resize(img_rect, (W, H), interpolation=cv2.INTER_AREA)
    img_rect = np.clip(cv2.GaussianBlur(img_rect.astype(float), (0, 0), 0.7) + noise, 0, 255).astype(np.uint8)
    photo3 = os.path.join(tmp, 'synthetic_rectilinear.png')
    na_write_image(photo3, img_rect)
    def rough_rect(X0, X1, jitter=1.5):
        a, b = px_rect(np.array([X0, X1], float))
        return [list(a + rng.normal(0, jitter, 2)), list(b + rng.normal(0, jitter, 2))]
    lines_rect = [
        {'id': 'R1', 'axis': 'x', 'source': 'cad', 'rough': rough_rect([-11000, 0, 6000], [-800, 0, 6000]), 'sign': -1, 'w': 7, 'through': [0, 0, 6000]},
        {'id': 'R2', 'axis': 'x', 'source': 'cad', 'rough': rough_rect([-10200, 0, 900], [-2200, 0, 900]), 'sign': -1, 'w': 7, 'through': [0, 0, 900]},
        {'id': 'G1', 'axis': 'y', 'rough': rough_rect([0, 800, 6000], [0, 8200, 6000]), 'sign': -1, 'w': 7},
        {'id': 'G2', 'axis': 'y', 'rough': rough_rect([0, 1700, 2400], [0, 2700, 2400]), 'sign': 1, 'w': 7},
        {'id': 'G3', 'axis': 'y', 'rough': rough_rect([0, 5700, 900], [0, 6700, 900]), 'sign': -1, 'w': 7},
        {'id': 'B1', 'axis': 'z', 'source': 'cad', 'rough': rough_rect([0, 0, 300], [0, 0, 5700]), 'sign': 0, 'w': 7, 'through': [0, 0, 0]},
        {'id': 'B2', 'axis': 'z', 'source': 'cad', 'rough': rough_rect([-12000, 0, 300], [-12000, 0, 5700]), 'sign': 0, 'w': 7, 'through': [-12000, 0, 0]},
        {'id': 'B3', 'axis': 'z', 'rough': rough_rect([0, 9000, 300], [0, 9000, 5700]), 'sign': 0, 'w': 7}]
    job3 = dict(job, photo=photo3, lines=lines_rect, uncertainty={'refits': 0}, base_name='PM03__SelftestRect__',
                checks=[{'id': 'K1', 'px': list(px_rect(np.array([[0, 9000, 6000]]))[0]), 'plane': 'x=0', 'expect': {'y': 9000}}])
    res3 = Na__VisionWorker__Run(job3)
    ok7 = (not res3['photo']['lens']['applied']) and res3['photo']['lens']['lambda'] == 0.0 and res3['fit']['rms_px'] < 1.0
    print('rectilinear photo: lens left in (lambda %.4f), rms %.2f px  %s'
          % (res3['photo']['lens']['lambda'], res3['fit']['rms_px'], 'OK' if ok7 else 'FAIL'))
    ok = ok1 and ok2 and ok3 and ok4 and ok5 and ok6 and ok7
    import shutil
    shutil.rmtree(tmp, ignore_errors=True)               # the synthetic photos and their outputs
    print('==> OK' if ok else '==> FAIL')
    return ok

# endregion -------------------------------------------------------------------


def main(argv):
    if argv and argv[0] == '--deps':
        print(json.dumps(Na__VisionWorker__Deps()))
        return 0
    if argv and argv[0] == '--selftest':
        return 0 if na_selftest() else 1
    if not argv:
        print(__doc__ or 'usage: worker <job.json> | --deps | --selftest')
        return 2
    with open(argv[0], 'r', encoding='utf-8') as handle:
        job = json.load(handle)
    out_path = job.get('result_path') or os.path.splitext(argv[0])[0] + '__Result.json'
    try:
        result = Na__VisionWorker__Run(job)
    except Na__VisionError as error:
        result = {'ok': False, 'error': {'code': error.na_code, 'message': error.na_message, 'hint': error.na_hint}}
    except Exception as error:                                # noqa: BLE001 - report every crash to the server
        result = {'ok': False, 'error': {'code': 'operation_failed', 'message': 'The vision worker failed: %s: %s' % (type(error).__name__, error),
                                         'hint': 'Details: ' + traceback.format_exc()[-1500:]}}
    with open(out_path, 'w', encoding='utf-8') as handle:
        json.dump(result, handle, indent=1, default=str)
    return 0 if result.get('ok') else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

# =============================================================================
# END OF FILE
# =============================================================================
