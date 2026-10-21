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
//   5 (v0.8.0): source record identity + time in clouds, cache v2, LAS content
//               key, the cleaning engine (preview context + export job).
//   6 (v0.9.1): the LAZ to LAS converter (napc_laz_convert_*).
#define NAPC_ABI_VERSION 6

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
    NAPC_J_FLAGS,                   // bit 0 the cloud knows its LAS records, bit 1 it has GPS time
    NAPC_J_TIME_BASE,               // GPS time of the first LAS record
    NAPC_J_KEY_HI, NAPC_J_KEY_LO,   // content key: of the LAS (import) or recorded in the cache (load)
    NAPC_J_CACHE_VERSION,           // cache load: 1 or 2
    NAPC_J_COUNT
};

// Cache header facts (napc_cache_peek) - doubles.
enum Na__CacheInfoIndex {
    NAPC_C_POINT_COUNT = 0, NAPC_C_ORIGIN_X, NAPC_C_ORIGIN_Y, NAPC_C_ORIGIN_Z,
    NAPC_C_MIN_X, NAPC_C_MIN_Y, NAPC_C_MIN_Z, NAPC_C_MAX_X, NAPC_C_MAX_Y, NAPC_C_MAX_Z,
    NAPC_C_COLOUR_BITS, NAPC_C_LAS_BYTES, NAPC_C_LAS_MTIME, NAPC_C_VERSION,
    NAPC_C_FLAGS, NAPC_C_KEY_HI, NAPC_C_KEY_LO, NAPC_C_TIME_BASE,
    NAPC_C_COUNT
};

NAPC_API int32_t     napc_abi_version(void);
NAPC_API int32_t     napc_thread_count(void);
NAPC_API const char* napc_last_error(void);

// xyz: count * 3 float32 (local units), rgb: count * 3 uint8. Returns an opaque handle or null.
NAPC_API void*       napc_cloud_create(const float* xyz, const uint8_t* rgb, int64_t count);
// As create, plus optional per-point LAS record numbers and GPS times (null = none).
NAPC_API void*       napc_cloud_create_ex(const float* xyz, const uint8_t* rgb, const uint32_t* source_index,
                                          const float* time, double time_base, int64_t count);
NAPC_API void        napc_cloud_destroy(void* cloud);
// out: [count, has source index, has time, time base]. Returns 0, or < 0.
NAPC_API int32_t     napc_cloud_info(void* cloud, double* out, int32_t out_count);
// Copies stored points [first, first + count) out (diagnostics and tests). Any
// output may be null; source_index / time are left untouched when the cloud has none.
NAPC_API int32_t     napc_cloud_read(void* cloud, int64_t first, int64_t count, float* xyz, uint32_t* bgra,
                                     uint32_t* source_index, float* time);

// Renders the cloud for one camera into an uncompressed RGBA PNG at path_utf8.
NAPC_API int32_t     napc_render_png(void* cloud, const double* params, int32_t param_count,
                                     const char* path_utf8, double* stats, int32_t stat_count);

// --- LAS (LASzip) ------------------------------------------------------------
// Header + VLR facts. text receives "system_id\tgenerating_software\twkt" (truncated to text_cap).
NAPC_API int32_t     napc_las_read_header(const char* path_utf8, double* info, int32_t info_count,
                                          char* text, int32_t text_cap);

// Content key of a LAS file (see LasFile.cpp): out[0] = high 32 bits, out[1] =
// low 32 bits (each exact in a double). Reads about 2 MB. 0, or < 0 on failure.
NAPC_API int32_t     napc_las_content_key(const char* path_utf8, double* out, int32_t out_count);

// Starts reading every point on a worker thread; with a cache path, the worker
// also writes the point cache once the cloud is ready.
// params: [fallback_r, fallback_g, fallback_b, las_bytes, las_mtime_unix, key_hi, key_lo].
// Returns a job handle (or null - see napc_last_error).
NAPC_API void*       napc_las_import_start(const char* path_utf8, const char* cache_path_utf8,
                                           const double* params, int32_t param_count);
// Loads a point cache on a worker thread (same job API).
// params: [expected_point_count or 0, expected key_hi, key_lo (0, 0 = any)].
NAPC_API void*       napc_cache_load_start(const char* cache_path_utf8, const double* params, int32_t param_count);
// Reads and validates a cache header (Na__CacheInfoIndex). 0 = valid, < 0 = missing or invalid.
NAPC_API int32_t     napc_cache_peek(const char* cache_path_utf8, double* out, int32_t out_count);
// Fills NAPC_J_COUNT doubles. Returns 1 when finished (success, failure or cancel), else 0.
NAPC_API int32_t     napc_job_poll(void* job, double* out, int32_t out_count);
NAPC_API int32_t     napc_job_error(void* job, char* text, int32_t text_cap);
NAPC_API void        napc_job_cancel(void* job);
// Hands the finished cloud to the caller (destroy with napc_cloud_destroy). Null if none.
NAPC_API void*       napc_job_take_cloud(void* job);
// Cancels if still running, joins the worker, frees the job.
NAPC_API void        napc_job_destroy(void* job);

// --- Cleaning (see CleanTypes.hpp for the parameter, flag and stat layouts) ------
// A context belongs to one loaded cloud. It shares the cloud's points (the
// cloud handle may be released while it works) and owns one preview worker.
NAPC_API void*       napc_clean_create(void* cloud, double mm_per_unit);
// Cancels and joins the preview worker, then frees the context.
NAPC_API void        napc_clean_destroy(void* ctx);

// Preview: region = NAPC_REGION_COUNT doubles, params = NAPC_CP_COUNT doubles.
// Returns the request id (> 0); a newer request cancels and replaces an older one.
NAPC_API int64_t     napc_clean_preview_request(void* ctx, const double* region, int32_t region_count,
                                                const double* params, int32_t param_count);
NAPC_API void        napc_clean_preview_cancel(void* ctx);
// out: [state (0 idle, 1 running, 2 done, 3 failed, 4 cancelled), finished request id,
//       running request id, grid ready]. Returns state.
NAPC_API int32_t     napc_clean_preview_poll(void* ctx, double* out, int32_t out_count);
NAPC_API int32_t     napc_clean_preview_stats(void* ctx, double* out, int32_t out_count);
NAPC_API int32_t     napc_clean_preview_error(void* ctx, char* text, int32_t text_cap);
// A new cloud of the finished preview's core points: which 0 = cleaned (kept
// points, refined, own colours), 1 = differences (every point, coloured by
// verdict; colours = NAPC_DIFF_COLOURS doubles). Caller owns it (napc_cloud_destroy).
NAPC_API void*       napc_clean_preview_cloud(void* ctx, int32_t which, const double* colours, int32_t colour_count);
// Per-point results of the finished preview (sorted by stored index). Returns
// the count; arrays may be null to ask for the count only.
NAPC_API int64_t     napc_clean_preview_points(void* ctx, uint32_t* stored, uint16_t* flags, float* delta, int64_t cap);

#define NAPC_DIFF_COLOURS 22   // removed, moved small, moved max, candidate, doubling, thinned, unchanged tint (rgb each) + tint share

// Diagnostics (tests): the surface analysis of every analysed cell that holds a
// core point of the finished preview, NAPC_CELL_DEBUG doubles each:
// [centre xyz, families, cell flags, sigma, then per family (3 x 12):
//  normal xyz, sheets, sheet 0..2 offsets, family flags, confidence, gap, sigma, members,
//  then planes lent by thin cells nearby, planes found, and the thin test's
//  measurements: block thickness, in-plane pair sigma, robust plane angle (deg),
//  robust plane inlier share].
// Only while the preview worker is idle. Returns the cell count.
#define NAPC_CELL_DEBUG 48
NAPC_API int64_t     napc_clean_debug_cells(void* ctx, double* out, int64_t cap_cells);

// Export: cleans the WHOLE cloud and writes dest_utf8 as a NEW LAS (never
// replacing anything), checked and published. dest_utf8 = null: clean only
// (results via napc_clean_export_points). origin = the cloud's local origin.
NAPC_API void*       napc_clean_export_start(void* ctx, const char* source_utf8, const char* dest_utf8,
                                             const double* params, int32_t param_count, const double* origin,
                                             const char* provenance_json, const char* software);
// Fills NAPC_E_COUNT doubles. Returns 1 when finished (success, failure or cancel).
NAPC_API int32_t     napc_clean_export_poll(void* job, double* out, int32_t out_count);
NAPC_API int32_t     napc_clean_export_error(void* job, char* text, int32_t text_cap);
NAPC_API int32_t     napc_clean_export_notes(void* job, char* text, int32_t text_cap);
NAPC_API void        napc_clean_export_cancel(void* job);
NAPC_API int64_t     napc_clean_export_points(void* job, uint16_t* flags, float* delta, int64_t cap);
// Cancels if running, joins, frees (and deletes any partial file).
NAPC_API void        napc_clean_export_destroy(void* job);

enum Na__ExportPollIndex {
    NAPC_E_PHASE = 0, NAPC_E_DONE, NAPC_E_TOTAL, NAPC_E_FINISHED, NAPC_E_FAILED, NAPC_E_CANCELLED,
    NAPC_E_SOURCE_POINTS, NAPC_E_WRITTEN, NAPC_E_MOVED, NAPC_E_REMOVED, NAPC_E_HELD_RANGE,
    NAPC_E_REMOVED_ISOLATED, NAPC_E_REMOVED_CLUSTER, NAPC_E_REMOVED_BLOWOUT, NAPC_E_REMOVED_DENSITY,
    NAPC_E_DOUBLING, NAPC_E_CANDIDATES,
    NAPC_E_MIN_X, NAPC_E_MIN_Y, NAPC_E_MIN_Z, NAPC_E_MAX_X, NAPC_E_MAX_Y, NAPC_E_MAX_Z,
    NAPC_E_BYTES, NAPC_E_KEY_HI, NAPC_E_KEY_LO,
    NAPC_E_CLEAN_MS, NAPC_E_WRITE_MS, NAPC_E_VERIFY_MS, NAPC_E_TOTAL_MS,
    NAPC_E_TILES, NAPC_E_MAX_TILE_POINTS, NAPC_E_PEAK_WORK_MB,
    NAPC_E_BY_RETURN_MISMATCH, NAPC_E_DROPPED_VLRS, NAPC_E_DROPPED_EVLRS, NAPC_E_GRID_MS,
    NAPC_E_COUNT
};

// --- LAZ to LAS (LazConvert.hpp) ---------------------------------------------------
// Decompresses source_utf8 (a .laz) into dest_utf8, a NEW uncompressed LAS (never
// replacing anything), checked and published on a worker thread.
NAPC_API void*       napc_laz_convert_start(const char* source_utf8, const char* dest_utf8);
// Fills NAPC_Z_COUNT doubles. Returns 1 when finished (success, failure or cancel).
NAPC_API int32_t     napc_laz_convert_poll(void* job, double* out, int32_t out_count);
NAPC_API int32_t     napc_laz_convert_error(void* job, char* text, int32_t text_cap);
NAPC_API int32_t     napc_laz_convert_notes(void* job, char* text, int32_t text_cap);
NAPC_API void        napc_laz_convert_cancel(void* job);
// Cancels if running, joins, frees (and deletes any partial file).
NAPC_API void        napc_laz_convert_destroy(void* job);

enum Na__LazPollIndex {
    NAPC_Z_PHASE = 0, NAPC_Z_DONE, NAPC_Z_TOTAL, NAPC_Z_FINISHED, NAPC_Z_FAILED, NAPC_Z_CANCELLED,
    NAPC_Z_POINT_COUNT, NAPC_Z_POINT_FORMAT, NAPC_Z_RECORD_LENGTH, NAPC_Z_VERSION_MAJOR, NAPC_Z_VERSION_MINOR,
    NAPC_Z_SOURCE_BYTES, NAPC_Z_WRITTEN_BYTES,
    NAPC_Z_HEADER_MIN_X, NAPC_Z_HEADER_MIN_Y, NAPC_Z_HEADER_MIN_Z, NAPC_Z_HEADER_MAX_X, NAPC_Z_HEADER_MAX_Y, NAPC_Z_HEADER_MAX_Z,
    NAPC_Z_POINT_MIN_X, NAPC_Z_POINT_MIN_Y, NAPC_Z_POINT_MIN_Z, NAPC_Z_POINT_MAX_X, NAPC_Z_POINT_MAX_Y, NAPC_Z_POINT_MAX_Z,
    NAPC_Z_DROPPED_RECORDS, NAPC_Z_CONVERT_MS, NAPC_Z_CHECK_MS, NAPC_Z_TOTAL_MS,
    NAPC_Z_COUNT
};

// Stops and joins the worker threads. Call before unloading the DLL.
NAPC_API void        napc_shutdown(void);
