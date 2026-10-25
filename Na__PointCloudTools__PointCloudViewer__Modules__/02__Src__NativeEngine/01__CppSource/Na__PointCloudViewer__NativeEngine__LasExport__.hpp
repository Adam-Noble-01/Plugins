// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - LAS EXPORT (CLEANED COPY)
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__LasExport__.hpp
// PURPOSE    : Writes a NEW LAS file: the source's records, minus the removed
//              ones, with X / Y / Z changed only for refined points.
//
// WHAT IS KEPT, BYTE FOR BYTE: every field of every kept record (intensity,
//   returns, classification and flags, scan angle, user data, point source,
//   GPS time, RGB, NIR, wave packet descriptors, extra bytes), the public
//   header (version, point format, record length, scale, offset, GUID, file
//   source, global encoding, header padding), every VLR (coordinate system,
//   extra-bytes descriptors, classification table...), the bytes between the
//   VLRs and the points, and every EVLR and internal waveform record.
//
// WHAT IS UPDATED: point counts (legacy and LAS 1.4), points by return
//   (recomputed from the records), the bounds, the offsets that follow the
//   point data, the creation day/year, "System Identifier" = MODIFICATION (as
//   the LAS specification asks of modified files), "Generating Software", and
//   extra-bytes min/max statistics, which are cleared (marked absent) when
//   points were removed because they would describe deleted records.
//
// WHAT IS ADDED: one VLR, user "NobleArch_PCV", record 1, holding a JSON
//   provenance record (source file and its content key, every cleaning
//   parameter, the counts, a unique export id, and the previous record when
//   the source was itself a cleaned file).
//
// WHAT IS DROPPED (and reported): index records that describe the source's
//   point order (LAStools spatial index EVLR, LASzip / COPC records), and
//   bytes after the last structure of a pre-1.3 file.
//
// COORDINATES: an unmoved point keeps its integer X / Y / Z exactly. A moved
//   point is source + displacement, quantised with the file's own scale and
//   offset. If that would not fit the file's 32-bit range (RealityCapture
//   sets its scale so the range ends exactly at the bounds), the point keeps
//   its original position and is counted.
//
// SAFETY (see ARCHITECTURE section 22):
//   - the source is opened read-only and never written;
//   - every source record is checked against the engine's copy of that point
//     (same position, through the same conversion), so a LAS changed since it
//     was loaded, or a wrong mapping, stops the export;
//   - the output is written to "<final>.partial-<id>" created with CREATE_NEW,
//     flushed to disk, then re-read in full by LASzip (an independent reader)
//     and compared, and only then renamed to the final name WITHOUT
//     MOVEFILE_REPLACE_EXISTING: an existing file is never replaced;
//   - any failure or cancel deletes the partial file.
//
// =============================================================================

#pragma once

#include <atomic>
#include <cstdint>
#include <string>
#include <vector>

#include "Na__PointCloudViewer__NativeEngine__Rasterizer__.hpp"

enum Na__ExportPhase {
    NA_EXPORT_PHASE_CHECKING = 0,
    NA_EXPORT_PHASE_INDEXING = 1,
    NA_EXPORT_PHASE_CLEANING = 2,
    NA_EXPORT_PHASE_WRITING  = 3,
    NA_EXPORT_PHASE_VERIFYING = 4,
    NA_EXPORT_PHASE_PUBLISHING = 5,
    NA_EXPORT_PHASE_DONE = 6
};

struct Na__LasExportInput {
    std::wstring source;             // the LAS the cloud was loaded from (read only)
    std::wstring final_path;         // the NEW file (must not exist)
    const Na__CloudPoints* cloud = nullptr;
    const std::vector<uint16_t>* flags = nullptr;    // per stored point
    const std::vector<float>* delta = nullptr;       // per stored point * 3; null = no point moves (Crop and Cut)
    double origin[3] = { 0, 0, 0 };  // the loaded cloud's local origin (source units)
    std::string provenance_json;     // from Ruby: settings, ids
    std::string software;            // "Na Point Cloud Viewer 0.8.0"
};

struct Na__LasExportResult {
    uint64_t source_points = 0;
    uint64_t written_points = 0;
    uint64_t moved_points = 0;
    uint64_t held_range = 0;          // moves refused: outside the file's coordinate range
    uint64_t removed_points = 0;
    double   min[3] = { 0, 0, 0 }, max[3] = { 0, 0, 0 };   // new bounds (source coordinates)
    uint64_t bytes = 0;
    bool     by_return_mismatch = false;   // the source header's return counts disagreed with its records
    uint32_t dropped_vlrs = 0, dropped_evlrs = 0;
    uint64_t dropped_tail_bytes = 0;
    bool     cleared_extra_stats = false;
    std::string temp_path_utf8;
    std::string notes;               // plain-English, ' | ' separated
};

// Writes, verifies and publishes. `done` / `total` count records per phase.
bool Na__LasExport__Run(const Na__LasExportInput& input, std::atomic<int>& phase, std::atomic<int64_t>& done,
                        std::atomic<int64_t>& total, const std::atomic<bool>& cancel, bool& cancelled,
                        Na__LasExportResult& result, std::string& error);
