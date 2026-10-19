// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - CLEANING: REFINE SURFACES
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__CleanSurface__.cpp
// PURPOSE    : Filter 02, the surface analysis it rests on, and the sparse
//              scatter test of filter 01.
//
// THE IDEA: orientation from a LARGE neighbourhood, position from a SMALL one.
//   A wall scanned with ~10 mm of range noise has no meaningful normal at
//   the scale of a few points, so each 50 mm cell judges the 150 mm block
//   around it (3 x 3 x 3 cells) to find WHICH surfaces are there and how they
//   face. Each point is then moved along its own surface's normal onto a
//   robust fit of its neighbours within 30 mm (in-plane), so steps, reveals
//   and bows wider than that survive, while scatter across the surface shrinks.
//
// PER CELL (deterministic: seeded by the cell's global coordinates):
//   1. noise width: in "thin" cells (one clean sheet) the scatter across the
//      sheet is measured from differences between in-plane nearest
//      neighbours (immune to bows, steps and tilt); each cell uses the median
//      of the thin cells around it.
//   2. orientations: one sheet -> its PCA plane; otherwise up to three planes
//      by MSAC (truncated-quadratic RANSAC), each competing with the planes
//      of the thin cells nearby: a surface's orientation is measured best
//      where it is alone, and a corner block holds too little of each wall
//      to fix it (60 mm of a wall with 10 mm of noise tilts by ~5 degrees,
//      and a tilted plane reads as two sheets). Planes within 25 degrees of
//      each other are one FAMILY (parallel sheets); others are separate
//      families (internal / external corners, reveals, sills, wall-to-floor).
//   3. sheets: the offsets of a family's points along its normal are smoothed
//      (kernel = noise width); separate modes are separate sheets.
//   4. two sheets side by side (a skirting, a frame rebate, a sash inside its
//      frame) cover complementary parts of the block: STEP, both kept and
//      refined apart. Two sheets over the SAME area are the same surface seen
//      twice: DOUBLING, a possible scan registration error, flagged and (by
//      default) left unrefined so it is never averaged into a plausible but
//      wrong middle wall. With GPS time, scan passes are compared directly,
//      which catches doubling even when the sheets overlap too much to show
//      as two modes.
//
// PER POINT:
//   - assigned to the nearest sheet; points within ~1 noise width of where
//     two orientations meet are left alone (no rounding of corners);
//   - only points within inlier_band noise widths of their surface move;
//   - a Tukey-weighted fit z = a + b u + c v over in-plane neighbours of the
//     same family (redescending: neighbours from another sheet get zero
//     weight), started at the point's own height, gives the surface under it;
//   - the point moves strength x confidence of the way there, at most
//     max_move_mm, along the family normal only (never sideways, so edges of
//     openings stay where they were).
//
// =============================================================================

#include "Na__PointCloudViewer__NativeEngine__CleanRegion__.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>

namespace {

    double Na__MsSince(std::chrono::steady_clock::time_point start) {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    }

    const double NA_FAMILY_ANGLE_DEG = 25.0;
    const double NA_THIN_RATIO       = 0.25;
    const uint32_t NA_SAMPLE_CAP     = 1024;
    const int NA_HYPOTHESES          = 40;
    const int NA_FIT_NEIGHBOURS      = 96;
    const size_t NA_BORROW_MAX       = 24;       // distinct planes lent to one cell

    inline Na__V3 Na__P(const Na__CleanWork& w, uint32_t i) {
        return Na__V3(w.xyz[size_t(i) * 3], w.xyz[size_t(i) * 3 + 1], w.xyz[size_t(i) * 3 + 2]);
    }

    inline bool Na__NoiseRemoved(const Na__CleanWork& w, uint32_t i) {
        return (w.flags[i] & (NA_CF_REMOVED_ISOLATED | NA_CF_REMOVED_CLUSTER)) != 0;
    }

    // Points of the (2r+1)^3 cells around `cell`, in canonical order, skipping noise.
    void Na__BlockPoints(const Na__CleanWork& w, uint32_t cell, int r, std::vector<uint32_t>& out) {
        out.clear();
        int64_t c[3];
        Na__Clean__CellCoords(w, cell, c);
        for (int64_t dz = -r; dz <= r; ++dz) {
            for (int64_t dy = -r; dy <= r; ++dy) {
                for (int64_t dx = -r; dx <= r; ++dx) {
                    const uint32_t nb = Na__Clean__CellAt(w, c[0] + dx, c[1] + dy, c[2] + dz);
                    if (nb == UINT32_MAX) continue;
                    for (uint32_t j = w.cell_start[nb]; j < w.cell_start[nb + 1]; ++j) {
                        if (!Na__NoiseRemoved(w, j)) out.push_back(j);
                    }
                }
            }
        }
    }

    Na__V3 Na__CellCentre(const Na__CleanWork& w, uint32_t cell) {
        int64_t c[3];
        Na__Clean__CellCoords(w, cell, c);
        return Na__V3((c[0] + 0.5) * w.fine, (c[1] + 0.5) * w.fine, (c[2] + 0.5) * w.fine);
    }

    uint64_t Na__CellSeed(const Na__CleanWork& w, uint32_t cell) {
        int64_t c[3];
        Na__Clean__CellCoords(w, cell, c);
        uint64_t h = 0x4E415043u;
        for (int a = 0; a < 3; ++a) h = Na__Mix64(h ^ static_cast<uint64_t>(c[a] + (1ll << 40)));
        return h;
    }

    // PCA plane of the given points, anchored at `anchor`.
    Na__PlaneFit Na__FitPoints(const Na__CleanWork& w, const std::vector<uint32_t>& idx, const Na__V3& anchor) {
        Na__PlaneAccumulator acc(anchor);
        for (uint32_t i : idx) acc.Add(w.xyz[size_t(i) * 3], w.xyz[size_t(i) * 3 + 1], w.xyz[size_t(i) * 3 + 2]);
        return acc.Fit();
    }

    struct Plane { Na__V3 n, c; uint32_t inliers = 0; bool borrowed = false; };
    bool Na__FindPlane(const Na__CleanWork& w, const std::vector<uint32_t>& block, const std::vector<uint32_t>& sample,
                       const std::vector<Na__V3>& scored, const std::vector<double>& base, const std::vector<Plane>& found,
                       double tau, Na__Rng& rng, const Na__V3& anchor, Plane& out);

    // Noise of a set of (u, v, z) points from differences between in-plane
    // nearest neighbours: 1.4826 x median |dz| / sqrt 2. On a real sheet this
    // is its noise; on points stacked across the plane (another surface seen
    // edge-on, a corner) it is far larger. -1 when too few pairs.
    double Na__PairSigma(const std::vector<Na__V3>& q, size_t max_points = 512) {
        if (q.size() < 10) return -1.0;
        const size_t step = std::max<size_t>(1, q.size() / max_points);
        std::vector<Na__V3> s;
        for (size_t k = 0; k < q.size(); k += step) s.push_back(q[k]);
        double ulo = 1e300, uhi = -1e300, vlo = 1e300, vhi = -1e300;
        for (const Na__V3& p : s) { ulo = std::min(ulo, p.x); uhi = std::max(uhi, p.x); vlo = std::min(vlo, p.y); vhi = std::max(vhi, p.y); }
        const double area = std::max(1e-18, (uhi - ulo) * (vhi - vlo));
        const double g = std::max(1e-9, std::sqrt(area / s.size()));
        const int gx = std::max(1, std::min(256, static_cast<int>((uhi - ulo) / g) + 1));
        const int gy = std::max(1, std::min(256, static_cast<int>((vhi - vlo) / g) + 1));
        const double gu = (uhi - ulo) / gx + 1e-12, gv = (vhi - vlo) / gy + 1e-12;
        // The points sorted by bucket (counting sort, point order inside a
        // bucket) into flat arrays: the three buckets of a row of the 3 x 3
        // neighbourhood are then one contiguous run, searched in the same
        // order as bucket by bucket (so the same neighbour wins a tie).
        const size_t buckets = static_cast<size_t>(gx) * gy;
        const uint32_t count = static_cast<uint32_t>(s.size());
        std::vector<uint32_t> start(buckets + 1, 0), of(count), at(count);
        for (uint32_t i = 0; i < count; ++i) {
            const int bx = std::min(gx - 1, static_cast<int>((s[i].x - ulo) / gu));
            const int by = std::min(gy - 1, static_cast<int>((s[i].y - vlo) / gv));
            of[i] = static_cast<uint32_t>(by) * static_cast<uint32_t>(gx) + static_cast<uint32_t>(bx);
            ++start[of[i] + 1];
        }
        for (size_t b = 0; b < buckets; ++b) start[b + 1] += start[b];
        std::vector<double> su(count), sv(count), sz(count);
        {
            std::vector<uint32_t> fill(start.begin(), start.end() - 1);
            for (uint32_t i = 0; i < count; ++i) {
                const uint32_t t = fill[of[i]]++;
                at[i] = t;
                su[t] = s[i].x; sv[t] = s[i].y; sz[t] = s[i].z;
            }
        }
        std::vector<double> diffs;
        const double reach2 = 4.0 * g * g;
        for (uint32_t i = 0; i < count; ++i) {
            const int bx = static_cast<int>(of[i] % static_cast<uint32_t>(gx)), by = static_cast<int>(of[i] / static_cast<uint32_t>(gx));
            const int x0 = std::max(0, bx - 1), x1 = std::min(gx - 1, bx + 1);
            const double ui = s[i].x, vi = s[i].y, zi = s[i].z;
            const uint32_t self = at[i];
            double best = 1e300, dz = 0.0;
            for (int yy = std::max(0, by - 1); yy <= std::min(gy - 1, by + 1); ++yy) {
                const uint32_t t0 = start[static_cast<size_t>(yy) * gx + x0], t1 = start[static_cast<size_t>(yy) * gx + x1 + 1];
                for (uint32_t t = t0; t < t1; ++t) {
                    if (t == self) continue;
                    const double du = su[t] - ui, dv = sv[t] - vi;
                    const double d2 = du * du + dv * dv;
                    if (d2 < best) { best = d2; dz = sz[t] - zi; }
                }
            }
            if (best <= reach2) diffs.push_back(std::fabs(dz));
        }
        if (diffs.size() < 8) return -1.0;
        return 1.4826 * Na__Stat__Median(diffs) / std::sqrt(2.0);
    }

    // Two Gaussians with one shared width over the SORTED offsets `o`, against
    // one Gaussian. EM runs on bins 1/32 of the spread wide, each holding its
    // count and the sums of x and x^2 (so the means and the width are exact for
    // responsibilities taken at the bin's mean), with one exp per bin through
    // the logistic form. EM usually runs its 60 rounds, so ~100 bins instead
    // of every point (and one exp instead of two) was most of the surface
    // analysis's time. Measured on 500 000 real cases against the per-point
    // EM: the same decision in all but 10, each on a threshold (separation
    // 2.4999 against 2.5001, weight 0.1500). Bins a quarter of the spread wide
    // are too coarse: on small or heavy-tailed sets EM finds another solution.
    // The likelihoods that decide are summed over every point. Results: means
    // (ma, mb), shared width s, weight pa of ma, and the BIC gain of the
    // mixture; false when there is nothing to fit.
    struct Na__Mixture { double ma = 0, mb = 0, s = 0, pa = 0.5, delta_bic = -1e300; };
    struct Na__OffsetBin { double n, s1, s2; };

    void Na__BinOffsets(const std::vector<double>& o, double mean, double h, std::vector<Na__OffsetBin>& bins) {
        bins.clear();
        const size_t m = o.size();
        const double range = o.back() - o.front();
        if (range > 2048.0 * h) h = range / 2048.0;
        h = std::max(h, 1e-300);
        size_t k = 0;
        while (k < m) {
            const double edge = o.front() + (std::floor((o[k] - o.front()) / h) + 1.0) * h;
            Na__OffsetBin b = { 0.0, 0.0, 0.0 };
            do {
                const double d = o[k] - mean;
                b.n += 1.0; b.s1 += d; b.s2 += d * d;
                ++k;
            } while (k < m && o[k] < edge);
            bins.push_back(b);
        }
    }

    // Up to 60 EM rounds over centred bins; a, b, v (shared variance), pa in/out.
    void Na__MixtureEm(const std::vector<Na__OffsetBin>& bins, double nn, double& a, double& b, double& v, double& pa) {
        const size_t nb = bins.size();
        std::vector<double> r(nb);
        double so = 0.0;
        for (const Na__OffsetBin& bin : bins) so += bin.s1;
        for (int it = 0; it < 60; ++it) {
            // responsibility of a: 1 / (1 + exp(t)), t = log((1 - pa) / pa) + ((x - a)^2 - (x - b)^2) / 2v
            const double lp = std::log((1.0 - pa) / pa);
            double sr = 0.0, sro = 0.0;
            for (size_t j = 0; j < nb; ++j) {
                const double x = bins[j].s1 / bins[j].n;
                const double t = lp + ((x - a) * (x - a) - (x - b) * (x - b)) / (2.0 * v);
                r[j] = t > 700.0 ? 0.0 : (t < -700.0 ? 1.0 : 1.0 / (1.0 + std::exp(t)));
                sr += r[j] * bins[j].n;
                sro += r[j] * bins[j].s1;
            }
            if (sr < 1.0 || nn - sr < 1.0) break;
            const double na = sro / sr, nbm = (so - sro) / (nn - sr);
            double sq = 0.0;
            for (size_t j = 0; j < nb; ++j) {
                const Na__OffsetBin& bin = bins[j];
                sq += r[j] * (bin.s2 - 2.0 * na * bin.s1 + bin.n * na * na) +
                      (1.0 - r[j]) * (bin.s2 - 2.0 * nbm * bin.s1 + bin.n * nbm * nbm);
            }
            const double nv = std::max(sq / nn, 1e-18);
            const bool still = std::fabs(na - a) + std::fabs(nbm - b) < 1e-4 * std::sqrt(nv);
            a = na; b = nbm; v = nv; pa = sr / nn;
            if (still) break;
        }
    }

    bool Na__TwoSheetMixture(const std::vector<double>& o, Na__Mixture& out) {
        const size_t m = o.size();
        if (m < 4) return false;
        const double nn = static_cast<double>(m);
        double mean = 0.0, var = 0.0;
        for (double x : o) mean += x;
        mean /= nn;
        for (double x : o) var += (x - mean) * (x - mean);
        var = std::max(var / nn, 1e-18);

        std::vector<Na__OffsetBin> bins;
        double a = o[m / 4] - mean, b = o[m * 3 / 4] - mean, v = var / 4.0, pa = 0.5;
        Na__BinOffsets(o, mean, std::sqrt(var) / 32.0, bins);
        Na__MixtureEm(bins, nn, a, b, v, pa);
        if (!(pa > 0.0 && pa < 1.0)) return false;

        // log likelihoods over every point (log-sum-exp for the mixture)
        const double two_pi = 2.0 * 3.141592653589793;
        const double c1 = -0.5 * std::log(two_pi * var), c2 = -0.5 * std::log(two_pi * v);
        const double la = std::log(pa), lb = std::log(1.0 - pa);
        double l1 = 0.0, l2 = 0.0;
        for (double x0 : o) {
            const double x = x0 - mean;
            l1 += c1 - 0.5 * x * x / var;
            const double ea = la - 0.5 * (x - a) * (x - a) / v, eb = lb - 0.5 * (x - b) * (x - b) / v;
            const double top = std::max(ea, eb);
            l2 += c2 + top + std::log(std::exp(ea - top) + std::exp(eb - top));
        }
        out.ma = a + mean;
        out.mb = b + mean;
        out.s = std::sqrt(v);
        out.pa = pa;
        out.delta_bic = 2.0 * (l2 - l1) - 2.0 * std::log(nn);
        return true;
    }

    // --- pass 1: thin test + noise width from in-plane neighbour differences ---------------

    void Na__Pass1(Na__CleanWork& w, uint32_t slot, std::vector<uint32_t>& pts) {
        Na__CellSurface& cs = w.surfaces[slot];
        cs.pass1 = 1;
        const uint32_t cell = w.slot_cell[slot];
        Na__BlockPoints(w, cell, 1, pts);
        if (pts.size() < 12) return;
        const Na__V3 centre = Na__CellCentre(w, cell);
        const Na__PlaneFit fit = Na__FitPoints(w, pts, centre);
        if (!fit.valid || fit.eig[1] < (0.25 * w.fine) * (0.25 * w.fine)) return;
        cs.t_thick = static_cast<float>(std::sqrt(std::max(0.0, fit.eig[0])));
        if (fit.eig[0] > NA_THIN_RATIO * fit.eig[1]) return;
        // A corner can look flat to PCA (its flattest direction is the diagonal).
        // One sheet only if a robust plane agrees: same orientation, 80 % inliers.
        {
            std::vector<uint32_t> sample;
            const size_t step = std::max<size_t>(1, pts.size() / NA_SAMPLE_CAP);
            for (size_t s = 0; s < pts.size(); s += step) sample.push_back(pts[s]);
            Na__Rng rng(Na__CellSeed(w, cell) ^ 0x7417u);
            Plane robust;
            const double tau = 2.5 * std::sqrt(fit.eig[0]);
            const std::vector<double> base(sample.size(), 0.36 * tau * tau);
            std::vector<Na__V3> scored;
            scored.reserve(sample.size());
            for (uint32_t i : sample) scored.push_back(Na__P(w, i));
            if (!Na__FindPlane(w, pts, sample, scored, base, std::vector<Plane>(), tau, rng, centre, robust)) return;
            cs.t_angle = static_cast<float>(Na__Geo__LineAngleDeg(robust.n, fit.normal));
            cs.t_share = static_cast<float>(static_cast<double>(robust.inliers) / pts.size());
            if (Na__Geo__LineAngleDeg(robust.n, fit.normal) > 10.0 || robust.inliers < 0.8 * pts.size()) return;
        }
        cs.flags |= NA_CELL_THIN;

        // noise from in-plane neighbour differences in the PCA frame
        Na__V3 u, v;
        Na__Geo__PlaneBasis(fit.normal, u, v);
        std::vector<Na__V3> q;
        q.reserve(pts.size());
        for (uint32_t i : pts) {
            const Na__V3 d = Na__P(w, i) - fit.centre;
            q.push_back(Na__V3(d.Dot(u), d.Dot(v), d.Dot(fit.normal)));
        }
        const double pair_sigma = Na__PairSigma(q);
        cs.t_pair = static_cast<float>(pair_sigma);
        if (pair_sigma <= 0) { cs.flags &= static_cast<uint8_t>(~NA_CELL_THIN); return; }
        // One sheet's thickness IS its noise. A corner, a step or a return seen
        // edge-on is thicker than the noise between neighbouring points: not thin.
        if (std::sqrt(fit.eig[0]) > 1.3 * pair_sigma + 0.05 * w.units_per_mm) { cs.flags &= static_cast<uint8_t>(~NA_CELL_THIN); return; }
        // One sheet, not a staircase of narrow strips that the noise blurs into
        // one tilted plane (a frame and sash band, the edge of a sill): each
        // half of the block, split either way across, must face the way the
        // whole block does, within 2 degrees + 3 x its own expected error.
        {
            Na__PlaneAccumulator half[4] = { Na__PlaneAccumulator(centre), Na__PlaneAccumulator(centre),
                                             Na__PlaneAccumulator(centre), Na__PlaneAccumulator(centre) };
            for (size_t k = 0; k < pts.size(); ++k) {
                const Na__V3 p = Na__P(w, pts[k]);
                half[q[k].x < 0.0 ? 0 : 1].Add(p.x, p.y, p.z);
                half[q[k].y < 0.0 ? 2 : 3].Add(p.x, p.y, p.z);
            }
            for (int h = 0; h < 4; ++h) {
                const Na__PlaneFit hf = half[h].Fit();
                if (!hf.valid || hf.weight < 12 || hf.eig[1] <= 0.0) continue;
                const double err = std::sqrt(pair_sigma * pair_sigma / (hf.weight * hf.eig[1]));   // radians
                if (Na__Geo__LineAngleDeg(hf.normal, fit.normal) > 2.0 + 3.0 * err * 57.29577951308232) {
                    cs.flags &= static_cast<uint8_t>(~NA_CELL_THIN);
                    return;
                }
            }
        }
        cs.pair_sigma = static_cast<float>(pair_sigma);
        const Na__V3 tn = Na__Geo__CanonicalNormal(fit.normal);
        cs.thin_n[0] = static_cast<float>(tn.x); cs.thin_n[1] = static_cast<float>(tn.y); cs.thin_n[2] = static_cast<float>(tn.z);
        cs.thin_c[0] = static_cast<float>(fit.centre.x); cs.thin_c[1] = static_cast<float>(fit.centre.y); cs.thin_c[2] = static_cast<float>(fit.centre.z);
        cs.thin = 1;
    }

    // --- pass 3: orientations, sheets, step or doubling -----------------------------------

    // In-plane spread (std of the narrower direction) of the points within tau of a plane.
    double Na__InPlaneMinorStd(const Na__CleanWork& w, const std::vector<uint32_t>& points, const Na__V3& n, const Na__V3& c, double tau) {
        Na__V3 u, v;
        Na__Geo__PlaneBasis(n, u, v);
        double s = 0, su = 0, sv = 0, suu = 0, suv = 0, svv = 0;
        for (uint32_t i : points) {
            const Na__V3 d = Na__P(w, i) - c;
            if (std::fabs(d.Dot(n)) > tau) continue;
            const double a = d.Dot(u), b = d.Dot(v);
            s += 1; su += a; sv += b; suu += a * a; suv += a * b; svv += b * b;
        }
        if (s < 3) return 0.0;
        const double cuu = suu / s - (su / s) * (su / s), cvv = svv / s - (sv / s) * (sv / s), cuv = suv / s - (su / s) * (sv / s);
        const double tr = cuu + cvv, det = cuu * cvv - cuv * cuv;
        const double minor = 0.5 * tr - std::sqrt(std::max(0.0, 0.25 * tr * tr - det));
        return std::sqrt(std::max(0.0, minor));
    }

    // Truncated squared distance (band 0.6 tau = 1.5 noise widths) of every
    // `scored` point to the nearest plane found so far.
    void Na__BaseCost(const std::vector<Na__V3>& scored, const std::vector<Plane>& found,
                      double tau, std::vector<double>& base) {
        base.assign(scored.size(), 0.36 * tau * tau);
        for (size_t k = 0; k < scored.size(); ++k) {
            const Na__V3& p = scored[k];
            for (const Plane& f : found) {
                const double r = f.n.Dot(p - f.c);
                base[k] = std::min(base[k], r * r);
            }
        }
    }

    // MSAC cost of the planes found so far plus this one, over `scored`.
    double Na__JointCost(const std::vector<Na__V3>& scored, const std::vector<double>& base,
                         const Na__V3& n, const Na__V3& c, double stop = 1e300) {
        double s = 0.0;
        for (size_t k = 0; k < scored.size(); ++k) {
            const double r = n.Dot(scored[k] - c);
            s += std::min(base[k], r * r);
            if (s >= stop) break;
        }
        return s;
    }

    // Is p nearer to (n, c), at distance r, than to every plane found so far?
    bool Na__NearerThanFound(const std::vector<Plane>& found, const Na__V3& p, double r) {
        for (const Plane& f : found) if (std::fabs(f.n.Dot(p - f.c)) <= r) return false;
        return true;
    }

    // Block points within tau of the plane and nearer to it than to any plane
    // found so far: what it explains that nothing else does.
    uint32_t Na__ExclusiveInliers(const Na__CleanWork& w, const std::vector<uint32_t>& block, const std::vector<Plane>& found,
                                  const Na__V3& n, const Na__V3& c, double tau) {
        uint32_t count = 0;
        for (uint32_t i : block) {
            const Na__V3 p = Na__P(w, i);
            const double r = std::fabs(n.Dot(p - c));
            if (r <= tau && Na__NearerThanFound(found, p, r)) ++count;
        }
        return count;
    }

    // MSAC: hypotheses through points of `sample` (what no plane explains yet),
    // each scored over `scored` (a sample of the whole block) TOGETHER with the
    // planes already found (`base`), with a tight band (0.6 tau = 1.5 noise
    // widths, so a true wall beats a compromise tilted across a corner). The
    // next plane is the one that best explains the BLOCK given the others,
    // not the best plane through the leftovers: a strip of a perpendicular
    // frame left over after its jamb, seen edge-on, fits any plane through it.
    // Then two PCA refinements over the block points within 0.8 tau that are
    // nearer to it than to the planes found; inliers counted the same way
    // within tau.
    bool Na__FindPlane(const Na__CleanWork& w, const std::vector<uint32_t>& block, const std::vector<uint32_t>& sample,
                       const std::vector<Na__V3>& scored, const std::vector<double>& base, const std::vector<Plane>& found,
                       double tau, Na__Rng& rng, const Na__V3& anchor, Plane& out) {
        if (sample.size() < 3) return false;
        double best_score = 1e300;
        Na__V3 best_n, best_c;
        bool have = false;
        for (int h = 0; h < NA_HYPOTHESES; ++h) {
            const uint32_t a = sample[rng.Below(static_cast<uint32_t>(sample.size()))];
            const uint32_t b = sample[rng.Below(static_cast<uint32_t>(sample.size()))];
            const uint32_t c = sample[rng.Below(static_cast<uint32_t>(sample.size()))];
            if (a == b || b == c || a == c) continue;
            const Na__V3 pa = Na__P(w, a), pb = Na__P(w, b), pc = Na__P(w, c);
            const Na__V3 cross = (pb - pa).Cross(pc - pa);
            const double len = cross.Length();
            if (len < 1e-12 * std::max(1.0, (pb - pa).Length() * (pc - pa).Length()) || len == 0.0) continue;
            const Na__V3 n = cross * (1.0 / len);
            const double score = Na__JointCost(scored, base, n, pa, best_score);
            if (score < best_score) { best_score = score; best_n = n; best_c = pa; have = true; }
        }
        if (!have) return false;
        Na__V3 n = best_n, c = best_c;
        std::vector<uint32_t> in;
        for (int round = 0; round < 2; ++round) {
            in.clear();
            for (uint32_t i : block) {
                const Na__V3 p = Na__P(w, i);
                const double r = std::fabs(n.Dot(p - c));
                if (r <= 0.8 * tau && Na__NearerThanFound(found, p, r)) in.push_back(i);
            }
            if (in.size() < 3) return false;
            const Na__PlaneFit fit = Na__FitPoints(w, in, anchor);
            if (!fit.valid) return false;
            n = fit.normal;
            c = fit.centre;
        }
        out.n = Na__Geo__CanonicalNormal(n);
        out.c = c;
        out.inliers = Na__ExclusiveInliers(w, block, found, n, c, tau);
        return true;
    }

    // Neighbour offsets within NA_SURFACE_BORROW_REACH, nearest first (then z, y, x).
    const std::vector<std::array<int, 3>>& Na__BorrowOffsets() {
        static const std::vector<std::array<int, 3>> offsets = [] {
            std::vector<std::array<int, 3>> o;
            const int r = NA_SURFACE_BORROW_REACH;
            for (int dz = -r; dz <= r; ++dz) for (int dy = -r; dy <= r; ++dy) for (int dx = -r; dx <= r; ++dx) {
                if (dx || dy || dz) o.push_back({ { dx, dy, dz } });
            }
            std::stable_sort(o.begin(), o.end(), [](const std::array<int, 3>& a, const std::array<int, 3>& b) {
                return a[0] * a[0] + a[1] * a[1] + a[2] * a[2] < b[0] * b[0] + b[1] * b[1] + b[2] * b[2];
            });
            return o;
        }();
        return offsets;
    }

    // The planes of the thin cells nearby that pass through this block, nearest
    // cell first, near-duplicates (within 3 degrees and half a noise width at
    // the cell) dropped.
    void Na__BorrowPlanes(const Na__CleanWork& w, uint32_t cell, const Na__V3& anchor, double sigma, double tau, std::vector<Plane>& out) {
        out.clear();
        int64_t c[3];
        Na__Clean__CellCoords(w, cell, c);
        const double crosses = 1.5 * std::sqrt(3.0) * w.fine + tau;
        for (const std::array<int, 3>& d : Na__BorrowOffsets()) {
            const uint32_t nb = Na__Clean__CellAt(w, c[0] + d[0], c[1] + d[1], c[2] + d[2]);
            if (nb == UINT32_MAX || w.cell_slot[nb] == UINT32_MAX) continue;
            const Na__CellSurface& o = w.surfaces[w.cell_slot[nb]];
            if (!o.thin) continue;
            const Na__V3 n(o.thin_n[0], o.thin_n[1], o.thin_n[2]), pc(o.thin_c[0], o.thin_c[1], o.thin_c[2]);
            const double at = n.Dot(anchor - pc);
            if (std::fabs(at) > crosses) continue;
            bool duplicate = false;
            for (const Plane& b : out) {
                if (Na__Geo__LineAngleDeg(b.n, n) < 3.0 && std::fabs(b.n.Dot(anchor - b.c) - at) < 0.5 * sigma) { duplicate = true; break; }
            }
            if (duplicate) continue;
            Plane pl;
            pl.n = n;
            pl.c = pc;
            pl.borrowed = true;
            out.push_back(pl);
            if (out.size() >= NA_BORROW_MAX) break;
        }
    }

    // The borrowed plane (re-centred on these points: a bowed wall drifts a few
    // mm over a block) that explains `sample` best, unless a surface found
    // already has it (same orientation, meeting it in the block), or the
    // block's own plane does clearly better (a surface no thin cell sees: a
    // sill, a reveal, the top of a skirting).
    bool Na__BestBorrowed(const Na__CleanWork& w, const std::vector<Plane>& borrowed, const std::vector<Plane>& found,
                          const std::vector<uint32_t>& block, const std::vector<Na__V3>& scored, const std::vector<double>& base,
                          double tau, const Na__V3& anchor, const Plane* own, Plane& out) {
        double best = 1e300;
        int best_k = -1;
        Na__V3 best_c;
        for (size_t k = 0; k < borrowed.size(); ++k) {
            const Plane& b = borrowed[k];
            bool known = false;
            for (const Plane& f : found) {
                if (Na__Geo__LineAngleDeg(f.n, b.n) < NA_FAMILY_ANGLE_DEG && std::fabs(f.n.Dot(anchor - f.c) - b.n.Dot(anchor - b.c)) < tau) { known = true; break; }
            }
            if (known) continue;
            Na__V3 c = b.c;
            for (int round = 0; round < 2; ++round) {
                double sr = 0.0, cnt = 0.0;
                for (size_t j = 0; j < scored.size(); ++j) {
                    const double r = b.n.Dot(scored[j] - c);
                    if (std::fabs(r) <= 0.6 * tau && r * r < base[j]) { sr += r; cnt += 1.0; }
                }
                if (cnt < 3.0) break;
                c = c + b.n * (sr / cnt);
            }
            const double cost = Na__JointCost(scored, base, b.n, c);
            if (cost < best) { best = cost; best_k = static_cast<int>(k); best_c = c; }
        }
        if (best_k < 0) return false;
        if (own && best > 1.1 * Na__JointCost(scored, base, own->n, own->c)) return false;
        out = borrowed[static_cast<size_t>(best_k)];
        out.c = best_c;
        out.inliers = Na__ExclusiveInliers(w, block, found, out.n, out.c, tau);
        return true;
    }

    // Nearest sheet of any family: returns the family, fills the signed residual
    // (and the sheet index when asked).
    int Na__NearestSheet(const Na__CellSurface& cs, const Na__V3& p, double& residual, double& second_family_abs,
                         int* sheet_out = nullptr) {
        int best = -1;
        double best_abs = 1e300;
        double family_best[3] = { 1e300, 1e300, 1e300 };
        double family_res[3] = { 0, 0, 0 };
        int family_sheet[3] = { 0, 0, 0 };
        for (int f = 0; f < cs.families; ++f) {
            const Na__SurfaceFamily& fam = cs.family[f];
            const double o = (p.x - fam.c[0]) * fam.n[0] + (p.y - fam.c[1]) * fam.n[1] + (p.z - fam.c[2]) * fam.n[2];
            for (int s = 0; s < fam.sheets; ++s) {
                const double r = o - fam.sheet[s];
                if (std::fabs(r) < family_best[f]) { family_best[f] = std::fabs(r); family_res[f] = r; family_sheet[f] = s; }
            }
            if (family_best[f] < best_abs) { best_abs = family_best[f]; best = f; }
        }
        second_family_abs = 1e300;
        for (int f = 0; f < cs.families; ++f) if (f != best) second_family_abs = std::min(second_family_abs, family_best[f]);
        residual = best >= 0 ? family_res[best] : 0.0;
        if (sheet_out) *sheet_out = best >= 0 ? family_sheet[best] : -1;
        return best;
    }

    void Na__Pass3(Na__CleanWork& w, uint32_t slot, std::vector<uint32_t>& pts) {
        Na__CellSurface& cs = w.surfaces[slot];
        const Na__CleanParams& p = w.params;
        const uint32_t cell = w.slot_cell[slot];
        cs.computed = 1;
        cs.families = 0;
        Na__BlockPoints(w, cell, 1, pts);
        const uint32_t N = static_cast<uint32_t>(pts.size());
        if (N < 12) { cs.flags |= NA_CELL_ROUGH; return; }
        const double sigma = cs.sigma;
        const double tau = 2.5 * sigma;
        const Na__V3 anchor = Na__CellCentre(w, cell);
        Na__Rng rng(Na__CellSeed(w, cell));

        // --- planes ------------------------------------------------------------------------
        std::vector<Plane> borrowed;
        Na__BorrowPlanes(w, cell, anchor, sigma, tau, borrowed);
        cs.lent = static_cast<uint8_t>(std::min<size_t>(255, borrowed.size()));
        std::vector<Plane> planes;
        std::vector<uint32_t> remaining = pts, sample;
        std::vector<Na__V3> scored;
        {
            const size_t step = std::max<size_t>(1, pts.size() / NA_SAMPLE_CAP);
            for (size_t s = 0; s < pts.size(); s += step) scored.push_back(Na__P(w, pts[s]));
        }
        std::vector<double> base;
        for (int iter = 0; iter < 3; ++iter) {
            // hypotheses come from what is left, but a plane is judged on the whole
            // block (exclusive inliers), so a few leftovers are enough to start from
            if (iter > 0 && remaining.size() < std::max<size_t>(12, static_cast<size_t>(0.05 * N))) break;
            Na__BaseCost(scored, planes, tau, base);
            Plane plane;
            bool ok = false;
            if (iter == 0 && (cs.flags & NA_CELL_THIN)) {
                const Na__PlaneFit fit = Na__FitPoints(w, remaining, anchor);
                if (fit.valid) {
                    plane.n = fit.normal;
                    plane.c = fit.centre;
                    plane.inliers = Na__ExclusiveInliers(w, pts, planes, plane.n, plane.c, tau);
                    ok = true;
                }
            } else {
                sample.clear();
                const size_t step = std::max<size_t>(1, remaining.size() / NA_SAMPLE_CAP);
                for (size_t s = 0; s < remaining.size(); s += step) sample.push_back(remaining[s]);
                ok = Na__FindPlane(w, pts, sample, scored, base, planes, tau, rng, anchor, plane);
                Plane lent;
                if (!borrowed.empty() && Na__BestBorrowed(w, borrowed, planes, pts, scored, base, tau, anchor, ok ? &plane : nullptr, lent)) {
                    plane = lent;
                    ok = true;
                }
            }
            if (!ok || plane.inliers < std::max<uint32_t>(10, static_cast<uint32_t>(0.10 * N))) break;
            std::vector<uint32_t> rest;
            for (uint32_t i : remaining) if (std::fabs(plane.n.Dot(Na__P(w, i) - plane.c)) > tau) rest.push_back(i);
            remaining.swap(rest);
            // A surface must be a surface: spread at least ~50 mm both ways in the
            // block (judged on every block point near it, so a wall that enters a
            // corner block only partly still counts). A pipe, a rail or a sliver
            // of an edge is not fitted as a plane (it would be flattened).
            if (Na__InPlaneMinorStd(w, pts, plane.n, plane.c, tau) < 0.1 * 3.0 * w.fine) continue;
            planes.push_back(plane);
        }
        cs.planes = static_cast<uint8_t>(planes.size());
        if (planes.empty()) { cs.flags |= NA_CELL_ROUGH; return; }

        // Joint refinement: each point belongs to its NEAREST plane, and each
        // plane is refitted on its own points only, so the points of one wall
        // near a corner never tilt the other wall's plane. A borrowed plane
        // keeps its orientation (measured over a whole block of that surface)
        // and is only moved onto its points.
        if (planes.size() > 1) {
            for (int round = 0; round < 2; ++round) {
                std::vector<Na__PlaneAccumulator> acc(planes.size(), Na__PlaneAccumulator(anchor));
                std::vector<double> shift(planes.size(), 0.0), shift_n(planes.size(), 0.0);
                for (uint32_t i : pts) {
                    const Na__V3 q = Na__P(w, i);
                    size_t best = 0;
                    double best_r = 1e300, best_s = 0.0;
                    for (size_t k = 0; k < planes.size(); ++k) {
                        const double s = planes[k].n.Dot(q - planes[k].c);
                        if (std::fabs(s) < best_r) { best_r = std::fabs(s); best = k; best_s = s; }
                    }
                    if (best_r > tau) continue;
                    if (planes[best].borrowed) { shift[best] += best_s; shift_n[best] += 1.0; }
                    else acc[best].Add(q.x, q.y, q.z);
                }
                for (size_t k = 0; k < planes.size(); ++k) {
                    if (planes[k].borrowed) {
                        if (shift_n[k] >= 10) planes[k].c = planes[k].c + planes[k].n * (shift[k] / shift_n[k]);
                        continue;
                    }
                    const Na__PlaneFit fit = acc[k].Fit();
                    if (fit.valid && fit.weight >= 10) { planes[k].n = Na__Geo__CanonicalNormal(fit.normal); planes[k].c = fit.centre; }
                }
            }
        }

        // --- families (orientations) and their sheets ----------------------------------------
        for (const Plane& pl : planes) {
            int fam = -1;
            for (int f = 0; f < cs.families; ++f) {
                const Na__V3 fn(cs.family[f].n[0], cs.family[f].n[1], cs.family[f].n[2]);
                if (Na__Geo__LineAngleDeg(fn, pl.n) < NA_FAMILY_ANGLE_DEG) { fam = f; break; }
            }
            if (fam < 0) {
                if (cs.families >= 3) continue;
                fam = cs.families++;
                Na__SurfaceFamily& sf = cs.family[fam];
                sf = Na__SurfaceFamily();
                for (int a = 0; a < 3; ++a) {
                    sf.n[a] = static_cast<float>(a == 0 ? pl.n.x : (a == 1 ? pl.n.y : pl.n.z));
                    sf.c[a] = static_cast<float>(a == 0 ? pl.c.x : (a == 1 ? pl.c.y : pl.c.z));
                }
                Na__V3 u, v;
                Na__Geo__PlaneBasis(pl.n, u, v);
                sf.u[0] = static_cast<float>(u.x); sf.u[1] = static_cast<float>(u.y); sf.u[2] = static_cast<float>(u.z);
                sf.v[0] = static_cast<float>(v.x); sf.v[1] = static_cast<float>(v.y); sf.v[2] = static_cast<float>(v.z);
                sf.sheets = 1;
                sf.sheet[0] = 0.0f;
                if (pl.borrowed) sf.flags |= NA_FAM_BORROWED;
            } else {
                Na__SurfaceFamily& sf = cs.family[fam];
                if (sf.sheets < 3) {
                    const Na__V3 fn(sf.n[0], sf.n[1], sf.n[2]);
                    sf.sheet[sf.sheets++] = static_cast<float>(fn.Dot(pl.c - Na__V3(sf.c[0], sf.c[1], sf.c[2])));
                }
            }
        }

        // Assign every block point to the nearest sheet; refine sheets per family by
        // the modes of its offsets.
        std::vector<int8_t> family_of(N, -1);
        std::vector<double> offset_of(N, 0.0);
        for (uint32_t k = 0; k < N; ++k) {
            double r, second;
            const int f = Na__NearestSheet(cs, Na__P(w, pts[k]), r, second);
            family_of[k] = static_cast<int8_t>(f);
            const Na__SurfaceFamily& sf = cs.family[f];
            const Na__V3 d = Na__P(w, pts[k]) - Na__V3(sf.c[0], sf.c[1], sf.c[2]);
            offset_of[k] = d.Dot(Na__V3(sf.n[0], sf.n[1], sf.n[2]));
        }
        uint32_t explained = 0;
        const double pass_disagree = p.pass_disagree_mm * w.units_per_mm;
        for (int f = 0; f < cs.families; ++f) {
            Na__SurfaceFamily& sf = cs.family[f];
            std::vector<double> offs;
            std::vector<uint32_t> members;
            for (uint32_t k = 0; k < N; ++k) if (family_of[k] == f) { offs.push_back(offset_of[k]); members.push_back(k); }
            sf.members = static_cast<uint32_t>(members.size());
            if (offs.size() < 8) { sf.conf = 0.0f; continue; }

            // modes: histogram (bin sigma/2) smoothed by a Gaussian of width sigma
            double lo = *std::min_element(offs.begin(), offs.end()), hi = *std::max_element(offs.begin(), offs.end());
            const double bin = std::max(1e-9, sigma * 0.5);
            int bins = static_cast<int>((hi - lo) / bin) + 1;
            if (bins > 600) { lo = -150 * bin; hi = 150 * bin; bins = 301; }
            std::vector<double> hist(static_cast<size_t>(bins), 0.0), smooth(static_cast<size_t>(bins), 0.0);
            for (double o : offs) {
                const int b = static_cast<int>((o - lo) / bin);
                if (b >= 0 && b < bins) hist[static_cast<size_t>(b)] += 1.0;
            }
            for (int b = 0; b < bins; ++b) {
                double acc = 0.0;
                for (int d = -6; d <= 6; ++d) {
                    const int bb = b + d;
                    if (bb < 0 || bb >= bins) continue;
                    acc += hist[static_cast<size_t>(bb)] * std::exp(-0.5 * (d * 0.5) * (d * 0.5));
                }
                smooth[static_cast<size_t>(b)] = acc;
            }
            struct Mode { double at; double mass; };
            std::vector<Mode> modes;
            for (int b = 0; b < bins; ++b) {
                const double here = smooth[static_cast<size_t>(b)];
                const double left = b > 0 ? smooth[static_cast<size_t>(b - 1)] : -1.0;
                const double right = b + 1 < bins ? smooth[static_cast<size_t>(b + 1)] : -1.0;
                if (here > left && here >= right) {
                    const double at = lo + (b + 0.5) * bin;
                    double mass = 0.0;
                    for (double o : offs) if (std::fabs(o - at) <= 1.5 * sigma) mass += 1.0;
                    modes.push_back({ at, mass });
                }
            }
            std::sort(modes.begin(), modes.end(), [](const Mode& a, const Mode& b) { return a.mass > b.mass || (a.mass == b.mass && a.at < b.at); });
            std::vector<double> sheets;
            const double min_mass = std::max(8.0, 0.12 * offs.size());
            for (const Mode& m : modes) {
                if (m.mass < min_mass || sheets.size() >= 3) continue;
                bool far = true;
                for (double s : sheets) if (std::fabs(s - m.at) < 2.0 * sigma) far = false;
                if (far) sheets.push_back(m.at);
            }
            if (sheets.empty()) sheets.push_back(Na__Stat__Median(offs));

            // Two sheets closer than the smoothing can show? Interleaved scan
            // passes inflate the measured noise width (in-plane neighbours come
            // from both sheets), and the smoothing then merges them. A two-
            // component Gaussian mixture with a shared width does not depend on
            // that estimate: accepted only when it is clearly better (BIC by 10),
            // the sheets are at least 2.5 of their own widths apart, and neither
            // holds less than 15 % of the points (a single noisy sheet, even
            // heavy-tailed, never passes all three).
            double sheet_sigma = sigma;
            if (sheets.size() == 1 && offs.size() >= 40) {
                std::vector<double> sorted = offs;
                std::sort(sorted.begin(), sorted.end());
                const size_t cut = sorted.size() / 100;
                const std::vector<double> o(sorted.begin() + cut, sorted.end() - cut);   // central 98 %
                Na__Mixture mix;
                if (Na__TwoSheetMixture(o, mix) && mix.delta_bic > 10.0 && std::fabs(mix.ma - mix.mb) >= 2.5 * mix.s &&
                    std::min(mix.pa, 1.0 - mix.pa) >= 0.15) {
                    sheets = mix.pa >= 0.5 ? std::vector<double>{ mix.ma, mix.mb } : std::vector<double>{ mix.mb, mix.ma };
                    sheet_sigma = mix.s;
                    sf.sigma = static_cast<float>(mix.s);
                }
            }

            // A second sheet must BE a sheet: a plane parallel to the family. A
            // perpendicular surface the orientation search did not separate (a
            // reveal seen from its wall) also spreads along the normal, and must
            // never be mistaken for a parallel step or a doubled pass.
            // Each sheet must be locally smooth: neighbouring points within it
            // (in-plane nearest neighbours) differ only by its noise. Points of
            // a perpendicular surface or a corner projected onto this plane stack
            // across it, and their neighbours differ by tens of millimetres.
            if (sheets.size() >= 2) {
                const Na__V3 fn(sf.n[0], sf.n[1], sf.n[2]), fu(sf.u[0], sf.u[1], sf.u[2]), fv(sf.v[0], sf.v[1], sf.v[2]);
                const Na__V3 fc(sf.c[0], sf.c[1], sf.c[2]);
                bool parallel_sheet = true;
                for (int s = 0; s < 2 && parallel_sheet; ++s) {
                    std::vector<Na__V3> uvz;
                    for (uint32_t k : members) {
                        const double o = offset_of[k];
                        if (std::fabs(o - sheets[s]) >= std::fabs(o - sheets[1 - s]) || std::fabs(o - sheets[s]) > 2.0 * sheet_sigma) continue;
                        const Na__V3 d = Na__P(w, pts[k]) - fc;
                        uvz.push_back(Na__V3(d.Dot(fu), d.Dot(fv), o));
                    }
                    const double ps = Na__PairSigma(uvz);
                    parallel_sheet = uvz.size() >= 15 && ps > 0 && ps <= 1.5 * sheet_sigma;
                }
                if (!parallel_sheet) {
                    sheets.resize(1);
                    sf.sigma = 0.0f;
                    sheet_sigma = sigma;
                }
            }

            // Two sheets: side by side (a step) or over each other (doubling)?
            // A doubled surface is the same surface twice: each sheet covers
            // the whole footprint, so almost every small in-plane cell holds
            // points of both. A step's sheets cover complementary areas
            // (whatever their shape: bands, nested L's round a window frame),
            // so only the cells along their common edge hold both.
            if (sheets.size() >= 2) {
                const double a_at = sheets[0], b_at = sheets[1];
                const Na__V3 u(sf.u[0], sf.u[1], sf.u[2]), v(sf.v[0], sf.v[1], sf.v[2]), c(sf.c[0], sf.c[1], sf.c[2]);
                struct UV { double u, v; int which; };
                std::vector<UV> uv;
                double ulo = 1e300, uhi = -1e300, vlo = 1e300, vhi = -1e300;
                double box[2][4] = { { 1e300, -1e300, 1e300, -1e300 }, { 1e300, -1e300, 1e300, -1e300 } };
                double cnt[2] = { 0, 0 };
                // Only each sheet's core (within 0.75 sigma of it) takes part: the
                // noise tail of one sheet reaching into the other's band would
                // otherwise sprinkle "both" over every cell of a real step.
                for (uint32_t k : members) {
                    const double o = offset_of[k];
                    const int which = std::fabs(o - a_at) <= 0.75 * sheet_sigma ? 0 : (std::fabs(o - b_at) <= 0.75 * sheet_sigma ? 1 : -1);
                    if (which < 0) continue;
                    const Na__V3 d = Na__P(w, pts[k]) - c;
                    UV item = { d.Dot(u), d.Dot(v), which };
                    uv.push_back(item);
                    ulo = std::min(ulo, item.u); uhi = std::max(uhi, item.u); vlo = std::min(vlo, item.v); vhi = std::max(vhi, item.v);
                    box[which][0] = std::min(box[which][0], item.u); box[which][1] = std::max(box[which][1], item.u);
                    box[which][2] = std::min(box[which][2], item.v); box[which][3] = std::max(box[which][3], item.v);
                    cnt[which] += 1.0;
                }
                bool overlapping = false;
                if (cnt[0] >= 8 && cnt[1] >= 8) {
                    // cell = 2.5 x the sparser sheet's mean spacing (about 6 of its points per cell)
                    double spacing = 0.0;
                    for (int s = 0; s < 2; ++s) {
                        const double area = std::max(1e-12, (box[s][1] - box[s][0]) * (box[s][3] - box[s][2]));
                        spacing = std::max(spacing, std::sqrt(area / cnt[s]));
                    }
                    const double g = std::max(2.5 * spacing, 1e-9);
                    const int gx = std::max(1, std::min(64, static_cast<int>((uhi - ulo) / g) + 1));
                    const int gy = std::max(1, std::min(64, static_cast<int>((vhi - vlo) / g) + 1));
                    std::vector<uint32_t> in_cell(static_cast<size_t>(gx) * gy * 2, 0);
                    for (const UV& item : uv) {
                        const int bx = std::min(gx - 1, static_cast<int>((item.u - ulo) / ((uhi - ulo) / gx + 1e-12)));
                        const int by = std::min(gy - 1, static_cast<int>((item.v - vlo) / ((vhi - vlo) / gy + 1e-12)));
                        ++in_cell[(static_cast<size_t>(by) * gx + bx) * 2 + static_cast<size_t>(item.which)];
                    }
                    double only[2] = { 0, 0 }, both = 0, within = 0.0, weight = 0.0;
                    for (size_t g2 = 0; g2 < in_cell.size(); g2 += 2) {
                        const double na = in_cell[g2], nb = in_cell[g2 + 1];
                        if (na > 0 && nb > 0) both += 1;
                        else if (na > 0) only[0] += 1;
                        else if (nb > 0) only[1] += 1;
                        if (na + nb >= 2) { within += 2.0 * na * nb / (na + nb - 1.0); weight += na + nb; }
                    }
                    // both sheets must cover (nearly) the same cells ...
                    const double smaller = std::min(only[0], only[1]) + both;
                    const double larger = std::max(only[0], only[1]) + both;
                    overlapping = smaller > 0 && both / smaller >= 0.6 && both / larger >= 0.4;
                    // ... and be MIXED there: in a doubled surface the two sheets'
                    // points are interleaved everywhere, so almost all of the
                    // variance of "which sheet" is found within small cells (the
                    // ratio is ~1). Where trims meet (a skirting into a return, an
                    // architrave into a picture rail) a short edge runs round every
                    // proud part and the cells above say "both", but each cell is
                    // mostly one sheet or the other: most of the variance is
                    // between cells.
                    const double wa = cnt[0] / (cnt[0] + cnt[1]);
                    const double mixed = weight > 0 ? (within / weight) / std::max(1e-12, 2.0 * wa * (1.0 - wa)) : 0.0;
                    if (mixed < 0.5) overlapping = false;
                }
                // ... and both be wide: the near and far halves of a pipe or rail
                // also "overlap", but each is a narrow curved strip, not a wall.
                // Width across the narrower direction is the 10th to 90th
                // percentile range: a few points elsewhere in the block (a strip
                // of the wall behind a pipe) must not make a pipe "wide".
                bool wide = true;
                for (int s = 0; s < 2 && overlapping; ++s) {
                    double cnt_s = 0, mu = 0, mv = 0, uu = 0, uvv = 0, vv = 0;
                    for (const UV& item : uv) if (item.which == s) { cnt_s += 1; mu += item.u; mv += item.v; }
                    if (cnt_s < 3) { wide = false; break; }
                    mu /= cnt_s; mv /= cnt_s;
                    for (const UV& item : uv) if (item.which == s) {
                        uu += (item.u - mu) * (item.u - mu); uvv += (item.u - mu) * (item.v - mv); vv += (item.v - mv) * (item.v - mv);
                    }
                    uu /= cnt_s; uvv /= cnt_s; vv /= cnt_s;
                    // minor axis of the 2 x 2 covariance
                    const double tr = uu + vv, det = uu * vv - uvv * uvv;
                    const double minor = 0.5 * tr - std::sqrt(std::max(0.0, 0.25 * tr * tr - det));
                    double au = uvv, av = minor - uu;
                    if (std::fabs(au) + std::fabs(av) < 1e-30) { au = uu <= vv ? 1.0 : 0.0; av = uu <= vv ? 0.0 : 1.0; }
                    const double al = std::sqrt(au * au + av * av);
                    au /= al; av /= al;
                    std::vector<double> across;
                    for (const UV& item : uv) if (item.which == s) across.push_back(item.u * au + item.v * av);
                    const double p10 = Na__Stat__Percentile(across, 0.10), p90 = Na__Stat__Percentile(across, 0.90);
                    if (p90 - p10 < 0.8 * w.fine) wide = false;
                }
                const double gap = std::fabs(a_at - b_at);
                if (overlapping && !wide) {
                    // a narrow curved object: no confident surface here, leave it alone
                    sf.flags |= NA_FAM_NARROW;
                    sheets.resize(1);
                    sf.sigma = 0.0f;
                    sheet_sigma = sigma;
                } else if (!overlapping) {
                    sf.flags |= NA_FAM_STEP;
                    // Refined with at least the cell's noise width: if the "two
                    // sheets" were really one surface whose height drifts across
                    // the block, a narrower width would pull it into two.
                    if (sf.sigma > 0.0f && sf.sigma < sigma) { sf.sigma = 0.0f; sheet_sigma = sigma; }
                } else if (gap >= pass_disagree) {
                    sf.flags |= NA_FAM_DOUBLING;
                    sf.gap = static_cast<float>(gap);
                } else {
                    // interleaved sheets closer than the user's limit: one noisy surface
                    double sum = 0.0, n_in = 0.0;
                    for (double o : offs) if (std::fabs(o - a_at) <= 2.5 * sigma || std::fabs(o - b_at) <= 2.5 * sigma) { sum += o; n_in += 1.0; }
                    sheets.assign(1, n_in > 0 ? sum / n_in : a_at);
                    sf.sigma = 0.0f;
                    sheet_sigma = sigma;
                }
            }

            // GPS time: scan passes over the main sheet that disagree.
            if (!w.time.empty() && !(sf.flags & NA_FAM_DOUBLING)) {
                struct T { float t; double o; };
                std::vector<T> timed;
                for (uint32_t k : members) if (std::fabs(offset_of[k] - sheets[0]) <= 2.5 * sigma) timed.push_back({ w.time[pts[k]], offset_of[k] });
                std::sort(timed.begin(), timed.end(), [](const T& a, const T& b) { return a.t < b.t || (a.t == b.t && a.o < b.o); });
                const size_t min_pass = std::max<size_t>(25, timed.size() * 15 / 100);
                std::vector<double> medians, current;
                for (size_t i = 0; i < timed.size(); ++i) {
                    if (i > 0 && timed[i].t - timed[i - 1].t > p.pass_gap_s) {
                        if (current.size() >= min_pass) medians.push_back(Na__Stat__Median(current));
                        current.clear();
                    }
                    current.push_back(timed[i].o);
                }
                if (current.size() >= min_pass) medians.push_back(Na__Stat__Median(current));
                if (medians.size() >= 2) {
                    const double spread = *std::max_element(medians.begin(), medians.end()) - *std::min_element(medians.begin(), medians.end());
                    if (spread >= pass_disagree) {
                        sf.flags |= NA_FAM_DOUBLING | NA_FAM_PASSES;
                        sf.gap = static_cast<float>(spread);
                    }
                }
            }

            sf.sheets = static_cast<uint8_t>(std::min<size_t>(3, sheets.size()));
            for (int s = 0; s < sf.sheets; ++s) sf.sheet[s] = static_cast<float>(sheets[static_cast<size_t>(s)]);
        }

        // explained share, confidence, boundary
        for (uint32_t k = 0; k < N; ++k) {
            double r, second;
            if (Na__NearestSheet(cs, Na__P(w, pts[k]), r, second) >= 0 && std::fabs(r) <= tau) ++explained;
        }
        const double explained_share = static_cast<double>(explained) / N;
        for (int f = 0; f < cs.families; ++f) {
            Na__SurfaceFamily& sf = cs.family[f];
            sf.conf = static_cast<float>(Na__Smoothstep(explained_share, 0.55, 0.85) * Na__Smoothstep(sf.members, 12.0, 40.0));
            if (sf.flags & NA_FAM_NARROW) { sf.conf = 0.0f; cs.flags |= NA_CELL_ROUGH; }
            if (sf.flags & NA_FAM_STEP) cs.flags |= NA_CELL_STEP;
            if (sf.flags & NA_FAM_DOUBLING) cs.flags |= NA_CELL_DOUBLING;
            // boundary: the members' in-plane centroid sits off the cell centre
            const Na__V3 u(sf.u[0], sf.u[1], sf.u[2]), v(sf.v[0], sf.v[1], sf.v[2]);
            double su = 0, sv = 0, cnt = 0;
            for (uint32_t k = 0; k < N; ++k) {
                if (family_of[k] != f) continue;
                const Na__V3 d = Na__P(w, pts[k]) - anchor;
                su += d.Dot(u); sv += d.Dot(v); cnt += 1.0;
            }
            if (cnt > 0 && std::sqrt((su / cnt) * (su / cnt) + (sv / cnt) * (sv / cnt)) > 0.5 * w.fine) cs.flags |= NA_CELL_BOUNDARY;
        }
        if (cs.families >= 2) cs.flags |= NA_CELL_MULTI;
        if (explained_share < 0.55) cs.flags |= NA_CELL_ROUGH;
    }

} // namespace

// -----------------------------------------------------------------------------
// REGION | Surface analysis
// -----------------------------------------------------------------------------

void Na__Clean__Surfaces(Na__CleanWork& w) {
    const auto start = std::chrono::steady_clock::now();
    w.surface_done = false;
    const Na__CleanParams& p = w.params;
    const size_t slots = w.slot_cell.size();
    w.surfaces.assign(slots, Na__CellSurface());

    // Cells that need an analysis: any point within zones.surface.
    std::vector<float> min_depth(slots, 1e30f);
    for (size_t s = 0; s < slots; ++s) {
        const uint32_t c = w.slot_cell[s];
        for (uint32_t j = w.cell_start[c]; j < w.cell_start[c + 1]; ++j) min_depth[s] = std::min(min_depth[s], w.depth[j]);
    }
    const float zone = static_cast<float>(w.zones.surface);
    // Pass 1 for every cell a pass-3 cell reads: its noise width (3 x 3 x 3)
    // and the planes it borrows (NA_SURFACE_BORROW_REACH).
    std::vector<uint8_t> need3(slots, 0), need1(slots, 0);
    const int reach = std::max(1, NA_SURFACE_BORROW_REACH);
    for (size_t s = 0; s < slots; ++s) {
        if (min_depth[s] > zone) continue;
        need3[s] = 1;
        int64_t c[3];
        Na__Clean__CellCoords(w, w.slot_cell[s], c);
        for (int dz = -reach; dz <= reach; ++dz) for (int dy = -reach; dy <= reach; ++dy) for (int dx = -reach; dx <= reach; ++dx) {
            const uint32_t nb = Na__Clean__CellAt(w, c[0] + dx, c[1] + dy, c[2] + dz);
            if (nb != UINT32_MAX && w.cell_slot[nb] != UINT32_MAX) need1[w.cell_slot[nb]] = 1;
        }
    }

    std::vector<uint32_t> list1, list3;
    for (size_t s = 0; s < slots; ++s) { if (need1[s]) list1.push_back(static_cast<uint32_t>(s)); if (need3[s]) list3.push_back(static_cast<uint32_t>(s)); }

    Na__ParallelFor(static_cast<int64_t>(list1.size()), 16, w.cancel, [&](int64_t b, int64_t e) {
        std::vector<uint32_t> pts;
        for (int64_t k = b; k < e; ++k) Na__Pass1(w, list1[static_cast<size_t>(k)], pts);
    });

    // noise width per cell: median of the thin cells around it (3 x 3 x 3); where
    // fewer than three are that close (a strip of trim, a sill, a corner), the
    // nearest nine within the borrowing reach say how noisy this part of the
    // scan is, which the 8 mm fallback cannot.
    const float fallback = static_cast<float>(p.sigma_fallback_mm * w.units_per_mm);
    const float lo_sigma = static_cast<float>(0.2 * w.units_per_mm), hi_sigma = static_cast<float>(40.0 * w.units_per_mm);
    Na__ParallelFor(static_cast<int64_t>(list3.size()), 64, w.cancel, [&](int64_t b, int64_t e) {
        std::vector<float> near;
        for (int64_t k = b; k < e; ++k) {
            const uint32_t s = list3[static_cast<size_t>(k)];
            int64_t c[3];
            Na__Clean__CellCoords(w, w.slot_cell[s], c);
            auto thin_sigma = [&](int dx, int dy, int dz) {
                const uint32_t nb = Na__Clean__CellAt(w, c[0] + dx, c[1] + dy, c[2] + dz);
                if (nb == UINT32_MAX || w.cell_slot[nb] == UINT32_MAX) return -1.0f;
                const Na__CellSurface& other = w.surfaces[w.cell_slot[nb]];
                return other.thin && other.pair_sigma > 0 ? other.pair_sigma : -1.0f;
            };
            near.clear();
            const float own = thin_sigma(0, 0, 0);
            if (own > 0) near.push_back(own);
            for (int dz = -1; dz <= 1; ++dz) for (int dy = -1; dy <= 1; ++dy) for (int dx = -1; dx <= 1; ++dx) {
                if (!dx && !dy && !dz) continue;
                const float v = thin_sigma(dx, dy, dz);
                if (v > 0) near.push_back(v);
            }
            if (near.size() < 3) {
                for (const std::array<int, 3>& d : Na__BorrowOffsets()) {
                    if (std::abs(d[0]) <= 1 && std::abs(d[1]) <= 1 && std::abs(d[2]) <= 1) continue;   // counted above
                    const float v = thin_sigma(d[0], d[1], d[2]);
                    if (v > 0) near.push_back(v);
                    if (near.size() >= 9) break;
                }
            }
            const float sigma = near.empty() ? fallback : Na__Stat__MedianF(near, fallback);
            w.surfaces[s].sigma = std::min(hi_sigma, std::max(lo_sigma, sigma));
        }
    });

    Na__ParallelFor(static_cast<int64_t>(list3.size()), 8, w.cancel, [&](int64_t b, int64_t e) {
        std::vector<uint32_t> pts;
        for (int64_t k = b; k < e; ++k) Na__Pass3(w, list3[static_cast<size_t>(k)], pts);
    });

    w.ms_surface = Na__MsSince(start);
    w.surface_done = true;
}

// -----------------------------------------------------------------------------
// REGION | Refine + scatter candidates
// -----------------------------------------------------------------------------

void Na__Clean__Refine(Na__CleanWork& w) {
    const auto start = std::chrono::steady_clock::now();
    w.refine_done = false;
    const Na__CleanParams& p = w.params;
    const uint32_t n = w.n;
    const uint16_t cleared = static_cast<uint16_t>(NA_CF_MOVED | NA_CF_DOUBLING | NA_CF_HELD_AMBIGUOUS | NA_CF_ON_SURFACE |
                                                  NA_CF_FEATURE | NA_CF_CANDIDATE | NA_CF_REMOVED_BLOWOUT);
    for (uint32_t i = 0; i < n; ++i) w.flags[i] &= static_cast<uint16_t>(~cleared);
    std::fill(w.delta.begin(), w.delta.end(), 0.0f);
    w.family_of.assign(n, -1);
    w.sheet_of.assign(n, -1);

    const float zone_surface = static_cast<float>(w.zones.surface);
    const float zone_refine = static_cast<float>(w.zones.refine);
    const double max_move = p.max_move_mm * w.units_per_mm;
    const double rho = p.smooth_radius_mm * w.units_per_mm;
    const double strength = p.refine_strength;

    Na__ParallelFor(n, 1024, w.cancel, [&](int64_t b, int64_t e) {
        std::vector<uint32_t> found;
        struct Nb { double du, dv, dz, d2; uint32_t tie; };
        std::vector<Nb> nbs;
        for (int64_t ii = b; ii < e; ++ii) {
            const uint32_t i = static_cast<uint32_t>(ii);
            if (w.depth[i] > zone_surface || Na__NoiseRemoved(w, i)) continue;
            const uint32_t slot = w.cell_slot[w.cell[i]];
            if (slot == UINT32_MAX) continue;
            const Na__CellSurface& cs = w.surfaces[slot];
            if (!cs.computed) continue;
            if (cs.flags & (NA_CELL_MULTI | NA_CELL_STEP | NA_CELL_DOUBLING | NA_CELL_BOUNDARY | NA_CELL_ROUGH)) w.flags[i] |= NA_CF_FEATURE;
            if (cs.families == 0) continue;
            const Na__V3 pi = Na__P(w, i);
            double r, second;
            int sheet = -1;
            const int f = Na__NearestSheet(cs, pi, r, second, &sheet);
            if (f < 0) continue;
            const Na__SurfaceFamily& sf = cs.family[f];
            const double sigma = sf.sigma > 0.0f ? sf.sigma : cs.sigma;
            if (std::fabs(r) > p.inlier_band * sigma) {                   // not on this surface: never moved,
                w.flags[i] |= NA_CF_FEATURE;                               // and kept densely (pipes, handles...)
                continue;
            }
            w.family_of[i] = static_cast<int8_t>(f);
            w.sheet_of[i] = static_cast<int8_t>(sheet);
            if (sf.conf >= 0.5f) w.flags[i] |= NA_CF_ON_SURFACE;
            if (sf.flags & NA_FAM_DOUBLING) {
                w.flags[i] |= NA_CF_DOUBLING;
                if (p.doubling_hold) continue;
            }
            // the local fit moves points (Refine) and finds edges by its slope (Density)
            if (!(p.refine_enabled || p.density_enabled) || w.depth[i] > zone_refine) continue;

            // where two orientations meet, a point near both is left alone
            const double c_assign = cs.families > 1 ? Na__Smoothstep((second - std::fabs(r)) / sigma, 0.5, 2.0) : 1.0;
            if (c_assign < 0.25) { w.flags[i] |= NA_CF_HELD_AMBIGUOUS | NA_CF_FEATURE; continue; }

            // neighbours of the same family within rho in-plane and 4 sigma across
            const Na__V3 nrm(sf.n[0], sf.n[1], sf.n[2]), u(sf.u[0], sf.u[1], sf.u[2]), v(sf.v[0], sf.v[1], sf.v[2]);
            const double across = 4.0 * sigma;
            const float reach = static_cast<float>(std::sqrt(rho * rho + across * across));
            w.tree.Radius(&w.xyz[size_t(i) * 3], reach * reach, found);
            nbs.clear();
            for (uint32_t q : found) {
                if (q == i || Na__NoiseRemoved(w, q)) continue;
                const Na__V3 pq = Na__P(w, q);
                double rq, sq;
                if (Na__NearestSheet(cs, pq, rq, sq) != f) continue;
                const Na__V3 d = pq - pi;
                const double dz = d.Dot(nrm);
                if (std::fabs(dz) > across) continue;
                const double du = d.Dot(u), dv = d.Dot(v);
                const double d2 = du * du + dv * dv;
                if (d2 > rho * rho) continue;
                nbs.push_back({ du, dv, dz, d2, w.tie[q] });
            }
            if (nbs.size() > static_cast<size_t>(NA_FIT_NEIGHBOURS)) {
                std::nth_element(nbs.begin(), nbs.begin() + NA_FIT_NEIGHBOURS, nbs.end(),
                                 [](const Nb& a, const Nb& c) { return a.d2 < c.d2 || (a.d2 == c.d2 && a.tie < c.tie); });
                nbs.resize(NA_FIT_NEIGHBOURS);
            }
            // fixed order for the sums
            std::sort(nbs.begin(), nbs.end(), [](const Nb& a, const Nb& c) { return a.tie < c.tie; });
            if (nbs.size() < 6) continue;

            // start at the point's own height: the median of neighbours within 1 sigma of it
            std::vector<double> close;
            close.push_back(0.0);
            for (const Nb& nb : nbs) if (std::fabs(nb.dz) <= sigma) close.push_back(nb.dz);
            double a = Na__Stat__Median(close), bu = 0.0, bv = 0.0;
            const double ct = 2.5 * sigma;
            double weight_sum = 0.0;
            for (int iter = 0; iter < 8; ++iter) {
                double s[6] = { 0, 0, 0, 0, 0, 0 }, t[3] = { 0, 0, 0 };
                weight_sum = 0.0;
                for (const Nb& nb : nbs) {
                    const double res = nb.dz - (a + bu * nb.du + bv * nb.dv);
                    if (std::fabs(res) >= ct) continue;
                    const double x = res / ct, wt = (1.0 - x * x) * (1.0 - x * x);
                    weight_sum += wt;
                    s[0] += wt; s[1] += wt * nb.du; s[2] += wt * nb.dv;
                    s[3] += wt * nb.du * nb.du; s[4] += wt * nb.du * nb.dv; s[5] += wt * nb.dv * nb.dv;
                    t[0] += wt * nb.dz; t[1] += wt * nb.du * nb.dz; t[2] += wt * nb.dv * nb.dz;
                }
                if (weight_sum < 3.0) break;
                double na = t[0] / s[0], nu = 0.0, nv = 0.0;
                // full plane when the neighbours spread in both directions, else level
                const double m00 = s[0], m01 = s[1], m02 = s[2], m11 = s[3], m12 = s[4], m22 = s[5];
                const double det = m00 * (m11 * m22 - m12 * m12) - m01 * (m01 * m22 - m12 * m02) + m02 * (m01 * m12 - m11 * m02);
                const double spread = (m11 / m00 - (m01 / m00) * (m01 / m00)) * (m22 / m00 - (m02 / m00) * (m02 / m00));
                if (spread > 0.01 * rho * rho * rho * rho && std::fabs(det) > 1e-30) {
                    const double c00 = m11 * m22 - m12 * m12, c01 = m02 * m12 - m01 * m22, c02 = m01 * m12 - m02 * m11;
                    const double c11 = m00 * m22 - m02 * m02, c12 = m01 * m02 - m00 * m12, c22 = m00 * m11 - m01 * m01;
                    const double sa = (c00 * t[0] + c01 * t[1] + c02 * t[2]) / det;
                    const double su = (c01 * t[0] + c11 * t[1] + c12 * t[2]) / det;
                    const double sv = (c02 * t[0] + c12 * t[1] + c22 * t[2]) / det;
                    if (std::fabs(su) <= 0.6 && std::fabs(sv) <= 0.6) { na = sa; nu = su; nv = sv; }
                }
                const double change = std::fabs(na - a);
                a = na; bu = nu; bv = nv;
                if (change < 1e-3 * sigma) break;
            }
            if (weight_sum < 3.0) continue;
            // A step that noise hides from the cell analysis still tilts the
            // smoothed surface across its edge: keep detail there.
            if (bu * bu + bv * bv > 0.2 * 0.2) w.flags[i] |= NA_CF_FEATURE;
            if (!p.refine_enabled) continue;
            if (std::fabs(a) > p.inlier_band * sigma) continue;            // the surface is not where this point is

            const double conf = c_assign * Na__Smoothstep(weight_sum, 4.0, 16.0) * sf.conf;
            if (conf < 0.15) continue;
            double move = strength * conf * a;
            move = std::max(-max_move, std::min(max_move, move));
            if (move == 0.0) continue;
            w.delta[size_t(i) * 3]     = static_cast<float>(nrm.x * move);
            w.delta[size_t(i) * 3 + 1] = static_cast<float>(nrm.y * move);
            w.delta[size_t(i) * 3 + 2] = static_cast<float>(nrm.z * move);
            w.flags[i] |= NA_CF_MOVED;
        }
    });

    // --- sparse scatter off every surface (Remove Noise, reflection cleanup) ---------------
    // Reference: the spacing of the confident surfaces around the point, as
    // the median per COARSE cell (3 x 3 x 3 fine cells, 150 mm) over the
    // 5 x 5 x 5 coarse cells around it (at least 300 mm in every direction),
    // so a blow-out cloud hanging off a window still sees the wall and frame
    // it is next to. Scatter further than that from every surface is not
    // judged: with no surface near, sparse can just as well be real (a garden
    // seen through the glass).
    if (p.noise_enabled) {
        auto coarse_of = [&](const int64_t c[3], int64_t out[3]) {
            for (int a = 0; a < 3; ++a) out[a] = Na__FloorDiv(static_cast<double>(c[a]), 3.0);
        };
        // coarse cells relative to the region's first one, packed (sparse: only
        // coarse cells holding confident surface points are kept)
        int64_t cbase[3];
        {
            int64_t o[3] = { w.fine_origin[0], w.fine_origin[1], w.fine_origin[2] };
            coarse_of(o, cbase);
            for (int a = 0; a < 3; ++a) cbase[a] -= 2;
        }
        auto coarse_key = [&](const int64_t cc[3]) -> int64_t {
            const int64_t x = cc[0] - cbase[0], y = cc[1] - cbase[1], z = cc[2] - cbase[2];
            if (x < 0 || y < 0 || z < 0 || x >= (1 << 21) || y >= (1 << 21) || z >= (1 << 21)) return -1;
            return (z << 42) | (y << 21) | x;
        };
        struct KV { int64_t key; float value; };
        std::vector<KV> on_surface;
        for (uint32_t i = 0; i < n; ++i) {
            if (w.depth[i] > zone_surface || !(w.flags[i] & NA_CF_ON_SURFACE)) continue;
            int64_t c[3], cc[3];
            Na__Clean__CellCoords(w, w.cell[i], c);
            coarse_of(c, cc);
            const int64_t k = coarse_key(cc);
            if (k >= 0) on_surface.push_back({ k, w.spacing_ref[i] });
        }
        Na__CheckCancel(w.cancel);
        std::sort(on_surface.begin(), on_surface.end(), [](const KV& a, const KV& b) { return a.key < b.key || (a.key == b.key && a.value < b.value); });
        std::vector<int64_t> coarse_keys;
        std::vector<float> coarse_spacing;
        {
            std::vector<float> run;
            size_t begin = 0;
            while (begin < on_surface.size()) {
                size_t end = begin;
                run.clear();
                while (end < on_surface.size() && on_surface[end].key == on_surface[begin].key) run.push_back(on_surface[end++].value);
                if (run.size() >= 3) { coarse_keys.push_back(on_surface[begin].key); coarse_spacing.push_back(Na__Stat__MedianF(run)); }
                begin = end;
            }
        }
        std::vector<KV>().swap(on_surface);
        auto coarse_lookup = [&](const int64_t cc[3]) -> float {
            const int64_t k = coarse_key(cc);
            if (k < 0) return -1.0f;
            const auto it = std::lower_bound(coarse_keys.begin(), coarse_keys.end(), k);
            return it != coarse_keys.end() && *it == k ? coarse_spacing[static_cast<size_t>(it - coarse_keys.begin())] : -1.0f;
        };
        Na__ParallelFor(n, 4096, w.cancel, [&](int64_t b, int64_t e) {
            std::vector<float> near;
            for (int64_t ii = b; ii < e; ++ii) {
                const uint32_t i = static_cast<uint32_t>(ii);
                if (w.depth[i] > zone_refine || Na__NoiseRemoved(w, i) || (w.flags[i] & NA_CF_ON_SURFACE)) continue;
                int64_t c[3], cc[3];
                Na__Clean__CellCoords(w, w.cell[i], c);
                coarse_of(c, cc);
                near.clear();
                for (int dz = -2; dz <= 2; ++dz) for (int dy = -2; dy <= 2; ++dy) for (int dx = -2; dx <= 2; ++dx) {
                    const int64_t nb[3] = { cc[0] + dx, cc[1] + dy, cc[2] + dz };
                    const float spacing = coarse_lookup(nb);
                    if (spacing > 0) near.push_back(spacing);
                }
                if (near.empty()) continue;
                const float surface_spacing = Na__Stat__MedianF(near);
                if (w.spacing_ref[i] > static_cast<float>(p.scatter_ratio) * surface_spacing) {
                    w.flags[i] |= p.blowout_remove ? NA_CF_REMOVED_BLOWOUT : NA_CF_CANDIDATE;
                    if (p.blowout_remove) {
                        w.flags[i] &= static_cast<uint16_t>(~NA_CF_MOVED);
                        w.delta[size_t(i) * 3] = w.delta[size_t(i) * 3 + 1] = w.delta[size_t(i) * 3 + 2] = 0.0f;
                    }
                }
            }
        });
    }

    w.ms_refine = Na__MsSince(start);
    w.refine_done = true;
}
