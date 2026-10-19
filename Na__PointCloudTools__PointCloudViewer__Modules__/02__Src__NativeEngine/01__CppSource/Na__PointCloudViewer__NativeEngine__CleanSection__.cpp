// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - CLEANING: SECTION EVALUATION
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__CleanSection__.cpp
// PURPOSE    : The preview's numbers: counts per verdict, how far points
//              moved, and the scatter of the main surfaces in the box before
//              and after cleaning.
//
// WHAT THE SCATTER FIGURE IS: for each of up to two dominant flat surfaces in
//   the box, a plane is fitted ONCE to the original points (robust PCA). The
//   figure is the width that holds the middle 90 % of distances to that plane
//   (P95 - P5), for the original points and for the same points after
//   cleaning (those still kept). It is the thickness of the noisy band you
//   see in a section, measured around an estimated plane. It is NOT the
//   physical thickness of a wall and NOT survey accuracy. The median shift
//   says whether the band moved as a whole (it should not).
//
// WHEN THERE IS NO FIGURE: if no flat surface holds at least a quarter of the
//   box's points, or too few points are in the box, no figure is given. A
//   surface with a parallel second sheet, mixed cells or doubling is flagged
//   so the dialog can say the figure needs care.
//
// =============================================================================

#include "Na__PointCloudViewer__NativeEngine__CleanRegion__.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>

namespace {

    inline Na__V3 Na__Orig(const Na__CleanWork& w, uint32_t i) {
        return Na__V3(w.xyz[size_t(i) * 3], w.xyz[size_t(i) * 3 + 1], w.xyz[size_t(i) * 3 + 2]);
    }
    inline Na__V3 Na__After(const Na__CleanWork& w, uint32_t i) {
        return Na__V3(double(w.xyz[size_t(i) * 3]) + w.delta[size_t(i) * 3], double(w.xyz[size_t(i) * 3 + 1]) + w.delta[size_t(i) * 3 + 1],
                      double(w.xyz[size_t(i) * 3 + 2]) + w.delta[size_t(i) * 3 + 2]);
    }

    struct Na__SecPlane { Na__V3 n, c; };

    bool Na__SecRansac(const Na__CleanWork& w, const std::vector<uint32_t>& sample, double tau, Na__Rng& rng, Na__SecPlane& out) {
        if (sample.size() < 3) return false;
        double best = 1e300;
        bool have = false;
        for (int h = 0; h < 200; ++h) {
            const uint32_t a = sample[rng.Below(static_cast<uint32_t>(sample.size()))];
            const uint32_t b = sample[rng.Below(static_cast<uint32_t>(sample.size()))];
            const uint32_t c = sample[rng.Below(static_cast<uint32_t>(sample.size()))];
            if (a == b || b == c || a == c) continue;
            const Na__V3 pa = Na__Orig(w, a);
            const Na__V3 cross = (Na__Orig(w, b) - pa).Cross(Na__Orig(w, c) - pa);
            const double len = cross.Length();
            if (len <= 0.0) continue;
            const Na__V3 n = cross * (1.0 / len);
            double score = 0.0;
            for (uint32_t i : sample) {
                const double r = n.Dot(Na__Orig(w, i) - pa);
                score += std::min(r * r, tau * tau);
                if (score >= best) break;
            }
            if (score < best) { best = score; out.n = n; out.c = pa; have = true; }
        }
        return have;
    }

    Na__SecPlane Na__SecRefit(const Na__CleanWork& w, const std::vector<uint32_t>& members, const Na__SecPlane& start, double band) {
        Na__SecPlane plane = start;
        for (int round = 0; round < 3; ++round) {
            Na__PlaneAccumulator acc(plane.c);
            for (uint32_t i : members) {
                const Na__V3 p = Na__Orig(w, i);
                if (std::fabs(plane.n.Dot(p - plane.c)) <= band) acc.Add(p.x, p.y, p.z);
            }
            const Na__PlaneFit fit = acc.Fit();
            if (!fit.valid) break;
            plane.n = fit.normal;
            plane.c = fit.centre;
            // tighten to 2.5 robust sigmas of the bulk
            std::vector<double> res;
            for (uint32_t i : members) res.push_back(plane.n.Dot(Na__Orig(w, i) - plane.c));
            const double sigma = Na__Stat__RobustSigma(res, band / 2.5);
            band = std::max(2.5 * sigma, 1e-9);
        }
        return plane;
    }

    void Na__Band(std::vector<double>& values, double& p5, double& p50, double& p95, double& sigma) {
        p5  = Na__Stat__Percentile(values, 0.05);
        p50 = Na__Stat__Percentile(values, 0.50);
        p95 = Na__Stat__Percentile(values, 0.95);
        sigma = Na__Stat__RobustSigma(values);
    }

} // namespace

void Na__Clean__Section(const Na__CleanWork& w, double* s) {
    std::memset(s, 0, sizeof(double) * NAPC_CS_COUNT);
    const double mm = w.params.mm_per_unit;   // units -> mm

    // --- counts and moves over the core ----------------------------------------------------
    std::vector<uint32_t> core;
    std::vector<double> moves, sigmas;
    double gap = 0.0;
    for (uint32_t i = 0; i < w.n; ++i) {
        if (!w.core[i]) continue;
        core.push_back(i);
        const uint16_t f = w.flags[i];
        if (!(f & NA_CF_REMOVED_ANY)) s[NAPC_CS_KEPT] += 1;
        if (f & NA_CF_REMOVED_ISOLATED) s[NAPC_CS_REMOVED_ISOLATED] += 1;
        if (f & NA_CF_REMOVED_CLUSTER) s[NAPC_CS_REMOVED_CLUSTER] += 1;
        if (f & NA_CF_REMOVED_BLOWOUT) s[NAPC_CS_REMOVED_BLOWOUT] += 1;
        if ((f & NA_CF_REMOVED_DENSITY) && !(f & NA_CF_REMOVED_NOISE)) s[NAPC_CS_REMOVED_DENSITY] += 1;
        if ((f & NA_CF_MOVED) && !(f & NA_CF_REMOVED_ANY)) {
            s[NAPC_CS_MOVED] += 1;
            const double dx = w.delta[size_t(i) * 3], dy = w.delta[size_t(i) * 3 + 1], dz = w.delta[size_t(i) * 3 + 2];
            moves.push_back(std::sqrt(dx * dx + dy * dy + dz * dz) * mm);
        }
        if (f & NA_CF_CANDIDATE) s[NAPC_CS_CANDIDATES] += 1;
        if (f & NA_CF_DOUBLING) s[NAPC_CS_DOUBLING] += 1;
        if (f & NA_CF_HELD_AMBIGUOUS) s[NAPC_CS_HELD_AMBIGUOUS] += 1;
        if (f & NA_CF_ON_SURFACE) s[NAPC_CS_ON_SURFACE] += 1;
        if (f & NA_CF_FEATURE) s[NAPC_CS_FEATURE] += 1;
        const uint32_t slot = w.cell_slot[w.cell[i]];
        if (slot != UINT32_MAX && w.surfaces.size() > slot && w.surfaces[slot].computed) {
            const Na__CellSurface& cs = w.surfaces[slot];
            sigmas.push_back(cs.sigma * mm);
            for (int fam = 0; fam < cs.families; ++fam) {
                if (cs.family[fam].flags & NA_FAM_DOUBLING) gap = std::max(gap, static_cast<double>(cs.family[fam].gap) * mm);
            }
        }
    }
    s[NAPC_CS_CORE_POINTS] = static_cast<double>(core.size());
    if (!moves.empty()) {
        std::vector<double> m2 = moves;
        s[NAPC_CS_MOVE_MEDIAN_MM] = Na__Stat__Median(m2);
        m2 = moves;
        s[NAPC_CS_MOVE_P95_MM] = Na__Stat__Percentile(m2, 0.95);
        s[NAPC_CS_MOVE_MAX_MM] = *std::max_element(moves.begin(), moves.end());
    }
    s[NAPC_CS_GATHERED_POINTS] = w.n;
    s[NAPC_CS_HALO_MM] = w.zones.gather;
    const double sigma_mm = Na__Stat__Median(sigmas, w.params.sigma_fallback_mm);
    s[NAPC_CS_SIGMA_MM] = sigmas.empty() ? 0.0 : sigma_mm;
    s[NAPC_CS_DOUBLING_GAP_MM] = gap;

    // --- main surfaces ----------------------------------------------------------------------
    if (core.size() < 200) {
        s[NAPC_CS_SURFACE_COUNT] = -1;
        s[NAPC_CS_SURFACE_NOTE] = 3;
        return;
    }
    const double upm = w.units_per_mm;
    const double sigma_u = std::max(0.5, sigma_mm) * upm;
    const double tau = std::max(3.0 * sigma_u, 4.0 * upm);
    const double band = std::max(4.0 * sigma_u, 15.0 * upm);
    Na__Rng rng(0x5345435449ull);   // "SECTI": the same planes for the same points

    std::vector<uint32_t> remaining = core;
    struct Found { Na__SecPlane plane; std::vector<uint32_t> members; bool stepped = false; };
    std::vector<Found> reported;
    const size_t min_members = std::max<size_t>(300, core.size() / 4);
    for (int iter = 0; iter < 4 && remaining.size() >= min_members; ++iter) {
        std::vector<uint32_t> sample;
        const size_t step = std::max<size_t>(1, remaining.size() / 20000);
        for (size_t k = 0; k < remaining.size(); k += step) sample.push_back(remaining[k]);
        Na__SecPlane plane;
        if (!Na__SecRansac(w, sample, tau, rng, plane)) break;
        std::vector<uint32_t> members, rest;
        for (uint32_t i : remaining) (std::fabs(plane.n.Dot(Na__Orig(w, i) - plane.c)) <= band ? members : rest).push_back(i);
        if (members.size() < min_members) break;
        plane = Na__SecRefit(w, members, plane, band);
        members.clear(); rest.clear();
        for (uint32_t i : remaining) (std::fabs(plane.n.Dot(Na__Orig(w, i) - plane.c)) <= band ? members : rest).push_back(i);
        if (members.size() < min_members) break;
        bool parallel = false;
        for (Found& f : reported) {
            if (Na__Geo__LineAngleDeg(f.plane.n, plane.n) < 20.0) { f.stepped = true; parallel = true; }
        }
        if (!parallel && reported.size() < 2) reported.push_back({ plane, members, false });
        remaining.swap(rest);
    }

    if (reported.empty()) {
        s[NAPC_CS_SURFACE_COUNT] = -1;
        s[NAPC_CS_SURFACE_NOTE] = 2;
        return;
    }
    s[NAPC_CS_SURFACE_COUNT] = static_cast<double>(reported.size());
    s[NAPC_CS_SURFACE_NOTE] = reported.size() > 1 ? 1 : 0;
    for (size_t k = 0; k < reported.size(); ++k) {
        const Found& f = reported[k];
        double* o = s + NAPC_CS_S0 + k * NAPC_SS_COUNT;
        const Na__V3 n = f.plane.n;
        const double az = std::fabs(n.z);
        o[NAPC_SS_KIND] = az >= 0.95 ? 2 : (az <= 0.26 ? 1 : 3);
        o[NAPC_SS_NX] = n.x; o[NAPC_SS_NY] = n.y; o[NAPC_SS_NZ] = n.z;
        std::vector<double> before, after;
        double moved = 0, removed = 0, mixed = 0, doubled = 0;
        for (uint32_t i : f.members) {
            before.push_back(n.Dot(Na__Orig(w, i) - f.plane.c) * mm);
            const uint16_t fl = w.flags[i];
            if (fl & NA_CF_REMOVED_ANY) { removed += 1; continue; }
            after.push_back(n.Dot(Na__After(w, i) - f.plane.c) * mm);
            if (fl & NA_CF_MOVED) moved += 1;
            if (fl & NA_CF_DOUBLING) doubled += 1;
            const uint32_t slot = w.cell_slot[w.cell[i]];
            if (slot != UINT32_MAX && w.surfaces[slot].computed &&
                (w.surfaces[slot].flags & (NA_CELL_MULTI | NA_CELL_STEP | NA_CELL_DOUBLING | NA_CELL_ROUGH))) mixed += 1;
        }
        double p5, p50, p95, sg;
        o[NAPC_SS_POINTS_BEFORE] = static_cast<double>(before.size());
        Na__Band(before, p5, p50, p95, sg);
        o[NAPC_SS_BAND_BEFORE_MM] = p95 - p5;
        o[NAPC_SS_SIGMA_BEFORE_MM] = sg;
        const double median_before = p50;
        o[NAPC_SS_POINTS_AFTER] = static_cast<double>(after.size());
        if (!after.empty()) {
            Na__Band(after, p5, p50, p95, sg);
            o[NAPC_SS_BAND_AFTER_MM] = p95 - p5;
            o[NAPC_SS_SIGMA_AFTER_MM] = sg;
            o[NAPC_SS_SHIFT_MM] = p50 - median_before;
        }
        o[NAPC_SS_MOVED] = moved;
        o[NAPC_SS_REMOVED] = removed;
        const double kept = std::max(1.0, static_cast<double>(f.members.size()) - removed);
        o[NAPC_SS_FLAGS] = (f.stepped ? 1 : 0) | (mixed / kept > 0.2 ? 2 : 0) | (doubled / kept > 0.1 ? 4 : 0);
        o[NAPC_SS_SHARE] = static_cast<double>(f.members.size()) / core.size();
    }
}
