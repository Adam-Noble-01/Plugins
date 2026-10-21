// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - LAZ TO LAS CONVERTER
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__LazConvert__.hpp
// PURPOSE    : Decompresses a LAZ file into a NEW uncompressed LAS file, on
//              one worker thread with atomic progress and cancel.
//
// LOSSLESS BY CONSTRUCTION (the rule):
//   - Points: the vendored LASzip 3.5.0 decodes each record; LASzip's own raw
//     item writers (laswriteitemraw.hpp, the code its uncompressed writer
//     uses) turn it back into LAS record bytes. X, Y and Z stay the integers
//     stored in the file; nothing is rescaled, re-offset or reordered.
//   - Header: copied byte for byte from the LAZ. Only what compression itself
//     changed is put back: the point format byte loses its compression bits,
//     the LASzip VLR is taken out (so the VLR count and the offset to the
//     points shrink), and a LAS 1.4 file's EVLR start moves to just after
//     the points. Scale, offset, bounds, counts, GUID, dates, system id and
//     generating software are untouched. The bounds are NOT recomputed: the
//     points' real extent is measured and reported alongside, never written.
//   - VLRs, user data after the header and (LAS 1.4) EVLRs are copied
//     verbatim. COPC index records (user id "copc") describe chunk offsets
//     inside the compressed file, are meaningless in a LAS and are dropped,
//     with a note.
//
// REFUSED (plain message, nothing written): a file that is not LAZ, LASzip
//   "compatibility mode" files (LAS 1.4 points disguised as 1.2/1.3: their
//   stored header is not the real one), internal waveform data, and any file
//   whose header LASzip reads differently from the bytes on disk.
//
// CHECKED BEFORE PUBLISHING: the new file is written as
//   <final>.partial-<tag> and flushed, then (1) its layout must read back as
//   a valid uncompressed LAS with exactly the LAZ's format, record length,
//   point count, scale, offset and bounds; (2) its point record bytes must
//   hash to exactly what was written; (3) LASzip must read every record back
//   into the same point (same hash again). Only then is it renamed into place,
//   WITHOUT replacing anything. Cancel or any failure deletes the partial
//   file; the LAZ is only ever opened for reading.
//
// =============================================================================

#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>

enum Na__LazConvertPhase {
    NA_LAZ_PHASE_STARTING   = 0,
    NA_LAZ_PHASE_CONVERTING = 1,    // decoding the LAZ, writing the LAS
    NA_LAZ_PHASE_CHECKING   = 2,    // reading the new LAS back
    NA_LAZ_PHASE_PUBLISHING = 3,
    NA_LAZ_PHASE_DONE       = 4
};

struct Na__LazConvertJob {
    // inputs (set before the thread starts)
    std::string source_utf8;
    std::string dest_utf8;

    // progress (any thread)
    std::atomic<int>     phase{ NA_LAZ_PHASE_STARTING };
    std::atomic<int64_t> done{ 0 };
    std::atomic<int64_t> total{ 0 };
    std::atomic<bool>    cancel_requested{ false };
    std::atomic<bool>    finished{ false };
    std::atomic<bool>    failed{ false };
    std::atomic<bool>    cancelled{ false };

    // results (valid after finished == true)
    int64_t  point_count = 0;
    int      point_format = 0;
    int      record_length = 0;
    int      version_major = 0, version_minor = 0;
    uint64_t source_bytes = 0;
    uint64_t written_bytes = 0;
    double   header_min[3] = { 0, 0, 0 };   // as stated in the LAZ header (and kept in the LAS)
    double   header_max[3] = { 0, 0, 0 };
    double   point_min[3]  = { 0, 0, 0 };   // the points' real extent (integer * scale + offset)
    double   point_max[3]  = { 0, 0, 0 };
    int      dropped_records = 0;           // COPC VLRs / EVLRs left out
    double   convert_ms = 0, check_ms = 0, total_ms = 0;

    std::mutex  text_mutex;
    std::string error;
    std::string notes;                      // ' | ' separated, plain English

    std::thread worker;
};

// Starts the worker. Na__LazConvert__Destroy cancels, joins and frees.
void Na__LazConvert__Start(Na__LazConvertJob* job);
void Na__LazConvert__Destroy(Na__LazConvertJob* job);

// -----------------------------------------------------------------------------
// REGION | Record writer (LazRecord.cpp - LASzip's raw item writers)
// -----------------------------------------------------------------------------
//
// Kept in its own translation unit: it includes LASzip's internal headers
// (mydefs.hpp) and so stays clear of <windows.h>.

struct laszip_point;

class Na__LazRecordWriter {
public:
    Na__LazRecordWriter();
    ~Na__LazRecordWriter();
    Na__LazRecordWriter(const Na__LazRecordWriter&) = delete;
    Na__LazRecordWriter& operator=(const Na__LazRecordWriter&) = delete;

    // Items of point format 0..10 plus extra_bytes, reading from *point.
    // False when the format is unknown or the lengths do not add up.
    bool Setup(int point_format, int record_length, const laszip_point* point, std::string& error);
    // Writes exactly record_length bytes of the current point to out.
    bool Write(uint8_t* out);

private:
    struct Impl;
    Impl* m_impl;
};
