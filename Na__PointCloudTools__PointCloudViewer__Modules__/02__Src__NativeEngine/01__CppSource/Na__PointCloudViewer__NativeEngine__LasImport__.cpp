// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - LAS IMPORT
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__LasImport__.cpp
// PURPOSE    : See the header. LASzip calls used: laszip_create,
//              laszip_open_reader, laszip_get_header_pointer,
//              laszip_get_point_pointer, laszip_read_point,
//              laszip_close_reader, laszip_destroy, laszip_get_error.
//              (Not laszip_get_point_count - see Na__HeaderPointCount.)
//
// =============================================================================

#include "Na__PointCloudViewer__NativeEngine__LasImport__.hpp"
#include "Na__PointCloudViewer__NativeEngine__PointCache__.hpp"

#include "laszip_api.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <new>
#include <vector>

namespace {

    double Na__MsSince(std::chrono::steady_clock::time_point start) {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    }

    std::string Na__LaszipError(laszip_POINTER reader) {
        laszip_CHAR* message = nullptr;
        if (reader && laszip_get_error(reader, &message) == 0 && message) return std::string(message);
        return std::string("unknown LASzip error");
    }

    // Opens a reader; on failure fills error with a plain-English message.
    laszip_POINTER Na__OpenReader(const char* path_utf8, laszip_BOOL& compressed, std::string& error) {
        laszip_POINTER reader = nullptr;
        if (laszip_create(&reader) != 0 || !reader) {
            error = "The LAS reader could not be created.";
            return nullptr;
        }
        if (laszip_open_reader(reader, path_utf8, &compressed) != 0) {
            error = "The LAS file could not be opened or is not a valid LAS file (" + Na__LaszipError(reader) + ").";
            laszip_destroy(reader);
            return nullptr;
        }
        return reader;
    }

    // NOT laszip_get_point_count: despite its name it returns how many points
    // have been READ so far (0 straight after opening). The total lives in the
    // header - the legacy 32-bit field, or the LAS 1.4 64-bit one when that is 0.
    laszip_I64 Na__HeaderPointCount(const laszip_header* header) {
        return header->number_of_point_records ? static_cast<laszip_I64>(header->number_of_point_records)
                                               : static_cast<laszip_I64>(header->extended_number_of_point_records);
    }

    inline uint64_t Na__SplitMix64(uint64_t& state) {
        uint64_t z = (state += 0x9E3779B97F4A7C15ull);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
        return z ^ (z >> 31);
    }

    void Na__Fail(Na__LasImportJob* job, const std::string& message) {
        {
            std::lock_guard<std::mutex> lock(job->error_mutex);
            job->error = message;
        }
        job->failed.store(true, std::memory_order_release);
        job->finished.store(true, std::memory_order_release);
    }

    void Na__Worker(Na__LasImportJob* job) {
        const auto total_start = std::chrono::steady_clock::now();
        laszip_POINTER reader = nullptr;
        try {
            laszip_BOOL compressed = 0;
            std::string error;
            reader = Na__OpenReader(job->path.c_str(), compressed, error);
            if (!reader) return Na__Fail(job, error);

            laszip_header* header = nullptr;
            laszip_point*  point  = nullptr;
            if (laszip_get_header_pointer(reader, &header) != 0 || laszip_get_point_pointer(reader, &point) != 0) {
                error = "The LAS header could not be read (" + Na__LaszipError(reader) + ").";
                laszip_close_reader(reader); laszip_destroy(reader);
                return Na__Fail(job, error);
            }
            const laszip_I64 count = Na__HeaderPointCount(header);
            if (count <= 0) {
                laszip_close_reader(reader); laszip_destroy(reader);
                return Na__Fail(job, "The LAS file contains no points.");
            }

            const bool has_rgb = Na__Las__FormatHasRgb(header->point_data_format);
            const double sx = header->x_scale_factor, sy = header->y_scale_factor, sz = header->z_scale_factor;
            const double ox = header->x_offset, oy = header->y_offset, oz = header->z_offset;
            job->origin[0] = (header->min_x + header->max_x) * 0.5;
            job->origin[1] = (header->min_y + header->max_y) * 0.5;
            job->origin[2] = header->min_z;
            job->local_min[0] = header->min_x - job->origin[0];
            job->local_min[1] = header->min_y - job->origin[1];
            job->local_min[2] = header->min_z - job->origin[2];
            job->local_max[0] = header->max_x - job->origin[0];
            job->local_max[1] = header->max_y - job->origin[1];
            job->local_max[2] = header->max_z - job->origin[2];

            // --- read ---------------------------------------------------------------
            job->total.store(count);
            job->phase.store(NA_LAS_PHASE_READING);
            std::unique_ptr<Na__PointCloud> cloud(new Na__PointCloud());
            cloud->count = count;
            cloud->xyz.resize(static_cast<size_t>(count) * 3);
            cloud->bgra.resize(static_cast<size_t>(count));
            std::vector<uint16_t> rgb16(has_rgb ? static_cast<size_t>(count) * 3 : 0);

            const auto read_start = std::chrono::steady_clock::now();
            float* xyz = cloud->xyz.data();
            for (laszip_I64 i = 0; i < count; ++i) {
                if (laszip_read_point(reader) != 0) {
                    error = "The LAS file ended early or a point record is damaged at point " + std::to_string(i) +
                            " (" + Na__LaszipError(reader) + ").";
                    laszip_close_reader(reader); laszip_destroy(reader);
                    return Na__Fail(job, error);
                }
                xyz[i * 3]     = static_cast<float>(point->X * sx + ox - job->origin[0]);
                xyz[i * 3 + 1] = static_cast<float>(point->Y * sy + oy - job->origin[1]);
                xyz[i * 3 + 2] = static_cast<float>(point->Z * sz + oz - job->origin[2]);
                if (has_rgb) {
                    rgb16[i * 3]     = point->rgb[0];
                    rgb16[i * 3 + 1] = point->rgb[1];
                    rgb16[i * 3 + 2] = point->rgb[2];
                }
                if ((i & 0xFFFF) == 0) {
                    job->done.store(i, std::memory_order_relaxed);
                    if (job->cancel_requested.load(std::memory_order_relaxed)) {
                        laszip_close_reader(reader); laszip_destroy(reader);
                        job->cancelled.store(true);
                        job->finished.store(true, std::memory_order_release);
                        return;
                    }
                }
            }
            laszip_close_reader(reader);
            laszip_destroy(reader);
            reader = nullptr;
            job->read_ms = Na__MsSince(read_start);
            job->done.store(count);

            // --- colours: LAS says 16-bit, some writers store 0-255; detect -----------
            job->phase.store(NA_LAS_PHASE_COLOURS);
            const auto colour_start = std::chrono::steady_clock::now();
            uint32_t* bgra = cloud->bgra.data();
            if (has_rgb) {
                const uint16_t max_value = rgb16.empty() ? 0 : *std::max_element(rgb16.begin(), rgb16.end());
                const int shift = max_value > 255 ? 8 : 0;
                job->colour_bits = shift ? 16 : 8;
                for (laszip_I64 i = 0; i < count; ++i) {
                    bgra[i] = 0xFF000000u | (static_cast<uint32_t>(rgb16[i * 3] >> shift) << 16) |
                              (static_cast<uint32_t>(rgb16[i * 3 + 1] >> shift) << 8) |
                              static_cast<uint32_t>(rgb16[i * 3 + 2] >> shift);
                }
                std::vector<uint16_t>().swap(rgb16);
            } else {
                job->colour_bits = 0;
                const uint32_t fallback = 0xFF000000u | (uint32_t(job->fallback_rgb[0]) << 16) |
                                          (uint32_t(job->fallback_rgb[1]) << 8) | job->fallback_rgb[2];
                std::fill(cloud->bgra.begin(), cloud->bgra.end(), fallback);
            }
            job->colour_ms = Na__MsSince(colour_start);

            // --- shuffle so the point budget is a uniform sample ----------------------
            job->phase.store(NA_LAS_PHASE_SHUFFLE);
            job->done.store(0);
            const auto shuffle_start = std::chrono::steady_clock::now();
            uint64_t state = job->seed;
            for (laszip_I64 i = count - 1; i > 0; --i) {
                const laszip_I64 j = static_cast<laszip_I64>(Na__SplitMix64(state) % static_cast<uint64_t>(i + 1));
                std::swap(xyz[i * 3], xyz[j * 3]);
                std::swap(xyz[i * 3 + 1], xyz[j * 3 + 1]);
                std::swap(xyz[i * 3 + 2], xyz[j * 3 + 2]);
                std::swap(bgra[i], bgra[j]);
                if ((i & 0xFFFF) == 0) {
                    job->done.store(count - i, std::memory_order_relaxed);
                    if (job->cancel_requested.load(std::memory_order_relaxed)) {
                        job->cancelled.store(true);
                        job->finished.store(true, std::memory_order_release);
                        return;
                    }
                }
            }
            job->shuffle_ms = Na__MsSince(shuffle_start);

            job->point_count = count;
            job->cloud = std::move(cloud);

            // --- point cache for next time (a failure here never fails the import) ---
            if (!job->cache_path.empty()) {
                job->phase.store(NA_LAS_PHASE_SAVING);
                job->done.store(0);
                job->total.store(static_cast<int64_t>(sizeof(Na__CacheHeader)) + count * 16);
                bool save_cancelled = false;
                std::string cache_error;
                const bool saved = Na__Cache__Write(job->cache_path, *job, job->done, job->cancel_requested, save_cancelled, cache_error);
                if (save_cancelled) {
                    job->cloud.reset();
                    job->cancelled.store(true);
                    job->finished.store(true, std::memory_order_release);
                    return;
                }
                job->cache_state.store(saved ? 1 : -1);
                if (!saved) {
                    std::lock_guard<std::mutex> lock(job->error_mutex);
                    job->error = cache_error;
                }
            }
            job->total_ms = Na__MsSince(total_start);
            job->phase.store(NA_LAS_PHASE_DONE);
            job->finished.store(true, std::memory_order_release);
        } catch (const std::bad_alloc&) {
            if (reader) { laszip_close_reader(reader); laszip_destroy(reader); }
            Na__Fail(job, "Not enough memory to load this point cloud. Close other applications or use a smaller export.");
        } catch (...) {
            if (reader) { laszip_close_reader(reader); laszip_destroy(reader); }
            Na__Fail(job, "The LAS import failed unexpectedly.");
        }
    }

} // namespace

// -----------------------------------------------------------------------------
// REGION | Header
// -----------------------------------------------------------------------------

bool Na__Las__FormatHasRgb(int point_format) {
    switch (point_format) {
        case 2: case 3: case 5: case 7: case 8: case 10: return true;
        default: return false;
    }
}

bool Na__Las__ReadHeader(const char* path_utf8, Na__LasHeaderInfo& info, std::string& error) {
    laszip_BOOL compressed = 0;
    laszip_POINTER reader = Na__OpenReader(path_utf8, compressed, error);
    if (!reader) return false;

    laszip_header* header = nullptr;
    if (laszip_get_header_pointer(reader, &header) != 0) {
        error = "The LAS header could not be read (" + Na__LaszipError(reader) + ").";
        laszip_close_reader(reader);
        laszip_destroy(reader);
        return false;
    }

    info.version_major = header->version_major;
    info.version_minor = header->version_minor;
    info.point_format  = header->point_data_format;
    info.record_length = header->point_data_record_length;
    info.point_count   = Na__HeaderPointCount(header);
    info.scale[0] = header->x_scale_factor; info.scale[1] = header->y_scale_factor; info.scale[2] = header->z_scale_factor;
    info.offset[0] = header->x_offset; info.offset[1] = header->y_offset; info.offset[2] = header->z_offset;
    info.min[0] = header->min_x; info.min[1] = header->min_y; info.min[2] = header->min_z;
    info.max[0] = header->max_x; info.max[1] = header->max_y; info.max[2] = header->max_z;
    info.has_rgb = Na__Las__FormatHasRgb(header->point_data_format);
    info.vlr_count = static_cast<int>(header->number_of_variable_length_records);
    info.is_compressed = compressed != 0;
    info.system_id.assign(header->system_identifier, strnlen(header->system_identifier, 32));
    info.software.assign(header->generating_software, strnlen(header->generating_software, 32));
    for (laszip_U32 v = 0; v < header->number_of_variable_length_records; ++v) {
        const laszip_vlr& vlr = header->vlrs[v];
        if (std::strncmp(vlr.user_id, "LASF_Projection", 16) != 0) continue;
        if (vlr.record_id == 34735) info.has_geokeys = true;
        if (vlr.record_id == 2112 && vlr.data) {
            info.has_wkt = true;
            info.wkt.assign(reinterpret_cast<const char*>(vlr.data), strnlen(reinterpret_cast<const char*>(vlr.data), vlr.record_length_after_header));
        }
    }
    laszip_close_reader(reader);
    laszip_destroy(reader);
    return true;
}

// -----------------------------------------------------------------------------
// REGION | Job
// -----------------------------------------------------------------------------

void Na__LasJob__Start(Na__LasImportJob* job) {
    job->worker = job->from_cache ? std::thread(Na__Cache__LoadWorker, job) : std::thread(Na__Worker, job);
}

void Na__LasJob__Destroy(Na__LasImportJob* job) {
    if (!job) return;
    job->cancel_requested.store(true);
    if (job->worker.joinable()) job->worker.join();
    delete job;
}
