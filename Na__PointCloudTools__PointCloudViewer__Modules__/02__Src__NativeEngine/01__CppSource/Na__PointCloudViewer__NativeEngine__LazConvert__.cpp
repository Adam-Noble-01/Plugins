// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - LAZ TO LAS CONVERTER
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__LazConvert__.cpp
// PURPOSE    : See the header. LASzip calls used: laszip_create,
//              laszip_open_reader, laszip_get_header_pointer,
//              laszip_get_point_pointer, laszip_read_point,
//              laszip_close_reader, laszip_destroy, laszip_get_error.
//
// FIELD OFFSETS: ASPRS LAS 1.4 R15, Table 3 (as LasFile.cpp).
//
// =============================================================================

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include "Na__PointCloudViewer__NativeEngine__LazConvert__.hpp"
#include "Na__PointCloudViewer__NativeEngine__LasFile__.hpp"

#include "laszip_api.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <limits>
#include <new>
#include <vector>

namespace {

    // -------------------------------------------------------------------------
    // REGION | Helpers
    // -------------------------------------------------------------------------

    template <typename T> T Na__Get(const uint8_t* bytes, size_t offset) {
        T value;
        std::memcpy(&value, bytes + offset, sizeof(T));
        return value;
    }
    template <typename T> void Na__Put(std::vector<uint8_t>& bytes, size_t offset, T value) {
        std::memcpy(bytes.data() + offset, &value, sizeof(T));
    }

    std::string Na__FixedText(const uint8_t* bytes, size_t length) {
        size_t used = 0;
        while (used < length && bytes[used] != 0) ++used;
        return std::string(reinterpret_cast<const char*>(bytes), used);
    }

    double Na__MsSince(std::chrono::steady_clock::time_point start) {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    }

    std::string Na__LaszipError(laszip_POINTER reader) {
        laszip_CHAR* message = nullptr;
        if (reader && laszip_get_error(reader, &message) == 0 && message) return std::string(message);
        return std::string("unknown LASzip error");
    }

    struct Na__Reader {
        laszip_POINTER handle = nullptr;
        ~Na__Reader() { this->Close(); }
        void Close() {
            if (handle) { laszip_close_reader(handle); laszip_destroy(handle); }
            handle = nullptr;
        }
        bool Open(const std::string& path_utf8, std::string& error) {
            laszip_BOOL compressed = 0;
            if (laszip_create(&handle) != 0 || !handle) { handle = nullptr; error = "The LASzip reader could not be created."; return false; }
            if (laszip_open_reader(handle, path_utf8.c_str(), &compressed) != 0) {
                error = Na__LaszipError(handle);
                laszip_destroy(handle);
                handle = nullptr;
                return false;
            }
            return true;
        }
    };

    struct Na__TempGuard {
        std::wstring path;
        bool keep = false;
        ~Na__TempGuard() { if (!path.empty() && !keep) DeleteFileW(path.c_str()); }
    };

    void Na__Note(Na__LazConvertJob* job, const std::string& text) {
        std::lock_guard<std::mutex> lock(job->text_mutex);
        if (!job->notes.empty()) job->notes += " | ";
        job->notes += text;
    }

    // One block of VLRs (54-byte headers) or EVLRs (60-byte headers), kept or dropped.
    struct Na__Record {
        uint64_t    offset = 0;          // within its block
        uint64_t    size = 0;            // header + payload
        std::string user_id;
        uint16_t    record_id = 0;
    };

    // Chained hash of every point record, in file order.
    inline uint64_t Na__RecordHash(const uint8_t* record, size_t length, uint64_t h) {
        return Na__Hash64(record, length, h);
    }

    const size_t   NA_CHUNK_RECORDS = 65536;
    const uint64_t NA_HASH_SEED     = 0x4E41505A4C4153ull;   // "NAPZLAS"

    // -------------------------------------------------------------------------
    // REGION | The conversion
    // -------------------------------------------------------------------------

    bool Na__Run(Na__LazConvertJob* job, bool& cancelled, std::string& error) {
        cancelled = false;
        const std::wstring source_w = Na__Utf8ToWide(job->source_utf8);
        const std::wstring final_w  = Na__Utf8ToWide(job->dest_utf8);
        if (source_w.empty() || final_w.empty()) { error = "The file paths could not be read."; return false; }

        // --- the LAZ's own bytes: header, VLR block, EVLRs -----------------------------------
        Na__File src;
        if (!src.OpenRead(source_w, false)) { error = "The LAZ file could not be opened for reading."; return false; }
        const uint64_t file_size = src.Size();
        job->source_bytes = file_size;
        uint8_t head[375] = {};
        const size_t head_read = static_cast<size_t>(std::min<uint64_t>(file_size, sizeof(head)));
        if (head_read < 227 || !src.ReadAt(0, head, head_read) || std::memcmp(head, "LASF", 4) != 0) {
            error = "This is not a LAS or LAZ file (no LASF signature, or the header is cut short).";
            return false;
        }
        const uint8_t  version_major    = head[24];
        const uint8_t  version_minor    = head[25];
        const uint16_t global_encoding  = Na__Get<uint16_t>(head, 6);
        const uint16_t header_size      = Na__Get<uint16_t>(head, 94);
        const uint32_t offset_to_points = Na__Get<uint32_t>(head, 96);
        const uint32_t vlr_count        = Na__Get<uint32_t>(head, 100);
        const uint8_t  format_byte      = head[104];
        const int      point_format     = format_byte & 0x3F;
        const uint16_t record_length    = Na__Get<uint16_t>(head, 105);
        const uint32_t legacy_count     = Na__Get<uint32_t>(head, 107);
        job->version_major = version_major;
        job->version_minor = version_minor;
        job->point_format  = point_format;
        job->record_length = record_length;

        if (version_major != 1 || version_minor > 4) {
            error = "LAS version " + std::to_string(version_major) + "." + std::to_string(version_minor) + " is not supported (1.0 to 1.4 are).";
            return false;
        }
        const uint16_t min_header = version_minor >= 4 ? 375 : (version_minor == 3 ? 235 : 227);
        if (header_size < min_header || header_size > file_size || offset_to_points < header_size || offset_to_points > file_size) {
            error = "The header of this file does not match its LAS version.";
            return false;
        }
        if ((format_byte & 0xC0) == 0) {
            error = "This file is not LAZ-compressed. It is already a LAS file and can be imported as it is.";
            return false;
        }
        if (Na__Las__MinRecordLength(point_format) < 0 || record_length < Na__Las__MinRecordLength(point_format)) {
            error = "Point format " + std::to_string(point_format) + " with " + std::to_string(record_length) + "-byte records is not a valid LAS point format.";
            return false;
        }
        if (version_minor >= 3 && (global_encoding & 0x2)) {
            error = "This file stores waveform data inside itself, which the converter does not support. Nothing was written.";
            return false;
        }
        uint64_t extended_count = 0;
        uint64_t evlr_start = 0;
        uint32_t evlr_count = 0;
        if (version_minor >= 4) {
            evlr_start     = Na__Get<uint64_t>(head, 235);
            evlr_count     = Na__Get<uint32_t>(head, 243);
            extended_count = Na__Get<uint64_t>(head, 247);
        }
        const uint64_t count = (version_minor >= 4 && extended_count != 0) ? extended_count : legacy_count;
        if (version_minor >= 4 && legacy_count != 0 && extended_count != 0 && legacy_count != extended_count) {
            error = "The LAS 1.4 header gives two different point counts.";
            return false;
        }
        if (count == 0) { error = "This file contains no points."; return false; }
        if (count > static_cast<uint64_t>(std::numeric_limits<int64_t>::max() / record_length)) { error = "The point count in the header is not plausible."; return false; }
        job->point_count = static_cast<int64_t>(count);

        std::vector<uint8_t> header_bytes(header_size);
        std::vector<uint8_t> pre_block(offset_to_points - header_size);
        if (!src.ReadAt(0, header_bytes.data(), header_size) ||
            (!pre_block.empty() && !src.ReadAt(header_size, pre_block.data(), pre_block.size()))) {
            error = "The header block could not be read.";
            return false;
        }

        // VLRs: find the LASzip VLR (taken out), refuse compatibility mode, drop COPC.
        std::vector<Na__Record> vlrs;
        uint64_t at = 0;
        for (uint32_t v = 0; v < vlr_count; ++v) {
            if (at + 54 > pre_block.size()) { error = "Variable length record " + std::to_string(v + 1) + " runs into the point data."; return false; }
            Na__Record record;
            record.offset    = at;
            record.user_id   = Na__FixedText(pre_block.data() + at + 2, 16);
            record.record_id = Na__Get<uint16_t>(pre_block.data(), static_cast<size_t>(at + 18));
            record.size      = 54ull + Na__Get<uint16_t>(pre_block.data(), static_cast<size_t>(at + 20));
            if (at + record.size > pre_block.size()) { error = "Variable length record " + std::to_string(v + 1) + " runs into the point data."; return false; }
            at += record.size;
            vlrs.push_back(record);
        }
        int laszip_vlrs = 0;
        uint64_t laszip_vlr_bytes = 0;
        for (const Na__Record& record : vlrs) {
            if (record.user_id == "laszip encoded" && record.record_id == 22204) { ++laszip_vlrs; laszip_vlr_bytes = record.size; }
            if (record.user_id == "lascompatible" && record.record_id == 22204) {
                error = "This LAZ was written in LASzip's compatibility mode (LAS 1.4 points stored as LAS 1.2/1.3). Converting it is not supported yet; nothing was written.";
                return false;
            }
        }
        if (laszip_vlrs != 1) {
            error = laszip_vlrs == 0 ? "This file is marked as compressed but has no LASzip record, so it cannot be decompressed."
                                     : "This file has more than one LASzip record; it is not a valid LAZ.";
            return false;
        }
        std::vector<uint8_t> out_pre;
        out_pre.reserve(pre_block.size());
        uint32_t out_vlr_count = 0;
        for (const Na__Record& record : vlrs) {
            if (record.user_id == "laszip encoded" && record.record_id == 22204) continue;
            if (record.user_id == "copc") { ++job->dropped_records; continue; }
            out_pre.insert(out_pre.end(), pre_block.begin() + static_cast<ptrdiff_t>(record.offset),
                           pre_block.begin() + static_cast<ptrdiff_t>(record.offset + record.size));
            ++out_vlr_count;
        }
        // user data after the last VLR (kept as it is)
        out_pre.insert(out_pre.end(), pre_block.begin() + static_cast<ptrdiff_t>(at), pre_block.end());

        // EVLRs (LAS 1.4): after the compressed points, copied verbatim (COPC dropped).
        std::vector<uint8_t> out_evlrs;
        uint32_t out_evlr_count = 0;
        if (version_minor >= 4 && evlr_count > 0) {
            if (evlr_start < offset_to_points || evlr_start > file_size) { error = "The extended variable length records are not where the header says."; return false; }
            std::vector<uint8_t> tail(static_cast<size_t>(file_size - evlr_start));
            if (!tail.empty() && !src.ReadAt(evlr_start, tail.data(), tail.size())) { error = "The extended variable length records could not be read."; return false; }
            uint64_t e = 0;
            for (uint32_t v = 0; v < evlr_count; ++v) {
                if (e + 60 > tail.size()) { error = "Extended variable length record " + std::to_string(v + 1) + " is cut short."; return false; }
                const std::string user = Na__FixedText(tail.data() + e + 2, 16);
                const uint64_t length = Na__Get<uint64_t>(tail.data(), static_cast<size_t>(e + 20));
                if (length > tail.size() || e + 60 + length > tail.size()) { error = "Extended variable length record " + std::to_string(v + 1) + " is cut short."; return false; }
                if (user == "copc") {
                    ++job->dropped_records;
                } else {
                    out_evlrs.insert(out_evlrs.end(), tail.begin() + static_cast<ptrdiff_t>(e), tail.begin() + static_cast<ptrdiff_t>(e + 60 + length));
                    ++out_evlr_count;
                }
                e += 60 + length;
            }
        }
        src.Close();

        double scale[3], offset[3], hmin[3], hmax[3];
        for (int a = 0; a < 3; ++a) {
            scale[a]  = Na__Get<double>(head, 131 + 8 * a);
            offset[a] = Na__Get<double>(head, 155 + 8 * a);
            hmax[a]   = Na__Get<double>(head, 179 + 16 * a);
            hmin[a]   = Na__Get<double>(head, 187 + 16 * a);
            job->header_min[a] = hmin[a];
            job->header_max[a] = hmax[a];
        }

        // --- LASzip must read the same header the bytes say -------------------------------------
        Na__Reader reader;
        if (!reader.Open(job->source_utf8, error)) { error = "LASzip could not open the LAZ (" + error + ")."; return false; }
        laszip_header* lh = nullptr;
        laszip_point*  point = nullptr;
        if (laszip_get_header_pointer(reader.handle, &lh) != 0 || laszip_get_point_pointer(reader.handle, &point) != 0) {
            error = "LASzip could not read the LAZ header (" + Na__LaszipError(reader.handle) + ").";
            return false;
        }
        const uint64_t lh_count = lh->number_of_point_records ? lh->number_of_point_records : lh->extended_number_of_point_records;
        // LASzip hides its own VLR, exactly as this copy leaves it out.
        bool same = lh->version_major == version_major && lh->version_minor == version_minor &&
                    lh->point_data_format == point_format && lh->point_data_record_length == record_length && lh_count == count &&
                    lh->number_of_variable_length_records == vlr_count - 1 &&
                    static_cast<uint64_t>(lh->offset_to_point_data) == offset_to_points - laszip_vlr_bytes;
        const double lh_scale[3]  = { lh->x_scale_factor, lh->y_scale_factor, lh->z_scale_factor };
        const double lh_offset[3] = { lh->x_offset, lh->y_offset, lh->z_offset };
        const double lh_min[3]    = { lh->min_x, lh->min_y, lh->min_z };
        const double lh_max[3]    = { lh->max_x, lh->max_y, lh->max_z };
        for (int a = 0; a < 3; ++a) {
            same = same && std::memcmp(&lh_scale[a], &scale[a], 8) == 0 && std::memcmp(&lh_offset[a], &offset[a], 8) == 0 &&
                   std::memcmp(&lh_min[a], &hmin[a], 8) == 0 && std::memcmp(&lh_max[a], &hmax[a], 8) == 0;
        }
        if (!same) {
            error = "LASzip reads this file's header differently from the bytes stored in it, so a faithful copy cannot be guaranteed. Nothing was written.";
            return false;
        }
        Na__LazRecordWriter record_writer;
        if (!record_writer.Setup(point_format, record_length, point, error)) return false;

        // --- the new header ------------------------------------------------------------------
        const uint64_t new_offset = static_cast<uint64_t>(header_size) + out_pre.size();
        const uint64_t points_bytes = count * record_length;
        if (new_offset > UINT32_MAX) { error = "The header block is too large."; return false; }
        std::vector<uint8_t> out_header = header_bytes;
        out_header[104] = static_cast<uint8_t>(point_format);                  // compression bits off
        Na__Put<uint32_t>(out_header, 96, static_cast<uint32_t>(new_offset));
        Na__Put<uint32_t>(out_header, 100, out_vlr_count);
        if (version_minor >= 4) {
            Na__Put<uint64_t>(out_header, 235, out_evlr_count ? new_offset + points_bytes : 0);
            Na__Put<uint32_t>(out_header, 243, out_evlr_count);
        }

        // --- write <final>.partial-<tag> -------------------------------------------------------
        wchar_t tag[16];
        swprintf(tag, 16, L"%08x", static_cast<unsigned>(GetTickCount() ^ (GetCurrentProcessId() << 16)));
        Na__TempGuard guard;
        guard.path = final_w + L".partial-" + tag;
        Na__File out;
        if (!out.CreateNew(guard.path)) {
            guard.path.clear();
            error = "The new LAS could not be created in that folder (no permission, a read-only or full drive, or the folder is missing). Nothing was written.";
            return false;
        }
        if (!out.Write(out_header.data(), out_header.size()) || (!out_pre.empty() && !out.Write(out_pre.data(), out_pre.size()))) {
            error = "Writing the new LAS failed (is the drive full?). It was deleted; the LAZ is untouched.";
            return false;
        }

        const auto convert_start = std::chrono::steady_clock::now();
        job->phase.store(NA_LAZ_PHASE_CONVERTING);
        job->total.store(static_cast<int64_t>(count));
        job->done.store(0);
        std::vector<uint8_t> chunk(NA_CHUNK_RECORDS * record_length);
        uint64_t written_hash = NA_HASH_SEED;   // "NAPZLAS" seed
        int32_t lo[3] = { std::numeric_limits<int32_t>::max(), std::numeric_limits<int32_t>::max(), std::numeric_limits<int32_t>::max() };
        int32_t hi[3] = { std::numeric_limits<int32_t>::min(), std::numeric_limits<int32_t>::min(), std::numeric_limits<int32_t>::min() };
        for (uint64_t first = 0; first < count; first += NA_CHUNK_RECORDS) {
            const uint64_t n = std::min<uint64_t>(NA_CHUNK_RECORDS, count - first);
            for (uint64_t k = 0; k < n; ++k) {
                if (laszip_read_point(reader.handle) != 0) {
                    error = "LASzip could not decode point " + std::to_string(first + k + 1) + " of " + std::to_string(count) +
                            " (" + Na__LaszipError(reader.handle) + "). The LAZ may be damaged or cut short. Nothing was kept.";
                    return false;
                }
                uint8_t* record = chunk.data() + k * record_length;
                if (!record_writer.Write(record)) { error = "A point record could not be assembled."; return false; }
                written_hash = Na__RecordHash(record, record_length, written_hash);
                const int32_t xyz[3] = { point->X, point->Y, point->Z };
                for (int a = 0; a < 3; ++a) { lo[a] = std::min(lo[a], xyz[a]); hi[a] = std::max(hi[a], xyz[a]); }
            }
            if (!out.Write(chunk.data(), static_cast<size_t>(n * record_length))) {
                error = "Writing the new LAS failed (is the drive full?). It was deleted; the LAZ is untouched.";
                return false;
            }
            job->done.store(static_cast<int64_t>(first + n));
            if (job->cancel_requested.load(std::memory_order_relaxed)) { cancelled = true; return false; }
        }
        reader.Close();
        if (!out_evlrs.empty() && !out.Write(out_evlrs.data(), out_evlrs.size())) {
            error = "Writing the new LAS failed (is the drive full?). It was deleted; the LAZ is untouched.";
            return false;
        }
        if (!out.Flush()) { error = "The new LAS could not be flushed to disk. It was deleted; the LAZ is untouched."; return false; }
        out.Close();
        for (int a = 0; a < 3; ++a) {
            job->point_min[a] = static_cast<double>(lo[a]) * scale[a] + offset[a];
            job->point_max[a] = static_cast<double>(hi[a]) * scale[a] + offset[a];
        }
        job->convert_ms = Na__MsSince(convert_start);

        // --- check: layout, record bytes, LASzip read-back -------------------------------------
        const auto check_start = std::chrono::steady_clock::now();
        job->phase.store(NA_LAZ_PHASE_CHECKING);
        job->done.store(0);
        const char* check_failed = "Check failed: the new LAS did not read back exactly as the LAZ. It was deleted; the LAZ is untouched.";
        Na__LasLayout layout;
        std::string layout_error;
        if (!Na__LasFile__ReadLayout(guard.path, layout, layout_error)) {
            error = std::string(check_failed) + " (" + layout_error + ")";
            return false;
        }
        bool ok = layout.point_format == point_format && layout.record_length == record_length && layout.point_count == count &&
                  layout.offset_to_points == new_offset && layout.vlr_count == out_vlr_count &&
                  layout.file_size == new_offset + points_bytes + out_evlrs.size() && !layout.compressed;
        for (int a = 0; a < 3; ++a) {
            ok = ok && std::memcmp(&layout.scale[a], &scale[a], 8) == 0 && std::memcmp(&layout.offset[a], &offset[a], 8) == 0 &&
                 std::memcmp(&layout.min[a], &hmin[a], 8) == 0 && std::memcmp(&layout.max[a], &hmax[a], 8) == 0;
        }
        // every header byte other than the four patched fields is the LAZ's own
        for (size_t b = 0; b < header_bytes.size() && ok; ++b) {
            const bool patched = b == 104 || (b >= 96 && b < 104) || (version_minor >= 4 && b >= 235 && b < 247);
            ok = patched || layout.header_bytes[b] == header_bytes[b];
        }
        if (!ok) { error = check_failed; return false; }

        Na__File raw;
        Na__Reader check;
        if (!raw.OpenRead(guard.path, true) || !raw.Seek(new_offset)) { error = check_failed; return false; }
        if (!check.Open(Na__WideToUtf8(guard.path), error)) { error = std::string(check_failed) + " (LASzip: " + error + ")"; return false; }
        laszip_point* back = nullptr;
        if (laszip_get_point_pointer(check.handle, &back) != 0) { error = check_failed; return false; }
        Na__LazRecordWriter back_writer;
        if (!back_writer.Setup(point_format, record_length, back, error)) return false;
        std::vector<uint8_t> again(record_length);
        uint64_t disk_hash = NA_HASH_SEED, back_hash = NA_HASH_SEED;
        for (uint64_t first = 0; first < count; first += NA_CHUNK_RECORDS) {
            const uint64_t n = std::min<uint64_t>(NA_CHUNK_RECORDS, count - first);
            if (!raw.Read(chunk.data(), static_cast<size_t>(n * record_length))) { error = check_failed; return false; }
            for (uint64_t k = 0; k < n; ++k) {
                disk_hash = Na__RecordHash(chunk.data() + k * record_length, record_length, disk_hash);
                if (laszip_read_point(check.handle) != 0 || !back_writer.Write(again.data())) { error = check_failed; return false; }
                back_hash = Na__RecordHash(again.data(), record_length, back_hash);
            }
            job->done.store(static_cast<int64_t>(first + n));
            if (job->cancel_requested.load(std::memory_order_relaxed)) { cancelled = true; return false; }
        }
        check.Close();
        raw.Close();
        if (disk_hash != written_hash || back_hash != written_hash) { error = check_failed; return false; }
        job->check_ms = Na__MsSince(check_start);

        // --- publish: rename, never replacing anything -------------------------------------------
        job->phase.store(NA_LAZ_PHASE_PUBLISHING);
        if (!MoveFileExW(guard.path.c_str(), final_w.c_str(), MOVEFILE_WRITE_THROUGH)) {
            const DWORD code = GetLastError();
            error = (code == ERROR_ALREADY_EXISTS || code == ERROR_FILE_EXISTS)
                ? "A file with that name appeared while converting. Nothing was replaced; choose another name."
                : "The finished LAS could not be given its name (Windows error " + std::to_string(code) + "). Nothing was replaced.";
            return false;
        }
        guard.keep = true;
        job->written_bytes = layout.file_size;
        if (job->dropped_records > 0) {
            Na__Note(job, std::to_string(job->dropped_records) + " COPC index record" + (job->dropped_records == 1 ? " was" : "s were") +
                          " left out: they point into the compressed file and mean nothing in a LAS. No point data is affected.");
        }
        return true;
    }

    void Na__Worker(Na__LazConvertJob* job) {
        const auto start = std::chrono::steady_clock::now();
        bool cancelled = false;
        std::string error;
        bool ok = false;
        try {
            ok = Na__Run(job, cancelled, error);
        } catch (const std::bad_alloc&) {
            error = "Not enough memory to convert this file. Nothing was kept.";
        } catch (...) {
            error = "The LAZ conversion failed unexpectedly. Nothing was kept.";
        }
        job->total_ms = Na__MsSince(start);
        if (ok) {
            job->phase.store(NA_LAZ_PHASE_DONE);
        } else if (cancelled) {
            job->cancelled.store(true);
        } else {
            {
                std::lock_guard<std::mutex> lock(job->text_mutex);
                job->error = error;
            }
            job->failed.store(true);
        }
        job->finished.store(true, std::memory_order_release);
    }

} // namespace

void Na__LazConvert__Start(Na__LazConvertJob* job) {
    job->worker = std::thread(Na__Worker, job);
}

void Na__LazConvert__Destroy(Na__LazConvertJob* job) {
    if (!job) return;
    job->cancel_requested.store(true);
    if (job->worker.joinable()) job->worker.join();
    delete job;
}
