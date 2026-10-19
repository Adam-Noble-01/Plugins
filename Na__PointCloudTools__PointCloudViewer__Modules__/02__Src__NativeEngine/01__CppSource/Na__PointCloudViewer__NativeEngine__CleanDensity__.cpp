// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - CLEANING: REDUCE DENSITY
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__CleanDensity__.cpp
// PURPOSE    : Filter 03. Keeps one REAL point per patch of surface (or per
//              voxel off the surfaces) - the one nearest the patch's centroid
//              - and drops the rest.
//
// WHY NOT VOXEL AVERAGING (Open3D voxel_down_sample, PCL VoxelGrid): an
//   averaged point is a new point that was never measured. In a voxel that
//   straddles a window reveal or two thin surfaces, the average lands in the
//   air between them. Keeping a measured point (with all of its LAS
//   attributes) cannot invent geometry.
//
// WHY PATCHES ON SURFACES: a wall scanned with 30 mm of noise is a 30 mm
//   thick slab of points, and 3D voxels smaller than that keep several points
//   through its depth, so "about one point every 9 mm" would not be true. A
//   point on a confident surface is binned in 2D on that surface (its cell's
//   in-plane axes): one point per voxel_mm x voxel_mm of wall, however noisy.
//
// FEATURE PROTECTION: points at a corner or edge (several orientations), a
//   step, a doubled surface, the end of a surface (an opening's edge), on
//   rough ground, off every surface (pipes, handles, small objects), held at
//   an ambiguous meeting of surfaces, or where the refined surface tilts
//   across a step the noise hid, use 3D voxels feature_factor times finer.
//   Flat walls and floors thin the most.
//
// DETERMINISM: voxels are anchored at the local origin, patches at each
//   cell's surface fit (computed identically for any region), centroids are
//   summed in LAS-record order and ties go to the lower record, so a preview
//   and the export keep exactly the same points.
//
// =============================================================================

#include "Na__PointCloudViewer__NativeEngine__CleanRegion__.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>

namespace {
    double Na__MsSince(std::chrono::steady_clock::time_point start) {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    }

    struct Na__DensityEntry {
        uint8_t  level;     // 0 plain voxel, 1 feature voxel, 2 surface patch
        int64_t  key[4];
        uint32_t tie;
        uint32_t index;
        bool operator<(const Na__DensityEntry& o) const {
            if (level != o.level) return level < o.level;
            for (int a = 0; a < 4; ++a) if (key[a] != o.key[a]) return key[a] < o.key[a];
            return tie < o.tie;
        }
        bool SameBin(const Na__DensityEntry& o) const {
            return level == o.level && key[0] == o.key[0] && key[1] == o.key[1] && key[2] == o.key[2] && key[3] == o.key[3];
        }
    };
}

void Na__Clean__Density(Na__CleanWork& w) {
    const auto start = std::chrono::steady_clock::now();
    w.density_done = false;
    const Na__CleanParams& p = w.params;
    for (uint32_t i = 0; i < w.n; ++i) w.flags[i] &= static_cast<uint16_t>(~NA_CF_REMOVED_DENSITY);
    if (!p.density_enabled) {
        w.ms_density = 0.0;
        w.density_done = true;
        return;
    }
    const double plain = p.voxel_mm * w.units_per_mm;
    const double fine = plain / std::max(1.0, p.feature_factor);
    const float zone = static_cast<float>(w.zones.density);
    const bool have_fit = w.family_of.size() == w.n;

    std::vector<Na__DensityEntry> entries;
    entries.reserve(w.n / 2);
    for (uint32_t i = 0; i < w.n; ++i) {
        if (w.depth[i] > zone || (w.flags[i] & NA_CF_REMOVED_NOISE)) continue;
        double pos[3];
        for (int a = 0; a < 3; ++a) pos[a] = static_cast<double>(w.xyz[size_t(i) * 3 + a]) + w.delta[size_t(i) * 3 + a];
        Na__DensityEntry e;
        e.tie = w.tie[i];
        e.index = i;
        const bool feature = (w.flags[i] & NA_CF_FEATURE) != 0;
        const int fam = have_fit ? w.family_of[i] : -1;
        const uint32_t slot = w.cell_slot[w.cell[i]];
        bool patched = false;
        if (!feature && (w.flags[i] & NA_CF_ON_SURFACE) && fam >= 0 && slot != UINT32_MAX) {
            // The noise band of a wall straddles cell boundaries: points on both
            // sides of one must share one patch grid. So the patch belongs to the
            // cell the point lands in when PROJECTED onto its surface, in that
            // cell's frame (its family of the same orientation).
            const Na__SurfaceFamily& own = w.surfaces[slot].family[fam];
            const int own_sheet = std::max<int>(0, w.sheet_of[i]);
            const double off = (pos[0] - own.c[0]) * own.n[0] + (pos[1] - own.c[1]) * own.n[1] + (pos[2] - own.c[2]) * own.n[2] - own.sheet[own_sheet];
            if (std::fabs(off) <= w.fine) {
                const double q[3] = { pos[0] - off * own.n[0], pos[1] - off * own.n[1], pos[2] - off * own.n[2] };
                const uint32_t pc = Na__Clean__CellAt(w, Na__FloorDiv(q[0], w.fine), Na__FloorDiv(q[1], w.fine), Na__FloorDiv(q[2], w.fine));
                const uint32_t ps = pc == UINT32_MAX ? UINT32_MAX : w.cell_slot[pc];
                const Na__CellSurface* target = ps != UINT32_MAX && w.surfaces[ps].computed ? &w.surfaces[ps] : nullptr;
                int tf = -1;
                if (target) {
                    for (int f = 0; f < target->families && tf < 0; ++f) {
                        const Na__SurfaceFamily& cand = target->family[f];
                        const double dot = std::fabs(cand.n[0] * own.n[0] + cand.n[1] * own.n[1] + cand.n[2] * own.n[2]);
                        if (dot >= 0.906) tf = f;                 // within 25 degrees
                    }
                }
                const Na__SurfaceFamily& frame = tf >= 0 ? target->family[tf] : own;
                int sheet = own_sheet;
                if (tf >= 0) {
                    const double o = (q[0] - frame.c[0]) * frame.n[0] + (q[1] - frame.c[1]) * frame.n[1] + (q[2] - frame.c[2]) * frame.n[2];
                    double best = 1e300;
                    for (int s = 0; s < frame.sheets; ++s) if (std::fabs(o - frame.sheet[s]) < best) { best = std::fabs(o - frame.sheet[s]); sheet = s; }
                }
                const double d[3] = { q[0] - frame.c[0], q[1] - frame.c[1], q[2] - frame.c[2] };
                e.level = 2;
                e.key[0] = tf >= 0 ? pc : w.slot_cell[slot];
                e.key[1] = (tf >= 0 ? tf : fam) * 4 + sheet + (tf >= 0 ? 0 : 16);
                e.key[2] = Na__FloorDiv(d[0] * frame.u[0] + d[1] * frame.u[1] + d[2] * frame.u[2], plain);
                e.key[3] = Na__FloorDiv(d[0] * frame.v[0] + d[1] * frame.v[1] + d[2] * frame.v[2], plain);
                patched = true;
            }
        }
        if (!patched) {
            const double size = feature ? fine : plain;
            e.level = feature ? 1 : 0;
            for (int a = 0; a < 3; ++a) e.key[a] = Na__FloorDiv(pos[a], size);
            e.key[3] = 0;
        }
        entries.push_back(e);
    }
    Na__CheckCancel(w.cancel);
    std::sort(entries.begin(), entries.end());
    Na__CheckCancel(w.cancel);

    size_t begin = 0;
    while (begin < entries.size()) {
        size_t end = begin + 1;
        while (end < entries.size() && entries[end].SameBin(entries[begin])) ++end;
        if (end - begin > 1) {
            double c[3] = { 0, 0, 0 };
            for (size_t k = begin; k < end; ++k) {
                const uint32_t i = entries[k].index;
                for (int a = 0; a < 3; ++a) c[a] += static_cast<double>(w.xyz[size_t(i) * 3 + a]) + w.delta[size_t(i) * 3 + a];
            }
            for (int a = 0; a < 3; ++a) c[a] /= static_cast<double>(end - begin);
            size_t keep = begin;
            double best = 1e300;
            for (size_t k = begin; k < end; ++k) {          // ascending tie: the first of equals wins
                const uint32_t i = entries[k].index;
                double d2 = 0.0;
                for (int a = 0; a < 3; ++a) {
                    const double d = static_cast<double>(w.xyz[size_t(i) * 3 + a]) + w.delta[size_t(i) * 3 + a] - c[a];
                    d2 += d * d;
                }
                if (d2 < best) { best = d2; keep = k; }
            }
            for (size_t k = begin; k < end; ++k) if (k != keep) w.flags[entries[k].index] |= NA_CF_REMOVED_DENSITY;
        }
        begin = end;
    }
    w.ms_density = Na__MsSince(start);
    w.density_done = true;
}
