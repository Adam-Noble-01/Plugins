// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - C API IMPLEMENTATION
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__Api__.cpp
// PURPOSE    : Exported functions. Validates input, owns the shared frame
//              buffers and the worker pool, and turns every failure into a
//              status code + a plain-English message (never an exception
//              across the DLL boundary).
//
// =============================================================================

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include "Na__PointCloudViewer__NativeEngine__Api__.h"
#include "Na__PointCloudViewer__NativeEngine__BoxFilter__.hpp"
#include "Na__PointCloudViewer__NativeEngine__LasFile__.hpp"
#include "Na__PointCloudViewer__NativeEngine__LasImport__.hpp"
#include "Na__PointCloudViewer__NativeEngine__LazConvert__.hpp"
#include "Na__PointCloudViewer__NativeEngine__PngWriter__.hpp"
#include "Na__PointCloudViewer__NativeEngine__PointCache__.hpp"
#include "Na__PointCloudViewer__NativeEngine__Rasterizer__.hpp"
#include "Na__PointCloudViewer__NativeEngine__ThreadPool__.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <vector>

namespace {

    std::mutex        g_render_mutex;
    Na__ThreadPool*   g_pool = nullptr;      // heap only - see ThreadPool header
    Na__FrameBuffers* g_buffers = nullptr;
    thread_local std::string g_last_error;

    unsigned Na__WantedThreads() {
        const unsigned hw = std::thread::hardware_concurrency();
        return std::max(1u, std::min(32u, hw == 0 ? 4u : hw));
    }

    Na__ThreadPool& Na__Pool() {
        if (!g_pool) g_pool = new Na__ThreadPool(Na__WantedThreads());
        return *g_pool;
    }

    int32_t Na__Fail(const char* message, int32_t code) {
        g_last_error = message;
        return code;
    }

} // namespace

// -----------------------------------------------------------------------------
// REGION | Info
// -----------------------------------------------------------------------------

NAPC_API int32_t napc_abi_version(void) {
    return NAPC_ABI_VERSION;
}

NAPC_API int32_t napc_thread_count(void) {
    return static_cast<int32_t>(Na__WantedThreads());
}

NAPC_API const char* napc_last_error(void) {
    return g_last_error.c_str();
}

// -----------------------------------------------------------------------------
// REGION | Clouds
// -----------------------------------------------------------------------------

NAPC_API void* napc_cloud_create_ex(const float* xyz, const uint8_t* rgb, const uint32_t* source_index,
                                   const float* time, double time_base, int64_t count) {
    if (!xyz || !rgb || count <= 0) {
        Na__Fail("No point data was supplied.", -1);
        return nullptr;
    }
    try {
        std::shared_ptr<Na__CloudPoints> points(new Na__CloudPoints());
        points->count = count;
        points->xyz.assign(xyz, xyz + count * 3);
        points->bgra.resize(static_cast<size_t>(count));
        for (int64_t i = 0; i < count; ++i) {
            points->bgra[i] = 0xFF000000u | (static_cast<uint32_t>(rgb[i * 3]) << 16) |
                              (static_cast<uint32_t>(rgb[i * 3 + 1]) << 8) | rgb[i * 3 + 2];
        }
        if (source_index) points->source_index.assign(source_index, source_index + count);
        if (time) {
            points->time.assign(time, time + count);
            points->time_base = time_base;
        }
        std::unique_ptr<Na__PointCloud> cloud(new Na__PointCloud());
        cloud->count  = count;
        cloud->points = std::move(points);
        return cloud.release();
    } catch (const std::bad_alloc&) {
        Na__Fail("Not enough memory to hold the point cloud in the native engine.", -2);
        return nullptr;
    }
}

NAPC_API void* napc_cloud_create(const float* xyz, const uint8_t* rgb, int64_t count) {
    return napc_cloud_create_ex(xyz, rgb, nullptr, nullptr, 0.0, count);
}

NAPC_API void napc_cloud_destroy(void* cloud) {
    delete static_cast<Na__PointCloud*>(cloud);
}

NAPC_API int32_t napc_cloud_info(void* cloud_handle, double* out, int32_t out_count) {
    const Na__PointCloud* cloud = static_cast<const Na__PointCloud*>(cloud_handle);
    if (!cloud || !cloud->points || !out || out_count < 4) return Na__Fail("Cloud info is missing arguments.", -1);
    out[0] = static_cast<double>(cloud->count);
    out[1] = cloud->points->source_index.empty() ? 0 : 1;
    out[2] = cloud->points->time.empty() ? 0 : 1;
    out[3] = cloud->points->time_base;
    return 0;
}

NAPC_API int32_t napc_cloud_read(void* cloud_handle, int64_t first, int64_t count, float* xyz, uint32_t* bgra,
                                 uint32_t* source_index, float* time) {
    const Na__PointCloud* cloud = static_cast<const Na__PointCloud*>(cloud_handle);
    if (!cloud || !cloud->points) return Na__Fail("No point cloud was given.", -1);
    const Na__CloudPoints& points = *cloud->points;
    if (first < 0 || count < 0 || first + count > points.count) return Na__Fail("The requested range is outside the cloud.", -2);
    const size_t begin = static_cast<size_t>(first), n = static_cast<size_t>(count);
    if (xyz)  std::memcpy(xyz, points.xyz.data() + begin * 3, n * 12);
    if (bgra) std::memcpy(bgra, points.bgra.data() + begin, n * 4);
    if (source_index && !points.source_index.empty()) std::memcpy(source_index, points.source_index.data() + begin, n * 4);
    if (time && !points.time.empty()) std::memcpy(time, points.time.data() + begin, n * 4);
    return 0;
}

// -----------------------------------------------------------------------------
// REGION | Render
// -----------------------------------------------------------------------------

namespace {

    // The PNG and the stats every render writes. Caller holds the render mutex.
    int32_t Na__FinishRender(const double* frame, const char* path_utf8, const Na__RasterStats& raster,
                             std::chrono::steady_clock::time_point total_start, double* stats, int32_t stat_count) {
        Na__PngTimings png;
        std::string error;
        const int width = static_cast<int>(frame[NAPC_P_WIDTH]);
        const int height = static_cast<int>(frame[NAPC_P_HEIGHT]);
        if (!Na__Png__WriteStored(Na__Utf8ToWide(path_utf8), g_buffers->raw.data(), g_buffers->raw.size(),
                                  width, height, Na__Pool(), g_buffers->file, png, error)) {
            return Na__Fail(error.c_str(), -5);
        }
        if (stats && stat_count >= NAPC_S_COUNT) {
            stats[NAPC_S_POINTS_TESTED]    = static_cast<double>(raster.points_tested);
            stats[NAPC_S_POINTS_ON_SCREEN] = static_cast<double>(raster.points_on_screen);
            stats[NAPC_S_THREADS]          = static_cast<double>(Na__Pool().Size());
            stats[NAPC_S_CLEAR_MS]         = raster.clear_ms;
            stats[NAPC_S_RASTER_MS]        = raster.raster_ms;
            stats[NAPC_S_RESOLVE_MS]       = raster.resolve_ms;
            stats[NAPC_S_ENCODE_MS]        = png.encode_ms;
            stats[NAPC_S_WRITE_MS]         = png.write_ms;
            stats[NAPC_S_TOTAL_MS]         = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - total_start).count();
            stats[NAPC_S_PNG_BYTES]        = static_cast<double>(png.bytes);
        }
        return 0;
    }

} // namespace

NAPC_API int32_t napc_render_png(void* cloud_handle, const double* params, int32_t param_count,
                                 const char* path_utf8, double* stats, int32_t stat_count) {
    if (!cloud_handle) return Na__Fail("No point cloud is loaded in the native engine.", -1);
    if (!params || param_count < NAPC_P_BASE_COUNT) return Na__Fail("Render parameters are missing.", -2);
    if (!path_utf8) return Na__Fail("No output path was given.", -3);

    const auto total_start = std::chrono::steady_clock::now();
    std::lock_guard<std::mutex> lock(g_render_mutex);
    try {
        if (!g_buffers) g_buffers = new Na__FrameBuffers();
        const Na__PointCloud& cloud = *static_cast<const Na__PointCloud*>(cloud_handle);

        Na__RasterStats raster;
        std::string error;
        if (!Na__Raster__Render(cloud, params, param_count, Na__Pool(), *g_buffers, raster, error)) return Na__Fail(error.c_str(), -4);
        return Na__FinishRender(params, path_utf8, raster, total_start, stats, stat_count);
    } catch (const std::bad_alloc&) {
        return Na__Fail("Not enough memory for the render image.", -6);
    } catch (...) {
        return Na__Fail("The native renderer failed unexpectedly.", -7);
    }
}

NAPC_API int32_t napc_render_layers_png(void* const* clouds, int32_t layer_count, const double* params,
                                        int32_t param_stride, double total_budget, const char* path_utf8,
                                        double* stats, int32_t stat_count, double* layer_stats, int32_t layer_stat_count) {
    if (!clouds || layer_count < 1) return Na__Fail("No point clouds were given to render.", -1);
    if (layer_count > NAPC_MAX_LAYERS) return Na__Fail("Too many point clouds for one frame.", -1);
    for (int32_t i = 0; i < layer_count; ++i) {
        if (!clouds[i]) return Na__Fail("A point cloud to render is not loaded in the native engine.", -1);
    }
    if (!params || param_stride < NAPC_P_BASE_COUNT) return Na__Fail("Render parameters are missing.", -2);
    if (!path_utf8) return Na__Fail("No output path was given.", -3);

    const auto total_start = std::chrono::steady_clock::now();
    std::lock_guard<std::mutex> lock(g_render_mutex);
    try {
        if (!g_buffers) g_buffers = new Na__FrameBuffers();
        std::vector<Na__RenderLayer> layers(static_cast<size_t>(layer_count));
        for (int32_t i = 0; i < layer_count; ++i) {
            layers[i].cloud  = static_cast<const Na__PointCloud*>(clouds[i]);
            layers[i].params = params + static_cast<size_t>(i) * static_cast<size_t>(param_stride);
            layers[i].param_count = param_stride;
        }
        const int64_t budget = total_budget >= 9.0e18 ? std::numeric_limits<int64_t>::max()
                                                      : (total_budget > 0.0 ? static_cast<int64_t>(total_budget) : 0);
        Na__RasterStats raster;
        std::vector<Na__LayerStats> per_layer;
        std::string error;
        if (!Na__Raster__RenderLayers(layers.data(), layer_count, budget, Na__Pool(), *g_buffers, raster, per_layer, error)) {
            return Na__Fail(error.c_str(), -4);
        }
        const int32_t code = Na__FinishRender(params, path_utf8, raster, total_start, stats, stat_count);
        if (code < 0) return code;
        if (layer_stats && layer_stat_count >= layer_count * NAPC_LS_COUNT) {
            for (int32_t i = 0; i < layer_count; ++i) {
                double* out = layer_stats + static_cast<size_t>(i) * NAPC_LS_COUNT;
                out[NAPC_LS_DEMAND]    = static_cast<double>(per_layer[i].demand);
                out[NAPC_LS_SHARE]     = static_cast<double>(per_layer[i].share);
                out[NAPC_LS_TESTED]    = static_cast<double>(per_layer[i].tested);
                out[NAPC_LS_ON_SCREEN] = static_cast<double>(per_layer[i].on_screen);
            }
        }
        return 0;
    } catch (const std::bad_alloc&) {
        return Na__Fail("Not enough memory for the render image.", -6);
    } catch (...) {
        return Na__Fail("The native renderer failed unexpectedly.", -7);
    }
}

// -----------------------------------------------------------------------------
// REGION | Crop and Cut: how many points the boxes remove
// -----------------------------------------------------------------------------

// The same Verdict() as the export (both /fp:precise), so the dialog's figures
// are exactly what Remove Points & Export LAS removes. Runs on the render pool,
// under the render mutex (the pool takes one task at a time).
NAPC_API int32_t napc_box_count(void* cloud_handle, const double* boxes, int32_t box_count, double* out, int32_t out_count) {
    const Na__PointCloud* cloud = static_cast<const Na__PointCloud*>(cloud_handle);
    if (!cloud || !cloud->points) return Na__Fail("No point cloud is loaded in the native engine.", -1);
    if (!boxes || box_count < NAPC_BOXES_COUNT || !out || out_count < 4) return Na__Fail("The box count is missing arguments.", -2);
    Na__BoxFilter filter;
    if (!Na__BoxFilter__Read(boxes, boxes + 12, filter)) return Na__Fail("A Crop and Cut box is not a valid box.", -3);
    std::lock_guard<std::mutex> lock(g_render_mutex);
    try {
        const Na__CloudPoints& points = *cloud->points;
        const int64_t count = points.count;
        const float* xyz = points.xyz.data();
        Na__ThreadPool& pool = Na__Pool();
        const unsigned workers = pool.Size();
        std::vector<int64_t> outside(workers, 0), inside(workers, 0);
        if (filter.Active()) {
            pool.Run([&](unsigned worker, unsigned total) {
                const int64_t chunk = (count + total - 1) / total;
                const int64_t begin = std::min<int64_t>(count, chunk * worker);
                const int64_t end   = std::min<int64_t>(count, begin + chunk);
                int64_t o = 0, c = 0;
                for (int64_t i = begin; i < end; ++i) {
                    const int verdict = filter.Verdict(xyz[i * 3], xyz[i * 3 + 1], xyz[i * 3 + 2]);
                    if (verdict == NA_BOX_OUTSIDE_KEEP) ++o;
                    else if (verdict == NA_BOX_INSIDE_CUT) ++c;
                }
                outside[worker] = o;
                inside[worker] = c;
            });
        }
        int64_t removed_keep = 0, removed_cut = 0;
        for (unsigned w = 0; w < workers; ++w) { removed_keep += outside[w]; removed_cut += inside[w]; }
        out[0] = static_cast<double>(count);
        out[1] = static_cast<double>(removed_keep);
        out[2] = static_cast<double>(removed_cut);
        out[3] = static_cast<double>(count - removed_keep - removed_cut);
        return 0;
    } catch (const std::bad_alloc&) {
        return Na__Fail("Not enough memory to count the points.", -4);
    } catch (...) {
        return Na__Fail("Counting the points failed unexpectedly.", -5);
    }
}

// -----------------------------------------------------------------------------
// REGION | What is inside a box (ABI 9): the points, and points per grid cell
// -----------------------------------------------------------------------------

// Both use the box filter's own Verdict(), so a box here keeps exactly what
// napc_box_count counts, and both run on the render pool under the render
// mutex. Workers never allocate and never throw: every buffer is made first.

namespace {

    double Na__MsSinceStart(std::chrono::steady_clock::time_point start) {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    }

    // [begin, end) of one worker's slice of `count` points.
    void Na__Slice(int64_t count, unsigned worker, unsigned total, int64_t& begin, int64_t& end) {
        const int64_t chunk = (count + total - 1) / total;
        begin = std::min<int64_t>(count, chunk * worker);
        end   = std::min<int64_t>(count, begin + chunk);
    }

    void Na__WriteStats(double* stats, int32_t stat_count, double kept, double written, double max_cell, double ms) {
        if (!stats || stat_count < NAPC_BS_COUNT) return;
        stats[NAPC_BS_KEPT]     = kept;
        stats[NAPC_BS_WRITTEN]  = written;
        stats[NAPC_BS_MAX_CELL] = max_cell;
        stats[NAPC_BS_MS]       = ms;
    }

} // namespace

// Pass 1 counts what each worker's slice keeps; slices are then given their
// share of `cap` in stored order, so pass 2 copies exactly the FIRST cap kept
// points (an even sample: the store is shuffled) and stops early. No index
// list is ever held, so memory stays at the output buffers.
NAPC_API int64_t napc_box_points(void* cloud_handle, const double* boxes, int32_t box_count, double scale,
                                 double* out_xyz, uint32_t* out_bgra, int64_t cap,
                                 double* stats, int32_t stat_count) {
    const Na__PointCloud* cloud = static_cast<const Na__PointCloud*>(cloud_handle);
    if (!cloud || !cloud->points) return Na__Fail("No point cloud is loaded in the native engine.", -1);
    if (!boxes || box_count < NAPC_BOXES_COUNT || cap < 0 || (cap > 0 && !out_xyz)) return Na__Fail("The point request is missing arguments.", -2);
    if (!(std::isfinite(scale) && scale > 0.0)) return Na__Fail("The point scale must be a positive number.", -2);
    Na__BoxFilter filter;
    if (!Na__BoxFilter__Read(boxes, boxes + 12, filter)) return Na__Fail("A box is not a valid box.", -3);
    std::lock_guard<std::mutex> lock(g_render_mutex);
    try {
        const auto started = std::chrono::steady_clock::now();
        const Na__CloudPoints& points = *cloud->points;
        const int64_t count = points.count;
        const float* xyz = points.xyz.data();
        const uint32_t* bgra = points.bgra.size() == static_cast<size_t>(count) ? points.bgra.data() : nullptr;
        const bool active = filter.Active();
        Na__ThreadPool& pool = Na__Pool();
        const unsigned workers = pool.Size();
        std::vector<int64_t> kept(workers, 0), quota(workers, 0), offset(workers, 0);
        pool.Run([&](unsigned worker, unsigned total) {
            int64_t begin = 0, end = 0;
            Na__Slice(count, worker, total, begin, end);
            int64_t k = 0;
            if (!active) {
                k = end - begin;
            } else {
                for (int64_t i = begin; i < end; ++i) {
                    if (filter.Verdict(xyz[i * 3], xyz[i * 3 + 1], xyz[i * 3 + 2]) == NA_BOX_KEPT) ++k;
                }
            }
            kept[worker] = k;
        });
        int64_t all_kept = 0, left = cap, at = 0;
        for (unsigned w = 0; w < workers; ++w) {
            all_kept += kept[w];
            quota[w] = std::min<int64_t>(kept[w], left);
            offset[w] = at;
            at += quota[w];
            left -= quota[w];
        }
        const int64_t written = at;
        if (written > 0) {
            const double* m = filter.m;
            const double* t = filter.t;
            pool.Run([&](unsigned worker, unsigned total) {
                int64_t want = quota[worker];
                if (want <= 0) return;
                int64_t begin = 0, end = 0;
                Na__Slice(count, worker, total, begin, end);
                int64_t o = offset[worker];
                for (int64_t i = begin; i < end && want > 0; ++i) {
                    const float lx = xyz[i * 3], ly = xyz[i * 3 + 1], lz = xyz[i * 3 + 2];
                    if (active && filter.Verdict(lx, ly, lz) != NA_BOX_KEPT) continue;
                    const double x = lx, y = ly, z = lz;
                    out_xyz[o * 3]     = (m[0] * x + m[1] * y + m[2] * z + t[0]) * scale;
                    out_xyz[o * 3 + 1] = (m[3] * x + m[4] * y + m[5] * z + t[1]) * scale;
                    out_xyz[o * 3 + 2] = (m[6] * x + m[7] * y + m[8] * z + t[2]) * scale;
                    if (out_bgra) out_bgra[o] = bgra ? bgra[i] : 0xFF000000u;
                    ++o;
                    --want;
                }
            });
        }
        Na__WriteStats(stats, stat_count, static_cast<double>(all_kept), static_cast<double>(written), 0.0, Na__MsSinceStart(started));
        return written;
    } catch (const std::bad_alloc&) {
        return Na__Fail("Not enough memory to read the points.", -4);
    } catch (...) {
        return Na__Fail("Reading the points failed unexpectedly.", -5);
    }
}

// u . p and v . p are taken straight from the stored (local) coordinates:
// u . (M x + t) = (M^T u) . x + u . t, in double precision. A small grid (a
// histogram, a thin strip) gets one count array per worker, summed after; a
// large one (an image) is shared through relaxed atomic increments, so memory
// never grows with the number of threads.
NAPC_API int32_t napc_box_grid(void* cloud_handle, const double* boxes, int32_t box_count,
                               const double* grid, int32_t grid_count, uint32_t* out_counts, int64_t cap,
                               double* stats, int32_t stat_count) {
    const Na__PointCloud* cloud = static_cast<const Na__PointCloud*>(cloud_handle);
    if (!cloud || !cloud->points) return Na__Fail("No point cloud is loaded in the native engine.", -1);
    if (!boxes || box_count < NAPC_BOXES_COUNT || !grid || grid_count < NAPC_G_COUNT || !out_counts) {
        return Na__Fail("The grid request is missing arguments.", -2);
    }
    for (int k = 0; k < NAPC_G_COUNT; ++k) {
        if (!std::isfinite(grid[k])) return Na__Fail("A grid number is not a number.", -2);
    }
    const double su = grid[NAPC_G_SU], sv = grid[NAPC_G_SV];
    const double w_in = grid[NAPC_G_WIDTH], h_in = grid[NAPC_G_HEIGHT];
    if (!(su > 0.0 && sv > 0.0)) return Na__Fail("A grid cell must have a positive size.", -2);
    if (!(w_in >= 1.0 && h_in >= 1.0 && w_in <= 1.0e6 && h_in <= 1.0e6)) return Na__Fail("A grid must be 1 to 1,000,000 cells each way.", -2);
    const int64_t width = static_cast<int64_t>(w_in), height = static_cast<int64_t>(h_in);
    const int64_t cells = width * height;
    if (cells > cap || cells > 200000000LL) return Na__Fail("The grid has more cells than the output can hold.", -2);
    Na__BoxFilter filter;
    if (!Na__BoxFilter__Read(boxes, boxes + 12, filter)) return Na__Fail("A box is not a valid box.", -3);
    std::lock_guard<std::mutex> lock(g_render_mutex);
    try {
        const auto started = std::chrono::steady_clock::now();
        const Na__CloudPoints& points = *cloud->points;
        const int64_t count = points.count;
        const float* xyz = points.xyz.data();
        const bool active = filter.Active();
        const double* m = filter.m;
        const double* t = filter.t;
        const double u[3] = { grid[NAPC_G_UX], grid[NAPC_G_UY], grid[NAPC_G_UZ] };
        const double v[3] = { grid[NAPC_G_VX], grid[NAPC_G_VY], grid[NAPC_G_VZ] };
        // M^T u and M^T v (M row-major), then the translation's part.
        const double au[3] = { m[0] * u[0] + m[3] * u[1] + m[6] * u[2], m[1] * u[0] + m[4] * u[1] + m[7] * u[2],
                               m[2] * u[0] + m[5] * u[1] + m[8] * u[2] };
        const double av[3] = { m[0] * v[0] + m[3] * v[1] + m[6] * v[2], m[1] * v[0] + m[4] * v[1] + m[7] * v[2],
                               m[2] * v[0] + m[5] * v[1] + m[8] * v[2] };
        const double bu = u[0] * t[0] + u[1] * t[1] + u[2] * t[2] - grid[NAPC_G_U0];
        const double bv = grid[NAPC_G_V1] - (v[0] * t[0] + v[1] * t[1] + v[2] * t[2]);
        const double wd = static_cast<double>(width), hd = static_cast<double>(height);
        Na__ThreadPool& pool = Na__Pool();
        const unsigned workers = pool.Size();
        std::vector<int64_t> kept(workers, 0), landed(workers, 0);
        const bool per_worker = cells * static_cast<int64_t>(workers) <= 4000000LL;
        std::vector<uint32_t> partial(per_worker ? static_cast<size_t>(cells * workers) : 0, 0u);
        std::unique_ptr<std::atomic<uint32_t>[]> shared;
        if (!per_worker) {
            shared.reset(new std::atomic<uint32_t>[static_cast<size_t>(cells)]);
            for (int64_t c = 0; c < cells; ++c) shared[c].store(0u, std::memory_order_relaxed);
        }
        pool.Run([&](unsigned worker, unsigned total) {
            int64_t begin = 0, end = 0;
            Na__Slice(count, worker, total, begin, end);
            uint32_t* mine = per_worker ? partial.data() + static_cast<size_t>(cells) * worker : nullptr;
            int64_t k = 0, l = 0;
            for (int64_t i = begin; i < end; ++i) {
                const float lx = xyz[i * 3], ly = xyz[i * 3 + 1], lz = xyz[i * 3 + 2];
                if (active && filter.Verdict(lx, ly, lz) != NA_BOX_KEPT) continue;
                ++k;
                const double x = lx, y = ly, z = lz;
                const double cf = (au[0] * x + au[1] * y + au[2] * z + bu) / su;
                const double rf = (bv - (av[0] * x + av[1] * y + av[2] * z)) / sv;
                if (!(cf >= 0.0 && cf < wd && rf >= 0.0 && rf < hd)) continue;
                const int64_t cell = static_cast<int64_t>(rf) * width + static_cast<int64_t>(cf);
                if (mine) ++mine[cell];
                else shared[cell].fetch_add(1u, std::memory_order_relaxed);
                ++l;
            }
            kept[worker] = k;
            landed[worker] = l;
        });
        int64_t all_kept = 0, all_landed = 0;
        for (unsigned w = 0; w < workers; ++w) { all_kept += kept[w]; all_landed += landed[w]; }
        uint32_t most = 0;
        for (int64_t c = 0; c < cells; ++c) {
            uint32_t sum = 0;
            if (per_worker) {
                for (unsigned w = 0; w < workers; ++w) sum += partial[static_cast<size_t>(cells) * w + c];
            } else {
                sum = shared[c].load(std::memory_order_relaxed);
            }
            out_counts[c] = sum;
            most = std::max(most, sum);
        }
        Na__WriteStats(stats, stat_count, static_cast<double>(all_kept), static_cast<double>(all_landed),
                       static_cast<double>(most), Na__MsSinceStart(started));
        return 0;
    } catch (const std::bad_alloc&) {
        return Na__Fail("Not enough memory for the grid.", -4);
    } catch (...) {
        return Na__Fail("Counting the grid failed unexpectedly.", -5);
    }
}

// -----------------------------------------------------------------------------
// REGION | LAS
// -----------------------------------------------------------------------------

namespace {
    int32_t Na__CopyText(const std::string& source, char* text, int32_t text_cap) {
        if (!text || text_cap <= 0) return 0;
        const size_t length = std::min(source.size(), static_cast<size_t>(text_cap - 1));
        std::memcpy(text, source.data(), length);
        text[length] = '\0';
        return static_cast<int32_t>(length);
    }
}

NAPC_API int32_t napc_las_read_header(const char* path_utf8, double* info, int32_t info_count, char* text, int32_t text_cap) {
    if (!path_utf8 || !info || info_count < NAPC_L_COUNT) return Na__Fail("LAS header request is missing arguments.", -1);
    Na__LasHeaderInfo header;
    std::string error;
    if (!Na__Las__ReadHeader(path_utf8, header, error)) return Na__Fail(error.c_str(), -2);
    info[NAPC_L_VERSION_MAJOR] = header.version_major;
    info[NAPC_L_VERSION_MINOR] = header.version_minor;
    info[NAPC_L_POINT_FORMAT]  = header.point_format;
    info[NAPC_L_RECORD_LENGTH] = header.record_length;
    info[NAPC_L_POINT_COUNT]   = static_cast<double>(header.point_count);
    for (int axis = 0; axis < 3; ++axis) {
        info[NAPC_L_SCALE_X + axis]  = header.scale[axis];
        info[NAPC_L_OFFSET_X + axis] = header.offset[axis];
        info[NAPC_L_MIN_X + axis]    = header.min[axis];
        info[NAPC_L_MAX_X + axis]    = header.max[axis];
    }
    info[NAPC_L_HAS_RGB]       = header.has_rgb ? 1 : 0;
    info[NAPC_L_VLR_COUNT]     = header.vlr_count;
    info[NAPC_L_HAS_WKT]       = header.has_wkt ? 1 : 0;
    info[NAPC_L_HAS_GEOKEYS]   = header.has_geokeys ? 1 : 0;
    info[NAPC_L_IS_COMPRESSED] = header.is_compressed ? 1 : 0;
    Na__CopyText(header.system_id + "\t" + header.software + "\t" + header.wkt, text, text_cap);
    return 0;
}

namespace {
    uint64_t Na__KeyFromParams(const double* params, int32_t param_count, int32_t at) {
        if (!params || param_count < at + 2) return 0;
        return (static_cast<uint64_t>(params[at]) << 32) | static_cast<uint64_t>(params[at + 1]);
    }
    void Na__KeyToDoubles(uint64_t key, double* hi, double* lo) {
        *hi = static_cast<double>(key >> 32);
        *lo = static_cast<double>(key & 0xFFFFFFFFull);
    }
}

NAPC_API int32_t napc_las_content_key(const char* path_utf8, double* out, int32_t out_count) {
    if (!path_utf8 || !out || out_count < 2) return Na__Fail("Content key request is missing arguments.", -1);
    uint64_t key = 0;
    std::string error;
    if (!Na__LasFile__ContentKey(Na__Utf8ToWide(path_utf8), key, error)) return Na__Fail(error.c_str(), -2);
    Na__KeyToDoubles(key, &out[0], &out[1]);
    return 0;
}

NAPC_API void* napc_las_import_start(const char* path_utf8, const char* cache_path_utf8,
                                    const double* params, int32_t param_count) {
    if (!path_utf8) {
        Na__Fail("No LAS path was given.", -1);
        return nullptr;
    }
    try {
        Na__LasImportJob* job = new Na__LasImportJob();
        job->path = path_utf8;
        job->cache_path = cache_path_utf8 ? cache_path_utf8 : "";
        if (params && param_count >= 3) {
            for (int c = 0; c < 3; ++c) job->fallback_rgb[c] = static_cast<uint8_t>(std::clamp(params[c], 0.0, 255.0));
        }
        if (params && param_count >= 5) {
            job->las_bytes = params[3];
            job->las_mtime = params[4];
        }
        job->content_key = Na__KeyFromParams(params, param_count, 5);
        Na__LasJob__Start(job);
        return job;
    } catch (...) {
        Na__Fail("The LAS import could not be started.", -2);
        return nullptr;
    }
}

NAPC_API void* napc_cache_load_start(const char* cache_path_utf8, const double* params, int32_t param_count) {
    if (!cache_path_utf8) {
        Na__Fail("No cache path was given.", -1);
        return nullptr;
    }
    try {
        Na__LasImportJob* job = new Na__LasImportJob();
        job->path = cache_path_utf8;
        job->from_cache = true;
        if (params && param_count >= 1) job->expect_count = static_cast<int64_t>(params[0]);
        job->expect_key = Na__KeyFromParams(params, param_count, 1);
        Na__LasJob__Start(job);
        return job;
    } catch (...) {
        Na__Fail("The point cache load could not be started.", -2);
        return nullptr;
    }
}

NAPC_API int32_t napc_cache_peek(const char* cache_path_utf8, double* out, int32_t out_count) {
    if (!cache_path_utf8 || !out || out_count < NAPC_C_COUNT) return Na__Fail("Cache peek is missing arguments.", -1);
    Na__CacheHeader header;
    std::string error;
    if (!Na__Cache__ReadHeader(cache_path_utf8, header, error)) return Na__Fail(error.c_str(), -2);
    out[NAPC_C_POINT_COUNT] = static_cast<double>(header.point_count);
    for (int axis = 0; axis < 3; ++axis) {
        out[NAPC_C_ORIGIN_X + axis] = header.origin[axis];
        out[NAPC_C_MIN_X + axis]    = header.local_min[axis];
        out[NAPC_C_MAX_X + axis]    = header.local_max[axis];
    }
    out[NAPC_C_COLOUR_BITS] = header.colour_bits;
    out[NAPC_C_LAS_BYTES]   = header.las_bytes;
    out[NAPC_C_LAS_MTIME]   = header.las_mtime;
    out[NAPC_C_VERSION]     = header.version;
    out[NAPC_C_FLAGS]       = header.flags;
    Na__KeyToDoubles(header.content_key, &out[NAPC_C_KEY_HI], &out[NAPC_C_KEY_LO]);
    out[NAPC_C_TIME_BASE]   = header.time_base;
    return 0;
}

NAPC_API int32_t napc_job_poll(void* job_handle, double* out, int32_t out_count) {
    Na__LasImportJob* job = static_cast<Na__LasImportJob*>(job_handle);
    if (!job || !out || out_count < NAPC_J_COUNT) return Na__Fail("Job poll is missing arguments.", -1);
    const bool finished = job->finished.load(std::memory_order_acquire);
    out[NAPC_J_PHASE]     = job->phase.load();
    out[NAPC_J_DONE]      = static_cast<double>(job->done.load());
    out[NAPC_J_TOTAL]     = static_cast<double>(job->total.load());
    out[NAPC_J_FINISHED]  = finished ? 1 : 0;
    out[NAPC_J_FAILED]    = job->failed.load() ? 1 : 0;
    out[NAPC_J_CANCELLED] = job->cancelled.load() ? 1 : 0;
    if (finished) {
        out[NAPC_J_READ_MS] = job->read_ms;
        out[NAPC_J_COLOUR_MS] = job->colour_ms;
        out[NAPC_J_SHUFFLE_MS] = job->shuffle_ms;
        out[NAPC_J_TOTAL_MS] = job->total_ms;
        out[NAPC_J_COLOUR_BITS] = job->colour_bits;
        for (int axis = 0; axis < 3; ++axis) {
            out[NAPC_J_ORIGIN_X + axis] = job->origin[axis];
            out[NAPC_J_MIN_X + axis] = job->local_min[axis];
            out[NAPC_J_MAX_X + axis] = job->local_max[axis];
        }
        out[NAPC_J_POINT_COUNT] = static_cast<double>(job->point_count);
        const Na__CloudPoints* points = job->cloud ? job->cloud->points.get() : nullptr;
        out[NAPC_J_FLAGS]     = points ? ((points->source_index.empty() ? 0 : 1) | (points->time.empty() ? 0 : 2)) : 0;
        out[NAPC_J_TIME_BASE] = points ? points->time_base : 0.0;
        Na__KeyToDoubles(job->content_key, &out[NAPC_J_KEY_HI], &out[NAPC_J_KEY_LO]);
        out[NAPC_J_CACHE_VERSION] = job->cache_version;
    }
    out[NAPC_J_CACHE_STATE] = job->cache_state.load();
    return finished ? 1 : 0;
}

NAPC_API int32_t napc_job_error(void* job_handle, char* text, int32_t text_cap) {
    Na__LasImportJob* job = static_cast<Na__LasImportJob*>(job_handle);
    if (!job) return 0;
    std::lock_guard<std::mutex> lock(job->error_mutex);
    return Na__CopyText(job->error, text, text_cap);
}

NAPC_API void napc_job_cancel(void* job_handle) {
    Na__LasImportJob* job = static_cast<Na__LasImportJob*>(job_handle);
    if (job) job->cancel_requested.store(true);
}

NAPC_API void* napc_job_take_cloud(void* job_handle) {
    Na__LasImportJob* job = static_cast<Na__LasImportJob*>(job_handle);
    if (!job || !job->finished.load(std::memory_order_acquire)) return nullptr;
    return job->cloud.release();
}

NAPC_API void napc_job_destroy(void* job_handle) {
    Na__LasJob__Destroy(static_cast<Na__LasImportJob*>(job_handle));
}

// -----------------------------------------------------------------------------
// REGION | LAZ to LAS
// -----------------------------------------------------------------------------

NAPC_API void* napc_laz_convert_start(const char* source_utf8, const char* dest_utf8) {
    if (!source_utf8 || !dest_utf8) {
        Na__Fail("The LAZ conversion needs a source and a destination path.", -1);
        return nullptr;
    }
    try {
        Na__LazConvertJob* job = new Na__LazConvertJob();
        job->source_utf8 = source_utf8;
        job->dest_utf8   = dest_utf8;
        Na__LazConvert__Start(job);
        return job;
    } catch (...) {
        Na__Fail("The LAZ conversion could not be started.", -2);
        return nullptr;
    }
}

NAPC_API int32_t napc_laz_convert_poll(void* job_handle, double* out, int32_t out_count) {
    Na__LazConvertJob* job = static_cast<Na__LazConvertJob*>(job_handle);
    if (!job || !out || out_count < NAPC_Z_COUNT) return Na__Fail("LAZ conversion poll is missing arguments.", -1);
    const bool finished = job->finished.load(std::memory_order_acquire);
    std::fill(out, out + NAPC_Z_COUNT, 0.0);
    out[NAPC_Z_PHASE]     = job->phase.load();
    out[NAPC_Z_DONE]      = static_cast<double>(job->done.load());
    out[NAPC_Z_TOTAL]     = static_cast<double>(job->total.load());
    out[NAPC_Z_FINISHED]  = finished ? 1 : 0;
    out[NAPC_Z_FAILED]    = job->failed.load() ? 1 : 0;
    out[NAPC_Z_CANCELLED] = job->cancelled.load() ? 1 : 0;
    if (finished) {
        out[NAPC_Z_POINT_COUNT]   = static_cast<double>(job->point_count);
        out[NAPC_Z_POINT_FORMAT]  = job->point_format;
        out[NAPC_Z_RECORD_LENGTH] = job->record_length;
        out[NAPC_Z_VERSION_MAJOR] = job->version_major;
        out[NAPC_Z_VERSION_MINOR] = job->version_minor;
        out[NAPC_Z_SOURCE_BYTES]  = static_cast<double>(job->source_bytes);
        out[NAPC_Z_WRITTEN_BYTES] = static_cast<double>(job->written_bytes);
        for (int axis = 0; axis < 3; ++axis) {
            out[NAPC_Z_HEADER_MIN_X + axis] = job->header_min[axis];
            out[NAPC_Z_HEADER_MAX_X + axis] = job->header_max[axis];
            out[NAPC_Z_POINT_MIN_X + axis]  = job->point_min[axis];
            out[NAPC_Z_POINT_MAX_X + axis]  = job->point_max[axis];
        }
        out[NAPC_Z_DROPPED_RECORDS] = job->dropped_records;
        out[NAPC_Z_CONVERT_MS]      = job->convert_ms;
        out[NAPC_Z_CHECK_MS]        = job->check_ms;
        out[NAPC_Z_TOTAL_MS]        = job->total_ms;
    }
    return finished ? 1 : 0;
}

NAPC_API int32_t napc_laz_convert_error(void* job_handle, char* text, int32_t text_cap) {
    Na__LazConvertJob* job = static_cast<Na__LazConvertJob*>(job_handle);
    if (!job) return 0;
    std::lock_guard<std::mutex> lock(job->text_mutex);
    return Na__CopyText(job->error, text, text_cap);
}

NAPC_API int32_t napc_laz_convert_notes(void* job_handle, char* text, int32_t text_cap) {
    Na__LazConvertJob* job = static_cast<Na__LazConvertJob*>(job_handle);
    if (!job) return 0;
    std::lock_guard<std::mutex> lock(job->text_mutex);
    return Na__CopyText(job->notes, text, text_cap);
}

NAPC_API void napc_laz_convert_cancel(void* job_handle) {
    Na__LazConvertJob* job = static_cast<Na__LazConvertJob*>(job_handle);
    if (job) job->cancel_requested.store(true);
}

NAPC_API void napc_laz_convert_destroy(void* job_handle) {
    Na__LazConvert__Destroy(static_cast<Na__LazConvertJob*>(job_handle));
}

// -----------------------------------------------------------------------------
// REGION | Shutdown
// -----------------------------------------------------------------------------

void Na__Clean__ShutdownAll();   // CleanContext.cpp

NAPC_API void napc_shutdown(void) {
    Na__Clean__ShutdownAll();    // no cleaning worker may outlive the DLL
    std::lock_guard<std::mutex> lock(g_render_mutex);
    delete g_pool;
    g_pool = nullptr;
    delete g_buffers;
    g_buffers = nullptr;
}
