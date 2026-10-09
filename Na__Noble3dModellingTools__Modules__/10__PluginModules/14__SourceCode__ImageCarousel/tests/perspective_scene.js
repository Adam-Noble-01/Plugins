/* Synthetic photos for the Perspective Angle tests.
 *
 * World: Z up, metres. A gable wall lies in the XZ plane at y = 0 (x 0..W), a
 * side wall in the YZ plane at x = W (y 0..D); the camera stands in front
 * (y < 0). Points are projected with the solver's own conventions: image
 * space from the centre, y down, camera x right / y down / z forward.
 */
'use strict';

function rng(seed) {
    var s = seed >>> 0, spare = null;
    function u() {
        s = (s + 0x6D2B79F5) >>> 0;
        var t = s;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    }
    return {
        u: u,
        range: function(a, b) { return a + (b - a) * u(); },
        gauss: function() {
            if (spare !== null) { var v = spare; spare = null; return v; }
            var u1 = 0; while (u1 <= 1e-12) u1 = u();
            var u2 = u(), m = Math.sqrt(-2 * Math.log(u1));
            spare = m * Math.sin(2 * Math.PI * u2);
            return m * Math.cos(2 * Math.PI * u2);
        }
    };
}

function dot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
function unit(a) { var n = Math.sqrt(dot(a, a)); return [a[0] / n, a[1] / n, a[2] / n]; }
function rotAbout(v, axis, ang) {
    var k = unit(axis), c = Math.cos(ang), s = Math.sin(ang), kd = dot(k, v), kx = cross(k, v);
    return [v[0] * c + kx[0] * s + k[0] * kd * (1 - c), v[1] * c + kx[1] * s + k[1] * kd * (1 - c), v[2] * c + kx[2] * s + k[2] * kd * (1 - c)];
}

// The camera starts looking along +y, turns by yaw about Z, tilts up about
// its right axis, then rolls about its forward axis.
function makeCamera(opt) {
    var yaw = opt.yawDeg * Math.PI / 180, tilt = opt.tiltDeg * Math.PI / 180, roll = (opt.rollDeg || 0) * Math.PI / 180;
    var fwd = [0, 1, 0], right = [1, 0, 0];
    fwd = rotAbout(fwd, [0, 0, 1], yaw); right = rotAbout(right, [0, 0, 1], yaw);
    fwd = rotAbout(fwd, right, tilt);
    right = rotAbout(right, fwd, roll);
    var down = cross(fwd, right);
    return { pos: opt.pos, fwd: unit(fwd), right: unit(right), down: unit(down), f: opt.f, w: opt.w, h: opt.h };
}

function project(cam, P) {
    var d = [P[0] - cam.pos[0], P[1] - cam.pos[1], P[2] - cam.pos[2]];
    var c = [dot(d, cam.right), dot(d, cam.down), dot(d, cam.fwd)];
    if (c[2] <= 0.05) return null;
    return { x: cam.f * c[0] / c[2], y: cam.f * c[1] / c[2] };
}

function inImage(cam, p, margin) {
    var m = margin || 0;
    return !!p && Math.abs(p.x) <= cam.w / 2 - m && Math.abs(p.y) <= cam.h / 2 - m;
}

// The world axes seen in camera space: the solver's frame for this camera.
function trueFrame(cam) {
    return {
        x: [cam.right[0], cam.down[0], cam.fwd[0]],
        y: [cam.right[1], cam.down[1], cam.fwd[1]],
        z: [cam.right[2], cam.down[2], cam.fwd[2]]
    };
}

// Project a 3D segment, keeping the part inside the image.
function segment(cam, A, B) {
    var pts = [];
    for (var i = 0; i <= 40; i++) {
        var t = i / 40;
        var p = project(cam, [A[0] + (B[0] - A[0]) * t, A[1] + (B[1] - A[1]) * t, A[2] + (B[2] - A[2]) * t]);
        if (inImage(cam, p, 4)) pts.push(p);
    }
    if (pts.length < 2) return null;
    var a = pts[0], b = pts[pts.length - 1];
    return Math.hypot(b.x - a.x, b.y - a.y) > 60 ? { a: a, b: b } : null;
}

// A random gabled box and camera. opt.oblique / opt.close pick harder views.
function buildCase(seed, opt) {
    opt = opt || {};
    var r = rng(seed);
    var W = r.range(6, 10), He = r.range(4, 6), D = r.range(6, 12);
    var theta = r.range(25, 60), theta2 = r.range(25, 55);
    var ridge = He + (W / 2) * Math.tan(theta * Math.PI / 180);
    var w = 4032, h = 3024;
    var f = opt.f || r.range(2400, 4200);
    var camX = opt.camX !== undefined ? opt.camX : r.range(-4, W + 14);
    var camY = -r.range(10, 26);
    if (opt.oblique) { camX = W + r.range(12, 22); camY = -r.range(5, 11); }
    if (opt.close)   { camX = W / 2 + r.range(-3, 3); camY = -r.range(5, 8); }
    var C = [camX, camY, r.range(1.3, 1.9)];
    var T = [W / 2 + r.range(-1.5, 1.5), r.range(0, D / 3), He * r.range(0.7, 1.1)];
    var d = [T[0] - C[0], T[1] - C[1], T[2] - C[2]];
    var yaw = Math.atan2(-d[0], d[1]) * 180 / Math.PI + r.range(-4, 4);
    var tilt = Math.atan2(d[2], Math.hypot(d[0], d[1])) * 180 / Math.PI + r.range(-3, 6);
    var roll = opt.roll !== undefined ? opt.roll : r.range(-2.5, 2.5);
    var cam = makeCamera({ pos: C, yawDeg: yaw, tiltDeg: tilt, rollDeg: roll, f: f, w: w, h: h });

    var segs = { z: [], x: [], y: [] };
    function add(axis, A, B) { var s = segment(cam, A, B); if (s) segs[axis].push(s); }
    add('z', [0, 0, 0.1], [0, 0, He]);
    add('z', [W, 0, 0.1], [W, 0, He]);
    add('z', [W, D, 0.1], [W, D, He]);
    add('z', [W / 2 - 0.45, 0, He + 0.5], [W / 2 - 0.45, 0, ridge + 1.2]);
    add('z', [W / 2 + 0.45, 0, He + 0.5], [W / 2 + 0.45, 0, ridge + 1.2]);
    for (var j = 0; j < 3; j++) { var xj = r.range(0.6, W - 0.6); add('z', [xj, 0, 0.9], [xj, 0, 2.3]); }
    add('x', [0.1, 0, 0.15], [W - 0.1, 0, 0.15]);
    add('x', [0.1, 0, He], [W - 0.1, 0, He]);
    add('x', [0.3, 0, 1.1], [W - 0.3, 0, 1.1]);
    add('x', [0.3, 0, 2.3], [W - 0.3, 0, 2.3]);
    add('y', [W, 0.1, 0.15], [W, D - 0.1, 0.15]);
    add('y', [W, 0.1, He], [W, D - 0.1, He]);
    add('y', [W, 0.3, 2.0], [W, D - 0.3, 2.0]);

    var t = Math.tan(theta * Math.PI / 180);
    var Ar = [W, 0, He], Br = [W / 2 + 0.6, 0, He + (W / 2 - 0.6) * t];
    var Al = [0, 0, He];
    var apex = [W / 2, 0, ridge];
    var A2 = [W, 0, He], B2 = [W, D / 2 - 0.5, He + (D / 2 - 0.5) * Math.tan(theta2 * Math.PI / 180)];
    var pts = {
        right: [project(cam, Ar), project(cam, Br)],
        apex : [project(cam, Al), project(cam, apex), project(cam, Ar)],
        side : [project(cam, A2), project(cam, B2)]
    };
    return { cam: cam, segs: segs, theta: theta, theta2: theta2, pts: pts, f: f, w: w, h: h };
}

function noisy(p, sigma, r) { return { x: p.x + sigma * r.gauss(), y: p.y + sigma * r.gauss(), prec: 1 }; }

function linesFrom(cs, axes, sigma, r) {
    var out = [], id = 1;
    axes.split('').forEach(function(axis) {
        cs.segs[axis].forEach(function(s) {
            out.push({ id: id++, axis: axis,
                a: sigma ? noisy(s.a, sigma, r) : { x: s.a.x, y: s.a.y, prec: 1 },
                b: sigma ? noisy(s.b, sigma, r) : { x: s.b.x, y: s.b.y, prec: 1 } });
        });
    });
    return out;
}

function visible(cs, list) {
    return list.every(function(p) { return p && inImage(cs.cam, p, 2); });
}

function meas(kind, plane, list, sigma, r, id) {
    return { id: id, kind: kind, plane: plane, pts: list.map(function(p) { return sigma ? noisy(p, sigma, r) : { x: p.x, y: p.y, prec: 1 }; }) };
}

// The house photo the UI test clicks on: a 47.5 degree gable seen steeply,
// so the photo shows its verge at about 60 degrees.
function house() {
    var W = 8, He = 5.2, D = 9, pitch = 47.5;
    var ridge = He + (W / 2) * Math.tan(pitch * Math.PI / 180);
    var cam = makeCamera({ pos: [W + 13, -7.5, 1.6], yawDeg: 52, tiltDeg: 12, rollDeg: 0.8, f: 3000, w: 4032, h: 3024 });
    function P(x, y, z) { return project(cam, [x, y, z]); }
    var polys = [
        { fill: '#b55a3c', pts: [P(0, 0, 0), P(W, 0, 0), P(W, 0, He), P(W / 2, 0, ridge), P(0, 0, He)] },
        { fill: '#9c4b33', pts: [P(W, 0, 0), P(W, D, 0), P(W, D, He), P(W, 0, He)] },
        { fill: '#c8642d', pts: [P(W + 0.3, -0.2, He - 0.3), P(W + 0.3, D, He - 0.3), P(W / 2, D, ridge), P(W / 2, -0.2, ridge)] }
    ];
    [[1.2, 2.4], [5.2, 6.4]].forEach(function(xs) {
        polys.push({ fill: '#d9ded8', pts: [P(xs[0], 0, 1.0), P(xs[1], 0, 1.0), P(xs[1], 0, 2.4), P(xs[0], 0, 2.4)] });
        polys.push({ fill: '#2b3238', pts: [P(xs[0] + 0.08, 0, 1.08), P(xs[1] - 0.08, 0, 1.08), P(xs[1] - 0.08, 0, 2.32), P(xs[0] + 0.08, 0, 2.32)] });
    });
    var lines = [];
    for (var z = 0.3; z < He; z += 0.3) {
        lines.push({ color: '#7d3a25', a: P(0, 0, z), b: P(W, 0, z) });
        lines.push({ color: '#6e3320', a: P(W, 0, z), b: P(W, D, z) });
    }
    for (z = He + 0.3; z < ridge - 0.2; z += 0.3) {
        var half = (ridge - z) / Math.tan(pitch * Math.PI / 180);
        lines.push({ color: '#7d3a25', a: P(W / 2 - half, 0, z), b: P(W / 2 + half, 0, z) });
    }
    var key = {
        verticals: [[P(0, 0, 0.05), P(0, 0, He)], [P(W, 0, 0.05), P(W, 0, He)], [P(W, D, 0.05), P(W, D, He)]],
        red      : [[P(0.05, 0, 0.3), P(W - 0.05, 0, 0.3)], [P(0.05, 0, He), P(W - 0.05, 0, He)]],
        green    : [[P(W, 0.05, 0.3), P(W, D - 0.05, 0.3)], [P(W, 0.05, He), P(W, D - 0.05, He)]],
        verge    : [P(W, 0, He), P(W / 2, 0, ridge)],
        apex     : [P(0, 0, He), P(W / 2, 0, ridge), P(W, 0, He)]
    };
    // Named points for the guide tests: window heads and sills on the gable
    // wall share heights; the side wall carries the same head height.
    var points = {
        headL1 : P(1.2, 0, 2.4), headL2 : P(2.4, 0, 2.4), headR1 : P(5.2, 0, 2.4), headR2 : P(6.4, 0, 2.4),
        sillR2 : P(6.4, 0, 1.0), sideHead1 : P(W, 2.5, 2.4), sideHead2 : P(W, 7.5, 2.4),
        eaves  : P(W, 0, He), apexPt : P(W / 2, 0, ridge),
        lowEaves : P(W, 0, 1.6), lowVerge : P(W / 2 + 0.8, 0, 1.6 + (W / 2 - 0.8) * Math.tan(pitch * Math.PI / 180)),
        sky    : P(W + 5, -1, 8.5)
    };
    return { w: 4032, h: 3024, pitch: pitch, f: 3000, polys: polys, lines: lines, key: key, points: points };
}

module.exports = {
    rng: rng, makeCamera: makeCamera, project: project, inImage: inImage, trueFrame: trueFrame, segment: segment,
    buildCase: buildCase, noisy: noisy, linesFrom: linesFrom, visible: visible, meas: meas, house: house
};
