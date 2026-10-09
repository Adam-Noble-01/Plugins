/* =============================================================================
   NA PROFILE TOOLS - DRAW PROFILE - VIEWPORT
   =============================================================================
   FILE       : Na__ProfileTools__DrawProfile__Viewport__.js
   NAMESPACE  : window.Na__DrawProfile__View
   PURPOSE    : The drawing canvas: the view transform (zoom about the cursor,
                pan, zoom to fit) and everything drawn on it - grid, datum,
                the profile and its fill, construction, dimensions, check
                markers, grips, the selection box, snap glyphs and tracking
                guides, and whatever preview the active tool asks for.

   SPACE      world: profile millimetres, y up. screen: CSS pixels, y down.
              sx = ox + x * scale, sy = oy - y * scale.

   @delegate  : TrueVision Layout Editor
                27__System__DrawingGrid  lines mode: solid major over dotted
                                         [1,2] minor on half pixels; points
                                         mode: 2.5 / 1.5 px dots; a family
                                         closer than 6 px is not drawn
                28__System__ObjectSnap   the glyphs (AutoCAD's), white casing
                                         4.4 under a 2.2 ink, 18 % tint
                33__System__DrawingAxes  F9 red / green lines through the cursor
                15__Core__Markup         dimension skeleton: gap, overshoot,
                                         45 deg ticks, text never upside down
   ============================================================================= */

(function () {
    'use strict';

    var G = window.Na__DrawProfile__Geom;
    var D = window.Na__DrawProfile__Doc;

    // -------------------------------------------------------------------------
    // REGION | Glyphs (TV ObjectSnap Glyphs, 24 x 24 about 12, 12)
    // -------------------------------------------------------------------------

    var GLYPHS = {
        end   : { path : 'M5 5 H19 V19 H5 Z', closed : true },
        mid   : { path : 'M12 4.5 L20 18.5 H4 Z', closed : true },
        int   : { path : 'M5 5 L19 19 M19 5 L5 19' },
        perp  : { path : 'M5 4 V19 H20 M5 12 H12 V19' },
        cen   : { path : 'M12 4.5 A7.5 7.5 0 1 0 12 19.5 A7.5 7.5 0 1 0 12 4.5 Z', closed : true },
        quad  : { path : 'M12 3.5 L20.5 12 L12 20.5 L3.5 12 Z', closed : true },
        near  : { path : 'M5 5 H19 L5 19 H19 Z', closed : true },
        grid  : { path : 'M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 Z', fill : 'M12 9.2 A2.8 2.8 0 1 0 12 14.8 A2.8 2.8 0 1 0 12 9.2 Z', scale : 0.6 },
        track : { path : 'M12 4.5 A7.5 7.5 0 1 0 12 19.5 A7.5 7.5 0 1 0 12 4.5 Z', dash : [ 3.2, 2.6 ] }
    };
    var PATH_CACHE = {};

    function GlyphPath(source) {
        if (!PATH_CACHE[source]) PATH_CACHE[source] = new Path2D(source);
        return PATH_CACHE[source];
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | View Transform
    // -------------------------------------------------------------------------

    function Create(canvas, config) {
        var view = {
            canvas : canvas,
            ctx    : canvas.getContext('2d'),
            dpr    : window.devicePixelRatio || 1,
            w      : 0,
            h      : 0,
            scale  : config.View.StartScale,
            ox     : 0,
            oy     : 0,
            hasFit : false
        };
        Resize(view);
        view.ox = view.w * 0.3;
        view.oy = view.h * 0.7;
        return view;
    }

    function Resize(view) {
        var rect = view.canvas.getBoundingClientRect();
        var w = Math.max(1, Math.round(rect.width)), h = Math.max(1, Math.round(rect.height));
        var dpr = window.devicePixelRatio || 1;
        if (w === view.w && h === view.h && dpr === view.dpr) return false;
        var oldW = view.w, oldH = view.h;
        view.w = w; view.h = h; view.dpr = dpr;
        view.canvas.width = Math.round(w * dpr);
        view.canvas.height = Math.round(h * dpr);
        if (oldW && oldH) { view.ox += (w - oldW) / 2; view.oy += (h - oldH) / 2; }
        return true;
    }

    function W2S(view, p) { return { x : view.ox + (p.x * view.scale), y : view.oy - (p.y * view.scale) }; }
    function S2W(view, sx, sy) { return { x : (sx - view.ox) / view.scale, y : (view.oy - sy) / view.scale }; }

    function ZoomAt(view, sx, sy, factor, config) {
        var before = S2W(view, sx, sy);
        var next = Math.max(config.View.MinScale, Math.min(config.View.MaxScale, view.scale * factor));
        view.scale = next;
        view.ox = sx - (before.x * next);
        view.oy = sy + (before.y * next);
    }

    function Pan(view, dx, dy) {
        view.ox += dx;
        view.oy += dy;
    }

    function Fit(view, box, config) {
        if (!box) return;
        var pad = config.View.FitPaddingPx;
        var w = Math.max(1e-3, box.maxX - box.minX), h = Math.max(1e-3, box.maxY - box.minY);
        var scale = Math.min((view.w - (pad * 2)) / w, (view.h - (pad * 2)) / h);
        view.scale = Math.max(config.View.MinScale, Math.min(config.View.MaxScale, scale));
        var cx = (box.minX + box.maxX) / 2, cy = (box.minY + box.maxY) / 2;
        view.ox = (view.w / 2) - (cx * view.scale);
        view.oy = (view.h / 2) + (cy * view.scale);
        view.hasFit = true;
    }

    function VisibleBox(view) {
        var a = S2W(view, 0, view.h), b = S2W(view, view.w, 0);
        return { minX : a.x, minY : a.y, maxX : b.x, maxY : b.y };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Render
    // -------------------------------------------------------------------------

    // ed: the editor state. Draws everything, back to front.
    function Render(view, ed) {
        var ctx = view.ctx;
        var cfg = ed.settings;
        ctx.setTransform(view.dpr, 0, 0, view.dpr, 0, 0);
        ctx.fillStyle = cfg.Colours.Paper;
        ctx.fillRect(0, 0, view.w, view.h);

        if (cfg.Grid.Show) DrawGrid(view, cfg);
        DrawOriginAxes(view, cfg);
        DrawLoopFill(view, ed);
        DrawEntities(view, ed);
        if (PaintOn(ed)) DrawPaintVertices(view, ed);
        DrawDimensions(view, ed);
        DrawLoopInfo(view, ed);
        DrawMarkers(view, ed);
        DrawDatum(view, cfg);
        DrawGrips(view, ed);
        if (ed.tool && typeof ed.tool.draw === 'function') {
            ctx.save();
            try { ed.tool.draw(ed, ctx, view); } catch (err) { console.error('[DrawProfile] tool draw failed', err); }
            ctx.restore();
        }
        DrawBox(view, ed);
        DrawGuides(view, ed);
        DrawDrawingAxes(view, ed);
        DrawSnap(view, ed);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Grid
    // -------------------------------------------------------------------------

    function DrawGrid(view, cfg) {
        var grid = cfg.Grid;
        var ctx = view.ctx;
        var major = Math.max(grid.MajorMinMm || 1, grid.MajorMm);
        var minor = Math.max(grid.MinorMinMm || 0.25, major / Math.max(1, grid.Divisions));
        var showMajor = major * view.scale >= grid.MinPx;
        var showMinor = grid.ShowMinor !== false && grid.Divisions > 1 && minor * view.scale >= grid.MinPx;

        // Zoomed far out the grid is never simply gone: the major spacing is
        // multiplied by ten until it is far enough apart to draw.
        var coarse = major;
        while (!showMajor && coarse * view.scale < grid.MinPx && coarse < 1e7) coarse *= 10;
        var majorStep = showMajor ? major : coarse;

        var box = VisibleBox(view);
        if (grid.Type === 'points') {
            if (showMinor) DrawDots(view, box, minor, majorStep, grid.MinorColour, 1.5, true);
            DrawDots(view, box, majorStep, 0, grid.MajorColour, 2.5, false);
            return;
        }
        // Lines are drawn lighter than TV's paper grid: here the grid sits
        // under every edge of the profile and must not compete with it.
        ctx.save();
        ctx.globalAlpha = 0.55;
        if (showMinor) DrawLines(view, box, minor, majorStep, grid.MinorColour, [ 1, 2 ]);
        ctx.globalAlpha = 0.42;
        DrawLines(view, box, majorStep, 0, grid.MajorColour, null);
        ctx.restore();
    }

    function DrawLines(view, box, step, skipEvery, colour, dash) {
        var ctx = view.ctx;
        ctx.save();
        ctx.strokeStyle = colour;
        ctx.lineWidth = 1;
        ctx.setLineDash(dash || []);
        ctx.beginPath();
        var x0 = Math.floor(box.minX / step), x1 = Math.ceil(box.maxX / step);
        var y0 = Math.floor(box.minY / step), y1 = Math.ceil(box.maxY / step);
        if ((x1 - x0) + (y1 - y0) > 4000) { ctx.restore(); return; }
        for (var i = x0; i <= x1; i++) {
            var wx = i * step;
            if (skipEvery && IsMultiple(wx, skipEvery)) continue;
            var sx = Math.round(view.ox + (wx * view.scale)) + 0.5;
            ctx.moveTo(sx, 0); ctx.lineTo(sx, view.h);
        }
        for (var j = y0; j <= y1; j++) {
            var wy = j * step;
            if (skipEvery && IsMultiple(wy, skipEvery)) continue;
            var sy = Math.round(view.oy - (wy * view.scale)) + 0.5;
            ctx.moveTo(0, sy); ctx.lineTo(view.w, sy);
        }
        ctx.stroke();
        ctx.restore();
    }

    function DrawDots(view, box, step, skipEvery, colour, sizePx, square) {
        var ctx = view.ctx;
        var x0 = Math.floor(box.minX / step), x1 = Math.ceil(box.maxX / step);
        var y0 = Math.floor(box.minY / step), y1 = Math.ceil(box.maxY / step);
        if ((x1 - x0) * (y1 - y0) > 60000) return;
        ctx.save();
        ctx.fillStyle = colour;
        var half = sizePx / 2;
        for (var i = x0; i <= x1; i++) {
            var wx = i * step;
            var sx = view.ox + (wx * view.scale);
            for (var j = y0; j <= y1; j++) {
                var wy = j * step;
                if (skipEvery && IsMultiple(wx, skipEvery) && IsMultiple(wy, skipEvery)) continue;
                var sy = view.oy - (wy * view.scale);
                if (square || sizePx * view.dpr < 3) ctx.fillRect(sx - half, sy - half, sizePx, sizePx);
                else { ctx.beginPath(); ctx.arc(sx, sy, half, 0, G.TAU); ctx.fill(); }
            }
        }
        ctx.restore();
    }

    function IsMultiple(value, step) {
        var q = value / step;
        return Math.abs(q - Math.round(q)) < 1e-6;
    }

    function DrawOriginAxes(view, cfg) {
        var ctx = view.ctx;
        var o = W2S(view, { x : 0, y : 0 });
        ctx.save();
        ctx.strokeStyle = cfg.Colours.AxisLine;
        ctx.lineWidth = 1;
        ctx.setLineDash([ 4, 3 ]);
        ctx.beginPath();
        ctx.moveTo(0, Math.round(o.y) + 0.5); ctx.lineTo(view.w, Math.round(o.y) + 0.5);
        ctx.moveTo(Math.round(o.x) + 0.5, 0); ctx.lineTo(Math.round(o.x) + 0.5, view.h);
        ctx.stroke();
        ctx.restore();
    }

    // The datum: the orange X the Apply / Edit previews draw.
    function DrawDatum(view, cfg) {
        var ctx = view.ctx;
        var o = W2S(view, { x : 0, y : 0 });
        var arm = 7;
        ctx.save();
        ctx.strokeStyle = cfg.Colours.Datum;
        ctx.lineWidth = 2;
        ctx.lineCap = 'round';
        ctx.beginPath();
        ctx.moveTo(o.x - arm, o.y - arm); ctx.lineTo(o.x + arm, o.y + arm);
        ctx.moveTo(o.x - arm, o.y + arm); ctx.lineTo(o.x + arm, o.y - arm);
        ctx.stroke();
        ctx.restore();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Profile
    // -------------------------------------------------------------------------

    function Polyline(view, pts, closed) {
        var ctx = view.ctx;
        ctx.beginPath();
        pts.forEach(function (p, i) {
            var s = W2S(view, p);
            if (i === 0) ctx.moveTo(s.x, s.y); else ctx.lineTo(s.x, s.y);
        });
        if (closed) ctx.closePath();
    }

    function DrawLoopFill(view, ed) {
        if (!ed.analysis || !ed.analysis.ok || !ed.analysis.loop) return;
        var ctx = view.ctx;
        ctx.save();
        Polyline(view, ed.analysis.loop.points, true);
        ctx.fillStyle = PaintOn(ed) ? ed.settings.Colours.PaintFill : ed.settings.Colours.LoopFill;
        ctx.fill();
        ctx.restore();
    }

    // Edge Paint view: edges in their colours, vertices as dots.
    function PaintOn(ed) {
        return !!(window.Na__DrawProfile__Paint && ed && typeof ed.PaintView === 'function' && ed.PaintView());
    }

    function DrawEntities(view, ed) {
        var ctx = view.ctx;
        var cfg = ed.settings;
        var colours = cfg.Colours;
        var hidden = ed.hiddenIds || null;
        ctx.save();
        ctx.lineJoin = 'round';
        ctx.lineCap = 'round';

        var P = PaintOn(ed) ? window.Na__DrawProfile__Paint : null;
        var usual = P ? ed.PaintDefault() : null;

        ed.doc.ents.forEach(function (e) {
            if (hidden && hidden.has(e.id)) return;
            var pts = G.Tessellate(e, cfg.Curves);
            var closed = e.type === 'circle';
            var selected = ed.selection.has(e.id);
            var hover = ed.hoverId === e.id;

            if (selected) {
                ctx.setLineDash([]);
                ctx.strokeStyle = colours.SelectedHalo;
                ctx.lineWidth = 7;
                Polyline(view, pts, closed);
                ctx.stroke();
            }

            // EDGE PAINT: the edge in its colour, thicker; a near-white one on
            // a dark halo. An unpainted edge carries a fine white dash: it
            // takes the profile's usual colour when saved.
            if (P && !e.constr) {
                var hex = P.EdgeHex(e, usual);
                ctx.setLineDash([]);
                if (P.Luminance(hex) > 0.8) {
                    ctx.strokeStyle = colours.PaintHalo;
                    ctx.lineWidth = selected || hover ? 6 : 5;
                    Polyline(view, pts, closed);
                    ctx.stroke();
                }
                ctx.strokeStyle = hex;
                ctx.lineWidth = selected || hover ? 4 : 3;
                Polyline(view, pts, closed);
                ctx.stroke();
                if (!e.paint) {
                    ctx.setLineDash([ 2, 5 ]);
                    ctx.strokeStyle = 'rgba(255, 255, 255, 0.9)';
                    ctx.lineWidth = 1;
                    Polyline(view, pts, closed);
                    ctx.stroke();
                    ctx.setLineDash([]);
                }
                if (cfg.ShowSegments && e.type !== 'line') DrawSegmentTicks(view, pts, closed, colours.SegmentTick);
                return;
            }
            ctx.setLineDash(e.constr ? [ 6, 4 ] : []);
            ctx.strokeStyle = selected ? colours.LineSelected : (hover ? colours.LineHover : (e.constr ? colours.Construction : (ed.analysis && ed.analysis.ok ? colours.LoopStroke : colours.Line)));
            ctx.lineWidth = selected ? 2 : (hover ? 2.2 : 1.5);
            Polyline(view, pts, closed);
            ctx.stroke();

            if (cfg.ShowSegments && e.type !== 'line') DrawSegmentTicks(view, pts, closed, colours.SegmentTick);
        });
        ctx.restore();
    }

    // A painted vertex is a solid dot in its colour; an unpainted one a ring
    // in the colour it will follow (its edges', the darker where they differ).
    function DrawPaintVertices(view, ed) {
        var P = window.Na__DrawProfile__Paint;
        var ctx = view.ctx;
        ctx.save();
        ctx.setLineDash([]);
        P.Vertices(ed.doc, ed.PaintDefault()).forEach(function (v) {
            var s = W2S(view, v.p);
            if (v.explicit) {
                ctx.beginPath();
                ctx.arc(s.x, s.y, 5.2, 0, G.TAU);
                ctx.fillStyle = v.hex;
                ctx.fill();
                ctx.lineWidth = 1.6;
                ctx.strokeStyle = '#ffffff';
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(s.x, s.y, 6.6, 0, G.TAU);
                ctx.lineWidth = 1;
                ctx.strokeStyle = 'rgba(15, 23, 42, 0.8)';
                ctx.stroke();
            } else {
                ctx.beginPath();
                ctx.arc(s.x, s.y, 3.6, 0, G.TAU);
                ctx.fillStyle = '#ffffff';
                ctx.fill();
                ctx.lineWidth = 1.8;
                ctx.strokeStyle = v.hex;
                ctx.stroke();
            }
        });
        ctx.restore();
    }

    // The vertices an arc is divided into, which become real vertices of the
    // profile - shown so the count is never a surprise.
    function DrawSegmentTicks(view, pts, closed, colour) {
        if (pts.length < 3) return;
        var ctx = view.ctx;
        var a = W2S(view, pts[0]), b = W2S(view, pts[1]);
        if (G.Dist(a, b) < 5) return;
        ctx.save();
        ctx.setLineDash([]);
        ctx.fillStyle = colour;
        var last = closed ? pts.length : pts.length - 1;
        for (var i = closed ? 0 : 1; i < last; i++) {
            var s = W2S(view, pts[i]);
            ctx.fillRect(s.x - 1.5, s.y - 1.5, 3, 3);
        }
        ctx.restore();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Dimensions (TV DimensionGeometry Skeleton + ticks)
    // -------------------------------------------------------------------------

    function DimensionFrame(a, b, orient) {
        var dx = b.x - a.x, dy = b.y - a.y;
        if (orient === 'horizontal') { var sx = dx < 0 ? -1 : 1; return Math.abs(dx) > 0 ? { length : Math.abs(dx), dir : { x : sx, y : 0 }, perp : { x : 0, y : sx }, axis : 'x' } : null; }
        if (orient === 'vertical')   { var sy = dy < 0 ? -1 : 1; return Math.abs(dy) > 0 ? { length : Math.abs(dy), dir : { x : 0, y : sy }, perp : { x : -sy, y : 0 }, axis : 'y' } : null; }
        var len = Math.hypot(dx, dy);
        if (!(len > 0)) return null;
        var dir = { x : dx / len, y : dy / len };
        return { length : len, dir : dir, perp : { x : -dir.y, y : dir.x }, axis : null };
    }

    // World points of a dimension: S, E measured; DS, DE its line; extension
    // lines from a gap off each point to an overshoot past the line. gap and
    // overshoot are world lengths.
    function DimensionSkeleton(a, b, off, orient, gap, overshoot) {
        var frame = DimensionFrame(a, b, orient);
        if (!frame) return null;
        var perp = frame.perp;
        var reach = frame.axis ? off - (((b.x - a.x) * perp.x) + ((b.y - a.y) * perp.y)) : off;
        var sign = off >= 0 ? 1 : -1, signE = reach >= 0 ? 1 : -1;
        var at = function (p, along) { return { x : p.x + (perp.x * along), y : p.y + (perp.y * along) }; };
        var DS = at(a, off);
        var DE = frame.axis === 'x' ? { x : b.x, y : DS.y } : (frame.axis === 'y' ? { x : DS.x, y : b.y } : at(b, off));
        return {
            length : frame.length, dir : frame.dir, perp : perp,
            DS : DS, DE : DE,
            X1 : at(a, gap * sign), T1 : at(a, off + (overshoot * sign)),
            X2 : at(b, gap * signE), T2 : at(b, reach + (overshoot * signE)),
            MID : { x : (DS.x + DE.x) / 2, y : (DS.y + DE.y) / 2 },
            showExt1 : Math.abs(off) > gap, showExt2 : Math.abs(reach) > gap
        };
    }

    function DrawDimensions(view, ed) {
        var cfg = ed.settings;
        var list = ed.doc.dims.slice();
        if (ed.dimPreview) list.push(ed.dimPreview);
        list.forEach(function (d) {
            DrawDimension(view, d, cfg, ed.selection.has(d.id), d === ed.dimPreview);
        });
    }

    function DrawDimension(view, d, cfg, selected, preview) {
        var ctx = view.ctx;
        var gap = 3 / view.scale, overshoot = 6 / view.scale;
        var sk = DimensionSkeleton(d.a, d.b, d.off || 0, d.orient, gap, overshoot);
        if (!sk) return;
        var colour = selected ? cfg.Colours.LineSelected : cfg.Colours.Dimension;
        ctx.save();
        ctx.strokeStyle = colour;
        ctx.fillStyle = colour;
        ctx.lineWidth = selected ? 1.6 : 1;
        ctx.setLineDash(preview ? [ 5, 3 ] : []);
        ctx.beginPath();
        var seg = function (p, q) { var s = W2S(view, p), t = W2S(view, q); ctx.moveTo(s.x, s.y); ctx.lineTo(t.x, t.y); };
        if (sk.showExt1) seg(sk.X1, sk.T1);
        if (sk.showExt2) seg(sk.X2, sk.T2);
        seg(sk.DS, sk.DE);
        ctx.stroke();

        // 45 deg ticks, 8 px
        ctx.setLineDash([]);
        ctx.lineWidth = selected ? 2 : 1.4;
        ctx.beginPath();
        [ sk.DS, sk.DE ].forEach(function (p) {
            var s = W2S(view, p);
            var dirS = { x : sk.dir.x, y : -sk.dir.y };
            var tx = (dirS.x - dirS.y) * 4, ty = (dirS.y + dirS.x) * 4;
            ctx.moveTo(s.x - tx, s.y - ty); ctx.lineTo(s.x + tx, s.y + ty);
        });
        ctx.stroke();

        // The value, along the line and never upside down.
        var mid = W2S(view, sk.MID);
        var angle = Math.atan2(-sk.dir.y, sk.dir.x);
        if (angle > Math.PI / 2 + 1e-9) angle -= Math.PI;
        if (angle < -Math.PI / 2 + 1e-9) angle += Math.PI;
        var text = G.FormatMm(sk.length, cfg.Precision);
        ctx.translate(mid.x, mid.y);
        ctx.rotate(angle);
        ctx.font = '600 11px "Segoe UI", Tahoma, sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'bottom';
        var width = ctx.measureText(text).width;
        ctx.fillStyle = 'rgba(255,255,255,0.85)';
        ctx.fillRect(-(width / 2) - 2, -15, width + 4, 13);
        ctx.fillStyle = selected ? cfg.Colours.LineSelected : cfg.Colours.DimensionText;
        ctx.fillText(text, 0, -3);
        ctx.restore();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Check Markers + Loop Information
    // -------------------------------------------------------------------------

    function DrawMarkers(view, ed) {
        if (!ed.analysis || !ed.showIssues) return;
        var ctx = view.ctx;
        var colours = ed.settings.Colours;
        ctx.save();
        ed.analysis.markers.forEach(function (m, index) {
            var s = W2S(view, m.p);
            var colour = m.code === 'gap' ? colours.IssueGap : (m.severity === 'warn' ? colours.IssueWarn : colours.IssueError);
            var focused = ed.focusIssue === index;
            ctx.strokeStyle = colour;
            ctx.fillStyle = colour;
            ctx.lineWidth = focused ? 3 : 2;
            ctx.setLineDash([]);
            ctx.beginPath();
            ctx.arc(s.x, s.y, focused ? 12 : 8, 0, G.TAU);
            ctx.stroke();
            if (m.code === 'cross' || m.code === 'branch') {
                ctx.beginPath();
                ctx.moveTo(s.x - 4, s.y - 4); ctx.lineTo(s.x + 4, s.y + 4);
                ctx.moveTo(s.x - 4, s.y + 4); ctx.lineTo(s.x + 4, s.y - 4);
                ctx.stroke();
            } else {
                ctx.beginPath();
                ctx.arc(s.x, s.y, 2.5, 0, G.TAU);
                ctx.fill();
            }
        });
        ctx.restore();
    }

    // Vertex numbers and the way round, as the saved profile will run.
    function DrawLoopInfo(view, ed) {
        if (!ed.settings.ShowLoopInfo || !ed.analysis || !ed.analysis.loop) return;
        var ctx = view.ctx;
        var pts = ed.analysis.loop.points;
        var n = pts.length;
        var every = Math.max(1, Math.ceil(n / 120));
        ctx.save();
        ctx.font = '10px "Segoe UI", Tahoma, sans-serif';
        ctx.textBaseline = 'middle';
        for (var i = 0; i < n; i += every) {
            var s = W2S(view, pts[i]);
            var label = 'V' + (i + 1);
            ctx.fillStyle = 'rgba(255,255,255,0.85)';
            var w = ctx.measureText(label).width;
            ctx.fillRect(s.x + 4, s.y - 13, w + 4, 12);
            ctx.fillStyle = i === 0 ? ed.settings.Colours.Datum : '#334155';
            ctx.fillText(label, s.x + 6, s.y - 7);
            ctx.beginPath(); ctx.arc(s.x, s.y, i === 0 ? 3.5 : 2, 0, G.TAU); ctx.fill();

            var nextP = pts[(i + 1) % n];
            var m = W2S(view, G.Mid(pts[i], nextP)), t = W2S(view, nextP);
            var ang = Math.atan2(t.y - s.y, t.x - s.x);
            if (G.Dist(s, t) < 18) continue;
            ctx.save();
            ctx.translate(m.x, m.y); ctx.rotate(ang);
            ctx.fillStyle = '#1f6fd6';
            ctx.beginPath(); ctx.moveTo(5, 0); ctx.lineTo(-3, -3.5); ctx.lineTo(-3, 3.5); ctx.closePath(); ctx.fill();
            ctx.restore();
        }
        ctx.restore();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Grips (TV Grips: 9 px squares, 13 px picked)
    // -------------------------------------------------------------------------

    function DrawGrips(view, ed) {
        var grips = ed.gripsToDraw || [];
        if (!grips.length) return;
        var ctx = view.ctx;
        var colours = ed.settings.Colours;
        ctx.save();
        ctx.setLineDash([]);
        grips.forEach(function (g) {
            var s = W2S(view, g.p);
            var picked = !!g.picked, hot = !!g.hot;
            var size = picked ? 11 : (hot ? 11 : 8);
            ctx.fillStyle = picked ? colours.GripPicked : (hot ? '#dbeafe' : '#ffffff');
            ctx.strokeStyle = picked ? '#8f1218' : colours.GripFree;
            ctx.lineWidth = 1.5;
            if (g.kind === 'bulge') {
                ctx.beginPath();
                ctx.moveTo(s.x, s.y - (size / 2) - 1); ctx.lineTo(s.x + (size / 2) + 1, s.y);
                ctx.lineTo(s.x, s.y + (size / 2) + 1); ctx.lineTo(s.x - (size / 2) - 1, s.y);
                ctx.closePath(); ctx.fill(); ctx.stroke();
            } else {
                ctx.fillRect(s.x - (size / 2), s.y - (size / 2), size, size);
                ctx.strokeRect(s.x - (size / 2) + 0.5, s.y - (size / 2) + 0.5, size - 1, size - 1);
            }
        });
        ctx.restore();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Selection Box (TV: window blue solid, crossing green dashed)
    // -------------------------------------------------------------------------

    function DrawBox(view, ed) {
        var box = ed.box;
        if (!box) return;
        var ctx = view.ctx;
        var colours = ed.settings.Colours;
        var crossing = box.mode === 'crossing';
        var x = Math.min(box.sx0, box.sx1), y = Math.min(box.sy0, box.sy1);
        var w = Math.abs(box.sx1 - box.sx0), h = Math.abs(box.sy1 - box.sy0);
        ctx.save();
        ctx.fillStyle = crossing ? colours.CrossingFill : colours.WindowFill;
        ctx.fillRect(x, y, w, h);
        ctx.strokeStyle = crossing ? colours.CrossingStroke : colours.WindowStroke;
        ctx.lineWidth = 1;
        ctx.setLineDash(crossing ? [ 5, 3 ] : []);
        ctx.strokeRect(x + 0.5, y + 0.5, w, h);
        ctx.restore();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Snap Marker, Tracking Guides, Drawing Axes
    // -------------------------------------------------------------------------

    function DrawSnap(view, ed) {
        var snap = ed.snapShown;
        if (!snap || !snap.kind) return;
        var cfg = ed.settings;
        var kind = snap.target === 'datum' ? 'end' : snap.kind;
        var glyph = GLYPHS[kind];
        if (!glyph) return;
        var colour = snap.target === 'grid' ? cfg.Colours.SnapGrid
                   : (snap.target === 'datum' ? cfg.Colours.SnapDatum
                   : (snap.target === 'dim' ? cfg.Colours.SnapDimension : cfg.Colours.SnapShape));
        var s = W2S(view, snap.p);
        var size = cfg.Snap.MarkerPx * (glyph.scale || 1);
        var ctx = view.ctx;
        ctx.save();
        ctx.translate(s.x, s.y);
        ctx.scale(size / 24, size / 24);
        ctx.translate(-12, -12);
        var path = GlyphPath(glyph.path);
        ctx.lineJoin = 'round'; ctx.lineCap = 'round';
        ctx.setLineDash([]);
        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth = 4.4;
        ctx.stroke(path);
        if (glyph.closed) {
            ctx.globalAlpha = 0.18;
            ctx.fillStyle = colour;
            ctx.fill(path);
            ctx.globalAlpha = 1;
        }
        ctx.strokeStyle = colour;
        ctx.lineWidth = 2.2;
        if (glyph.dash) ctx.setLineDash(glyph.dash);
        ctx.stroke(path);
        if (glyph.fill) { ctx.fillStyle = colour; ctx.fill(GlyphPath(glyph.fill)); }
        ctx.restore();

        if (snap.label && ed.showSnapLabel !== false) {
            ctx.save();
            ctx.font = '11px "Segoe UI", Tahoma, sans-serif';
            var text = snap.label;
            var w = ctx.measureText(text).width;
            var lx = s.x + 12, ly = s.y + 14;
            ctx.fillStyle = 'rgba(255,255,255,0.92)';
            ctx.strokeStyle = 'rgba(15,23,42,0.18)';
            ctx.lineWidth = 1;
            ctx.fillRect(lx - 3, ly - 1, w + 6, 15);
            ctx.strokeRect(lx - 2.5, ly - 0.5, w + 5, 14);
            ctx.fillStyle = colour;
            ctx.textBaseline = 'top';
            ctx.fillText(text, lx, ly + 1);
            ctx.restore();
        }
    }

    function DrawGuides(view, ed) {
        var ctx = view.ctx;
        var colours = ed.settings.Colours;
        ctx.save();
        ctx.lineWidth = 1;
        if (ed.track && ed.track.acquired.length) {
            ctx.strokeStyle = '#64748b';
            ed.track.acquired.forEach(function (a) {
                var s = W2S(view, a.p);
                ctx.beginPath();
                ctx.moveTo(s.x - 4, s.y); ctx.lineTo(s.x + 4, s.y);
                ctx.moveTo(s.x, s.y - 4); ctx.lineTo(s.x, s.y + 4);
                ctx.stroke();
            });
        }
        var snap = ed.snapShown;
        if (snap && snap.guides && snap.guides.length) {
            ctx.setLineDash([ 5, 4 ]);
            snap.guides.forEach(function (g) {
                var s = W2S(view, g.through);
                var end = W2S(view, snap.p);
                ctx.strokeStyle = g.axis === 'x' ? colours.TrackLevel : colours.TrackPlumb;
                ctx.beginPath();
                ctx.moveTo(s.x, s.y); ctx.lineTo(end.x, end.y);
                if (g.axis === 'x') { ctx.moveTo(Math.min(s.x, end.x) - 40, s.y); ctx.lineTo(Math.max(s.x, end.x) + 40, s.y); }
                else { ctx.moveTo(s.x, Math.min(s.y, end.y) - 40); ctx.lineTo(s.x, Math.max(s.y, end.y) + 40); }
                ctx.stroke();
            });
        }
        ctx.restore();
    }

    function DrawDrawingAxes(view, ed) {
        if (!ed.settings.DrawingAxes || !ed.cursorWorld) return;
        var at = ed.snapShown && ed.snapShown.kind ? ed.snapShown.p : ed.cursorWorld;
        var s = W2S(view, at);
        var ctx = view.ctx;
        ctx.save();
        ctx.lineWidth = 1;
        ctx.setLineDash([]);
        ctx.strokeStyle = ed.settings.Colours.DrawingAxisX;
        ctx.beginPath(); ctx.moveTo(0, Math.round(s.y) + 0.5); ctx.lineTo(view.w, Math.round(s.y) + 0.5); ctx.stroke();
        ctx.strokeStyle = ed.settings.Colours.DrawingAxisY;
        ctx.beginPath(); ctx.moveTo(Math.round(s.x) + 0.5, 0); ctx.lineTo(Math.round(s.x) + 0.5, view.h); ctx.stroke();
        ctx.restore();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Preview Helpers (for the tools' draw hooks)
    // -------------------------------------------------------------------------

    // The rubber band (TV Paper.css): free 2 px dashed #336699, X-locked solid
    // red, Y-locked solid green.
    function DrawBand(view, cfg, a, b, lock) {
        var ctx = view.ctx;
        var s = W2S(view, a), t = W2S(view, b);
        ctx.save();
        ctx.lineWidth = 2;
        ctx.strokeStyle = lock === 'x' ? cfg.Colours.BandLockX : (lock === 'y' ? cfg.Colours.BandLockY : cfg.Colours.BandFree);
        ctx.setLineDash(lock ? [] : [ 6, 4 ]);
        ctx.beginPath(); ctx.moveTo(s.x, s.y); ctx.lineTo(t.x, t.y); ctx.stroke();
        ctx.restore();
    }

    // An entity drawn as a preview: kind 'add' (blue dashed), 'remove' (red
    // dashed) or 'ghost' (grey, for what a move carries).
    function DrawPreviewEntity(view, cfg, e, kind) {
        var ctx = view.ctx;
        var pts = G.Tessellate(e, cfg.Curves);
        ctx.save();
        ctx.lineWidth = kind === 'held' ? 3 : 2;
        ctx.strokeStyle = kind === 'remove' ? cfg.Colours.PreviewRemove : (kind === 'ghost' ? 'rgba(31,41,55,0.45)' : cfg.Colours.PreviewAdd);
        ctx.setLineDash(kind === 'ghost' ? [] : [ 6, 4 ]);
        Polyline(view, pts, e.type === 'circle');
        ctx.stroke();
        ctx.restore();
    }

    function DrawPointMark(view, p, colour, radiusPx) {
        var ctx = view.ctx;
        var s = W2S(view, p);
        ctx.save();
        ctx.fillStyle = colour;
        ctx.beginPath(); ctx.arc(s.x, s.y, radiusPx || 3, 0, G.TAU); ctx.fill();
        ctx.restore();
    }

    function DrawLabel(view, p, text, colour, dx, dy) {
        var ctx = view.ctx;
        var s = W2S(view, p);
        ctx.save();
        ctx.font = '600 11px "Segoe UI", Tahoma, sans-serif';
        var w = ctx.measureText(text).width;
        var x = s.x + (dx || 10), y = s.y + (dy || -22);
        ctx.fillStyle = 'rgba(255,255,255,0.92)';
        ctx.fillRect(x - 3, y - 1, w + 6, 15);
        ctx.fillStyle = colour || '#1f2937';
        ctx.textBaseline = 'top';
        ctx.fillText(text, x, y + 1);
        ctx.restore();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Export
    // -------------------------------------------------------------------------

    window.Na__DrawProfile__View = {
        Create : Create, Resize : Resize, W2S : W2S, S2W : S2W, ZoomAt : ZoomAt, Pan : Pan, Fit : Fit,
        VisibleBox : VisibleBox, Render : Render,
        DimensionSkeleton : DimensionSkeleton,
        DrawBand : DrawBand, DrawPreviewEntity : DrawPreviewEntity, DrawPointMark : DrawPointMark, DrawLabel : DrawLabel,
        DrawDimension : DrawDimension
    };

    // endregion ----------------------------------------------------------------
})();
