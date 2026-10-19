// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - LAS FILE (RAW ACCESS)
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__LasFile__.cpp
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

#include "Na__PointCloudViewer__NativeEngine__LasFile__.hpp"

#include <algorithm>
#include <cstring>

// -----------------------------------------------------------------------------
// REGION | Point record formats
// -----------------------------------------------------------------------------

int Na__Las__MinRecordLength(int format) {
    static const int lengths[11] = { 20, 28, 26, 34, 57, 63, 30, 36, 38, 59, 67 };
    return format >= 0 && format <= 10 ? lengths[format] : -1;
}

int Na__Las__GpsTimeOffset(int format) {
    switch (format) {
        case 1: case 3: case 4: case 5: return 20;
        case 6: case 7: case 8: case 9: case 10: return 22;
        default: return -1;
    }
}

int Na__Las__ReturnNumber(const uint8_t* record, int format) {
    return format >= 6 ? (record[14] & 0x0F) : (record[14] & 0x07);
}

float Na__Las__LocalCoordinate(int32_t value, double scale, double offset, double origin) {
    return static_cast<float>(value * scale + offset - origin);
}

// -----------------------------------------------------------------------------
// REGION | Strings and hashing
// -----------------------------------------------------------------------------

std::wstring Na__Utf8ToWide(const std::string& utf8) {
    if (utf8.empty()) return std::wstring();
    const int length = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
    if (length <= 0) return std::wstring();
    std::wstring wide(static_cast<size_t>(length - 1), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, wide.data(), length);
    return wide;
}

std::string Na__WideToUtf8(const std::wstring& wide) {
    if (wide.empty()) return std::string();
    const int length = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (length <= 0) return std::string();
    std::string utf8(static_cast<size_t>(length - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, utf8.data(), length, nullptr, nullptr);
    return utf8;
}

namespace {
    inline uint64_t Na__Fmix64(uint64_t z) {          // MurmurHash3 finaliser
        z ^= z >> 33; z *= 0xFF51AFD7ED558CCDull;
        z ^= z >> 33; z *= 0xC4CEB9FE1A85EC53ull;
        z ^= z >> 33;
        return z;
    }
}

uint64_t Na__Hash64(const uint8_t* data, size_t size, uint64_t seed) {
    uint64_t h = Na__Fmix64(seed ^ (static_cast<uint64_t>(size) * 0x9E3779B97F4A7C15ull));
    size_t i = 0;
    for (; i + 8 <= size; i += 8) {
        uint64_t word;
        std::memcpy(&word, data + i, 8);
        h = Na__Fmix64(h ^ word) + 0x9E3779B97F4A7C15ull;
    }
    uint64_t tail = 0;
    if (i < size) std::memcpy(&tail, data + i, size - i);
    return Na__Fmix64(h ^ tail ^ (static_cast<uint64_t>(size - i) << 56));
}

// -----------------------------------------------------------------------------
// REGION | File wrapper
// -----------------------------------------------------------------------------

Na__File::~Na__File() { this->Close(); }

bool Na__File::OpenRead(const std::wstring& path, bool sequential) {
    this->Close();
    HANDLE handle = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                                FILE_ATTRIBUTE_NORMAL | (sequential ? FILE_FLAG_SEQUENTIAL_SCAN : 0), nullptr);
    if (handle == INVALID_HANDLE_VALUE) return false;
    m_handle = handle;
    return true;
}

bool Na__File::CreateNew(const std::wstring& path) {
    this->Close();
    // CREATE_NEW: fails if anything already exists at the path - never truncates.
    HANDLE handle = CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                                FILE_ATTRIBUTE_NORMAL, nullptr);
    if (handle == INVALID_HANDLE_VALUE) return false;
    m_handle = handle;
    return true;
}

bool Na__File::IsOpen() const { return m_handle != nullptr; }

uint64_t Na__File::Size() const {
    LARGE_INTEGER size;
    if (!m_handle || !GetFileSizeEx(static_cast<HANDLE>(m_handle), &size)) return 0;
    return static_cast<uint64_t>(size.QuadPart);
}

bool Na__File::Seek(uint64_t offset) {
    LARGE_INTEGER target;
    target.QuadPart = static_cast<LONGLONG>(offset);
    return m_handle && SetFilePointerEx(static_cast<HANDLE>(m_handle), target, nullptr, FILE_BEGIN) != 0;
}

bool Na__File::Read(void* buffer, size_t size) {
    uint8_t* out = static_cast<uint8_t*>(buffer);
    while (size > 0) {
        const DWORD part = static_cast<DWORD>(std::min<size_t>(size, size_t(1) << 26));
        DWORD got = 0;
        if (!ReadFile(static_cast<HANDLE>(m_handle), out, part, &got, nullptr) || got != part) return false;
        out += part;
        size -= part;
    }
    return true;
}

bool Na__File::ReadAt(uint64_t offset, void* buffer, size_t size) {
    return this->Seek(offset) && this->Read(buffer, size);
}

bool Na__File::Write(const void* buffer, size_t size) {
    const uint8_t* in = static_cast<const uint8_t*>(buffer);
    while (size > 0) {
        const DWORD part = static_cast<DWORD>(std::min<size_t>(size, size_t(1) << 26));
        DWORD wrote = 0;
        if (!WriteFile(static_cast<HANDLE>(m_handle), in, part, &wrote, nullptr) || wrote != part) return false;
        in += part;
        size -= part;
    }
    return true;
}

bool Na__File::WriteAt(uint64_t offset, const void* buffer, size_t size) {
    return this->Seek(offset) && this->Write(buffer, size);
}

bool Na__File::Flush() {
    return m_handle && FlushFileBuffers(static_cast<HANDLE>(m_handle)) != 0;
}

bool Na__File::Identity(uint64_t& volume, uint64_t& index) const {
    BY_HANDLE_FILE_INFORMATION info;
    if (!m_handle || !GetFileInformationByHandle(static_cast<HANDLE>(m_handle), &info)) return false;
    volume = info.dwVolumeSerialNumber;
    index  = (static_cast<uint64_t>(info.nFileIndexHigh) << 32) | info.nFileIndexLow;
    return true;
}

void Na__File::Close() {
    if (m_handle) CloseHandle(static_cast<HANDLE>(m_handle));
    m_handle = nullptr;
}

// -----------------------------------------------------------------------------
// REGION | Layout
// -----------------------------------------------------------------------------

namespace {
    template <typename T> T Na__Get(const uint8_t* bytes, size_t offset) {
        T value;
        std::memcpy(&value, bytes + offset, sizeof(T));
        return value;
    }

    std::string Na__FixedText(const uint8_t* bytes, size_t length) {
        size_t used = 0;
        while (used < length && bytes[used] != 0) ++used;
        return std::string(reinterpret_cast<const char*>(bytes), used);
    }
}

bool Na__LasFile__ReadLayout(const std::wstring& path, Na__LasLayout& layout, std::string& error) {
    layout = Na__LasLayout();
    Na__File file;
    if (!file.OpenRead(path, false)) {
        error = "The LAS file could not be opened for reading.";
        return false;
    }
    layout.file_size = file.Size();
    uint8_t head[375] = {};
    const size_t head_read = static_cast<size_t>(std::min<uint64_t>(layout.file_size, sizeof(head)));
    if (head_read < 227 || !file.ReadAt(0, head, head_read) || std::memcmp(head, "LASF", 4) != 0) {
        error = "This is not a LAS file (no LASF signature or the header is cut short).";
        return false;
    }
    layout.global_encoding  = Na__Get<uint16_t>(head, 6);
    layout.version_major    = head[24];
    layout.version_minor    = head[25];
    layout.header_size      = Na__Get<uint16_t>(head, 94);
    layout.offset_to_points = Na__Get<uint32_t>(head, 96);
    layout.vlr_count        = Na__Get<uint32_t>(head, 100);
    layout.format_byte      = head[104];
    layout.point_format     = head[104] & 0x3F;
    layout.compressed       = (head[104] & 0xC0) != 0;
    layout.record_length    = Na__Get<uint16_t>(head, 105);
    layout.legacy_count     = Na__Get<uint32_t>(head, 107);
    for (int r = 0; r < 5; ++r) layout.legacy_by_return[r] = Na__Get<uint32_t>(head, 111 + 4 * r);
    for (int a = 0; a < 3; ++a) {
        layout.scale[a]  = Na__Get<double>(head, 131 + 8 * a);
        layout.offset[a] = Na__Get<double>(head, 155 + 8 * a);
        layout.max[a]    = Na__Get<double>(head, 179 + 16 * a);
        layout.min[a]    = Na__Get<double>(head, 187 + 16 * a);
    }

    if (layout.version_major != 1 || layout.version_minor > 4) {
        error = "LAS version " + std::to_string(layout.version_major) + "." + std::to_string(layout.version_minor) +
                " is not supported (1.0 to 1.4 are).";
        return false;
    }
    const uint16_t min_header = layout.version_minor >= 4 ? 375 : (layout.version_minor == 3 ? 235 : 227);
    if (layout.header_size < min_header || layout.header_size > layout.file_size) {
        error = "The LAS header size does not match its version.";
        return false;
    }
    if (layout.compressed) {
        error = "This file is LAZ-compressed; only uncompressed LAS is supported.";
        return false;
    }
    const int min_record = Na__Las__MinRecordLength(layout.point_format);
    if (min_record < 0 || layout.record_length < min_record) {
        error = "Point format " + std::to_string(layout.point_format) + " with " + std::to_string(layout.record_length) +
                "-byte records is not a valid LAS point format.";
        return false;
    }
    if (layout.version_minor >= 3) layout.waveform_start = Na__Get<uint64_t>(head, 227);
    if (layout.version_minor >= 4) {
        layout.evlr_start     = Na__Get<uint64_t>(head, 235);
        layout.evlr_count     = Na__Get<uint32_t>(head, 243);
        layout.extended_count = Na__Get<uint64_t>(head, 247);
        for (int r = 0; r < 15; ++r) layout.extended_by_return[r] = Na__Get<uint64_t>(head, 255 + 8 * r);
    }
    layout.point_count = (layout.version_minor >= 4 && layout.extended_count != 0) ? layout.extended_count : layout.legacy_count;
    if (layout.version_minor >= 4 && layout.legacy_count != 0 && layout.extended_count != 0 &&
        layout.legacy_count != layout.extended_count) {
        error = "The LAS 1.4 header gives two different point counts.";
        return false;
    }
    if (layout.offset_to_points < layout.header_size || layout.offset_to_points > layout.file_size) {
        error = "The LAS header points past the end of the file.";
        return false;
    }
    const uint64_t room = layout.file_size - layout.offset_to_points;
    if (layout.point_count > room / layout.record_length) {
        error = "The LAS file is shorter than its header says (" + std::to_string(layout.point_count) +
                " points of " + std::to_string(layout.record_length) + " bytes). It may be incomplete.";
        return false;
    }
    layout.points_end = static_cast<uint64_t>(layout.offset_to_points) + layout.point_count * layout.record_length;
    if (layout.points_end > layout.file_size) {
        error = "The LAS file is shorter than its header says (" + std::to_string(layout.point_count) +
                " points of " + std::to_string(layout.record_length) + " bytes). It may be incomplete.";
        return false;
    }

    layout.header_bytes.resize(layout.header_size);
    if (!file.ReadAt(0, layout.header_bytes.data(), layout.header_size)) {
        error = "The LAS header could not be read.";
        return false;
    }

    // VLRs: back to back after the header, ending at or before the points.
    uint64_t at = layout.header_size;
    for (uint32_t v = 0; v < layout.vlr_count; ++v) {
        uint8_t vh[54];
        if (at + 54 > layout.offset_to_points || !file.ReadAt(at, vh, 54)) {
            error = "Variable length record " + std::to_string(v + 1) + " runs into the point data.";
            return false;
        }
        Na__LasVlrInfo info;
        info.header_offset = at;
        info.reserved  = Na__Get<uint16_t>(vh, 0);
        info.user_id   = Na__FixedText(vh + 2, 16);
        info.record_id = Na__Get<uint16_t>(vh, 18);
        info.length    = Na__Get<uint16_t>(vh, 20);
        at += 54 + info.length;
        if (at > layout.offset_to_points) {
            error = "Variable length record " + std::to_string(v + 1) + " runs into the point data.";
            return false;
        }
        layout.vlrs.push_back(info);
    }
    layout.vlr_end = at;

    // EVLRs (LAS 1.4): after the point data.
    if (layout.version_minor >= 4 && layout.evlr_count > 0) {
        if (layout.evlr_start < layout.points_end || layout.evlr_start > layout.file_size) {
            error = "The extended variable length records are not where the header says.";
            return false;
        }
        at = layout.evlr_start;
        for (uint32_t v = 0; v < layout.evlr_count; ++v) {
            uint8_t eh[60];
            if (at + 60 > layout.file_size || !file.ReadAt(at, eh, 60)) {
                error = "Extended variable length record " + std::to_string(v + 1) + " is cut short.";
                return false;
            }
            Na__LasEvlrInfo info;
            info.header_offset = at;
            info.user_id   = Na__FixedText(eh + 2, 16);
            info.record_id = Na__Get<uint16_t>(eh, 18);
            info.length    = Na__Get<uint64_t>(eh, 20);
            if (info.length > layout.file_size || at + 60 + info.length > layout.file_size) {
                error = "Extended variable length record " + std::to_string(v + 1) + " is cut short.";
                return false;
            }
            at += 60 + info.length;
            layout.evlrs.push_back(info);
        }
    }
    return true;
}

// -----------------------------------------------------------------------------
// REGION | Content key
// -----------------------------------------------------------------------------
//
// NAPC content key v1 covers:
//   - the file size
//   - every byte before the point records (header, VLRs, user data), up to 4 MB
//   - 64 blocks of 16 KB spread evenly over the point records (all of them
//     when the records are smaller than that), first and last block included
//   - up to 1 MB after the point records (EVLRs, waveform data)
// About 2 MB read in a few milliseconds, instead of hashing a whole file of
// several hundred MB on every Reload. Two different exports of one scan always
// differ (each carries a unique export id in its header). The point cache also
// records the LAS size and modified time, so an in-place edit that kept every
// sampled byte is still caught as "the LAS changed".

bool Na__LasFile__ContentKey(const std::wstring& path, uint64_t& key, std::string& error) {
    Na__File file;
    if (!file.OpenRead(path, false)) {
        error = "The LAS file could not be opened for reading.";
        return false;
    }
    const uint64_t size = file.Size();
    uint8_t head[227];
    if (size < sizeof(head) || !file.ReadAt(0, head, sizeof(head)) || std::memcmp(head, "LASF", 4) != 0) {
        error = "This is not a LAS file.";
        return false;
    }
    uint32_t offset_to_points;
    uint16_t record_length;
    uint32_t legacy_count;
    std::memcpy(&offset_to_points, head + 96, 4);
    std::memcpy(&record_length, head + 105, 2);
    std::memcpy(&legacy_count, head + 107, 4);
    uint64_t count = legacy_count;
    if (head[25] >= 4 && size >= 255) {
        uint64_t extended = 0;
        if (!file.ReadAt(247, &extended, 8)) { error = "The LAS header could not be read."; return false; }
        if (extended) count = extended;
    }
    const uint64_t points_begin = std::min<uint64_t>(offset_to_points, size);
    if (record_length) count = std::min<uint64_t>(count, (size - points_begin) / record_length);
    const uint64_t points_end   = std::min<uint64_t>(size, points_begin + count * record_length);

    uint64_t h = Na__Hash64(reinterpret_cast<const uint8_t*>("NAPC-CONTENT-KEY-1"), 18, size);
    std::vector<uint8_t> buffer;

    auto hash_range = [&](uint64_t begin, uint64_t length) -> bool {
        buffer.resize(static_cast<size_t>(length));
        if (length && !file.ReadAt(begin, buffer.data(), buffer.size())) return false;
        h = Na__Hash64(buffer.data(), buffer.size(), h ^ begin);
        return true;
    };

    if (!hash_range(0, std::min<uint64_t>(points_begin, 4ull << 20))) { error = "The LAS header could not be read."; return false; }

    const uint64_t block = 16384, blocks = 64;
    const uint64_t span = points_end - points_begin;
    if (span <= block * blocks) {
        if (!hash_range(points_begin, span)) { error = "The LAS point records could not be read."; return false; }
    } else {
        for (uint64_t j = 0; j < blocks; ++j) {
            const uint64_t at = points_begin + j * (span - block) / (blocks - 1);
            if (!hash_range(at, block)) { error = "The LAS point records could not be read."; return false; }
        }
    }
    if (size > points_end && !hash_range(points_end, std::min<uint64_t>(size - points_end, 1ull << 20))) {
        error = "The end of the LAS file could not be read.";
        return false;
    }
    key = h;
    return true;
}
