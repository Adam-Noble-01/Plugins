// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - GEOMETRY HELPERS
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__Geometry__.cpp
// PURPOSE    : See the header.
//
// =============================================================================

#include "Na__PointCloudViewer__NativeEngine__Geometry__.hpp"

#include <exception>
#include <mutex>
#include <new>
#include <thread>

// -----------------------------------------------------------------------------
// REGION | Vectors
// -----------------------------------------------------------------------------

Na__V3 Na__Geo__CanonicalNormal(const Na__V3& n) {
    const double ax = std::fabs(n.x), ay = std::fabs(n.y), az = std::fabs(n.z);
    double lead = n.x;
    if (ay > ax && ay >= az) lead = n.y;
    else if (az > ax && az > ay) lead = n.z;
    return lead < 0 ? n * -1.0 : n;
}

void Na__Geo__PlaneBasis(const Na__V3& n, Na__V3& u, Na__V3& v) {
    // Least-aligned world axis -> u, then v = n x u: a fixed rule, so the same
    // normal always gets the same in-plane axes.
    const double ax = std::fabs(n.x), ay = std::fabs(n.y), az = std::fabs(n.z);
    Na__V3 helper = (ax <= ay && ax <= az) ? Na__V3(1, 0, 0) : (ay <= az ? Na__V3(0, 1, 0) : Na__V3(0, 0, 1));
    u = (helper - n * helper.Dot(n)).Normalised();
    v = n.Cross(u).Normalised();
}

double Na__Geo__LineAngleDeg(const Na__V3& a, const Na__V3& b) {
    const double c = std::min(1.0, std::fabs(a.Dot(b)));
    return std::acos(c) * 57.29577951308232;
}

// -----------------------------------------------------------------------------
// REGION | Eigen (cyclic Jacobi)
// -----------------------------------------------------------------------------

void Na__Geo__SymEigen3(const double in[9], double values[3], Na__V3 vectors[3]) {
    double a[3][3] = { { in[0], in[1], in[2] }, { in[3], in[4], in[5] }, { in[6], in[7], in[8] } };
    double v[3][3] = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } };
    for (int sweep = 0; sweep < 32; ++sweep) {
        const double off = a[0][1] * a[0][1] + a[0][2] * a[0][2] + a[1][2] * a[1][2];
        const double diag = a[0][0] * a[0][0] + a[1][1] * a[1][1] + a[2][2] * a[2][2];
        if (off <= 1e-30 * (diag + 1e-300)) break;
        for (int p = 0; p < 2; ++p) {
            for (int q = p + 1; q < 3; ++q) {
                if (std::fabs(a[p][q]) < 1e-300) continue;
                const double theta = (a[q][q] - a[p][p]) / (2.0 * a[p][q]);
                const double t = (theta >= 0 ? 1.0 : -1.0) / (std::fabs(theta) + std::sqrt(theta * theta + 1.0));
                const double c = 1.0 / std::sqrt(t * t + 1.0), s = t * c;
                for (int k = 0; k < 3; ++k) {          // A = J^T A J
                    const double akp = a[k][p], akq = a[k][q];
                    a[k][p] = c * akp - s * akq;
                    a[k][q] = s * akp + c * akq;
                }
                for (int k = 0; k < 3; ++k) {
                    const double apk = a[p][k], aqk = a[q][k];
                    a[p][k] = c * apk - s * aqk;
                    a[q][k] = s * apk + c * aqk;
                }
                for (int k = 0; k < 3; ++k) {          // V = V J
                    const double vkp = v[k][p], vkq = v[k][q];
                    v[k][p] = c * vkp - s * vkq;
                    v[k][q] = s * vkp + c * vkq;
                }
            }
        }
    }
    int order[3] = { 0, 1, 2 };
    std::sort(order, order + 3, [&](int i, int j) { return a[i][i] < a[j][j] || (a[i][i] == a[j][j] && i < j); });
    for (int r = 0; r < 3; ++r) {
        const int i = order[r];
        values[r]  = a[i][i];
        vectors[r] = Na__V3(v[0][i], v[1][i], v[2][i]).Normalised();
    }
}

// -----------------------------------------------------------------------------
// REGION | Plane accumulator
// -----------------------------------------------------------------------------

void Na__PlaneAccumulator::Add(double x, double y, double z, double w) {
    const double dx = x - m_anchor.x, dy = y - m_anchor.y, dz = z - m_anchor.z;
    m_w += w;
    m_s[0] += w * dx; m_s[1] += w * dy; m_s[2] += w * dz;
    m_ss[0] += w * dx * dx; m_ss[1] += w * dx * dy; m_ss[2] += w * dx * dz;
    m_ss[3] += w * dy * dy; m_ss[4] += w * dy * dz; m_ss[5] += w * dz * dz;
}

Na__PlaneFit Na__PlaneAccumulator::Fit() const {
    Na__PlaneFit fit;
    fit.weight = m_w;
    if (!(m_w > 0)) return fit;
    const double mx = m_s[0] / m_w, my = m_s[1] / m_w, mz = m_s[2] / m_w;
    const double cov[9] = {
        m_ss[0] / m_w - mx * mx, m_ss[1] / m_w - mx * my, m_ss[2] / m_w - mx * mz,
        m_ss[1] / m_w - mx * my, m_ss[3] / m_w - my * my, m_ss[4] / m_w - my * mz,
        m_ss[2] / m_w - mx * mz, m_ss[4] / m_w - my * mz, m_ss[5] / m_w - mz * mz };
    Na__V3 vectors[3];
    Na__Geo__SymEigen3(cov, fit.eig, vectors);
    for (double& e : fit.eig) e = std::max(0.0, e);
    fit.centre = Na__V3(mx + m_anchor.x, my + m_anchor.y, mz + m_anchor.z);
    fit.normal = Na__Geo__CanonicalNormal(vectors[0]);
    fit.valid  = true;
    return fit;
}

// -----------------------------------------------------------------------------
// REGION | Robust statistics
// -----------------------------------------------------------------------------

double Na__Stat__Median(std::vector<double>& values, double fallback) {
    if (values.empty()) return fallback;
    const size_t mid = (values.size() - 1) / 2;
    std::nth_element(values.begin(), values.begin() + mid, values.end());
    return values[mid];
}

float Na__Stat__MedianF(std::vector<float>& values, float fallback) {
    if (values.empty()) return fallback;
    const size_t mid = (values.size() - 1) / 2;
    std::nth_element(values.begin(), values.begin() + mid, values.end());
    return values[mid];
}

double Na__Stat__Percentile(std::vector<double>& values, double p, double fallback) {
    if (values.empty()) return fallback;
    const double clamped = std::min(1.0, std::max(0.0, p));
    const size_t at = static_cast<size_t>(std::floor(clamped * (values.size() - 1)));
    std::nth_element(values.begin(), values.begin() + at, values.end());
    return values[at];
}

double Na__Stat__RobustSigma(std::vector<double>& values, double fallback) {
    if (values.size() < 2) return fallback;
    const double median = Na__Stat__Median(values);
    for (double& v : values) v = std::fabs(v - median);
    return 1.4826 * Na__Stat__Median(values);
}

// -----------------------------------------------------------------------------
// REGION | Pool + parallel for
// -----------------------------------------------------------------------------

namespace {
    std::mutex       g_clean_pool_mutex;   // creation / shutdown
    std::mutex       g_clean_run_mutex;    // one parallel run at a time
    Na__ThreadPool*  g_clean_pool = nullptr;

    unsigned Na__CleanThreads() {
        const unsigned hw = std::thread::hardware_concurrency();
        // Leave a core for SketchUp's own thread and the renderer.
        return std::max(1u, std::min(32u, (hw == 0 ? 4u : hw) - (hw > 2 ? 1u : 0u)));
    }
}

Na__ThreadPool& Na__Clean__Pool() {
    std::lock_guard<std::mutex> lock(g_clean_pool_mutex);
    if (!g_clean_pool) g_clean_pool = new Na__ThreadPool(Na__CleanThreads());
    return *g_clean_pool;
}

void Na__Clean__ShutdownPool() {
    std::lock_guard<std::mutex> run(g_clean_run_mutex);
    std::lock_guard<std::mutex> lock(g_clean_pool_mutex);
    delete g_clean_pool;
    g_clean_pool = nullptr;
}

void Na__ParallelFor(int64_t n, int64_t grain, const std::atomic<bool>* cancel,
                     const std::function<void(int64_t, int64_t)>& fn) {
    if (n <= 0) return;
    Na__CheckCancel(cancel);
    grain = std::max<int64_t>(1, grain);
    Na__ThreadPool& pool = Na__Clean__Pool();
    if (n <= grain || pool.Size() <= 1) {
        fn(0, n);
        Na__CheckCancel(cancel);
        return;
    }
    std::atomic<int64_t> next(0);
    std::atomic<bool> failed(false);
    std::exception_ptr error;
    std::mutex error_mutex;
    {
        std::lock_guard<std::mutex> run(g_clean_run_mutex);
        pool.Run([&](unsigned, unsigned) {
            for (;;) {
                if (failed.load(std::memory_order_relaxed)) return;
                if (cancel && cancel->load(std::memory_order_relaxed)) return;
                const int64_t begin = next.fetch_add(grain);
                if (begin >= n) return;
                try {
                    fn(begin, std::min(n, begin + grain));
                } catch (...) {
                    std::lock_guard<std::mutex> lock(error_mutex);
                    if (!error) error = std::current_exception();
                    failed.store(true);
                    return;
                }
            }
        });
    }
    if (error) std::rethrow_exception(error);
    Na__CheckCancel(cancel);
}
