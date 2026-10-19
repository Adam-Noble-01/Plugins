// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - LAS FILE (RAW ACCESS)
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__LasFile__.hpp
// PURPOSE    : Byte-level access to an UNCOMPRESSED LAS file, independent of
//              LASzip:
//                - Na__LasLayout: every header field, the VLR and EVLR lists,
//                  and where each part of the file sits (LAS 1.0 to 1.4)
//                - the content key that names a point cache
//                - a small Win32 file wrapper (Unicode paths, > 4 GB files)
//
// WHY NOT LASZIP HERE: LASzip decodes points into a struct and its writer
//   (3.5.0) drops EVLRs and the waveform start ("EVLRs not supported ...
//   writing 0 instead") and rewrites the generating software. A cleaned LAS
//   must keep every byte it does not deliberately change, so the exporter
//   copies source records verbatim and patches only X, Y and Z. LASzip is
//   still the importer, and it independently re-reads every exported file.
//
// FIELD OFFSETS: ASPRS LAS 1.4 R15, Table 3 (public header block). Older
//   versions are prefixes of it: 1.0 to 1.2 end at byte 227, 1.3 at 235.
//
// =============================================================================

#pragma once

#include <cstdint>
#include <string>
#include <vector>

// -----------------------------------------------------------------------------
// REGION | Point record formats
// -----------------------------------------------------------------------------

// Minimum record length of formats 0..10 (extra bytes come after these).
int  Na__Las__MinRecordLength(int format);
// Byte offset of the GPS time double inside a record, or -1 (formats 0 and 2).
int  Na__Las__GpsTimeOffset(int format);
// Return number of a record (1..5 legacy formats, 1..15 formats 6..10).
int  Na__Las__ReturnNumber(const uint8_t* record, int format);

// THE conversion from a LAS integer coordinate to the engine's stored float
// (source unit, relative to the local origin). One compiled function, used by
// the importer and by the exporter's record check, so both get the same bits.
float Na__Las__LocalCoordinate(int32_t value, double scale, double offset, double origin);

// -----------------------------------------------------------------------------
// REGION | Layout
// -----------------------------------------------------------------------------

struct Na__LasVlrInfo {
    uint64_t    header_offset = 0;     // file offset of the 54-byte VLR header
    uint16_t    reserved = 0;
    std::string user_id;               // up to 16 characters
    uint16_t    record_id = 0;
    uint16_t    length = 0;            // bytes after the header
};

struct Na__LasEvlrInfo {
    uint64_t    header_offset = 0;     // file offset of the 60-byte EVLR header
    std::string user_id;
    uint16_t    record_id = 0;
    uint64_t    length = 0;            // bytes after the header
};

struct Na__LasLayout {
    uint64_t file_size = 0;
    uint8_t  version_major = 0;
    uint8_t  version_minor = 0;
    uint16_t global_encoding = 0;
    uint16_t header_size = 0;
    uint32_t offset_to_points = 0;
    uint32_t vlr_count = 0;
    uint8_t  format_byte = 0;          // as stored (LAZ sets bit 7 / 6)
    int      point_format = 0;         // low 6 bits
    bool     compressed = false;
    uint16_t record_length = 0;
    uint32_t legacy_count = 0;
    uint32_t legacy_by_return[5] = {};
    uint64_t extended_count = 0;       // LAS 1.4 only
    uint64_t extended_by_return[15] = {};
    uint64_t point_count = 0;          // whichever count the file uses
    double   scale[3] = {};
    double   offset[3] = {};
    double   max[3] = {};
    double   min[3] = {};
    uint64_t waveform_start = 0;       // LAS 1.3+
    uint64_t evlr_start = 0;           // LAS 1.4
    uint32_t evlr_count = 0;
    uint64_t vlr_end = 0;              // first byte after the last VLR
    uint64_t points_end = 0;           // offset_to_points + count * record_length
    std::vector<uint8_t>        header_bytes;   // [0, header_size)
    std::vector<Na__LasVlrInfo>  vlrs;
    std::vector<Na__LasEvlrInfo> evlrs;
};

// Reads and checks the header, the VLR list and (LAS 1.4) the EVLR list.
// Refuses compressed files, unknown formats and inconsistent sizes.
bool Na__LasFile__ReadLayout(const std::wstring& path, Na__LasLayout& layout, std::string& error);

// 64-bit content key (see the .cpp for exactly what it covers). Distinct LAS
// contents get distinct cache files; an exported file always differs from its
// source because it carries a unique export id.
bool Na__LasFile__ContentKey(const std::wstring& path, uint64_t& key, std::string& error);

// Stable 64-bit hash (NAPC content key v1). Never change: cache names depend on it.
uint64_t Na__Hash64(const uint8_t* data, size_t size, uint64_t seed);

// -----------------------------------------------------------------------------
// REGION | File wrapper
// -----------------------------------------------------------------------------

std::wstring Na__Utf8ToWide(const std::string& utf8);
std::string  Na__WideToUtf8(const std::wstring& wide);

class Na__File {
public:
    Na__File() = default;
    ~Na__File();
    Na__File(const Na__File&) = delete;
    Na__File& operator=(const Na__File&) = delete;

    bool OpenRead(const std::wstring& path, bool sequential);
    bool CreateNew(const std::wstring& path);      // fails if the file exists
    bool IsOpen() const;
    uint64_t Size() const;
    bool ReadAt(uint64_t offset, void* buffer, size_t size);
    bool Read(void* buffer, size_t size);
    bool Write(const void* buffer, size_t size);
    bool WriteAt(uint64_t offset, const void* buffer, size_t size);
    bool Seek(uint64_t offset);
    bool Flush();                                    // FlushFileBuffers: on disk, not just cached
    // Volume serial + file index: the identity of the file itself, whatever path reached it.
    bool Identity(uint64_t& volume, uint64_t& index) const;
    void Close();

private:
    void* m_handle = nullptr;
};
