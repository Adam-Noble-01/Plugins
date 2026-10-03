// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - RASTERIZER
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__Rasterizer__.hpp
// PURPOSE    : Multi-threaded CPU point splatting into a depth-tested frame.
//
// METHOD (compute-rasterisation style, binned by screen band):
//   Each pixel holds 64 bits: high 32 an order-preserving depth key, low 32
//   the point's BGRA; the smallest value (nearest point) wins.
//   Points are stored in random order (so a budget is an even sample), which
//   means every worker would write all over the image at once and the cores
//   would fight over the same cache lines (~77 ns per point measured). So:
//     pass 1  every worker projects its slice of points and drops each one
//             into the bin of the horizontal band(s) of the image it covers
//     pass 2  every band is owned by ONE worker, which applies its bins with
//             plain loads and stores: no sharing, and the band stays in cache
//   Points go through in batches so the bins stay small. A resolve pass turns
//   the buffer into RGBA rows (alpha = opacity, empty pixels transparent) and
//   resets it for the next frame.
//
// CROP: the image can be just the rectangle of the viewport the cloud covers
//   (FULL_WIDTH/HEIGHT + CROP_X/Y); the projection still uses the whole view.
//
// =============================================================================

#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "Na__PointCloudViewer__NativeEngine__ThreadPool__.hpp"

// How far into the point list the render must go to meet the budget with the
// clip box on. Recomputed only when the box, the placement or the budget change.
struct Na__ClipLimitCache {
    bool    valid = false;
    double  key[20] = {};
    int64_t limit = 0;
};

struct Na__PointCloud {
    std::vector<float>    xyz;     // count * 3, local units
    std::vector<uint32_t> bgra;    // count, 0xAARRGGBB little-endian -> bytes B,G,R,A
    int64_t               count = 0;
    mutable Na__ClipLimitCache clip_cache;   // renders run one at a time (Ruby main thread)
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

// params: NAPC_P_COUNT doubles (see the Api header). Fills buffers.raw.
bool Na__Raster__Render(const Na__PointCloud& cloud, const double* params, Na__ThreadPool& pool,
                        Na__FrameBuffers& buffers, Na__RasterStats& stats, std::string& error);
