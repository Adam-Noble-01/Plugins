// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - LAS IMPORT
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__LasImport__.hpp
// PURPOSE    : Reads LAS through the vendored LASzip C API.
//                - Na__Las__ReadHeader: header facts + VLR scan (fast, no points)
//                - Na__LasImportJob   : full read on ONE worker thread with
//                  atomic progress and cancel, producing an engine point cloud
//
// COORDINATES: points are stored in the SOURCE UNIT, relative to a local
//   origin (header bounds: centre x, centre y, minimum z). The unit factor and
//   any user transform are applied per frame through the render matrix - the
//   stored data never changes when the user moves or rotates the cloud.
//
// ORDER: points are shuffled (deterministic Fisher-Yates, fixed seed) so that
//   "the first N points" - the point budget - is a uniform sample of the whole
//   cloud rather than whichever patch the scanner wrote first.
//
// THREADING: the worker touches only this job's own buffers and the LASzip
//   reader. Results are published with a release store on `finished`.
//
// =============================================================================

#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "Na__PointCloudViewer__NativeEngine__Rasterizer__.hpp"

struct Na__LasHeaderInfo {
    int     version_major = 0;
    int     version_minor = 0;
    int     point_format = 0;
    int     record_length = 0;
    int64_t point_count = 0;
    double  scale[3]  = { 0, 0, 0 };
    double  offset[3] = { 0, 0, 0 };
    double  min[3]    = { 0, 0, 0 };
    double  max[3]    = { 0, 0, 0 };
    bool    has_rgb = false;
    int     vlr_count = 0;
    bool    has_wkt = false;
    bool    has_geokeys = false;
    bool    is_compressed = false;
    std::string system_id;
    std::string software;
    std::string wkt;
};

bool Na__Las__ReadHeader(const char* path_utf8, Na__LasHeaderInfo& info, std::string& error);
bool Na__Las__FormatHasRgb(int point_format);

enum Na__LasImportPhase {
    NA_LAS_PHASE_STARTING = 0,
    NA_LAS_PHASE_READING  = 1,    // LAS records, or the cache file when loading one
    NA_LAS_PHASE_COLOURS  = 2,
    NA_LAS_PHASE_SHUFFLE  = 3,
    NA_LAS_PHASE_SAVING   = 4,    // writing the point cache for next time
    NA_LAS_PHASE_DONE     = 5
};

struct Na__LasImportJob {
    // inputs (set before the thread starts)
    std::string path;                     // the LAS, or the cache file when from_cache
    std::string cache_path;               // LAS import: also write this cache ("" = none)
    bool        from_cache = false;
    int64_t     expect_count = 0;         // cache load: refuse a different point count
    double      las_bytes = 0;            // stored in the cache header
    double      las_mtime = 0;
    uint8_t     fallback_rgb[3] = { 110, 110, 110 };
    uint64_t    seed = 0x4E41504331ull;   // "NAPC1"

    // progress (any thread)
    std::atomic<int>     phase{ NA_LAS_PHASE_STARTING };
    std::atomic<int64_t> done{ 0 };
    std::atomic<int64_t> total{ 0 };
    std::atomic<bool>    cancel_requested{ false };
    std::atomic<bool>    finished{ false };
    std::atomic<bool>    failed{ false };
    std::atomic<bool>    cancelled{ false };
    std::atomic<int>     cache_state{ 0 };   // 0 none, 1 written / loaded, -1 failed

    // results (valid after finished == true)
    std::unique_ptr<Na__PointCloud> cloud;
    double  origin[3]    = { 0, 0, 0 };
    double  local_min[3] = { 0, 0, 0 };
    double  local_max[3] = { 0, 0, 0 };
    int     colour_bits = 0;          // 16, 8, or 0 when the format has no RGB
    int64_t point_count = 0;
    double  read_ms = 0, colour_ms = 0, shuffle_ms = 0, total_ms = 0;

    std::mutex  error_mutex;
    std::string error;

    std::thread worker;
};

// Starts the worker. The job owns the thread; Na__LasJob__Destroy cancels and joins.
void Na__LasJob__Start(Na__LasImportJob* job);
void Na__LasJob__Destroy(Na__LasImportJob* job);
