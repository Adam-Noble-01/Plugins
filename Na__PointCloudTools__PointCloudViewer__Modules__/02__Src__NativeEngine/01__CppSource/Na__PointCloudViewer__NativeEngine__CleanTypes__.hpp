// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - CLEANING TYPES
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__CleanTypes__.hpp
// PURPOSE    : The cleaning engine's parameters (physical units, as Ruby sends
//              them), per-point result flags and the statistics layouts shared
//              with the Ruby bridge.
//
// UNITS: every length parameter is in MILLIMETRES. The engine converts to the
//   cloud's source unit with mm_per_unit (1000 for metres, 304.8 for feet...),
//   so the algorithms never depend on which unit the LAS happens to use.
//
// The mapping from the user's strength sliders to these values lives in Ruby
// (80__System__Clean/...Settings__.rb); the engine only ever sees physical
// thresholds, so every test can name exactly what it ran.
//
// =============================================================================

#pragma once

#include <cstdint>

// -----------------------------------------------------------------------------
// REGION | Filter parameters (doubles, in this order)
// -----------------------------------------------------------------------------

enum Na__CleanParamIndex {
    NAPC_CP_MM_PER_UNIT = 0,          // millimetres per source unit

    // Remove Noise
    NAPC_CP_NOISE_ENABLED,            // 0 / 1
    NAPC_CP_ISO_RATIO,                // isolated: own spacing > ratio x the local spacing ...
    NAPC_CP_ISO_MIN_MM,               // ... and more than this
    NAPC_CP_KNN_CAP_MM,               // neighbours are only looked for this far
    NAPC_CP_LINK_FACTOR,              // detached groups: linked when closer than factor x local spacing ...
    NAPC_CP_LINK_MIN_MM,              // ... but at least this ...
    NAPC_CP_LINK_MAX_MM,              // ... and at most this
    NAPC_CP_CLUSTER_MIN_POINTS,       // a detached group with fewer points ...
    NAPC_CP_CLUSTER_MAX_MM,           // ... and smaller than this is removed
    NAPC_CP_BLOWOUT_REMOVE,           // 0 = only mark sparse off-surface scatter, 1 = remove it
    NAPC_CP_SCATTER_RATIO,            // scatter: spacing > ratio x the spacing of the surfaces around it

    // Refine Surfaces
    NAPC_CP_REFINE_ENABLED,
    NAPC_CP_REFINE_STRENGTH,          // 0..1: share of the distance to the local surface a point moves
    NAPC_CP_MAX_MOVE_MM,              // no point ever moves further than this
    NAPC_CP_CELL_MM,                  // analysis cell; the surface is judged over 3 x 3 x 3 cells
    NAPC_CP_SMOOTH_RADIUS_MM,         // the local surface under a point is fitted over this radius
    NAPC_CP_INLIER_BAND,              // only points within this many noise widths of the surface move
    NAPC_CP_PASS_GAP_S,               // a gap in GPS time this long starts a new scan pass
    NAPC_CP_PASS_DISAGREE_MM,         // passes (or parallel sheets) further apart than this are flagged
    NAPC_CP_DOUBLING_HOLD,            // 1 = leave flagged doubled surfaces unrefined
    NAPC_CP_SIGMA_FALLBACK_MM,        // noise width assumed where none can be measured

    // Reduce Density
    NAPC_CP_DENSITY_ENABLED,
    NAPC_CP_VOXEL_MM,                 // keep about one point per cube of this size on plain surfaces
    NAPC_CP_FEATURE_FACTOR,           // ... and this many times finer at corners, edges and steps

    NAPC_CP_COUNT
};

struct Na__CleanParams {
    double mm_per_unit = 1000.0;

    bool   noise_enabled = true;
    double iso_ratio = 3.0;
    double iso_min_mm = 20.0;
    double knn_cap_mm = 100.0;
    double link_factor = 3.0;
    double link_min_mm = 40.0;
    double link_max_mm = 120.0;
    int    cluster_min_points = 35;
    double cluster_max_mm = 200.0;
    bool   blowout_remove = false;
    double scatter_ratio = 2.5;

    bool   refine_enabled = true;
    double refine_strength = 0.7;
    double max_move_mm = 25.0;
    double cell_mm = 50.0;
    double smooth_radius_mm = 30.0;
    double inlier_band = 3.0;
    double pass_gap_s = 2.0;
    double pass_disagree_mm = 15.0;
    bool   doubling_hold = true;
    double sigma_fallback_mm = 8.0;

    bool   density_enabled = false;
    double voxel_mm = 9.0;
    double feature_factor = 2.5;
};

// Reads (and clamps to safe ranges) NAPC_CP_COUNT doubles.
bool Na__CleanParams__FromArray(const double* values, int32_t count, Na__CleanParams& params, const char** error);

// -----------------------------------------------------------------------------
// REGION | Per-point result flags (uint16)
// -----------------------------------------------------------------------------

enum Na__CleanFlag : uint16_t {
    NA_CF_REMOVED_ISOLATED  = 1u << 0,   // Remove Noise: isolated point
    NA_CF_REMOVED_CLUSTER   = 1u << 1,   // Remove Noise: small detached group
    NA_CF_REMOVED_BLOWOUT   = 1u << 2,   // Remove Noise: sparse scatter off any surface (reflection cleanup on)
    NA_CF_REMOVED_DENSITY   = 1u << 3,   // Reduce Density: not the point kept for its cell
    NA_CF_MOVED             = 1u << 4,   // Refine Surfaces moved it
    NA_CF_CANDIDATE         = 1u << 5,   // sparse scatter off any surface, kept (reflection cleanup off)
    NA_CF_DOUBLING          = 1u << 6,   // on a surface seen twice, apart (possible scan registration error)
    NA_CF_HELD_AMBIGUOUS    = 1u << 7,   // near where two surfaces meet: left where it was
    NA_CF_HELD_RANGE        = 1u << 8,   // export: the LAS quantisation could not hold its new position
    NA_CF_ON_SURFACE        = 1u << 9,   // assigned to a confident local surface
    NA_CF_FEATURE           = 1u << 10,  // in a corner, edge, step or rough cell (density kept more)
    NA_CF_REMOVED_KEEP      = 1u << 11,  // Crop and Cut: outside the Keep box (box export only)
    NA_CF_REMOVED_CUT       = 1u << 12,  // Crop and Cut: inside a Cut box (box export only)
};

const uint16_t NA_CF_REMOVED_BOX = NA_CF_REMOVED_KEEP | NA_CF_REMOVED_CUT;
const uint16_t NA_CF_REMOVED_ANY = NA_CF_REMOVED_ISOLATED | NA_CF_REMOVED_CLUSTER | NA_CF_REMOVED_BLOWOUT | NA_CF_REMOVED_DENSITY |
                                   NA_CF_REMOVED_BOX;
const uint16_t NA_CF_REMOVED_NOISE = NA_CF_REMOVED_ISOLATED | NA_CF_REMOVED_CLUSTER | NA_CF_REMOVED_BLOWOUT;

// -----------------------------------------------------------------------------
// REGION | Region (where a run applies)
// -----------------------------------------------------------------------------
//
// A run cleans the CORE of a region and reads a margin (halo) around it, so
// that every result inside the core is exactly what a run over the whole cloud
// gives. The core is a box in a FRAME: frame = M * local + t, where M is a
// rotation times a uniform scale (frame units per source unit). The preview
// uses the model frame (the clip box, in inches); full-cloud tiles use the
// local frame itself.

struct Na__CleanRegion {
    double m[9] = { 1, 0, 0, 0, 1, 0, 0, 0, 1 };
    double t[3] = { 0, 0, 0 };
    double lo[3] = { 0, 0, 0 };
    double hi[3] = { 0, 0, 0 };
    double frame_per_unit = 1.0;      // uniform scale of M
    bool   half_open = false;         // tiles: [lo, hi) so a point lands in exactly one tile
};

// Region parameters from Ruby: [m (9), t (3), lo (3), hi (3), frame_per_unit].
const int32_t NAPC_REGION_COUNT = 19;

// -----------------------------------------------------------------------------
// REGION | Preview statistics (doubles, napc_clean_preview_stats)
// -----------------------------------------------------------------------------

enum Na__CleanStatIndex {
    NAPC_CS_CORE_POINTS = 0, NAPC_CS_KEPT, NAPC_CS_REMOVED_ISOLATED, NAPC_CS_REMOVED_CLUSTER,
    NAPC_CS_REMOVED_BLOWOUT, NAPC_CS_REMOVED_DENSITY, NAPC_CS_MOVED, NAPC_CS_CANDIDATES,
    NAPC_CS_DOUBLING, NAPC_CS_HELD_AMBIGUOUS, NAPC_CS_ON_SURFACE, NAPC_CS_FEATURE,
    NAPC_CS_MOVE_MEDIAN_MM, NAPC_CS_MOVE_P95_MM, NAPC_CS_MOVE_MAX_MM,
    NAPC_CS_GATHERED_POINTS, NAPC_CS_HALO_MM, NAPC_CS_SIGMA_MM, NAPC_CS_DOUBLING_GAP_MM,
    NAPC_CS_GATHER_MS, NAPC_CS_INDEX_MS, NAPC_CS_NOISE_MS, NAPC_CS_SURFACE_MS, NAPC_CS_REFINE_MS,
    NAPC_CS_DENSITY_MS, NAPC_CS_SECTION_MS, NAPC_CS_TOTAL_MS,
    NAPC_CS_REUSED_STAGES,            // bit 0 gather+index, bit 1 noise, bit 2 surfaces, bit 3 refine
    NAPC_CS_SURFACE_COUNT,            // 0..2 surfaces measured (below), -1 = the region is not suitable
    NAPC_CS_SURFACE_NOTE,             // 0 ok, 1 several surfaces, 2 no dominant flat surface, 3 too few points
    NAPC_CS_S0,                       // first surface block (NAPC_SS_COUNT doubles), then the second
    NAPC_CS_COUNT = NAPC_CS_S0 + 2 * 16
};

// One measured surface (offsets from NAPC_CS_S0 + k * NAPC_SS_COUNT).
enum Na__CleanSurfaceStat {
    NAPC_SS_KIND = 0,                 // 1 wall (vertical), 2 floor or ceiling (horizontal), 3 sloping
    NAPC_SS_NX, NAPC_SS_NY, NAPC_SS_NZ, // normal in LOCAL axes
    NAPC_SS_POINTS_BEFORE, NAPC_SS_POINTS_AFTER,
    NAPC_SS_BAND_BEFORE_MM,           // P95 - P5 of distances to the fitted plane, before
    NAPC_SS_BAND_AFTER_MM,            // the same points (those kept), after
    NAPC_SS_SIGMA_BEFORE_MM, NAPC_SS_SIGMA_AFTER_MM,   // robust (MAD) widths
    NAPC_SS_SHIFT_MM,                 // median after - median before: did the surface move?
    NAPC_SS_MOVED, NAPC_SS_REMOVED,
    NAPC_SS_FLAGS,                    // bit 0 stepped / parallel sheet inside, bit 1 mixed cells, bit 2 doubling
    NAPC_SS_SHARE,                    // share of the box's points on this surface (0..1)
    NAPC_SS_RESERVED,
    NAPC_SS_COUNT                     // 16
};
