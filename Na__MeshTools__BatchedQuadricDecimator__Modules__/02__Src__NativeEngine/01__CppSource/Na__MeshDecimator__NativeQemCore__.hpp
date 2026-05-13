#pragma once

#include <array>
#include <vector>

namespace NaMeshDecimatorNative {

struct NaNativeVertex {
    std::array<double, 3> point;
    std::array<double, 10> quadric;
};

struct NaNativeTriangle {
    std::array<int, 3> vertices;
    int material_index;
};

struct NaNativeMesh {
    std::vector<NaNativeVertex> vertices;
    std::vector<NaNativeTriangle> triangles;
    bool stopped_early = false;
};

struct NaNativeOptions {
    bool maintain_border_edges = true;
    bool preserve_material_boundary_edges = true;
    double max_seconds_per_group = 10.0;
    int max_passes_per_group = 4;
    int max_candidate_edges_per_pass = 10000;
};

NaNativeMesh Na__NativeQemCore__SimplifyMesh(
    NaNativeMesh mesh,
    int target_triangles,
    const NaNativeOptions& options
);

} // namespace NaMeshDecimatorNative
