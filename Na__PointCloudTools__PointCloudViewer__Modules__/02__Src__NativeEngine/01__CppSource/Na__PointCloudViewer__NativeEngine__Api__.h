// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - C API
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__Api__.h
// PURPOSE    : The whole Ruby <-> native boundary. A plain C ABI loaded from
//              Ruby with Fiddle - no Ruby headers, no Ruby objects, no SketchUp
//              API on this side. Ruby passes packed buffers and a parameter
//              array; the engine returns status codes and fills stats arrays.
//
// RULES:
//   - Never call back into Ruby or SketchUp.
//   - Worker threads only touch engine-owned memory.
//   - Every input buffer is COPIED before the call returns; Ruby may free it.
//   - Return codes: >= 0 success, < 0 failure (message in napc_last_error).
//
// =============================================================================

#pragma once

#include <cstdint>

#ifdef _WIN32
#define NAPC_API extern "C" __declspec(dllexport)
#else
#define NAPC_API extern "C"
#endif

// Bumped whenever a signature or the render parameter layout changes. The Ruby
// bridge refuses a DLL whose ABI it does not know.
#define NAPC_ABI_VERSION 4

// Render parameter layout (doubles), shared with the Ruby bridge.
enum Na__RenderParamIndex {
    NAPC_P_EYE_X = 0, NAPC_P_EYE_Y, NAPC_P_EYE_Z,
    NAPC_P_XAXIS_X, NAPC_P_XAXIS_Y, NAPC_P_XAXIS_Z,
    NAPC_P_YAXIS_X, NAPC_P_YAXIS_Y, NAPC_P_YAXIS_Z,
    NAPC_P_ZAXIS_X, NAPC_P_ZAXIS_Y, NAPC_P_ZAXIS_Z,
    NAPC_P_IS_PERSPECTIVE,          // 1 = perspective, 0 = parallel
    NAPC_P_SCALE_X, NAPC_P_SCALE_Y, // ndc = cam_xy / cam_z * scale (perspective) or cam_xy * scale (parallel)
    NAPC_P_WIDTH, NAPC_P_HEIGHT,    // output image pixels
    NAPC_P_POINT_SIZE,              // splat diameter in output pixels (>= 1)
    NAPC_P_OPACITY,                 // 0..1
    NAPC_P_COLOUR_MODE,             // 0 = RGB, 1 = monochrome
    NAPC_P_MONO_R, NAPC_P_MONO_G, NAPC_P_MONO_B,
    NAPC_P_BUDGET,                  // max points drawn: the first N (points are stored in random order);
                                    // with the clip on, the first N INSIDE the box
    NAPC_P_NEAR,                    // perspective near distance, model inches
    NAPC_P_M00, NAPC_P_M01, NAPC_P_M02, NAPC_P_M10, NAPC_P_M11, NAPC_P_M12,
    NAPC_P_M20, NAPC_P_M21, NAPC_P_M22, NAPC_P_TX, NAPC_P_TY, NAPC_P_TZ,   // local -> model inches
    NAPC_P_CLIP_ENABLED,                                                  // 1 = hide points outside the box
    NAPC_P_CLIP_MIN_X, NAPC_P_CLIP_MIN_Y, NAPC_P_CLIP_MIN_Z,              // clip box, MODEL inches,
    NAPC_P_CLIP_MAX_X, NAPC_P_CLIP_MAX_Y, NAPC_P_CLIP_MAX_Z,              // axis-aligned to the model
    NAPC_P_FULL_WIDTH, NAPC_P_FULL_HEIGHT,  // the whole viewport in output pixels (projection centre)
    NAPC_P_CROP_X, NAPC_P_CROP_Y,           // where the output image (WIDTH x HEIGHT) starts in it
    NAPC_P_COUNT
};

// Render stats layout (doubles) written by napc_render_png.
enum Na__RenderStatIndex {
    NAPC_S_POINTS_TESTED = 0, NAPC_S_POINTS_ON_SCREEN, NAPC_S_THREADS,
    NAPC_S_CLEAR_MS, NAPC_S_RASTER_MS, NAPC_S_RESOLVE_MS, NAPC_S_ENCODE_MS, NAPC_S_WRITE_MS, NAPC_S_TOTAL_MS,
    NAPC_S_PNG_BYTES,
    NAPC_S_COUNT
};

// LAS header facts (napc_las_read_header) - doubles.
enum Na__LasInfoIndex {
    NAPC_L_VERSION_MAJOR = 0, NAPC_L_VERSION_MINOR, NAPC_L_POINT_FORMAT, NAPC_L_RECORD_LENGTH, NAPC_L_POINT_COUNT,
    NAPC_L_SCALE_X, NAPC_L_SCALE_Y, NAPC_L_SCALE_Z, NAPC_L_OFFSET_X, NAPC_L_OFFSET_Y, NAPC_L_OFFSET_Z,
    NAPC_L_MIN_X, NAPC_L_MIN_Y, NAPC_L_MIN_Z, NAPC_L_MAX_X, NAPC_L_MAX_Y, NAPC_L_MAX_Z,
    NAPC_L_HAS_RGB, NAPC_L_VLR_COUNT, NAPC_L_HAS_WKT, NAPC_L_HAS_GEOKEYS, NAPC_L_IS_COMPRESSED,
    NAPC_L_COUNT
};

// Import job progress (napc_job_poll) - doubles.
enum Na__JobPollIndex {
    NAPC_J_PHASE = 0, NAPC_J_DONE, NAPC_J_TOTAL, NAPC_J_FINISHED, NAPC_J_FAILED, NAPC_J_CANCELLED,
    NAPC_J_READ_MS, NAPC_J_COLOUR_MS, NAPC_J_SHUFFLE_MS, NAPC_J_TOTAL_MS, NAPC_J_COLOUR_BITS,
    NAPC_J_ORIGIN_X, NAPC_J_ORIGIN_Y, NAPC_J_ORIGIN_Z,
    NAPC_J_MIN_X, NAPC_J_MIN_Y, NAPC_J_MIN_Z, NAPC_J_MAX_X, NAPC_J_MAX_Y, NAPC_J_MAX_Z,
    NAPC_J_POINT_COUNT,
    NAPC_J_CACHE_STATE,             // 0 none, 1 cache written (import) / loaded (cache), -1 failed
    NAPC_J_COUNT
};

#define NAPC_C_COUNT 14

NAPC_API int32_t     napc_abi_version(void);
NAPC_API int32_t     napc_thread_count(void);
NAPC_API const char* napc_last_error(void);

// xyz: count * 3 float32 (local units), rgb: count * 3 uint8. Returns an opaque handle or null.
NAPC_API void*       napc_cloud_create(const float* xyz, const uint8_t* rgb, int64_t count);
NAPC_API void        napc_cloud_destroy(void* cloud);

// Renders the cloud for one camera into an uncompressed RGBA PNG at path_utf8.
NAPC_API int32_t     napc_render_png(void* cloud, const double* params, int32_t param_count,
                                     const char* path_utf8, double* stats, int32_t stat_count);

// --- LAS (LASzip) ------------------------------------------------------------
// Header + VLR facts. text receives "system_id\tgenerating_software\twkt" (truncated to text_cap).
NAPC_API int32_t     napc_las_read_header(const char* path_utf8, double* info, int32_t info_count,
                                          char* text, int32_t text_cap);

// Starts reading every point on a worker thread; with a cache path, the worker
// also writes the point cache once the cloud is ready.
// params: [fallback_r, fallback_g, fallback_b, las_bytes, las_mtime_unix].
// Returns a job handle (or null - see napc_last_error).
NAPC_API void*       napc_las_import_start(const char* path_utf8, const char* cache_path_utf8,
                                           const double* params, int32_t param_count);
// Loads a point cache on a worker thread (same job API). params: [expected_point_count or 0].
NAPC_API void*       napc_cache_load_start(const char* cache_path_utf8, const double* params, int32_t param_count);
// Reads and validates a cache header. out: [count, origin xyz, min xyz, max xyz, colour_bits,
// las_bytes, las_mtime, version] (NAPC_C_COUNT). 0 = valid, < 0 = missing or invalid.
NAPC_API int32_t     napc_cache_peek(const char* cache_path_utf8, double* out, int32_t out_count);
// Fills NAPC_J_COUNT doubles. Returns 1 when finished (success, failure or cancel), else 0.
NAPC_API int32_t     napc_job_poll(void* job, double* out, int32_t out_count);
NAPC_API int32_t     napc_job_error(void* job, char* text, int32_t text_cap);
NAPC_API void        napc_job_cancel(void* job);
// Hands the finished cloud to the caller (destroy with napc_cloud_destroy). Null if none.
NAPC_API void*       napc_job_take_cloud(void* job);
// Cancels if still running, joins the worker, frees the job.
NAPC_API void        napc_job_destroy(void* job);

// Stops and joins the worker threads. Call before unloading the DLL.
NAPC_API void        napc_shutdown(void);
