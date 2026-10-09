/* =============================================================================
   NA PROFILE TOOLS - DRAW PROFILE - GEOMETRY
   =============================================================================
   FILE       : Na__ProfileTools__DrawProfile__Geometry__.js
   NAMESPACE  : window.Na__DrawProfile__Geom
   PURPOSE    : The exact 2D maths behind the Draw Profile editor: lines, arcs
                and circles, where they meet, how they split, offset and are
                rounded or cut at a corner.

   ENTITIES (world millimetres, y up)
     line    { type:'line',   a:{x,y}, b:{x,y} }
     arc     { type:'arc',    a:{x,y}, b:{x,y}, sw, segs }
             sw is the signed sweep from a to b in radians, CCW positive,
             0 < |sw| < 2 pi. The ends are stored exactly, so an arc drawn
             between two snaps ends ON them, and moving one end keeps the
             sweep: the arc stays an arc (a DXF bulge, in effect).
     circle  { type:'circle', c:{x,y}, r, segs }
     segs    0 means automatic (Na__DrawProfile__Geom.SegmentsFor).

   PARAMETERS
     t runs 0..1 along a line or an arc from a to b, and 0..1 once round a
     circle from angle 0, CCW.

   @delegate  : TrueVision Layout Editor 37__System__VectorTools
                Curves__   SegmentsFor, ArcSegmentsFor, CircleThrough,
                           ArcThrough, CarrySweep, Describe (ported, y up)
                Offset__   CornerFillet, CornerChamfer (ported verbatim),
                           MitreLimit
                Geometry__ the touch rule: an edge that stops ON another
                           crosses it; parallel edges never cross
   ============================================================================= */

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Constants
    // -------------------------------------------------------------------------

    var TAU         = Math.PI * 2;
    var SAME_MM     = 1e-6;
    var TOUCH_MM    = 1e-4;
    var MIN_RADIUS  = 1e-4;
    var MITRE_LIMIT = 4;

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Points and Vectors
    // -------------------------------------------------------------------------

    function P(x, y)          { return { x : x, y : y }; }
    function Copy(p)          { return { x : p.x, y : p.y }; }
    function Add(p, q)        { return { x : p.x + q.x, y : p.y + q.y }; }
    function Sub(p, q)        { return { x : p.x - q.x, y : p.y - q.y }; }
    function Mul(p, k)        { return { x : p.x * k, y : p.y * k }; }
    function Dot(p, q)        { return (p.x * q.x) + (p.y * q.y); }
    function Cross(p, q)      { return (p.x * q.y) - (p.y * q.x); }
    function Len(p)           { return Math.hypot(p.x, p.y); }
    function Dist(p, q)       { return Math.hypot(p.x - q.x, p.y - q.y); }
    function Lerp(p, q, t)    { return { x : p.x + ((q.x - p.x) * t), y : p.y + ((q.y - p.y) * t) }; }
    function Mid(p, q)        { return { x : (p.x + q.x) / 2, y : (p.y + q.y) / 2 }; }
    function Same(p, q, tol)  { return Dist(p, q) <= (tol === undefined ? SAME_MM : tol); }
    function Left(v)          { return { x : -v.y, y : v.x }; }           // the left-hand normal, y up

    function Unit(v) {
        var l = Len(v);
        return l > 0 ? { x : v.x / l, y : v.y / l } : { x : 0, y : 0 };
    }

    function NormAngle(a) {
        var r = a % TAU;
        return r < 0 ? r + TAU : r;
    }

    function Rotate(p, centre, angle) {
        var c = Math.cos(angle), s = Math.sin(angle);
        var dx = p.x - centre.x, dy = p.y - centre.y;
        return { x : centre.x + (dx * c) - (dy * s), y : centre.y + (dx * s) + (dy * c) };
    }

    function ScaleAbout(p, centre, k) {
        return { x : centre.x + ((p.x - centre.x) * k), y : centre.y + ((p.y - centre.y) * k) };
    }

    // The point reflected across the line through a and b.
    function MirrorPoint(p, a, b) {
        var d = Unit(Sub(b, a));
        var v = Sub(p, a);
        var along = Dot(v, d);
        var foot = Add(a, Mul(d, along));
        return { x : (2 * foot.x) - p.x, y : (2 * foot.y) - p.y };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Segment Counts (TV VectorTools Curves)
    // -------------------------------------------------------------------------

    // The flat of an edge stands r * (1 - cos(pi / n)) off the true curve, so
    // n = pi / acos(1 - tolerance / r), rounded UP to a multiple of four so the
    // quadrant points are real vertices, and held between the two limits.
    function SegmentsFor(radiusMm, toleranceMm, minimum, maximum) {
        var min = Math.max(4, Math.round(Number.isFinite(minimum) ? minimum : 24));
        var max = Math.max(min, Math.round(Number.isFinite(maximum) ? maximum : 360));
        var tol = (Number.isFinite(toleranceMm) && toleranceMm > 0) ? toleranceMm : 0.01;
        var n = min;
        if (Number.isFinite(radiusMm) && radiusMm > tol) n = Math.ceil(Math.PI / Math.acos(1 - (tol / radiusMm)));
        n = Math.max(min, Math.min(max, n));
        return Math.min(max - (max % 4), Math.ceil(n / 4) * 4) || 4;
    }

    // An arc's share of the whole circle's count.
    function ArcSegmentsFor(radiusMm, sweepRad, toleranceMm, minimum, maximum) {
        var whole = SegmentsFor(radiusMm, toleranceMm, minimum, maximum);
        return Math.max(2, Math.ceil(whole * (Math.min(TAU, Math.abs(sweepRad)) / TAU)));
    }

    // What an entity is divided into: its own count, else the automatic one.
    function EntitySegments(e, curves) {
        if (!e || e.type === 'line') return 1;
        var cfg = curves || {};
        if (e.type === 'circle') {
            if (e.segs >= 3) return Math.round(e.segs);
            return SegmentsFor(e.r, cfg.ToleranceMm, cfg.MinWhole, cfg.MaxWhole);
        }
        if (e.segs >= 1) return Math.round(e.segs);
        var g = ArcGeom(e);
        return g ? ArcSegmentsFor(g.r, g.sw, cfg.ToleranceMm, cfg.MinWhole, cfg.MaxWhole) : 1;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Arcs: Ends + Sweep <-> Centre + Radius
    // -------------------------------------------------------------------------

    // { c, r, a0, sw } for an arc entity, or null when it has no chord or no
    // sweep. The centre lies (L/2) / tan(sw/2) along the chord's left normal,
    // which puts it left of a CCW minor arc and right of a CCW major one.
    function ArcGeom(e) {
        var dx = e.b.x - e.a.x, dy = e.b.y - e.a.y;
        var chord = Math.hypot(dx, dy);
        var half = e.sw / 2;
        var s = Math.sin(half);
        if (!(chord > SAME_MM) || Math.abs(s) < 1e-12) return null;
        var r = (chord / 2) / Math.abs(s);
        var h = (chord / 2) * Math.cos(half) / s;
        var c = { x : ((e.a.x + e.b.x) / 2) - ((dy / chord) * h), y : ((e.a.y + e.b.y) / 2) + ((dx / chord) * h) };
        return { c : c, r : r, a0 : Math.atan2(e.a.y - c.y, e.a.x - c.x), sw : e.sw };
    }

    // An arc entity about a centre: radius, start angle and signed sweep.
    function ArcFromCentre(c, r, a0, sw, segs) {
        return {
            type : 'arc',
            a    : { x : c.x + (r * Math.cos(a0)), y : c.y + (r * Math.sin(a0)) },
            b    : { x : c.x + (r * Math.cos(a0 + sw)), y : c.y + (r * Math.sin(a0 + sw)) },
            sw   : sw,
            segs : segs || 0
        };
    }

    // How far a point stands off the chord a -> b, positive to the LEFT.
    function SagittaOf(a, b, p) {
        var chord = Dist(a, b);
        if (!(chord > 0)) return 0;
        return Cross(Sub(b, a), Sub(p, a)) / chord;
    }

    // The sweep of the arc on a chord that bulges `s` off its middle (left
    // positive). A bulge to the left is travelled clockwise: sw = -4 atan(2s/L).
    function SweepFromSagitta(chord, s) {
        if (!(chord > 0)) return 0;
        return -4 * Math.atan((2 * s) / chord);
    }

    function SagittaFromSweep(chord, sw) {
        return -(chord / 2) * Math.tan(sw / 4);
    }

    // The bulge giving a chord a radius: the minor arc unless `major`, on the
    // side `sign` names (left positive). Null when the radius cannot span it.
    function SagittaForRadius(chord, radius, sign, major) {
        if (!(chord > 0) || !(radius >= (chord / 2) - 1e-9)) return null;
        var root = Math.sqrt(Math.max(0, (radius * radius) - ((chord * chord) / 4)));
        var s = major ? radius + root : radius - root;
        return (sign < 0 ? -1 : 1) * s;
    }

    // TV Curves: the circle through three points (null when in a line).
    function CircleThrough(a, b, c) {
        var d = 2 * ((a.x * (b.y - c.y)) + (b.x * (c.y - a.y)) + (c.x * (a.y - b.y)));
        var span = Math.max(Dist(a, b), Dist(a, c), Dist(b, c));
        if (!(span > 0) || Math.abs(d) < 1e-10 * span * span) return null;
        var a2 = (a.x * a.x) + (a.y * a.y), b2 = (b.x * b.x) + (b.y * b.y), c2 = (c.x * c.x) + (c.y * c.y);
        var cx = ((a2 * (b.y - c.y)) + (b2 * (c.y - a.y)) + (c2 * (a.y - b.y))) / d;
        var cy = ((a2 * (c.x - b.x)) + (b2 * (a.x - c.x)) + (c2 * (b.x - a.x))) / d;
        return { c : { x : cx, y : cy }, r : Math.hypot(a.x - cx, a.y - cy) };
    }

    // TV Curves: the arc from `from` to `to` passing through `through`, as
    // { c, r, a0, sw } with sw signed the way round that passes through it.
    function ArcThrough(from, through, to) {
        var circle = CircleThrough(from, through, to);
        if (!circle || !(circle.r >= MIN_RADIUS)) return null;
        var a0 = Math.atan2(from.y - circle.c.y, from.x - circle.c.x);
        var aM = Math.atan2(through.y - circle.c.y, through.x - circle.c.x);
        var a1 = Math.atan2(to.y - circle.c.y, to.x - circle.c.x);
        var round  = NormAngle(a1 - a0);
        var middle = NormAngle(aM - a0);
        var sweep  = middle <= round ? round : round - TAU;
        return { c : circle.c, r : circle.r, a0 : a0, sw : sweep };
    }

    // TV Curves: a sweep carried on from the last one, so a centre arc can be
    // dragged past a half turn without flipping to the short way round.
    function CarrySweep(lastSweep, startRad, cursorRad) {
        var sweep = cursorRad - startRad;
        while (sweep > Math.PI)  sweep -= TAU;
        while (sweep < -Math.PI) sweep += TAU;
        if (Number.isFinite(lastSweep)) {
            while (sweep - lastSweep > Math.PI)  sweep -= TAU;
            while (sweep - lastSweep < -Math.PI) sweep += TAU;
        }
        return Math.max(-TAU + 1e-6, Math.min(TAU - 1e-6, sweep));
    }

    // Is an angle inside an arc's sweep? Returns its parameter 0..1, or null.
    function AngleParam(g, angle, tolAngle) {
        var tol = tolAngle || 0;
        var span = Math.abs(g.sw);
        var d = g.sw >= 0 ? NormAngle(angle - g.a0) : NormAngle(g.a0 - angle);
        if (d <= span + tol) return Math.min(1, d / span);
        if (d >= TAU - tol) return 0;
        return null;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Evaluating an Entity
    // -------------------------------------------------------------------------

    function EndPoints(e) {
        if (!e || e.type === 'circle') return null;
        return [ e.a, e.b ];
    }

    function PointAt(e, t) {
        if (e.type === 'line') {
            if (t <= 0) return Copy(e.a);
            if (t >= 1) return Copy(e.b);
            return Lerp(e.a, e.b, t);
        }
        if (e.type === 'arc') {
            if (t <= 0) return Copy(e.a);
            if (t >= 1) return Copy(e.b);
            var g = ArcGeom(e);
            if (!g) return Lerp(e.a, e.b, t);
            var ang = g.a0 + (g.sw * t);
            return { x : g.c.x + (g.r * Math.cos(ang)), y : g.c.y + (g.r * Math.sin(ang)) };
        }
        var ca = TAU * t;
        return { x : e.c.x + (e.r * Math.cos(ca)), y : e.c.y + (e.r * Math.sin(ca)) };
    }

    // The unit direction of travel at t.
    function TangentAt(e, t) {
        if (e.type === 'line') return Unit(Sub(e.b, e.a));
        var c, ang, dirSign;
        if (e.type === 'arc') {
            var g = ArcGeom(e);
            if (!g) return Unit(Sub(e.b, e.a));
            c = g.c; ang = g.a0 + (g.sw * t); dirSign = g.sw >= 0 ? 1 : -1;
        } else {
            c = e.c; ang = TAU * t; dirSign = 1;
        }
        return { x : -Math.sin(ang) * dirSign, y : Math.cos(ang) * dirSign };
    }

    function MidPoint(e) {
        if (e.type === 'circle') return Copy(e.c);
        return PointAt(e, 0.5);
    }

    function Length(e) {
        if (e.type === 'line') return Dist(e.a, e.b);
        if (e.type === 'arc') { var g = ArcGeom(e); return g ? g.r * Math.abs(g.sw) : Dist(e.a, e.b); }
        return TAU * e.r;
    }

    function Radius(e) {
        if (e.type === 'circle') return e.r;
        if (e.type === 'arc') { var g = ArcGeom(e); return g ? g.r : 0; }
        return 0;
    }

    function Centre(e) {
        if (e.type === 'circle') return Copy(e.c);
        if (e.type === 'arc') { var g = ArcGeom(e); return g ? Copy(g.c) : null; }
        return null;
    }

    // The points an entity is drawn and exported with, ends exact.
    function Tessellate(e, curves) {
        if (e.type === 'line') return [ Copy(e.a), Copy(e.b) ];
        var n = EntitySegments(e, curves);
        var out = [];
        if (e.type === 'arc') {
            var g = ArcGeom(e);
            if (!g) return [ Copy(e.a), Copy(e.b) ];
            for (var i = 0; i <= n; i++) {
                if (i === 0) { out.push(Copy(e.a)); continue; }
                if (i === n) { out.push(Copy(e.b)); continue; }
                var ang = g.a0 + ((g.sw * i) / n);
                out.push({ x : g.c.x + (g.r * Math.cos(ang)), y : g.c.y + (g.r * Math.sin(ang)) });
            }
            return out;
        }
        for (var k = 0; k < n; k++) {
            var ca = (TAU * k) / n;
            out.push({ x : e.c.x + (e.r * Math.cos(ca)), y : e.c.y + (e.r * Math.sin(ca)) });
        }
        return out;
    }

    function Bbox(e) {
        if (e.type === 'line') {
            return { minX : Math.min(e.a.x, e.b.x), minY : Math.min(e.a.y, e.b.y), maxX : Math.max(e.a.x, e.b.x), maxY : Math.max(e.a.y, e.b.y) };
        }
        if (e.type === 'circle') {
            return { minX : e.c.x - e.r, minY : e.c.y - e.r, maxX : e.c.x + e.r, maxY : e.c.y + e.r };
        }
        var g = ArcGeom(e);
        var box = { minX : Math.min(e.a.x, e.b.x), minY : Math.min(e.a.y, e.b.y), maxX : Math.max(e.a.x, e.b.x), maxY : Math.max(e.a.y, e.b.y) };
        if (!g) return box;
        [ 0, Math.PI / 2, Math.PI, Math.PI * 1.5 ].forEach(function (ang) {
            if (AngleParam(g, ang, 0) === null) return;
            var px = g.c.x + (g.r * Math.cos(ang)), py = g.c.y + (g.r * Math.sin(ang));
            box.minX = Math.min(box.minX, px); box.maxX = Math.max(box.maxX, px);
            box.minY = Math.min(box.minY, py); box.maxY = Math.max(box.maxY, py);
        });
        return box;
    }

    function UnionBox(a, b) {
        if (!a) return b ? { minX : b.minX, minY : b.minY, maxX : b.maxX, maxY : b.maxY } : null;
        if (!b) return a;
        return { minX : Math.min(a.minX, b.minX), minY : Math.min(a.minY, b.minY), maxX : Math.max(a.maxX, b.maxX), maxY : Math.max(a.maxY, b.maxY) };
    }

    // { p, t, d } - the nearest point of the entity to p.
    function Nearest(e, p) {
        if (e.type === 'line') {
            var ab = Sub(e.b, e.a);
            var len2 = Dot(ab, ab);
            var t = len2 > 0 ? Dot(Sub(p, e.a), ab) / len2 : 0;
            t = Math.max(0, Math.min(1, t));
            var q = Lerp(e.a, e.b, t);
            return { p : q, t : t, d : Dist(p, q) };
        }
        if (e.type === 'circle') {
            var ang = Math.atan2(p.y - e.c.y, p.x - e.c.x);
            var on = { x : e.c.x + (e.r * Math.cos(ang)), y : e.c.y + (e.r * Math.sin(ang)) };
            return { p : on, t : NormAngle(ang) / TAU, d : Dist(p, on) };
        }
        var g = ArcGeom(e);
        if (!g) return Nearest({ type : 'line', a : e.a, b : e.b }, p);
        var angA = Math.atan2(p.y - g.c.y, p.x - g.c.x);
        var tp = AngleParam(g, angA, 0);
        if (tp !== null) {
            var onArc = { x : g.c.x + (g.r * Math.cos(angA)), y : g.c.y + (g.r * Math.sin(angA)) };
            return { p : onArc, t : tp, d : Dist(p, onArc) };
        }
        var da = Dist(p, e.a), db = Dist(p, e.b);
        return da <= db ? { p : Copy(e.a), t : 0, d : da } : { p : Copy(e.b), t : 1, d : db };
    }

    // The parameter of a point that lies on the entity (or nearly).
    function ParamOf(e, p) {
        return Nearest(e, p).t;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Intersections
    // -------------------------------------------------------------------------

    // Infinite lines through (a1, b1) and (a2, b2): { p, t, u } with t, u the
    // fractions along each, or null when parallel.
    function LineLineInfinite(a1, b1, a2, b2) {
        var r = Sub(b1, a1), s = Sub(b2, a2);
        var denom = Cross(r, s);
        var rl = Len(r), sl = Len(s);
        if (!(rl > 0) || !(sl > 0) || Math.abs(denom) < 1e-12 * rl * sl) return null;
        var q = Sub(a2, a1);
        var t = Cross(q, s) / denom;
        var u = Cross(q, r) / denom;
        return { p : Add(a1, Mul(r, t)), t : t, u : u };
    }

    // The points where the infinite line a -> b meets a circle, with t the
    // fraction along a -> b. A line within `tol` of tangent touches once.
    function LineCircle(a, b, c, r, tol) {
        var d = Sub(b, a);
        var L = Len(d);
        if (!(L > 0)) return [];
        var u = { x : d.x / L, y : d.y / L };
        var tc = Dot(Sub(c, a), u);
        var foot = Add(a, Mul(u, tc));
        var h = Dist(foot, c);
        var touch = tol || TOUCH_MM;
        if (h > r + touch) return [];
        if (h >= r - touch) return [ { p : foot, t : tc / L } ];
        var k = Math.sqrt((r * r) - (h * h));
        return [ { p : Add(a, Mul(u, tc - k)), t : (tc - k) / L }, { p : Add(a, Mul(u, tc + k)), t : (tc + k) / L } ];
    }

    function CircleCircle(c1, r1, c2, r2, tol) {
        var d = Dist(c1, c2);
        var touch = tol || TOUCH_MM;
        if (d < SAME_MM) return [];
        if (d > r1 + r2 + touch) return [];
        if (d < Math.abs(r1 - r2) - touch) return [];
        var a = ((r1 * r1) - (r2 * r2) + (d * d)) / (2 * d);
        var h2 = (r1 * r1) - (a * a);
        var ux = (c2.x - c1.x) / d, uy = (c2.y - c1.y) / d;
        var pm = { x : c1.x + (ux * a), y : c1.y + (uy * a) };
        if (h2 <= touch * touch * 4) return [ pm ];
        var h = Math.sqrt(h2);
        return [ { x : pm.x - (uy * h), y : pm.y + (ux * h) }, { x : pm.x + (uy * h), y : pm.y - (ux * h) } ];
    }

    // The circle an arc or circle lies on.
    function CircleOf(e) {
        if (e.type === 'circle') return { c : e.c, r : e.r, g : null };
        var g = ArcGeom(e);
        return g ? { c : g.c, r : g.r, g : g } : null;
    }

    // Where a point on an entity's circle sits as a parameter (null if it is
    // off an arc's sweep).
    function CurveParamAt(e, circle, p, tol) {
        var ang = Math.atan2(p.y - circle.c.y, p.x - circle.c.x);
        if (e.type === 'circle') return NormAngle(ang) / TAU;
        return AngleParam(circle.g, ang, (tol || TOUCH_MM) / circle.r);
    }

    // Every point where two entities meet: [{ p, t1, t2 }]. An end that stops
    // ON the other entity counts (TV's touch rule); parallel or overlapping
    // straight edges never cross.
    function Intersect(e1, e2, tol) {
        var touch = tol || TOUCH_MM;
        var out = [];
        if (e1.type === 'line' && e2.type === 'line') {
            var hit = LineLineInfinite(e1.a, e1.b, e2.a, e2.b);
            if (!hit) return out;
            var tolT = touch / Math.max(SAME_MM, Dist(e1.a, e1.b)), tolU = touch / Math.max(SAME_MM, Dist(e2.a, e2.b));
            if (hit.t < -tolT || hit.t > 1 + tolT || hit.u < -tolU || hit.u > 1 + tolU) return out;
            var tc = Math.max(0, Math.min(1, hit.t)), uc = Math.max(0, Math.min(1, hit.u));
            out.push({ p : Lerp(e1.a, e1.b, tc), t1 : tc, t2 : uc });
            return out;
        }
        if (e1.type === 'line' || e2.type === 'line') {
            var line = e1.type === 'line' ? e1 : e2;
            var curve = e1.type === 'line' ? e2 : e1;
            var circle = CircleOf(curve);
            if (!circle) return out;
            var tolL = touch / Math.max(SAME_MM, Dist(line.a, line.b));
            LineCircle(line.a, line.b, circle.c, circle.r, touch).forEach(function (h) {
                if (h.t < -tolL || h.t > 1 + tolL) return;
                var tl = Math.max(0, Math.min(1, h.t));
                var tcv = CurveParamAt(curve, circle, h.p, touch);
                if (tcv === null) return;
                var p = Lerp(line.a, line.b, tl);
                out.push(e1.type === 'line' ? { p : p, t1 : tl, t2 : tcv } : { p : p, t1 : tcv, t2 : tl });
            });
            return out;
        }
        var c1 = CircleOf(e1), c2 = CircleOf(e2);
        if (!c1 || !c2) return out;
        CircleCircle(c1.c, c1.r, c2.c, c2.r, touch).forEach(function (p) {
            var t1 = CurveParamAt(e1, c1, p, touch);
            var t2 = CurveParamAt(e2, c2, p, touch);
            if (t1 === null || t2 === null) return;
            out.push({ p : p, t1 : t1, t2 : t2 });
        });
        return out;
    }

    // Where the infinite line from `origin` along unit `dir` meets an entity:
    // [{ p, dist }] with dist signed along dir.
    function RayHits(origin, dir, e, tol) {
        var far = Add(origin, dir);
        var probe = { type : 'line', a : origin, b : far };
        var out = [];
        if (e.type === 'line') {
            var hit = LineLineInfinite(origin, far, e.a, e.b);
            if (!hit) return out;
            var tolU = (tol || TOUCH_MM) / Math.max(SAME_MM, Dist(e.a, e.b));
            if (hit.u < -tolU || hit.u > 1 + tolU) return out;
            out.push({ p : hit.p, dist : hit.t });
            return out;
        }
        var circle = CircleOf(e);
        if (!circle) return out;
        LineCircle(probe.a, probe.b, circle.c, circle.r, tol).forEach(function (h) {
            if (CurveParamAt(e, circle, h.p, tol) === null) return;
            out.push({ p : h.p, dist : h.t });
        });
        return out;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Cutting, Reversing, Transforming
    // -------------------------------------------------------------------------

    function Clone(e) {
        var out = { type : e.type };
        Object.keys(e).forEach(function (key) {
            var v = e[key];
            out[key] = (v && typeof v === 'object') ? { x : v.x, y : v.y } : v;
        });
        return out;
    }

    // The part of an entity between two parameters, t0 < t1 (for a circle the
    // way round from t0 CCW to t1, wrapping). Null when it has no length.
    function Part(e, t0, t1) {
        if (e.type === 'line') {
            if (t1 - t0 <= 0) return null;
            var part = Clone(e);
            part.a = PointAt(e, t0); part.b = PointAt(e, t1);
            return Dist(part.a, part.b) > SAME_MM ? part : null;
        }
        if (e.type === 'arc') {
            if (t1 - t0 <= 0) return null;
            var g = ArcGeom(e);
            if (!g) return null;
            var arc = Clone(e);
            arc.a = PointAt(e, t0); arc.b = PointAt(e, t1);
            arc.sw = g.sw * (t1 - t0);
            if (e.segs >= 1) arc.segs = Math.max(1, Math.round(e.segs * (t1 - t0)));
            return Dist(arc.a, arc.b) > SAME_MM && Math.abs(arc.sw) > 1e-9 ? arc : null;
        }
        var span = t1 - t0;
        if (span <= 0) span += 1;
        if (span <= 1e-9 || span >= 1 - 1e-9) return null;
        var a0 = TAU * t0;
        var res = ArcFromCentre(e.c, e.r, a0, TAU * span, e.segs >= 3 ? Math.max(1, Math.round(e.segs * span)) : 0);
        return res;
    }

    function Reverse(e) {
        var out = Clone(e);
        if (e.type === 'circle') return out;
        out.a = Copy(e.b); out.b = Copy(e.a);
        if (e.type === 'arc') out.sw = -e.sw;
        return out;
    }

    // Applies a point map to an entity. `flips` is true for a mirror, which
    // turns an arc the other way round.
    function MapEntity(e, fn, flips, scale) {
        var out = Clone(e);
        if (e.type === 'circle') {
            out.c = fn(e.c);
            out.r = e.r * (scale || 1);
            return out;
        }
        out.a = fn(e.a); out.b = fn(e.b);
        if (e.type === 'arc' && flips) out.sw = -e.sw;
        return out;
    }

    // A parallel copy `d` to the LEFT of the way the entity runs (outward for a
    // circle). Null when nothing is left of it.
    function OffsetEntity(e, d) {
        if (e.type === 'line') {
            var n = Mul(Left(Unit(Sub(e.b, e.a))), d);
            var line = Clone(e);
            line.a = Add(e.a, n); line.b = Add(e.b, n);
            return line;
        }
        if (e.type === 'circle') {
            var rr = e.r + d;
            if (!(rr > MIN_RADIUS)) return null;
            var circ = Clone(e); circ.r = rr;
            return circ;
        }
        var g = ArcGeom(e);
        if (!g) return null;
        var r2 = g.r - (d * (g.sw >= 0 ? 1 : -1));                  // left of a CCW arc is towards its centre
        if (!(r2 > MIN_RADIUS)) return null;
        var arc = ArcFromCentre(g.c, r2, g.a0, g.sw, e.segs);
        arc.constr = e.constr;
        return arc;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Corners (TV VectorTools Offset: CornerFillet / CornerChamfer)
    // -------------------------------------------------------------------------

    function CornerOf(prev, corner, next) {
        var ax = prev.x - corner.x, ay = prev.y - corner.y;
        var bx = next.x - corner.x, by = next.y - corner.y;
        var la = Math.hypot(ax, ay), lb = Math.hypot(bx, by);
        if (la < SAME_MM || lb < SAME_MM) return null;
        var ux = ax / la, uy = ay / la, vx = bx / lb, vy = by / lb;
        var dot = Math.max(-1, Math.min(1, (ux * vx) + (uy * vy)));
        return { ux : ux, uy : uy, vx : vx, vy : vy, la : la, lb : lb, angle : Math.acos(dot) };
    }

    // Round a corner. prev / next are points along each edge away from the
    // corner (their distance is how much room the edge has). Returns
    // { ok, from, to, c, r, sw, setback } or { ok:false, reason, room }.
    function CornerFillet(prev, corner, next, radiusMm) {
        var c = CornerOf(prev, corner, next);
        if (!c || c.angle < 1e-6 || c.angle > Math.PI - 1e-6) return { ok : false, reason : 'straight' };
        if (!(radiusMm > SAME_MM)) return { ok : false, reason : 'radius' };
        var setback = radiusMm / Math.tan(c.angle / 2);
        if (setback > c.la + SAME_MM || setback > c.lb + SAME_MM) return { ok : false, reason : 'long', setback : setback, room : Math.min(c.la, c.lb) };
        var from = { x : corner.x + (c.ux * setback), y : corner.y + (c.uy * setback) };
        var to   = { x : corner.x + (c.vx * setback), y : corner.y + (c.vy * setback) };
        var mx = c.ux + c.vx, my = c.uy + c.vy;
        var ml = Math.hypot(mx, my);
        var reach = radiusMm / Math.sin(c.angle / 2);
        var centre = { x : corner.x + ((mx / ml) * reach), y : corner.y + ((my / ml) * reach) };
        var start = Math.atan2(from.y - centre.y, from.x - centre.x);
        var sweep = Math.atan2(to.y - centre.y, to.x - centre.x) - start;
        while (sweep > Math.PI)  sweep -= TAU;
        while (sweep < -Math.PI) sweep += TAU;
        return { ok : true, from : from, to : to, c : centre, r : radiusMm, sw : sweep, setback : setback };
    }

    // Cut a corner off: d1 back along the first edge, d2 along the second.
    function CornerChamfer(prev, corner, next, d1, d2) {
        var c = CornerOf(prev, corner, next);
        var second = Number.isFinite(d2) ? d2 : d1;
        if (!c || c.angle < 1e-6 || c.angle > Math.PI - 1e-6) return { ok : false, reason : 'straight' };
        if (!(d1 > SAME_MM) || !(second > SAME_MM)) return { ok : false, reason : 'radius' };
        if (d1 > c.la + SAME_MM || second > c.lb + SAME_MM) return { ok : false, reason : 'long', setback : Math.max(d1, second), room : Math.min(c.la, c.lb) };
        return {
            ok   : true,
            from : { x : corner.x + (c.ux * d1), y : corner.y + (c.uy * d1) },
            to   : { x : corner.x + (c.vx * second), y : corner.y + (c.vy * second) }
        };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Polygons
    // -------------------------------------------------------------------------

    function PolygonArea(points) {
        var area = 0;
        for (var i = 0; i < points.length; i++) {
            var p = points[i], q = points[(i + 1) % points.length];
            area += (p.x * q.y) - (q.x * p.y);
        }
        return area / 2;
    }

    function PolygonPerimeter(points) {
        var total = 0;
        for (var i = 0; i < points.length; i++) total += Dist(points[i], points[(i + 1) % points.length]);
        return total;
    }

    function PointInPolygon(p, points) {
        var inside = false;
        for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
            var a = points[i], b = points[j];
            if (((a.y > p.y) !== (b.y > p.y)) && (p.x < ((b.x - a.x) * (p.y - a.y) / (b.y - a.y)) + a.x)) inside = !inside;
        }
        return inside;
    }

    // Where a closed ring of points crosses or doubles back on itself:
    // [{ p, i, j }], i and j the two edges. Neighbouring edges only count when
    // they fold back over each other. Edges are swept left to right, so a
    // long outline stays quick.
    function RingSelfIntersections(points, limit) {
        var n = points.length;
        var max = limit || 20;
        var edges = [];
        for (var i = 0; i < n; i++) {
            var a = points[i], b = points[(i + 1) % n];
            edges.push({ i : i, a : a, b : b, minX : Math.min(a.x, b.x), maxX : Math.max(a.x, b.x), minY : Math.min(a.y, b.y), maxY : Math.max(a.y, b.y) });
        }
        var order = edges.slice().sort(function (p, q) { return p.minX - q.minX; });
        var found = [];
        for (var k = 0; k < order.length && found.length < max; k++) {
            var e = order[k];
            for (var m = k + 1; m < order.length && order[m].minX <= e.maxX + SAME_MM; m++) {
                var f = order[m];
                if (f.minY > e.maxY + SAME_MM || f.maxY < e.minY - SAME_MM) continue;
                var gap = Math.abs(e.i - f.i);
                var neighbours = gap === 1 || gap === n - 1;
                var hit = SegmentCross(e.a, e.b, f.a, f.b);
                if (neighbours) {
                    if (FoldsBack(e, f, n)) found.push({ p : Copy(SharedEnd(e, f, n)), i : e.i, j : f.i, kind : 'fold' });
                    continue;
                }
                if (hit) found.push({ p : hit, i : e.i, j : f.i, kind : 'cross' });
                if (found.length >= max) break;
            }
        }
        return found;
    }

    function SharedEnd(e, f, n) {
        return ((e.i + 1) % n === f.i) ? e.b : e.a;
    }

    // Two neighbouring edges that run back along each other (a spike).
    function FoldsBack(e, f, n) {
        var first = ((e.i + 1) % n === f.i) ? e : f;
        var second = first === e ? f : e;
        var d1 = Unit(Sub(first.b, first.a)), d2 = Unit(Sub(second.b, second.a));
        return Dot(d1, d2) < -1 + 1e-9;
    }

    // Two straight edges crossing, ends shared or touching excluded.
    function SegmentCross(a1, b1, a2, b2) {
        var hit = LineLineInfinite(a1, b1, a2, b2);
        if (!hit) {
            // Collinear overlap is a doubling-back too.
            var r = Sub(b1, a1);
            if (Math.abs(Cross(r, Sub(a2, a1))) > SAME_MM * Len(r)) return null;
            var len2 = Dot(r, r);
            if (!(len2 > 0)) return null;
            var s0 = Dot(Sub(a2, a1), r) / len2, s1 = Dot(Sub(b2, a1), r) / len2;
            var lo = Math.max(0, Math.min(s0, s1)), hi = Math.min(1, Math.max(s0, s1));
            return (hi - lo) * Math.sqrt(len2) > SAME_MM * 10 ? Lerp(a1, b1, (lo + hi) / 2) : null;
        }
        var eps = 1e-9;
        if (hit.t <= eps || hit.t >= 1 - eps || hit.u <= eps || hit.u >= 1 - eps) {
            var touchesEnd = (hit.t > -eps && hit.t < 1 + eps) && (hit.u > -eps && hit.u < 1 + eps);
            if (!touchesEnd) return null;
            // An end resting on the middle of the other edge is a touch, and
            // in a ring that is still a crossing; a shared corner is not.
            var tEnd = hit.t <= eps || hit.t >= 1 - eps;
            var uEnd = hit.u <= eps || hit.u >= 1 - eps;
            return (tEnd && uEnd) ? null : hit.p;
        }
        return hit.p;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Boxes (TV SelectionBox: window takes what is inside, crossing
    //          what it touches; Liang-Barsky for the touch)
    // -------------------------------------------------------------------------

    function PointInRect(p, r) {
        return p.x >= r.minX && p.x <= r.maxX && p.y >= r.minY && p.y <= r.maxY;
    }

    function SegmentTouchesRect(a, b, r) {
        var t0 = 0, t1 = 1;
        var dx = b.x - a.x, dy = b.y - a.y;
        var checks = [ [ -dx, a.x - r.minX ], [ dx, r.maxX - a.x ], [ -dy, a.y - r.minY ], [ dy, r.maxY - a.y ] ];
        for (var i = 0; i < 4; i++) {
            var p = checks[i][0], q = checks[i][1];
            if (p === 0) { if (q < 0) return false; continue; }
            var t = q / p;
            if (p < 0) { if (t > t1) return false; if (t > t0) t0 = t; }
            else       { if (t < t0) return false; if (t < t1) t1 = t; }
        }
        return true;
    }

    // mode 'window' (wholly inside) or 'crossing' (touching at all).
    function EntityInRect(e, r, mode, curves) {
        var pts = Tessellate(e, curves);
        if (e.type === 'circle') pts.push(pts[0]);
        if (mode === 'window') return pts.every(function (p) { return PointInRect(p, r); });
        for (var i = 0; i < pts.length - 1; i++) {
            if (SegmentTouchesRect(pts[i], pts[i + 1], r)) return true;
        }
        return pts.length === 1 && PointInRect(pts[0], r);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Reading a Curve Back From Points (TV Curves Describe, y up)
    // -------------------------------------------------------------------------

    // What arc these points are, or null. Every inside point must sit on the
    // circle within fitMm, the steps round it must be even within stepRad,
    // and the two END steps may be shorter (what a trim leaves). Returns
    // { c, r, sw, segments } with sw the signed sweep from the first point.
    function DescribeArc(points, fitMm, stepRad) {
        var n = points.length;
        if (n < 4) return null;
        var fit  = Number.isFinite(fitMm) ? fitMm : 1e-3;
        var step = Number.isFinite(stepRad) ? stepRad : 1e-4;
        var inside = n >= 5;
        var circle = inside ? CircleThrough(points[1], points[Math.floor(n / 2)], points[n - 2])
                            : CircleThrough(points[0], points[Math.floor(n / 2)], points[n - 1]);
        if (!circle || !(circle.r >= MIN_RADIUS)) return null;
        if (circle.r > 1e6) return null;
        var off = function (p) { return Dist(p, circle.c) - circle.r; };
        for (var i = inside ? 1 : 0; i < (inside ? n - 1 : n); i++) {
            if (Math.abs(off(points[i])) > fit) return null;
        }
        var arc = ArcThrough(points[0], points[Math.floor(n / 2)], points[n - 1]);
        if (!arc) return null;
        var way = arc.sw < 0 ? -1 : 1;
        var steps = [];
        for (var k = 1; k < n; k++) {
            var a = Math.atan2(points[k - 1].y - circle.c.y, points[k - 1].x - circle.c.x);
            var b = Math.atan2(points[k].y - circle.c.y, points[k].x - circle.c.x);
            var s = NormAngle((b - a) * way);
            if (s > Math.PI || !(s > 0)) return null;
            steps.push(s);
        }
        var inner = steps.length > 2 ? steps.slice(1, -1) : steps;
        var full = Math.max.apply(null, inner);
        if (!(full > 0)) return null;
        for (var m = 0; m < inner.length; m++) { if (Math.abs(inner[m] - full) > step) return null; }
        if (steps[0] > full + step || steps[steps.length - 1] > full + step) return null;
        if (inside) {
            var sag = circle.r * (1 - Math.cos(full / 2));
            var endOk = function (p) { var o = off(p); return o <= fit && o >= -(sag + fit); };
            if (!endOk(points[0]) || !endOk(points[n - 1])) return null;
        }
        var sweep = steps.reduce(function (sum, s2) { return sum + s2; }, 0) * way;
        if (Math.abs(sweep) >= TAU - 1e-6) return null;
        return { c : circle.c, r : circle.r, sw : sweep, segments : steps.length };
    }

    // A closed ring of points that is a whole circle at even steps, or null.
    function DescribeCircle(points, fitMm, stepRad) {
        var n = points.length;
        if (n < 6) return null;
        var fit = Number.isFinite(fitMm) ? fitMm : 1e-3;
        var stepTol = Number.isFinite(stepRad) ? stepRad : 1e-4;
        var sx = 0, sy = 0;
        points.forEach(function (p) { sx += p.x; sy += p.y; });
        var c = { x : sx / n, y : sy / n };
        var r = Dist(points[0], c);
        if (!(r >= MIN_RADIUS)) return null;
        if (points.some(function (p) { return Math.abs(Dist(p, c) - r) > fit; })) return null;
        var start = Math.atan2(points[0].y - c.y, points[0].x - c.x);
        var first = NormAngle(Math.atan2(points[1].y - c.y, points[1].x - c.x) - start);
        var way = first <= Math.PI ? 1 : -1;
        var stepAng = (TAU / n) * way;
        for (var i = 1; i < n; i++) {
            var want = start + (stepAng * i);
            var have = Math.atan2(points[i].y - c.y, points[i].x - c.x);
            var d = NormAngle(have - want);
            if (d > Math.PI) d -= TAU;
            if (Math.abs(d) > stepTol * 10) return null;
        }
        return { c : c, r : r, segments : n };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Formatting
    // -------------------------------------------------------------------------

    // Millimetres as the editor shows them: up to `precision` places, trailing
    // zeros dropped (TV MeasureParse Format, no thousands separator here).
    function FormatMm(value, precision) {
        if (!Number.isFinite(value)) return '';
        var places = Number.isFinite(precision) ? precision : 2;
        var fixed = Math.abs(value).toFixed(places);
        if (fixed.indexOf('.') !== -1) fixed = fixed.replace(/0+$/, '').replace(/[.]$/, '');
        var negative = value < 0 && parseFloat(fixed) !== 0;
        return (negative ? '-' : '') + fixed;
    }

    function ToDeg(rad) { return rad * 180 / Math.PI; }
    function ToRad(deg) { return deg * Math.PI / 180; }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Export
    // -------------------------------------------------------------------------

    window.Na__DrawProfile__Geom = {
        TAU : TAU, SAME_MM : SAME_MM, TOUCH_MM : TOUCH_MM, MIN_RADIUS : MIN_RADIUS, MITRE_LIMIT : MITRE_LIMIT,
        P : P, Copy : Copy, Add : Add, Sub : Sub, Mul : Mul, Dot : Dot, Cross : Cross, Len : Len, Dist : Dist,
        Lerp : Lerp, Mid : Mid, Same : Same, Left : Left, Unit : Unit, NormAngle : NormAngle,
        Rotate : Rotate, ScaleAbout : ScaleAbout, MirrorPoint : MirrorPoint,
        SegmentsFor : SegmentsFor, ArcSegmentsFor : ArcSegmentsFor, EntitySegments : EntitySegments,
        ArcGeom : ArcGeom, ArcFromCentre : ArcFromCentre, SagittaOf : SagittaOf,
        SweepFromSagitta : SweepFromSagitta, SagittaFromSweep : SagittaFromSweep, SagittaForRadius : SagittaForRadius,
        CircleThrough : CircleThrough, ArcThrough : ArcThrough, CarrySweep : CarrySweep, AngleParam : AngleParam,
        EndPoints : EndPoints, PointAt : PointAt, TangentAt : TangentAt, MidPoint : MidPoint, Length : Length,
        Radius : Radius, Centre : Centre, Tessellate : Tessellate, Bbox : Bbox, UnionBox : UnionBox,
        Nearest : Nearest, ParamOf : ParamOf,
        LineLineInfinite : LineLineInfinite, LineCircle : LineCircle, CircleCircle : CircleCircle,
        CircleOf : CircleOf, Intersect : Intersect, RayHits : RayHits,
        Clone : Clone, Part : Part, Reverse : Reverse, MapEntity : MapEntity, OffsetEntity : OffsetEntity,
        CornerFillet : CornerFillet, CornerChamfer : CornerChamfer,
        PolygonArea : PolygonArea, PolygonPerimeter : PolygonPerimeter, PointInPolygon : PointInPolygon,
        RingSelfIntersections : RingSelfIntersections, SegmentCross : SegmentCross,
        PointInRect : PointInRect, SegmentTouchesRect : SegmentTouchesRect, EntityInRect : EntityInRect,
        DescribeArc : DescribeArc, DescribeCircle : DescribeCircle,
        FormatMm : FormatMm, ToDeg : ToDeg, ToRad : ToRad
    };

    // endregion ----------------------------------------------------------------
})();
