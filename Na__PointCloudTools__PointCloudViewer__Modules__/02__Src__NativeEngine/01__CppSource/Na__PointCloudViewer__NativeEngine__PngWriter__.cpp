// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - PNG WRITER
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__PngWriter__.cpp
// PURPOSE    : Stored-deflate RGBA PNG: signature, IHDR, one IDAT (zlib header,
//              <= 65535-byte stored blocks, Adler-32), IEND. CRC-32 uses a
//              slicing-by-8 table; Adler-32 defers the modulo (NMAX = 5552).
//              Every worker copies and checksums its own run of blocks; the
//              per-run checksums are joined with zlib's combine maths, so the
//              file is byte-identical to a single-threaded encode.
//
// =============================================================================

#include "Na__PointCloudViewer__NativeEngine__PngWriter__.hpp"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <mutex>

namespace {

    // -------------------------------------------------------------------------
    // REGION | Checksums
    // -------------------------------------------------------------------------

    uint32_t g_crc_table[8][256];
    std::once_flag g_crc_once;

    void Na__Crc__BuildTables() {
        for (uint32_t n = 0; n < 256; ++n) {
            uint32_t c = n;
            for (int k = 0; k < 8; ++k) c = (c & 1u) ? 0xEDB88320u ^ (c >> 1) : (c >> 1);
            g_crc_table[0][n] = c;
        }
        for (uint32_t n = 0; n < 256; ++n) {
            uint32_t c = g_crc_table[0][n];
            for (int t = 1; t < 8; ++t) {
                c = g_crc_table[0][c & 0xFFu] ^ (c >> 8);
                g_crc_table[t][n] = c;
            }
        }
    }

    uint32_t Na__Crc32(const uint8_t* data, size_t size) {
        std::call_once(g_crc_once, Na__Crc__BuildTables);
        uint32_t crc = 0xFFFFFFFFu;
        while (size >= 8) {
            uint32_t one, two;
            std::memcpy(&one, data, 4);
            std::memcpy(&two, data + 4, 4);
            one ^= crc;
            crc = g_crc_table[7][one & 0xFF] ^ g_crc_table[6][(one >> 8) & 0xFF] ^
                  g_crc_table[5][(one >> 16) & 0xFF] ^ g_crc_table[4][one >> 24] ^
                  g_crc_table[3][two & 0xFF] ^ g_crc_table[2][(two >> 8) & 0xFF] ^
                  g_crc_table[1][(two >> 16) & 0xFF] ^ g_crc_table[0][two >> 24];
            data += 8;
            size -= 8;
        }
        while (size--) crc = g_crc_table[0][(crc ^ *data++) & 0xFF] ^ (crc >> 8);
        return crc ^ 0xFFFFFFFFu;
    }

    uint32_t Na__Adler32(const uint8_t* data, size_t size) {
        const uint32_t mod = 65521u;
        uint32_t a = 1, b = 0;
        while (size > 0) {
            size_t chunk = size < 5552 ? size : 5552;
            size -= chunk;
            while (chunk--) {
                a += *data++;
                b += a;
            }
            a %= mod;
            b %= mod;
        }
        return (b << 16) | a;
    }

    // Joining checksums of consecutive runs (the zlib method: CRC-32 shifts by
    // len2 zero bytes through GF(2) matrix squaring; Adler-32 is arithmetic).
    uint32_t Na__Gf2Times(const uint32_t* matrix, uint32_t vector) {
        uint32_t sum = 0;
        while (vector) {
            if (vector & 1u) sum ^= *matrix;
            vector >>= 1;
            ++matrix;
        }
        return sum;
    }

    void Na__Gf2Square(uint32_t* square, const uint32_t* matrix) {
        for (int n = 0; n < 32; ++n) square[n] = Na__Gf2Times(matrix, matrix[n]);
    }

    uint32_t Na__Crc32Combine(uint32_t crc1, uint32_t crc2, size_t len2) {
        if (len2 == 0) return crc1;
        uint32_t even[32];
        uint32_t odd[32];
        odd[0] = 0xEDB88320u;
        uint32_t row = 1;
        for (int n = 1; n < 32; ++n) {
            odd[n] = row;
            row <<= 1;
        }
        Na__Gf2Square(even, odd);
        Na__Gf2Square(odd, even);
        do {
            Na__Gf2Square(even, odd);
            if (len2 & 1u) crc1 = Na__Gf2Times(even, crc1);
            len2 >>= 1;
            if (len2 == 0) break;
            Na__Gf2Square(odd, even);
            if (len2 & 1u) crc1 = Na__Gf2Times(odd, crc1);
            len2 >>= 1;
        } while (len2 != 0);
        return crc1 ^ crc2;
    }

    uint32_t Na__Adler32Combine(uint32_t adler1, uint32_t adler2, size_t len2) {
        const uint32_t base = 65521u;
        const uint32_t rem  = static_cast<uint32_t>(len2 % base);
        uint32_t sum1 = adler1 & 0xFFFFu;
        uint32_t sum2 = static_cast<uint32_t>((static_cast<uint64_t>(rem) * sum1) % base);
        sum1 += (adler2 & 0xFFFFu) + base - 1;
        sum2 += ((adler1 >> 16) & 0xFFFFu) + ((adler2 >> 16) & 0xFFFFu) + base - rem;
        if (sum1 >= base) sum1 -= base;
        if (sum1 >= base) sum1 -= base;
        if (sum2 >= (base << 1)) sum2 -= (base << 1);
        if (sum2 >= base) sum2 -= base;
        return sum1 | (sum2 << 16);
    }

    // -------------------------------------------------------------------------
    // REGION | Byte Helpers
    // -------------------------------------------------------------------------

    void Na__PutBe32(uint8_t* out, uint32_t value) {
        out[0] = static_cast<uint8_t>(value >> 24);
        out[1] = static_cast<uint8_t>(value >> 16);
        out[2] = static_cast<uint8_t>(value >> 8);
        out[3] = static_cast<uint8_t>(value);
    }

    double Na__MsSince(std::chrono::steady_clock::time_point start) {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    }

} // namespace

// -----------------------------------------------------------------------------
// REGION | Public
// -----------------------------------------------------------------------------

uint32_t Na__Png__Crc32(const uint8_t* data, size_t size) {
    return Na__Crc32(data, size);
}

bool Na__Png__WriteStored(const std::wstring& path, const uint8_t* raw, size_t raw_size,
                          int width, int height, Na__ThreadPool& pool, std::vector<uint8_t>& scratch,
                          Na__PngTimings& timings, std::string& error) {
    const auto encode_start = std::chrono::steady_clock::now();

    const size_t block_max   = 65535;
    const size_t block_count = raw_size == 0 ? 1 : (raw_size + block_max - 1) / block_max;
    const size_t idat_size   = 2 + block_count * 5 + raw_size + 4;           // zlib header + blocks + adler
    const size_t file_size   = 8 + (12 + 13) + (12 + idat_size) + 12;
    scratch.resize(file_size);
    uint8_t* out = scratch.data();

    static const uint8_t signature[8] = { 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };
    std::memcpy(out, signature, 8);
    out += 8;

    // IHDR: width, height, bit depth 8, colour type 6 (RGBA), deflate, filter 0, no interlace.
    Na__PutBe32(out, 13);
    std::memcpy(out + 4, "IHDR", 4);
    Na__PutBe32(out + 8, static_cast<uint32_t>(width));
    Na__PutBe32(out + 12, static_cast<uint32_t>(height));
    out[16] = 8; out[17] = 6; out[18] = 0; out[19] = 0; out[20] = 0;
    Na__PutBe32(out + 21, Na__Crc32(out + 4, 17));
    out += 25;

    // IDAT
    Na__PutBe32(out, static_cast<uint32_t>(idat_size));
    std::memcpy(out + 4, "IDAT", 4);
    uint8_t* idat_type = out + 4;
    uint8_t* zlib = out + 8;
    zlib[0] = 0x78;
    zlib[1] = 0x01;
    uint8_t* blocks = zlib + 2;

    // Every block but the last is full, so block k starts at k * (5 + 65535).
    const unsigned workers = pool.Size();
    std::vector<uint32_t> run_adler(workers, 1u), run_crc(workers, 0u);
    std::vector<size_t>   run_raw(workers, 0), run_file(workers, 0);
    pool.Run([&](unsigned worker, unsigned count) {
        const size_t per   = (block_count + count - 1) / count;
        const size_t first = std::min(block_count, per * worker);
        const size_t last  = std::min(block_count, first + per);
        if (first >= last) return;
        uint8_t* const run_start = blocks + first * (5 + block_max);
        const uint8_t* const source_start = raw + first * block_max;
        uint8_t* cursor = run_start;
        const uint8_t* source = source_start;
        for (size_t block = first; block < last; ++block) {
            const size_t length = std::min(block_max, raw_size - block * block_max);
            const uint16_t len16 = static_cast<uint16_t>(length);
            cursor[0] = (block + 1 == block_count) ? 1 : 0;
            cursor[1] = static_cast<uint8_t>(len16 & 0xFF);
            cursor[2] = static_cast<uint8_t>(len16 >> 8);
            cursor[3] = static_cast<uint8_t>(~len16 & 0xFF);
            cursor[4] = static_cast<uint8_t>((~len16 >> 8) & 0xFF);
            std::memcpy(cursor + 5, source, length);
            cursor += 5 + length;
            source += length;
        }
        run_raw[worker]   = static_cast<size_t>(source - source_start);
        run_file[worker]  = static_cast<size_t>(cursor - run_start);
        run_adler[worker] = Na__Adler32(source_start, run_raw[worker]);
        run_crc[worker]   = Na__Crc32(run_start, run_file[worker]);
    });

    uint32_t adler = 1u;
    uint32_t crc   = Na__Crc32(idat_type, 6);                       // "IDAT" + zlib header
    size_t   block_bytes = 0;
    for (unsigned worker = 0; worker < workers; ++worker) {
        if (run_file[worker] == 0) continue;
        adler = Na__Adler32Combine(adler, run_adler[worker], run_raw[worker]);
        crc   = Na__Crc32Combine(crc, run_crc[worker], run_file[worker]);
        block_bytes += run_file[worker];
    }
    uint8_t* cursor = blocks + block_bytes;
    Na__PutBe32(cursor, adler);
    crc = Na__Crc32Combine(crc, Na__Crc32(cursor, 4), 4);
    cursor += 4;
    Na__PutBe32(cursor, crc);
    cursor += 4;

    // IEND
    Na__PutBe32(cursor, 0);
    std::memcpy(cursor + 4, "IEND", 4);
    Na__PutBe32(cursor + 8, Na__Crc32(cursor + 4, 4));

    timings.encode_ms = Na__MsSince(encode_start);
    timings.bytes     = file_size;

    const auto write_start = std::chrono::steady_clock::now();
    FILE* file = nullptr;
    if (_wfopen_s(&file, path.c_str(), L"wb") != 0 || !file) {
        error = "The render image file could not be opened for writing.";
        return false;
    }
    const size_t written = std::fwrite(scratch.data(), 1, file_size, file);
    std::fclose(file);
    timings.write_ms = Na__MsSince(write_start);
    if (written != file_size) {
        error = "The render image file could not be written completely.";
        return false;
    }
    return true;
}
