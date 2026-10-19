// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - CLEANING REGION
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__CleanRegion__.hpp
// PURPOSE    : The data every cleaning stage works on.
//
//   Na__CleanGrid  - one per loaded cloud: points sorted into coarse cells
//                    (about 250 mm) so a region's points are found without
//                    scanning the whole cloud. Built once, reused by every
//                    preview and by the export.
//   Na__CleanZones - how far around the core each stage must be computed so
//                    that every result INSIDE the core is exactly what a run
//                    over the whole cloud would give (see the .cpp).
//   Na__CleanWork  - one region: its points (copied, in a canonical order),
//                    their distance outside the core, a KD-tree, a fine cell
//                    grid, and every stage's results.
//
// CANONICAL ORDER: region points are sorted by (fine cell, LAS record), and
//   every loop that accumulates runs in that order, so two regions that hold
//   the same points produce the same bits.
//
// =============================================================================

#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <vector>

#include "Na__PointCloudViewer__NativeEngine__CleanTypes__.hpp"
#include "Na__PointCloudViewer__NativeEngine__Geometry__.hpp"
#include "Na__PointCloudViewer__NativeEngine__KdTree__.hpp"
#include "Na__PointCloudViewer__NativeEngine__Rasterizer__.hpp"

// -----------------------------------------------------------------------------
// REGION | Global coarse grid (per cloud)
// -----------------------------------------------------------------------------

struct Na__CleanGrid {
    double   cell = 0.0;               // source units
    int64_t  origin[3] = { 0, 0, 0 };  // first cell's integer coordinates
    int64_t  dims[3] = { 0, 0, 0 };
    float    lo[3] = { 0, 0, 0 }, hi[3] = { 0, 0, 0 };   // cloud bounds, local
    std::vector<uint32_t> start;       // dims product + 1 offsets into perm
    std::vector<uint32_t> perm;        // stored point indices sorted by cell
    double   build_ms = 0.0;
    size_t   MemoryBytes() const { return start.capacity() * 4 + perm.capacity() * 4; }
};

// mm_per_unit sets the cell size (250 mm, larger for huge sites).
bool Na__CleanGrid__Build(const Na__CloudPoints& points, double mm_per_unit, Na__CleanGrid& grid,
                          const std::atomic<bool>* cancel);

// -----------------------------------------------------------------------------
// REGION | Zones (millimetres outside the core)
// -----------------------------------------------------------------------------

struct Na__CleanZones {
    double density = 0;   // points density selection reads (refined position + flags)
    double refine  = 0;   // points whose refined position is needed
    double surface = 0;   // points whose cell needs a surface analysis
    double noise   = 0;   // points whose noise verdict is needed
    double spacing = 0;   // points whose local spacing and link distance are needed
    double knn     = 0;   // points whose nearest neighbours are needed
    double gather  = 0;   // everything read: the halo
};

// rotation_spread: max row sum of |R| for the frame (1 axis-aligned .. sqrt(3)),
// so cell-shaped reaches are converted to frame distances exactly.
Na__CleanZones Na__CleanZones__For(const Na__CleanParams& params, double rotation_spread);

// -----------------------------------------------------------------------------
// REGION | Surface analysis per fine cell
// -----------------------------------------------------------------------------

enum Na__CellFlag : uint8_t {
    NA_CELL_THIN     = 1u << 0,   // one clean sheet (used to measure the noise width)
    NA_CELL_MULTI    = 1u << 1,   // two or three surface orientations meet (corner, edge, reveal)
    NA_CELL_STEP     = 1u << 2,   // parallel sheets side by side (a real step: skirting, reveal, frame)
    NA_CELL_DOUBLING = 1u << 3,   // parallel sheets over the same area, or scan passes that disagree
    NA_CELL_BOUNDARY = 1u << 4,   // a surface ends inside the block (opening edge, top of a wall)
    NA_CELL_ROUGH    = 1u << 5,   // no confident surface (clutter, furniture, plants, scatter)
};

enum Na__FamilyFlag : uint8_t {
    NA_FAM_STEP     = 1u << 0,
    NA_FAM_DOUBLING = 1u << 1,
    NA_FAM_PASSES   = 1u << 2,    // the doubling evidence came from GPS time (scan passes)
    NA_FAM_NARROW   = 1u << 3,    // a narrow curved object (pipe, rail): no confident surface
    NA_FAM_BORROWED = 1u << 4,    // orientation lent by a thin cell nearby (diagnostics)
};

struct Na__SurfaceFamily {
    float   n[3] = { 0, 0, 1 };   // unit normal (canonical sign)
    float   c[3] = { 0, 0, 0 };   // reference point on the dominant sheet
    float   u[3] = { 1, 0, 0 };   // in-plane axes
    float   v[3] = { 0, 1, 0 };
    float   sheet[3] = { 0, 0, 0 };   // offsets of parallel sheets along n, relative to c
    uint8_t sheets = 1;
    uint8_t flags = 0;
    float   conf = 0.0f;          // 0..1
    float   gap = 0.0f;           // doubling: distance between the sheets or passes (units)
    float   sigma = 0.0f;         // noise width of ONE sheet when the sheets were split by the
                                  // mixture test (the cell's width counts both); 0 = use the cell's
    uint32_t members = 0;
};

struct Na__CellSurface {
    uint8_t  computed = 0;
    uint8_t  families = 0;
    uint8_t  flags = 0;
    uint8_t  pass1 = 0;           // thin test + pair sigma done
    uint8_t  thin = 0;            // pass 1 verdict (pass 3 reads it on neighbours; never rewritten)
    uint8_t  lent = 0;            // pass 3 diagnostics: planes lent by thin cells nearby,
    uint8_t  planes = 0;          // and planes found
    float    t_thick = -1.0f;     // pass 1 diagnostics: block thickness (units), in-plane pair
    float    t_pair = -1.0f;      // sigma (units), robust plane's angle to the PCA plane (deg)
    float    t_angle = -1.0f;     // and its inlier share
    float    t_share = -1.0f;
    float    pair_sigma = -1.0f;  // pass 1 (thin cells), units
    float    sigma = 0.0f;        // the noise width used for this cell, units
    float    thin_n[3] = { 0, 0, 0 };   // pass 1 (thin cells): the block's plane, lent to
    float    thin_c[3] = { 0, 0, 0 };   // the cells around it that hold several surfaces
    Na__SurfaceFamily family[3];
};

// A cell's analysis borrows the planes of thin cells up to this many cells
// away (the zone arithmetic reads it).
const int NA_SURFACE_BORROW_REACH = 3;

// -----------------------------------------------------------------------------
// REGION | One region's work
// -----------------------------------------------------------------------------

struct Na__CleanWork {
    // --- inputs ------------------------------------------------------------------
    std::shared_ptr<const Na__CloudPoints> cloud;
    const Na__CleanGrid* grid = nullptr;
    Na__CleanRegion region;
    Na__CleanParams params;           // as last run (stage caches compare against it)
    Na__CleanZones  zones;
    double units_per_mm = 0.001;
    const std::atomic<bool>* cancel = nullptr;

    // --- gathered points (canonical order) -----------------------------------------
    uint32_t n = 0;
    std::vector<float>    xyz;        // n * 3, local source units
    std::vector<uint32_t> stored;     // index in the loaded cloud
    std::vector<uint32_t> tie;        // LAS record (or stored index): identity + tie-break
    std::vector<float>    time;       // seconds (empty = no GPS time)
    std::vector<float>    depth;      // mm outside the core (0 = core)
    std::vector<uint8_t>  core;       // 1 = inside the core
    std::vector<uint32_t> cell;       // fine cell (linear index in the region's cell grid)

    // fine cell grid (cell size = params.cell_mm), anchored at the local origin.
    // SPARSE: only occupied cells exist. A cell id is its rank in canonical
    // (z, y, x) order among the occupied cells; Na__Clean__CellAt finds it
    // through a table of 16 x 16 x 16-cell blocks allocated only where points
    // are, so memory follows the points, not the region's volume (a dense grid
    // over a 16 m tile and its halo was ~400 MB even for a sparse cloud).
    double   fine = 0.0;              // units
    int64_t  fine_origin[3] = { 0, 0, 0 };
    int64_t  fine_dims[3] = { 0, 0, 0 };
    int64_t  block_dims[3] = { 0, 0, 0 };
    std::vector<uint32_t> block_table;  // block -> index into block_cells / 4096 (UINT32_MAX = no points)
    std::vector<uint32_t> block_cells;  // 4096 per allocated block: cell id (UINT32_MAX = empty)
    std::vector<int32_t>  cell_coord;   // 3 per cell: coordinates relative to fine_origin
    std::vector<uint32_t> cell_start; // cells + 1 (points of cell c: [cell_start[c], cell_start[c + 1]))
    std::vector<uint32_t> cell_slot;  // cell -> index into surfaces (every cell is occupied: identity)
    std::vector<uint32_t> slot_cell;  // slot -> cell (identity)
    std::vector<float>    cell_max_depth;   // per slot: deepest point in it (mm)

    Na__KdTree tree;

    // --- noise ----------------------------------------------------------------------
    std::vector<uint32_t> knn;        // n * NA_KNN slots (UINT32_MAX = none)
    std::vector<float>    knn_d2;     // matching squared distances
    std::vector<uint8_t>  knn_found;
    std::vector<float>    spacing;    // mean distance to the 8 nearest (units)
    std::vector<float>    spacing_ref;// median spacing around the point (units)
    std::vector<uint32_t> component;  // union-find root (zone 'spacing' points)

    // --- results ----------------------------------------------------------------------
    std::vector<uint16_t> flags;      // Na__CleanFlag
    std::vector<float>    delta;      // n * 3, refined displacement (units)
    std::vector<int8_t>   family_of;  // surface family of the point in its cell (-1 none) - refine zone
    std::vector<int8_t>   sheet_of;   // ... and which of its parallel sheets
    std::vector<Na__CellSurface> surfaces;   // per occupied fine cell (slot)
    float noise_sigma_mm = 0.0f;      // median measured noise width in the core
    float doubling_gap_mm = 0.0f;     // largest flagged gap in the core

    // --- which stages hold valid results for `params` (preview reuse) ---------------
    bool gathered = false, noise_done = false, surface_done = false, refine_done = false, density_done = false;
    double ms_gather = 0, ms_index = 0, ms_noise = 0, ms_surface = 0, ms_refine = 0, ms_density = 0;
    int reused = 0;                   // bit 0 gather, 1 noise, 2 surfaces, 3 refine (last run)

    // what each stage was last computed with (CleanPipeline.cpp)
    Na__CleanRegion key_region;
    double key_halo = -1.0, key_cell = -1.0, key_mpu = -1.0;
    std::vector<double> key_zones, key_noise, key_surface, key_refine, key_density;

    size_t MemoryBytes() const;
};

const int NA_KNN = 12;                // neighbours kept per point
const int NA_SPACING_K = 8;           // ... of which this many define its spacing

// -----------------------------------------------------------------------------
// REGION | Stages (each throws Na__Cancelled when work.cancel is set)
// -----------------------------------------------------------------------------

// Frame helpers for a region.
double Na__CleanRegion__RotationSpread(const Na__CleanRegion& region);

// Copies the points of core + halo, sorts them, builds the cell grid + KD-tree.
void Na__Clean__Gather(Na__CleanWork& work);
// Isolated points and small detached groups (CleanNoise.cpp).
void Na__Clean__Noise(Na__CleanWork& work);
// Surface analysis per fine cell (CleanSurface.cpp).
void Na__Clean__Surfaces(Na__CleanWork& work);
// Refined displacement per point + scatter candidates (CleanSurface.cpp).
void Na__Clean__Refine(Na__CleanWork& work);
// Representative-point thinning (CleanDensity.cpp).
void Na__Clean__Density(Na__CleanWork& work);
// Before / after scatter of the main surfaces in the core (CleanSection.cpp).
void Na__Clean__Section(const Na__CleanWork& work, double* stats);

// Fine cell helpers.
inline int64_t Na__FloorDiv(double value, double size) { return static_cast<int64_t>(std::floor(value / size)); }
bool Na__Clean__CellCoords(const Na__CleanWork& work, uint32_t cell, int64_t out[3]);
uint32_t Na__Clean__CellAt(const Na__CleanWork& work, int64_t cx, int64_t cy, int64_t cz);   // UINT32_MAX outside
