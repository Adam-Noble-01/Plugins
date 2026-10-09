/* =============================================================================
   NA PROFILE TOOLS - DRAW PROFILE - OPERATIONS
   =============================================================================
   FILE       : Na__ProfileTools__DrawProfile__Ops__.js
   NAMESPACE  : window.Na__DrawProfile__Ops
   PURPOSE    : What the modify tools do to the drawing - trim, extend, corner,
                fillet, chamfer, offset, split - as plain functions on the
                document, so the tools only have to pick and preview.

   CONVENTIONS
     Every operation takes options.dryRun: true returns what WOULD happen
     ({ ok, message, preview:{ add:[entity], remove:[entity] } }) without
     touching the document, which is how the tools draw their previews.
     A refusal ({ ok:false, message }) always names what to do instead.

   SEMANTICS (TV VectorTools, carried over to exact lines and arcs)
     Trim     the clicked span goes, back to the nearest crossing either side;
              nothing crosses, nothing is cut. A circle needs two crossings.
     Extend   the end nearer the click runs on (straight, or round its circle)
              to the first edge it meets, within 2000 mm.
     Corner   both picked edges run to where they meet; the picked sides are
              kept. (Fillet radius 0, as in AutoCAD.)
     Fillet   an arc tangent to both edges; between two straight edges the TV
              CornerFillet maths verbatim, otherwise the centre is where the
              two edges' offsets by the radius cross.
     Chamfer  a straight cut, d1 back along one edge and d2 along the other.
     Offset   the whole chain the picked edge belongs to, each edge moved
              sideways and joined to its neighbours where they meet; mitres
              past 4x the distance are cut square, swallowed edges drop out.
   ============================================================================= */

(function () {
    'use strict';

    var G = window.Na__DrawProfile__Geom;
    var D = window.Na__DrawProfile__Doc;

    var SAME = 1e-6;

    // -------------------------------------------------------------------------
    // REGION | Helpers
    // -------------------------------------------------------------------------

    function Ok(message, extra) {
        var out = { ok : true, message : message || '' };
        if (extra) Object.keys(extra).forEach(function (k) { out[k] = extra[k]; });
        return out;
    }

    function Fail(message) { return { ok : false, message : message }; }

    // Every place another entity crosses or touches `e`, as sorted params.
    function CutParams(doc, e, options) {
        var hits = [];
        doc.ents.forEach(function (other) {
            if (other.id === e.id) return;
            G.Intersect(e, other).forEach(function (h) { hits.push({ t : h.t1, p : h.p }); });
        });
        (options && options.extraCutters || []).forEach(function (cutter) {
            G.Intersect(e, cutter).forEach(function (h) { hits.push({ t : h.t1, p : h.p }); });
        });
        hits.sort(function (a, b) { return a.t - b.t; });
        var out = [];
        hits.forEach(function (h) {
            var last = out[out.length - 1];
            if (last && Math.abs(h.t - last.t) <= 1e-9) return;
            out.push(h);
        });
        return out;
    }

    // Moves one end of a line or arc to `p`, which lies on the entity's own
    // line or circle. An arc keeps running the same way round from its other
    // end, so it shortens or lengthens along its circle.
    function MoveEnd(e, end, p) {
        var out = G.Clone(e);
        if (e.type === 'line') { out[end] = G.Copy(p); return out; }
        var g = G.ArcGeom(e);
        if (!g) return null;
        var sign = g.sw >= 0 ? 1 : -1;
        var angP = Math.atan2(p.y - g.c.y, p.x - g.c.x);
        var sweep;
        if (end === 'b') {
            sweep = sign * G.NormAngle((angP - g.a0) * sign);
            out.b = G.Copy(p);
        } else {
            var angB = g.a0 + g.sw;
            sweep = sign * G.NormAngle((angB - angP) * sign);
            out.a = G.Copy(p);
        }
        if (!(Math.abs(sweep) > 1e-9) || Math.abs(sweep) >= G.TAU - 1e-9) return null;
        out.sw = sweep;
        if (e.segs >= 1) out.segs = Math.max(1, Math.round(e.segs * Math.abs(sweep / g.sw)));
        return out;
    }

    // How far along an arc (in its own params, measured forward from a and
    // unwrapped onto [0, 2pi/|sw|)) a point on its circle lies.
    function ArcForwardParam(e, p) {
        var g = G.ArcGeom(e);
        var sign = g.sw >= 0 ? 1 : -1;
        var ang = Math.atan2(p.y - g.c.y, p.x - g.c.x);
        return G.NormAngle((ang - g.a0) * sign) / Math.abs(g.sw);
    }

    // Which end of e should move to x, keeping the side the pick is on.
    function EndTowards(e, x, pick) {
        if (e.type === 'line') {
            var ab = G.Sub(e.b, e.a);
            var len2 = G.Dot(ab, ab);
            var tx = G.Dot(G.Sub(x, e.a), ab) / len2;
            var tp = G.Dot(G.Sub(pick, e.a), ab) / len2;
            return tx > tp ? 'b' : 'a';
        }
        var g = G.ArcGeom(e);
        var tX = ArcForwardParam(e, x);
        var tP = Math.min(1, ArcForwardParam(e, G.Nearest(e, pick).p));
        if (tX <= 1 + 1e-9) return tX > tP ? 'b' : 'a';
        var beyondB = tX - 1;
        var beforeA = (G.TAU / Math.abs(g.sw)) - tX;
        return beyondB <= beforeA ? 'b' : 'a';
    }

    // Where two entities' lines / circles meet, extended: all candidates.
    function ExtendedMeets(e1, e2) {
        var c1 = e1.type === 'line' ? null : G.CircleOf(e1);
        var c2 = e2.type === 'line' ? null : G.CircleOf(e2);
        if (!c1 && !c2) {
            var hit = G.LineLineInfinite(e1.a, e1.b, e2.a, e2.b);
            return hit ? [ hit.p ] : [];
        }
        if (!c1 || !c2) {
            var line = c1 ? e2 : e1, circle = c1 || c2;
            return G.LineCircle(line.a, line.b, circle.c, circle.r).map(function (h) { return h.p; });
        }
        return G.CircleCircle(c1.c, c1.r, c2.c, c2.r);
    }

    function Nearest(points, to) {
        var best = null, bestD = Infinity;
        points.forEach(function (p) { var d = G.Dist(p, to); if (d < bestD) { best = p; bestD = d; } });
        return best;
    }

    // The two entities meeting at a location, and which of their ends is there.
    function CornerAt(doc, key) {
        var index = D.VertexIndex(doc, { construction : false });
        var v = index.get(key);
        if (!v) return Fail('There is no corner there.');
        if (v.degree !== 2) return Fail(v.degree < 2 ? 'That is an open end, not a corner.' : 'More than two edges meet there — pick two of them instead.');
        var r1 = v.refs[0], r2 = v.refs[1];
        if (r1.id === r2.id) return Fail('That edge meets itself there.');
        return Ok('', { p : v.p, e1 : D.Get(doc, r1.id), end1 : r1.end, e2 : D.Get(doc, r2.id), end2 : r2.end });
    }

    function Other(end) { return end === 'a' ? 'b' : 'a'; }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Trim
    // -------------------------------------------------------------------------

    function Trim(doc, id, pick, options) {
        var opts = options || {};
        var e = D.Get(doc, id);
        if (!e) return Fail('Nothing to trim there.');
        var cuts = CutParams(doc, e, opts);
        var t = G.Nearest(e, pick).t;

        if (e.type === 'circle') {
            if (cuts.length < 2) return Fail('A circle needs two crossings to trim between. Draw the edges that cut it first.');
            var after = null, before = null;
            cuts.forEach(function (c) { if (c.t > t && !after) after = c; });
            for (var i = cuts.length - 1; i >= 0; i--) { if (cuts[i].t < t) { before = cuts[i]; break; } }
            after = after || cuts[0];
            before = before || cuts[cuts.length - 1];
            var removed = G.Part(e, before.t, after.t);
            var kept = G.Part(e, after.t, before.t);
            if (!removed || !kept) return Fail('Nothing to trim there.');
            kept.a = G.Copy(after.p); kept.b = G.Copy(before.p);
            if (opts.dryRun) return Ok('', { preview : { remove : [ removed ], add : [] } });
            D.Replace(doc, id, [ kept ]);
            return Ok('Trimmed the circle into an arc.');
        }

        var inner = cuts.filter(function (c) { return c.t > 1e-7 && c.t < 1 - 1e-7; });
        if (!inner.length) return Fail('Nothing crosses this edge here, so there is nothing to trim back to. Use Delete to remove it.');
        var lo = { t : 0, p : e.a }, hi = { t : 1, p : e.b };
        inner.forEach(function (c) {
            if (c.t <= t && c.t > lo.t) lo = c;
            if (c.t >= t && c.t < hi.t) hi = c;
        });
        if (lo.t === 0 && hi.t === 1) return Fail('Nothing crosses this edge here.');

        var span = G.Part(e, lo.t, hi.t);
        var keep = [];
        if (lo.t > 0) { var k1 = G.Part(e, 0, lo.t); if (k1) { k1.b = G.Copy(lo.p); keep.push(k1); } }
        if (hi.t < 1) { var k2 = G.Part(e, hi.t, 1); if (k2) { k2.a = G.Copy(hi.p); keep.push(k2); } }
        if (opts.dryRun) return Ok('', { preview : { remove : span ? [ span ] : [], add : [] } });
        if (keep.length) D.Replace(doc, id, keep); else D.Remove(doc, [ id ]);
        return Ok('Trimmed.');
    }

    // Fence trim: every entity the fence crosses loses the span it crosses.
    function TrimFence(doc, a, b, options) {
        var fence = { type : 'line', a : a, b : b };
        var hits = [];
        doc.ents.forEach(function (e) {
            G.Intersect(fence, e).forEach(function (h) { hits.push({ id : e.id, p : h.p }); });
        });
        if (!hits.length) return Fail('The fence crosses nothing.');
        if (options && options.dryRun) {
            var removes = [];
            hits.forEach(function (h) {
                var r = Trim(doc, h.id, h.p, { dryRun : true });
                if (r.ok) removes = removes.concat(r.preview.remove);
            });
            return Ok('', { preview : { remove : removes, add : [] } });
        }
        var count = 0;
        hits.forEach(function (h) {
            var e = D.Get(doc, h.id);
            if (!e) return;
            // The entity may already have been cut; find the piece that still
            // runs through the fence point.
            var candidates = doc.ents.filter(function (x) { return G.Nearest(x, h.p).d < 1e-6; });
            candidates.forEach(function (x) { if (Trim(doc, x.id, h.p, {}).ok) count += 1; });
        });
        return count ? Ok('Fence trimmed ' + count + ' span(s).') : Fail('Nothing the fence crosses has a span to trim.');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Extend
    // -------------------------------------------------------------------------

    function Extend(doc, id, pick, maxMm, options) {
        var e = D.Get(doc, id);
        if (!e || e.type === 'circle') return Fail('Only a line or an arc has an end to extend.');
        var limit = maxMm || 2000;
        var t = G.Nearest(e, pick).t;
        var end = t >= 0.5 ? 'b' : 'a';
        var from = e[end];
        var best = null;

        if (e.type === 'line') {
            var dir = end === 'b' ? G.Unit(G.Sub(e.b, e.a)) : G.Unit(G.Sub(e.a, e.b));
            doc.ents.forEach(function (other) {
                if (other.id === id) return;
                G.RayHits(from, dir, other).forEach(function (h) {
                    if (h.dist <= 1e-5 || h.dist > limit) return;
                    if (!best || h.dist < best.d) best = { p : h.p, d : h.dist };
                });
            });
        } else {
            var g = G.ArcGeom(e);
            var free = G.TAU - Math.abs(g.sw);
            var sign = g.sw >= 0 ? 1 : -1;
            var endAng = end === 'b' ? g.a0 + g.sw : g.a0;
            var probe = { type : 'circle', c : g.c, r : g.r };
            doc.ents.forEach(function (other) {
                if (other.id === id) return;
                G.Intersect(probe, other).forEach(function (h) {
                    var ang = Math.atan2(h.p.y - g.c.y, h.p.x - g.c.x);
                    // Beyond b the arc runs on in its own direction; before a, against it.
                    var run = end === 'b' ? G.NormAngle((ang - endAng) * sign) : G.NormAngle((endAng - ang) * sign);
                    if (run <= 1e-7 || run >= free - 1e-7) return;
                    var d = run * g.r;
                    if (d > limit) return;
                    if (!best || d < best.d) best = { p : h.p, d : d };
                });
            });
        }

        if (!best) return Fail('Nothing lies ahead of this end within ' + limit + ' mm to extend to.');
        var extended = MoveEnd(e, end, best.p);
        if (!extended) return Fail('That extension would close the arc on itself.');
        if (options && options.dryRun) {
            var addPiece = e.type === 'line' ? { type : 'line', a : from, b : best.p } : (end === 'b' ? G.Part(extended, Math.abs(e.sw / extended.sw), 1) : G.Part(extended, 0, 1 - Math.abs(e.sw / extended.sw)));
            return Ok('', { preview : { add : addPiece ? [ addPiece ] : [ extended ], remove : [] } });
        }
        D.Replace(doc, id, [ extended ]);
        return Ok('Extended ' + G.FormatMm(best.d, 2) + ' mm.');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Corner (fillet radius 0)
    // -------------------------------------------------------------------------

    function Corner(doc, id1, pick1, id2, pick2, options) {
        if (id1 === id2) return Fail('Pick two different edges.');
        var e1 = D.Get(doc, id1), e2 = D.Get(doc, id2);
        if (!e1 || !e2) return Fail('Pick two edges.');
        if (e1.type === 'circle' || e2.type === 'circle') return Fail('A whole circle has no end to bring to a corner. Trim it into an arc first.');
        var meets = ExtendedMeets(e1, e2);
        if (!meets.length) return Fail('Those edges never meet, however far they run.');
        var x = Nearest(meets, G.Mid(G.Nearest(e1, pick1).p, G.Nearest(e2, pick2).p));
        var end1 = EndTowards(e1, x, pick1), end2 = EndTowards(e2, x, pick2);
        var n1 = MoveEnd(e1, end1, x), n2 = MoveEnd(e2, end2, x);
        if (!n1 || !n2) return Fail('The corner would close an arc on itself.');
        if (options && options.dryRun) return Ok('', { preview : { add : [ n1, n2 ], remove : [ e1, e2 ] }, point : x });
        D.Replace(doc, id1, [ n1 ]);
        D.Replace(doc, id2, [ n2 ]);
        return Ok('Corner made.', { point : x });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Fillet
    // -------------------------------------------------------------------------

    // A point `along` mm from an entity's end `end`, into the entity; null when
    // the entity is shorter than that.
    function PointInFrom(e, end, along) {
        var length = G.Length(e);
        if (along > length + SAME) return null;
        var t = Math.min(1, along / length);
        return G.PointAt(e, end === 'a' ? t : 1 - t);
    }

    // Rounds the corner where e1's end1 meets e2's end2 at p, radius r.
    function FilletEnds(doc, e1, end1, e2, end2, p, radius, segs, options) {
        var prev, next, made;
        if (e1.type === 'line' && e2.type === 'line') {
            prev = e1[Other(end1)]; next = e2[Other(end2)];
            made = G.CornerFillet(prev, p, next, radius);
            if (!made.ok) return Fail(FilletReason(made, radius));
            var arc = { type : 'arc', a : made.from, b : made.to, sw : made.sw, segs : segs || 0 };
            var n1 = MoveEnd(e1, end1, made.from), n2 = MoveEnd(e2, end2, made.to);
            return Apply(doc, [ [ e1.id, n1 ], [ e2.id, n2 ] ], [ arc ], options, 'Filleted, radius ' + G.FormatMm(radius, 2) + ' mm.');
        }
        return FilletCurved(doc, e1, end1, e2, end2, p, radius, segs, options);
    }

    function FilletReason(made, radius) {
        if (made.reason === 'straight') return 'Those edges run straight on; there is no corner to round.';
        if (made.reason === 'radius') return 'Type a radius above nothing first (e.g. 10).';
        return 'A ' + G.FormatMm(radius, 2) + ' mm radius needs ' + G.FormatMm(made.setback, 2) + ' mm along each edge, and the shorter has ' + G.FormatMm(made.room, 2) + ' mm. Use a smaller radius.';
    }

    // Line-arc or arc-arc: the centre is where the two edges' parallels at the
    // radius cross; the tangent points are the centre's feet on each.
    function FilletCurved(doc, e1, end1, e2, end2, p, radius, segs, options) {
        var candidates = [];
        [ -1, 1 ].forEach(function (s1) {
            [ -1, 1 ].forEach(function (s2) {
                var o1 = G.OffsetEntity(e1, radius * s1), o2 = G.OffsetEntity(e2, radius * s2);
                if (!o1 || !o2) return;
                ExtendedMeets(o1, o2).forEach(function (c) {
                    var t1 = Foot(e1, c), t2 = Foot(e2, c);
                    if (!t1 || !t2) return;
                    if (Math.abs(G.Dist(c, t1.p) - radius) > 1e-6 || Math.abs(G.Dist(c, t2.p) - radius) > 1e-6) return;
                    candidates.push({ c : c, p1 : t1.p, p2 : t2.p, score : G.Dist(t1.p, p) + G.Dist(t2.p, p) });
                });
            });
        });
        candidates.sort(function (a, b) { return a.score - b.score; });
        var best = candidates[0];
        if (!best) return Fail('No ' + G.FormatMm(radius, 2) + ' mm radius fits between those edges. Try a smaller one.');
        var sw = Math.atan2(best.p2.y - best.c.y, best.p2.x - best.c.x) - Math.atan2(best.p1.y - best.c.y, best.p1.x - best.c.x);
        while (sw > Math.PI) sw -= G.TAU;
        while (sw < -Math.PI) sw += G.TAU;
        var arc = { type : 'arc', a : best.p1, b : best.p2, sw : sw, segs : segs || 0 };
        var n1 = MoveEnd(e1, end1, best.p1), n2 = MoveEnd(e2, end2, best.p2);
        if (!n1 || !n2) return Fail('The fillet does not fit on those edges.');
        return Apply(doc, [ [ e1.id, n1 ], [ e2.id, n2 ] ], [ arc ], options, 'Filleted, radius ' + G.FormatMm(radius, 2) + ' mm.');
    }

    // The foot of a point on an entity, only if it lands inside it.
    function Foot(e, c) {
        if (e.type === 'line') {
            var ab = G.Sub(e.b, e.a);
            var t = G.Dot(G.Sub(c, e.a), ab) / G.Dot(ab, ab);
            if (t < -1e-9 || t > 1 + 1e-9) return null;
            return { p : G.Lerp(e.a, e.b, Math.max(0, Math.min(1, t))) };
        }
        var circle = G.CircleOf(e);
        var u = G.Unit(G.Sub(c, circle.c));
        var cands = [ G.Add(circle.c, G.Mul(u, circle.r)), G.Sub(circle.c, G.Mul(u, circle.r)) ];
        for (var i = 0; i < cands.length; i++) {
            var q = cands[i];
            if (e.type === 'circle' || G.AngleParam(circle.g, Math.atan2(q.y - circle.c.y, q.x - circle.c.x), 1e-9) !== null) return { p : q };
        }
        return null;
    }

    function FilletAt(doc, key, radius, segs, options) {
        var corner = CornerAt(doc, key);
        if (!corner.ok) return corner;
        return FilletEnds(doc, corner.e1, corner.end1, corner.e2, corner.end2, corner.p, radius, segs, options);
    }

    // Two picked edges: brought to a corner first (unless they already share
    // one), then rounded there. Radius 0 is just the corner.
    function FilletPair(doc, id1, pick1, id2, pick2, radius, segs, options) {
        if (!(radius > 0)) return Corner(doc, id1, pick1, id2, pick2, options);
        var work = options && options.dryRun ? D.Deserialize(D.Serialize(doc)) : doc;
        var corner = Corner(work, id1, pick1, id2, pick2, {});
        if (!corner.ok) return corner;
        D.Heal(work, 1e-4);
        var key = D.KeyOf(corner.point);
        var result = FilletAt(work, key, radius, segs, options);
        if (!result.ok && !(options && options.dryRun)) return result;
        return result;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Chamfer
    // -------------------------------------------------------------------------

    function ChamferEnds(doc, e1, end1, e2, end2, p, d1, d2, options) {
        var second = Number.isFinite(d2) ? d2 : d1;
        if (!(d1 > 0) || !(second > 0)) return Fail('Type a chamfer distance above nothing first (e.g. 5, or 5,10 for unequal).');
        var q1 = PointInFrom(e1, end1, d1), q2 = PointInFrom(e2, end2, second);
        if (!q1 || !q2) {
            var room = Math.min(G.Length(e1), G.Length(e2));
            return Fail('The chamfer needs ' + G.FormatMm(Math.max(d1, second), 2) + ' mm along each edge and the shorter has ' + G.FormatMm(room, 2) + ' mm.');
        }
        if (e1.type === 'line' && e2.type === 'line') {
            var straight = G.CornerChamfer(e1[Other(end1)], p, e2[Other(end2)], d1, second);
            if (!straight.ok && straight.reason === 'straight') return Fail('Those edges run straight on; there is no corner to cut.');
        }
        var n1 = MoveEnd(e1, end1, q1), n2 = MoveEnd(e2, end2, q2);
        if (!n1 || !n2) return Fail('The chamfer does not fit on those edges.');
        var cut = { type : 'line', a : G.Copy(q1), b : G.Copy(q2) };
        return Apply(doc, [ [ e1.id, n1 ], [ e2.id, n2 ] ], [ cut ], options,
                     'Chamfered ' + G.FormatMm(d1, 2) + (second !== d1 ? ' x ' + G.FormatMm(second, 2) : '') + ' mm.');
    }

    function ChamferAt(doc, key, d1, d2, options) {
        var corner = CornerAt(doc, key);
        if (!corner.ok) return corner;
        return ChamferEnds(doc, corner.e1, corner.end1, corner.e2, corner.end2, corner.p, d1, d2, options);
    }

    function ChamferPair(doc, id1, pick1, id2, pick2, d1, d2, options) {
        var work = options && options.dryRun ? D.Deserialize(D.Serialize(doc)) : doc;
        var corner = Corner(work, id1, pick1, id2, pick2, {});
        if (!corner.ok) return corner;
        D.Heal(work, 1e-4);
        return ChamferAt(work, D.KeyOf(corner.point), d1, d2, options);
    }

    // Replaces entities and adds new ones, or previews it.
    function Apply(doc, replacements, additions, options, message) {
        if (replacements.some(function (r) { return !r[1]; })) return Fail('That does not fit on those edges.');
        if (options && options.dryRun) {
            return Ok('', { preview : {
                add    : replacements.map(function (r) { return r[1]; }).concat(additions),
                remove : replacements.map(function (r) { return D.Get(doc, r[0]); }).filter(Boolean)
            } });
        }
        // A fillet's arc or a chamfer's cut takes the colour of the edges it
        // joins (the first picked where they differ), so a painted outline
        // stays painted.
        var inherited = null;
        replacements.forEach(function (r) { var old = D.Get(doc, r[0]); if (!inherited && old && old.paint) inherited = old.paint; });
        replacements.forEach(function (r) { D.Replace(doc, r[0], [ r[1] ]); });
        additions.forEach(function (e) { if (inherited && !e.paint) e.paint = inherited; D.Add(doc, e); });
        return Ok(message);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Offset
    // -------------------------------------------------------------------------

    // The chain through `id`, each entity turned to run the same way:
    // { list:[entity], closed }.
    function OrientedChain(doc, id) {
        var ids = D.ChainOf(doc, id);
        var first = D.Get(doc, ids[0]);
        if (!first) return null;
        if (first.type === 'circle') return { list : [ G.Clone(first) ], closed : true };
        var list = [];
        var cursorKey = null;
        if (ids.length > 1) {
            var second = D.Get(doc, ids[1]);
            var keysSecond = [ D.KeyOf(second.a), D.KeyOf(second.b) ];
            cursorKey = keysSecond.indexOf(D.KeyOf(first.b)) >= 0 ? D.KeyOf(first.a) : D.KeyOf(first.b);
        } else {
            cursorKey = D.KeyOf(first.a);
        }
        ids.forEach(function (eid) {
            var e = D.Get(doc, eid);
            var forward = D.KeyOf(e.a) === cursorKey;
            var oriented = forward ? G.Clone(e) : G.Reverse(e);
            oriented.id = eid;
            list.push(oriented);
            cursorKey = D.KeyOf(oriented.b);
        });
        var closed = list.length > 1 && D.KeyOf(list[list.length - 1].b) === D.KeyOf(list[0].a);
        return { list : list, closed : closed };
    }

    // Which side of a chain a point is on: +1 left of the way it runs, -1
    // right, and how far off it is (TV SideOf, against the nearest edge).
    function SideOf(chain, p) {
        var best = null;
        chain.list.forEach(function (e) {
            var near = G.Nearest(e, p);
            if (!best || near.d < best.d) best = { d : near.d, e : e, t : near.t, at : near.p };
        });
        if (!best) return { sign : 1, distance : 0 };
        if (best.e.type === 'circle') {
            var inside = G.Dist(p, best.e.c) < best.e.r;
            return { sign : inside ? -1 : 1, distance : best.d };
        }
        var tangent = G.TangentAt(best.e, best.t);
        var cross = G.Cross(tangent, G.Sub(p, best.at));
        return { sign : cross >= 0 ? 1 : -1, distance : best.d };
    }

    // Where two consecutive offset pieces meet: their own shared point when
    // they already touch (a tangent joint), else where their lines / circles
    // cross nearest the old corner.
    function JoinPoint(o1, o2, corner) {
        if (G.Same(o1.b, o2.a, 1e-7)) return G.Copy(o1.b);
        var meets = ExtendedMeets(o1, o2);
        if (!meets.length) return null;
        return Nearest(meets, corner);
    }

    function OffsetChain(doc, id, distance, options) {
        var chain = OrientedChain(doc, id);
        if (!chain) return Fail('Nothing to offset there.');
        if (!(Math.abs(distance) > SAME)) return Fail('Type an offset distance above nothing.');

        if (chain.list.length === 1 && chain.list[0].type === 'circle') {
            var circ = G.OffsetEntity(chain.list[0], distance);
            if (!circ) return Fail('The circle is smaller than the offset.');
            delete circ.id;
            return Finish(doc, [ circ ], options, 'Offset ' + G.FormatMm(Math.abs(distance), 2) + ' mm.');
        }

        var items = chain.list.map(function (e) {
            return { src : e, off : G.OffsetEntity(e, distance), corner : G.Copy(e.b) };
        });
        var limit = Math.abs(distance) * G.MITRE_LIMIT;
        var closed = chain.closed;

        for (var pass = 0; pass < 64; pass++) {
            items = items.filter(function (it) { return !!it.off; });
            if (items.length < (closed ? 2 : 1)) return Fail('Offset by ' + G.FormatMm(Math.abs(distance), 2) + ' mm, nothing of this outline is left.');
            var count = items.length;
            var joints = [];
            for (var i = 0; i < count; i++) {
                if (!closed && i === count - 1) { joints.push(null); break; }
                var a = items[i], b = items[(i + 1) % count];
                joints.push({ p : JoinPoint(a.off, b.off, a.corner), corner : a.corner });
            }
            // An edge whose two joints have swapped places along it is swallowed.
            var dropped = -1;
            for (var k = 0; k < count && dropped < 0; k++) {
                var startJ = (closed || k > 0) ? joints[(k - 1 + count) % count] : null;
                var endJ = joints[k];
                var it2 = items[k];
                var from = startJ && startJ.p ? startJ.p : it2.off.a;
                var to = endJ && endJ.p ? endJ.p : it2.off.b;
                if (it2.off.type === 'line') {
                    var along = G.Dot(G.Sub(to, from), G.Sub(it2.off.b, it2.off.a));
                    if (along < -SAME) dropped = k;
                } else {
                    var trimmed = TrimArcBetween(it2.off, from, to);
                    if (!trimmed) dropped = k;
                }
            }
            if (dropped < 0) {
                return BuildOffset(doc, items, joints, closed, limit, options, distance);
            }
            items.splice(dropped, 1);
        }
        return Fail('That offset folds the outline over itself. Try a smaller distance.');
    }

    // An arc cut back (or run on) to new ends on its circle, same direction;
    // null if the new ends cross over (the arc was swallowed).
    function TrimArcBetween(arc, from, to) {
        var g = G.ArcGeom(arc);
        if (!g) return null;
        var sign = g.sw >= 0 ? 1 : -1;
        var angFrom = Math.atan2(from.y - g.c.y, from.x - g.c.x);
        var angTo = Math.atan2(to.y - g.c.y, to.x - g.c.x);
        var sweep = sign * G.NormAngle((angTo - angFrom) * sign);
        // A swallowed arc's ends swap, which reads as almost a whole turn.
        if (!(Math.abs(sweep) > 1e-9) || Math.abs(sweep) > Math.abs(g.sw) + Math.PI) return null;
        return { type : 'arc', a : G.Copy(from), b : G.Copy(to), sw : sweep, segs : arc.segs };
    }

    function BuildOffset(doc, items, joints, closed, limit, options, distance) {
        var count = items.length;
        var out = [];
        for (var i = 0; i < count; i++) {
            var it = items[i];
            var startJ = (closed || i > 0) ? joints[(i - 1 + count) % count] : null;
            var endJ = joints[i];
            var from = it.off.a, to = it.off.b;
            var startMitre = startJ && startJ.p && G.Dist(startJ.p, startJ.corner) <= limit + SAME;
            var endMitre = endJ && endJ.p && G.Dist(endJ.p, endJ.corner) <= limit + SAME;
            if (startMitre) from = startJ.p;
            if (endMitre) to = endJ.p;
            var piece = it.off.type === 'line' ? { type : 'line', a : G.Copy(from), b : G.Copy(to) } : TrimArcBetween(it.off, from, to);
            if (piece && it.src.paint) piece.paint = it.src.paint;
            if (piece && G.Dist(piece.a, piece.b) > SAME) out.push(piece);
            // Past the mitre limit (or no meeting at all) the corner is cut square.
            if (endJ && !endMitre) {
                var next = items[(i + 1) % count].off;
                var square = { type : 'line', a : G.Copy(it.off.b), b : G.Copy(next.a) };
                if (it.src.paint) square.paint = it.src.paint;
                if (G.Dist(it.off.b, next.a) > SAME) out.push(square);
            }
        }
        if (!out.length) return Fail('Nothing of the outline is left at that offset.');
        return Finish(doc, out, options, 'Offset ' + G.FormatMm(Math.abs(distance), 2) + ' mm.');
    }

    function Finish(doc, entities, options, message) {
        if (options && options.dryRun) return Ok('', { preview : { add : entities, remove : [] } });
        var ids = entities.map(function (e) { delete e.id; return D.Add(doc, e); });
        return Ok(message, { ids : ids });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Split
    // -------------------------------------------------------------------------

    // Cuts every entity running through p there (TV Split: a cut at a
    // crossing splits every line through that point).
    function SplitThrough(doc, p, options) {
        var through = doc.ents.filter(function (e) {
            var near = G.Nearest(e, p);
            if (near.d > 1e-4) return false;
            return e.type === 'circle' || (near.t > 1e-7 && near.t < 1 - 1e-7);
        });
        if (!through.length) return Fail('No edge runs through that point (its ends are already joints).');
        if (options && options.dryRun) return Ok('', { count : through.length });
        var count = 0;
        through.forEach(function (e) { if (D.SplitAt(doc, e.id, G.Nearest(e, p).p).length) count += 1; });
        return count ? Ok('Split ' + count + ' edge(s).') : Fail('Nothing to split there.');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Export
    // -------------------------------------------------------------------------

    window.Na__DrawProfile__Ops = {
        CutParams : CutParams,
        MoveEnd : MoveEnd,
        CornerAt : CornerAt,
        Trim : Trim,
        TrimFence : TrimFence,
        Extend : Extend,
        Corner : Corner,
        FilletAt : FilletAt,
        FilletPair : FilletPair,
        ChamferAt : ChamferAt,
        ChamferPair : ChamferPair,
        OrientedChain : OrientedChain,
        SideOf : SideOf,
        OffsetChain : OffsetChain,
        SplitThrough : SplitThrough
    };

    // endregion ----------------------------------------------------------------
})();
