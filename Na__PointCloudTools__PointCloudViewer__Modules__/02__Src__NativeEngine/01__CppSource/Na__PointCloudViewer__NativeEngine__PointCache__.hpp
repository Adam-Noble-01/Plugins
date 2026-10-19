// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - POINT CACHE (.napc)
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__PointCache__.hpp
// PURPOSE    : The engine's own copy of an imported cloud on disk, so the next
//              Reload reads one file straight into memory instead of decoding
//              and shuffling the whole LAS again.
//
// FORMAT v2 (v0.8.0, little-endian):
//   [256-byte header, CRC-32 over its first 252 bytes]
//   [xyz          float32 * 3 * count]  local coordinates, source units, shuffled order
//   [bgra         uint32 * count]       colours as drawn
//   [source index uint32 * count]       the LAS record of each stored point (flag bit 0)
//   [time         float32 * count]      GPS time - time_base, seconds (flag bit 1)
//   The header carries the point count, local origin and box (source units),
//   colour depth, the size + modified time of the LAS it was made from and
//   that LAS's content key, so a cache can never stand in for different LAS
//   content, and the plugin can tell when its LAS has changed.
//
// FORMAT v1 (v0.7.0) is the same header with zeros where v2 adds fields and
//   only the xyz + bgra sections. It is still read (for display); it has no
//   source index, so a cleaning export needs the LAS read again (the plugin
//   does that whenever the LAS is available, writing a v2 cache).
//
// SAFETY: written to <path>.tmp and renamed over the old file only once
//   complete, so a cache is either whole or absent. A cache that fails any
//   check is never used: the LAS is read instead. The LAS is never touched.
//
// =============================================================================

#pragma once

#include <atomic>
#include <cstdint>
#include <string>

struct Na__LasImportJob;
struct Na__CloudPoints;

#pragma pack(push, 1)
struct Na__CacheHeader {
    char     magic[8];          // "NAPCv2\0\0" ("NAPCv1\0\0" for version 1)
    uint32_t header_bytes;      // 256
    uint32_t version;           // 2 (1 is still read)
    int64_t  point_count;
    double   origin[3];         // local origin, source units
    double   local_min[3];
    double   local_max[3];
    int32_t  colour_bits;
    uint32_t flags;             // bit 0 source index section, bit 1 time section (v1: 0)
    double   las_bytes;         // the LAS it was made from: size ...
    double   las_mtime;         // ... and modified time (Unix seconds, as Ruby reports it)
    uint64_t xyz_bytes;
    uint64_t bgra_bytes;
    uint64_t source_index_bytes;    // v2
    uint64_t time_bytes;            // v2
    double   time_base;             // v2: GPS time of the first LAS record
    uint64_t content_key;           // v2: content key of the LAS (0 = unknown)
    uint8_t  reserved[84];
    uint32_t header_crc;        // CRC-32 of bytes 0..251
};
#pragma pack(pop)
static_assert(sizeof(Na__CacheHeader) == 256, "cache header must be 256 bytes");

const uint32_t NA_CACHE_VERSION      = 2;
const uint32_t NA_CACHE_FLAG_INDEX   = 1;
const uint32_t NA_CACHE_FLAG_TIME    = 2;

// Total file size a v2 cache of these points takes.
uint64_t Na__Cache__FileBytes(const Na__CloudPoints& points);

// Writes job.cloud + metadata (called on the import worker). `done` counts bytes.
bool Na__Cache__Write(const std::string& path_utf8, const Na__LasImportJob& job,
                      std::atomic<int64_t>& done, const std::atomic<bool>& cancel, bool& cancelled, std::string& error);

// Reads and fully validates the header (magic, version, CRC, sizes, file length).
bool Na__Cache__ReadHeader(const std::string& path_utf8, Na__CacheHeader& header, std::string& error);

// Worker body for a cache load: fills the job exactly like a LAS import does.
void Na__Cache__LoadWorker(Na__LasImportJob* job);
