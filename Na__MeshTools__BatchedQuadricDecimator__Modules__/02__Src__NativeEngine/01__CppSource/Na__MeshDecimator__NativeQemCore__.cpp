#include "Na__MeshDecimator__NativeQemCore__.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <limits>
#include <unordered_map>
#include <unordered_set>

namespace NaMeshDecimatorNative {
namespace {

constexpr double Na__NativeQem__Epsilon = 1.0e-9;

struct NaEdgeRecord {
    int a = 0;
    int b = 0;
    std::vector<int> triangle_indices;
};

struct NaCollapseCandidate {
    int keep = 0;
    int remove = 0;
    std::array<double, 3> point;
    std::array<double, 10> quadric;
    double error = 0.0;
};

std::array<double, 10> Na__NativeQem__ZeroQuadric()
{
    return { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };
}

std::array<double, 3> Na__NativeQem__Subtract(
    const std::array<double, 3>& a,
    const std::array<double, 3>& b
)
{
    return { a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}

std::array<double, 3> Na__NativeQem__Cross(
    const std::array<double, 3>& a,
    const std::array<double, 3>& b
)
{
    return {
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0]
    };
}

double Na__NativeQem__Dot(
    const std::array<double, 3>& a,
    const std::array<double, 3>& b
)
{
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

double Na__NativeQem__Length(const std::array<double, 3>& vector)
{
    return std::sqrt(Na__NativeQem__Dot(vector, vector));
}

double Na__NativeQem__TriangleAreaTwice(
    const std::array<double, 3>& p0,
    const std::array<double, 3>& p1,
    const std::array<double, 3>& p2
)
{
    return Na__NativeQem__Length(
        Na__NativeQem__Cross(
            Na__NativeQem__Subtract(p1, p0),
            Na__NativeQem__Subtract(p2, p0)
        )
    );
}

std::array<double, 10> Na__NativeQem__AddQuadrics(
    const std::array<double, 10>& qa,
    const std::array<double, 10>& qb
)
{
    return {
        qa[0] + qb[0],
        qa[1] + qb[1],
        qa[2] + qb[2],
        qa[3] + qb[3],
        qa[4] + qb[4],
        qa[5] + qb[5],
        qa[6] + qb[6],
        qa[7] + qb[7],
        qa[8] + qb[8],
        qa[9] + qb[9]
    };
}

bool Na__NativeQem__CreatePlaneQuadric(
    const std::array<double, 3>& p0,
    const std::array<double, 3>& p1,
    const std::array<double, 3>& p2,
    std::array<double, 10>& quadric
)
{
    const auto edge_a = Na__NativeQem__Subtract(p1, p0);
    const auto edge_b = Na__NativeQem__Subtract(p2, p0);
    const auto normal = Na__NativeQem__Cross(edge_a, edge_b);
    const double length = Na__NativeQem__Length(normal);

    if (length <= Na__NativeQem__Epsilon) {
        return false;
    }

    const double a = normal[0] / length;
    const double b = normal[1] / length;
    const double c = normal[2] / length;
    const double d = -(a * p0[0] + b * p0[1] + c * p0[2]);

    quadric = {
        a * a,
        a * b,
        a * c,
        a * d,
        b * b,
        b * c,
        b * d,
        c * c,
        c * d,
        d * d
    };

    return true;
}

double Na__NativeQem__CalculateQuadricError(
    const std::array<double, 10>& quadric,
    const std::array<double, 3>& point
)
{
    const double x = point[0];
    const double y = point[1];
    const double z = point[2];

    return quadric[0] * x * x +
        2.0 * quadric[1] * x * y +
        2.0 * quadric[2] * x * z +
        2.0 * quadric[3] * x +
        quadric[4] * y * y +
        2.0 * quadric[5] * y * z +
        2.0 * quadric[6] * y +
        quadric[7] * z * z +
        2.0 * quadric[8] * z +
        quadric[9];
}

double Na__NativeQem__Determinant3x3(
    double a00, double a01, double a02,
    double a10, double a11, double a12,
    double a20, double a21, double a22
)
{
    return a00 * (a11 * a22 - a12 * a21) -
        a01 * (a10 * a22 - a12 * a20) +
        a02 * (a10 * a21 - a11 * a20);
}

bool Na__NativeQem__SolveOptimalPoint(
    const std::array<double, 10>& quadric,
    std::array<double, 3>& point
)
{
    const double a00 = quadric[0]; const double a01 = quadric[1]; const double a02 = quadric[2];
    const double a10 = quadric[1]; const double a11 = quadric[4]; const double a12 = quadric[5];
    const double a20 = quadric[2]; const double a21 = quadric[5]; const double a22 = quadric[7];

    const double b0 = -quadric[3];
    const double b1 = -quadric[6];
    const double b2 = -quadric[8];

    const double det = Na__NativeQem__Determinant3x3(
        a00, a01, a02,
        a10, a11, a12,
        a20, a21, a22
    );

    if (std::abs(det) <= Na__NativeQem__Epsilon) {
        return false;
    }

    const double det_x = Na__NativeQem__Determinant3x3(b0, a01, a02, b1, a11, a12, b2, a21, a22);
    const double det_y = Na__NativeQem__Determinant3x3(a00, b0, a02, a10, b1, a12, a20, b2, a22);
    const double det_z = Na__NativeQem__Determinant3x3(a00, a01, b0, a10, a11, b1, a20, a21, b2);

    point = { det_x / det, det_y / det, det_z / det };
    return true;
}

std::array<double, 3> Na__NativeQem__FindBestCollapsePoint(
    const std::array<double, 10>& quadric,
    const std::array<double, 3>& point_a,
    const std::array<double, 3>& point_b
)
{
    std::array<double, 3> solved;
    if (Na__NativeQem__SolveOptimalPoint(quadric, solved)) {
        return solved;
    }

    const std::array<double, 3> midpoint = {
        (point_a[0] + point_b[0]) * 0.5,
        (point_a[1] + point_b[1]) * 0.5,
        (point_a[2] + point_b[2]) * 0.5
    };

    std::array<double, 3> best = point_a;
    double best_error = Na__NativeQem__CalculateQuadricError(quadric, best);

    const double point_b_error = Na__NativeQem__CalculateQuadricError(quadric, point_b);
    if (point_b_error < best_error) {
        best = point_b;
        best_error = point_b_error;
    }

    const double midpoint_error = Na__NativeQem__CalculateQuadricError(quadric, midpoint);
    if (midpoint_error < best_error) {
        best = midpoint;
    }

    return best;
}

NaNativeMesh Na__NativeQem__CompactMesh(const NaNativeMesh& mesh)
{
    NaNativeMesh compacted;
    compacted.stopped_early = mesh.stopped_early;

    std::vector<bool> used(mesh.vertices.size(), false);
    std::vector<NaNativeTriangle> usable_triangles;
    usable_triangles.reserve(mesh.triangles.size());

    for (const auto& triangle : mesh.triangles) {
        const int a = triangle.vertices[0];
        const int b = triangle.vertices[1];
        const int c = triangle.vertices[2];

        if (a == b || b == c || c == a) {
            continue;
        }

        if (a < 0 || b < 0 || c < 0 ||
            a >= static_cast<int>(mesh.vertices.size()) ||
            b >= static_cast<int>(mesh.vertices.size()) ||
            c >= static_cast<int>(mesh.vertices.size())) {
            continue;
        }

        if (Na__NativeQem__TriangleAreaTwice(
            mesh.vertices[a].point,
            mesh.vertices[b].point,
            mesh.vertices[c].point
        ) <= Na__NativeQem__Epsilon) {
            continue;
        }

        used[a] = true;
        used[b] = true;
        used[c] = true;
        usable_triangles.push_back(triangle);
    }

    std::vector<int> remap(mesh.vertices.size(), -1);
    compacted.vertices.reserve(mesh.vertices.size());

    for (size_t index = 0; index < mesh.vertices.size(); ++index) {
        if (!used[index]) {
            continue;
        }

        remap[index] = static_cast<int>(compacted.vertices.size());
        NaNativeVertex vertex;
        vertex.point = mesh.vertices[index].point;
        vertex.quadric = Na__NativeQem__ZeroQuadric();
        compacted.vertices.push_back(vertex);
    }

    compacted.triangles.reserve(usable_triangles.size());
    for (auto triangle : usable_triangles) {
        triangle.vertices = {
            remap[triangle.vertices[0]],
            remap[triangle.vertices[1]],
            remap[triangle.vertices[2]]
        };
        compacted.triangles.push_back(triangle);
    }

    return compacted;
}

void Na__NativeQem__BuildInitialQuadrics(NaNativeMesh& mesh)
{
    for (auto& vertex : mesh.vertices) {
        vertex.quadric = Na__NativeQem__ZeroQuadric();
    }

    for (const auto& triangle : mesh.triangles) {
        const int a = triangle.vertices[0];
        const int b = triangle.vertices[1];
        const int c = triangle.vertices[2];

        std::array<double, 10> quadric;
        if (!Na__NativeQem__CreatePlaneQuadric(
            mesh.vertices[a].point,
            mesh.vertices[b].point,
            mesh.vertices[c].point,
            quadric
        )) {
            continue;
        }

        mesh.vertices[a].quadric = Na__NativeQem__AddQuadrics(mesh.vertices[a].quadric, quadric);
        mesh.vertices[b].quadric = Na__NativeQem__AddQuadrics(mesh.vertices[b].quadric, quadric);
        mesh.vertices[c].quadric = Na__NativeQem__AddQuadrics(mesh.vertices[c].quadric, quadric);
    }
}

std::uint64_t Na__NativeQem__EdgeKey(int a, int b)
{
    const std::uint32_t u = static_cast<std::uint32_t>(std::min(a, b));
    const std::uint32_t v = static_cast<std::uint32_t>(std::max(a, b));
    return (static_cast<std::uint64_t>(u) << 32) | v;
}

std::vector<NaEdgeRecord> Na__NativeQem__BuildEdgeData(
    const std::vector<NaNativeTriangle>& triangles
)
{
    std::vector<NaEdgeRecord> edges;
    std::unordered_map<std::uint64_t, size_t> index_by_key;

    edges.reserve(triangles.size() * 3);
    index_by_key.reserve(triangles.size() * 3);

    for (size_t tri_index = 0; tri_index < triangles.size(); ++tri_index) {
        const auto& triangle = triangles[tri_index];
        const int raw_edges[3][2] = {
            { triangle.vertices[0], triangle.vertices[1] },
            { triangle.vertices[1], triangle.vertices[2] },
            { triangle.vertices[2], triangle.vertices[0] }
        };

        for (const auto& raw_edge : raw_edges) {
            const int a = std::min(raw_edge[0], raw_edge[1]);
            const int b = std::max(raw_edge[0], raw_edge[1]);
            const std::uint64_t key = Na__NativeQem__EdgeKey(a, b);

            auto found = index_by_key.find(key);
            if (found == index_by_key.end()) {
                NaEdgeRecord record;
                record.a = a;
                record.b = b;
                record.triangle_indices.push_back(static_cast<int>(tri_index));
                index_by_key[key] = edges.size();
                edges.push_back(record);
            } else {
                edges[found->second].triangle_indices.push_back(static_cast<int>(tri_index));
            }
        }
    }

    return edges;
}

bool Na__NativeQem__CollapseWouldInvertTriangles(
    const std::vector<NaNativeVertex>& vertices,
    const std::vector<NaNativeTriangle>& triangles,
    int keep_index,
    int remove_index,
    const std::array<double, 3>& collapse_point
)
{
    for (const auto& triangle : triangles) {
        const bool adjacent =
            triangle.vertices[0] == keep_index || triangle.vertices[1] == keep_index || triangle.vertices[2] == keep_index ||
            triangle.vertices[0] == remove_index || triangle.vertices[1] == remove_index || triangle.vertices[2] == remove_index;

        if (!adjacent) {
            continue;
        }

        const std::array<double, 3> old_points[3] = {
            vertices[triangle.vertices[0]].point,
            vertices[triangle.vertices[1]].point,
            vertices[triangle.vertices[2]].point
        };

        const int new_indices[3] = {
            triangle.vertices[0] == remove_index ? keep_index : triangle.vertices[0],
            triangle.vertices[1] == remove_index ? keep_index : triangle.vertices[1],
            triangle.vertices[2] == remove_index ? keep_index : triangle.vertices[2]
        };

        if (new_indices[0] == new_indices[1] ||
            new_indices[1] == new_indices[2] ||
            new_indices[2] == new_indices[0]) {
            continue;
        }

        std::array<double, 3> new_points[3];
        for (int i = 0; i < 3; ++i) {
            const int vertex_index = triangle.vertices[i];
            new_points[i] = (vertex_index == keep_index || vertex_index == remove_index)
                ? collapse_point
                : vertices[vertex_index].point;
        }

        const auto old_normal = Na__NativeQem__Cross(
            Na__NativeQem__Subtract(old_points[1], old_points[0]),
            Na__NativeQem__Subtract(old_points[2], old_points[0])
        );

        const auto new_normal = Na__NativeQem__Cross(
            Na__NativeQem__Subtract(new_points[1], new_points[0]),
            Na__NativeQem__Subtract(new_points[2], new_points[0])
        );

        if (Na__NativeQem__Length(new_normal) <= Na__NativeQem__Epsilon) {
            return true;
        }

        if (Na__NativeQem__Dot(old_normal, new_normal) < 0.0) {
            return true;
        }
    }

    return false;
}

std::vector<NaCollapseCandidate> Na__NativeQem__BuildSortedCollapseCandidates(
    const NaNativeMesh& mesh,
    const std::vector<NaEdgeRecord>& edge_data,
    const NaNativeOptions& options
)
{
    std::vector<NaCollapseCandidate> candidates;
    const int limit = std::max(options.max_candidate_edges_per_pass, 1);
    candidates.reserve(std::min(limit, static_cast<int>(edge_data.size())));

    for (const auto& edge : edge_data) {
        if (static_cast<int>(candidates.size()) >= limit) {
            break;
        }

        if (options.maintain_border_edges && edge.triangle_indices.size() != 2) {
            continue;
        }

        if (options.preserve_material_boundary_edges && edge.triangle_indices.size() > 1) {
            const int material_index = mesh.triangles[edge.triangle_indices[0]].material_index;
            bool has_boundary = false;

            for (int triangle_index : edge.triangle_indices) {
                if (mesh.triangles[triangle_index].material_index != material_index) {
                    has_boundary = true;
                    break;
                }
            }

            if (has_boundary) {
                continue;
            }
        }

        const int a = edge.a;
        const int b = edge.b;
        const auto combined_q = Na__NativeQem__AddQuadrics(
            mesh.vertices[a].quadric,
            mesh.vertices[b].quadric
        );

        const auto collapse_point = Na__NativeQem__FindBestCollapsePoint(
            combined_q,
            mesh.vertices[a].point,
            mesh.vertices[b].point
        );

        if (Na__NativeQem__CollapseWouldInvertTriangles(
            mesh.vertices,
            mesh.triangles,
            a,
            b,
            collapse_point
        )) {
            continue;
        }

        NaCollapseCandidate candidate;
        candidate.keep = a;
        candidate.remove = b;
        candidate.point = collapse_point;
        candidate.quadric = combined_q;
        candidate.error = Na__NativeQem__CalculateQuadricError(combined_q, collapse_point);
        candidates.push_back(candidate);
    }

    std::sort(candidates.begin(), candidates.end(), [](const auto& a, const auto& b) {
        return a.error < b.error;
    });

    return candidates;
}

int Na__NativeQem__CalculateBatchSize(
    int current_triangle_count,
    int target_triangles,
    int candidate_count
)
{
    const int triangles_to_remove = current_triangle_count - target_triangles;
    const int collapses_needed = std::max(static_cast<int>(std::ceil(triangles_to_remove / 2.0)), 1);
    const int candidate_percentage = std::max(static_cast<int>(std::ceil(candidate_count * 0.25)), 1);
    return std::min(collapses_needed, candidate_percentage);
}

std::vector<NaCollapseCandidate> Na__NativeQem__ChooseNonConflictingBatch(
    const std::vector<NaCollapseCandidate>& candidates,
    int batch_limit
)
{
    std::vector<NaCollapseCandidate> chosen;
    std::unordered_set<int> used_vertices;

    chosen.reserve(batch_limit);
    used_vertices.reserve(batch_limit * 2);

    for (const auto& candidate : candidates) {
        if (used_vertices.find(candidate.keep) != used_vertices.end()) {
            continue;
        }

        if (used_vertices.find(candidate.remove) != used_vertices.end()) {
            continue;
        }

        chosen.push_back(candidate);
        used_vertices.insert(candidate.keep);
        used_vertices.insert(candidate.remove);

        if (static_cast<int>(chosen.size()) >= batch_limit) {
            break;
        }
    }

    return chosen;
}

int Na__NativeQem__ApplyCollapseBatch(
    NaNativeMesh& mesh,
    const std::vector<NaCollapseCandidate>& candidates
)
{
    std::unordered_map<int, int> collapse_map;
    collapse_map.reserve(candidates.size());

    for (const auto& candidate : candidates) {
        collapse_map[candidate.remove] = candidate.keep;
        mesh.vertices[candidate.keep].point = candidate.point;
        mesh.vertices[candidate.keep].quadric = candidate.quadric;
    }

    for (auto& triangle : mesh.triangles) {
        for (int& vertex_index : triangle.vertices) {
            const auto found = collapse_map.find(vertex_index);
            if (found != collapse_map.end()) {
                vertex_index = found->second;
            }
        }
    }

    return static_cast<int>(candidates.size());
}

} // namespace

NaNativeMesh Na__NativeQemCore__SimplifyMesh(
    NaNativeMesh mesh,
    int target_triangles,
    const NaNativeOptions& options
)
{
    mesh = Na__NativeQem__CompactMesh(mesh);
    const auto start_time = std::chrono::steady_clock::now();

    int pass_index = 0;

    while (static_cast<int>(mesh.triangles.size()) > target_triangles) {
        const auto now = std::chrono::steady_clock::now();
        const double elapsed = std::chrono::duration<double>(now - start_time).count();

        if (elapsed > options.max_seconds_per_group) {
            mesh.stopped_early = true;
            break;
        }

        if (pass_index >= options.max_passes_per_group) {
            mesh.stopped_early = true;
            break;
        }

        Na__NativeQem__BuildInitialQuadrics(mesh);

        const auto edge_data = Na__NativeQem__BuildEdgeData(mesh.triangles);
        const auto candidates = Na__NativeQem__BuildSortedCollapseCandidates(mesh, edge_data, options);

        if (candidates.empty()) {
            mesh.stopped_early = true;
            break;
        }

        const int batch_size = Na__NativeQem__CalculateBatchSize(
            static_cast<int>(mesh.triangles.size()),
            target_triangles,
            static_cast<int>(candidates.size())
        );

        const auto chosen = Na__NativeQem__ChooseNonConflictingBatch(candidates, batch_size);

        if (chosen.empty()) {
            mesh.stopped_early = true;
            break;
        }

        const int collapsed = Na__NativeQem__ApplyCollapseBatch(mesh, chosen);
        mesh = Na__NativeQem__CompactMesh(mesh);

        if (collapsed <= 0) {
            mesh.stopped_early = true;
            break;
        }

        ++pass_index;
    }

    return mesh;
}

} // namespace NaMeshDecimatorNative
