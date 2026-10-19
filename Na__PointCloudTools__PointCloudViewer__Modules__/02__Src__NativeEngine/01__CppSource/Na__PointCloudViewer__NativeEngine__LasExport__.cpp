// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - LAS EXPORT (CLEANED COPY)
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__LasExport__.cpp
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

#include "Na__PointCloudViewer__NativeEngine__LasExport__.hpp"
#include "Na__PointCloudViewer__NativeEngine__CleanTypes__.hpp"
#include "Na__PointCloudViewer__NativeEngine__LasFile__.hpp"

#include "laszip_api.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <ctime>
#include <limits>

namespace {

    template <typename T> void Na__Put(std::vector<uint8_t>& bytes, size_t offset, T value) {
        std::memcpy(bytes.data() + offset, &value, sizeof(T));
    }
    template <typename T> T Na__Get(const uint8_t* bytes, size_t offset) {
        T value;
        std::memcpy(&value, bytes + offset, sizeof(T));
        return value;
    }

    void Na__Note(Na__LasExportResult& result, const std::string& text) {
        if (!result.notes.empty()) result.notes += " | ";
        result.notes += text;
    }

    bool Na__IsIndexRecord(const std::string& user, uint16_t record) {
        return (user == "LAStools" && record == 30) || user == "LASzip" || user == "copc";
    }

    const char* NA_PROVENANCE_USER = "NobleArch_PCV";
    const uint16_t NA_PROVENANCE_RECORD = 1;

    // Order-sensitive digest of the coordinates written, compared after LASzip re-reads them.
    inline uint64_t Na__Digest(uint64_t h, int32_t x, int32_t y, int32_t z) {
        uint64_t v = static_cast<uint32_t>(x);
        v = v * 0x100000001B3ull ^ static_cast<uint32_t>(y);
        v = v * 0x100000001B3ull ^ static_cast<uint32_t>(z);
        return (h ^ v) * 0x9E3779B97F4A7C15ull + 0x632BE59BD9B4E019ull;
    }

    struct Na__TempGuard {
        std::wstring path;
        bool keep = false;
        ~Na__TempGuard() { if (!path.empty() && !keep) DeleteFileW(path.c_str()); }
    };

    std::string Na__LaszipError(laszip_POINTER reader) {
        laszip_CHAR* message = nullptr;
        if (reader && laszip_get_error(reader, &message) == 0 && message) return std::string(message);
        return std::string("unknown LASzip error");
    }

} // namespace

bool Na__LasExport__Run(const Na__LasExportInput& in, std::atomic<int>& phase, std::atomic<int64_t>& done,
                        std::atomic<int64_t>& total, const std::atomic<bool>& cancel, bool& cancelled,
                        Na__LasExportResult& result, std::string& error) {
    cancelled = false;
    result = Na__LasExportResult();
    const Na__CloudPoints& cloud = *in.cloud;
    const std::vector<uint16_t>& flags = *in.flags;
    const std::vector<float>& delta = *in.delta;

    // --- the source ------------------------------------------------------------------------
    phase.store(NA_EXPORT_PHASE_CHECKING);
    Na__LasLayout L;
    if (!Na__LasFile__ReadLayout(in.source, L, error)) return false;
    if (L.point_count != static_cast<uint64_t>(cloud.count)) {
        error = "The LAS file holds " + std::to_string(L.point_count) + " points but the loaded cloud has " +
                std::to_string(cloud.count) + ". It has changed since it was loaded; reload it first.";
        return false;
    }
    if (cloud.source_index.size() != static_cast<size_t>(cloud.count)) {
        error = "The loaded cloud does not know which LAS record each point came from (it came from an older point cache). Reload it from the LAS first.";
        return false;
    }
    const uint64_t n = L.point_count;
    std::vector<uint32_t> stored_of(static_cast<size_t>(n), UINT32_MAX);
    for (uint64_t s = 0; s < n; ++s) {
        const uint32_t src = cloud.source_index[static_cast<size_t>(s)];
        if (src >= n || stored_of[src] != UINT32_MAX) { error = "The loaded cloud's record map is damaged. Reload it from the LAS."; return false; }
        stored_of[src] = static_cast<uint32_t>(s);
    }
    uint64_t kept = 0;
    for (uint64_t s = 0; s < n; ++s) if (!(flags[static_cast<size_t>(s)] & NA_CF_REMOVED_ANY)) ++kept;
    if (kept == 0) { error = "These settings would remove every point; nothing was written."; return false; }
    if (L.version_minor < 4 && kept > UINT32_MAX) { error = "Too many points for this LAS version."; return false; }

    Na__File src;
    if (!src.OpenRead(in.source, true)) { error = "The LAS file could not be opened for reading."; return false; }

    // --- the new header block: header + VLRs (+ provenance) + gap ---------------------------
    std::vector<uint8_t> header = L.header_bytes;
    std::vector<uint8_t> vlr_block;
    std::string previous;
    for (const Na__LasVlrInfo& v : L.vlrs) {
        std::vector<uint8_t> bytes(54 + static_cast<size_t>(v.length));
        if (!src.ReadAt(v.header_offset, bytes.data(), bytes.size())) { error = "A VLR of the LAS file could not be read."; return false; }
        if (v.user_id == NA_PROVENANCE_USER && v.record_id == NA_PROVENANCE_RECORD) {
            previous.assign(reinterpret_cast<const char*>(bytes.data() + 54), v.length);
            continue;                                         // replaced by the new record below
        }
        if (Na__IsIndexRecord(v.user_id, v.record_id)) {
            ++result.dropped_vlrs;
            Na__Note(result, "Dropped VLR '" + v.user_id + "' " + std::to_string(v.record_id) + " (an index of the source's point order)");
            continue;
        }
        if (v.user_id == "LASF_Spec" && v.record_id == 4 && kept < n) {
            // extra-bytes descriptors: min / max would describe removed points
            for (size_t d = 54; d + 192 <= bytes.size(); d += 192) {
                if (bytes[d + 3] & 0x06) {
                    bytes[d + 3] &= static_cast<uint8_t>(~0x06);
                    std::memset(bytes.data() + d + 64, 0, 48);
                    result.cleared_extra_stats = true;
                }
            }
        }
        vlr_block.insert(vlr_block.end(), bytes.begin(), bytes.end());
    }
    if (result.cleared_extra_stats) Na__Note(result, "Extra-bytes min / max statistics were cleared (they described removed points)");

    std::string json = in.provenance_json;
    if (!previous.empty() && !json.empty() && json.back() == '}' && json.size() + previous.size() + 16 < 60000) {
        json.insert(json.size() - 1, ",\"previous\":" + previous);
    }
    if (json.size() > 65000) json = json.substr(0, 65000);
    {
        std::vector<uint8_t> vh(54, 0);
        const uint16_t reserved = (L.version_minor == 0) ? 0xAABB : 0;
        std::memcpy(vh.data(), &reserved, 2);
        std::memcpy(vh.data() + 2, NA_PROVENANCE_USER, std::strlen(NA_PROVENANCE_USER));
        const uint16_t record = NA_PROVENANCE_RECORD, length = static_cast<uint16_t>(json.size());
        std::memcpy(vh.data() + 18, &record, 2);
        std::memcpy(vh.data() + 20, &length, 2);
        const char* desc = "Na Point Cloud Viewer cleaning";
        std::memcpy(vh.data() + 22, desc, std::strlen(desc));
        vlr_block.insert(vlr_block.end(), vh.begin(), vh.end());
        vlr_block.insert(vlr_block.end(), json.begin(), json.end());
    }
    std::vector<uint8_t> gap(static_cast<size_t>(L.offset_to_points - L.vlr_end));
    if (!gap.empty() && !src.ReadAt(L.vlr_end, gap.data(), gap.size())) { error = "The LAS header block could not be read."; return false; }
    const uint32_t vlr_count = static_cast<uint32_t>(L.vlrs.size()) - result.dropped_vlrs - (previous.empty() ? 0 : 1) + 1;
    const uint64_t new_offset = static_cast<uint64_t>(L.header_size) + vlr_block.size() + gap.size();
    if (new_offset > UINT32_MAX) { error = "The LAS header block would be too large."; return false; }

    // --- the output file ----------------------------------------------------------------------
    uint64_t src_volume = 0, src_index = 0;
    src.Identity(src_volume, src_index);
    wchar_t tag[16];
    swprintf(tag, 16, L"%08x", static_cast<unsigned>(GetTickCount() ^ (GetCurrentProcessId() << 16)));
    Na__TempGuard guard;
    guard.path = in.final_path + L".partial-" + tag;
    result.temp_path_utf8 = Na__WideToUtf8(guard.path);
    Na__File out;
    if (!out.CreateNew(guard.path)) {
        guard.path.clear();
        error = "The new file could not be created in that folder (no permission, a read-only or full drive, or the folder is missing). Nothing was written.";
        return false;
    }
    uint64_t out_volume = 0, out_index = 0;
    if (out.Identity(out_volume, out_index) && out_volume == src_volume && out_index == src_index) {
        error = "Refused: the output would be the source file itself.";
        return false;
    }
    std::vector<uint8_t> zeros(static_cast<size_t>(new_offset), 0);
    if (!out.Write(zeros.data(), zeros.size())) { error = "Writing the new LAS failed (is the drive full?)."; return false; }

    // --- point records -----------------------------------------------------------------------
    phase.store(NA_EXPORT_PHASE_WRITING);
    total.store(static_cast<int64_t>(n));
    done.store(0);
    const int format = L.point_format;
    const size_t rec = L.record_length;
    const size_t chunk = static_cast<size_t>(std::min<uint64_t>(n, 1u << 20));
    std::vector<uint8_t> buffer(chunk * rec), outbuf(chunk * rec);
    uint64_t hist_out[16] = {}, hist_src[16] = {};
    double lo[3] = { 1e300, 1e300, 1e300 }, hi[3] = { -1e300, -1e300, -1e300 };
    uint64_t digest = 0x4E415043ull;
    const double float_eps = std::numeric_limits<float>::epsilon();
    if (!src.Seek(L.offset_to_points)) { error = "The LAS point records could not be read."; return false; }
    for (uint64_t base = 0; base < n; base += chunk) {
        if (cancel.load(std::memory_order_relaxed)) { cancelled = true; return false; }
        const size_t count = static_cast<size_t>(std::min<uint64_t>(chunk, n - base));
        if (!src.Read(buffer.data(), count * rec)) { error = "The LAS point records could not be read completely."; return false; }
        size_t used = 0;
        for (size_t k = 0; k < count; ++k) {
            const uint64_t i = base + k;
            const uint8_t* r = buffer.data() + k * rec;
            ++hist_src[Na__Las__ReturnNumber(r, format)];
            const uint32_t s = stored_of[static_cast<size_t>(i)];
            int32_t xyz[3] = { Na__Get<int32_t>(r, 0), Na__Get<int32_t>(r, 4), Na__Get<int32_t>(r, 8) };
            // the engine's copy of this point must be this record
            for (int a = 0; a < 3; ++a) {
                const float want = Na__Las__LocalCoordinate(xyz[a], L.scale[a], L.offset[a], in.origin[a]);
                const float have = cloud.xyz[size_t(s) * 3 + a];
                const double tol = std::max(0.5 * std::fabs(L.scale[a]), 4.0 * float_eps * std::max(1.0, std::fabs(double(have))));
                if (std::fabs(double(want) - double(have)) > tol) {
                    error = "The LAS file does not match the loaded point cloud at record " + std::to_string(i) +
                            ". It has changed since it was loaded. Reload it, check the preview and export again.";
                    return false;
                }
            }
            const uint16_t f = flags[s];
            if (f & NA_CF_REMOVED_ANY) { ++result.removed_points; continue; }
            uint8_t* o = outbuf.data() + used * rec;
            std::memcpy(o, r, rec);
            if (f & NA_CF_MOVED) {
                int32_t moved[3];
                bool fits = true;
                for (int a = 0; a < 3; ++a) {
                    const double source = xyz[a] * L.scale[a] + L.offset[a];
                    const double target = source + static_cast<double>(delta[size_t(s) * 3 + a]);
                    const double q = std::nearbyint((target - L.offset[a]) / L.scale[a]);
                    if (!(q >= -2147483648.0 && q <= 2147483647.0)) { fits = false; break; }
                    moved[a] = static_cast<int32_t>(q);
                }
                if (fits) {
                    if (moved[0] != xyz[0] || moved[1] != xyz[1] || moved[2] != xyz[2]) ++result.moved_points;
                    std::memcpy(xyz, moved, 12);
                    std::memcpy(o, xyz, 12);
                } else {
                    ++result.held_range;
                }
            }
            for (int a = 0; a < 3; ++a) {
                const double v = xyz[a] * L.scale[a] + L.offset[a];
                lo[a] = std::min(lo[a], v);
                hi[a] = std::max(hi[a], v);
            }
            ++hist_out[Na__Las__ReturnNumber(o, format)];
            digest = Na__Digest(digest, xyz[0], xyz[1], xyz[2]);
            ++used;
        }
        if (used && !out.Write(outbuf.data(), used * rec)) { error = "Writing the new LAS failed (is the drive full?)."; return false; }
        result.written_points += used;
        done.store(static_cast<int64_t>(base + count));
    }
    result.source_points = n;
    for (int a = 0; a < 3; ++a) { result.min[a] = lo[a]; result.max[a] = hi[a]; }
    const uint64_t new_points_end = new_offset + result.written_points * rec;

    // --- after the points: EVLRs / waveform ----------------------------------------------------
    uint64_t new_evlr_start = 0, new_waveform = 0;
    uint32_t new_evlr_count = 0;
    const int64_t shift = static_cast<int64_t>(new_points_end) - static_cast<int64_t>(L.points_end);
    auto copy_range = [&](uint64_t from, uint64_t length) -> bool {
        std::vector<uint8_t> bytes(static_cast<size_t>(std::min<uint64_t>(length, 64ull << 20)));
        while (length > 0) {
            const size_t part = static_cast<size_t>(std::min<uint64_t>(length, bytes.size()));
            if (!src.ReadAt(from, bytes.data(), part) || !out.Write(bytes.data(), part)) return false;
            from += part;
            length -= part;
        }
        return true;
    };
    uint64_t at = new_points_end;
    if (L.version_minor >= 4 && !L.evlrs.empty()) {
        if (L.evlr_start > L.points_end) {
            if (!copy_range(L.points_end, L.evlr_start - L.points_end)) { error = "Copying the extended records failed."; return false; }
            at += L.evlr_start - L.points_end;
        }
        for (const Na__LasEvlrInfo& e : L.evlrs) {
            if (Na__IsIndexRecord(e.user_id, e.record_id)) {
                ++result.dropped_evlrs;
                Na__Note(result, "Dropped EVLR '" + e.user_id + "' " + std::to_string(e.record_id) + " (an index of the source's point order)");
                continue;
            }
            if (new_evlr_count == 0) new_evlr_start = at;
            if (L.waveform_start == e.header_offset) new_waveform = at;
            if (!copy_range(e.header_offset, 60 + e.length)) { error = "Copying the extended records failed."; return false; }
            at += 60 + e.length;
            ++new_evlr_count;
        }
    } else if (L.version_minor >= 3 && L.waveform_start >= L.points_end && L.waveform_start > 0 && (L.global_encoding & 2)) {
        if (!copy_range(L.points_end, L.file_size - L.points_end)) { error = "Copying the waveform data failed."; return false; }
        at += L.file_size - L.points_end;
        new_waveform = static_cast<uint64_t>(static_cast<int64_t>(L.waveform_start) + shift);
    } else if (L.file_size > L.points_end) {
        result.dropped_tail_bytes = L.file_size - L.points_end;
        Na__Note(result, std::to_string(result.dropped_tail_bytes) + " bytes after the point records (outside any LAS structure) were not copied");
    }
    if ((L.global_encoding & 4) && L.waveform_start == 0) Na__Note(result, "Waveform data is in an external .wdp file, which was not copied");

    // --- patch the header ---------------------------------------------------------------------
    std::memset(header.data() + 26, 0, 32);
    std::memcpy(header.data() + 26, "MODIFICATION", 12);
    std::memset(header.data() + 58, 0, 32);
    std::memcpy(header.data() + 58, in.software.data(), std::min<size_t>(31, in.software.size()));
    {
        const time_t now = time(nullptr);
        tm utc;
        gmtime_s(&utc, &now);
        Na__Put<uint16_t>(header, 90, static_cast<uint16_t>(utc.tm_yday + 1));
        Na__Put<uint16_t>(header, 92, static_cast<uint16_t>(utc.tm_year + 1900));
    }
    Na__Put<uint32_t>(header, 96, static_cast<uint32_t>(new_offset));
    Na__Put<uint32_t>(header, 100, vlr_count);
    const bool legacy = L.version_minor < 4 || (L.point_format < 6 && result.written_points <= UINT32_MAX && L.legacy_count != 0);
    Na__Put<uint32_t>(header, 107, legacy ? static_cast<uint32_t>(result.written_points) : 0u);
    for (int r = 0; r < 5; ++r) Na__Put<uint32_t>(header, 111 + 4 * r, legacy ? static_cast<uint32_t>(hist_out[r + 1]) : 0u);
    for (int a = 0; a < 3; ++a) {
        Na__Put<double>(header, 179 + 16 * a, hi[a]);
        Na__Put<double>(header, 187 + 16 * a, lo[a]);
    }
    if (L.version_minor >= 3) Na__Put<uint64_t>(header, 227, new_waveform);
    if (L.version_minor >= 4) {
        Na__Put<uint64_t>(header, 235, new_evlr_start);
        Na__Put<uint32_t>(header, 243, new_evlr_count);
        Na__Put<uint64_t>(header, 247, result.written_points);
        for (int r = 0; r < 15; ++r) Na__Put<uint64_t>(header, 255 + 8 * r, hist_out[r + 1]);
    }
    // did the source's own return counts describe its records?
    for (int r = 0; r < (L.version_minor >= 4 ? 15 : 5); ++r) {
        const uint64_t recorded = L.version_minor >= 4 ? L.extended_by_return[r] : L.legacy_by_return[r];
        if (recorded != hist_src[r + 1]) result.by_return_mismatch = true;
    }
    if (result.by_return_mismatch) Na__Note(result, "The source header's points-by-return did not match its records; the new header counts the records");
    if (result.held_range) Na__Note(result, std::to_string(result.held_range) + " points could not move: the file's coordinate range ends at them");

    if (!out.WriteAt(0, header.data(), header.size()) || !out.Write(vlr_block.data(), vlr_block.size()) ||
        (!gap.empty() && !out.Write(gap.data(), gap.size())) || !out.Flush()) {
        error = "Finishing the new LAS failed (is the drive full?).";
        return false;
    }
    result.bytes = out.Size();
    out.Close();
    src.Close();

    // --- verify with LASzip (an independent reader) -------------------------------------------
    if (cancel.load()) { cancelled = true; return false; }
    phase.store(NA_EXPORT_PHASE_VERIFYING);
    total.store(static_cast<int64_t>(result.written_points));
    done.store(0);
    {
        laszip_POINTER reader = nullptr;
        laszip_BOOL compressed = 0;
        if (laszip_create(&reader) != 0 || laszip_open_reader(reader, result.temp_path_utf8.c_str(), &compressed) != 0) {
            error = "Check failed: the new file could not be opened as LAS (" + Na__LaszipError(reader) + ").";
            if (reader) laszip_destroy(reader);
            return false;
        }
        laszip_header* h = nullptr;
        laszip_point* pt = nullptr;
        laszip_get_header_pointer(reader, &h);
        laszip_get_point_pointer(reader, &pt);
        const uint64_t count = h->number_of_point_records ? h->number_of_point_records : h->extended_number_of_point_records;
        bool ok = !compressed && count == result.written_points && h->point_data_format == L.point_format &&
                  h->point_data_record_length == L.record_length && h->version_minor == L.version_minor &&
                  h->x_scale_factor == L.scale[0] && h->y_scale_factor == L.scale[1] && h->z_scale_factor == L.scale[2] &&
                  h->x_offset == L.offset[0] && h->y_offset == L.offset[1] && h->z_offset == L.offset[2] &&
                  h->min_x == lo[0] && h->max_x == hi[0] && h->min_y == lo[1] && h->max_y == hi[1] && h->min_z == lo[2] && h->max_z == hi[2] &&
                  h->offset_to_point_data == new_offset;
        uint64_t check = 0x4E415043ull, read = 0;
        double vlo[3] = { 1e300, 1e300, 1e300 }, vhi[3] = { -1e300, -1e300, -1e300 };
        for (uint64_t i = 0; ok && i < count; ++i) {
            if (laszip_read_point(reader) != 0) { ok = false; break; }
            check = Na__Digest(check, pt->X, pt->Y, pt->Z);
            const double v[3] = { pt->X * L.scale[0] + L.offset[0], pt->Y * L.scale[1] + L.offset[1], pt->Z * L.scale[2] + L.offset[2] };
            for (int a = 0; a < 3; ++a) { vlo[a] = std::min(vlo[a], v[a]); vhi[a] = std::max(vhi[a], v[a]); }
            ++read;
            if ((i & 0xFFFF) == 0) {
                done.store(static_cast<int64_t>(i));
                if (cancel.load(std::memory_order_relaxed)) { laszip_close_reader(reader); laszip_destroy(reader); cancelled = true; return false; }
            }
        }
        laszip_close_reader(reader);
        laszip_destroy(reader);
        for (int a = 0; a < 3; ++a) ok = ok && vlo[a] == lo[a] && vhi[a] == hi[a];
        if (!ok || read != result.written_points || check != digest) {
            error = "Check failed: reading the new file back did not give exactly what was written. It was deleted; the original is untouched.";
            return false;
        }
    }

    // --- publish: rename, never replacing anything ----------------------------------------------
    phase.store(NA_EXPORT_PHASE_PUBLISHING);
    if (!MoveFileExW(guard.path.c_str(), in.final_path.c_str(), MOVEFILE_WRITE_THROUGH)) {
        const DWORD code = GetLastError();
        error = (code == ERROR_ALREADY_EXISTS || code == ERROR_FILE_EXISTS)
            ? "A file with that name appeared while cleaning. Nothing was replaced; choose another name."
            : "The finished file could not be given its name (Windows error " + std::to_string(code) + "). Nothing was replaced.";
        return false;
    }
    guard.keep = true;
    phase.store(NA_EXPORT_PHASE_DONE);
    return true;
}
