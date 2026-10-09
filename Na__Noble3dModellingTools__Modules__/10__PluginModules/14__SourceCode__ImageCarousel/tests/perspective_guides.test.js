/* Perspective guides: geometry on synthetic photos with known cameras.
 *
 * node tests/perspective_guides.test.js
 * A guide is an infinite 3D line drawn in perspective. With the true camera,
 * a red guide through one point must pass exactly through every other point
 * at the same height on that wall; guides must cross where their 3D lines
 * meet; a guide stops at its vanishing point when that lies inside the photo.
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

function trueCal(cs) { return { ok: true, frame: scene.trueFrame(cs.cam), f: cs.f }; }
function onSeg(q, seg) { return seg ? S.closestOnSegment(q, seg).dist : Infinity; }
function add(P, d, k) { return [P[0] + d[0] * k, P[1] + d[1] * k, P[2] + d[2] * k]; }

// ---------------------------------------------------------------- axis guides pass through same-height / plumb points
(function() {
    var worst = { x: 0, y: 0, z: 0 }, n = { x: 0, y: 0, z: 0 };
    for (var seed = 1; seed <= 200; seed++) {
        var cs = scene.buildCase(seed);
        var cal = trueCal(cs), size = { w: cs.w, h: cs.h };
        var r = scene.rng(seed * 7);
        var tries = [
            { axis: 'x', P: [r.range(0.5, 7), 0, r.range(0.4, 4)], d: [1, 0, 0] },
            { axis: 'z', P: [r.range(0.5, 7), 0, r.range(0.4, 4)], d: [0, 0, 1] },
            { axis: 'y', P: [8, r.range(0.5, 6), r.range(0.4, 4)], d: [0, 1, 0] }
        ];
        tries.forEach(function(t) {
            var p = scene.project(cs.cam, t.P);
            if (!scene.inImage(cs.cam, p, 2)) return;
            var seg = S.guideSegment(p, S.vanishingPoint(cal, t.axis), size);
            [-3, -1.5, 1.2, 2.5].forEach(function(k) {
                var q = scene.project(cs.cam, add(t.P, t.d, k));
                if (!scene.inImage(cs.cam, q, 2)) return;
                n[t.axis]++;
                worst[t.axis] = Math.max(worst[t.axis], onSeg(q, seg));
            });
        });
    }
    console.log('axis guides: red ' + n.x + ' / green ' + n.y + ' / blue ' + n.z + ' points; worst miss ' +
        worst.x.toExponential(1) + ' / ' + worst.y.toExponential(1) + ' / ' + worst.z.toExponential(1) + ' px');
    check('red guides run through same-height points on the wall', n.x > 200 && worst.x < 1e-6, worst.x);
    check('green guides run through same-height points on the side wall', n.y > 100 && worst.y < 1e-6, worst.y);
    check('blue guides run through plumb points', n.z > 200 && worst.z < 1e-6, worst.z);
})();

// ---------------------------------------------------------------- a red and a blue guide cross where their 3D lines meet
(function() {
    var worst = 0, n = 0;
    for (var seed = 1; seed <= 200; seed++) {
        var cs = scene.buildCase(seed);
        var cal = trueCal(cs), size = { w: cs.w, h: cs.h };
        var r = scene.rng(seed * 11);
        var P1 = [r.range(0.5, 7), 0, r.range(0.4, 4)], P2 = [r.range(0.5, 7), 0, r.range(0.4, 4)];
        var p1 = scene.project(cs.cam, P1), p2 = scene.project(cs.cam, P2);
        var X = scene.project(cs.cam, [P2[0], 0, P1[2]]);
        if (!scene.inImage(cs.cam, p1, 2) || !scene.inImage(cs.cam, p2, 2) || !scene.inImage(cs.cam, X, 2)) continue;
        var red = S.guideSegment(p1, S.vanishingPoint(cal, 'x'), size);
        var blue = S.guideSegment(p2, S.vanishingPoint(cal, 'z'), size);
        var hit = red && blue ? S.segmentIntersection(red, blue) : null;
        if (!hit) { check('red and blue guides intersect (seed ' + seed + ')', false); continue; }
        n++;
        worst = Math.max(worst, Math.hypot(hit.x - X.x, hit.y - X.y));
    }
    console.log('guide intersections: ' + n + ' cases, worst ' + worst.toExponential(1) + ' px');
    check('guides cross where their 3D lines meet', n > 100 && worst < 1e-5, worst);
})();

// ---------------------------------------------------------------- a guide at the roof pitch runs from the eaves to the apex
(function() {
    var worst = 0, wrongSide = Infinity, n = 0;
    for (var seed = 1; seed <= 200; seed++) {
        var cs = scene.buildCase(seed);
        var cal = trueCal(cs), size = { w: cs.w, h: cs.h };
        var eaves = cs.pts.right[0], apex = cs.pts.apex[1];
        if (!scene.inImage(cs.cam, eaves, 2) || !scene.inImage(cs.cam, apex, 2)) continue;
        // the right verge rises toward -x, so side -1 on the red wall
        var up = S.guideSegment(eaves, S.directionVanishingPoint(cal, S.wallDirection(cal, 'xz', cs.theta, -1)), size);
        var other = S.guideSegment(eaves, S.directionVanishingPoint(cal, S.wallDirection(cal, 'xz', cs.theta, 1)), size);
        n++;
        worst = Math.max(worst, onSeg(apex, up));
        wrongSide = Math.min(wrongSide, onSeg(apex, other));
    }
    console.log('pitch guides: ' + n + ' cases, worst miss at the apex ' + worst.toExponential(1) + ' px; mirror guide misses by at least ' + wrongSide.toFixed(0) + ' px');
    check('a guide at the true pitch hits the apex', n > 100 && worst < 1e-5, worst);
    check('its mirror image does not', wrongSide > 20, wrongSide);
})();

// ---------------------------------------------------------------- parallel to a measured pitch
(function() {
    var worst = 0, n = 0;
    for (var seed = 1; seed <= 150; seed++) {
        var cs = scene.buildCase(seed);
        var cal = trueCal(cs), size = { w: cs.w, h: cs.h };
        if (!scene.visible(cs, cs.pts.right)) continue;
        var res = S.measure(cal, { kind: 'pitch', plane: 'xz', pts: cs.pts.right });
        var d = S.measurementDirection(res);
        if (!d) continue;
        // The same slope lower down the wall: shift both ends of the measured
        // verge down (camera space) and the parallel guide through the lower
        // shifted end must run through the upper one.
        var up = cal.frame.z, X = res.draw.X;
        var drop = 0.3 * S.vec.len(S.vec.sub(X[1], X[0]));
        var lo = S.project(cal, S.vec.sub(X[res.draw.lo], S.vec.scale(up, drop)));
        var hi = S.project(cal, S.vec.sub(X[res.draw.hi], S.vec.scale(up, drop)));
        if (!scene.inImage(cs.cam, lo, 2) || !scene.inImage(cs.cam, hi, 2)) continue;
        var seg = S.guideSegment(lo, S.directionVanishingPoint(cal, d), size);
        n++;
        worst = Math.max(worst, onSeg(hi, seg));
    }
    check('a guide parallel to a pitch, lower down the wall, keeps its slope', n > 80 && worst < 1e-5, [n, worst]);
})();

// ---------------------------------------------------------------- vanishing point inside the photo ends the guide
(function() {
    var cam = scene.makeCamera({ pos: [4, -12, 1.6], yawDeg: 0, tiltDeg: 0, rollDeg: 0, f: 3000, w: 4032, h: 3024 });
    var cal = { ok: true, frame: scene.trueFrame(cam), f: 3000 };
    var vp = S.vanishingPoint(cal, 'y');
    check('looking along +y puts the green vanishing point at the centre', Math.abs(vp.x / vp.w) < 1e-9 && Math.abs(vp.y / vp.w) < 1e-9, vp);
    var p = scene.project(cam, [8, 6, 3]);
    var seg = S.guideSegment(p, vp, { w: 4032, h: 3024 });
    var endsAtVp = Math.min(Math.hypot(seg.a.x, seg.a.y), Math.hypot(seg.b.x, seg.b.y));
    check('the guide stops at its vanishing point', endsAtVp < 1e-6, endsAtVp);
    var far = scene.project(cam, [8, 40, 3]);
    check('and still runs through points far along it', onSeg(far, seg) < 1e-6, onSeg(far, seg));
})();

// ---------------------------------------------------------------- inference picks the axis being followed
(function() {
    var ok = 0, n = 0, noneOk = 0, noneN = 0;
    for (var seed = 1; seed <= 120; seed++) {
        var cs = scene.buildCase(seed);
        var cal = trueCal(cs);
        var cands = ['x', 'y', 'z'].map(function(a) { return { key: a, vp: S.vanishingPoint(cal, a) }; });
        var P = [4, 0, 2];
        var p = scene.project(cs.cam, P);
        if (!scene.inImage(cs.cam, p, 2)) continue;
        [['x', [1, 0, 0]], ['z', [0, 0, 1]], ['y', [0, 1, 0]]].forEach(function(t) {
            var q = scene.project(cs.cam, add(P, t[1], 0.8));
            if (!q || Math.hypot(q.x - p.x, q.y - p.y) < 40) return;
            n++;
            var inf = S.inferGuide(p, q, cands, 10);
            if (inf && inf.candidate.key === t[0]) ok++;
        });
        // a direction well away from every axis infers nothing
        var dirs = cands.map(function(c) { return Math.atan2(c.vp.y - c.vp.w * p.y, c.vp.x - c.vp.w * p.x); });
        for (var a = 0; a < 180; a += 1) {
            var ang = a * Math.PI / 180;
            var clear = dirs.every(function(dd) { var diff = Math.abs(((ang - dd) % Math.PI + Math.PI) % Math.PI); return Math.min(diff, Math.PI - diff) > 25 * Math.PI / 180; });
            if (!clear) continue;
            noneN++;
            if (!S.inferGuide(p, { x: p.x + 200 * Math.cos(ang), y: p.y + 200 * Math.sin(ang) }, cands, 10)) noneOk++;
            break;
        }
    }
    check('dragging along an axis infers that axis', n > 200 && ok / n > 0.97, [ok, n]);
    check('dragging away from every axis infers nothing', noneN > 50 && noneOk === noneN, [noneOk, noneN]);
})();

// ---------------------------------------------------------------- free guides
(function() {
    var size = { w: 4032, h: 3024 };
    var seg = S.freeSegment({ x: -100, y: 50 }, { x: 300, y: 250 }, size);
    check('a free guide runs through both points', onSeg({ x: -100, y: 50 }, seg) < 1e-9 && onSeg({ x: 300, y: 250 }, seg) < 1e-9);
    var touches = [seg.a, seg.b].every(function(q) { return Math.abs(Math.abs(q.x) - 2016) < 1e-6 || Math.abs(Math.abs(q.y) - 1512) < 1e-6; });
    check('and reaches the edges of the photo', touches, seg);
    check('a zero-length free guide is refused', S.freeSegment({ x: 1, y: 1 }, { x: 1, y: 1 }, size) === null);
})();

console.log('\n' + passes + ' passed, ' + fails + ' failed');
process.exit(fails ? 1 : 0);
