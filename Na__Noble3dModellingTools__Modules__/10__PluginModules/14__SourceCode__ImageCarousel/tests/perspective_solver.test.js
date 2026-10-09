/* Perspective Angle solver: accuracy and honest +/- on synthetic photos.
 *
 * node tests/perspective_solver.test.js
 * Random gabled boxes are photographed by random cameras (lens, tilt, turn,
 * roll), lines are clicked with pixel noise, and the solver must return the
 * true pitch, with the shown +/- (2 sigma) containing it about 95% of the time.
 */
'use strict';
var path = require('path');
var S = require(path.resolve(__dirname, '..', 'Na__Noble3dModellingTools__ImageCarousel__PerspectiveSolver__.js'));
var scene = require('./perspective_scene.js');

var fails = 0, passes = 0;
function check(name, cond, detail) {
    if (cond) { passes++; }
    else { fails++; console.log('FAIL  ' + name + (detail ? '  ' + detail : '')); }
}

// ---------------------------------------------------------------- linear algebra
(function() {
    var r = scene.rng(7);
    for (var t = 0; t < 50; t++) {
        var n = t % 2 ? 3 : 4, A = [];
        for (var i = 0; i < n; i++) { A.push([]); for (var j = 0; j < n; j++) A[i].push(0); }
        for (i = 0; i < n; i++) for (j = i; j < n; j++) { var v = r.range(-5, 5); A[i][j] = v; A[j][i] = v; }
        var e = S._symEig(A), worst = 0;
        for (var k = 0; k < n; k++) {
            var vec = e.vectors[k];
            for (i = 0; i < n; i++) {
                var av = 0; for (j = 0; j < n; j++) av += A[i][j] * vec[j];
                worst = Math.max(worst, Math.abs(av - e.values[k] * vec[i]));
            }
        }
        check('symEig ' + t, worst < 1e-9, 'residual ' + worst);
    }
    var E = S._rotExp([0.3, -1.2, 0.7]), orth = 0;
    for (var a = 0; a < 3; a++) for (var b = 0; b < 3; b++) {
        var d = E[0][a] * E[0][b] + E[1][a] * E[1][b] + E[2][a] * E[2][b];
        orth = Math.max(orth, Math.abs(d - (a === b ? 1 : 0)));
    }
    check('rotExp orthonormal', orth < 1e-12, orth);
    var f26 = S.lensMmToPx(26, 4032, 3024);
    check('26 mm on 4032x3024 ~ 3028 px', Math.abs(f26 - 3028.6) < 1.5, f26);
    check('lens px->mm round trip', Math.abs(S.lensPxToMm(f26, 4032, 3024) - 26) < 1e-9);
})();

var buildCase = scene.buildCase, linesFrom = scene.linesFrom, visible = scene.visible, meas = scene.meas;

// ---------------------------------------------------------------- noise-free accuracy
(function() {
    var worst = 0, worstF = 0, n = 0, worstCase = '', worstExact = 0;
    for (var seed = 1; seed <= 150; seed++) {
        var cs = buildCase(seed);
        if (cs.segs.z.length < 2 || cs.segs.x.length < 2) continue;
        if (!visible(cs, cs.pts.right) || !visible(cs, cs.pts.apex)) continue;
        var r = scene.rng(seed * 31);
        var lensErr = 0.08 * r.gauss();
        var lens = { fPx: cs.f * Math.exp(lensErr), sigmaLn: 0.12 };
        var lines = linesFrom(cs, 'zxy', 0, r);
        var exact = S.analyse({ lines: lines, lens: { fPx: cs.f, sigmaLn: 0.12 }, size: { w: cs.w, h: cs.h }, trials: 0,
            measurements: [meas('pitch', 'xz', cs.pts.right, 0, r, 1)] });
        if (exact.cal.ok) worstExact = Math.max(worstExact, Math.abs(exact.results[0].value - cs.theta), Math.abs(exact.cal.f / cs.f - 1) * 100);
        var out = S.analyse({ lines: lines, lens: lens, size: { w: cs.w, h: cs.h }, trials: 0,
            measurements: [meas('pitch', 'xz', cs.pts.right, 0, r, 1), meas('angle', 'xz', cs.pts.apex, 0, r, 2)] });
        if (!out.cal.ok) { check('noise-free calibrates ' + seed, false, out.cal.need); continue; }
        n++;
        var e1 = Math.abs(out.results[0].value - cs.theta);
        var e2 = Math.abs(out.results[1].value - (180 - 2 * cs.theta));
        var ef = Math.abs(out.cal.f / cs.f - 1);
        if (Math.max(e1, e2) > worst) { worst = Math.max(e1, e2); worstCase = 'seed ' + seed; }
        worstF = Math.max(worstF, ef);
    }
    console.log('noise-free, 3 axes, lens prior 8% off: ' + n + ' cases, worst angle error ' + worst.toFixed(6) + ' deg (' + worstCase + '), worst f error ' + (worstF * 100).toFixed(4) + '%');
    console.log('noise-free, 3 axes, true lens prior: worst angle-or-f(%) error ' + worstExact.toFixed(8));
    check('noise-free 3-axis cases ran', n > 60, n);
    check('noise-free 3-axis exact with the true lens', worstExact < 1e-4, worstExact);
    check('noise-free 3-axis with an 8% lens error stays within 0.05 deg', worst < 0.05, worst);
    check('noise-free 3-axis lines mostly override the lens prior', worstF < 0.03, worstF);
})();

// ---------------------------------------------------------------- noise-free, verticals + red only (gable workflow)
(function() {
    var worst = 0, n = 0, worstCase = '';
    for (var seed = 1; seed <= 150; seed++) {
        var cs = buildCase(seed);
        if (cs.segs.z.length < 2 || cs.segs.x.length < 2) continue;
        if (!visible(cs, cs.pts.right)) continue;
        var r = scene.rng(seed * 17);
        var lens = { fPx: cs.f, sigmaLn: 0.02 };
        var out = S.analyse({ lines: linesFrom(cs, 'zx', 0, r), lens: lens, size: { w: cs.w, h: cs.h }, trials: 0,
            measurements: [meas('pitch', 'xz', cs.pts.right, 0, r, 1)] });
        if (!out.cal.ok) { check('zx calibrates ' + seed, false, out.cal.need); continue; }
        n++;
        var e = Math.abs(out.results[0].value - cs.theta);
        if (e > worst) { worst = e; worstCase = 'seed ' + seed; }
    }
    console.log('noise-free, verticals + red, true lens: ' + n + ' cases, worst pitch error ' + worst.toFixed(6) + ' deg (' + worstCase + ')');
    check('zx exact with the true lens', worst < 0.01, worst);
})();

// ---------------------------------------------------------------- side wall (YZ) pitch
(function() {
    var worst = 0, n = 0;
    for (var seed = 1; seed <= 150; seed++) {
        var cs = buildCase(seed, { camX: 16 + (seed % 7) });
        if (cs.segs.z.length < 2 || cs.segs.y.length < 2 || cs.segs.x.length < 1) continue;
        if (!visible(cs, cs.pts.side)) continue;
        var r = scene.rng(seed * 13);
        var out = S.analyse({ lines: linesFrom(cs, 'zxy', 0, r), lens: { fPx: cs.f, sigmaLn: 0.02 }, size: { w: cs.w, h: cs.h }, trials: 0,
            measurements: [meas('pitch', 'yz', cs.pts.side, 0, r, 1)] });
        if (!out.cal.ok || !out.results[0].ok) continue;
        n++;
        worst = Math.max(worst, Math.abs(out.results[0].value - cs.theta2));
    }
    console.log('noise-free, side wall pitch on YZ: ' + n + ' cases, worst error ' + worst.toFixed(6) + ' deg');
    check('yz cases ran', n > 30, n);
    check('yz pitch exact', worst < 0.01, worst);
})();

// ---------------------------------------------------------------- noisy: error vs reported uncertainty
function noisyStudy(label, axes, lensSigma, lensErr, sigmaPx, plane, which, truthKey, opts) {
    var zs = [], errs = [], sigmas = [], raw = [], n = 0;
    for (var seed = 1; seed <= (opts && opts.cases || 120); seed++) {
        var cs = buildCase(1000 + (opts && opts.reps ? Math.floor((seed - 1) / opts.reps) + 1 : seed), opts && opts.scene);
        if (cs.segs.z.length < 2) continue;
        if (axes.indexOf('x') >= 0 && cs.segs.x.length < 2) continue;
        if (axes.indexOf('y') >= 0 && cs.segs.y.length < 2) continue;
        if (!visible(cs, cs.pts[which])) continue;
        var r = scene.rng(seed * 101);
        var lens = { fPx: cs.f * Math.exp(lensErr * r.gauss()), sigmaLn: lensSigma };
        var out = S.analyse({ lines: linesFrom(cs, axes, sigmaPx, r), lens: lens, size: { w: cs.w, h: cs.h }, trials: 120,
            measurements: [meas(which === 'apex' ? 'angle' : 'pitch', plane, cs.pts[which], sigmaPx, r, 1)] });
        if (!out.cal.ok || !out.results[0].ok || !out.results[0].sigma) continue;
        var truth = truthKey === 'apex' ? 180 - 2 * cs.theta : cs[truthKey];
        var e = out.results[0].value - truth;
        n++;
        errs.push(Math.abs(e));
        sigmas.push(out.results[0].sigma);
        zs.push(Math.abs(e) / out.results[0].sigma);
        raw.push(Math.abs(out.results[0].raw2d - truth));
    }
    function median(a) { var s = a.slice().sort(function(p, q) { return p - q; }); return s[Math.floor(s.length / 2)]; }
    function pct(a, q) { var s = a.slice().sort(function(p, q2) { return p - q2; }); return s[Math.floor(s.length * q)]; }
    var within2 = zs.filter(function(z) { return z < 2; }).length / Math.max(1, zs.length);  // the UI shows +/- 2 sigma
    console.log(label + ': ' + n + ' cases | median |err| ' + median(errs).toFixed(3) + ' deg, 95th pct ' + pct(errs, 0.95).toFixed(3) +
        ' | median sigma ' + median(sigmas).toFixed(3) + ' | within shown +/-: ' + (within2 * 100).toFixed(1) + '% | raw 2D median err ' + median(raw).toFixed(2) + ' deg');
    return { n: n, within2: within2, medianErr: median(errs), p95: pct(errs, 0.95) };
}

var a = noisyStudy('noisy 1px, zxy, auto lens (8% off, prior 12%)', 'zxy', 0.12, 0.08, 1.0, 'xz', 'right', 'theta');
check('zxy coverage', a.within2 > 0.88 && a.within2 <= 1, a.within2);
check('zxy median error < 0.5 deg', a.medianErr < 0.5, a.medianErr);
var b = noisyStudy('noisy 1px, zx only, auto lens', 'zx', 0.12, 0.08, 1.0, 'xz', 'right', 'theta');
check('zx coverage', b.within2 > 0.88, b.within2);
var c = noisyStudy('noisy 1px, zx, set lens (2%)', 'zx', 0.02, 0.01, 1.0, 'xz', 'right', 'theta');
check('zx set-lens coverage', c.within2 > 0.88, c.within2);
var d = noisyStudy('noisy 1px, zxy, apex angle', 'zxy', 0.12, 0.08, 1.0, 'xz', 'apex', 'apex');
check('apex coverage', d.within2 > 0.88, d.within2);
var e = noisyStudy('noisy 2px, zxy, auto lens', 'zxy', 0.12, 0.08, 2.0, 'xz', 'right', 'theta');
console.log('   (2px noise with 1px model: coverage expected to drop unless the variance factor adapts)');
check('2px coverage adapts via variance factor', e.within2 > 0.8, e.within2);

var o1 = noisyStudy('OBLIQUE noisy 1px, zxy, auto lens', 'zxy', 0.12, 0.08, 1.0, 'xz', 'right', 'theta', { scene: { oblique: true }, cases: 150 });
check('oblique zxy coverage', o1.within2 > 0.88, o1.within2);
var o2 = noisyStudy('OBLIQUE noisy 1px, zx, auto lens', 'zx', 0.12, 0.08, 1.0, 'xz', 'right', 'theta', { scene: { oblique: true }, cases: 150 });
check('oblique zx coverage', o2.within2 > 0.88, o2.within2);
var o3 = noisyStudy('OBLIQUE noisy 1px, zx, set lens 2%', 'zx', 0.02, 0.01, 1.0, 'xz', 'right', 'theta', { scene: { oblique: true }, cases: 150 });
check('oblique zx set-lens coverage', o3.within2 > 0.88, o3.within2);
var o4 = noisyStudy('CLOSE + tilted noisy 1px, zxy, auto lens', 'zxy', 0.12, 0.08, 1.0, 'xz', 'right', 'theta', { scene: { close: true }, cases: 600, reps: 4 });
check('close zxy coverage', o4.within2 > 0.88, o4.within2);
var o5 = noisyStudy('CLOSE + tilted noisy 1px, zx, auto lens', 'zx', 0.12, 0.08, 1.0, 'xz', 'right', 'theta', { scene: { close: true }, cases: 600, reps: 4 });
check('close zx coverage', o5.within2 > 0.88, o5.within2);

// ---------------------------------------------------------------- determinacy messages
(function() {
    var cs = buildCase(5);
    var r = scene.rng(5);
    var lens = { fPx: cs.f, sigmaLn: 0.12 };
    var onlyZ = S.calibrate(linesFrom(cs, 'z', 0, r), lens, { w: cs.w, h: cs.h });
    check('only verticals is not enough', !onlyZ.ok && /level lines/.test(onlyZ.need), onlyZ.need);
    var none = S.calibrate([], lens, { w: cs.w, h: cs.h });
    check('no lines asks for both', !none.ok && /verticals/.test(none.need), none.need);
    var zl = linesFrom(cs, 'z', 0, r).slice(0, 2).concat(linesFrom(cs, 'x', 0, r).slice(0, 1));
    var z2x1 = S.calibrate(zl, lens, { w: cs.w, h: cs.h });
    check('2 verticals + 1 level line calibrates', z2x1.ok, z2x1.need);
    var one = linesFrom(cs, 'z', 0, r).slice(0, 1).concat(linesFrom(cs, 'x', 0, r).slice(0, 1));
    var z1x1 = S.calibrate(one, lens, { w: cs.w, h: cs.h });
    check('1 + 1 lines is not enough', !z1x1.ok, z1x1.need);
    var m = S.measure(z2x1, { kind: 'pitch', plane: 'xy', pts: cs.pts.right });
    check('pitch on the ground plane is refused', !m.ok && m.reason === 'pitch-on-ground');
    var unc = S.measure(onlyZ, { kind: 'pitch', plane: 'xz', pts: cs.pts.right });
    check('uncalibrated measurement still gives the 2D angle', !unc.ok && unc.raw2d > 0);
})();

// ---------------------------------------------------------------- a bad line is flagged
(function() {
    var cs = buildCase(1011);
    var r = scene.rng(77);
    var lines = linesFrom(cs, 'zxy', 0.7, r);
    var bad = lines.filter(function(l) { return l.axis === 'x'; })[1];
    bad.b = { x: bad.b.x, y: bad.b.y + 40, prec: 1 };
    var cal = S.calibrate(lines, { fPx: cs.f, sigmaLn: 0.12 }, { w: cs.w, h: cs.h });
    var flagged = cal.lines.filter(function(d) { return d.flagged; });
    check('a line 40 px off is the one flagged', flagged.length >= 1 && flagged.some(function(d) { return d.id === bad.id; }), JSON.stringify(flagged.map(function(d) { return [d.id, d.residualPx.toFixed(1)]; })));
})();

// ---------------------------------------------------------------- horizon refusal
(function() {
    var cs = buildCase(12);
    var r = scene.rng(9);
    var cal = S.calibrate(linesFrom(cs, 'zxy', 0, r), { fPx: cs.f, sigmaLn: 0.12 }, { w: cs.w, h: cs.h });
    var vl = S.vanishingPoint(cal, 'x'), vz = S.vanishingPoint(cal, 'z');
    // ground plane: its vanishing line is the horizon; points above and below it
    var hz = S.vanishingPoint(cal, 'x');
    var horizonY = hz.w !== 0 ? hz.y / hz.w : 0;
    var m = S.measure(cal, { kind: 'angle', plane: 'xy', pts: [{ x: -100, y: horizonY - 300 }, { x: 0, y: horizonY + 300 }, { x: 100, y: horizonY + 400 }] });
    check('angle across the horizon is refused', !m.ok && m.reason === 'horizon', m.reason);
})();

console.log('\n' + passes + ' passed, ' + fails + ' failed');
process.exit(fails ? 1 : 0);
