// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - GEOMETRY HELPERS
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__Geometry__.hpp
// PURPOSE    : Small numerical tools for the cleaning engine:
//                - 3x3 symmetric eigen decomposition (cyclic Jacobi)
//                - weighted plane fit (centroid + covariance in double)
//                - deterministic randomness keyed to global positions
//                - robust statistics (median, MAD, percentiles)
//                - a parallel-for over the engine's cleaning pool, with cancel
//
// WHY NO EIGEN: the engine only ever needs 3x3 symmetric eigenproblems and
//   3x3 solves. A 40-line Jacobi solver (quadratic convergence, exact for the
//   symmetric case, tested against analytic cases) covers that without
//   vendoring a 5 MB header library.
//
// DETERMINISM: every result must be identical whichever region (preview box
//   or full-cloud tile) computed it, so nothing here depends on thread timing
//   or processing order: sums run in a fixed order and randomness is seeded
//   from global cell coordinates.
//
// =============================================================================

#pragma once

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <functional>
#include <stdexcept>
#include <vector>

#include "Na__PointCloudViewer__NativeEngine__ThreadPool__.hpp"

// -----------------------------------------------------------------------------
// REGION | Vectors
// -----------------------------------------------------------------------------

struct Na__V3 {
    double x = 0, y = 0, z = 0;
    Na__V3() = default;
    Na__V3(double ax, double ay, double az) : x(ax), y(ay), z(az) {}
    Na__V3 operator+(const Na__V3& o) const { return { x + o.x, y + o.y, z + o.z }; }
    Na__V3 operator-(const Na__V3& o) const { return { x - o.x, y - o.y, z - o.z }; }
    Na__V3 operator*(double s) const { return { x * s, y * s, z * s }; }
    double Dot(const Na__V3& o) const { return x * o.x + y * o.y + z * o.z; }
    Na__V3 Cross(const Na__V3& o) const { return { y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x }; }
    double Length() const { return std::sqrt(x * x + y * y + z * z); }
    Na__V3 Normalised() const { const double l = Length(); return l > 0 ? Na__V3(x / l, y / l, z / l) : Na__V3(0, 0, 1); }
};

// Same direction every time for the same plane: flipped so the largest
// component is positive (ties: x before y before z).
Na__V3 Na__Geo__CanonicalNormal(const Na__V3& n);
// Orthonormal in-plane axes for a unit normal, deterministic.
void   Na__Geo__PlaneBasis(const Na__V3& n, Na__V3& u, Na__V3& v);
// Angle between two lines (normals up to sign), degrees 0..90.
double Na__Geo__LineAngleDeg(const Na__V3& a, const Na__V3& b);

// -----------------------------------------------------------------------------
// REGION | Eigen + plane fit
// -----------------------------------------------------------------------------

// Symmetric 3x3 (row-major a[9]). values ascending; vectors[i] belongs to values[i].
void Na__Geo__SymEigen3(const double a[9], double values[3], Na__V3 vectors[3]);

struct Na__PlaneFit {
    Na__V3 centre;
    Na__V3 normal;               // unit, canonical sign
    double eig[3] = { 0, 0, 0 }; // covariance eigenvalues ascending (normal variance first)
    double weight = 0.0;
    bool   valid = false;
};

// Accumulates weighted points (double) relative to an anchor, so far-from-origin
// coordinates cannot lose precision. Add in a fixed order for identical bits.
class Na__PlaneAccumulator {
public:
    explicit Na__PlaneAccumulator(const Na__V3& anchor) : m_anchor(anchor) {}
    void Add(double x, double y, double z, double w = 1.0);
    Na__PlaneFit Fit() const;
private:
    Na__V3 m_anchor;
    double m_w = 0, m_s[3] = { 0, 0, 0 }, m_ss[6] = { 0, 0, 0, 0, 0, 0 };
};

// -----------------------------------------------------------------------------
// REGION | Deterministic randomness + smooth steps
// -----------------------------------------------------------------------------

inline uint64_t Na__Mix64(uint64_t z) {
    z += 0x9E3779B97F4A7C15ull;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
    return z ^ (z >> 31);
}

class Na__Rng {
public:
    explicit Na__Rng(uint64_t seed) : m_state(seed) {}
    uint64_t Next() { m_state += 0x9E3779B97F4A7C15ull; return Na__Mix64(m_state); }
    uint32_t Below(uint32_t n) { return n ? static_cast<uint32_t>(Next() % n) : 0; }
private:
    uint64_t m_state;
};

inline double Na__Smoothstep(double x, double edge0, double edge1) {
    if (edge1 <= edge0) return x >= edge1 ? 1.0 : 0.0;
    const double t = std::min(1.0, std::max(0.0, (x - edge0) / (edge1 - edge0)));
    return t * t * (3.0 - 2.0 * t);
}

// -----------------------------------------------------------------------------
// REGION | Robust statistics (reorder their input)
// -----------------------------------------------------------------------------

// Lower median (deterministic for even counts). Empty -> fallback.
double Na__Stat__Median(std::vector<double>& values, double fallback = 0.0);
float  Na__Stat__MedianF(std::vector<float>& values, float fallback = 0.0f);
// Percentile p in [0, 1] by the nearest-rank (lower) rule.
double Na__Stat__Percentile(std::vector<double>& values, double p, double fallback = 0.0);
// 1.4826 * median |x - median|: the Gaussian sigma of the bulk, ignoring outliers.
double Na__Stat__RobustSigma(std::vector<double>& values, double fallback = 0.0);

// -----------------------------------------------------------------------------
// REGION | Parallel for (cleaning pool) + cancel
// -----------------------------------------------------------------------------

struct Na__Cancelled : std::runtime_error {
    Na__Cancelled() : std::runtime_error("cancelled") {}
};

// The pool the cleaning engine runs on (separate from the render pool, so a
// long clean never stalls drawing). Created on first use, destroyed by
// Na__Clean__ShutdownPool (napc_shutdown). Calls are serialised.
Na__ThreadPool& Na__Clean__Pool();
void Na__Clean__ShutdownPool();

// Runs fn(begin, end) over [0, n) in chunks of `grain`, on every worker.
// Stops early when *cancel is set and then throws Na__Cancelled; an exception
// inside fn (bad_alloc) is re-thrown on the calling thread.
void Na__ParallelFor(int64_t n, int64_t grain, const std::atomic<bool>* cancel,
                     const std::function<void(int64_t, int64_t)>& fn);

inline void Na__CheckCancel(const std::atomic<bool>* cancel) {
    if (cancel && cancel->load(std::memory_order_relaxed)) throw Na__Cancelled();
}
