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
#include "Na__PointCloudViewer__NativeEngine__LasFile__.hpp"
#include "Na__PointCloudViewer__NativeEngine__LasImport__.hpp"
#include "Na__PointCloudViewer__NativeEngine__LazConvert__.hpp"
#include "Na__PointCloudViewer__NativeEngine__PngWriter__.hpp"
#include "Na__PointCloudViewer__NativeEngine__PointCache__.hpp"
#include "Na__PointCloudViewer__NativeEngine__Rasterizer__.hpp"
#include "Na__PointCloudViewer__NativeEngine__ThreadPool__.hpp"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <thread>

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

NAPC_API int32_t napc_render_png(void* cloud_handle, const double* params, int32_t param_count,
                                 const char* path_utf8, double* stats, int32_t stat_count) {
    if (!cloud_handle) return Na__Fail("No point cloud is loaded in the native engine.", -1);
    if (!params || param_count < NAPC_P_COUNT) return Na__Fail("Render parameters are missing.", -2);
    if (!path_utf8) return Na__Fail("No output path was given.", -3);

    const auto total_start = std::chrono::steady_clock::now();
    std::lock_guard<std::mutex> lock(g_render_mutex);
    try {
        if (!g_buffers) g_buffers = new Na__FrameBuffers();
        const Na__PointCloud& cloud = *static_cast<const Na__PointCloud*>(cloud_handle);

        Na__RasterStats raster;
        std::string error;
        if (!Na__Raster__Render(cloud, params, Na__Pool(), *g_buffers, raster, error)) return Na__Fail(error.c_str(), -4);

        Na__PngTimings png;
        const int width = static_cast<int>(params[NAPC_P_WIDTH]);
        const int height = static_cast<int>(params[NAPC_P_HEIGHT]);
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
    } catch (const std::bad_alloc&) {
        return Na__Fail("Not enough memory for the render image.", -6);
    } catch (...) {
        return Na__Fail("The native renderer failed unexpectedly.", -7);
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
