// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - RASTERIZER
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__Rasterizer__.cpp
// PURPOSE    : See the header. Projection matches SketchUp's own camera exactly
//              (verified against View#screen_coords: 0.0 px error, perspective
//              and parallel), given the scale factors the Ruby side computes.
//
// =============================================================================

#include "Na__PointCloudViewer__NativeEngine__Rasterizer__.hpp"
#include "Na__PointCloudViewer__NativeEngine__Api__.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>
#include <numeric>

namespace {

    const uint64_t NA_EMPTY_PIXEL = ~0ull;
    const int64_t  NA_CLIP_CHUNKS = 256;

    double Na__MsSince(std::chrono::steady_clock::time_point start) {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    }

    // Maps any float to a uint32 whose unsigned order equals the float order
    // (needed for parallel views, where camera depth can be negative).
    inline uint32_t Na__OrderedDepth(float value) {
        uint32_t bits;
        std::memcpy(&bits, &value, 4);
        return (bits & 0x80000000u) ? ~bits : (bits | 0x80000000u);
    }

    struct Na__SplatOffset { int dx; int dy; };

    // Square up to 2 px, round from 3 px.
    std::vector<Na__SplatOffset> Na__SplatOffsets(int size) {
        std::vector<Na__SplatOffset> offsets;
        const int low = -(size - 1) / 2;
        const int high = low + size - 1;
        const double centre = (low + high) / 2.0;
        const double radius_sq = (size / 2.0) * (size / 2.0);
        for (int dy = low; dy <= high; ++dy) {
            for (int dx = low; dx <= high; ++dx) {
                if (size >= 3) {
                    const double ex = dx - centre, ey = dy - centre;
                    if (ex * ex + ey * ey > radius_sq) continue;
                }
                offsets.push_back({ dx, dy });
            }
        }
        return offsets;
    }

    // Model-space box test: local -> model (M, t), then compare with the box.
    struct Na__ClipTest {
        float m[3][3];
        float t[3];
        float lo[3];
        float hi[3];

        inline bool Inside(float x, float y, float z) const {
            const float mx = m[0][0] * x + m[0][1] * y + m[0][2] * z + t[0];
            const float my = m[1][0] * x + m[1][1] * y + m[1][2] * z + t[1];
            const float mz = m[2][0] * x + m[2][1] * y + m[2][2] * z + t[2];
            return mx >= lo[0] && mx <= hi[0] && my >= lo[1] && my <= hi[1] && mz >= lo[2] && mz <= hi[2];
        }
    };

    Na__ClipTest Na__MakeClipTest(const double* p) {
        Na__ClipTest test;
        for (int r = 0; r < 3; ++r) {
            for (int c = 0; c < 3; ++c) test.m[r][c] = static_cast<float>(p[NAPC_P_M00 + r * 3 + c]);
            test.t[r]  = static_cast<float>(p[NAPC_P_TX + r]);
            test.lo[r] = static_cast<float>(p[NAPC_P_CLIP_MIN_X + r]);
            test.hi[r] = static_cast<float>(p[NAPC_P_CLIP_MAX_X + r]);
        }
        return test;
    }

    // How many points lie inside the box, per chunk of the point list. The
    // count runs in parallel over fixed chunks, and is kept until the box or
    // the placement change.
    const Na__ClipCountCache& Na__ClipCounts(const Na__PointCloud& cloud, const Na__ClipTest& test, const double* p,
                                             Na__ThreadPool& pool) {
        double key[19];
        for (int k = 0; k < 12; ++k) key[k] = p[NAPC_P_M00 + k];
        for (int k = 0; k < 7; ++k)  key[12 + k] = p[NAPC_P_CLIP_ENABLED + k];
        Na__ClipCountCache& cache = cloud.clip_cache;
        if (cache.valid && std::memcmp(cache.key, key, sizeof(key)) == 0) return cache;

        const int64_t count = cloud.count;
        const int64_t chunk_size = (count + NA_CLIP_CHUNKS - 1) / NA_CLIP_CHUNKS;
        cache.inside.assign(static_cast<size_t>(NA_CLIP_CHUNKS), 0);
        const float* xyz = cloud.points->xyz.data();
        int64_t* inside = cache.inside.data();
        pool.Run([&](unsigned worker, unsigned workers) {
            for (int64_t c = worker; c < NA_CLIP_CHUNKS; c += workers) {
                const int64_t begin = std::min(count, c * chunk_size);
                const int64_t end   = std::min(count, begin + chunk_size);
                int64_t n = 0;
                for (int64_t i = begin; i < end; ++i) {
                    if (test.Inside(xyz[i * 3], xyz[i * 3 + 1], xyz[i * 3 + 2])) ++n;
                }
                inside[c] = n;
            }
        });
        cache.inside_total = 0;
        for (int64_t c = 0; c < NA_CLIP_CHUNKS; ++c) cache.inside_total += inside[c];
        std::memcpy(cache.key, key, sizeof(key));
        cache.valid = true;
        cache.limit_share = -1;
        return cache;
    }

    // Smallest prefix of the (randomly ordered) point list that holds `share`
    // points inside the box, from the counts above: only the chunk where the
    // share is reached is scanned point by point. The prefix of a random
    // order is still an even sample of the box. Call with fresh counts and
    // 0 < share < inside_total.
    int64_t Na__ClipPrefix(const Na__PointCloud& cloud, const Na__ClipTest& test, int64_t share) {
        Na__ClipCountCache& cache = cloud.clip_cache;
        if (cache.limit_share == share) return cache.limit;
        const int64_t count = cloud.count;
        const int64_t chunk_size = (count + NA_CLIP_CHUNKS - 1) / NA_CLIP_CHUNKS;
        const float* xyz = cloud.points->xyz.data();
        int64_t limit = count;
        int64_t seen = 0;
        for (int64_t c = 0; c < NA_CLIP_CHUNKS; ++c) {
            const int64_t here = cache.inside[static_cast<size_t>(c)];
            if (seen + here < share) { seen += here; continue; }
            const int64_t begin = std::min(count, c * chunk_size);
            const int64_t end   = std::min(count, begin + chunk_size);
            limit = end;
            for (int64_t i = begin; i < end; ++i) {
                if (test.Inside(xyz[i * 3], xyz[i * 3 + 1], xyz[i * 3 + 2]) && ++seen == share) { limit = i + 1; break; }
            }
            break;
        }
        cache.limit_share = share;
        cache.limit = limit;
        return limit;
    }

    void Na__EnsureBuffers(Na__FrameBuffers& buffers, size_t pixels, int width, int height) {
        if (buffers.pixels != pixels) {
            buffers.depth.reset(new std::atomic<uint64_t>[pixels]);
            for (size_t i = 0; i < pixels; ++i) buffers.depth[i].store(NA_EMPTY_PIXEL, std::memory_order_relaxed);
            buffers.pixels = pixels;
        }
        buffers.raw.resize(static_cast<size_t>(height) * (1 + static_cast<size_t>(width) * 4));
    }

} // namespace

// -----------------------------------------------------------------------------
// REGION | Shared Budget
// -----------------------------------------------------------------------------

std::vector<int64_t> Na__Raster__ShareBudget(const std::vector<int64_t>& demand, int64_t total) {
    const size_t n = demand.size();
    std::vector<int64_t> share(n, 0);
    std::vector<size_t> order(n);
    std::iota(order.begin(), order.end(), size_t(0));
    std::stable_sort(order.begin(), order.end(), [&](size_t a, size_t b) { return demand[a] < demand[b]; });
    int64_t remaining = std::max<int64_t>(0, total);
    for (size_t k = 0; k < n; ++k) {
        const size_t  i    = order[k];
        const int64_t want = std::max<int64_t>(0, demand[i]);
        const int64_t left = static_cast<int64_t>(n - k);
        const int64_t fair = remaining / left;
        if (want <= fair) {
            share[i] = want;
            remaining -= want;
            continue;
        }
        // Every layer from here on wants more than an equal share of what is
        // left: split it evenly, the first ones (in layer order) taking one
        // more point each until the remainder is gone.
        std::vector<size_t> rest(order.begin() + static_cast<std::ptrdiff_t>(k), order.end());
        std::sort(rest.begin(), rest.end());
        int64_t extra = remaining - fair * left;
        for (size_t j : rest) {
            share[j] = fair + (extra > 0 ? 1 : 0);
            if (extra > 0) --extra;
        }
        break;
    }
    return share;
}

// -----------------------------------------------------------------------------
// REGION | Render
// -----------------------------------------------------------------------------

bool Na__Raster__RenderLayers(const Na__RenderLayer* layers, int layer_count, int64_t total_budget, Na__ThreadPool& pool,
                              Na__FrameBuffers& buffers, Na__RasterStats& stats, std::vector<Na__LayerStats>& layer_stats,
                              std::string& error) {
    if (!layers || layer_count < 1) {
        error = "There is nothing to render.";
        return false;
    }
    for (int li = 0; li < layer_count; ++li) {
        if (!layers[li].cloud || !layers[li].cloud->points || !layers[li].params) {
            error = "A point cloud to render is missing.";
            return false;
        }
    }
    // The first layer describes the frame: camera, image size, crop, near plane.
    const double* f = layers[0].params;
    const int width  = static_cast<int>(f[NAPC_P_WIDTH]);
    const int height = static_cast<int>(f[NAPC_P_HEIGHT]);
    if (width < 1 || height < 1 || width > 16384 || height > 16384) {
        error = "The render size is invalid.";
        return false;
    }
    // The whole view (projection centre) and where this image sits in it.
    const double full_w = f[NAPC_P_FULL_WIDTH] >= 1.0 ? f[NAPC_P_FULL_WIDTH] : width;
    const double full_h = f[NAPC_P_FULL_HEIGHT] >= 1.0 ? f[NAPC_P_FULL_HEIGHT] : height;
    const double crop_x = f[NAPC_P_CROP_X];
    const double crop_y = f[NAPC_P_CROP_Y];

    const auto clear_start = std::chrono::steady_clock::now();
    Na__EnsureBuffers(buffers, static_cast<size_t>(width) * static_cast<size_t>(height), width, height);
    stats.clear_ms = Na__MsSince(clear_start);

    const double rx[3] = { f[NAPC_P_XAXIS_X], f[NAPC_P_XAXIS_Y], f[NAPC_P_XAXIS_Z] };
    const double ry[3] = { f[NAPC_P_YAXIS_X], f[NAPC_P_YAXIS_Y], f[NAPC_P_YAXIS_Z] };
    const double rz[3] = { f[NAPC_P_ZAXIS_X], f[NAPC_P_ZAXIS_Y], f[NAPC_P_ZAXIS_Z] };
    const double* rows[3] = { rx, ry, rz };

    const bool  perspective = f[NAPC_P_IS_PERSPECTIVE] > 0.5;
    const float half_w = static_cast<float>(0.5 * full_w - crop_x);
    const float half_h = static_cast<float>(0.5 * full_h - crop_y);
    const float fx = static_cast<float>(0.5 * full_w * f[NAPC_P_SCALE_X]);
    const float fy = static_cast<float>(0.5 * full_h * f[NAPC_P_SCALE_Y]);
    const float near_z = static_cast<float>(std::max(f[NAPC_P_NEAR], 1e-3));

    // --- the shared budget: what each layer can draw, its share, its prefix --------
    // With the clip on, a layer's budget counts points INSIDE its box, so a
    // small box is drawn as densely as the whole cloud would be. A budget that
    // covers every point of every layer needs no counting at all.
    const auto limit_start = std::chrono::steady_clock::now();
    std::vector<Na__ClipTest> tests(static_cast<size_t>(layer_count));
    std::vector<char> clips(static_cast<size_t>(layer_count), 0);
    std::vector<int64_t> limits(static_cast<size_t>(layer_count), 0);
    layer_stats.assign(static_cast<size_t>(layer_count), Na__LayerStats());
    int64_t all_points = 0;
    for (int li = 0; li < layer_count; ++li) {
        const double* p = layers[li].params;
        tests[li] = Na__MakeClipTest(p);
        clips[li] = p[NAPC_P_CLIP_ENABLED] > 0.5 ? 1 : 0;
        all_points += layers[li].cloud->count;
    }
    const int64_t budget = std::max<int64_t>(0, total_budget);
    if (budget >= all_points) {
        for (int li = 0; li < layer_count; ++li) {
            const int64_t count = layers[li].cloud->count;
            limits[li] = count;
            layer_stats[li].demand = count;
            layer_stats[li].share  = count;
        }
    } else {
        std::vector<int64_t> demand(static_cast<size_t>(layer_count), 0);
        for (int li = 0; li < layer_count; ++li) {
            const Na__PointCloud& cloud = *layers[li].cloud;
            demand[li] = clips[li] ? Na__ClipCounts(cloud, tests[li], layers[li].params, pool).inside_total : cloud.count;
        }
        const std::vector<int64_t> shares = Na__Raster__ShareBudget(demand, budget);
        for (int li = 0; li < layer_count; ++li) {
            const Na__PointCloud& cloud = *layers[li].cloud;
            const int64_t share = shares[li];
            if (!clips[li])               limits[li] = share;
            else if (share <= 0)          limits[li] = 0;
            else if (share >= demand[li]) limits[li] = cloud.count;     // every point inside the box
            else                          limits[li] = Na__ClipPrefix(cloud, tests[li], share);
            layer_stats[li].demand = demand[li];
            layer_stats[li].share  = share;
        }
    }
    const double limit_ms = Na__MsSince(limit_start);

    std::atomic<uint64_t>* depth = buffers.depth.get();

    // --- bands and bins ------------------------------------------------------------
    // More bands than workers so a cloud that fills only part of the image still
    // spreads over every core in pass 2 (bands are handed out dynamically).
    const unsigned workers = pool.Size();
    const int bands  = std::max(1, std::min(height, static_cast<int>(workers) * 4));
    const int band_h = (height + bands - 1) / bands;
    const size_t bin_count = static_cast<size_t>(workers) * static_cast<size_t>(bands);
    if (buffers.bins.size() != bin_count) {
        buffers.bins.clear();
        buffers.bins.resize(bin_count);
    }
    const int64_t batch = int64_t(1) << 21;                  // 2M points per pass pair: bins stay ~24 MB

    // --- raster, one layer after another into the same depth buffer ------------------
    const auto raster_start = std::chrono::steady_clock::now();
    stats.points_tested = 0;
    stats.points_on_screen = 0;
    for (int li = 0; li < layer_count; ++li) {
        const Na__PointCloud& cloud = *layers[li].cloud;
        const double* p = layers[li].params;

        // camera = R * (M * local + t - eye), folded into one affine
        const double m[3][3] = { { p[NAPC_P_M00], p[NAPC_P_M01], p[NAPC_P_M02] },
                                 { p[NAPC_P_M10], p[NAPC_P_M11], p[NAPC_P_M12] },
                                 { p[NAPC_P_M20], p[NAPC_P_M21], p[NAPC_P_M22] } };
        const double shift[3] = { p[NAPC_P_TX] - f[NAPC_P_EYE_X], p[NAPC_P_TY] - f[NAPC_P_EYE_Y], p[NAPC_P_TZ] - f[NAPC_P_EYE_Z] };
        float a[3][3];
        float b[3];
        for (int r = 0; r < 3; ++r) {
            for (int c = 0; c < 3; ++c) {
                a[r][c] = static_cast<float>(rows[r][0] * m[0][c] + rows[r][1] * m[1][c] + rows[r][2] * m[2][c]);
            }
            b[r] = static_cast<float>(rows[r][0] * shift[0] + rows[r][1] * shift[1] + rows[r][2] * shift[2]);
        }

        const int   point_size = std::max(1, std::min(32, static_cast<int>(std::lround(p[NAPC_P_POINT_SIZE]))));
        const bool  mono = p[NAPC_P_COLOUR_MODE] > 0.5;
        // The layer's opacity rides in the colour's top byte, so the resolve
        // gives each pixel the opacity of the cloud whose point won it.
        const uint32_t alpha_bits = static_cast<uint32_t>(static_cast<uint8_t>(
            std::lround(std::clamp(p[NAPC_P_OPACITY], 0.0, 1.0) * 255.0))) << 24;
        const uint32_t mono_rgb =
            (static_cast<uint32_t>(std::clamp(p[NAPC_P_MONO_R], 0.0, 255.0)) << 16) |
            (static_cast<uint32_t>(std::clamp(p[NAPC_P_MONO_G], 0.0, 255.0)) << 8) |
            static_cast<uint32_t>(std::clamp(p[NAPC_P_MONO_B], 0.0, 255.0));
        const std::vector<Na__SplatOffset> offsets = Na__SplatOffsets(point_size);
        const int reach = point_size;
        const int splat_low  = -(point_size - 1) / 2;            // row extent of a splat around its centre
        const int splat_high = splat_low + point_size - 1;

        // Clip box in MODEL space: points go through local -> model (M, t) first, so
        // the box stays level with the model even after the cloud is rotated.
        const bool clip = clips[li] != 0;
        const Na__ClipTest& clip_test = tests[li];
        const int64_t limit = limits[li];

        const float*    xyz  = cloud.points->xyz.data();
        const uint32_t* bgra = cloud.points->bgra.data();
        std::vector<int64_t> on_screen(workers, 0);

        for (int64_t base = 0; base < limit; base += batch) {
            const int64_t batch_end = std::min(limit, base + batch);

            // pass 1: project this batch, drop each point into its band bin(s)
            pool.Run([&](unsigned worker, unsigned count) {
                const int64_t span  = batch_end - base;
                const int64_t chunk = (span + count - 1) / count;
                const int64_t begin = base + std::min<int64_t>(span, chunk * worker);
                const int64_t end   = base + std::min<int64_t>(span, chunk * worker + chunk);
                std::vector<Na__BinEntry>* mine = &buffers.bins[static_cast<size_t>(worker) * bands];
                for (int band = 0; band < bands; ++band) mine[band].clear();
                int64_t visible = 0;
                for (int64_t i = begin; i < end; ++i) {
                    const float x = xyz[i * 3], y = xyz[i * 3 + 1], z = xyz[i * 3 + 2];
                    if (clip && !clip_test.Inside(x, y, z)) continue;
                    const float cx = a[0][0] * x + a[0][1] * y + a[0][2] * z + b[0];
                    const float cy = a[1][0] * x + a[1][1] * y + a[1][2] * z + b[1];
                    const float cz = a[2][0] * x + a[2][1] * y + a[2][2] * z + b[2];
                    float sx, sy;
                    if (perspective) {
                        if (cz <= near_z) continue;
                        const float inv = 1.0f / cz;
                        sx = cx * inv * fx + half_w;
                        sy = half_h - cy * inv * fy;
                    } else {
                        sx = cx * fx + half_w;
                        sy = half_h - cy * fy;
                    }
                    if (!(sx > -reach && sx < width + reach && sy > -reach && sy < height + reach)) continue;
                    const int px = static_cast<int>(std::floor(sx));
                    const int py = static_cast<int>(std::floor(sy));
                    const int row_lo = std::max(0, py + splat_low);
                    const int row_hi = std::min(height - 1, py + splat_high);
                    if (row_lo > row_hi) continue;
                    const Na__BinEntry entry = { static_cast<int16_t>(px), static_cast<int16_t>(py),
                                                 Na__OrderedDepth(cz), (mono ? mono_rgb : (bgra[i] & 0x00FFFFFFu)) | alpha_bits };
                    const int band_lo = row_lo / band_h;
                    const int band_hi = row_hi / band_h;
                    for (int band = band_lo; band <= band_hi; ++band) mine[band].push_back(entry);
                    ++visible;
                }
                on_screen[worker] += visible;
            });

            // pass 2: one worker per band applies every bin for that band - no sharing
            std::atomic<int> next_band(0);
            pool.Run([&](unsigned, unsigned) {
                for (int band = next_band.fetch_add(1); band < bands; band = next_band.fetch_add(1)) {
                    const int row_lo = band * band_h;
                    const int row_hi = std::min(height, row_lo + band_h) - 1;
                    for (unsigned source = 0; source < workers; ++source) {
                        const std::vector<Na__BinEntry>& bin = buffers.bins[static_cast<size_t>(source) * bands + band];
                        for (const Na__BinEntry& e : bin) {
                            const uint64_t value = (static_cast<uint64_t>(e.depth) << 32) | e.colour;
                            for (const Na__SplatOffset& o : offsets) {
                                const int qx = e.x + o.dx, qy = e.y + o.dy;
                                if (qy < row_lo || qy > row_hi || qx < 0 || qx >= width) continue;
                                std::atomic<uint64_t>& slot = depth[static_cast<size_t>(qy) * width + qx];
                                if (value < slot.load(std::memory_order_relaxed)) slot.store(value, std::memory_order_relaxed);
                            }
                        }
                    }
                }
            });
        }
        int64_t layer_on_screen = 0;
        for (int64_t v : on_screen) layer_on_screen += v;
        layer_stats[li].tested    = limit;
        layer_stats[li].on_screen = layer_on_screen;
        stats.points_tested      += limit;
        stats.points_on_screen   += layer_on_screen;
    }
    stats.raster_ms = Na__MsSince(raster_start) + limit_ms;

    // --- resolve to RGBA scanlines and reset the buffer --------------------------
    const auto resolve_start = std::chrono::steady_clock::now();
    uint8_t* raw = buffers.raw.data();
    const size_t stride = 1 + static_cast<size_t>(width) * 4;
    pool.Run([&](unsigned worker, unsigned count) {
        for (int row = static_cast<int>(worker); row < height; row += static_cast<int>(count)) {
            uint8_t* out = raw + static_cast<size_t>(row) * stride;
            *out++ = 0;  // PNG filter: none
            std::atomic<uint64_t>* line = depth + static_cast<size_t>(row) * width;
            for (int col = 0; col < width; ++col) {
                const uint64_t value = line[col].load(std::memory_order_relaxed);
                if (value == NA_EMPTY_PIXEL) {
                    out[0] = 0; out[1] = 0; out[2] = 0; out[3] = 0;
                } else {
                    const uint32_t colour = static_cast<uint32_t>(value);
                    out[0] = static_cast<uint8_t>(colour >> 16);   // R
                    out[1] = static_cast<uint8_t>(colour >> 8);    // G
                    out[2] = static_cast<uint8_t>(colour);         // B
                    out[3] = static_cast<uint8_t>(colour >> 24);   // the winning cloud's opacity
                    line[col].store(NA_EMPTY_PIXEL, std::memory_order_relaxed);
                }
                out += 4;
            }
        }
    });
    stats.resolve_ms = Na__MsSince(resolve_start);
    return true;
}

bool Na__Raster__Render(const Na__PointCloud& cloud, const double* p, Na__ThreadPool& pool,
                        Na__FrameBuffers& buffers, Na__RasterStats& stats, std::string& error) {
    const Na__RenderLayer layer = { &cloud, p };
    std::vector<Na__LayerStats> layer_stats;
    const double raw_budget = p ? p[NAPC_P_BUDGET] : 0.0;
    const int64_t budget = raw_budget >= 9.0e18 ? std::numeric_limits<int64_t>::max()
                                                : (raw_budget > 0.0 ? static_cast<int64_t>(raw_budget) : 0);
    return Na__Raster__RenderLayers(&layer, 1, budget, pool, buffers, stats, layer_stats, error);
}
