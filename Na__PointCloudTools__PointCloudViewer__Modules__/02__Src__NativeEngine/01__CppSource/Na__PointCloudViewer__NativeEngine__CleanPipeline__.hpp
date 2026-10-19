// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - CLEANING PIPELINE
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__CleanPipeline__.hpp
// PURPOSE    : Runs the three filters over a region, in this order:
//                1 Remove Noise   (isolated points, small detached groups)
//                2 surface analysis (needed by 2 and 3, and the scatter test)
//                3 Refine Surfaces (+ sparse scatter candidates of filter 1)
//                4 Reduce Density
//              Noise first so stray points never pull a surface fit; density
//              last so it keeps points at their refined positions and knows
//              where the corners and edges are.
//
//   RunRegion: one region, re-using every stage whose inputs did not change
//              (a strength slider on Reduce Density re-runs only density).
//   RunFull  : the whole cloud in tiles (each a region with its own halo),
//              through the same RunRegion, so the export is exactly what the
//              preview showed for every point a preview box can hold.
//
// =============================================================================

#pragma once

#include <atomic>
#include <cstdint>
#include <string>
#include <vector>

#include "Na__PointCloudViewer__NativeEngine__CleanRegion__.hpp"

// Runs (or re-uses) every stage for `params` over work.region. work.cloud,
// work.grid and work.cancel must be set. Throws Na__Cancelled.
void Na__CleanPipeline__RunRegion(Na__CleanWork& work, const Na__CleanParams& params);

struct Na__CleanFullResult {
    std::vector<uint16_t> flags;     // per stored point
    std::vector<float>    delta;     // per stored point * 3, source units
    int64_t tiles = 0;
    int64_t max_tile_points = 0;     // gathered, incl. halo
    size_t  peak_work_bytes = 0;
    double  ms = 0.0;
};

// progress_done / progress_total count core points.
void Na__CleanPipeline__RunFull(const std::shared_ptr<const Na__CloudPoints>& cloud, const Na__CleanGrid& grid,
                                const Na__CleanParams& params, const std::atomic<bool>* cancel,
                                std::atomic<int64_t>* progress_done, std::atomic<int64_t>* progress_total,
                                Na__CleanFullResult& result);
