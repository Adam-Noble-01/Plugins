// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - KD-TREE
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__KdTree__.hpp
// PURPOSE    : Nearest-neighbour and radius queries over one cleaning region's
//              points (float32, source units).
//
// WHY NOT NANOFLANN: nanoflann (BSD) was the obvious candidate and is a fine
//   library, but its k-nearest result keeps whichever of several equidistant
//   points it meets first, so the answer depends on the tree's shape. LAS
//   coordinates are quantised (0.1 mm, 1 mm grids), which makes exactly equal
//   distances common, and a preview box and a full-cloud tile build different
//   trees from different point sets. Here every comparison is on
//   (squared distance, tie key) with the tie key = the point's LAS record
//   number, so a query returns the same neighbours from any tree that holds
//   them: the preview equals the export bit for bit.
//
// LAYOUT: median split on the longest axis, leaves of up to 12 points, a
//   box per node for exact pruning, points copied into tree order.
//
// BUILD: on a flat copy of the coordinates (each split streams through
//   memory instead of reading points through an index), the top levels one
//   level at a time with that level's splits in parallel, then each subtree
//   below on its own thread. The splits are exactly those of a one-thread
//   build (each range is split by the same rule on the same points); only the
//   node numbering differs, and no query result depends on it.
//
// =============================================================================

#pragma once

#include <cstdint>
#include <vector>

class Na__KdTree {
public:
    // pts: n * 3 floats; tie: n keys (distinct per point). Both are copied.
    void Build(const float* pts, const uint32_t* tie, uint32_t n);
    void Clear();
    uint32_t Size() const { return m_count; }

    // The k (<= 32) nearest points other than `self` (pass UINT32_MAX for none)
    // within squared distance max_d2, ordered by (d2, tie). Returns the count.
    int Knn(const float* q, uint32_t self, int k, float max_d2, uint32_t* out_index, float* out_d2) const;

    // Every point within squared distance r2 (inclusive), unordered.
    void Radius(const float* q, float r2, std::vector<uint32_t>& out) const;

    size_t MemoryBytes() const;

private:
    struct Node {
        float    lo[3];
        float    hi[3];
        uint32_t begin;
        uint32_t end;
        uint32_t left;       // 0 = leaf (node 0 is the root, never a child)
        uint32_t right;
    };
    struct Item {
        float    p[3];
        uint32_t index;      // point index (also the split tie-break)
    };
    // Bounds of items[begin, end) and, when it splits, the axis (-1 = leaf).
    static int Split(Item* items, uint32_t begin, uint32_t end, float lo[3], float hi[3]);
    // Subtree over items[begin, end) appended to `nodes`; returns its id there.
    static uint32_t BuildNode(std::vector<Node>& nodes, Item* items, uint32_t begin, uint32_t end);

    std::vector<Node>     m_nodes;
    std::vector<uint32_t> m_order;   // tree position -> point index
    std::vector<float>    m_pts;     // tree order coordinates
    std::vector<uint32_t> m_tie;     // tree order tie keys
    uint32_t              m_count = 0;
};
