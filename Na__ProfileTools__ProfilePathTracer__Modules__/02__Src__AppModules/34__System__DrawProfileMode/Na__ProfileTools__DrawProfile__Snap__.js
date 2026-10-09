/* =============================================================================
   NA PROFILE TOOLS - DRAW PROFILE - SNAP
   =============================================================================
   FILE       : Na__ProfileTools__DrawProfile__Snap__.js
   NAMESPACE  : window.Na__DrawProfile__Snap
   PURPOSE    : Where the cursor really is: object snaps, tracking off acquired
                points, grid snap, and the axis lock / ortho constraint.

   THE ORDER (TV ObjectSnap, then ViewportSnapMove's tracking)
     1. A point snap in reach - endpoint, intersection, midpoint, centre,
        quadrant, perpendicular - scored distance x weight, lowest wins
        (end 1, int 1.05, mid 1.25, cen 1.25, quad 1.25, perp 1.4).
     2. Tracking - level or plumb with a point the cursor rested on for
        400 ms (up to three), or with the point the line is being drawn
        from; two guides cross at a point, one guide meets the edge under
        the cursor.
     3. Nearest - a point ON an edge, only when nothing else is in reach.
     4. The grid, which needs no reach (it is everywhere).
     5. The cursor itself.

   CONSTRAINTS (TV AxisLock, OrthoMode)
     An arrow-key lock beats a snap but the snap still supplies the free
     coordinate; Ortho XOR Shift holds the nearer axis, chosen by the free
     cursor, the coordinate along it taken from the snap.
   ============================================================================= */

(function () {
    'use strict';

    var G = window.Na__DrawProfile__Geom;
    var D = window.Na__DrawProfile__Doc;

    // -------------------------------------------------------------------------
    // REGION | Tracking State
    // -------------------------------------------------------------------------

    function CreateState() {
        return { acquired : [] };
    }

    function Acquire(state, snap, max) {
        if (!snap || !snap.p || [ 'end', 'mid', 'int', 'cen', 'quad', 'origin' ].indexOf(snap.kind) < 0) return false;
        var exists = state.acquired.some(function (a) { return G.Same(a.p, snap.p, 1e-6); });
        if (exists) return false;
        state.acquired.push({ p : G.Copy(snap.p), kind : snap.kind });
        while (state.acquired.length > (max || 3)) state.acquired.shift();
        return true;
    }

    function ClearAcquired(state) {
        state.acquired.length = 0;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Grid
    // -------------------------------------------------------------------------

    // The step a grid snap rounds to: the minor spacing while the minor grid
    // is shown, else the major (TV DrawingGrid State).
    function GridStep(grid) {
        var major = Math.max(grid.MajorMinMm || 1, grid.MajorMm || 10);
        var minor = Math.max(grid.MinorMinMm || 0.25, major / Math.max(1, grid.Divisions || 10));
        return grid.ShowMinor === false ? major : minor;
    }

    function RoundToGrid(p, step) {
        var round6 = function (v) { return Math.round(v * 1e6) / 1e6; };
        return { x : round6(Math.round(p.x / step) * step), y : round6(Math.round(p.y / step) * step) };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Find
    // -------------------------------------------------------------------------

    // ctx: { doc, scale, cursor, from, settings, exclude (Set of ids),
    //        excludeKeys (Set of location keys), extra ([{p, kind, label}]),
    //        track (state), noTrack }
    // Returns { p, kind, label, target, entId, guides, snapped }.
    function Find(ctx) {
        var cfg = ctx.settings;
        var snapCfg = cfg.Snap;
        var radius = snapCfg.RadiusPx / ctx.scale;
        var cursor = ctx.cursor;
        var exclude = ctx.exclude || new Set();
        var excludeKeys = ctx.excludeKeys || new Set();
        var modes = snapCfg.Modes;
        var weights = snapCfg.Weights;
        var best = null;
        var nearest = null;
        var reach = [];

        function offer(p, kind, entId, target) {
            if (!p) return;
            if (Math.abs(p.x - cursor.x) > radius || Math.abs(p.y - cursor.y) > radius) return;
            var d = G.Dist(p, cursor);
            if (d > radius) return;
            var score = d * (weights[kind] || 1);
            if (!best || score < best.score) best = { p : G.Copy(p), kind : kind, entId : entId || null, target : target || 'shape', score : score };
        }

        if (snapCfg.On) {
            ctx.doc.ents.forEach(function (e) {
                if (exclude.has(e.id)) return;
                var box = G.Bbox(e);
                if (cursor.x < box.minX - radius || cursor.x > box.maxX + radius || cursor.y < box.minY - radius || cursor.y > box.maxY + radius) return;
                reach.push(e);

                if (e.type !== 'circle') {
                    if (modes.end) {
                        if (!excludeKeys.has(D.KeyOf(e.a))) offer(e.a, 'end', e.id);
                        if (!excludeKeys.has(D.KeyOf(e.b))) offer(e.b, 'end', e.id);
                    }
                    if (modes.mid) offer(G.MidPoint(e), 'mid', e.id);
                }
                if (e.type !== 'line') {
                    var circle = G.CircleOf(e);
                    if (circle) {
                        if (modes.cen) offer(circle.c, 'cen', e.id);
                        if (modes.quad) {
                            [ 0, Math.PI / 2, Math.PI, Math.PI * 1.5 ].forEach(function (ang) {
                                if (e.type === 'arc' && G.AngleParam(circle.g, ang, 1e-9) === null) return;
                                offer({ x : circle.c.x + (circle.r * Math.cos(ang)), y : circle.c.y + (circle.r * Math.sin(ang)) }, 'quad', e.id);
                            });
                        }
                    }
                }
                if (modes.perp && ctx.from) {
                    PerpendicularFeet(e, ctx.from).forEach(function (p) { offer(p, 'perp', e.id); });
                }
                if (modes.near) {
                    var near = G.Nearest(e, cursor);
                    if (near.d <= radius && (!nearest || near.d < nearest.d)) nearest = { p : near.p, d : near.d, entId : e.id };
                }
            });

            if (modes.int && reach.length > 1) {
                var list = reach.slice(0, snapCfg.MaxCrossingEntities || 48);
                for (var i = 0; i < list.length; i++) {
                    for (var j = i + 1; j < list.length; j++) {
                        G.Intersect(list[i], list[j]).forEach(function (hit) {
                            var endOfBoth = IsEndParam(list[i], hit.t1) && IsEndParam(list[j], hit.t2);
                            if (!endOfBoth) offer(hit.p, 'int', list[i].id);
                        });
                    }
                }
            }

            (ctx.extra || []).forEach(function (item) { offer(item.p, item.kind || 'end', null, item.target || 'shape'); });
            if (modes.end) offer({ x : 0, y : 0 }, 'end', null, 'datum');
        }

        var label = function (kind, target) {
            if (target === 'datum') return cfg.Snap.Labels.origin;
            return cfg.Snap.Labels[kind] || '';
        };

        if (best) {
            return { p : best.p, kind : best.kind, label : label(best.kind, best.target), target : best.target, entId : best.entId, guides : [], snapped : true };
        }

        // TRACKING | level / plumb with acquired points and the band's anchor
        var guides = ctx.noTrack ? null : Track(ctx, radius, reach, nearest);
        if (guides) return guides;

        if (nearest) {
            return { p : G.Copy(nearest.p), kind : 'near', label : label('near'), target : 'shape', entId : nearest.entId, guides : [], snapped : true };
        }

        if (cfg.Grid.Snap) {
            return { p : RoundToGrid(cursor, GridStep(cfg.Grid)), kind : 'grid', label : label('grid'), target : 'grid', entId : null, guides : [], snapped : true };
        }

        return { p : G.Copy(cursor), kind : null, label : '', target : null, entId : null, guides : [], snapped : false };
    }

    function IsEndParam(e, t) {
        if (e.type === 'circle') return false;
        return t <= 1e-6 || t >= 1 - 1e-6;
    }

    // Feet of perpendiculars from `from` onto an entity, inside it.
    function PerpendicularFeet(e, from) {
        if (e.type === 'line') {
            var ab = G.Sub(e.b, e.a);
            var len2 = G.Dot(ab, ab);
            if (!(len2 > 0)) return [];
            var t = G.Dot(G.Sub(from, e.a), ab) / len2;
            if (t <= 1e-6 || t >= 1 - 1e-6) return [];
            return [ G.Lerp(e.a, e.b, t) ];
        }
        var circle = G.CircleOf(e);
        if (!circle) return [];
        var dir = G.Sub(from, circle.c);
        if (!(G.Len(dir) > 1e-9)) return [];
        var u = G.Unit(dir);
        var pts = [ G.Add(circle.c, G.Mul(u, circle.r)), G.Sub(circle.c, G.Mul(u, circle.r)) ];
        if (e.type === 'circle') return pts;
        return pts.filter(function (p) { return G.AngleParam(circle.g, Math.atan2(p.y - circle.c.y, p.x - circle.c.x), 1e-9) !== null; });
    }

    // The tracking answer, or null when no guide is in reach.
    function Track(ctx, radius, reach, nearest) {
        var anchors = [];
        if (ctx.track) ctx.track.acquired.forEach(function (a) { anchors.push(a.p); });
        if (ctx.from) anchors.push(ctx.from);
        if (!anchors.length) return null;

        var cursor = ctx.cursor;
        var plumb = null, level = null;
        anchors.forEach(function (q) {
            var dx = Math.abs(cursor.x - q.x), dy = Math.abs(cursor.y - q.y);
            if (dx <= radius && (!plumb || dx < plumb.d)) plumb = { q : q, d : dx };
            if (dy <= radius && (!level || dy < level.d)) level = { q : q, d : dy };
        });
        if (!plumb && !level) return null;

        // Both guides at once: they meet at a point, unless it is the anchor itself.
        if (plumb && level && !(plumb.q === level.q)) {
            var meet = { x : plumb.q.x, y : level.q.y };
            return { p : meet, kind : 'track', label : 'Tracking', target : 'shape', entId : null, snapped : true,
                     guides : [ { axis : 'y', through : G.Copy(plumb.q) }, { axis : 'x', through : G.Copy(level.q) } ] };
        }

        var guide = plumb ? { axis : 'y', through : G.Copy(plumb.q) } : { axis : 'x', through : G.Copy(level.q) };

        // One guide meeting the edge under the cursor.
        if (nearest) {
            var lineA = guide.axis === 'y' ? { x : guide.through.x, y : guide.through.y - 1 } : { x : guide.through.x - 1, y : guide.through.y };
            var lineB = guide.axis === 'y' ? { x : guide.through.x, y : guide.through.y + 1 } : { x : guide.through.x + 1, y : guide.through.y };
            var target = null;
            reach.forEach(function (e) {
                if (e.id !== nearest.entId) return;
                RayHitsBoth(lineA, lineB, e).forEach(function (p) {
                    var d = G.Dist(p, cursor);
                    if (d <= radius && (!target || d < target.d)) target = { p : p, d : d };
                });
            });
            if (target) {
                return { p : target.p, kind : 'int', label : 'On edge, tracking', target : 'shape', entId : nearest.entId, snapped : true, guides : [ guide ] };
            }
        }

        var p = guide.axis === 'y' ? { x : guide.through.x, y : cursor.y } : { x : cursor.x, y : guide.through.y };
        if (ctx.settings.Grid.Snap) {
            var g = RoundToGrid(p, GridStep(ctx.settings.Grid));
            if (guide.axis === 'y') p.y = g.y; else p.x = g.x;
        }
        return { p : p, kind : 'track', label : 'Tracking', target : 'shape', entId : null, snapped : true, guides : [ guide ] };
    }

    function RayHitsBoth(a, b, e) {
        var dir = G.Unit(G.Sub(b, a));
        return G.RayHits(a, dir, e).map(function (h) { return h.p; });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Constraints (TV AxisLock + OrthoMode)
    // -------------------------------------------------------------------------

    // anchor: the point the band runs from. snap: a Find result. aim: the raw
    // cursor. Returns { p, lock: 'x' | 'y' | null } - 'x' when the band is
    // held level (moving along x), 'y' when plumb.
    function Constrain(anchor, snap, aim, axisLock, holdNearest) {
        if (!anchor) return { p : G.Copy(snap.p), lock : null };
        if (axisLock === 'x') return { p : { x : snap.p.x, y : anchor.y }, lock : 'x' };
        if (axisLock === 'y') return { p : { x : anchor.x, y : snap.p.y }, lock : 'y' };
        if (holdNearest) {
            var across = Math.abs(aim.x - anchor.x) >= Math.abs(aim.y - anchor.y);
            var source = snap.snapped ? snap.p : aim;
            return across ? { p : { x : source.x, y : anchor.y }, lock : 'x' } : { p : { x : anchor.x, y : source.y }, lock : 'y' };
        }
        return { p : G.Copy(snap.p), lock : null };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Export
    // -------------------------------------------------------------------------

    window.Na__DrawProfile__Snap = {
        CreateState : CreateState,
        Acquire : Acquire,
        ClearAcquired : ClearAcquired,
        GridStep : GridStep,
        RoundToGrid : RoundToGrid,
        Find : Find,
        Constrain : Constrain,
        PerpendicularFeet : PerpendicularFeet
    };

    // endregion ----------------------------------------------------------------
})();
