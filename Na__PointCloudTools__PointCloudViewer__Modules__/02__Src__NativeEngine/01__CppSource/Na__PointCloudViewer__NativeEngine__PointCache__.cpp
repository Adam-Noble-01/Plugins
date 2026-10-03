// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - POINT CACHE (.napc)
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__PointCache__.cpp
// PURPOSE    : See the header.
//
// =============================================================================

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include "Na__PointCloudViewer__NativeEngine__PointCache__.hpp"
#include "Na__PointCloudViewer__NativeEngine__LasImport__.hpp"
#include "Na__PointCloudViewer__NativeEngine__PngWriter__.hpp"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <new>

namespace {

    const char   NA_MAGIC[8]  = { 'N', 'A', 'P', 'C', 'v', '1', 0, 0 };
    const size_t NA_CHUNK     = size_t(8) << 20;      // 8 MB per read / write call

    double Na__MsSince(std::chrono::steady_clock::time_point start) {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    }

    std::wstring Na__Wide(const std::string& utf8) {
        if (utf8.empty()) return std::wstring();
        const int length = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
        if (length <= 0) return std::wstring();
        std::wstring wide(static_cast<size_t>(length - 1), L'\0');
        MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, wide.data(), length);
        return wide;
    }

    uint32_t Na__HeaderCrc(const Na__CacheHeader& header) {
        return Na__Png__Crc32(reinterpret_cast<const uint8_t*>(&header), sizeof(Na__CacheHeader) - 4);
    }

    bool Na__WriteAll(FILE* file, const uint8_t* data, size_t size, std::atomic<int64_t>& done,
                      const std::atomic<bool>& cancel, bool& cancelled) {
        while (size > 0) {
            if (cancel.load(std::memory_order_relaxed)) {
                cancelled = true;
                return false;
            }
            const size_t part = std::min(size, NA_CHUNK);
            if (std::fwrite(data, 1, part, file) != part) return false;
            data += part;
            size -= part;
            done.fetch_add(static_cast<int64_t>(part), std::memory_order_relaxed);
        }
        return true;
    }

    bool Na__ReadAll(FILE* file, uint8_t* data, size_t size, std::atomic<int64_t>& done, int64_t done_per_byte_div,
                     const std::atomic<bool>& cancel, bool& cancelled) {
        while (size > 0) {
            if (cancel.load(std::memory_order_relaxed)) {
                cancelled = true;
                return false;
            }
            const size_t part = std::min(size, NA_CHUNK);
            if (std::fread(data, 1, part, file) != part) return false;
            data += part;
            size -= part;
            done.fetch_add(static_cast<int64_t>(part) / done_per_byte_div, std::memory_order_relaxed);
        }
        return true;
    }

    void Na__Fail(Na__LasImportJob* job, const std::string& message) {
        {
            std::lock_guard<std::mutex> lock(job->error_mutex);
            job->error = message;
        }
        job->cache_state.store(-1);
        job->failed.store(true, std::memory_order_release);
        job->finished.store(true, std::memory_order_release);
    }

} // namespace

// -----------------------------------------------------------------------------
// REGION | Write
// -----------------------------------------------------------------------------

bool Na__Cache__Write(const std::string& path_utf8, const Na__LasImportJob& job,
                      std::atomic<int64_t>& done, const std::atomic<bool>& cancel, bool& cancelled, std::string& error) {
    cancelled = false;
    const Na__PointCloud& cloud = *job.cloud;
    Na__CacheHeader header;
    std::memset(&header, 0, sizeof(header));
    std::memcpy(header.magic, NA_MAGIC, 8);
    header.header_bytes = sizeof(Na__CacheHeader);
    header.version      = NA_CACHE_VERSION;
    header.point_count  = cloud.count;
    for (int axis = 0; axis < 3; ++axis) {
        header.origin[axis]    = job.origin[axis];
        header.local_min[axis] = job.local_min[axis];
        header.local_max[axis] = job.local_max[axis];
    }
    header.colour_bits = job.colour_bits;
    header.las_bytes   = job.las_bytes;
    header.las_mtime   = job.las_mtime;
    header.xyz_bytes   = static_cast<uint64_t>(cloud.count) * 12u;
    header.bgra_bytes  = static_cast<uint64_t>(cloud.count) * 4u;
    header.header_crc  = Na__HeaderCrc(header);

    const std::wstring final_path = Na__Wide(path_utf8);
    const std::wstring temp_path  = final_path + L".tmp";
    FILE* file = nullptr;
    if (final_path.empty() || _wfopen_s(&file, temp_path.c_str(), L"wb") != 0 || !file) {
        error = "The point cache file could not be created.";
        return false;
    }
    bool ok = std::fwrite(&header, 1, sizeof(header), file) == sizeof(header) &&
              Na__WriteAll(file, reinterpret_cast<const uint8_t*>(cloud.xyz.data()), header.xyz_bytes, done, cancel, cancelled) &&
              Na__WriteAll(file, reinterpret_cast<const uint8_t*>(cloud.bgra.data()), header.bgra_bytes, done, cancel, cancelled);
    ok = (std::fclose(file) == 0) && ok;
    if (ok && !MoveFileExW(temp_path.c_str(), final_path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        ok = false;
    }
    if (!ok) {
        _wremove(temp_path.c_str());
        if (!cancelled) error = "The point cache could not be written (disk full or folder not writable). The cloud is loaded; only the cache is missing.";
        return false;
    }
    return true;
}

// -----------------------------------------------------------------------------
// REGION | Read
// -----------------------------------------------------------------------------

bool Na__Cache__ReadHeader(const std::string& path_utf8, Na__CacheHeader& header, std::string& error) {
    FILE* file = nullptr;
    if (_wfopen_s(&file, Na__Wide(path_utf8).c_str(), L"rb") != 0 || !file) {
        error = "There is no point cache file.";
        return false;
    }
    bool ok = std::fread(&header, 1, sizeof(header), file) == sizeof(header);
    int64_t file_size = -1;
    if (ok && _fseeki64(file, 0, SEEK_END) == 0) file_size = _ftelli64(file);
    std::fclose(file);
    if (!ok || std::memcmp(header.magic, NA_MAGIC, 8) != 0 || header.header_bytes != sizeof(Na__CacheHeader) ||
        header.version != NA_CACHE_VERSION || header.header_crc != Na__HeaderCrc(header)) {
        error = "The point cache is from another version or is damaged.";
        return false;
    }
    if (header.point_count <= 0 || header.xyz_bytes != static_cast<uint64_t>(header.point_count) * 12u ||
        header.bgra_bytes != static_cast<uint64_t>(header.point_count) * 4u ||
        file_size != static_cast<int64_t>(sizeof(Na__CacheHeader) + header.xyz_bytes + header.bgra_bytes)) {
        error = "The point cache is incomplete or damaged.";
        return false;
    }
    return true;
}

void Na__Cache__LoadWorker(Na__LasImportJob* job) {
    const auto total_start = std::chrono::steady_clock::now();
    FILE* file = nullptr;
    try {
        Na__CacheHeader header;
        std::string error;
        if (!Na__Cache__ReadHeader(job->path, header, error)) return Na__Fail(job, error);
        if (job->expect_count > 0 && header.point_count != job->expect_count) {
            return Na__Fail(job, "The point cache holds a different number of points than expected.");
        }
        if (_wfopen_s(&file, Na__Wide(job->path).c_str(), L"rb") != 0 || !file || _fseeki64(file, sizeof(header), SEEK_SET) != 0) {
            if (file) std::fclose(file);
            return Na__Fail(job, "The point cache could not be opened.");
        }

        const int64_t count = header.point_count;
        job->total.store(count);
        job->phase.store(NA_LAS_PHASE_READING);
        std::unique_ptr<Na__PointCloud> cloud(new Na__PointCloud());
        cloud->count = count;
        cloud->xyz.resize(static_cast<size_t>(count) * 3);
        cloud->bgra.resize(static_cast<size_t>(count));

        const auto read_start = std::chrono::steady_clock::now();
        bool cancelled = false;
        const bool ok = Na__ReadAll(file, reinterpret_cast<uint8_t*>(cloud->xyz.data()), header.xyz_bytes, job->done, 16, job->cancel_requested, cancelled) &&
                        Na__ReadAll(file, reinterpret_cast<uint8_t*>(cloud->bgra.data()), header.bgra_bytes, job->done, 16, job->cancel_requested, cancelled);
        std::fclose(file);
        file = nullptr;
        if (cancelled) {
            job->cancelled.store(true);
            job->finished.store(true, std::memory_order_release);
            return;
        }
        if (!ok) return Na__Fail(job, "The point cache could not be read completely.");
        job->read_ms = Na__MsSince(read_start);
        job->done.store(count);

        for (int axis = 0; axis < 3; ++axis) {
            job->origin[axis]    = header.origin[axis];
            job->local_min[axis] = header.local_min[axis];
            job->local_max[axis] = header.local_max[axis];
        }
        job->colour_bits = header.colour_bits;
        job->point_count = count;
        job->cloud = std::move(cloud);
        job->cache_state.store(1);
        job->total_ms = Na__MsSince(total_start);
        job->phase.store(NA_LAS_PHASE_DONE);
        job->finished.store(true, std::memory_order_release);
    } catch (const std::bad_alloc&) {
        if (file) std::fclose(file);
        Na__Fail(job, "Not enough memory to load this point cloud. Close other applications or use a smaller export.");
    } catch (...) {
        if (file) std::fclose(file);
        Na__Fail(job, "The point cache could not be loaded.");
    }
}
