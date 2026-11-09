"""Native tests for ABI 9: napc_box_points and napc_box_grid, checked against numpy.

    python native_box_queries_test.py [path/to/Na__PointCloudViewer__NativeEngine.dll]

Default DLL: this module's own 02__Src__NativeEngine/04__Bin__WindowsSketchUp2026. The DLL is
copied to a temp file first, so the build output is never locked. A cloud is made with
napc_cloud_create (stored in the order given), placed by a rotation, a unit factor and a
translation like a real cloud, and every answer is compared with the same sums in numpy,
done in the engine's order (float local coordinates, then double).
"""
import ctypes
import os
import shutil
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DLL = os.path.normpath(os.path.join(HERE, '..', '..', '..', '02__Src__NativeEngine', '04__Bin__WindowsSketchUp2026',
                                            'Na__PointCloudViewer__NativeEngine.dll'))
BOX_BLOCK = 8 + 6 * 20
BOXES = 12 + BOX_BLOCK
GRID = 12
STATS = 4

failures = []
checks = [0]


def check(label, ok):
    checks[0] += 1
    if not ok:
        failures.append(label)


def load(path):
    copy = os.path.join(tempfile.mkdtemp(prefix='na_pcv_abi9_'), 'engine.dll')
    shutil.copy2(path, copy)
    lib = ctypes.CDLL(copy)
    vp, i32, i64, dbl = ctypes.c_void_p, ctypes.c_int32, ctypes.c_int64, ctypes.c_double
    lib.napc_abi_version.restype = i32
    lib.napc_last_error.restype = ctypes.c_char_p
    lib.napc_cloud_create.argtypes = [vp, vp, i64]
    lib.napc_cloud_create.restype = vp
    lib.napc_cloud_destroy.argtypes = [vp]
    lib.napc_box_count.argtypes = [vp, vp, i32, vp, i32]
    lib.napc_box_count.restype = i32
    lib.napc_box_points.argtypes = [vp, vp, i32, dbl, vp, vp, i64, vp, i32]
    lib.napc_box_points.restype = i64
    lib.napc_box_grid.argtypes = [vp, vp, i32, vp, i32, vp, i64, vp, i32]
    lib.napc_box_grid.restype = i32
    return lib


def ptr(array):
    return array.ctypes.data_as(ctypes.c_void_p)


def boxes_block(transform, keep=None, cuts=()):
    block = np.zeros(BOXES, dtype=np.float64)
    block[:12] = transform
    if keep is not None:
        block[12] = 1.0
        block[13:16] = keep[0]
        block[16:19] = keep[1]
    block[19] = len(cuts)
    for c, (lo, hi) in enumerate(cuts):
        block[20 + 6 * c:23 + 6 * c] = lo
        block[23 + 6 * c:26 + 6 * c] = hi
    return block


def kept_mask(model, keep=None, cuts=()):
    mask = np.ones(len(model), dtype=bool)
    if keep is not None:
        mask &= np.all((model >= keep[0]) & (model <= keep[1]), axis=1)
    for lo, hi in cuts:
        mask &= ~np.all((model >= lo) & (model <= hi), axis=1)
    return mask


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DLL
    lib = load(path)
    check('ABI is 9', lib.napc_abi_version() == 9)

    rng = np.random.default_rng(20261109)
    n = 300_000
    local = rng.uniform(-6.0, 6.0, size=(n, 3)).astype(np.float32)          # metres, about a local origin
    local[: n // 3, 2] = np.round(local[: n // 3, 2] * 4) / 4                 # a third on z planes 0.25 m apart
    rgb = rng.integers(0, 256, size=(n, 3), dtype=np.uint8)
    angle = np.radians(27.0)
    k = 1000.0 / 25.4                                                          # metres -> inches
    R = np.array([[np.cos(angle), -np.sin(angle), 0], [np.sin(angle), np.cos(angle), 0], [0, 0, 1]])
    M = R * k
    t = np.array([550.0, -320.0, 41.0])
    transform = np.concatenate([M.reshape(-1), t])
    model = local.astype(np.float64) @ M.T + t
    bgra = (0xFF000000 | (rgb[:, 0].astype(np.uint32) << 16) | (rgb[:, 1].astype(np.uint32) << 8) | rgb[:, 2]).astype(np.uint32)

    cloud = lib.napc_cloud_create(ptr(np.ascontiguousarray(local)), ptr(np.ascontiguousarray(rgb)), n)
    check('cloud created', bool(cloud))

    keep = (np.array([400.0, -400.0, -60.0]), np.array([700.0, -100.0, 120.0]))
    cut = ((np.array([500.0, -300.0, -80.0]), np.array([560.0, -200.0, 0.0])),)
    block = boxes_block(transform, keep, cut)
    mask = kept_mask(model, keep, cut)
    stats = np.zeros(STATS)

    # --- box_count still agrees (unchanged call) ---
    out = np.zeros(4)
    lib.napc_box_count(cloud, ptr(block), BOXES, ptr(out), 4)
    check('box_count kept matches numpy', int(out[3]) == int(mask.sum()))

    # --- box_points: the first cap kept, in stored order, scaled ---
    for cap in (0, 1, 777, int(mask.sum()), int(mask.sum()) + 50):
        xyz = np.zeros((max(cap, 1), 3))
        col = np.zeros(max(cap, 1), dtype=np.uint32)
        written = lib.napc_box_points(cloud, ptr(block), BOXES, 25.4, ptr(xyz), ptr(col), cap, ptr(stats), STATS)
        expect = np.flatnonzero(mask)[:cap]
        check('points cap %d: written' % cap, written == len(expect))
        check('points cap %d: kept stat' % cap, int(stats[0]) == int(mask.sum()) and int(stats[1]) == written)
        if written:
            check('points cap %d: model mm, stored order' % cap, np.allclose(xyz[:written], model[expect] * 25.4, rtol=0, atol=1e-9))
            check('points cap %d: colours' % cap, np.array_equal(col[:written], bgra[expect]))

    xyz = np.zeros((10, 3))
    written = lib.napc_box_points(cloud, ptr(boxes_block(transform)), BOXES, 1.0, ptr(xyz), None, 10, ptr(stats), STATS)
    check('points, no box: every point counts, colours optional', written == 10 and int(stats[0]) == n and np.allclose(xyz, model[:10]))
    check('points: a scale of 0 is refused', lib.napc_box_points(cloud, ptr(block), BOXES, 0.0, ptr(xyz), None, 10, None, 0) < 0)
    bad = boxes_block(transform, (keep[1], keep[0]))
    check('points: an inside-out box is refused', lib.napc_box_points(cloud, ptr(bad), BOXES, 1.0, ptr(xyz), None, 10, None, 0) < 0)

    # --- box_grid: counts per cell, against numpy in the engine's order ---
    def grid_case(label, u, v, u0, v1, su, sv, width, height):
        grid = np.array([*u, *v, u0, v1, su, sv, width, height], dtype=np.float64)
        counts = np.zeros(width * height, dtype=np.uint32)
        code = lib.napc_box_grid(cloud, ptr(block), BOXES, ptr(grid), GRID, ptr(counts), width * height, ptr(stats), STATS)
        check(label + ': returns 0', code == 0)
        au, av = M.T @ np.array(u), M.T @ np.array(v)
        bu = float(np.dot(u, t)) - u0
        bv = v1 - float(np.dot(v, t))
        x = local[mask].astype(np.float64)
        cf = (x @ au + bu) / su
        rf = (bv - x @ av) / sv
        on = (cf >= 0) & (cf < width) & (rf >= 0) & (rf < height)
        cell = rf[on].astype(np.int64) * width + cf[on].astype(np.int64)
        expect = np.bincount(cell, minlength=width * height).astype(np.uint32)
        check(label + ': every cell matches numpy', np.array_equal(counts, expect))
        check(label + ': stats', int(stats[0]) == int(mask.sum()) and int(stats[1]) == int(on.sum()) and int(stats[2]) == int(expect.max()))
        return counts

    s = 1 / np.sqrt(2)
    grid_case('grid, a small plan (one count array per worker)', (1, 0, 0), (0, 1, 0), 400.0, -100.0, 5.0, 5.0, 60, 60)
    grid_case('grid, a large view (shared atomic counts)', (0, 1, 0), (0, 0, 1), -400.0, 120.0, 0.15, 0.09, 2000, 2000)
    grid_case('grid, axes at 45 degrees', (s, s, 0), (0, 0, 1), -80.0, 120.0, 2.0, 2.0, 300, 100)
    hist = grid_case('histogram: a one-cell-wide grid, z bins of 0.5 in', (1, 0, 0), (0, 0, -1), 400.0, 60.0, 300.0, 0.5, 1, 360)
    check('histogram: the 0.25 m planes stand out', hist.max() > 4 * np.median(hist[hist > 0]))
    counts = np.zeros(4, dtype=np.uint32)
    zero = np.array([1, 0, 0, 0, 1, 0, 0, 0, 0, 1, 2, 2], dtype=np.float64)
    check('grid: a zero cell size is refused', lib.napc_box_grid(cloud, ptr(block), BOXES, ptr(zero), GRID, ptr(counts), 4, None, 0) < 0)
    big = np.array([1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 3, 3], dtype=np.float64)
    check('grid: more cells than the output holds is refused', lib.napc_box_grid(cloud, ptr(block), BOXES, ptr(big), GRID, ptr(counts), 4, None, 0) < 0)

    lib.napc_cloud_destroy(cloud)
    print('Native ABI 9 box queries: %d passed, %d failed.' % (checks[0] - len(failures), len(failures)))
    for failure in failures:
        print('  FAILED: ' + failure)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
