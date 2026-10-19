// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - CLEANING REGION
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__CleanRegion__.cpp
// PURPOSE    : Parameters, the global grid, the zone arithmetic and the
//              gather of one region (see the header).
//
// =============================================================================

#include "Na__PointCloudViewer__NativeEngine__CleanRegion__.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>

namespace {
    double Na__MsSince(std::chrono::steady_clock::time_point start) {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    }
    double Na__Clamp(double v, double lo, double hi) { return std::isfinite(v) ? std::min(hi, std::max(lo, v)) : lo; }
}

// -----------------------------------------------------------------------------
// REGION | Parameters
// -----------------------------------------------------------------------------

bool Na__CleanParams__FromArray(const double* v, int32_t count, Na__CleanParams& p, const char** error) {
    if (!v || count < NAPC_CP_COUNT) {
        if (error) *error = "Cleaning parameters are missing.";
        return false;
    }
    p = Na__CleanParams();
    p.mm_per_unit        = Na__Clamp(v[NAPC_CP_MM_PER_UNIT], 1e-3, 1e6);
    p.noise_enabled      = v[NAPC_CP_NOISE_ENABLED] > 0.5;
    p.iso_ratio          = Na__Clamp(v[NAPC_CP_ISO_RATIO], 1.2, 20.0);
    p.iso_min_mm         = Na__Clamp(v[NAPC_CP_ISO_MIN_MM], 0.5, 1000.0);
    p.knn_cap_mm         = Na__Clamp(v[NAPC_CP_KNN_CAP_MM], 5.0, 1000.0);
    p.link_factor        = Na__Clamp(v[NAPC_CP_LINK_FACTOR], 1.0, 10.0);
    p.link_min_mm        = Na__Clamp(v[NAPC_CP_LINK_MIN_MM], 1.0, 1000.0);
    p.link_max_mm        = Na__Clamp(v[NAPC_CP_LINK_MAX_MM], p.link_min_mm, 2000.0);
    p.cluster_min_points = static_cast<int>(Na__Clamp(v[NAPC_CP_CLUSTER_MIN_POINTS], 0.0, 100000.0));
    p.cluster_max_mm     = Na__Clamp(v[NAPC_CP_CLUSTER_MAX_MM], 0.0, 5000.0);
    p.blowout_remove     = v[NAPC_CP_BLOWOUT_REMOVE] > 0.5;
    p.scatter_ratio      = Na__Clamp(v[NAPC_CP_SCATTER_RATIO], 1.2, 50.0);
    p.refine_enabled     = v[NAPC_CP_REFINE_ENABLED] > 0.5;
    p.refine_strength    = Na__Clamp(v[NAPC_CP_REFINE_STRENGTH], 0.0, 1.0);
    p.max_move_mm        = Na__Clamp(v[NAPC_CP_MAX_MOVE_MM], 0.0, 500.0);
    p.cell_mm            = Na__Clamp(v[NAPC_CP_CELL_MM], 10.0, 500.0);
    p.smooth_radius_mm   = Na__Clamp(v[NAPC_CP_SMOOTH_RADIUS_MM], 2.0, p.cell_mm);
    p.inlier_band        = Na__Clamp(v[NAPC_CP_INLIER_BAND], 1.0, 6.0);
    p.pass_gap_s         = Na__Clamp(v[NAPC_CP_PASS_GAP_S], 0.05, 3600.0);
    p.pass_disagree_mm   = Na__Clamp(v[NAPC_CP_PASS_DISAGREE_MM], 1.0, 500.0);
    p.doubling_hold      = v[NAPC_CP_DOUBLING_HOLD] > 0.5;
    p.sigma_fallback_mm  = Na__Clamp(v[NAPC_CP_SIGMA_FALLBACK_MM], 0.1, 100.0);
    p.density_enabled    = v[NAPC_CP_DENSITY_ENABLED] > 0.5;
    p.voxel_mm           = Na__Clamp(v[NAPC_CP_VOXEL_MM], 0.5, 1000.0);
    p.feature_factor     = Na__Clamp(v[NAPC_CP_FEATURE_FACTOR], 1.0, 10.0);
    return true;
}

// -----------------------------------------------------------------------------
// REGION | Zones
// -----------------------------------------------------------------------------
//
// Worked from the core outwards. A result at depth d (mm outside the core)
// needs other points up to d + reach. Euclidean reaches (neighbour radii,
// group sizes) are at most the same distance in the frame; reaches shaped as
// local cell blocks are scaled by the frame's rotation spread (1 when the
// model and the cloud axes agree, up to sqrt 3).
//
//   density : a voxel holds points within one voxel diagonal, which refining
//             moved at most max_move; a surface patch holds points of one cell.
//   refine  : refined positions are needed wherever density reads them.
//   surface : a point's refinement and its on-surface verdict come from its
//             cell's analysis; the scatter test reads on-surface verdicts over
//             5 x 5 x 5 coarse cells of 3 x 3 x 3 cells (up to 9 cells per axis
//             from a point in the middle coarse cell).
//   noise   : a cell's analysis reads noise verdicts over its 3 x 3 x 3 block,
//             and its noise width and borrowed planes from the blocks of the
//             thin cells up to NA_SURFACE_BORROW_REACH cells away (reach + 2).
//   spacing : a small detached group is at most cluster_max across, and its
//             neighbours are checked out to link_max.
//   knn     : a point's reference spacing reads its neighbours' spacings.
//   gather  : and their nearest neighbours must be exact.

Na__CleanZones Na__CleanZones__For(const Na__CleanParams& p, double spread) {
    Na__CleanZones z;
    const double cell = p.cell_mm * spread;
    const bool surfaces = p.refine_enabled || p.density_enabled || p.noise_enabled;
    // a voxel's points (moved at most max_move), or a surface patch's: projected
    // into one cell from at most one cell away, so within two cells (+ max_move)
    z.density = p.density_enabled ? std::max(p.voxel_mm * std::sqrt(3.0), 2.0 * cell) + (p.refine_enabled ? p.max_move_mm : 0.0) + 1.0 : 0.0;
    z.refine  = z.density;
    z.surface = surfaces ? z.refine + (p.noise_enabled ? 9.0 * cell : 0.0) : 0.0;
    z.noise   = z.surface + (surfaces ? (NA_SURFACE_BORROW_REACH + 2.0) * cell : 0.0);
    if (p.noise_enabled) {
        z.spacing = z.noise + p.cluster_max_mm + p.link_max_mm + 1.0;
        z.knn     = z.spacing + p.knn_cap_mm;
        z.gather  = z.knn + p.knn_cap_mm + 1.0;
    } else {
        z.spacing = z.knn = z.noise;
        z.gather  = z.noise + 1.0;
    }
    return z;
}

double Na__CleanRegion__RotationSpread(const Na__CleanRegion& region) {
    const double k = region.frame_per_unit > 0 ? region.frame_per_unit : 1.0;
    double spread = 1.0;
    for (int r = 0; r < 3; ++r) {
        const double row = (std::fabs(region.m[r * 3]) + std::fabs(region.m[r * 3 + 1]) + std::fabs(region.m[r * 3 + 2])) / k;
        spread = std::max(spread, row);
    }
    return std::min(spread, std::sqrt(3.0) + 1e-9);
}

// -----------------------------------------------------------------------------
// REGION | Global grid
// -----------------------------------------------------------------------------

bool Na__CleanGrid__Build(const Na__CloudPoints& points, double mm_per_unit, Na__CleanGrid& grid,
                          const std::atomic<bool>* cancel) {
    const auto start = std::chrono::steady_clock::now();
    grid = Na__CleanGrid();
    const int64_t n = points.count;
    if (n <= 0) return false;
    const float* xyz = points.xyz.data();

    // bounds (parallel)
    const unsigned slots = 64;
    std::vector<float> lo(slots * 3, 1e30f), hi(slots * 3, -1e30f);
    const int64_t chunk = (n + slots - 1) / slots;
    Na__ParallelFor(slots, 1, cancel, [&](int64_t b, int64_t e) {
        for (int64_t s = b; s < e; ++s) {
            const int64_t i0 = s * chunk, i1 = std::min(n, i0 + chunk);
            for (int64_t i = i0; i < i1; ++i) {
                for (int a = 0; a < 3; ++a) {
                    const float v = xyz[i * 3 + a];
                    lo[s * 3 + a] = std::min(lo[s * 3 + a], v);
                    hi[s * 3 + a] = std::max(hi[s * 3 + a], v);
                }
            }
        }
    });
    for (int a = 0; a < 3; ++a) {
        grid.lo[a] = 1e30f; grid.hi[a] = -1e30f;
        for (unsigned s = 0; s < slots; ++s) {
            grid.lo[a] = std::min(grid.lo[a], lo[s * 3 + a]);
            grid.hi[a] = std::max(grid.hi[a], hi[s * 3 + a]);
        }
    }

    // cell size: 250 mm, larger when the site would need more than 8M cells
    const double units_per_mm = 1.0 / mm_per_unit;
    double cell = 250.0 * units_per_mm;
    const double ex = std::max(1e-9, double(grid.hi[0]) - grid.lo[0]);
    const double ey = std::max(1e-9, double(grid.hi[1]) - grid.lo[1]);
    const double ez = std::max(1e-9, double(grid.hi[2]) - grid.lo[2]);
    while ((ex / cell + 2) * (ey / cell + 2) * (ez / cell + 2) > 8.0e6) cell *= 1.25;
    grid.cell = cell;
    for (int a = 0; a < 3; ++a) {
        grid.origin[a] = Na__FloorDiv(grid.lo[a], cell);
        grid.dims[a]   = Na__FloorDiv(grid.hi[a], cell) - grid.origin[a] + 1;
    }
    const int64_t cells = grid.dims[0] * grid.dims[1] * grid.dims[2];
    grid.start.assign(static_cast<size_t>(cells) + 1, 0);

    std::vector<uint32_t> cell_of(static_cast<size_t>(n));
    Na__ParallelFor(n, 1 << 16, cancel, [&](int64_t b, int64_t e) {
        for (int64_t i = b; i < e; ++i) {
            const int64_t cx = Na__FloorDiv(xyz[i * 3], cell) - grid.origin[0];
            const int64_t cy = Na__FloorDiv(xyz[i * 3 + 1], cell) - grid.origin[1];
            const int64_t cz = Na__FloorDiv(xyz[i * 3 + 2], cell) - grid.origin[2];
            const int64_t c = (std::min(std::max<int64_t>(cz, 0), grid.dims[2] - 1) * grid.dims[1] +
                               std::min(std::max<int64_t>(cy, 0), grid.dims[1] - 1)) * grid.dims[0] +
                              std::min(std::max<int64_t>(cx, 0), grid.dims[0] - 1);
            cell_of[static_cast<size_t>(i)] = static_cast<uint32_t>(c);
        }
    });
    Na__CheckCancel(cancel);
    for (int64_t i = 0; i < n; ++i) ++grid.start[cell_of[static_cast<size_t>(i)] + 1];
    for (int64_t c = 0; c < cells; ++c) grid.start[c + 1] += grid.start[c];
    grid.perm.resize(static_cast<size_t>(n));
    std::vector<uint32_t> cursor(grid.start.begin(), grid.start.end() - 1);
    for (int64_t i = 0; i < n; ++i) grid.perm[cursor[cell_of[static_cast<size_t>(i)]]++] = static_cast<uint32_t>(i);
    grid.build_ms = Na__MsSince(start);
    return true;
}

// -----------------------------------------------------------------------------
// REGION | Fine cells
// -----------------------------------------------------------------------------

namespace {
    const int64_t NA_BLOCK_SHIFT = 4;                 // 16 x 16 x 16 cells per block
    const int64_t NA_BLOCK_EDGE  = 1 << NA_BLOCK_SHIFT;
    const int64_t NA_BLOCK_CELLS = NA_BLOCK_EDGE * NA_BLOCK_EDGE * NA_BLOCK_EDGE;
    const int64_t NA_COORD_LIMIT = int64_t(1) << 21;  // relative cell coordinates are packed in 21 bits

    inline size_t Na__BlockIndex(const Na__CleanWork& w, int64_t x, int64_t y, int64_t z) {
        return static_cast<size_t>(((z >> NA_BLOCK_SHIFT) * w.block_dims[1] + (y >> NA_BLOCK_SHIFT)) * w.block_dims[0] + (x >> NA_BLOCK_SHIFT));
    }

    inline size_t Na__InBlock(int64_t x, int64_t y, int64_t z) {
        const int64_t m = NA_BLOCK_EDGE - 1;
        return static_cast<size_t>((((z & m) << NA_BLOCK_SHIFT) + (y & m)) << NA_BLOCK_SHIFT) + static_cast<size_t>(x & m);
    }

    // (z, y, x) packed so that numeric order is the canonical cell order.
    inline uint64_t Na__PackCell(int64_t x, int64_t y, int64_t z) {
        return (static_cast<uint64_t>(z) << 42) | (static_cast<uint64_t>(y) << 21) | static_cast<uint64_t>(x);
    }
}

bool Na__Clean__CellCoords(const Na__CleanWork& w, uint32_t cell, int64_t out[3]) {
    for (int a = 0; a < 3; ++a) out[a] = static_cast<int64_t>(w.cell_coord[size_t(cell) * 3 + a]) + w.fine_origin[a];
    return true;
}

uint32_t Na__Clean__CellAt(const Na__CleanWork& w, int64_t cx, int64_t cy, int64_t cz) {
    const int64_t x = cx - w.fine_origin[0], y = cy - w.fine_origin[1], z = cz - w.fine_origin[2];
    if (x < 0 || y < 0 || z < 0 || x >= w.fine_dims[0] || y >= w.fine_dims[1] || z >= w.fine_dims[2]) return UINT32_MAX;
    const uint32_t block = w.block_table[Na__BlockIndex(w, x, y, z)];
    if (block == UINT32_MAX) return UINT32_MAX;
    return w.block_cells[size_t(block) * NA_BLOCK_CELLS + Na__InBlock(x, y, z)];
}

size_t Na__CleanWork::MemoryBytes() const {
    return xyz.capacity() * 4 + stored.capacity() * 4 + tie.capacity() * 4 + time.capacity() * 4 + depth.capacity() * 4 +
           core.capacity() + cell.capacity() * 4 + cell_start.capacity() * 4 + cell_slot.capacity() * 4 +
           block_table.capacity() * 4 + block_cells.capacity() * 4 + cell_coord.capacity() * 4 +
           slot_cell.capacity() * 4 + cell_max_depth.capacity() * 4 + tree.MemoryBytes() + knn.capacity() * 4 +
           knn_d2.capacity() * 4 + knn_found.capacity() + spacing.capacity() * 4 + spacing_ref.capacity() * 4 +
           component.capacity() * 4 + flags.capacity() * 2 + delta.capacity() * 4 + surfaces.capacity() * sizeof(Na__CellSurface);
}

// -----------------------------------------------------------------------------
// REGION | Gather
// -----------------------------------------------------------------------------

void Na__Clean__Gather(Na__CleanWork& w) {
    const auto start = std::chrono::steady_clock::now();
    const Na__CloudPoints& cloud = *w.cloud;
    const Na__CleanGrid& grid = *w.grid;
    const Na__CleanRegion& r = w.region;
    const double k = r.frame_per_unit > 0 ? r.frame_per_unit : 1.0;
    w.units_per_mm = 1.0 / w.params.mm_per_unit;
    const double halo_frame = w.zones.gather / w.params.mm_per_unit * k;     // mm -> units -> frame
    const double frame_to_mm = w.params.mm_per_unit / k;

    // Expanded box in the frame -> its corners in local space -> local AABB.
    const double* m = r.m;
    // inverse of M = (k R): R^T / k
    double inv[9];
    for (int i = 0; i < 3; ++i) for (int j = 0; j < 3; ++j) inv[i * 3 + j] = m[j * 3 + i] / (k * k);
    double llo[3] = { 1e300, 1e300, 1e300 }, lhi[3] = { -1e300, -1e300, -1e300 };
    for (int c = 0; c < 8; ++c) {
        const double f[3] = { (c & 1) ? r.hi[0] + halo_frame : r.lo[0] - halo_frame,
                              (c & 2) ? r.hi[1] + halo_frame : r.lo[1] - halo_frame,
                              (c & 4) ? r.hi[2] + halo_frame : r.lo[2] - halo_frame };
        const double d[3] = { f[0] - r.t[0], f[1] - r.t[1], f[2] - r.t[2] };
        for (int a = 0; a < 3; ++a) {
            const double l = inv[a * 3] * d[0] + inv[a * 3 + 1] * d[1] + inv[a * 3 + 2] * d[2];
            llo[a] = std::min(llo[a], l);
            lhi[a] = std::max(lhi[a], l);
        }
    }

    // Grid cells overlapping that AABB (clamped to the cloud's grid).
    int64_t c0[3], c1[3];
    for (int a = 0; a < 3; ++a) {
        c0[a] = std::max<int64_t>(0, Na__FloorDiv(llo[a], grid.cell) - grid.origin[a]);
        c1[a] = std::min<int64_t>(grid.dims[a] - 1, Na__FloorDiv(lhi[a], grid.cell) - grid.origin[a]);
    }
    std::vector<int64_t> columns;   // (z, y) rows of cells, gathered in parallel
    if (c0[0] <= c1[0] && c0[1] <= c1[1] && c0[2] <= c1[2]) {
        for (int64_t z = c0[2]; z <= c1[2]; ++z) for (int64_t y = c0[1]; y <= c1[1]; ++y) columns.push_back(z * grid.dims[1] + y);
    }

    // Each hit carries what the later passes need (position, LAS record, time),
    // so nothing below reads the loaded cloud again: its points are stored in
    // shuffled order, so every such read would be a cache miss.
    struct Hit { float p[3]; uint32_t stored; uint32_t tie; float time; float depth; uint8_t core; };
    std::vector<std::vector<Hit>> parts(columns.size());
    const float* xyz = cloud.xyz.data();
    const bool has_index = !cloud.source_index.empty();
    const bool has_time = !cloud.time.empty();
    Na__ParallelFor(static_cast<int64_t>(columns.size()), 4, w.cancel, [&](int64_t b, int64_t e) {
        for (int64_t ci = b; ci < e; ++ci) {
            std::vector<Hit>& out = parts[static_cast<size_t>(ci)];
            const int64_t row = columns[static_cast<size_t>(ci)] * grid.dims[0];
            const uint32_t s0 = grid.start[static_cast<size_t>(row + c0[0])];
            const uint32_t s1 = grid.start[static_cast<size_t>(row + c1[0] + 1)];
            for (uint32_t s = s0; s < s1; ++s) {
                const uint32_t i = grid.perm[s];
                const double p[3] = { xyz[size_t(i) * 3], xyz[size_t(i) * 3 + 1], xyz[size_t(i) * 3 + 2] };
                double outside = 0.0;
                bool in_core = true, in_halo = true;
                for (int a = 0; a < 3; ++a) {
                    const double f = m[a * 3] * p[0] + m[a * 3 + 1] * p[1] + m[a * 3 + 2] * p[2] + r.t[a];
                    const double below = r.lo[a] - f, above = f - r.hi[a];
                    if (below > halo_frame || above > halo_frame) { in_halo = false; break; }
                    outside = std::max(outside, std::max(below, above));
                    if (r.half_open ? (f < r.lo[a] || f >= r.hi[a]) : (f < r.lo[a] || f > r.hi[a])) in_core = false;
                }
                if (!in_halo) continue;
                Hit hit;
                std::memcpy(hit.p, xyz + size_t(i) * 3, 12);
                hit.stored = i;
                hit.tie = has_index ? cloud.source_index[i] : i;
                hit.time = has_time ? cloud.time[i] : 0.0f;
                hit.core = in_core ? 1 : 0;
                hit.depth = in_core ? 0.0f : static_cast<float>(std::max(outside * frame_to_mm, 1e-6));
                out.push_back(hit);
            }
        }
    });

    // Gather order: parts in column order, hits in scan order ('at').
    const int64_t part_count = static_cast<int64_t>(parts.size());
    std::vector<size_t> part_start(parts.size() + 1, 0);
    for (size_t pk = 0; pk < parts.size(); ++pk) part_start[pk + 1] = part_start[pk] + parts[pk].size();
    const size_t total = part_start.back();
    if (total >= UINT32_MAX) throw std::bad_alloc();

    // Fine cell grid over what was gathered.
    w.fine = w.params.cell_mm * w.units_per_mm;
    float plo[3] = { 1e30f, 1e30f, 1e30f }, phi[3] = { -1e30f, -1e30f, -1e30f };
    {
        std::vector<float> part_lo(parts.size() * 3, 1e30f), part_hi(parts.size() * 3, -1e30f);
        Na__ParallelFor(part_count, 16, w.cancel, [&](int64_t b, int64_t e) {
            for (int64_t pk = b; pk < e; ++pk) {
                for (const Hit& h : parts[static_cast<size_t>(pk)]) {
                    for (int a = 0; a < 3; ++a) {
                        part_lo[size_t(pk) * 3 + a] = std::min(part_lo[size_t(pk) * 3 + a], h.p[a]);
                        part_hi[size_t(pk) * 3 + a] = std::max(part_hi[size_t(pk) * 3 + a], h.p[a]);
                    }
                }
            }
        });
        for (size_t pk = 0; pk < parts.size(); ++pk) {
            for (int a = 0; a < 3; ++a) { plo[a] = std::min(plo[a], part_lo[pk * 3 + a]); phi[a] = std::max(phi[a], part_hi[pk * 3 + a]); }
        }
    }
    int64_t blocks = 1;
    for (int a = 0; a < 3; ++a) {
        w.fine_origin[a] = total ? Na__FloorDiv(plo[a], w.fine) - 1 : 0;      // one empty cell of margin each side
        w.fine_dims[a]   = total ? Na__FloorDiv(phi[a], w.fine) - w.fine_origin[a] + 2 : 1;
        if (w.fine_dims[a] >= NA_COORD_LIMIT) throw std::bad_alloc();       // region far too large for this cell size
        w.block_dims[a]  = (w.fine_dims[a] + NA_BLOCK_EDGE - 1) / NA_BLOCK_EDGE;
        blocks *= w.block_dims[a];
    }
    if (blocks > 64ll * 1024 * 1024) throw std::bad_alloc();

    // Occupied cells: blocks allocated where points are, cells marked, then
    // numbered in canonical (z, y, x) order.
    std::vector<int32_t> rel(total * 3);
    Na__ParallelFor(part_count, 16, w.cancel, [&](int64_t b, int64_t e) {
        for (int64_t pk = b; pk < e; ++pk) {
            size_t at = part_start[static_cast<size_t>(pk)];
            for (const Hit& h : parts[static_cast<size_t>(pk)]) {
                rel[at * 3]     = static_cast<int32_t>(Na__FloorDiv(h.p[0], w.fine) - w.fine_origin[0]);
                rel[at * 3 + 1] = static_cast<int32_t>(Na__FloorDiv(h.p[1], w.fine) - w.fine_origin[1]);
                rel[at * 3 + 2] = static_cast<int32_t>(Na__FloorDiv(h.p[2], w.fine) - w.fine_origin[2]);
                ++at;
            }
        }
    });
    w.block_table.assign(static_cast<size_t>(blocks), UINT32_MAX);
    w.block_cells.clear();
    for (size_t at = 0; at < total; ++at) {
        const int64_t x = rel[at * 3], y = rel[at * 3 + 1], z = rel[at * 3 + 2];
        uint32_t& block = w.block_table[Na__BlockIndex(w, x, y, z)];
        if (block == UINT32_MAX) {
            block = static_cast<uint32_t>(w.block_cells.size() / NA_BLOCK_CELLS);
            w.block_cells.resize(w.block_cells.size() + NA_BLOCK_CELLS, UINT32_MAX);
        }
        w.block_cells[size_t(block) * NA_BLOCK_CELLS + Na__InBlock(x, y, z)] = 0;    // occupied
    }
    Na__CheckCancel(w.cancel);
    std::vector<uint64_t> keys;
    for (size_t bz = 0; bz < size_t(w.block_dims[2]); ++bz) {
        for (size_t by = 0; by < size_t(w.block_dims[1]); ++by) {
            for (size_t bx = 0; bx < size_t(w.block_dims[0]); ++bx) {
                const uint32_t block = w.block_table[(bz * w.block_dims[1] + by) * w.block_dims[0] + bx];
                if (block == UINT32_MAX) continue;
                const uint32_t* entry = &w.block_cells[size_t(block) * NA_BLOCK_CELLS];
                for (int64_t e = 0; e < NA_BLOCK_CELLS; ++e) {
                    if (entry[e] == UINT32_MAX) continue;
                    const int64_t lx = e & (NA_BLOCK_EDGE - 1), ly = (e >> NA_BLOCK_SHIFT) & (NA_BLOCK_EDGE - 1), lz = e >> (2 * NA_BLOCK_SHIFT);
                    keys.push_back(Na__PackCell(int64_t(bx) * NA_BLOCK_EDGE + lx, int64_t(by) * NA_BLOCK_EDGE + ly, int64_t(bz) * NA_BLOCK_EDGE + lz));
                }
            }
        }
    }
    std::sort(keys.begin(), keys.end());
    const int64_t cells = static_cast<int64_t>(keys.size());
    if (cells >= UINT32_MAX) throw std::bad_alloc();
    w.cell_coord.resize(static_cast<size_t>(cells) * 3);
    const uint64_t mask = static_cast<uint64_t>(NA_COORD_LIMIT - 1);
    for (int64_t c = 0; c < cells; ++c) {
        const int64_t x = static_cast<int64_t>(keys[size_t(c)] & mask), y = static_cast<int64_t>((keys[size_t(c)] >> 21) & mask),
                      z = static_cast<int64_t>(keys[size_t(c)] >> 42);
        w.cell_coord[size_t(c) * 3] = static_cast<int32_t>(x);
        w.cell_coord[size_t(c) * 3 + 1] = static_cast<int32_t>(y);
        w.cell_coord[size_t(c) * 3 + 2] = static_cast<int32_t>(z);
        w.block_cells[size_t(w.block_table[Na__BlockIndex(w, x, y, z)]) * NA_BLOCK_CELLS + Na__InBlock(x, y, z)] = static_cast<uint32_t>(c);
    }

    // Counting sort by fine cell, then by tie inside each cell: canonical order.
    std::vector<uint32_t> cell_of(total);
    Na__ParallelFor(static_cast<int64_t>(total), 1 << 15, w.cancel, [&](int64_t b, int64_t e) {
        for (int64_t at = b; at < e; ++at) {
            const int64_t x = rel[size_t(at) * 3], y = rel[size_t(at) * 3 + 1], z = rel[size_t(at) * 3 + 2];
            cell_of[size_t(at)] = w.block_cells[size_t(w.block_table[Na__BlockIndex(w, x, y, z)]) * NA_BLOCK_CELLS + Na__InBlock(x, y, z)];
        }
    });
    std::vector<int32_t>().swap(rel);
    std::vector<uint32_t> counts(static_cast<size_t>(cells) + 1, 0);
    for (size_t at = 0; at < total; ++at) ++counts[cell_of[at] + 1];
    for (int64_t c = 0; c < cells; ++c) counts[c + 1] += counts[c];
    w.cell_start = counts;
    std::vector<uint32_t> order(total);
    {
        std::vector<uint32_t> cursor(counts.begin(), counts.end() - 1);
        for (size_t at = 0; at < total; ++at) order[cursor[cell_of[at]]++] = static_cast<uint32_t>(at);
    }
    std::vector<const Hit*> flat(total);
    {
        size_t at = 0;
        for (const auto& part : parts) for (const Hit& h : part) flat[at++] = &h;
    }
    Na__ParallelFor(cells, 4096, w.cancel, [&](int64_t b, int64_t e) {
        for (int64_t c = b; c < e; ++c) {
            const uint32_t s0 = w.cell_start[c], s1 = w.cell_start[c + 1];
            if (s1 - s0 > 1) {
                std::sort(order.begin() + s0, order.begin() + s1,
                          [&](uint32_t a, uint32_t b2) { return flat[a]->tie < flat[b2]->tie; });
            }
        }
    });

    w.n = static_cast<uint32_t>(total);
    w.xyz.resize(total * 3);
    w.stored.resize(total);
    w.tie.resize(total);
    w.depth.resize(total);
    w.core.resize(total);
    w.cell.resize(total);
    if (has_time) w.time.resize(total); else w.time.clear();
    Na__ParallelFor(static_cast<int64_t>(total), 1 << 15, w.cancel, [&](int64_t b, int64_t e) {
        for (int64_t jj = b; jj < e; ++jj) {
            const size_t j = static_cast<size_t>(jj);
            const Hit* h = flat[order[j]];
            std::memcpy(&w.xyz[j * 3], h->p, 12);
            w.stored[j] = h->stored;
            w.tie[j]    = h->tie;
            w.depth[j]  = h->depth;
            w.core[j]   = h->core;
            w.cell[j]   = cell_of[order[j]];
            if (has_time) w.time[j] = h->time;
        }
    });

    // Every cell is occupied, so a cell's slot (surface analysis storage) is the cell itself.
    w.cell_slot.resize(static_cast<size_t>(cells));
    w.slot_cell.resize(static_cast<size_t>(cells));
    w.cell_max_depth.assign(static_cast<size_t>(cells), 0.0f);
    Na__ParallelFor(cells, 4096, w.cancel, [&](int64_t b, int64_t e) {
        for (int64_t c = b; c < e; ++c) {
            w.cell_slot[size_t(c)] = w.slot_cell[size_t(c)] = static_cast<uint32_t>(c);
            float deepest = 0.0f;
            for (uint32_t j = w.cell_start[c]; j < w.cell_start[c + 1]; ++j) deepest = std::max(deepest, w.depth[j]);
            w.cell_max_depth[size_t(c)] = deepest;
        }
    });
    w.ms_gather = Na__MsSince(start);

    const auto index_start = std::chrono::steady_clock::now();
    w.tree.Build(w.xyz.data(), w.tie.data(), w.n);
    w.ms_index = Na__MsSince(index_start);

    w.flags.assign(total, 0);
    w.delta.assign(total * 3, 0.0f);
    w.gathered = true;
    w.noise_done = w.surface_done = w.refine_done = w.density_done = false;
}
