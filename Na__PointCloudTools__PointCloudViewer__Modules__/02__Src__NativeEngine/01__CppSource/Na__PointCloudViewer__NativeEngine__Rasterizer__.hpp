// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - RASTERIZER
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__Rasterizer__.hpp
// PURPOSE    : Multi-threaded CPU point splatting into a depth-tested frame.
//
// METHOD (compute-rasterisation style, binned by screen band):
//   Each pixel holds 64 bits: high 32 an order-preserving depth key, low 32
//   the point's colour with its cloud's opacity in the top byte; the smallest
//   value (nearest point) wins.
//   Points are stored in random order (so a budget is an even sample), which
//   means every worker would write all over the image at once and the cores
//   would fight over the same cache lines (~77 ns per point measured). So:
//     pass 1  every worker projects its slice of points and drops each one
//             into the bin of the horizontal band(s) of the image it covers
//     pass 2  every band is owned by ONE worker, which applies its bins with
//             plain loads and stores: no sharing, and the band stays in cache
//   Points go through in batches so the bins stay small. A resolve pass turns
//   the buffer into RGBA rows (alpha = the winning point's cloud opacity,
//   empty pixels transparent) and resets it for the next frame.
//
// LAYERS (v0.10.0, ABI 7): several clouds can be drawn into ONE frame. They
//   share the depth buffer, so the nearest point wins whichever cloud it
//   belongs to (two scans of one building occlude each other correctly), and
//   they share one point budget: split equally between the layers, a layer
//   that holds fewer points (all of them, or all inside its clip box) passing
//   the rest to the others. A single cloud is simply one layer, drawn exactly
//   as before.
//
// CROP: the image can be just the rectangle of the viewport the clouds cover
//   (FULL_WIDTH/HEIGHT + CROP_X/Y); the projection still uses the whole view.
//
// CROP AND CUT BOXES (v0.11.0, ABI 8): a layer can carry the Clean tab's
//   boxes (BoxFilter.hpp). Result: the points they remove are not drawn and
//   the budget counts only the points kept, so the result is drawn as densely
//   as the whole cloud. Differences: every point is drawn, the removed ones in
//   the removed colour and the kept ones tinted. A 48-number block (ABI 7)
//   has no boxes and renders exactly as before.
//
// =============================================================================

#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "Na__PointCloudViewer__NativeEngine__ThreadPool__.hpp"

// How many of a cloud's points are shown (inside its clip box, and kept by
// its Crop and Cut boxes in the Result view), counted per fixed chunk of the
// (randomly ordered) point list. Recomputed only when a box or the placement
// change; the prefix that holds any share of the budget is then found from
// the counts (one chunk scanned), and the last one is kept.
struct Na__ClipCountCache {
    bool                 valid = false;
    std::vector<double>  key;               // local -> model (12), clip enabled and box (7), hide flag (+ the boxes)
    std::vector<int64_t> inside;            // points shown, per chunk
    int64_t              inside_total = 0;
    int64_t              limit_share = -1;  // the last share asked for ...
    int64_t              limit = 0;         // ... and the prefix length that holds it
};

// The points themselves: built once (import, cache load or a cleaning
// preview), then never changed. Shared, so a cleaning worker can keep reading
// them even if Ruby releases the cloud handle while the worker runs.
struct Na__CloudPoints {
    std::vector<float>    xyz;           // count * 3, local units (source unit, relative to the local origin)
    std::vector<uint32_t> bgra;          // count, 0xAARRGGBB little-endian -> bytes B,G,R,A
    std::vector<uint32_t> source_index;  // count: the LAS record each stored point came from (empty = unknown)
    std::vector<float>    time;          // count: GPS time - time_base, seconds (empty = the LAS has no time)
    double                time_base = 0.0;
    int64_t               count = 0;
};

// What Ruby holds: the shared points plus this handle's own render cache.
struct Na__PointCloud {
    std::shared_ptr<const Na__CloudPoints> points;
    int64_t               count = 0;     // == points->count
    mutable Na__ClipCountCache clip_cache;   // renders run one at a time (the render mutex)
};

// One cloud of a frame: its points and its render parameters (NAPC_P_COUNT,
// or NAPC_P_BASE_COUNT without boxes). The FIRST layer's camera and image
// fields describe the frame for every layer.
struct Na__RenderLayer {
    const Na__PointCloud* cloud  = nullptr;
    const double*         params = nullptr;
    int32_t               param_count = 0;
};

// One projected point waiting in a band's bin (12 bytes).
struct Na__BinEntry {
    int16_t  x;
    int16_t  y;
    uint32_t depth;
    uint32_t colour;
};

struct Na__FrameBuffers {
    std::unique_ptr<std::atomic<uint64_t>[]> depth;
    size_t               pixels = 0;
    std::vector<uint8_t> raw;      // PNG scanlines: filter byte + RGBA
    std::vector<uint8_t> file;     // encoded PNG
    std::vector<std::vector<Na__BinEntry>> bins;   // [worker * bands + band], capacity kept between frames
};

struct Na__RasterStats {
    int64_t points_tested    = 0;
    int64_t points_on_screen = 0;
    double  clear_ms   = 0.0;
    double  raster_ms  = 0.0;
    double  resolve_ms = 0.0;
};

// Per layer: what it could draw, its part of the budget, what was walked and drawn.
struct Na__LayerStats {
    int64_t demand    = 0;   // every point, or every point inside its clip box
    int64_t share     = 0;   // its part of the shared budget (<= demand)
    int64_t tested    = 0;   // prefix of its point list walked
    int64_t on_screen = 0;   // points that landed in the image
};

// Splits a budget between layers that can each draw at most demand[i]
// points: equal shares, a layer that needs less passing the rest on (the
// first of the layers that still want more get the remainder, one each).
// Deterministic: ties are broken by layer order.
std::vector<int64_t> Na__Raster__ShareBudget(const std::vector<int64_t>& demand, int64_t total);

// layers: layer_count entries (see Na__RenderLayer). Fills buffers.raw.
bool Na__Raster__RenderLayers(const Na__RenderLayer* layers, int layer_count, int64_t total_budget, Na__ThreadPool& pool,
                              Na__FrameBuffers& buffers, Na__RasterStats& stats, std::vector<Na__LayerStats>& layer_stats,
                              std::string& error);

// One cloud, its budget in params[NAPC_P_BUDGET] (the single-layer frame).
bool Na__Raster__Render(const Na__PointCloud& cloud, const double* params, int32_t param_count, Na__ThreadPool& pool,
                        Na__FrameBuffers& buffers, Na__RasterStats& stats, std::string& error);
