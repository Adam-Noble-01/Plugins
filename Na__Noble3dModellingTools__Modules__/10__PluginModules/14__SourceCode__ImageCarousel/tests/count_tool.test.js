/* Count tool: perspective division on synthetic photos with known cameras.
 *
 * node tests/count_tool.test.js
 * A line divided into n equal parts on the building must put its ticks
 * exactly where the equally spaced 3D points are seen, from nothing but
 * the two clicked ends and the vanishing point of the line's direction.
 * Also covers spacing set by hand (a dragged tick), the round trips the
 * tool relies on, and the vanishing point of one colour of lines alone.
 */
'use strict';
var path = require('path');
var S = require(path.resolve(__dirname, '..', 'Na__Noble3dModellingTools__ImageCarousel__PerspectiveSolver__.js'));
var scene = require('./perspective_scene.js');

var passes = 0, fails = 0;
function check(name, cond, detail) {
    if (cond) passes++;
    else { fails++; console.log('FAIL  ' + name + (detail !== undefined ? '  ' + JSON.stringify(detail) : '')); }
}

function camDir(cam, d) { return [d[0] * cam.right[0] + d[1] * cam.right[1] + d[2] * cam.right[2], d[0] * cam.down[0] + d[1] * cam.down[1] + d[2] * cam.down[2], d[0] * cam.fwd[0] + d[1] * cam.fwd[1] + d[2] * cam.fwd[2]]; }
function vpOf(cam, d) { var c = camDir(cam, d); return { x: cam.f * c[0], y: cam.f * c[1], w: c[2] }; }
function along(P, d, s) { return [P[0] + d[0] * s, P[1] + d[1] * s, P[2] + d[2] * s]; }
function dist(p, q) { return Math.hypot(p.x - q.x, p.y - q.y); }
function median(a) { var s = a.slice().sort(function(p, q) { return p - q; }); return s.length ? s[Math.floor(s.length / 2)] : NaN; }

// ---------------------------------------------------------------- ticks land on equally spaced 3D points
(function() {
    var worst = 0, cases = 0, flatParts = [], flatWorstParts = 0;
    for (var seed = 1; seed <= 200; seed++) {
        var cs = scene.buildCase(seed);
        var r = scene.rng(seed * 13);
        var dirs = [[1, 0, 0], [0, 1, 0], [0, 0, 1], [0.6, 0.3, 0.74]];
        dirs.forEach(function(d0) {
            var dl = Math.hypot(d0[0], d0[1], d0[2]), d = [d0[0] / dl, d0[1] / dl, d0[2] / dl];
            var P0 = [r.range(0.5, 7), r.range(0, 4), r.range(0.3, 3)];
            var len = r.range(1.5, 5), n = 5 + Math.floor(r.u() * 30);
            var a = scene.project(cs.cam, P0), b = scene.project(cs.cam, along(P0, d, len));
            if (!scene.inImage(cs.cam, a, 2) || !scene.inImage(cs.cam, b, 2) || dist(a, b) < 200) return;
            var k = S.countDepthRatio(a, b, vpOf(cs.cam, d));
            if (!k) { check('a real line has a depth ratio (seed ' + seed + ')', false); return; }
            var ticks = S.countTicks(a, b, n, k), flat = S.countTicks(a, b, n, 1);
            var partPx = dist(a, b) / n, flatMiss = 0;
            for (var j = 0; j <= n; j++) {
                var q = scene.project(cs.cam, along(P0, d, len * j / n));
                worst = Math.max(worst, dist(ticks[j], q));
                flatMiss = Math.max(flatMiss, dist(flat[j], q));
            }
            flatParts.push(flatMiss / partPx);
            flatWorstParts = Math.max(flatWorstParts, flatMiss / partPx);
            cases++;
        });
    }
    console.log('perspective ticks: ' + cases + ' lines, worst miss ' + worst.toExponential(1) + ' px; even spacing would miss by up to ' +
        flatWorstParts.toFixed(2) + ' of a part (median ' + median(flatParts).toFixed(2) + ')');
    check('ticks land exactly on the equally spaced points', cases > 400 && worst < 1e-6, worst);
    check('even spacing on the photo is visibly wrong in perspective', flatWorstParts > 0.3, flatWorstParts);
})();

// ---------------------------------------------------------------- the house: 15 courses up the corner
(function() {
    var house = scene.house();
    var cam = scene.makeCamera({ pos: [8 + 13, -7.5, 1.6], yawDeg: 52, tiltDeg: 12, rollDeg: 0.8, f: 3000, w: 4032, h: 3024 });
    var a = scene.project(cam, [8, 0, 0.3]), b = scene.project(cam, [8, 0, 4.8]);
    var k = S.countDepthRatio(a, b, vpOf(cam, [0, 0, 1]));
    var ticks = S.countTicks(a, b, 15, k), flat = S.countTicks(a, b, 15, 1), worstT = 0, worstF = 0;
    for (var j = 0; j <= 15; j++) {
        var q = scene.project(cam, [8, 0, 0.3 + 0.3 * j]);
        worstT = Math.max(worstT, dist(ticks[j], q));
        worstF = Math.max(worstF, dist(flat[j], q));
    }
    console.log('house corner, 15 courses: perspective ticks miss by ' + worstT.toExponential(1) + ' px, even ticks by ' + worstF.toFixed(1) + ' px (courses ' + (dist(a, b) / 15).toFixed(0) + ' px apart)');
    check('the house corner courses are matched exactly', worstT < 1e-6, worstT);
    check('the house test scene has visible perspective along its corner', worstF > 3, worstF);
    check('house points agree with the scene module', dist(a, house.key.verticals[1][0]) < 400);
})();

// ---------------------------------------------------------------- round trips
(function() {
    var r = scene.rng(77), worstT = 0, worstK = 0, worstTaper = 0;
    for (var i = 0; i < 2000; i++) {
        var k = Math.exp(r.range(-2.4, 2.4)), t = r.range(0, 1);
        worstT = Math.max(worstT, Math.abs(S.countParameter(k, S.countPosition(k, t)) - t));
        var a = { x: r.range(-2000, 2000), y: r.range(-1500, 1500) }, b = { x: r.range(-2000, 2000), y: r.range(-1500, 1500) };
        if (dist(a, b) < 50) continue;
        worstK = Math.max(worstK, Math.abs(S.countDepthRatio(a, b, S.countVanishingPoint(a, b, k)) / k - 1));
        var n = 2 + Math.floor(r.u() * 40), j = 1 + Math.floor(r.u() * (n - 1)), s = r.range(0.02, 0.98);
        var kt = S.countTaper(n, j, s);
        worstTaper = Math.max(worstTaper, Math.abs(S.countPosition(kt, j / n) - s));
    }
    check('photo fraction and real fraction convert both ways', worstT < 1e-12, worstT);
    check('a stored vanishing point gives back its depth ratio', worstK < 1e-9, worstK);
    check('a dragged tick lands where it is dropped', worstTaper < 1e-12, worstTaper);

    var a0 = { x: 0, y: 0 }, b0 = { x: 0, y: -1000 };
    check('a vanishing point far along the line means even spacing', Math.abs(S.countDepthRatio(a0, b0, { x: 0, y: -1, w: 0 }) - 1) < 1e-12);
    check('a vanishing point between the ends is refused', S.countDepthRatio(a0, b0, { x: 0, y: -400, w: 1 }) === null);
    check('beyond the far end the far end is deeper', S.countDepthRatio(a0, b0, { x: 0, y: -3000, w: 1 }) > 1);
    check('behind the start the start is deeper', S.countDepthRatio(a0, b0, { x: 0, y: 2000, w: 1 }) < 1);
    check('the homogeneous sign does not matter', Math.abs(S.countDepthRatio(a0, b0, { x: 0, y: 3000, w: -1 }) - S.countDepthRatio(a0, b0, { x: 0, y: -3000, w: 1 })) < 1e-12);
    check('a photo point past the vanishing point has no real fraction', S.countParameter(3, 1.6) === Infinity);
    check('a tick cannot be dropped on an end', S.countTaper(10, 4, 0) === null && S.countTaper(10, 4, 1) === null && S.countTaper(10, 0, 0.5) === null);
    var even = S.countTicks(a0, b0, 4, 1);
    check('even spacing at k = 1', even.every(function(p, j) { return Math.abs(p.y + 250 * j) < 1e-9 && p.x === 0; }));
    check('line fraction is unclamped', Math.abs(S.lineFraction(a0, b0, { x: 30, y: 500 }) + 0.5) < 1e-12);
})();

// ---------------------------------------------------------------- one colour of lines on its own
(function() {
    var worstDeg = 0, worstTick = 0, cases = 0;
    for (var seed = 1; seed <= 200; seed++) {
        var cs = scene.buildCase(seed);
        if (cs.segs.z.length < 2) continue;
        var r = scene.rng(seed * 5);
        var lines = scene.linesFrom(cs, 'z', 0.8, r).slice(0, 2);
        var vp = S.axisVanishingPoint(lines, 'z', { w: cs.w, h: cs.h });
        if (!vp) { check('two verticals give a vanishing point (seed ' + seed + ')', false); continue; }
        var truth = vpOf(cs.cam, [0, 0, 1]);
        var u = [vp.x, vp.y, vp.w * cs.f], v = [truth.x, truth.y, truth.w * cs.f];
        var cosang = Math.abs(u[0] * v[0] + u[1] * v[1] + u[2] * v[2]) / (Math.hypot(u[0], u[1], u[2]) * Math.hypot(v[0], v[1], v[2]));
        worstDeg = Math.max(worstDeg, Math.acos(Math.min(1, cosang)) * 180 / Math.PI);
        var P0 = [r.range(1, 6), 0, 0.4], a = scene.project(cs.cam, P0), b = scene.project(cs.cam, [P0[0], 0, 3.4]);
        if (!scene.inImage(cs.cam, a, 2) || !scene.inImage(cs.cam, b, 2)) continue;
        var k = S.countDepthRatio(a, b, vp);
        if (!k) continue;
        var ticks = S.countTicks(a, b, 10, k);
        for (var j = 0; j <= 10; j++) worstTick = Math.max(worstTick, dist(ticks[j], scene.project(cs.cam, [P0[0], 0, 0.4 + 0.3 * j])));
        cases++;
    }
    console.log('two verticals alone: ' + cases + ' counts, direction off by up to ' + worstDeg.toFixed(2) + ' deg, ticks miss by up to ' + worstTick.toFixed(2) + ' px');
    check('two drawn verticals space a vertical count to within a pixel', cases > 100 && worstTick < 1, worstTick);

    var one = [{ axis: 'z', a: { x: 0, y: 0, prec: 1 }, b: { x: 10, y: -900, prec: 1 } }];
    check('one line is not enough', S.axisVanishingPoint(one, 'z', { w: 4032, h: 3024 }) === null);
    var twice = one.concat([{ axis: 'z', a: { x: 0, y: 0, prec: 1 }, b: { x: 10, y: -900, prec: 1 } }]);
    check('the same edge drawn twice is not enough', S.axisVanishingPoint(twice, 'z', { w: 4032, h: 3024 }) === null);
    check('other colours are ignored', S.axisVanishingPoint(one.concat([{ axis: 'x', a: { x: 0, y: 0, prec: 1 }, b: { x: 900, y: 10, prec: 1 } }]), 'z', { w: 4032, h: 3024 }) === null);
})();

// ---------------------------------------------------------------- dimensions from a reference along the count
// 15 courses of 300 mm up the middle of the gable. A reference on the
// count's own line (two of its ticks, say) is read exactly at any height; a
// flat reading is not. Beside the count, on this steeply seen wall, the
// reference is nearer or farther than the count, so it is read approximately.
(function() {
    var cam = scene.house().cam;
    function P(x, y, z) { return scene.project(cam, [x, y, z]); }
    var a = P(4, 0, 0.3), b = P(4, 0, 4.8);
    var k = S.countDepthRatio(a, b, vpOf(cam, [0, 0, 1]));
    var heights = [[0.3, 0.6], [2.4, 2.7], [4.5, 4.8], [0.3, 1.5]];
    function worst(x) {
        var w = { read: 0, flat: 0 };
        heights.forEach(function(zs) {
            var ra = P(x, 0, zs[0]), rb = P(x, 0, zs[1]), mm = (zs[1] - zs[0]) * 1000;
            var read = S.countReferenceLength(a, b, k, ra, rb, mm);
            var flat = dist(a, b) / (dist(ra, rb) / mm);
            w.read = Math.max(w.read, read ? Math.abs(read / 4500 - 1) : Infinity);
            w.flat = Math.max(w.flat, Math.abs(flat / 4500 - 1));
        });
        return w;
    }
    var on = worst(4), beside = worst(3.5);
    console.log('reference on the count: read along it within ' + (on.read * 100).toFixed(4) + '%, read flat off by up to ' + (on.flat * 100).toFixed(1) + '%');
    console.log('reference 0.5 m beside it: read along it within ' + (beside.read * 100).toFixed(1) + '%, read flat off by up to ' + (beside.flat * 100).toFixed(1) + '%');
    check('a reference on the count line gives its length exactly, in perspective', on.read < 1e-6, on.read);
    check('a flat reading is off with this perspective', on.flat > 0.02, on.flat);
    check('a reference beside the count reads closer than flat', beside.read < 0.03 && beside.read < beside.flat, beside);

    var a2 = { x: 0, y: 0 }, b2 = { x: 0, y: -1000 };
    check('a reference across the count is not read along it', S.countReferenceLength(a2, b2, 1.3, { x: -40, y: -300 }, { x: 40, y: -300 }, 300) === null);
    check('a reference far from the count is not read along it', S.countReferenceLength(a2, b2, 1.3, { x: 500, y: -300 }, { x: 500, y: -360 }, 300) === null);
    check('a reference past the ends of the count is not read along it', S.countReferenceLength(a2, b2, 1.3, { x: 20, y: -1400 }, { x: 20, y: -1460 }, 300) === null);
    var even = S.countReferenceLength(a, b, 1, P(3.5, 0, 0.3), P(3.5, 0, 0.6), 300);
    check('with even spacing the reference reads as the flat scale', Math.abs(even / (dist(a, b) / (dist(P(3.5, 0, 0.3), P(3.5, 0, 0.6)) / 300)) - 1) < 0.01, even);
})();

console.log('\n' + passes + ' passed, ' + fails + ' failed');
process.exit(fails ? 1 : 0);
