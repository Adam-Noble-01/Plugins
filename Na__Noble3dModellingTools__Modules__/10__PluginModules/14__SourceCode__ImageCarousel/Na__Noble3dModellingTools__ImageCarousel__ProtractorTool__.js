// =============================================================================
// NA NOBLE3D MODELLING TOOLS - IMAGE VIEWER - PROTRACTOR TOOL
//
// FILE       : Na__Noble3dModellingTools__ImageCarousel__ProtractorTool__.js
// PURPOSE    : A flat 2D protractor for drawings and scans: the angle between
//              two lines as they are on the picture. No camera correction
//              (that is the Angle tool, for photos taken in perspective).
//
// INTERACTION: P or the Protractor button. Click the corner (the vertex),
//              then a point along the first line, then a point along the
//              second: the angle between them is marked with an arc and read
//              in degrees, to 0.1°. Ortho (F8) or Shift holds an arm level or
//              plumb from the corner, so a roof pitch is the vertex, a level
//              arm and the roof line. Points snap as the other tools' do
//              (dimension ends, guides, count ticks).
//              Click a protractor to select it; drag its corner or either
//              arm's end to change it (3 px before a press is a drag; Esc puts
//              a drag back). Delete removes it. Esc steps back: the point
//              being placed, then the selection, then the tool. The middle
//              button pans throughout.
//
// DESIGN     : Self-contained, like the Count tool. It talks to the viewer
//              through window.Na__ImageViewer__Core: drawing, the shared undo
//              history (one step per protractor placed, moved or deleted),
//              the active-tool hand-off, snapping, and keeping its work in the
//              model (registerPersist, tool 'protractor': { items:[ { v, a, b } ] }
//              in photo pixels from the top-left). Ortho is read from the
//              Measure tool. Clear All clears protractors too, in the same
//              undo step as the dimensions (Measurement calls clearForUndo).
// =============================================================================

(function() {
    'use strict';

    var na_core = window.Na__ImageViewer__Core;
    if (!na_core || typeof na_core.registerHistory !== 'function' || typeof na_core.claimTool !== 'function') { return; }

    // -------------------------------------------------------------------------
    // REGION | Constants
    // -------------------------------------------------------------------------

    var NA_TOOL_NAME     = 'protractor';
    var NA_COLOR         = '#c2185b';   // its own colour: not the dimensions' red or the Angle tool's purple
    var NA_SELECTED      = '#f5a623';   // as a selected dimension
    var NA_PREVIEW       = '#2f77d5';   // as a dimension being drawn
    var NA_LINE_PX       = 1.6;
    var NA_ARC_PX        = 34;          // the arc's radius on screen, never past the shorter arm
    var NA_GRIP_PX       = 4.5;
    var NA_GRIP_REACH_PX = 14;
    var NA_HIT_PX        = 9;
    var NA_DRAG_START_PX = 3;
    var NA_FONT_PX       = 12;

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | State
    // -------------------------------------------------------------------------

    var na_itemsByKey = {};      // image key -> [ { v:{x,y}, a:{x,y}, b:{x,y} } ] image space
    var na_active     = false;
    var na_points     = [];      // the protractor being placed: vertex, then the first arm's point
    var na_cursor     = null;    // canvas px (snapped and held) while placing
    var na_selected   = null;
    var na_grabbed    = null;    // { item, part:'v'|'a'|'b', orig, press:{x,y}, moved }
    var na_hover      = null;    // { item, part }
    var na_suppressClick = false;
    var na_shiftHeld  = false;

    var na_btn  = null;
    var na_hint = null;

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Geometry
    // -------------------------------------------------------------------------

    function Na__ImageViewerProtractor__Clone(it) {
        return { v: { x: it.v.x, y: it.v.y }, a: { x: it.a.x, y: it.a.y }, b: { x: it.b.x, y: it.b.y } };
    }

    // The angle between the arms at the vertex, 0..180 degrees, in the picture's
    // own (image) space, so rotating the view never changes it.
    function Na__ImageViewerProtractor__Degrees(v, a, b) {
        var ax = a.x - v.x, ay = a.y - v.y, bx = b.x - v.x, by = b.y - v.y;
        var la = Math.sqrt(ax * ax + ay * ay), lb = Math.sqrt(bx * bx + by * by);
        if (!(la > 0) || !(lb > 0)) return null;
        var c = (ax * bx + ay * by) / (la * lb);
        return Math.acos(Math.max(-1, Math.min(1, c))) * 180 / Math.PI;
    }

    function Na__ImageViewerProtractor__Label(deg) {
        return deg === null ? '' : (Math.round(deg * 10) / 10).toFixed(1) + '°';
    }

    function Na__ImageViewerProtractor__OrthoHeld(shiftKey) {
        var m = window.Na__ImageViewer__Measure;
        var on = !!(m && typeof m.getOptions === 'function' && m.getOptions().ortho);
        return on !== !!shiftKey;
    }

    // A point for the pointer at (cx, cy): snapped, then held level or plumb
    // from `from` (canvas px) when Ortho is in effect.
    function Na__ImageViewerProtractor__PointAt(cx, cy, from, shiftKey) {
        var hit = typeof na_core.snap === 'function' ? na_core.snap(cx, cy) : null;
        var sx = hit ? hit.screen.x : cx, sy = hit ? hit.screen.y : cy;
        if (from && Na__ImageViewerProtractor__OrthoHeld(shiftKey)) {
            var f = na_core.imgToScreen(from);
            if (Math.abs(cx - f.x) >= Math.abs(cy - f.y)) sy = f.y; else sx = f.x;
            var moved = !hit || Math.abs(sx - hit.screen.x) > 0.5 || Math.abs(sy - hit.screen.y) > 0.5;
            return { img: na_core.screenToImg(sx, sy), screen: { x: sx, y: sy }, hit: moved ? null : hit };
        }
        return { img: hit ? { x: hit.img.x, y: hit.img.y } : na_core.screenToImg(cx, cy), screen: { x: sx, y: sy }, hit: hit };
    }

    function Na__ImageViewerProtractor__Dist(p, q) {
        return Math.sqrt((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y));
    }

    function Na__ImageViewerProtractor__DistToSeg(p, s1, s2) {
        var dx = s2.x - s1.x, dy = s2.y - s1.y, l2 = dx * dx + dy * dy;
        var t = l2 > 0 ? Math.max(0, Math.min(1, ((p.x - s1.x) * dx + (p.y - s1.y) * dy) / l2)) : 0;
        return Na__ImageViewerProtractor__Dist(p, { x: s1.x + t * dx, y: s1.y + t * dy });
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Drawing
    // -------------------------------------------------------------------------

    function Na__ImageViewerProtractor__Render(ctx) {
        var key = na_core.getImageKey();
        if (!ctx || !key) return;
        var ratio = na_core.getRatio();
        var exporting = typeof na_core.isExporting === 'function' && na_core.isExporting();
        (na_itemsByKey[key] || []).forEach(function(it) {
            var sel = !exporting && it === na_selected;
            Na__ImageViewerProtractor__DrawOne(ctx, ratio,
                na_core.imgToScreen(it.v), na_core.imgToScreen(it.a), na_core.imgToScreen(it.b),
                sel ? NA_SELECTED : NA_COLOR, Na__ImageViewerProtractor__Degrees(it.v, it.a, it.b), false);
            if (sel) ['v', 'a', 'b'].forEach(function(part) {
                Na__ImageViewerProtractor__Grip(ctx, ratio, na_core.imgToScreen(it[part]), NA_SELECTED, Na__ImageViewerProtractor__GripState(it, part));
            });
            else if (!exporting && na_active && na_hover && na_hover.item === it && na_hover.part !== 'arm') {
                Na__ImageViewerProtractor__Grip(ctx, ratio, na_core.imgToScreen(it[na_hover.part]), NA_COLOR, 'hover');
            }
        });
        if (exporting || !na_active || !na_points.length || !na_cursor) return;

        var v = na_core.imgToScreen(na_points[0]);
        if (na_points.length === 1) {
            Na__ImageViewerProtractor__Arm(ctx, ratio, v, na_cursor, NA_PREVIEW, true);
            Na__ImageViewerProtractor__Dot(ctx, ratio, v, NA_PREVIEW);
        } else {
            var a  = na_core.imgToScreen(na_points[1]);
            var bi = na_core.screenToImg(na_cursor.x, na_cursor.y);
            Na__ImageViewerProtractor__DrawOne(ctx, ratio, v, a, na_cursor, NA_PREVIEW,
                Na__ImageViewerProtractor__Degrees(na_points[0], na_points[1], bi), true);
        }
    }

    function Na__ImageViewerProtractor__DrawOne(ctx, ratio, v, a, b, color, deg, dashed) {
        Na__ImageViewerProtractor__Arm(ctx, ratio, v, a, color, false);
        Na__ImageViewerProtractor__Arm(ctx, ratio, v, b, color, dashed);
        Na__ImageViewerProtractor__Dot(ctx, ratio, v, color);
        if (deg === null) return;

        var r  = Math.min(NA_ARC_PX * ratio, Na__ImageViewerProtractor__Dist(v, a) * 0.8, Na__ImageViewerProtractor__Dist(v, b) * 0.8);
        var t1 = Math.atan2(a.y - v.y, a.x - v.x), t2 = Math.atan2(b.y - v.y, b.x - v.x);
        var d  = t2 - t1;
        while (d > Math.PI) d -= 2 * Math.PI;
        while (d < -Math.PI) d += 2 * Math.PI;
        ctx.save();
        ctx.strokeStyle = color;
        ctx.lineWidth   = NA_LINE_PX * ratio;
        ctx.beginPath();
        ctx.arc(v.x, v.y, r, t1, t1 + d, d < 0);
        ctx.stroke();
        ctx.restore();

        // The reading just outside the arc, on its bisector.
        var mid = t1 + d / 2, lr = r + 16 * ratio;
        Na__ImageViewerProtractor__Tag(ctx, ratio, v.x + Math.cos(mid) * lr, v.y + Math.sin(mid) * lr, Na__ImageViewerProtractor__Label(deg), color);
    }

    function Na__ImageViewerProtractor__Arm(ctx, ratio, p, q, color, dashed) {
        ctx.save();
        ctx.strokeStyle = color;
        ctx.lineWidth   = NA_LINE_PX * ratio;
        ctx.lineCap     = 'round';
        if (dashed) ctx.setLineDash([6 * ratio, 5 * ratio]);
        ctx.beginPath();
        ctx.moveTo(p.x, p.y);
        ctx.lineTo(q.x, q.y);
        ctx.stroke();
        ctx.restore();
    }

    function Na__ImageViewerProtractor__Dot(ctx, ratio, p, color) {
        ctx.save();
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.arc(p.x, p.y, 2.6 * ratio, 0, Math.PI * 2);
        ctx.fill();
        ctx.restore();
    }

    function Na__ImageViewerProtractor__Tag(ctx, ratio, cx, cy, text, color) {
        if (!text) return;
        ctx.save();
        ctx.font = '600 ' + (NA_FONT_PX * ratio) + 'px "Segoe UI", Arial, sans-serif';
        ctx.textBaseline = 'middle';
        ctx.textAlign    = 'center';
        var w = ctx.measureText(text).width + 10 * ratio, h = NA_FONT_PX * ratio + 6 * ratio;
        ctx.fillStyle   = color;
        ctx.strokeStyle = 'rgba(255,255,255,0.9)';
        ctx.lineWidth   = 1 * ratio;
        ctx.beginPath();
        ctx.rect(cx - w / 2, cy - h / 2, w, h);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = '#ffffff';
        ctx.fillText(text, cx, cy + ratio * 0.5);
        ctx.restore();
    }

    function Na__ImageViewerProtractor__GripState(it, part) {
        if (na_grabbed && na_grabbed.item === it && na_grabbed.part === part && na_grabbed.moved) return 'held';
        if (na_hover && na_hover.item === it && na_hover.part === part) return 'hover';
        return '';
    }

    // Square grips, as the dimensions'.
    function Na__ImageViewerProtractor__Grip(ctx, ratio, p, color, state) {
        var half = (state === 'held' ? NA_GRIP_PX * 1.45 : state === 'hover' ? NA_GRIP_PX * 1.25 : NA_GRIP_PX) * ratio;
        ctx.save();
        ctx.fillStyle   = state === 'held' ? NA_COLOR : state === 'hover' ? '#ffffff' : color;
        ctx.strokeStyle = state === 'hover' ? color : '#ffffff';
        ctx.lineWidth   = (state === 'hover' ? 2 : 1.2) * ratio;
        ctx.beginPath();
        ctx.rect(p.x - half, p.y - half, half * 2, half * 2);
        ctx.fill();
        ctx.stroke();
        ctx.restore();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | History And The Model
    // -------------------------------------------------------------------------

    function Na__ImageViewerProtractor__Snapshot(key) {
        return (na_itemsByKey[key] || []).map(Na__ImageViewerProtractor__Clone);
    }

    function Na__ImageViewerProtractor__Restore(key, snap) {
        if (snap && snap.length) na_itemsByKey[key] = snap.map(Na__ImageViewerProtractor__Clone);
        else delete na_itemsByKey[key];
    }

    function Na__ImageViewerProtractor__OnHistoryChanged(reason) {
        if (reason !== 'undo' && reason !== 'redo') return;
        na_grabbed = null;
        na_points  = [];
        var list = na_itemsByKey[na_core.getImageKey()] || [];
        if (list.indexOf(na_selected) === -1) na_selected = null;
        Na__ImageViewerProtractor__Refresh();
    }

    function Na__ImageViewerProtractor__Serialise(key, conv) {
        var list = na_itemsByKey[key] || [];
        if (!list.length) return null;
        return { items: list.map(function(it) { return { v: conv.pt(it.v), a: conv.pt(it.a), b: conv.pt(it.b) }; }) };
    }

    function Na__ImageViewerProtractor__Materialise(key, state, conv) {
        if (!state || !Array.isArray(state.items)) return;
        var list = [];
        state.items.forEach(function(raw) {
            var v = raw && conv.unpt(raw.v), a = raw && conv.unpt(raw.a), b = raw && conv.unpt(raw.b);
            if (v && a && b) list.push({ v: { x: v.x, y: v.y }, a: { x: a.x, y: a.y }, b: { x: b.x, y: b.y } });
        });
        if (list.length) na_itemsByKey[key] = list;
    }

    // Clear All: the Measure tool has already taken the undo snapshot.
    function Na__ImageViewerProtractor__ClearForUndo(key) {
        delete na_itemsByKey[key];
        na_selected = null;
        na_grabbed  = null;
        na_points   = [];
        Na__ImageViewerProtractor__Refresh();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | The Tool
    // -------------------------------------------------------------------------

    function Na__ImageViewerProtractor__SetActive(on) {
        if (on === na_active) return;
        na_active = on;
        if (on) {
            na_core.claimTool(NA_TOOL_NAME, function() { Na__ImageViewerProtractor__SetActive(false); });
            na_core.setPanEnabled(false);
        } else {
            na_core.releaseTool(NA_TOOL_NAME);
            na_core.setPanEnabled(true);
            na_points = [];
            na_cursor = null;
            na_selected = null;
            na_hover = null;
            Na__ImageViewerProtractor__CancelDrag();
            Na__ImageViewerProtractor__Cursor('');
            if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(null);
            Na__ImageViewerProtractor__HideHint();
        }
        Na__ImageViewerProtractor__Refresh();
    }

    function Na__ImageViewerProtractor__Refresh() {
        if (na_btn) na_btn.classList.toggle('naImageViewer__Btn--active', na_active);
        if (na_active) Na__ImageViewerProtractor__ShowHint(Na__ImageViewerProtractor__HintText());
        na_core.requestDraw();
    }

    function Na__ImageViewerProtractor__HintText() {
        var ortho = Na__ImageViewerProtractor__OrthoHeld(false) ? ' Ortho on (F8).' : '';
        if (na_points.length === 0 && na_selected) return 'Protractor: selected. Drag its corner or an arm\'s end; Delete removes. Esc to deselect.';
        if (na_points.length === 0) return 'Protractor: click the corner, then a point on each line.' + ortho + ' Esc to stop.';
        if (na_points.length === 1) return 'Protractor: click a point along the first line.' + ortho + ' Esc steps back.';
        return 'Protractor: click a point along the second line.' + ortho + ' Esc steps back.';
    }

    function Na__ImageViewerProtractor__ShowHint(text) {
        if (!na_hint) return;
        na_hint.textContent = text;
        na_hint.classList.add('naImageViewer__MeasureHint--visible');
    }

    function Na__ImageViewerProtractor__HideHint() {
        if (na_hint) na_hint.classList.remove('naImageViewer__MeasureHint--visible');
    }

    function Na__ImageViewerProtractor__Cursor(kind) {
        var c = na_core.getCanvas();
        if (!c) return;
        var want = { grip: 'naImageViewer__Canvas--grip', move: 'naImageViewer__Canvas--moveDim' };
        Object.keys(want).forEach(function(k) {
            if (c.classList.contains(want[k]) !== (kind === k)) c.classList.toggle(want[k], kind === k);
        });
    }

    function Na__ImageViewerProtractor__CanvasXY(e) {
        var r = na_core.getCanvas().getBoundingClientRect(), k = na_core.getRatio();
        return { x: (e.clientX - r.left) * k, y: (e.clientY - r.top) * k };
    }

    // The grip under the pointer: the selected protractor's first, then any; else an arm.
    function Na__ImageViewerProtractor__GripAt(p) {
        var list = na_itemsByKey[na_core.getImageKey()] || [];
        var ratio = na_core.getRatio(), best = null, bestD = NA_GRIP_REACH_PX * ratio;
        var order = na_selected && list.indexOf(na_selected) !== -1 ? [na_selected].concat(list.filter(function(i) { return i !== na_selected; })) : list.slice().reverse();
        order.forEach(function(it, n) {
            ['v', 'a', 'b'].forEach(function(part) {
                var d = Na__ImageViewerProtractor__Dist(p, na_core.imgToScreen(it[part])) - (n === 0 && it === na_selected ? 2 * ratio : 0);
                if (d <= bestD) { bestD = d; best = { item: it, part: part }; }
            });
        });
        if (best) return best;
        for (var i = list.length - 1; i >= 0; i--) {
            var v = na_core.imgToScreen(list[i].v);
            if (Na__ImageViewerProtractor__DistToSeg(p, v, na_core.imgToScreen(list[i].a)) <= NA_HIT_PX * ratio ||
                Na__ImageViewerProtractor__DistToSeg(p, v, na_core.imgToScreen(list[i].b)) <= NA_HIT_PX * ratio) return { item: list[i], part: 'arm' };
        }
        return null;
    }

    function Na__ImageViewerProtractor__OnMouseDown(e) {
        if (!na_active || e.button !== 0 || e.target !== na_core.getCanvas() || na_points.length) return;
        var p   = Na__ImageViewerProtractor__CanvasXY(e);
        var hit = Na__ImageViewerProtractor__GripAt(p);
        if (!hit) return;                          // a click on nothing places a corner
        e.preventDefault();
        na_suppressClick = true;
        na_selected = hit.item;
        if (hit.part !== 'arm') na_grabbed = { item: hit.item, part: hit.part, orig: Na__ImageViewerProtractor__Clone(hit.item), press: { x: e.clientX, y: e.clientY }, moved: false };
        Na__ImageViewerProtractor__Refresh();
    }

    function Na__ImageViewerProtractor__OnMouseMove(e) {
        if (!na_active) return;
        var canvas = na_core.getCanvas();
        var p = Na__ImageViewerProtractor__CanvasXY(e);
        na_shiftHeld = !!e.shiftKey;
        if (na_grabbed) {
            var g = na_grabbed;
            if (!g.moved && Math.sqrt((e.clientX - g.press.x) * (e.clientX - g.press.x) + (e.clientY - g.press.y) * (e.clientY - g.press.y)) < NA_DRAG_START_PX) return;
            g.moved = true;
            var from = g.part === 'v' ? null : g.item.v;     // an arm's end is held level or plumb from the corner
            var at = Na__ImageViewerProtractor__PointAt(p.x, p.y, from, na_shiftHeld);
            g.item[g.part] = at.img;
            if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(at.hit);
            na_core.requestDraw();
            return;
        }
        if (e.target !== canvas) return;
        if (na_points.length) {
            var held = Na__ImageViewerProtractor__PointAt(p.x, p.y, na_points[0], na_shiftHeld);
            na_cursor = held.screen;
            if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(held.hit);
            na_core.requestDraw();
            return;
        }
        var hov = Na__ImageViewerProtractor__GripAt(p), was = na_hover;
        na_hover = hov;
        Na__ImageViewerProtractor__Cursor(hov ? (hov.part === 'arm' ? '' : 'grip') : '');
        var snapHit = Na__ImageViewerProtractor__PointAt(p.x, p.y, null, false).hit;
        if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(hov ? null : snapHit);
        if (hov !== was || snapHit) na_core.requestDraw();
    }

    function Na__ImageViewerProtractor__OnMouseUp() {
        var g = na_grabbed;
        if (!g) return;
        na_grabbed = null;
        if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(null);
        if (!g.moved) { na_core.requestDraw(); return; }
        var after = Na__ImageViewerProtractor__Clone(g.item);
        g.item.v = g.orig.v; g.item.a = g.orig.a; g.item.b = g.orig.b;
        na_core.pushHistory();                       // one undo step, holding it as it was
        g.item.v = after.v; g.item.a = after.a; g.item.b = after.b;
        Na__ImageViewerProtractor__Refresh();
    }

    function Na__ImageViewerProtractor__CancelDrag() {
        var g = na_grabbed;
        if (!g) return false;
        na_grabbed = null;
        g.item.v = g.orig.v; g.item.a = g.orig.a; g.item.b = g.orig.b;
        if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(null);
        na_core.requestDraw();
        return true;
    }

    function Na__ImageViewerProtractor__OnClick(e) {
        if (!na_active || e.button !== 0) return;
        if (na_suppressClick) { na_suppressClick = false; return; }
        var key = na_core.getImageKey();
        if (!key) return;
        var p  = Na__ImageViewerProtractor__CanvasXY(e);
        var at = Na__ImageViewerProtractor__PointAt(p.x, p.y, na_points.length ? na_points[0] : null, e.shiftKey);
        na_selected = null;
        if (na_points.length < 2) {
            if (na_points.length === 1 && Na__ImageViewerProtractor__Dist(at.screen, na_core.imgToScreen(na_points[0])) < 2) return;   // no zero-length arm
            na_points.push(at.img);
            na_cursor = at.screen;
            Na__ImageViewerProtractor__Refresh();
            return;
        }
        var item = { v: na_points[0], a: na_points[1], b: at.img };
        if (Na__ImageViewerProtractor__Degrees(item.v, item.a, item.b) === null) return;
        na_core.pushHistory();
        (na_itemsByKey[key] || (na_itemsByKey[key] = [])).push(item);
        na_points = [];
        na_cursor = null;
        Na__ImageViewerProtractor__Refresh();
    }

    function Na__ImageViewerProtractor__Delete() {
        var key = na_core.getImageKey(), list = na_itemsByKey[key] || [];
        var i = list.indexOf(na_selected);
        if (i === -1) return;
        na_core.pushHistory();
        list.splice(i, 1);
        if (!list.length) delete na_itemsByKey[key];
        na_selected = null;
        Na__ImageViewerProtractor__Refresh();
    }

    function Na__ImageViewerProtractor__OnKeyDown(e) {
        var tag = e.target && e.target.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
        if ((e.key === 'p' || e.key === 'P') && !e.ctrlKey && !e.metaKey && !e.altKey) {
            e.preventDefault();
            if (!na_active) Na__ImageViewerProtractor__SetActive(true);
            else { na_points = []; na_cursor = null; Na__ImageViewerProtractor__Refresh(); }   // P again: start afresh
            return;
        }
        if (!na_active) return;
        if (e.key === 'Shift' && !na_shiftHeld) { na_shiftHeld = true; return; }
        if ((e.key === 'Delete' || e.key === 'Backspace') && na_selected && !na_points.length) { e.preventDefault(); Na__ImageViewerProtractor__Delete(); return; }
        if (e.key === 'F8') { setTimeout(Na__ImageViewerProtractor__Refresh, 0); return; }   // the Measure tool switches Ortho
        if (e.key !== 'Escape') return;
        if (Na__ImageViewerProtractor__CancelDrag()) return;
        if (na_points.length) { na_points.pop(); if (!na_points.length) na_cursor = null; Na__ImageViewerProtractor__Refresh(); return; }
        if (na_selected) { na_selected = null; Na__ImageViewerProtractor__Refresh(); return; }
        Na__ImageViewerProtractor__SetActive(false);
    }

    function Na__ImageViewerProtractor__OnKeyUp(e) {
        if (e.key === 'Shift') na_shiftHeld = false;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Initialisation
    // -------------------------------------------------------------------------

    function Na__ImageViewerProtractor__Init() {
        na_btn  = document.getElementById('naImageViewer_btnProtractor');
        na_hint = document.getElementById('naImageViewer_measureHint');
        var canvas = na_core.getCanvas();
        if (!canvas) return;

        na_core.registerOverlay(Na__ImageViewerProtractor__Render);
        na_core.registerHistory(NA_TOOL_NAME, { snapshot: Na__ImageViewerProtractor__Snapshot, restore: Na__ImageViewerProtractor__Restore });
        na_core.onHistoryChanged(Na__ImageViewerProtractor__OnHistoryChanged);
        if (typeof na_core.registerPersist === 'function') {
            na_core.registerPersist(NA_TOOL_NAME, { serialise: Na__ImageViewerProtractor__Serialise, materialise: Na__ImageViewerProtractor__Materialise });
        }
        na_core.onImageChanged(function() {
            na_points = []; na_cursor = null; na_selected = null; na_grabbed = null; na_hover = null;
            if (na_active) Na__ImageViewerProtractor__Refresh();
        });

        canvas.addEventListener('mousedown', Na__ImageViewerProtractor__OnMouseDown);
        canvas.addEventListener('click', Na__ImageViewerProtractor__OnClick);
        canvas.addEventListener('mouseleave', function() {
            if (!na_active || na_grabbed) return;
            na_hover = null;
            if (!na_points.length) na_cursor = null;
            na_core.requestDraw();
        });
        window.addEventListener('mousemove', Na__ImageViewerProtractor__OnMouseMove);
        window.addEventListener('mouseup', Na__ImageViewerProtractor__OnMouseUp);
        window.addEventListener('keydown', Na__ImageViewerProtractor__OnKeyDown);
        window.addEventListener('keyup', Na__ImageViewerProtractor__OnKeyUp);
        if (na_btn) na_btn.addEventListener('click', function() { Na__ImageViewerProtractor__SetActive(!na_active); });
    }

    window.Na__ImageViewer__Protractor = {
        clearForUndo : function() { Na__ImageViewerProtractor__ClearForUndo(na_core.getImageKey()); },
        inspect      : function() {
            var key = na_core.getImageKey();
            return {
                active   : na_active,
                placing  : na_points.length,
                selected : (na_itemsByKey[key] || []).indexOf(na_selected),
                items    : (na_itemsByKey[key] || []).map(function(it) {
                    return { v: it.v, a: it.a, b: it.b, deg: Na__ImageViewerProtractor__Degrees(it.v, it.a, it.b), label: Na__ImageViewerProtractor__Label(Na__ImageViewerProtractor__Degrees(it.v, it.a, it.b)) };
                })
            };
        }
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na__ImageViewerProtractor__Init);
    } else {
        Na__ImageViewerProtractor__Init();
    }

    // endregion ---------------------------------------------------------------

    // =============================================================================
    // END OF FILE
    // =============================================================================

})();
