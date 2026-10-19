// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - KD-TREE
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__KdTree__.cpp
// PURPOSE    : See the header.
//
// =============================================================================

#include "Na__PointCloudViewer__NativeEngine__KdTree__.hpp"
#include "Na__PointCloudViewer__NativeEngine__Geometry__.hpp"

#include <algorithm>
#include <cfloat>
#include <cstring>

namespace {
    const uint32_t NA_LEAF = 12;

    inline float Na__BoxDist2(const float* q, const float* lo, const float* hi) {
        float d2 = 0.0f;
        for (int a = 0; a < 3; ++a) {
            const float below = lo[a] - q[a], above = q[a] - hi[a];
            const float d = below > 0.0f ? below : (above > 0.0f ? above : 0.0f);
            d2 += d * d;
        }
        return d2;
    }

    inline float Na__Dist2(const float* a, const float* b) {
        const float dx = a[0] - b[0], dy = a[1] - b[1], dz = a[2] - b[2];
        return dx * dx + dy * dy + dz * dz;
    }
}

void Na__KdTree::Clear() {
    std::vector<Node>().swap(m_nodes);
    std::vector<uint32_t>().swap(m_order);
    std::vector<float>().swap(m_pts);
    std::vector<uint32_t>().swap(m_tie);
    m_count = 0;
}

size_t Na__KdTree::MemoryBytes() const {
    return m_nodes.capacity() * sizeof(Node) + m_order.capacity() * 4 + m_pts.capacity() * 4 + m_tie.capacity() * 4;
}

int Na__KdTree::Split(Item* items, uint32_t begin, uint32_t end, float lo[3], float hi[3]) {
    for (int a = 0; a < 3; ++a) { lo[a] = FLT_MAX; hi[a] = -FLT_MAX; }
    for (uint32_t i = begin; i < end; ++i) {
        for (int a = 0; a < 3; ++a) {
            lo[a] = std::min(lo[a], items[i].p[a]);
            hi[a] = std::max(hi[a], items[i].p[a]);
        }
    }
    if (end - begin <= NA_LEAF) return -1;
    int axis = 0;
    float extent = hi[0] - lo[0];
    for (int a = 1; a < 3; ++a) {
        if (hi[a] - lo[a] > extent) { extent = hi[a] - lo[a]; axis = a; }
    }
    if (!(extent > 0.0f)) return -1;          // every point identical: one leaf, however many
    const uint32_t mid = begin + (end - begin) / 2;
    std::nth_element(items + begin, items + mid, items + end, [axis](const Item& i, const Item& j) {
        return i.p[axis] < j.p[axis] || (i.p[axis] == j.p[axis] && i.index < j.index);
    });
    return axis;
}

uint32_t Na__KdTree::BuildNode(std::vector<Node>& nodes, Item* items, uint32_t begin, uint32_t end) {
    const uint32_t id = static_cast<uint32_t>(nodes.size());
    nodes.push_back(Node());
    Node node;
    node.begin = begin;
    node.end = end;
    node.left = node.right = 0;
    if (Split(items, begin, end, node.lo, node.hi) >= 0) {
        const uint32_t mid = begin + (end - begin) / 2;
        node.left  = BuildNode(nodes, items, begin, mid);
        node.right = BuildNode(nodes, items, mid, end);
    }
    nodes[id] = node;
    return id;
}

void Na__KdTree::Build(const float* pts, const uint32_t* tie, uint32_t n) {
    this->Clear();
    m_count = n;
    if (n == 0) return;
    std::vector<Item> items(n);
    Na__ParallelFor(n, 1 << 16, nullptr, [&](int64_t b, int64_t e) {
        for (int64_t i = b; i < e; ++i) {
            std::memcpy(items[size_t(i)].p, pts + size_t(i) * 3, 12);
            items[size_t(i)].index = static_cast<uint32_t>(i);
        }
    });
    m_nodes.reserve(n / NA_LEAF * 2 + 8);

    // Top levels, one level at a time; each level's ranges are split in parallel.
    struct Range { uint32_t begin, end, node; };
    std::vector<Range> level(1, Range{ 0, n, 0 }), next;
    m_nodes.push_back(Node());
    const size_t wide = 64;                   // ranges handed to whole-subtree tasks
    while (!level.empty() && level.size() < wide && level[0].end - level[0].begin > 4096) {
        std::vector<int> axis(level.size());
        std::vector<Node> made(level.size());
        Na__ParallelFor(static_cast<int64_t>(level.size()), 1, nullptr, [&](int64_t b, int64_t e) {
            for (int64_t k = b; k < e; ++k) {
                const Range& r = level[size_t(k)];
                axis[size_t(k)] = Split(items.data(), r.begin, r.end, made[size_t(k)].lo, made[size_t(k)].hi);
            }
        });
        next.clear();
        for (size_t k = 0; k < level.size(); ++k) {
            Node node = made[k];
            node.begin = level[k].begin;
            node.end = level[k].end;
            node.left = node.right = 0;
            if (axis[k] >= 0) {
                const uint32_t mid = node.begin + (node.end - node.begin) / 2;
                node.left = static_cast<uint32_t>(m_nodes.size());
                m_nodes.push_back(Node());
                node.right = static_cast<uint32_t>(m_nodes.size());
                m_nodes.push_back(Node());
                next.push_back(Range{ node.begin, mid, node.left });
                next.push_back(Range{ mid, node.end, node.right });
            }
            m_nodes[level[k].node] = node;
        }
        level.swap(next);
    }

    // Below: whole subtrees in parallel, each into its own node list, then
    // appended (its root goes into the node waiting for it).
    std::vector<std::vector<Node>> subtrees(level.size());
    Na__ParallelFor(static_cast<int64_t>(level.size()), 1, nullptr, [&](int64_t b, int64_t e) {
        for (int64_t k = b; k < e; ++k) {
            const Range& r = level[size_t(k)];
            BuildNode(subtrees[size_t(k)], items.data(), r.begin, r.end);
        }
    });
    for (size_t k = 0; k < level.size(); ++k) {
        const std::vector<Node>& sub = subtrees[k];
        const uint32_t base = static_cast<uint32_t>(m_nodes.size());      // where sub[1] lands
        auto moved = [base](Node node) {
            if (node.left != 0) { node.left += base - 1; node.right += base - 1; }
            return node;
        };
        m_nodes[level[k].node] = moved(sub[0]);
        for (size_t j = 1; j < sub.size(); ++j) m_nodes.push_back(moved(sub[j]));
    }

    m_order.resize(n);
    m_pts.resize(static_cast<size_t>(n) * 3);
    m_tie.resize(n);
    Na__ParallelFor(n, 1 << 16, nullptr, [&](int64_t b, int64_t e) {
        for (int64_t i = b; i < e; ++i) {
            const Item& it = items[size_t(i)];
            m_order[size_t(i)] = it.index;
            std::memcpy(&m_pts[size_t(i) * 3], it.p, 12);
            m_tie[size_t(i)] = tie[it.index];
        }
    });
}

int Na__KdTree::Knn(const float* q, uint32_t self, int k, float max_d2, uint32_t* out_index, float* out_d2) const {
    if (m_count == 0 || k <= 0) return 0;
    k = std::min(k, 32);
    uint32_t best_pos[32];
    float    best_d2[32];
    uint32_t best_tie[32];
    int found = 0;

    uint32_t stack[64];
    int top = 0;
    stack[top++] = 0;
    while (top > 0) {
        const Node& node = m_nodes[stack[--top]];
        const float worst = found < k ? max_d2 : best_d2[found - 1];
        if (Na__BoxDist2(q, node.lo, node.hi) > worst) continue;
        if (node.left == 0) {
            for (uint32_t i = node.begin; i < node.end; ++i) {
                if (m_order[i] == self) continue;
                const float d2 = Na__Dist2(q, &m_pts[static_cast<size_t>(i) * 3]);
                if (d2 > max_d2) continue;
                const uint32_t t = m_tie[i];
                if (found == k && (d2 > best_d2[k - 1] || (d2 == best_d2[k - 1] && t >= best_tie[k - 1]))) continue;
                int at = found < k ? found++ : k - 1;
                while (at > 0 && (best_d2[at - 1] > d2 || (best_d2[at - 1] == d2 && best_tie[at - 1] > t))) {
                    best_d2[at] = best_d2[at - 1]; best_tie[at] = best_tie[at - 1]; best_pos[at] = best_pos[at - 1];
                    --at;
                }
                best_d2[at] = d2; best_tie[at] = t; best_pos[at] = i;
            }
        } else {
            const Node& l = m_nodes[node.left];
            const Node& r = m_nodes[node.right];
            const float dl = Na__BoxDist2(q, l.lo, l.hi), dr = Na__BoxDist2(q, r.lo, r.hi);
            // nearer child on top of the stack, so it is searched first
            if (top + 2 > 64) continue;   // cannot happen with a balanced tree of < 2^60 points
            if (dl <= dr) { stack[top++] = node.right; stack[top++] = node.left; }
            else          { stack[top++] = node.left;  stack[top++] = node.right; }
        }
    }
    for (int i = 0; i < found; ++i) {
        out_index[i] = m_order[best_pos[i]];
        out_d2[i] = best_d2[i];
    }
    return found;
}

void Na__KdTree::Radius(const float* q, float r2, std::vector<uint32_t>& out) const {
    out.clear();
    if (m_count == 0) return;
    uint32_t stack[64];
    int top = 0;
    stack[top++] = 0;
    while (top > 0) {
        const Node& node = m_nodes[stack[--top]];
        if (Na__BoxDist2(q, node.lo, node.hi) > r2) continue;
        if (node.left == 0) {
            for (uint32_t i = node.begin; i < node.end; ++i) {
                if (Na__Dist2(q, &m_pts[static_cast<size_t>(i) * 3]) <= r2) out.push_back(m_order[i]);
            }
        } else if (top + 2 <= 64) {
            stack[top++] = node.left;
            stack[top++] = node.right;
        }
    }
}
