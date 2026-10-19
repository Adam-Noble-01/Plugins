// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - CLEANING PIPELINE
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__CleanPipeline__.cpp
// PURPOSE    : See the header.
//
// =============================================================================

#include "Na__PointCloudViewer__NativeEngine__CleanPipeline__.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <stdexcept>
#include <string>

namespace {

    double Na__MsSince(std::chrono::steady_clock::time_point start) {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    }

    // The values each stage's result depends on (besides the stages before it).
    std::vector<double> Na__NoiseKey(const Na__CleanParams& p) {
        return { double(p.noise_enabled), p.iso_ratio, p.iso_min_mm, p.knn_cap_mm, p.link_factor,
                 p.link_min_mm, p.link_max_mm, double(p.cluster_min_points), p.cluster_max_mm };
    }
    std::vector<double> Na__SurfaceKey(const Na__CleanParams& p) {
        return { p.sigma_fallback_mm, p.pass_gap_s, p.pass_disagree_mm };
    }
    std::vector<double> Na__RefineKey(const Na__CleanParams& p) {
        // density_enabled: the local fit also runs (for its slope) when only density is on
        return { double(p.refine_enabled), double(p.density_enabled), p.refine_strength, p.max_move_mm, p.smooth_radius_mm,
                 p.inlier_band, double(p.doubling_hold), double(p.blowout_remove), p.scatter_ratio };
    }
    std::vector<double> Na__DensityKey(const Na__CleanParams& p) {
        return { double(p.density_enabled), p.voxel_mm, p.feature_factor };
    }
    std::vector<double> Na__ZoneKey(const Na__CleanZones& z) {
        return { z.density, z.refine, z.surface, z.noise, z.spacing, z.knn };
    }
    bool Na__SameRegion(const Na__CleanRegion& a, const Na__CleanRegion& b) {
        return std::memcmp(a.m, b.m, sizeof(a.m)) == 0 && std::memcmp(a.t, b.t, sizeof(a.t)) == 0 &&
               std::memcmp(a.lo, b.lo, sizeof(a.lo)) == 0 && std::memcmp(a.hi, b.hi, sizeof(a.hi)) == 0 &&
               a.frame_per_unit == b.frame_per_unit && a.half_open == b.half_open;
    }

} // namespace

// -----------------------------------------------------------------------------
// REGION | One region
// -----------------------------------------------------------------------------

void Na__CleanPipeline__RunRegion(Na__CleanWork& w, const Na__CleanParams& params) {
    const double spread = Na__CleanRegion__RotationSpread(w.region);
    const Na__CleanZones zones = Na__CleanZones__For(params, spread);
    // Gather as if every filter were on, so switching one on or off re-uses the gather.
    Na__CleanParams all = params;
    all.noise_enabled = all.refine_enabled = all.density_enabled = true;
    const double halo = Na__CleanZones__For(all, spread).gather;

    w.reused = 0;
    const bool same_gather = w.gathered && Na__SameRegion(w.region, w.key_region) && w.key_cell == params.cell_mm &&
                             w.key_mpu == params.mm_per_unit && w.key_halo >= halo;
    w.params = params;
    if (!same_gather) {
        w.gathered = w.noise_done = w.surface_done = w.refine_done = w.density_done = false;
        w.zones = zones;
        w.zones.gather = halo;
        Na__Clean__Gather(w);
        w.key_region = w.region;
        w.key_halo = halo;
        w.key_cell = params.cell_mm;
        w.key_mpu = params.mm_per_unit;
        w.key_zones.clear();
    } else {
        w.reused |= 1;
    }
    const double gathered_halo = w.key_halo;
    w.zones = zones;
    w.zones.gather = gathered_halo;

    const std::vector<double> zone_key = Na__ZoneKey(zones);
    const bool zones_same = w.key_zones == zone_key;
    if (!zones_same) w.noise_done = w.surface_done = w.refine_done = w.density_done = false;

    // 1 noise
    const std::vector<double> noise_key = Na__NoiseKey(params);
    if (!(w.noise_done && w.key_noise == noise_key)) {
        if (params.noise_enabled) {
            Na__Clean__Noise(w);
        } else {
            for (uint32_t i = 0; i < w.n; ++i) w.flags[i] &= static_cast<uint16_t>(~(NA_CF_REMOVED_ISOLATED | NA_CF_REMOVED_CLUSTER));
            std::vector<float>().swap(w.spacing_ref);
            w.ms_noise = 0.0;
            w.noise_done = true;
        }
        w.key_noise = noise_key;
        w.surface_done = w.refine_done = w.density_done = false;
    } else {
        w.reused |= 2;
    }

    // 2 surfaces
    const std::vector<double> surface_key = Na__SurfaceKey(params);
    const bool need_surfaces = params.noise_enabled || params.refine_enabled || params.density_enabled;
    if (!(w.surface_done && w.key_surface == surface_key)) {
        if (need_surfaces) Na__Clean__Surfaces(w);
        else { w.surfaces.assign(w.slot_cell.size(), Na__CellSurface()); w.ms_surface = 0.0; w.surface_done = true; }
        w.key_surface = surface_key;
        w.refine_done = w.density_done = false;
    } else {
        w.reused |= 4;
    }

    // 3 refine (+ scatter candidates)
    const std::vector<double> refine_key = Na__RefineKey(params);
    if (!(w.refine_done && w.key_refine == refine_key)) {
        Na__Clean__Refine(w);
        w.key_refine = refine_key;
        w.density_done = false;
    } else {
        w.reused |= 8;
    }

    // 4 density
    const std::vector<double> density_key = Na__DensityKey(params);
    if (!(w.density_done && w.key_density == density_key)) {
        Na__Clean__Density(w);
        w.key_density = density_key;
    }
    w.key_zones = zone_key;
}

// -----------------------------------------------------------------------------
// REGION | Whole cloud in tiles
// -----------------------------------------------------------------------------

void Na__CleanPipeline__RunFull(const std::shared_ptr<const Na__CloudPoints>& cloud, const Na__CleanGrid& grid,
                                const Na__CleanParams& params, const std::atomic<bool>* cancel,
                                std::atomic<int64_t>* progress_done, std::atomic<int64_t>* progress_total,
                                Na__CleanFullResult& result) {
    const auto start = std::chrono::steady_clock::now();
    const int64_t n = cloud->count;
    result.flags.assign(static_cast<size_t>(n), 0);
    result.delta.assign(static_cast<size_t>(n) * 3, 0.0f);
    result.tiles = 0;
    result.max_tile_points = 0;
    if (progress_total) progress_total->store(n);
    if (progress_done) progress_done->store(0);

    // Tiles: cubes of whole grid cells, 16 m at most. A cube holding more than
    // ~2.5 M points (counted from the global grid) is halved along every axis
    // longer than 2 m, again and again, until each part fits or is 2 m across.
    // Dense spots get small tiles and the rest of the site keeps large ones:
    // every tile re-reads a ~1.35 m margin, so one tile size for the whole
    // site, set by its densest spot, read the cloud many times over (a 39 M
    // point site fell to 1181 tiles of ~2 m). Results do not depend on the
    // tiling (section 22.3 of the architecture notes); only the time does.
    const double upm = 1.0 / params.mm_per_unit;
    const int64_t limit = 2500000;
    const double g0[3] = { grid.origin[0] * grid.cell, grid.origin[1] * grid.cell, grid.origin[2] * grid.cell };
    const int64_t top = std::max<int64_t>(1, static_cast<int64_t>(std::floor(16000.0 * upm / grid.cell)));
    const int64_t smallest = std::max<int64_t>(1, static_cast<int64_t>(std::ceil(2000.0 * upm / grid.cell)));
    struct Tile { int64_t c0[3], c1[3]; int64_t count; };
    // points in grid cells [c0, c1): the cells of one x-row are consecutive in grid.start
    auto count_in = [&](const int64_t c0[3], const int64_t c1[3]) {
        int64_t total = 0;
        for (int64_t z = c0[2]; z < c1[2]; ++z) {
            for (int64_t y = c0[1]; y < c1[1]; ++y) {
                const int64_t row = (z * grid.dims[1] + y) * grid.dims[0];
                total += static_cast<int64_t>(grid.start[static_cast<size_t>(row + c1[0])]) - grid.start[static_cast<size_t>(row + c0[0])];
            }
        }
        return total;
    };
    std::vector<Tile> tiles, pending;
    int64_t tdims[3];
    for (int a = 0; a < 3; ++a) tdims[a] = (grid.dims[a] + top - 1) / top;
    for (int64_t tz = tdims[2] - 1; tz >= 0; --tz) {          // pushed in reverse: popped in z, y, x order
        for (int64_t ty = tdims[1] - 1; ty >= 0; --ty) {
            for (int64_t tx = tdims[0] - 1; tx >= 0; --tx) {
                Tile t;
                const int64_t at[3] = { tx, ty, tz };
                for (int a = 0; a < 3; ++a) { t.c0[a] = at[a] * top; t.c1[a] = std::min(grid.dims[a], t.c0[a] + top); }
                t.count = count_in(t.c0, t.c1);
                if (t.count > 0) pending.push_back(t);
            }
        }
    }
    while (!pending.empty()) {
        const Tile t = pending.back();
        pending.pop_back();
        bool split[3];
        bool any = false;
        for (int a = 0; a < 3; ++a) { split[a] = t.c1[a] - t.c0[a] > smallest; any = any || split[a]; }
        if (t.count <= limit || !any) { tiles.push_back(t); continue; }
        std::vector<Tile> parts;
        for (int hz = 0; hz < (split[2] ? 2 : 1); ++hz) {
            for (int hy = 0; hy < (split[1] ? 2 : 1); ++hy) {
                for (int hx = 0; hx < (split[0] ? 2 : 1); ++hx) {
                    const int h[3] = { hx, hy, hz };
                    Tile p;
                    for (int a = 0; a < 3; ++a) {
                        const int64_t mid = t.c0[a] + (t.c1[a] - t.c0[a] + 1) / 2;
                        p.c0[a] = !split[a] ? t.c0[a] : (h[a] ? mid : t.c0[a]);
                        p.c1[a] = !split[a] ? t.c1[a] : (h[a] ? t.c1[a] : mid);
                    }
                    p.count = count_in(p.c0, p.c1);
                    if (p.count > 0) parts.push_back(p);
                }
            }
        }
        for (auto it = parts.rbegin(); it != parts.rend(); ++it) pending.push_back(*it);
    }
    Na__CheckCancel(cancel);

    Na__CleanWork work;
    work.cloud = cloud;
    work.grid = &grid;
    work.cancel = cancel;
    int64_t done = 0;
    for (const Tile& t : tiles) {
        Na__CheckCancel(cancel);
        Na__CleanRegion region;
        for (int a = 0; a < 3; ++a) {
            // the first and last tiles along an axis reach one cell past the grid, so
            // a point on either edge of it is inside a core whatever the rounding
            region.lo[a] = g0[a] + (t.c0[a] > 0 ? t.c0[a] : t.c0[a] - 1) * grid.cell;
            region.hi[a] = g0[a] + (t.c1[a] < grid.dims[a] ? t.c1[a] : t.c1[a] + 1) * grid.cell;
        }
        region.half_open = true;
        work.region = region;
        work.gathered = false;
        Na__CleanPipeline__RunRegion(work, params);
        result.max_tile_points = std::max<int64_t>(result.max_tile_points, work.n);
        result.peak_work_bytes = std::max(result.peak_work_bytes, work.MemoryBytes());
        for (uint32_t i = 0; i < work.n; ++i) {
            if (!work.core[i]) continue;
            const uint32_t s = work.stored[i];
            result.flags[s] = work.flags[i];
            std::memcpy(&result.delta[size_t(s) * 3], &work.delta[size_t(i) * 3], 12);
            ++done;
        }
        ++result.tiles;
        if (progress_done) progress_done->store(done);
    }
    // Every point is in exactly one tile's core; anything else is a bug, and an
    // export that silently left points uncleaned would not match the preview.
    if (done != n) {
        throw std::runtime_error("the tiles covered " + std::to_string(done) + " of " + std::to_string(n) +
                                 " points (internal error)");
    }
    result.ms = Na__MsSince(start);
}
