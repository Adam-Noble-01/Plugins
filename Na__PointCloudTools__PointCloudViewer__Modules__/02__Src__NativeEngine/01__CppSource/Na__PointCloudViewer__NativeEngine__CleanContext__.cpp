// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - CLEANING CONTEXT + EXPORT JOB
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__CleanContext__.cpp
// PURPOSE    : The C API of the cleaning engine.
//
//   CONTEXT (one per loaded cloud): holds the cloud's points (shared, so Ruby
//     releasing the cloud handle can never free memory a worker still reads),
//     the global grid (built once, on first use, off the main thread), and ONE
//     preview worker thread. A preview request replaces any pending one and
//     cancels the one running; the worker re-uses every stage whose inputs
//     did not change (CleanPipeline.cpp). Ruby polls; nothing calls back.
//
//   EXPORT JOB: its own thread. Shares the cloud and grid with the context
//     but not its lifetime: the job keeps them alive. Cleans the whole cloud
//     in tiles, then writes, verifies and publishes the LAS (LasExport.cpp).
//
//   BOX EXPORT (v0.11.0, Crop and Cut): the same job, started from a cloud
//     with its Keep and Cut boxes instead of a cleaning context. No grid and
//     no cleaning: every point is tested against the boxes (BoxFilter.hpp,
//     the test the preview and the count use), then the same writer copies
//     the kept records, checks the file and publishes it. Nothing moves.
//
//   SHUTDOWN (DLL hot swap): napc_shutdown stops and joins every worker that
//     is still alive before the pools go, so no thread can run in an unloaded
//     DLL. The Ruby bridge destroys its contexts and jobs first.
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
#include "Na__PointCloudViewer__NativeEngine__CleanPipeline__.hpp"
#include "Na__PointCloudViewer__NativeEngine__LasExport__.hpp"
#include "Na__PointCloudViewer__NativeEngine__LasFile__.hpp"

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <set>
#include <thread>

// -----------------------------------------------------------------------------
// REGION | Types
// -----------------------------------------------------------------------------

struct Na__CleanShared {
    std::shared_ptr<const Na__CloudPoints> cloud;
    double mm_per_unit = 1000.0;
    std::mutex grid_mutex;
    std::shared_ptr<const Na__CleanGrid> grid;
    std::atomic<bool> grid_ready{ false };   // read by polls without waiting on a build

    std::shared_ptr<const Na__CleanGrid> Grid(const std::atomic<bool>* cancel) {
        std::lock_guard<std::mutex> lock(grid_mutex);
        if (!grid) {
            std::shared_ptr<Na__CleanGrid> built(new Na__CleanGrid());
            Na__CleanGrid__Build(*cloud, mm_per_unit, *built, cancel);
            grid = built;
            grid_ready.store(true);
        }
        return grid;
    }
};

struct Na__CleanContext {
    std::shared_ptr<Na__CleanShared> shared;

    std::thread worker;
    std::mutex m;
    std::condition_variable cv;
    bool stopping = false;
    bool has_request = false;
    int64_t next_id = 0;
    Na__CleanRegion req_region;
    Na__CleanParams req_params;
    int64_t req_id = 0;
    std::atomic<bool> cancel{ false };
    std::atomic<int> state{ 0 };            // 0 idle, 1 running, 2 done, 3 failed, 4 cancelled
    std::atomic<int64_t> running_id{ 0 };

    // finished result (guarded by m)
    int64_t result_id = 0;
    std::string error;
    std::vector<double> stats;
    Na__CleanParams result_params;
    std::vector<uint32_t> res_stored;
    std::vector<uint16_t> res_flags;
    std::vector<float> res_delta;

    Na__CleanWork work;                     // worker thread only
};

struct Na__CleanExportJob {
    std::shared_ptr<Na__CleanShared> shared;
    std::string source, dest;               // UTF-8
    bool dry_run = false;
    bool box_mode = false;                  // Crop and Cut: the boxes decide, nothing is cleaned
    Na__BoxFilter boxes;
    Na__CleanParams params;
    double origin[3] = { 0, 0, 0 };
    std::string provenance, software;

    std::thread worker;
    std::atomic<int> phase{ NA_EXPORT_PHASE_CHECKING };
    std::atomic<int64_t> done{ 0 }, total{ 0 };
    std::atomic<bool> cancel{ false }, finished{ false }, failed{ false }, cancelled{ false };

    std::mutex text_mutex;
    std::string error, notes;
    double out[NAPC_E_COUNT] = {};          // valid once finished
    Na__CleanFullResult full;               // dry run keeps it
};

namespace {
    std::mutex g_registry_mutex;
    std::set<Na__CleanContext*> g_contexts;
    std::set<Na__CleanExportJob*> g_jobs;
    thread_local std::string g_clean_error;

    double Na__MsSince(std::chrono::steady_clock::time_point start) {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    }

    int32_t Na__CopyOut(const std::string& source, char* text, int32_t cap) {
        if (!text || cap <= 0) return static_cast<int32_t>(source.size());
        const size_t length = std::min(source.size(), static_cast<size_t>(cap - 1));
        std::memcpy(text, source.data(), length);
        text[length] = '\0';
        return static_cast<int32_t>(length);
    }

    void Na__StopContext(Na__CleanContext* ctx) {
        {
            std::lock_guard<std::mutex> lock(ctx->m);
            ctx->stopping = true;
            ctx->has_request = false;
        }
        ctx->cancel.store(true);
        ctx->cv.notify_all();
        if (ctx->worker.joinable()) ctx->worker.join();
    }

    void Na__StopJob(Na__CleanExportJob* job) {
        job->cancel.store(true);
        if (job->worker.joinable()) job->worker.join();
    }

    // -------------------------------------------------------------------------
    // Preview worker
    // -------------------------------------------------------------------------

    void Na__PreviewWorker(Na__CleanContext* ctx) {
        for (;;) {
            Na__CleanRegion region;
            Na__CleanParams params;
            int64_t id = 0;
            {
                std::unique_lock<std::mutex> lock(ctx->m);
                ctx->cv.wait(lock, [ctx] { return ctx->stopping || ctx->has_request; });
                if (ctx->stopping) return;
                region = ctx->req_region;
                params = ctx->req_params;
                id = ctx->req_id;
                ctx->has_request = false;
                ctx->cancel.store(false);
                ctx->running_id.store(id);
                ctx->state.store(1);
            }
            try {
                const auto start = std::chrono::steady_clock::now();
                std::shared_ptr<const Na__CleanGrid> grid = ctx->shared->Grid(&ctx->cancel);
                Na__CleanWork& w = ctx->work;
                w.cloud = ctx->shared->cloud;
                w.grid = grid.get();
                w.cancel = &ctx->cancel;
                w.region = region;
                Na__CleanPipeline__RunRegion(w, params);

                const auto section_start = std::chrono::steady_clock::now();
                std::vector<double> stats(NAPC_CS_COUNT, 0.0);
                Na__Clean__Section(w, stats.data());
                stats[NAPC_CS_GATHER_MS]  = w.reused & 1 ? 0.0 : w.ms_gather;
                stats[NAPC_CS_INDEX_MS]   = w.reused & 1 ? 0.0 : w.ms_index;
                stats[NAPC_CS_NOISE_MS]   = w.reused & 2 ? 0.0 : w.ms_noise;
                stats[NAPC_CS_SURFACE_MS] = w.reused & 4 ? 0.0 : w.ms_surface;
                stats[NAPC_CS_REFINE_MS]  = w.reused & 8 ? 0.0 : w.ms_refine;
                stats[NAPC_CS_DENSITY_MS] = w.ms_density;
                stats[NAPC_CS_SECTION_MS] = Na__MsSince(section_start);
                stats[NAPC_CS_TOTAL_MS]   = Na__MsSince(start);
                stats[NAPC_CS_REUSED_STAGES] = w.reused;

                std::vector<uint32_t> order;
                for (uint32_t i = 0; i < w.n; ++i) if (w.core[i]) order.push_back(i);
                std::sort(order.begin(), order.end(), [&w](uint32_t a, uint32_t b) { return w.stored[a] < w.stored[b]; });
                std::vector<uint32_t> stored(order.size());
                std::vector<uint16_t> flags(order.size());
                std::vector<float> delta(order.size() * 3);
                for (size_t k = 0; k < order.size(); ++k) {
                    stored[k] = w.stored[order[k]];
                    flags[k] = w.flags[order[k]];
                    std::memcpy(&delta[k * 3], &w.delta[size_t(order[k]) * 3], 12);
                }

                std::lock_guard<std::mutex> lock(ctx->m);
                if (ctx->has_request || ctx->stopping) {
                    ctx->state.store(4);            // superseded before it could be shown
                } else {
                    ctx->result_id = id;
                    ctx->stats.swap(stats);
                    ctx->result_params = params;
                    ctx->res_stored.swap(stored);
                    ctx->res_flags.swap(flags);
                    ctx->res_delta.swap(delta);
                    ctx->error.clear();
                    ctx->state.store(2);
                }
            } catch (const Na__Cancelled&) {
                // every stage marks itself not done on entry, so one cut short is simply redone
                std::lock_guard<std::mutex> lock(ctx->m);
                ctx->state.store(4);
            } catch (const std::bad_alloc&) {
                ctx->work = Na__CleanWork();
                std::lock_guard<std::mutex> lock(ctx->m);
                ctx->error = "Not enough memory for this preview. Make the clip box smaller.";
                ctx->state.store(3);
            } catch (const std::exception& e) {
                ctx->work = Na__CleanWork();
                std::lock_guard<std::mutex> lock(ctx->m);
                ctx->error = std::string("The preview failed: ") + e.what();
                ctx->state.store(3);
            } catch (...) {
                ctx->work = Na__CleanWork();
                std::lock_guard<std::mutex> lock(ctx->m);
                ctx->error = "The preview failed unexpectedly.";
                ctx->state.store(3);
            }
        }
    }

    // -------------------------------------------------------------------------
    // Export worker
    // -------------------------------------------------------------------------

    void Na__ExportFail(Na__CleanExportJob* job, const std::string& message) {
        {
            std::lock_guard<std::mutex> lock(job->text_mutex);
            job->error = message;
        }
        job->failed.store(true);
        job->finished.store(true, std::memory_order_release);
    }

    // Before any cleaning: a destination that exists (above all the source
    // itself) or a folder that does not is refused at once, so nobody waits
    // through a whole clean for it. The final rename refuses to replace
    // anything as well, so a file that appears meanwhile is still safe.
    bool Na__DestinationProblem(const std::string& source_utf8, const std::string& dest_utf8, std::string& problem) {
        const std::wstring dest = Na__Utf8ToWide(dest_utf8), source = Na__Utf8ToWide(source_utf8);
        const DWORD attributes = GetFileAttributesW(dest.c_str());
        if (attributes != INVALID_FILE_ATTRIBUTES) {
            Na__File a, b;
            uint64_t va = 0, ia = 0, vb = 1, ib = 1;
            const bool same = a.OpenRead(dest, false) && b.OpenRead(source, false) && a.Identity(va, ia) && b.Identity(vb, ib) && va == vb && ia == ib;
            problem = same ? "Refused: that is the source LAS itself. The original is never overwritten; choose a new name. Nothing was written."
                           : "That file already exists. Nothing is ever replaced; choose a new name. Nothing was written.";
            return true;
        }
        const size_t slash = dest.find_last_of(L"\\/");
        if (slash != std::wstring::npos && slash > 0) {
            const std::wstring folder = dest.substr(0, slash);
            const DWORD folder_attributes = GetFileAttributesW(folder.c_str());
            if (folder_attributes == INVALID_FILE_ATTRIBUTES || !(folder_attributes & FILE_ATTRIBUTE_DIRECTORY)) {
                problem = "The destination folder does not exist or cannot be reached. Nothing was written.";
                return true;
            }
        }
        return false;
    }

    // Crop and Cut: every point gets the boxes' verdict, in stored order, on
    // the job's own thread (a fraction of a second for tens of millions of
    // points; the writing and the check that follow take far longer).
    void Na__MarkBoxes(Na__CleanExportJob* job, double* o) {
        const auto start = std::chrono::steady_clock::now();
        const Na__CloudPoints& points = *job->shared->cloud;
        const int64_t n = points.count;
        job->full.flags.assign(static_cast<size_t>(n), 0);
        job->full.delta.clear();
        job->total.store(n);
        job->done.store(0);
        const float* xyz = points.xyz.data();
        const int64_t step = int64_t(1) << 20;
        int64_t outside = 0, inside = 0;
        for (int64_t base = 0; base < n; base += step) {
            Na__CheckCancel(&job->cancel);
            const int64_t end = std::min(n, base + step);
            for (int64_t i = base; i < end; ++i) {
                const int verdict = job->boxes.Verdict(xyz[i * 3], xyz[i * 3 + 1], xyz[i * 3 + 2]);
                if (verdict == NA_BOX_OUTSIDE_KEEP) {
                    job->full.flags[static_cast<size_t>(i)] = NA_CF_REMOVED_KEEP;
                    ++outside;
                } else if (verdict == NA_BOX_INSIDE_CUT) {
                    job->full.flags[static_cast<size_t>(i)] = NA_CF_REMOVED_CUT;
                    ++inside;
                }
            }
            job->done.store(end);
        }
        job->full.ms = Na__MsSince(start);
        o[NAPC_E_REMOVED_KEEP] = static_cast<double>(outside);
        o[NAPC_E_REMOVED_CUT] = static_cast<double>(inside);
        o[NAPC_E_CLEAN_MS] = job->full.ms;
    }

    void Na__ExportWorker(Na__CleanExportJob* job) {
        const auto start = std::chrono::steady_clock::now();
        double* o = job->out;
        try {
            if (!job->dry_run) {
                std::string problem;
                if (Na__DestinationProblem(job->source, job->dest, problem)) return Na__ExportFail(job, problem);
            }
            if (job->box_mode) {
                job->phase.store(NA_EXPORT_PHASE_CLEANING);
                Na__MarkBoxes(job, o);
            } else {
                job->phase.store(NA_EXPORT_PHASE_INDEXING);
                const auto grid_start = std::chrono::steady_clock::now();
                std::shared_ptr<const Na__CleanGrid> grid = job->shared->Grid(&job->cancel);
                o[NAPC_E_GRID_MS] = Na__MsSince(grid_start);

                job->phase.store(NA_EXPORT_PHASE_CLEANING);
                Na__CleanPipeline__RunFull(job->shared->cloud, *grid, job->params, &job->cancel, &job->done, &job->total, job->full);
                o[NAPC_E_CLEAN_MS] = job->full.ms;
                o[NAPC_E_TILES] = static_cast<double>(job->full.tiles);
                o[NAPC_E_MAX_TILE_POINTS] = static_cast<double>(job->full.max_tile_points);
                o[NAPC_E_PEAK_WORK_MB] = job->full.peak_work_bytes / 1048576.0;
                for (uint16_t f : job->full.flags) {
                    if (f & NA_CF_REMOVED_ISOLATED) o[NAPC_E_REMOVED_ISOLATED] += 1;
                    if (f & NA_CF_REMOVED_CLUSTER) o[NAPC_E_REMOVED_CLUSTER] += 1;
                    if (f & NA_CF_REMOVED_BLOWOUT) o[NAPC_E_REMOVED_BLOWOUT] += 1;
                    if ((f & NA_CF_REMOVED_DENSITY) && !(f & NA_CF_REMOVED_NOISE)) o[NAPC_E_REMOVED_DENSITY] += 1;
                    if (f & NA_CF_DOUBLING) o[NAPC_E_DOUBLING] += 1;
                    if (f & NA_CF_CANDIDATE) o[NAPC_E_CANDIDATES] += 1;
                }
            }
            o[NAPC_E_SOURCE_POINTS] = static_cast<double>(job->shared->cloud->count);

            if (!job->dry_run) {
                const auto write_start = std::chrono::steady_clock::now();
                Na__LasExportInput input;
                input.source = Na__Utf8ToWide(job->source);
                input.final_path = Na__Utf8ToWide(job->dest);
                input.cloud = job->shared->cloud.get();
                input.flags = &job->full.flags;
                input.delta = job->box_mode ? nullptr : &job->full.delta;
                for (int a = 0; a < 3; ++a) input.origin[a] = job->origin[a];
                input.provenance_json = job->provenance;
                input.software = job->software;
                Na__LasExportResult result;
                std::string error;
                bool cancelled = false;
                const bool ok = Na__LasExport__Run(input, job->phase, job->done, job->total, job->cancel, cancelled, result, error);
                {
                    std::lock_guard<std::mutex> lock(job->text_mutex);
                    job->notes = result.notes;
                }
                if (cancelled) {
                    job->cancelled.store(true);
                    job->finished.store(true, std::memory_order_release);
                    return;
                }
                if (!ok) return Na__ExportFail(job, error);
                o[NAPC_E_WRITTEN] = static_cast<double>(result.written_points);
                o[NAPC_E_MOVED] = static_cast<double>(result.moved_points);
                o[NAPC_E_REMOVED] = static_cast<double>(result.removed_points);
                o[NAPC_E_HELD_RANGE] = static_cast<double>(result.held_range);
                for (int a = 0; a < 3; ++a) { o[NAPC_E_MIN_X + a] = result.min[a]; o[NAPC_E_MAX_X + a] = result.max[a]; }
                o[NAPC_E_BYTES] = static_cast<double>(result.bytes);
                o[NAPC_E_BY_RETURN_MISMATCH] = result.by_return_mismatch ? 1 : 0;
                o[NAPC_E_DROPPED_VLRS] = result.dropped_vlrs;
                o[NAPC_E_DROPPED_EVLRS] = result.dropped_evlrs;
                o[NAPC_E_WRITE_MS] = Na__MsSince(write_start);
                uint64_t key = 0;
                std::string key_error;
                if (Na__LasFile__ContentKey(input.final_path, key, key_error)) {
                    o[NAPC_E_KEY_HI] = static_cast<double>(key >> 32);
                    o[NAPC_E_KEY_LO] = static_cast<double>(key & 0xFFFFFFFFull);
                }
            } else {
                uint64_t moved = 0, removed = 0;
                for (uint16_t f : job->full.flags) { if (f & NA_CF_REMOVED_ANY) ++removed; else if (f & NA_CF_MOVED) ++moved; }
                o[NAPC_E_MOVED] = static_cast<double>(moved);
                o[NAPC_E_REMOVED] = static_cast<double>(removed);
                o[NAPC_E_WRITTEN] = o[NAPC_E_SOURCE_POINTS] - static_cast<double>(removed);
            }
            o[NAPC_E_TOTAL_MS] = Na__MsSince(start);
            job->phase.store(NA_EXPORT_PHASE_DONE);
            job->finished.store(true, std::memory_order_release);
        } catch (const Na__Cancelled&) {
            job->cancelled.store(true);
            job->finished.store(true, std::memory_order_release);
        } catch (const std::bad_alloc&) {
            Na__ExportFail(job, "Not enough memory to clean the whole cloud. Close other applications and try again. Nothing was written.");
        } catch (const std::exception& e) {
            Na__ExportFail(job, std::string("Cleaning failed: ") + e.what() + ". Nothing was written.");
        } catch (...) {
            Na__ExportFail(job, "Cleaning failed unexpectedly. Nothing was written.");
        }
    }

    bool Na__RegionFromArray(const double* v, int32_t count, Na__CleanRegion& r) {
        if (!v || count < NAPC_REGION_COUNT) return false;
        std::memcpy(r.m, v, sizeof(r.m));
        std::memcpy(r.t, v + 9, sizeof(r.t));
        std::memcpy(r.lo, v + 12, sizeof(r.lo));
        std::memcpy(r.hi, v + 15, sizeof(r.hi));
        r.frame_per_unit = v[18];
        r.half_open = false;
        for (int a = 0; a < 3; ++a) if (!(r.hi[a] > r.lo[a])) return false;
        return r.frame_per_unit > 0;
    }

    uint32_t Na__Rgb(const double* c) {
        auto ch = [](double v) { return static_cast<uint32_t>(std::min(255.0, std::max(0.0, v))); };
        return 0xFF000000u | (ch(c[0]) << 16) | (ch(c[1]) << 8) | ch(c[2]);
    }

    uint32_t Na__Blend(uint32_t a, uint32_t b, double t) {
        t = std::min(1.0, std::max(0.0, t));
        uint32_t out = 0xFF000000u;
        for (int shift = 0; shift < 24; shift += 8) {
            const double ca = (a >> shift) & 0xFF, cb = (b >> shift) & 0xFF;
            out |= static_cast<uint32_t>(ca + (cb - ca) * t + 0.5) << shift;
        }
        return out;
    }

} // namespace

// -----------------------------------------------------------------------------
// REGION | Context API
// -----------------------------------------------------------------------------

NAPC_API void* napc_clean_create(void* cloud_handle, double mm_per_unit) {
    const Na__PointCloud* cloud = static_cast<const Na__PointCloud*>(cloud_handle);
    if (!cloud || !cloud->points || !(mm_per_unit > 0)) return nullptr;
    try {
        Na__CleanContext* ctx = new Na__CleanContext();
        ctx->shared = std::make_shared<Na__CleanShared>();
        ctx->shared->cloud = cloud->points;
        ctx->shared->mm_per_unit = mm_per_unit;
        ctx->worker = std::thread(Na__PreviewWorker, ctx);
        std::lock_guard<std::mutex> lock(g_registry_mutex);
        g_contexts.insert(ctx);
        return ctx;
    } catch (...) {
        return nullptr;
    }
}

NAPC_API void napc_clean_destroy(void* handle) {
    Na__CleanContext* ctx = static_cast<Na__CleanContext*>(handle);
    if (!ctx) return;
    {
        std::lock_guard<std::mutex> lock(g_registry_mutex);
        g_contexts.erase(ctx);
    }
    Na__StopContext(ctx);
    delete ctx;
}

NAPC_API int64_t napc_clean_preview_request(void* handle, const double* region, int32_t region_count,
                                           const double* params, int32_t param_count) {
    Na__CleanContext* ctx = static_cast<Na__CleanContext*>(handle);
    if (!ctx) return -1;
    Na__CleanRegion r;
    Na__CleanParams p;
    const char* problem = nullptr;
    if (!Na__RegionFromArray(region, region_count, r)) return -2;
    if (!Na__CleanParams__FromArray(params, param_count, p, &problem)) return -3;
    std::lock_guard<std::mutex> lock(ctx->m);
    ctx->req_region = r;
    ctx->req_params = p;
    ctx->req_id = ++ctx->next_id;
    ctx->has_request = true;
    ctx->cancel.store(true);       // the running preview is out of date: stop it
    ctx->cv.notify_one();
    return ctx->req_id;
}

NAPC_API void napc_clean_preview_cancel(void* handle) {
    Na__CleanContext* ctx = static_cast<Na__CleanContext*>(handle);
    if (!ctx) return;
    std::lock_guard<std::mutex> lock(ctx->m);
    ctx->has_request = false;
    ctx->cancel.store(true);
}

NAPC_API int32_t napc_clean_preview_poll(void* handle, double* out, int32_t out_count) {
    Na__CleanContext* ctx = static_cast<Na__CleanContext*>(handle);
    if (!ctx || !out || out_count < 4) return -1;
    std::lock_guard<std::mutex> lock(ctx->m);
    const int state = ctx->has_request ? 1 : ctx->state.load();
    out[0] = state;
    out[1] = static_cast<double>(ctx->result_id);
    out[2] = static_cast<double>(ctx->has_request ? ctx->req_id : ctx->running_id.load());
    out[3] = ctx->shared->grid_ready.load() ? 1 : 0;
    return state;
}

NAPC_API int32_t napc_clean_preview_stats(void* handle, double* out, int32_t out_count) {
    Na__CleanContext* ctx = static_cast<Na__CleanContext*>(handle);
    if (!ctx || !out || out_count < NAPC_CS_COUNT) return -1;
    std::lock_guard<std::mutex> lock(ctx->m);
    if (ctx->stats.size() != NAPC_CS_COUNT) return -2;
    std::memcpy(out, ctx->stats.data(), sizeof(double) * NAPC_CS_COUNT);
    return 0;
}

NAPC_API int32_t napc_clean_preview_error(void* handle, char* text, int32_t text_cap) {
    Na__CleanContext* ctx = static_cast<Na__CleanContext*>(handle);
    if (!ctx) return 0;
    std::lock_guard<std::mutex> lock(ctx->m);
    return Na__CopyOut(ctx->error, text, text_cap);
}

NAPC_API int64_t napc_clean_preview_points(void* handle, uint32_t* stored, uint16_t* flags, float* delta, int64_t cap) {
    Na__CleanContext* ctx = static_cast<Na__CleanContext*>(handle);
    if (!ctx) return -1;
    std::lock_guard<std::mutex> lock(ctx->m);
    const int64_t count = static_cast<int64_t>(ctx->res_stored.size());
    const int64_t n = std::min(count, std::max<int64_t>(0, cap));
    if (stored) std::memcpy(stored, ctx->res_stored.data(), size_t(n) * 4);
    if (flags) std::memcpy(flags, ctx->res_flags.data(), size_t(n) * 2);
    if (delta) std::memcpy(delta, ctx->res_delta.data(), size_t(n) * 12);
    return count;
}

NAPC_API void* napc_clean_preview_cloud(void* handle, int32_t which, const double* colours, int32_t colour_count) {
    Na__CleanContext* ctx = static_cast<Na__CleanContext*>(handle);
    if (!ctx) return nullptr;
    try {
        std::lock_guard<std::mutex> lock(ctx->m);
        const Na__CloudPoints& src = *ctx->shared->cloud;
        const size_t count = ctx->res_stored.size();
        std::shared_ptr<Na__CloudPoints> points(new Na__CloudPoints());
        const bool diff = which == 1;
        const bool with_index = !src.source_index.empty();
        uint32_t c_removed = 0xFFD02020u, c_low = 0xFF8EC5F0u, c_high = 0xFF0B3C9Eu, c_candidate = 0xFFF0A000u,
                 c_doubling = 0xFFC000C0u, c_thinned = 0xFFC8BCA8u, c_tint = 0xFFE6E6E6u;
        double tint_share = 0.6;
        if (diff && colours && colour_count >= NAPC_DIFF_COLOURS) {
            c_removed = Na__Rgb(colours); c_low = Na__Rgb(colours + 3); c_high = Na__Rgb(colours + 6);
            c_candidate = Na__Rgb(colours + 9); c_doubling = Na__Rgb(colours + 12); c_thinned = Na__Rgb(colours + 15);
            c_tint = Na__Rgb(colours + 18); tint_share = colours[21];
        }
        const double move_scale = std::max(1e-9, ctx->result_params.max_move_mm / ctx->result_params.mm_per_unit);
        for (size_t k = 0; k < count; ++k) {
            const uint16_t f = ctx->res_flags[k];
            if (!diff && (f & NA_CF_REMOVED_ANY)) continue;
            const uint32_t s = ctx->res_stored[k];
            const float* d = &ctx->res_delta[k * 3];
            for (int a = 0; a < 3; ++a) points->xyz.push_back(src.xyz[size_t(s) * 3 + a] + d[a]);
            uint32_t colour = src.bgra[s];
            if (diff) {
                if (f & NA_CF_REMOVED_NOISE) colour = c_removed;
                else if (f & NA_CF_REMOVED_DENSITY) colour = c_thinned;
                else if (f & NA_CF_DOUBLING) colour = c_doubling;
                else if (f & NA_CF_CANDIDATE) colour = c_candidate;
                else if (f & NA_CF_MOVED) {
                    const double len = std::sqrt(double(d[0]) * d[0] + double(d[1]) * d[1] + double(d[2]) * d[2]);
                    colour = Na__Blend(c_low, c_high, len / move_scale);
                } else colour = Na__Blend(colour, c_tint, tint_share);
            }
            points->bgra.push_back(colour);
            if (with_index) points->source_index.push_back(src.source_index[s]);
        }
        points->count = static_cast<int64_t>(points->bgra.size());
        if (points->count == 0) return nullptr;
        Na__PointCloud* cloud = new Na__PointCloud();
        cloud->count = points->count;
        cloud->points = std::move(points);
        return cloud;
    } catch (...) {
        return nullptr;
    }
}

NAPC_API int64_t napc_clean_debug_cells(void* handle, double* out, int64_t cap_cells) {
    Na__CleanContext* ctx = static_cast<Na__CleanContext*>(handle);
    if (!ctx) return -1;
    std::lock_guard<std::mutex> lock(ctx->m);
    if (ctx->has_request || ctx->state.load() == 1) return -2;
    const Na__CleanWork& w = ctx->work;
    int64_t count = 0;
    for (size_t s = 0; s < w.slot_cell.size() && s < w.surfaces.size(); ++s) {
        const Na__CellSurface& cs = w.surfaces[s];
        if (!cs.computed) continue;
        const uint32_t c = w.slot_cell[s];
        bool has_core = false;
        for (uint32_t j = w.cell_start[c]; j < w.cell_start[c + 1] && !has_core; ++j) has_core = w.core[j] != 0;
        if (!has_core) continue;
        if (out && count < cap_cells) {
            double* o = out + count * NAPC_CELL_DEBUG;
            int64_t cc[3];
            Na__Clean__CellCoords(w, c, cc);
            for (int a = 0; a < 3; ++a) o[a] = (cc[a] + 0.5) * w.fine;
            o[3] = cs.families; o[4] = cs.flags; o[5] = cs.sigma;
            for (int f = 0; f < 3; ++f) {
                const Na__SurfaceFamily& sf = cs.family[f];
                double* q = o + 6 + f * 12;
                q[0] = sf.n[0]; q[1] = sf.n[1]; q[2] = sf.n[2]; q[3] = sf.sheets;
                q[4] = sf.sheet[0]; q[5] = sf.sheet[1]; q[6] = sf.sheet[2];
                q[7] = sf.flags; q[8] = sf.conf; q[9] = sf.gap; q[10] = sf.sigma; q[11] = sf.members;
            }
            o[42] = cs.lent; o[43] = cs.planes;
            o[44] = cs.t_thick; o[45] = cs.t_pair; o[46] = cs.t_angle; o[47] = cs.t_share;
        }
        ++count;
    }
    return count;
}

// -----------------------------------------------------------------------------
// REGION | Export API
// -----------------------------------------------------------------------------

NAPC_API void* napc_clean_export_start(void* handle, const char* source_utf8, const char* dest_utf8,
                                      const double* params, int32_t param_count, const double* origin,
                                      const char* provenance_json, const char* software) {
    Na__CleanContext* ctx = static_cast<Na__CleanContext*>(handle);
    if (!ctx || (dest_utf8 && !source_utf8)) return nullptr;
    Na__CleanParams p;
    const char* problem = nullptr;
    if (!Na__CleanParams__FromArray(params, param_count, p, &problem)) return nullptr;
    try {
        Na__CleanExportJob* job = new Na__CleanExportJob();
        job->shared = ctx->shared;
        job->dry_run = dest_utf8 == nullptr;
        job->source = source_utf8 ? source_utf8 : "";
        job->dest = dest_utf8 ? dest_utf8 : "";
        job->params = p;
        if (origin) for (int a = 0; a < 3; ++a) job->origin[a] = origin[a];
        job->provenance = provenance_json ? provenance_json : "{}";
        job->software = software ? software : "Na Point Cloud Viewer";
        napc_clean_preview_cancel(ctx);          // one heavy job at a time
        job->worker = std::thread(Na__ExportWorker, job);
        std::lock_guard<std::mutex> lock(g_registry_mutex);
        g_jobs.insert(job);
        return job;
    } catch (...) {
        return nullptr;
    }
}

NAPC_API void* napc_box_export_start(void* cloud_handle, const char* source_utf8, const char* dest_utf8,
                                     const double* boxes, int32_t box_count, const double* origin,
                                     const char* provenance_json, const char* software) {
    const Na__PointCloud* cloud = static_cast<const Na__PointCloud*>(cloud_handle);
    if (!cloud || !cloud->points || (dest_utf8 && !source_utf8) || !boxes || box_count < NAPC_BOXES_COUNT) return nullptr;
    Na__BoxFilter filter;
    if (!Na__BoxFilter__Read(boxes, boxes + 12, filter) || !filter.Active()) return nullptr;
    try {
        Na__CleanExportJob* job = new Na__CleanExportJob();
        job->shared = std::make_shared<Na__CleanShared>();   // the points only: no grid is ever built
        job->shared->cloud = cloud->points;                  // shared: releasing the cloud handle is safe
        job->box_mode = true;
        job->boxes = filter;
        job->dry_run = dest_utf8 == nullptr;
        job->source = source_utf8 ? source_utf8 : "";
        job->dest = dest_utf8 ? dest_utf8 : "";
        if (origin) for (int a = 0; a < 3; ++a) job->origin[a] = origin[a];
        job->provenance = provenance_json ? provenance_json : "{}";
        job->software = software ? software : "Na Point Cloud Viewer";
        job->worker = std::thread(Na__ExportWorker, job);
        std::lock_guard<std::mutex> lock(g_registry_mutex);
        g_jobs.insert(job);
        return job;
    } catch (...) {
        return nullptr;
    }
}

NAPC_API int32_t napc_clean_export_poll(void* handle, double* out, int32_t out_count) {
    Na__CleanExportJob* job = static_cast<Na__CleanExportJob*>(handle);
    if (!job || !out || out_count < NAPC_E_COUNT) return -1;
    const bool finished = job->finished.load(std::memory_order_acquire);
    if (finished) std::memcpy(out, job->out, sizeof(job->out));
    else std::memset(out, 0, sizeof(double) * NAPC_E_COUNT);
    out[NAPC_E_PHASE] = job->phase.load();
    out[NAPC_E_DONE] = static_cast<double>(job->done.load());
    out[NAPC_E_TOTAL] = static_cast<double>(job->total.load());
    out[NAPC_E_FINISHED] = finished ? 1 : 0;
    out[NAPC_E_FAILED] = job->failed.load() ? 1 : 0;
    out[NAPC_E_CANCELLED] = job->cancelled.load() ? 1 : 0;
    return finished ? 1 : 0;
}

NAPC_API int32_t napc_clean_export_error(void* handle, char* text, int32_t text_cap) {
    Na__CleanExportJob* job = static_cast<Na__CleanExportJob*>(handle);
    if (!job) return 0;
    std::lock_guard<std::mutex> lock(job->text_mutex);
    return Na__CopyOut(job->error, text, text_cap);
}

NAPC_API int32_t napc_clean_export_notes(void* handle, char* text, int32_t text_cap) {
    Na__CleanExportJob* job = static_cast<Na__CleanExportJob*>(handle);
    if (!job) return 0;
    std::lock_guard<std::mutex> lock(job->text_mutex);
    return Na__CopyOut(job->notes, text, text_cap);
}

NAPC_API void napc_clean_export_cancel(void* handle) {
    Na__CleanExportJob* job = static_cast<Na__CleanExportJob*>(handle);
    if (job) job->cancel.store(true);
}

NAPC_API int64_t napc_clean_export_points(void* handle, uint16_t* flags, float* delta, int64_t cap) {
    Na__CleanExportJob* job = static_cast<Na__CleanExportJob*>(handle);
    if (!job || !job->finished.load(std::memory_order_acquire)) return -1;
    const int64_t count = static_cast<int64_t>(job->full.flags.size());
    const int64_t n = std::min(count, std::max<int64_t>(0, cap));
    if (flags) std::memcpy(flags, job->full.flags.data(), size_t(n) * 2);
    if (delta) {
        // a box export moves nothing and keeps no displacements
        if (job->full.delta.size() >= size_t(n) * 3) std::memcpy(delta, job->full.delta.data(), size_t(n) * 12);
        else std::memset(delta, 0, size_t(n) * 12);
    }
    return count;
}

NAPC_API void napc_clean_export_destroy(void* handle) {
    Na__CleanExportJob* job = static_cast<Na__CleanExportJob*>(handle);
    if (!job) return;
    {
        std::lock_guard<std::mutex> lock(g_registry_mutex);
        g_jobs.erase(job);
    }
    Na__StopJob(job);
    delete job;
}

// Called by napc_shutdown (Api.cpp): no worker may outlive the DLL.
void Na__Clean__ShutdownAll() {
    std::vector<Na__CleanContext*> contexts;
    std::vector<Na__CleanExportJob*> jobs;
    {
        std::lock_guard<std::mutex> lock(g_registry_mutex);
        contexts.assign(g_contexts.begin(), g_contexts.end());
        jobs.assign(g_jobs.begin(), g_jobs.end());
    }
    for (Na__CleanExportJob* job : jobs) Na__StopJob(job);
    for (Na__CleanContext* ctx : contexts) Na__StopContext(ctx);
    Na__Clean__ShutdownPool();
}
