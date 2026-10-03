// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - POINT CACHE (.napc)
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__PointCache__.hpp
// PURPOSE    : The engine's own copy of an imported cloud on disk, so the next
//              Reload reads one file straight into memory instead of decoding
//              and shuffling the whole LAS again.
//
// FORMAT v1 (little-endian):
//   [256-byte header, CRC-32 over its first 252 bytes]
//   [xyz  float32 * 3 * count]   local coordinates, source units, shuffled order
//   [bgra uint32 * count]        colours as drawn
//   The header carries the point count, local origin and box (source units),
//   colour depth, and the size + modified time of the LAS it was made from,
//   so the plugin can tell whether that LAS has changed since.
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

#pragma pack(push, 1)
struct Na__CacheHeader {
    char     magic[8];          // "NAPCv1\0\0"
    uint32_t header_bytes;      // 256
    uint32_t version;           // 1
    int64_t  point_count;
    double   origin[3];         // local origin, source units
    double   local_min[3];
    double   local_max[3];
    int32_t  colour_bits;
    int32_t  reserved0;
    double   las_bytes;         // the LAS it was made from: size ...
    double   las_mtime;         // ... and modified time (Unix seconds, as Ruby reports it)
    uint64_t xyz_bytes;
    uint64_t bgra_bytes;
    uint8_t  reserved[116];
    uint32_t header_crc;        // CRC-32 of bytes 0..251
};
#pragma pack(pop)
static_assert(sizeof(Na__CacheHeader) == 256, "cache header must be 256 bytes");

const uint32_t NA_CACHE_VERSION = 1;

// Writes job.cloud + metadata (called on the import worker). `done` counts bytes.
bool Na__Cache__Write(const std::string& path_utf8, const Na__LasImportJob& job,
                      std::atomic<int64_t>& done, const std::atomic<bool>& cancel, bool& cancelled, std::string& error);

// Reads and fully validates the header (magic, version, CRC, sizes, file length).
bool Na__Cache__ReadHeader(const std::string& path_utf8, Na__CacheHeader& header, std::string& error);

// Worker body for a cache load: fills the job exactly like a LAS import does.
void Na__Cache__LoadWorker(Na__LasImportJob* job);
