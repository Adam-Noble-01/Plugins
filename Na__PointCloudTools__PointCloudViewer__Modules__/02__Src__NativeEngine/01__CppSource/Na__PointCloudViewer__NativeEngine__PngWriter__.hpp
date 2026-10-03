// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - PNG WRITER
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__PngWriter__.hpp
// PURPOSE    : Writes an RGBA PNG with UNCOMPRESSED (stored) zlib blocks.
//
// WHY STORED:
//   Measured in SketchUp 26.2: ImageRep#load_file of a stored PNG is the
//   fastest route that keeps alpha (~16 ns/px) - faster than ImageRep#set_data
//   (~54 ns/px for 32-bit). Compression would only add decode time; the file
//   lives in the OS cache and is overwritten every frame.
//
// =============================================================================

#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "Na__PointCloudViewer__NativeEngine__ThreadPool__.hpp"

struct Na__PngTimings {
    double encode_ms = 0.0;
    double write_ms  = 0.0;
    size_t bytes     = 0;
};

// Standard CRC-32 (PNG / zlib), slicing-by-8. Thread-safe.
uint32_t Na__Png__Crc32(const uint8_t* data, size_t size);

// raw: height rows of [filter byte 0][width * 4 bytes RGBA], top row first.
// The copy and both checksums run on every worker of `pool`.
bool Na__Png__WriteStored(const std::wstring& path, const uint8_t* raw, size_t raw_size,
                          int width, int height, Na__ThreadPool& pool, std::vector<uint8_t>& scratch,
                          Na__PngTimings& timings, std::string& error);
