// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - CROP AND CUT BOXES
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__BoxFilter__.hpp
// PURPOSE    : The Clean tab's Crop and Cut boxes (v0.11.0, ABI 8): ONE Keep
//              box (every point outside it is removed) and up to
//              NAPC_MAX_CUT_BOXES Cut boxes (every point inside any of them is
//              removed). Like the clip box, each box is axis-aligned in MODEL
//              inches, and a point is tested after local -> model (M, t), so
//              the boxes stay level with the model whatever the placement.
//
// ONE TEST, EVERYWHERE: the preview (the renderer hides or colours what the
//   boxes remove), the count in the dialog and the export all call Verdict()
//   below, in double precision. The count and the export are compiled with
//   /fp:precise and agree exactly; the renderer's /fp:fast copy could only
//   differ for a point within about 1e-12 inch of a face.
//
// EDGES: a box holds its own faces, as the clip box does. A point on a Keep
//   box face is kept; a point on a Cut box face is removed.
//
// The engine's copy of a point (float, local) is what is tested, so a point
// within about a hundredth of a millimetre of a face is judged by that copy,
// not by its exact LAS integers. The export still copies the LAS records.
//
// =============================================================================

#pragma once

#include <cstdint>

#include "Na__PointCloudViewer__NativeEngine__Api__.h"

enum Na__BoxVerdict : int {
    NA_BOX_KEPT         = 0,
    NA_BOX_OUTSIDE_KEEP = 1,
    NA_BOX_INSIDE_CUT   = 2
};

struct Na__BoxFilter {
    double m[9] = { 1, 0, 0, 0, 1, 0, 0, 0, 1 };   // local -> model inches (row-major)
    double t[3] = { 0, 0, 0 };
    bool   keep = false;
    double keep_lo[3] = { 0, 0, 0 };
    double keep_hi[3] = { 0, 0, 0 };
    int    cuts = 0;
    double cut_lo[NAPC_MAX_CUT_BOXES][3] = {};
    double cut_hi[NAPC_MAX_CUT_BOXES][3] = {};

    bool Active() const { return keep || cuts > 0; }

    // What the boxes do to a point (local coordinates, as stored).
    inline int Verdict(float lx, float ly, float lz) const {
        const double x = lx, y = ly, z = lz;
        const double px = m[0] * x + m[1] * y + m[2] * z + t[0];
        const double py = m[3] * x + m[4] * y + m[5] * z + t[1];
        const double pz = m[6] * x + m[7] * y + m[8] * z + t[2];
        if (keep && !(px >= keep_lo[0] && px <= keep_hi[0] && py >= keep_lo[1] && py <= keep_hi[1] &&
                      pz >= keep_lo[2] && pz <= keep_hi[2])) {
            return NA_BOX_OUTSIDE_KEEP;
        }
        for (int c = 0; c < cuts; ++c) {
            if (px >= cut_lo[c][0] && px <= cut_hi[c][0] && py >= cut_lo[c][1] && py <= cut_hi[c][1] &&
                pz >= cut_lo[c][2] && pz <= cut_hi[c][2]) {
                return NA_BOX_INSIDE_CUT;
            }
        }
        return NA_BOX_KEPT;
    }
};

// transform: 12 doubles (row-major 3x3, then the translation); block:
// NAPC_BOX_BLOCK_COUNT doubles (Na__BoxBlockIndex). False when a box is not a
// box (a side not above its opposite, or not a number) or the cut count is
// out of range; `out` is then left inactive.
inline bool Na__BoxFilter__Read(const double* transform, const double* block, Na__BoxFilter& out) {
    out = Na__BoxFilter();
    if (!transform || !block) return false;
    Na__BoxFilter f;
    for (int k = 0; k < 9; ++k) f.m[k] = transform[k];
    for (int a = 0; a < 3; ++a) f.t[a] = transform[9 + a];
    f.keep = block[NAPC_B_KEEP] > 0.5;
    if (f.keep) {
        for (int a = 0; a < 3; ++a) {
            f.keep_lo[a] = block[NAPC_B_KEEP_MIN_X + a];
            f.keep_hi[a] = block[NAPC_B_KEEP_MAX_X + a];
            if (!(f.keep_hi[a] > f.keep_lo[a])) return false;
        }
    }
    const double count = block[NAPC_B_CUT_COUNT];
    if (!(count >= 0.0 && count <= NAPC_MAX_CUT_BOXES)) return false;
    f.cuts = static_cast<int>(count + 0.5);
    for (int c = 0; c < f.cuts; ++c) {
        const double* box = block + NAPC_B_CUTS + 6 * c;
        for (int a = 0; a < 3; ++a) {
            f.cut_lo[c][a] = box[a];
            f.cut_hi[c][a] = box[3 + a];
            if (!(f.cut_hi[c][a] > f.cut_lo[c][a])) return false;
        }
    }
    out = f;
    return true;
}
