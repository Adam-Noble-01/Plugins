// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - CLEANING: REMOVE NOISE
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__CleanNoise__.cpp
// PURPOSE    : Filter 01. Removes what cannot be part of a surface:
//
//   1. ISOLATED POINTS - a point's spacing s (mean distance to its 8 nearest
//      neighbours) is compared with the spacing of the points around it
//      (median over itself and its 12 nearest). Isolated when s is more than
//      iso_ratio times that AND more than iso_min_mm; always isolated with at
//      most one other point within knn_cap_mm. Relative, not absolute: a far
//      ceiling scanned sparsely is sparse everywhere and survives, while a
//      stray return next to a dense wall stands out. (A global statistical
//      outlier filter, as PCL / Open3D / CloudCompare SOR use, would delete
//      the sparse far side of every room in a handheld SLAM scan.)
//
//   2. SMALL DETACHED GROUPS - points are linked when closer than
//      min(link(p), link(q)), link = link_factor x local spacing clamped to
//      [link_min, link_max]. A connected group with fewer than
//      cluster_min_points points that is smaller than cluster_max_mm across
//      is removed: clumps of stray returns, blobs floating in a window
//      opening. Anything attached to a surface (a door handle, a tap, a pipe
//      bracket) is linked to it and survives; so does any detached object
//      bigger or denser than the limits (a pendant lamp).
//
//   Dense, coherent false surfaces (a mirror image of the room seen in
//   glass) are NOT detectable from XYZ alone and are not touched here. The
//   sparse-scatter test after the surface analysis (CleanSurface.cpp) marks
//   off-surface scatter as candidates; only the opt-in reflection cleanup
//   removes them.
//
// EXACTNESS: verdicts are exact for points within zones.noise of the core: a
//   removable group there lies wholly inside zones.spacing, where every link
//   distance is known, and every neighbour it could link to is checked.
//
// =============================================================================

#include "Na__PointCloudViewer__NativeEngine__CleanRegion__.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <mutex>

namespace {

    double Na__MsSince(std::chrono::steady_clock::time_point start) {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    }

    uint32_t Na__Find(std::vector<uint32_t>& parent, uint32_t i) {
        while (parent[i] != i) {
            parent[i] = parent[parent[i]];
            i = parent[i];
        }
        return i;
    }

    bool Na__Union(std::vector<uint32_t>& parent, uint32_t a, uint32_t b) {
        a = Na__Find(parent, a);
        b = Na__Find(parent, b);
        if (a == b) return false;
        if (a < b) parent[b] = a; else parent[a] = b;
        return true;
    }

} // namespace

void Na__Clean__Noise(Na__CleanWork& w) {
    const auto start = std::chrono::steady_clock::now();
    w.noise_done = false;
    const Na__CleanParams& p = w.params;
    const uint32_t n = w.n;
    const double upm = w.units_per_mm;
    const float cap = static_cast<float>(p.knn_cap_mm * upm);
    const float cap2 = cap * cap;
    const float zone_knn = static_cast<float>(w.zones.knn);
    const float zone_spacing = static_cast<float>(w.zones.spacing);

    // Noise verdicts are recomputed from scratch.
    for (uint32_t i = 0; i < n; ++i) w.flags[i] &= static_cast<uint16_t>(~(NA_CF_REMOVED_ISOLATED | NA_CF_REMOVED_CLUSTER));

    // --- 1. nearest neighbours and spacing ----------------------------------------------
    w.knn.assign(static_cast<size_t>(n) * NA_KNN, UINT32_MAX);
    w.knn_d2.assign(static_cast<size_t>(n) * NA_KNN, 0.0f);
    w.knn_found.assign(n, 0);
    w.spacing.assign(n, cap);
    Na__ParallelFor(n, 2048, w.cancel, [&](int64_t b, int64_t e) {
        uint32_t idx[NA_KNN];
        float d2[NA_KNN];
        for (int64_t i = b; i < e; ++i) {
            if (w.depth[i] > zone_knn) continue;
            const int found = w.tree.Knn(&w.xyz[size_t(i) * 3], static_cast<uint32_t>(i), NA_KNN, cap2, idx, d2);
            w.knn_found[i] = static_cast<uint8_t>(found);
            double sum = 0.0;
            for (int j = 0; j < NA_SPACING_K; ++j) sum += j < found ? std::sqrt(static_cast<double>(d2[j])) : static_cast<double>(cap);
            w.spacing[i] = static_cast<float>(sum / NA_SPACING_K);
            for (int j = 0; j < found; ++j) {
                w.knn[size_t(i) * NA_KNN + j] = idx[j];
                w.knn_d2[size_t(i) * NA_KNN + j] = d2[j];
            }
        }
    });

    // --- 2. reference spacing, isolated points, link distances --------------------------
    w.spacing_ref.assign(n, cap);
    std::vector<float> link(n, 0.0f);
    std::vector<uint8_t> member(n, 0);       // takes part in the groups (zone 'spacing', not isolated)
    const float iso_min = static_cast<float>(p.iso_min_mm * upm);
    const float link_min = static_cast<float>(p.link_min_mm * upm), link_max = static_cast<float>(p.link_max_mm * upm);
    Na__ParallelFor(n, 4096, w.cancel, [&](int64_t b, int64_t e) {
        std::vector<float> values;
        values.reserve(NA_KNN + 1);
        for (int64_t i = b; i < e; ++i) {
            if (w.depth[i] > zone_spacing) continue;
            values.clear();
            values.push_back(w.spacing[i]);
            const int found = w.knn_found[i];
            for (int j = 0; j < found; ++j) values.push_back(w.spacing[w.knn[size_t(i) * NA_KNN + j]]);
            const float ref = Na__Stat__MedianF(values, w.spacing[i]);
            w.spacing_ref[i] = ref;
            const bool isolated = found <= 1 ||
                                  (w.spacing[i] > static_cast<float>(p.iso_ratio) * ref && w.spacing[i] > iso_min);
            if (isolated) {
                w.flags[i] |= NA_CF_REMOVED_ISOLATED;
            } else {
                member[i] = 1;
                link[i] = std::min(link_max, std::max(link_min, static_cast<float>(p.link_factor) * ref));
            }
        }
    });

    // --- 3. detached groups ---------------------------------------------------------------
    w.component.resize(n);
    for (uint32_t i = 0; i < n; ++i) w.component[i] = i;
    std::vector<uint8_t> touches(n, 0);      // linked to a point outside zone 'spacing': maybe larger than seen
    for (uint32_t i = 0; i < n; ++i) {
        if (!member[i]) continue;
        const int found = w.knn_found[i];
        for (int j = 0; j < found; ++j) {
            const uint32_t q = w.knn[size_t(i) * NA_KNN + j];
            const float d = std::sqrt(w.knn_d2[size_t(i) * NA_KNN + j]);
            if (d > link[i]) break;           // sorted: the rest are further
            if (w.flags[q] & NA_CF_REMOVED_ISOLATED) continue;
            if (!member[q]) { touches[i] = 1; continue; }
            if (d <= std::min(link[i], link[q])) Na__Union(w.component, i, q);
        }
    }
    Na__CheckCancel(w.cancel);

    const double cluster_max = p.cluster_max_mm * upm;
    const uint32_t min_points = static_cast<uint32_t>(std::max(0, p.cluster_min_points));
    struct Group { uint32_t count = 0; float lo[3] = { 1e30f, 1e30f, 1e30f }, hi[3] = { -1e30f, -1e30f, -1e30f }; uint8_t touch = 0; };
    std::vector<Group> groups;
    std::vector<uint32_t> group_of(n, UINT32_MAX);
    auto summarise = [&]() {
        groups.clear();
        std::vector<uint32_t> group_of_root(n, UINT32_MAX);
        for (uint32_t i = 0; i < n; ++i) {
            if (!member[i]) continue;
            const uint32_t root = Na__Find(w.component, i);
            if (group_of_root[root] == UINT32_MAX) { group_of_root[root] = static_cast<uint32_t>(groups.size()); groups.push_back(Group()); }
            const uint32_t g = group_of_root[root];
            group_of[i] = g;
            Group& gr = groups[g];
            ++gr.count;
            gr.touch |= touches[i];
            for (int a = 0; a < 3; ++a) { gr.lo[a] = std::min(gr.lo[a], w.xyz[size_t(i) * 3 + a]); gr.hi[a] = std::max(gr.hi[a], w.xyz[size_t(i) * 3 + a]); }
        }
    };
    auto removable = [&](const Group& g) {
        if (g.touch || g.count >= min_points) return false;
        const double dx = g.hi[0] - g.lo[0], dy = g.hi[1] - g.lo[1], dz = g.hi[2] - g.lo[2];
        return std::sqrt(dx * dx + dy * dy + dz * dz) < cluster_max;
    };

    if (min_points > 0 && cluster_max > 0) {
        summarise();
        // Small groups found through 12 nearest neighbours may still be linked
        // to something just beyond them: check every link a small group has.
        for (int round = 0; round < 6; ++round) {
            std::vector<uint32_t> small;
            for (uint32_t i = 0; i < n; ++i) if (member[i] && removable(groups[group_of[i]])) small.push_back(i);
            if (small.empty()) break;
            std::vector<std::pair<uint32_t, uint32_t>> edges;
            std::vector<uint32_t> touched;
            std::mutex edge_mutex;
            Na__ParallelFor(static_cast<int64_t>(small.size()), 256, w.cancel, [&](int64_t b, int64_t e) {
                std::vector<uint32_t> found;
                std::vector<std::pair<uint32_t, uint32_t>> local_edges;
                std::vector<uint32_t> local_touched;
                for (int64_t s = b; s < e; ++s) {
                    const uint32_t i = small[static_cast<size_t>(s)];
                    w.tree.Radius(&w.xyz[size_t(i) * 3], link[i] * link[i], found);
                    for (uint32_t q : found) {
                        if (q == i || (w.flags[q] & NA_CF_REMOVED_ISOLATED)) continue;
                        if (!member[q]) { local_touched.push_back(i); continue; }
                        if (group_of[q] == group_of[i]) continue;
                        const float dx = w.xyz[size_t(q) * 3] - w.xyz[size_t(i) * 3];
                        const float dy = w.xyz[size_t(q) * 3 + 1] - w.xyz[size_t(i) * 3 + 1];
                        const float dz = w.xyz[size_t(q) * 3 + 2] - w.xyz[size_t(i) * 3 + 2];
                        if (std::sqrt(dx * dx + dy * dy + dz * dz) <= std::min(link[i], link[q])) local_edges.emplace_back(i, q);
                    }
                }
                std::lock_guard<std::mutex> lock(edge_mutex);
                edges.insert(edges.end(), local_edges.begin(), local_edges.end());
                touched.insert(touched.end(), local_touched.begin(), local_touched.end());
            });
            bool changed = false;
            for (uint32_t i : touched) { if (!touches[i]) { touches[i] = 1; changed = true; } }
            for (const auto& edge : edges) changed |= Na__Union(w.component, edge.first, edge.second);
            summarise();
            if (!changed) break;
        }
        for (uint32_t i = 0; i < n; ++i) {
            if (member[i] && removable(groups[group_of[i]])) w.flags[i] |= NA_CF_REMOVED_CLUSTER;
        }
    }

    w.ms_noise = Na__MsSince(start);
    w.noise_done = true;
}
