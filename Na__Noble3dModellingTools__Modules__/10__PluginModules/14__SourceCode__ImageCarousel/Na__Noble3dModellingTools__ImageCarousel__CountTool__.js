// =============================================================================
// NA NOBLE3D MODELLING TOOLS - IMAGE VIEWER - COUNT TOOL
//
// FILE       : Na__Noble3dModellingTools__ImageCarousel__CountTool__.js
// PURPOSE    : Count repeated things on a photo: brick courses, bricks in a
//              course, tiles, balusters. Drag a line from where the first
//              one starts to where the last one ends, then move back along
//              it: the line divides as you go, as SketchUp's Divide does,
//              and every part is numbered 01, 02, 03... On a calibrated
//              photo the parts are equal on the building rather than on the
//              picture, so the ticks stay on the joints in perspective.
//
// DESIGN     : Self-contained feature file, like the Measurement overlay. It
//              talks to the viewer through window.Na__ImageViewer__Core
//              (drawing, shared undo history, active-tool hand-off,
//              snapping), takes the photo's known directions from
//              window.Na__ImageViewer__Perspective and its maths from
//              window.Na__ImageViewer__PerspectiveSolver. Counts are kept
//              per image path for the session.
//
// INTERACTION: C or the Count button. Drag from the first edge to the last
//              (or click both ends). Move back along the line toward its
//              start: the first part follows the pointer and the rest of
//              the line fills with parts of that size, for a first guess.
//              Then dial it in while watching the ticks against the joints:
//              the wheel (while dividing), Up and Down add or remove one,
//              typing a number sets it. Click or Enter sets the count. Drag
//              an end to move it; drag a tick onto its joint to match the
//              perspective by hand. Delete removes the count, Esc steps
//              back. Right-drag pans and the wheel zooms without leaving
//              the tool.
//
// DIMENSIONS : Once Set Reference has given the photo a scale, every part
//              and the whole count are dimensioned in its units. The parts
//              are equal on the building, so each is the whole over the
//              count: counting 13 courses gives the gauge from 13 courses,
//              not from one. A reference drawn beside the count, along it
//              (one course, say), is read on the count's own perspective.
// =============================================================================

(function() {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Guard - require the viewer Core API and the solver
    // -------------------------------------------------------------------------

    var na_core   = window.Na__ImageViewer__Core;
    var na_solver = window.Na__ImageViewer__PerspectiveSolver;
    if (!na_core || !na_solver || typeof na_solver.countTicks !== 'function') { return; }
    if (typeof na_core.registerHistory !== 'function' || typeof na_core.claimTool !== 'function') { return; }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Constants
    // -------------------------------------------------------------------------

    var NA_TOOL_NAME       = 'count';
    var NA_COLOR           = '#00838f';   // teal: no other tool draws in it
    var NA_SELECT_COLOR    = '#f5a623';
    var NA_HALO_COLOR      = 'rgba(255, 255, 255, 0.92)';
    var NA_LINE_PX         = 2.2;
    var NA_END_TICK_PX     = 10;
    var NA_TICK_PX         = 7;
    var NA_HANDLE_PX       = 4.5;
    var NA_HIT_PX          = 9;
    var NA_TICK_HIT_PX     = 7;
    var NA_DRAG_START_PX   = 4;
    var NA_MIN_LINE_PX     = 12;    // a shorter line is a click, not a count
    var NA_MIN_PART_PX     = 4;     // the pointer divides no finer than this on screen
    var NA_MAX_COUNT       = 999;
    var NA_HYSTERESIS      = 0.12;  // in parts: the count holds still near a change-over
    var NA_WHEEL_STEP      = 40;    // wheel travel (px) for one more or one fewer
    var NA_INFER_DEG       = 10;    // how near a known direction a line must run
    var NA_SNAP_PX         = 8;
    var NA_TAPER_LIMIT     = 12;    // largest depth ratio a dragged tick may set
    var NA_BUBBLE_FONT_PX  = 11;
    var NA_TOTAL_FONT_PX   = 13;
    var NA_TAG_FONT_PX     = 12;
    var NA_LOUPE_RADIUS_PX = 66;
    var NA_LOUPE_GAIN      = 4;
    var NA_NICE_STEPS      = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500];
    var NA_DIM_COLOR       = '#e23b2e';   // as the Measure tool's dimensions
    var NA_DIM_FONT_PX     = 10.5;
    var NA_OVERALL_FONT_PX = 12;

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Feature State
    // -------------------------------------------------------------------------

    var na_countsByKey = {};    // image key -> [ { id, a:{x,y}, b:{x,y}, n, vp:{x,y,w}|null } ]
    var na_nextId      = 1;
    var na_active      = false;
    var na_phase       = null;  // null | 'draw' (placing the far end) | 'divide' (setting the count)
    var na_live        = null;  // the count being made: { a, b, n, follow }
    var na_selectedId  = null;
    var na_press       = null;  // a mouse press that may become a click, a drag or a pan
    var na_drag        = null;  // { item, part:'a'|'b'|'tick', index } while a handle is dragged
    var na_cursor      = null;  // pointer in canvas pixels while it is over the canvas
    var na_snap        = null;  // where the pointer has snapped while placing an end
    var na_hover       = null;  // the handle under the pointer
    var na_snapExclude = null;  // the count whose end is dragged: it cannot snap to itself
    var na_inputError  = '';
    var na_notice      = '';    // a one-off message in the bar, until the next action
    var na_wheelAcc    = 0;     // wheel travel not yet turned into a step

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | DOM Handles
    // -------------------------------------------------------------------------

    var na_canvas    = null;
    var na_wrap      = null;
    var na_btnTool   = null;
    var na_bar       = null;
    var na_input     = null;
    var na_btnMinus  = null;
    var na_btnPlus   = null;
    var na_spacingEl = null;
    var na_dimsEl    = null;
    var na_btnReset  = null;
    var na_btnClear  = null;
    var na_hintEl    = null;

    function Na__ImageViewerCount__El(id) {
        return document.getElementById(id);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Per-Image State And History
    // -------------------------------------------------------------------------

    function Na__ImageViewerCount__Key() {
        return na_core.getImageKey();
    }

    function Na__ImageViewerCount__List(key) {
        if (!na_countsByKey[key]) na_countsByKey[key] = [];
        return na_countsByKey[key];
    }

    function Na__ImageViewerCount__Clone(c) {
        return {
            id : c.id,
            a  : { x: c.a.x, y: c.a.y },
            b  : { x: c.b.x, y: c.b.y },
            n  : c.n,
            vp : c.vp ? { x: c.vp.x, y: c.vp.y, w: c.vp.w } : null
        };
    }

    function Na__ImageViewerCount__Snapshot(key) {
        return (na_countsByKey[key] || []).map(Na__ImageViewerCount__Clone);
    }

    function Na__ImageViewerCount__Restore(key, snap) {
        if (snap && snap.length) na_countsByKey[key] = snap.map(Na__ImageViewerCount__Clone);
        else                     delete na_countsByKey[key];
    }

    function Na__ImageViewerCount__OnHistoryChanged(reason) {
        if (reason !== 'undo' && reason !== 'redo') return;
        Na__ImageViewerCount__CancelLive();
        na_press = null;
        na_drag  = null;
        na_snapExclude = null;
        if (na_selectedId !== null && !Na__ImageViewerCount__Find(na_selectedId)) na_selectedId = null;
        Na__ImageViewerCount__RefreshBar(true);
    }

    function Na__ImageViewerCount__Find(id) {
        var list = na_countsByKey[Na__ImageViewerCount__Key()] || [];
        for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
        return null;
    }

    // The count the bar and the keys act on: the one being divided, else the
    // selected one.
    function Na__ImageViewerCount__Target() {
        if (na_live && na_phase === 'divide') return na_live;
        return na_selectedId !== null ? Na__ImageViewerCount__Find(na_selectedId) : null;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Spacing (perspective)
    // -------------------------------------------------------------------------
    // The parts of a count are equal on the building. Along a direction the
    // photo knows (the calibration's axes, a measured pitch, or two drawn
    // lines of one colour), the parts shrink toward the far end as they do on
    // the photo. A dragged tick sets the spacing by hand instead. Otherwise
    // the parts are equal on the photo.

    function Na__ImageViewerCount__Directions() {
        var p = window.Na__ImageViewer__Perspective;
        if (!p || typeof p.directions !== 'function') return [];
        try { return p.directions() || []; }
        catch (e) { return []; }
    }

    function Na__ImageViewerCount__Spacing(item, dirs) {
        if (item.vp) {
            var km = na_solver.countDepthRatio(item.a, item.b, item.vp);
            if (km && km >= 1 / NA_TAPER_LIMIT && km <= NA_TAPER_LIMIT) return { k: km, kind: 'manual', label: '' };
        }
        var list = dirs || Na__ImageViewerCount__Directions();
        if (list.length) {
            var mid = { x: (item.a.x + item.b.x) / 2, y: (item.a.y + item.b.y) / 2 };
            var inf = na_solver.inferGuide(mid, item.b, list, NA_INFER_DEG);
            if (inf) {
                var k = na_solver.countDepthRatio(item.a, item.b, inf.candidate.vp);
                if (k) return { k: k, kind: 'perspective', label: inf.candidate.label };
            }
        }
        return { k: 1, kind: 'even', label: '' };
    }

    function Na__ImageViewerCount__Ticks(item, sp) {
        return na_solver.countTicks(item.a, item.b, item.n, sp.k);
    }

    function Na__ImageViewerCount__SpacingText(sp) {
        if (sp.kind === 'manual')      return 'Spacing set by hand';
        if (sp.kind === 'perspective') return 'In perspective: ' + sp.label;
        return 'Even spacing';
    }

    // The most parts the pointer may make: none shorter than NA_MIN_PART_PX
    // on screen (the far end's parts are the short ones).
    function Na__ImageViewerCount__MaxCount(item, k) {
        var A = na_core.imgToScreen(item.a), B = na_core.imgToScreen(item.b);
        var L = Math.sqrt((B.x - A.x) * (B.x - A.x) + (B.y - A.y) * (B.y - A.y));
        var minPx = NA_MIN_PART_PX * na_core.getRatio();
        for (var n = Math.min(NA_MAX_COUNT, Math.floor(L / minPx)); n > 1; n--) {
            var first = na_solver.countPosition(k, 1 / n) * L;
            var last  = (1 - na_solver.countPosition(k, (n - 1) / n)) * L;
            if (Math.min(first, last) >= minPx) return n;
        }
        return 1;
    }

    // While dividing, the first part runs from the start to the pointer and
    // the rest of the line fills with parts that size, in perspective.
    // Returns true when the count changed.
    function Na__ImageViewerCount__FollowPointer(p) {
        if (!na_live || !na_live.follow) return false;
        var sp  = Na__ImageViewerCount__Spacing(na_live);
        var s   = na_solver.lineFraction(na_live.a, na_live.b, na_core.screenToImg(p.x, p.y));
        var t   = na_solver.countParameter(sp.k, s);
        var raw = t === Infinity ? 0 : (t > 1e-9 ? 1 / t : Infinity);
        if (Math.abs(raw - na_live.n) <= 0.5 + NA_HYSTERESIS) return false;
        var n = Math.max(1, Math.min(Na__ImageViewerCount__MaxCount(na_live, sp.k), Math.round(raw)));
        if (n === na_live.n) return false;
        na_live.n = n;
        return true;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Dimensions (with a reference scale)
    // -------------------------------------------------------------------------
    // The overall length is the count's photo length over the reference
    // scale, as Measure reads a dimension. When the reference line runs
    // beside the count and along it, and the parts shrink in perspective,
    // the reference is read instead as the share of the count it covers on
    // the building: a reference course at one end of a foreshortened row
    // then still gives the right length.

    function Na__ImageViewerCount__Scale() {
        var m = window.Na__ImageViewer__Measure;
        if (!m || typeof m.getScale !== 'function') return null;
        try {
            var s = m.getScale();
            return s && s.pxPerMm > 0 ? s : null;
        } catch (e) { return null; }
    }

    // { overall, part, unit, read:'flat'|'perspective' } in millimetres, or null.
    function Na__ImageViewerCount__Lengths(item, sp, scale) {
        if (!scale) return null;
        var dx = item.b.x - item.a.x, dy = item.b.y - item.a.y;
        var L  = Math.sqrt(dx * dx + dy * dy);
        if (!(L > 0)) return null;
        var overall = L / scale.pxPerMm, read = 'flat';
        var ref = scale.ref;
        if (ref && ref.mm > 0 && sp.k !== 1) {
            var along = na_solver.countReferenceLength(item.a, item.b, sp.k, ref.a, ref.b, ref.mm);
            if (along) { overall = along; read = 'perspective'; }
        }
        return { overall: overall, part: overall / item.n, unit: scale.unit, read: read };
    }

    // In the reference's unit, as Measure shows it; a part gets one more place.
    function Na__ImageViewerCount__FormatLength(mm, unit, fine) {
        if (unit === 'm')  return (mm / 1000).toFixed(fine ? 3 : 2) + ' m';
        if (unit === 'cm') return (mm / 10).toFixed(1) + ' cm';
        return Math.round(mm) + ' mm';
    }

    function Na__ImageViewerCount__DimsText(item, len) {
        if (!len) return '';
        var whole = Na__ImageViewerCount__FormatLength(len.overall, len.unit, false) + ' overall';
        if (item.n < 2) return whole;
        return Na__ImageViewerCount__FormatLength(len.part, len.unit, true) + ' each \u00b7 ' + whole;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Canvas Drawing Primitives
    // -------------------------------------------------------------------------

    function Na__ImageViewerCount__ToScreen(p) {
        return na_core.imgToScreen(p);
    }

    function Na__ImageViewerCount__Dist(p, q) {
        return Math.sqrt((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y));
    }

    function Na__ImageViewerCount__Font(ratio, fontPx, bold) {
        return (bold ? '700 ' : '600 ') + (fontPx * ratio) + 'px "Segoe UI", Arial, sans-serif';
    }

    function Na__ImageViewerCount__PillSize(ctx, ratio, text, fontPx, bold) {
        ctx.save();
        ctx.font = Na__ImageViewerCount__Font(ratio, fontPx, bold);
        var h = (fontPx + (bold ? 8 : 5)) * ratio;
        var w = Math.max(h, ctx.measureText(text).width + (bold ? 14 : 9) * ratio);
        ctx.restore();
        return { w: w, h: h };
    }

    // A rounded label. opt: { fontPx, bold, fill, color, border, left }
    function Na__ImageViewerCount__Pill(ctx, ratio, x, y, text, opt) {
        var size = Na__ImageViewerCount__PillSize(ctx, ratio, text, opt.fontPx, opt.bold);
        var left = opt.left ? x : x - size.w / 2;
        var top  = y - size.h / 2;
        var r    = size.h / 2;
        ctx.save();
        ctx.beginPath();
        ctx.moveTo(left + r, top);
        ctx.lineTo(left + size.w - r, top);
        ctx.arc(left + size.w - r, top + r, r, -Math.PI / 2, Math.PI / 2);
        ctx.lineTo(left + r, top + size.h);
        ctx.arc(left + r, top + r, r, Math.PI / 2, Math.PI * 1.5);
        ctx.closePath();
        ctx.fillStyle   = opt.fill;
        ctx.fill();
        ctx.strokeStyle = opt.border;
        ctx.lineWidth   = 1 * ratio;
        ctx.stroke();
        ctx.font         = Na__ImageViewerCount__Font(ratio, opt.fontPx, opt.bold);
        ctx.textBaseline = 'middle';
        ctx.textAlign    = 'center';
        ctx.fillStyle    = opt.color;
        ctx.fillText(text, left + size.w / 2, y + 0.5 * ratio);
        ctx.restore();
        return size;
    }

    // A label beside the pointer, as the guide tool shows its direction.
    function Na__ImageViewerCount__Tag(ctx, ratio, p, text) {
        Na__ImageViewerCount__Pill(ctx, ratio, p.x + 16 * ratio, p.y - 24 * ratio, text,
            { fontPx: NA_TAG_FONT_PX, bold: false, fill: NA_COLOR, color: '#ffffff', border: 'rgba(255, 255, 255, 0.9)', left: true });
    }

    function Na__ImageViewerCount__DrawHandle(ctx, ratio, p) {
        ctx.save();
        ctx.beginPath();
        ctx.arc(p.x, p.y, NA_HANDLE_PX * ratio, 0, Math.PI * 2);
        ctx.fillStyle   = NA_COLOR;
        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth   = 1.2 * ratio;
        ctx.fill();
        ctx.stroke();
        ctx.restore();
    }

    function Na__ImageViewerCount__DrawTickRing(ctx, ratio, p) {
        ctx.save();
        ctx.beginPath();
        ctx.arc(p.x, p.y, 6 * ratio, 0, Math.PI * 2);
        ctx.strokeStyle = NA_SELECT_COLOR;
        ctx.lineWidth   = 2 * ratio;
        ctx.stroke();
        ctx.restore();
    }

    // Zero-padded part numbers, as written on a site photo: 01, 02, 03...
    // (three digits past 99).
    function Na__ImageViewerCount__PartLabel(j, n) {
        var s = String(j);
        while (s.length < (n >= 100 ? 3 : 2)) s = '0' + s;
        return s;
    }

    // Number every part when the labels fit; otherwise every 2nd, 5th, 10th
    // part (with the first from every 5th on), always with the last.
    function Na__ImageViewerCount__ShownParts(centres, n, need) {
        function sep(i, j) { return Na__ImageViewerCount__Dist(centres[i], centres[j]); }
        if (n === 1) return [1];
        for (var si = 0; si < NA_NICE_STEPS.length; si++) {
            var step = NA_NICE_STEPS[si], list = [];
            for (var j = 1; j <= n; j++) {
                if (j === n || j % step === 0 || (j === 1 && step >= 5)) list.push(j);
            }
            while (list.length > 2 && sep(list[list.length - 2], n) < need) list.splice(list.length - 2, 1);
            while (list.length > 2 && list[0] === 1 && sep(1, list[1]) < need) list.splice(1, 1);
            var ok = true;
            for (var i = 1; i < list.length && ok; i++) if (sep(list[i - 1], list[i]) < need) ok = false;
            if (ok) return list;
        }
        return sep(1, n) >= need ? [1, n] : [n];
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Overlay Rendering
    // -------------------------------------------------------------------------

    function Na__ImageViewerCount__Render(ctx) {
        var key = Na__ImageViewerCount__Key();
        if (!ctx || !key) return;
        var ratio = na_core.getRatio();
        var dirs  = Na__ImageViewerCount__Directions();
        var scale = Na__ImageViewerCount__Scale();

        (na_countsByKey[key] || []).forEach(function(item) {
            var state = na_active && item.id === na_selectedId ? 'selected' : 'normal';
            Na__ImageViewerCount__DrawCount(ctx, ratio, item, Na__ImageViewerCount__Spacing(item, dirs), state, scale);
        });
        if (!na_active) return;
        if (na_live && na_phase === 'divide') {
            Na__ImageViewerCount__DrawCount(ctx, ratio, na_live, Na__ImageViewerCount__Spacing(na_live, dirs), 'live', scale);
            if (na_cursor) Na__ImageViewerCount__Tag(ctx, ratio, na_cursor, String(na_live.n));
        } else if (na_live && na_phase === 'draw') {
            Na__ImageViewerCount__DrawPlacing(ctx, ratio, dirs);
        }
        Na__ImageViewerCount__DrawLoupe(ctx, ratio, dirs);
    }

    function Na__ImageViewerCount__DrawCount(ctx, ratio, item, sp, state, scale) {
        var ticks = Na__ImageViewerCount__Ticks(item, sp).map(Na__ImageViewerCount__ToScreen);
        var A = ticks[0], B = ticks[ticks.length - 1];
        var L = Na__ImageViewerCount__Dist(A, B);
        if (L < 1e-6) return;
        var u    = { x: (B.x - A.x) / L, y: (B.y - A.y) / L };
        var nrm  = { x: -u.y, y: u.x };
        // Numbers go to the right of a vertical line and above a level one.
        var side = nrm.x - nrm.y >= 0 ? nrm : { x: -nrm.x, y: -nrm.y };

        ctx.save();
        ctx.lineCap = 'round';
        ctx.beginPath();
        ctx.moveTo(A.x, A.y);
        ctx.lineTo(B.x, B.y);
        ticks.forEach(function(p, j) {
            var half = (j === 0 || j === ticks.length - 1 ? NA_END_TICK_PX : NA_TICK_PX) * ratio;
            ctx.moveTo(p.x - nrm.x * half, p.y - nrm.y * half);
            ctx.lineTo(p.x + nrm.x * half, p.y + nrm.y * half);
        });
        ctx.strokeStyle = state === 'selected' ? NA_SELECT_COLOR : NA_HALO_COLOR;
        ctx.lineWidth   = (NA_LINE_PX + (state === 'selected' ? 4 : 2.5)) * ratio;
        ctx.stroke();
        ctx.strokeStyle = NA_COLOR;
        ctx.lineWidth   = NA_LINE_PX * ratio;
        ctx.stroke();
        ctx.restore();

        Na__ImageViewerCount__DrawNumbers(ctx, ratio, item, ticks, u, side);

        var total  = String(item.n);
        var tsize  = Na__ImageViewerCount__PillSize(ctx, ratio, total, NA_TOTAL_FONT_PX, true);
        var talong = Math.abs(u.x) * tsize.w + Math.abs(u.y) * tsize.h;
        var reach  = 7 * ratio + talong / 2;
        Na__ImageViewerCount__Pill(ctx, ratio, B.x + u.x * reach, B.y + u.y * reach, total,
            { fontPx: NA_TOTAL_FONT_PX, bold: true, fill: NA_COLOR, color: '#ffffff', border: '#ffffff' });

        var len = Na__ImageViewerCount__Lengths(item, sp, scale);
        if (len) Na__ImageViewerCount__DrawDims(ctx, ratio, item, ticks, u, side, len, B, reach + talong / 2);

        if (state !== 'selected') return;
        Na__ImageViewerCount__DrawHandle(ctx, ratio, A);
        Na__ImageViewerCount__DrawHandle(ctx, ratio, B);
        var ring = na_drag && na_drag.item === item ? na_drag : (na_hover && na_hover.item === item ? na_hover : null);
        if (ring && ring.part === 'tick' && ticks[ring.index]) Na__ImageViewerCount__DrawTickRing(ctx, ratio, ticks[ring.index]);
    }

    // A numbered bubble beside each part, at the part's middle on the photo.
    function Na__ImageViewerCount__DrawNumbers(ctx, ratio, item, ticks, u, side) {
        var n = item.n;
        var size   = Na__ImageViewerCount__PillSize(ctx, ratio, Na__ImageViewerCount__PartLabel(n, n), NA_BUBBLE_FONT_PX, false);
        var along  = Math.abs(u.x) * size.w + Math.abs(u.y) * size.h;
        var across = Math.abs(side.x) * size.w + Math.abs(side.y) * size.h;
        var off    = (NA_END_TICK_PX + 3) * ratio + across / 2;
        var centres = [null];
        for (var j = 1; j <= n; j++) {
            centres.push({ x: (ticks[j - 1].x + ticks[j].x) / 2, y: (ticks[j - 1].y + ticks[j].y) / 2 });
        }
        Na__ImageViewerCount__ShownParts(centres, n, along + 3 * ratio).forEach(function(k) {
            Na__ImageViewerCount__Pill(ctx, ratio, centres[k].x + side.x * off, centres[k].y + side.y * off,
                Na__ImageViewerCount__PartLabel(k, n), { fontPx: NA_BUBBLE_FONT_PX, bold: false, fill: '#ffffff', color: NA_COLOR, border: NA_COLOR });
        });
    }

    // Each part's length on the side away from the numbers (all of them when
    // they fit, else once, 'each'), and the overall length after the total.
    function Na__ImageViewerCount__DrawDims(ctx, ratio, item, ticks, u, side, len, B, endReach) {
        var n = item.n;
        var overall = Na__ImageViewerCount__FormatLength(len.overall, len.unit, false);
        var osize   = Na__ImageViewerCount__PillSize(ctx, ratio, overall, NA_OVERALL_FONT_PX, true);
        var oreach  = endReach + 5 * ratio + (Math.abs(u.x) * osize.w + Math.abs(u.y) * osize.h) / 2;
        Na__ImageViewerCount__Pill(ctx, ratio, B.x + u.x * oreach, B.y + u.y * oreach, overall,
            { fontPx: NA_OVERALL_FONT_PX, bold: true, fill: NA_DIM_COLOR, color: '#ffffff', border: '#ffffff' });
        if (n < 2) return;

        var text   = Na__ImageViewerCount__FormatLength(len.part, len.unit, true);
        var size   = Na__ImageViewerCount__PillSize(ctx, ratio, text, NA_DIM_FONT_PX, false);
        var along  = Math.abs(u.x) * size.w + Math.abs(u.y) * size.h;
        var fits   = true, centres = [];
        for (var j = 1; j <= n; j++) {
            centres.push({ x: (ticks[j - 1].x + ticks[j].x) / 2, y: (ticks[j - 1].y + ticks[j].y) / 2 });
            if (j > 1 && Na__ImageViewerCount__Dist(centres[j - 1], centres[j - 2]) < along + 3 * ratio) fits = false;
        }
        var shown = fits ? centres : [centres[Math.floor((n - 1) / 2)]];
        if (!fits) {
            text = text + ' each';
            size = Na__ImageViewerCount__PillSize(ctx, ratio, text, NA_DIM_FONT_PX, false);
        }
        var off = (NA_END_TICK_PX + 3) * ratio + (Math.abs(side.x) * size.w + Math.abs(side.y) * size.h) / 2;
        shown.forEach(function(c) {
            Na__ImageViewerCount__Pill(ctx, ratio, c.x - side.x * off, c.y - side.y * off, text,
                { fontPx: NA_DIM_FONT_PX, bold: false, fill: '#ffffff', color: NA_DIM_COLOR, border: NA_DIM_COLOR });
        });
    }

    // Placing the far end: a dashed line, and how the parts will be spaced.
    function Na__ImageViewerCount__DrawPlacing(ctx, ratio, dirs) {
        var A = Na__ImageViewerCount__ToScreen(na_live.a);
        var B = Na__ImageViewerCount__ToScreen(na_live.b);
        var L = Na__ImageViewerCount__Dist(A, B);
        ctx.save();
        ctx.lineCap = 'round';
        if (L > 1e-6) {
            var nx = -(B.y - A.y) / L, ny = (B.x - A.x) / L, half = NA_END_TICK_PX * ratio;
            ctx.beginPath();
            [A, B].forEach(function(p) {
                ctx.moveTo(p.x - nx * half, p.y - ny * half);
                ctx.lineTo(p.x + nx * half, p.y + ny * half);
            });
            ctx.strokeStyle = NA_HALO_COLOR;
            ctx.lineWidth   = (NA_LINE_PX + 2.5) * ratio;
            ctx.stroke();
            ctx.strokeStyle = NA_COLOR;
            ctx.lineWidth   = NA_LINE_PX * ratio;
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(A.x, A.y);
            ctx.lineTo(B.x, B.y);
            ctx.setLineDash([7 * ratio, 5 * ratio]);
            ctx.strokeStyle = NA_HALO_COLOR;
            ctx.lineWidth   = (NA_LINE_PX + 2.5) * ratio;
            ctx.stroke();
            ctx.strokeStyle = NA_COLOR;
            ctx.lineWidth   = NA_LINE_PX * ratio;
            ctx.stroke();
        }
        ctx.restore();
        Na__ImageViewerCount__DrawHandle(ctx, ratio, A);
        if (na_cursor && L >= NA_MIN_LINE_PX * ratio) {
            var sp = Na__ImageViewerCount__Spacing(na_live, dirs);
            Na__ImageViewerCount__Tag(ctx, ratio, B, sp.kind === 'perspective' ? sp.label : 'Even spacing');
        }
    }

    // A magnifier beside the point being placed or dragged, as in Angle.
    function Na__ImageViewerCount__LoupeTarget(dirs) {
        if (na_drag) {
            if (na_drag.part === 'tick') {
                var t = Na__ImageViewerCount__Ticks(na_drag.item, Na__ImageViewerCount__Spacing(na_drag.item, dirs));
                return t[na_drag.index] ? Na__ImageViewerCount__ToScreen(t[na_drag.index]) : null;
            }
            return Na__ImageViewerCount__ToScreen(na_drag.item[na_drag.part]);
        }
        if (!na_cursor || (na_press && na_press.kind === 'pan')) return null;
        if (na_phase === 'draw' && na_live) return Na__ImageViewerCount__ToScreen(na_live.b);
        if (na_phase === null && !na_hover) return na_snap ? na_snap.screen : na_cursor;
        return null;
    }

    function Na__ImageViewerCount__DrawLoupe(ctx, ratio, dirs) {
        var target = Na__ImageViewerCount__LoupeTarget(dirs);
        if (!target) return;
        var img  = na_core.getImage();
        var size = na_core.getImageSize();
        if (!img || !img.complete || !size.w) return;

        var R   = NA_LOUPE_RADIUS_PX * ratio;
        var w   = na_canvas.width, h = na_canvas.height;
        var off = R + 26 * ratio;
        var lx  = target.x - off, ly = target.y - off;
        if (lx - R < 6 * ratio) lx = target.x + off;
        if (ly - R < 6 * ratio) ly = target.y + off;
        if (lx + R > w - 6 * ratio) lx = target.x - off;
        if (ly + R > h - 6 * ratio) ly = target.y - off;

        var gain = Math.min(12, Math.max(1.5, na_core.getZoom() * NA_LOUPE_GAIN));
        var ip   = na_core.screenToImg(target.x, target.y);

        ctx.save();
        ctx.beginPath();
        ctx.arc(lx, ly, R, 0, Math.PI * 2);
        ctx.closePath();
        ctx.fillStyle = '#20242a';
        ctx.fill();
        ctx.clip();
        ctx.translate(lx, ly);
        ctx.rotate(na_core.getRotation());
        ctx.scale(gain, gain);
        ctx.translate(-ip.x, -ip.y);
        ctx.imageSmoothingEnabled = gain < 3;
        ctx.drawImage(img, -size.w / 2, -size.h / 2);

        // Counts inside the loupe, in image space at a hairline width.
        var items = (na_countsByKey[Na__ImageViewerCount__Key()] || []).slice();
        if (na_live) items.push(na_live);
        ctx.lineCap     = 'round';
        ctx.lineWidth   = 1.4 * ratio / gain;
        ctx.strokeStyle = NA_COLOR;
        items.forEach(function(item) {
            var dx = item.b.x - item.a.x, dy = item.b.y - item.a.y;
            var L  = Math.sqrt(dx * dx + dy * dy);
            if (L < 1e-9) return;
            var nx = -dy / L, ny = dx / L, half = NA_TICK_PX * ratio / gain;
            ctx.beginPath();
            ctx.moveTo(item.a.x, item.a.y);
            ctx.lineTo(item.b.x, item.b.y);
            Na__ImageViewerCount__Ticks(item, Na__ImageViewerCount__Spacing(item, dirs)).forEach(function(q) {
                ctx.moveTo(q.x - nx * half, q.y - ny * half);
                ctx.lineTo(q.x + nx * half, q.y + ny * half);
            });
            ctx.stroke();
        });
        ctx.restore();

        ctx.save();
        ctx.beginPath();
        ctx.arc(lx, ly, R, 0, Math.PI * 2);
        ctx.lineWidth   = 3 * ratio;
        ctx.strokeStyle = 'rgba(0, 0, 0, 0.45)';
        ctx.stroke();
        ctx.lineWidth   = 1.6 * ratio;
        ctx.strokeStyle = '#ffffff';
        ctx.stroke();
        var gap = 5 * ratio, arm = 16 * ratio;
        [[1, 0], [-1, 0], [0, 1], [0, -1]].forEach(function(d) {
            ctx.beginPath();
            ctx.moveTo(lx + d[0] * gap, ly + d[1] * gap);
            ctx.lineTo(lx + d[0] * arm, ly + d[1] * arm);
            ctx.lineWidth = 3 * ratio;   ctx.strokeStyle = 'rgba(0, 0, 0, 0.55)'; ctx.stroke();
            ctx.lineWidth = 1.2 * ratio; ctx.strokeStyle = '#ffffff';             ctx.stroke();
        });
        ctx.restore();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Hit Testing And Snapping
    // -------------------------------------------------------------------------

    // An end of any count (the selected count's first where ends meet), else
    // a tick of the selected count.
    function Na__ImageViewerCount__HitHandle(p) {
        var list  = na_countsByKey[Na__ImageViewerCount__Key()] || [];
        var ratio = na_core.getRatio();
        var best = null, bestD = NA_HIT_PX * ratio, bestSelected = false;
        list.forEach(function(item) {
            var selected = item.id === na_selectedId;
            ['a', 'b'].forEach(function(part) {
                var d = Na__ImageViewerCount__Dist(Na__ImageViewerCount__ToScreen(item[part]), p);
                if (d > NA_HIT_PX * ratio || (bestSelected && !selected)) return;
                if ((selected && !bestSelected) || d <= bestD) {
                    best = { item: item, part: part, index: part === 'a' ? 0 : item.n };
                    bestD = d;
                    bestSelected = selected;
                }
            });
        });
        if (best) return best;

        var sel = na_selectedId !== null ? Na__ImageViewerCount__Find(na_selectedId) : null;
        if (!sel || sel.n < 2) return null;
        var ticks = Na__ImageViewerCount__Ticks(sel, Na__ImageViewerCount__Spacing(sel));
        var tickD = NA_TICK_HIT_PX * ratio;
        for (var j = 1; j < sel.n; j++) {
            var d = Na__ImageViewerCount__Dist(Na__ImageViewerCount__ToScreen(ticks[j]), p);
            if (d <= tickD) { tickD = d; best = { item: sel, part: 'tick', index: j }; }
        }
        return best;
    }

    function Na__ImageViewerCount__HitCount(p) {
        var list = na_countsByKey[Na__ImageViewerCount__Key()] || [];
        var best = null, bestD = NA_HIT_PX * na_core.getRatio();
        list.forEach(function(item) {
            var A = Na__ImageViewerCount__ToScreen(item.a), B = Na__ImageViewerCount__ToScreen(item.b);
            var c = na_solver.closestOnSegment(p, { a: A, b: B });
            if (c.dist <= bestD) { bestD = c.dist; best = item; }
        });
        return best;
    }

    // Snap points this tool offers through the Core, to itself and to the
    // Measure tool: the ends of every count and each tick between them.
    function Na__ImageViewerCount__ProvideSnap(cx, cy) {
        var list = na_countsByKey[Na__ImageViewerCount__Key()] || [];
        if (!list.length) return null;
        var p    = { x: cx, y: cy };
        var dirs = Na__ImageViewerCount__Directions();
        var best = null, bestD = NA_SNAP_PX * na_core.getRatio();
        list.forEach(function(item) {
            if (item === na_snapExclude) return;
            Na__ImageViewerCount__Ticks(item, Na__ImageViewerCount__Spacing(item, dirs)).forEach(function(q, j) {
                var s = Na__ImageViewerCount__ToScreen(q);
                var d = Na__ImageViewerCount__Dist(s, p);
                if (d > bestD) return;
                var end = j === 0 || j === item.n;
                bestD = d;
                best  = { img: { x: q.x, y: q.y }, screen: s, kind: end ? 'endpoint' : 'division', label: end ? 'Count end' : 'Tick ' + j };
            });
        });
        return best;
    }

    function Na__ImageViewerCount__SnapAt(p) {
        var hit = typeof na_core.snap === 'function' ? na_core.snap(p.x, p.y) : null;
        if (hit) return { hit: hit, img: { x: hit.img.x, y: hit.img.y }, screen: hit.screen };
        return { hit: null, img: na_core.screenToImg(p.x, p.y), screen: { x: p.x, y: p.y } };
    }

    function Na__ImageViewerCount__SetMarker(hit) {
        if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(hit || null);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Making And Editing Counts
    // -------------------------------------------------------------------------

    function Na__ImageViewerCount__OnPhoto(img) {
        var size = na_core.getImageSize();
        return size.w > 0 && Math.abs(img.x) <= size.w / 2 && Math.abs(img.y) <= size.h / 2;
    }

    function Na__ImageViewerCount__CancelLive() {
        na_live  = null;
        na_phase = null;
        na_snap  = null;
        Na__ImageViewerCount__SetMarker(null);
    }

    function Na__ImageViewerCount__StartLine(img) {
        na_selectedId = null;
        na_live  = { a: { x: img.x, y: img.y }, b: { x: img.x, y: img.y }, n: 1, follow: true };
        na_phase = 'draw';
    }

    // The far end is placed: on to dividing, or keep waiting if the line is
    // too short to count along.
    function Na__ImageViewerCount__FinishLine(p) {
        if (!na_live) return;
        var snap = Na__ImageViewerCount__SnapAt(p);
        na_live.b = snap.img;
        na_snap   = null;
        Na__ImageViewerCount__SetMarker(null);
        var L = Na__ImageViewerCount__Dist(Na__ImageViewerCount__ToScreen(na_live.a), Na__ImageViewerCount__ToScreen(na_live.b));
        if (L < NA_MIN_LINE_PX * na_core.getRatio()) {
            na_phase = 'draw';
        } else {
            na_phase       = 'divide';
            na_live.n      = 1;
            na_live.follow = true;
        }
        Na__ImageViewerCount__RefreshBar();
        na_core.requestDraw();
    }

    function Na__ImageViewerCount__Commit() {
        var key = Na__ImageViewerCount__Key();
        if (!key || !na_live || na_phase !== 'divide') return;
        na_core.pushHistory();
        var item = { id: na_nextId++, a: { x: na_live.a.x, y: na_live.a.y }, b: { x: na_live.b.x, y: na_live.b.y }, n: na_live.n, vp: null };
        Na__ImageViewerCount__List(key).push(item);
        Na__ImageViewerCount__CancelLive();
        na_selectedId = item.id;
        na_inputError = '';
        Na__ImageViewerCount__RefreshBar(true);
        na_core.requestDraw();
    }

    function Na__ImageViewerCount__SetCount(n) {
        var target = Na__ImageViewerCount__Target();
        if (!target) return;
        if (target === na_live) {
            na_live.n      = n;
            na_live.follow = false;   // the keys have taken over from the pointer
        } else if (target.n !== n) {
            na_core.pushHistory();
            target.n = n;
        }
        na_inputError = '';
        Na__ImageViewerCount__RefreshBar(true);
        na_core.requestDraw();
    }

    function Na__ImageViewerCount__Step(delta) {
        var target = Na__ImageViewerCount__Target();
        if (!target) return;
        var n = target.n + delta;
        if (n < 1 && target.n > 1) n = 1;
        if (n > NA_MAX_COUNT && target.n < NA_MAX_COUNT) n = NA_MAX_COUNT;
        if (n < 1) {
            Na__ImageViewerCount__Notice('1 is the fewest a count can have.');
            return;
        }
        if (n > NA_MAX_COUNT) {
            Na__ImageViewerCount__Notice(NA_MAX_COUNT + ' is the most one count can hold. Count the rest with a second line.');
            return;
        }
        Na__ImageViewerCount__SetCount(n);
    }

    function Na__ImageViewerCount__DragTo(p) {
        var item = na_drag.item;
        if (na_drag.part === 'tick') {
            // The dragged tick goes where it is put, the ends stay, and the
            // other ticks follow the perspective that implies.
            var s = na_solver.lineFraction(item.a, item.b, na_core.screenToImg(p.x, p.y));
            s = Math.max(0.01, Math.min(0.99, s));
            var k = na_solver.countTaper(item.n, na_drag.index, s);
            if (!k) return;
            k = Math.max(1 / NA_TAPER_LIMIT, Math.min(NA_TAPER_LIMIT, k));
            item.vp = na_solver.countVanishingPoint(item.a, item.b, k);
            Na__ImageViewerCount__SetMarker(null);
            return;
        }
        var snap = Na__ImageViewerCount__SnapAt(p);
        item[na_drag.part] = snap.img;
        Na__ImageViewerCount__SetMarker(snap.hit);
    }

    function Na__ImageViewerCount__ResetSpacing() {
        var item = na_selectedId !== null ? Na__ImageViewerCount__Find(na_selectedId) : null;
        if (!item || !item.vp) return;
        na_core.pushHistory();
        item.vp = null;
        Na__ImageViewerCount__RefreshBar();
        na_core.requestDraw();
    }

    function Na__ImageViewerCount__DeleteSelected() {
        var key  = Na__ImageViewerCount__Key();
        var item = na_selectedId !== null ? Na__ImageViewerCount__Find(na_selectedId) : null;
        if (!key || !item) return;
        na_core.pushHistory();
        na_countsByKey[key] = na_countsByKey[key].filter(function(c) { return c !== item; });
        na_selectedId = null;
        Na__ImageViewerCount__Notice('Count deleted. Ctrl+Z brings it back.');
        na_core.requestDraw();
    }

    function Na__ImageViewerCount__ClearAll() {
        var key = Na__ImageViewerCount__Key();
        if (!key || !na_countsByKey[key] || !na_countsByKey[key].length) return;
        na_core.pushHistory();
        delete na_countsByKey[key];
        na_selectedId = null;
        Na__ImageViewerCount__CancelLive();
        Na__ImageViewerCount__Notice('Counts cleared on this photo. Ctrl+Z brings them back.');
        na_core.requestDraw();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Typed Count
    // -------------------------------------------------------------------------

    // A bare number is how many things the line covers. Anything that cannot
    // be a count is refused with the fix named, never rounded.
    function Na__ImageViewerCount__ParseCount(raw) {
        var s = String(raw === undefined || raw === null ? '' : raw).trim().toLowerCase().replace(/\s+/g, '').replace(/^[x\u00d7]/, '').replace(/[x\u00d7]$/, '');
        if (!s) return { ok: false, empty: true };
        if (!/^[0-9]*\.?[0-9]+$/.test(s)) return { ok: false, message: 'Type how many there are, e.g. 14.' };
        var v = parseFloat(s);
        if (v < 1) return { ok: false, message: s + ' is not a count. Type 1 or more.' };
        if (v !== Math.floor(v)) return { ok: false, message: s + ' is not a whole number. Type ' + Math.floor(v) + ' or ' + Math.ceil(v) + '.' };
        if (v > NA_MAX_COUNT) return { ok: false, message: s + ' is more than one count can hold. Type up to ' + NA_MAX_COUNT + ', or count in two lines.' };
        return { ok: true, n: v };
    }

    // Digits typed over the photo go into the count box, as SketchUp's
    // Measurements box takes them.
    function Na__ImageViewerCount__BeginTyping(ch) {
        if (!na_input) return;
        if (na_live) na_live.follow = false;
        na_inputError = '';
        na_input.disabled = false;
        na_input.value = ch;
        na_input.focus();
        try { na_input.setSelectionRange(na_input.value.length, na_input.value.length); } catch (e) { /* not a text box */ }
        Na__ImageViewerCount__RefreshBar();
    }

    // Returns true when the box can hand the keys back.
    function Na__ImageViewerCount__OnInputCommit() {
        if (!na_input) return true;
        var parsed = Na__ImageViewerCount__ParseCount(na_input.value);
        if (parsed.empty) {
            na_inputError = '';
            Na__ImageViewerCount__RefreshBar(true);
            return true;
        }
        if (!parsed.ok) {
            na_inputError = parsed.message;
            Na__ImageViewerCount__RefreshBar();
            return false;
        }
        var finishing = Na__ImageViewerCount__Target() === na_live && !!na_live;
        Na__ImageViewerCount__SetCount(parsed.n);
        if (finishing) Na__ImageViewerCount__Commit();   // a typed number ends the count, as in SketchUp
        return true;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Tool State And Bar
    // -------------------------------------------------------------------------

    // Stop counting, keep the counts.
    function Na__ImageViewerCount__Reset() {
        na_active = false;
        Na__ImageViewerCount__CancelLive();
        na_press       = null;
        na_drag        = null;
        na_hover       = null;
        na_snapExclude = null;
        na_selectedId  = null;
        na_inputError  = '';
        na_notice      = '';
        if (na_input && document.activeElement === na_input) na_input.blur();
    }

    // Another tool took the canvas.
    function Na__ImageViewerCount__Release() {
        Na__ImageViewerCount__Reset();
        Na__ImageViewerCount__UpdateCursor();
        Na__ImageViewerCount__RefreshBar();
        na_core.requestDraw();
    }

    function Na__ImageViewerCount__SetActive(on) {
        if (on) {
            na_active = true;
            na_notice = '';
            na_core.claimTool(NA_TOOL_NAME, Na__ImageViewerCount__Release);
        } else {
            Na__ImageViewerCount__Reset();
            na_core.releaseTool(NA_TOOL_NAME);
        }
        Na__ImageViewerCount__UpdateCursor();
        Na__ImageViewerCount__RefreshBar(true);
        na_core.requestDraw();
    }

    function Na__ImageViewerCount__Notice(text) {
        na_notice = text || '';
        Na__ImageViewerCount__RefreshBar();
    }

    function Na__ImageViewerCount__HintText(target, sp, len) {
        if (!Na__ImageViewerCount__Key()) return 'Choose a folder of photos first.';
        if (na_phase === 'draw') return 'Release, or click, where the last one ends.';
        if (na_phase === 'divide') {
            if (!na_live.follow) return 'Click, or press Enter, to set the count. Scroll, or Up and Down, for one more or one fewer.';
            return 'Move back along the line toward its start: the first part follows the pointer. Scroll, or Up and Down, for one more or one fewer, until every tick sits on a joint. Click to set, or type the number.';
        }
        if (target) {
            if (len && len.read === 'flat' && sp && sp.kind !== 'even') {
                return 'Sizes are read flat from the reference, as Measure reads them. For sizes in perspective, Set Reference on this count: click two of its ticks.';
            }
            if (sp && sp.kind === 'even') {
                return 'Even spacing. If the parts shrink with distance, calibrate the photo in Angle (two blue verticals are enough for a vertical count), or drag a tick onto its joint.';
            }
            return 'Up and Down add or remove one, or type the number. Drag an end to move it, or a tick onto its joint to match the perspective by hand. Delete removes.';
        }
        return 'Drag from where the first one starts to where the last one ends: brick courses, bricks, tiles. Right-drag pans, the wheel zooms.';
    }

    // forceValue rewrites the count box even while it has the focus.
    function Na__ImageViewerCount__RefreshBar(forceValue) {
        if (na_btnTool) na_btnTool.classList.toggle('naImageViewer__Btn--active', na_active);
        if (!na_bar) return;
        na_bar.classList.toggle('naImageViewer__CountBar--open', na_active);
        if (!na_active) return;

        var key    = Na__ImageViewerCount__Key();
        var target = Na__ImageViewerCount__Target();
        var typing = na_input && document.activeElement === na_input;
        var sp     = target ? Na__ImageViewerCount__Spacing(target) : (na_live ? Na__ImageViewerCount__Spacing(na_live) : null);

        if (na_input) {
            if (!typing) na_input.disabled = !target;
            if (!typing || forceValue) na_input.value = target ? String(target.n) : '';
            na_input.classList.toggle('naImageViewer__CountInput--error', !!na_inputError);
        }
        if (na_btnMinus)  na_btnMinus.disabled = !target || target.n <= 1;
        if (na_btnPlus)   na_btnPlus.disabled  = !target || target.n >= NA_MAX_COUNT;
        if (na_spacingEl) na_spacingEl.textContent = sp ? Na__ImageViewerCount__SpacingText(sp) : '';
        var len = target && sp ? Na__ImageViewerCount__Lengths(target, sp, Na__ImageViewerCount__Scale()) : null;
        if (na_dimsEl) {
            na_dimsEl.textContent = Na__ImageViewerCount__DimsText(target, len);
            na_dimsEl.title = !len ? '' : len.read === 'perspective'
                ? 'From the reference line beside this count, read in perspective'
                : 'From the reference scale (Set Reference), read flat as Measure reads it';
        }
        if (na_btnReset)  na_btnReset.style.display = target && target !== na_live && target.vp ? '' : 'none';
        if (na_btnClear)  na_btnClear.disabled = !(key && na_countsByKey[key] && na_countsByKey[key].length);
        if (na_hintEl) {
            na_hintEl.textContent = na_inputError || na_notice || Na__ImageViewerCount__HintText(target, sp, len);
            na_hintEl.classList.toggle('naImageViewer__CountHint--error', !!na_inputError);
        }
    }

    function Na__ImageViewerCount__UpdateCursor() {
        if (!na_canvas) return;
        var cursor = '';
        if (na_active) {
            if (na_drag || (na_press && na_press.kind === 'pan')) cursor = 'grabbing';
            else if (na_phase === null && na_hover) cursor = na_hover.part === 'tick' ? 'grab' : 'move';
            else cursor = 'crosshair';
        }
        if (na_canvas.style.cursor !== cursor) na_canvas.style.cursor = cursor;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Canvas Interaction
    // -------------------------------------------------------------------------

    function Na__ImageViewerCount__CanvasPoint(e) {
        var rect  = na_canvas.getBoundingClientRect();
        var ratio = na_core.getRatio();
        return { x: (e.clientX - rect.left) * ratio, y: (e.clientY - rect.top) * ratio };
    }

    // Capture phase on the canvas wrapper, ahead of the viewer's own pan:
    // while the tool is active every press on the photo is ours.
    function Na__ImageViewerCount__OnMouseDown(e) {
        if (!na_active || e.target !== na_canvas) return;
        e.stopPropagation();
        e.preventDefault();
        if (na_input && document.activeElement === na_input) na_input.blur();   // commits a typed count
        na_notice = '';
        if (!Na__ImageViewerCount__Key()) return;

        var p     = Na__ImageViewerCount__CanvasPoint(e);
        var press = { x: e.clientX, y: e.clientY, lastX: e.clientX, lastY: e.clientY, moved: false };
        if (e.button !== 0)            press.kind = 'pan';
        else if (na_phase === 'divide') press.kind = 'divide';
        else if (na_phase === 'draw')   press.kind = 'second';   // the far end of a clicked line
        else {
            var hit = Na__ImageViewerCount__HitHandle(p);
            if (hit) {
                press.kind = 'handle';
                press.hit  = hit;
            } else {
                press.kind = 'start';
                press.img  = Na__ImageViewerCount__SnapAt(p).img;
                press.on   = Na__ImageViewerCount__HitCount(p);
            }
        }
        na_press = press;
        Na__ImageViewerCount__UpdateCursor();
    }

    function Na__ImageViewerCount__OnMouseMove(e) {
        if (!na_active || !na_canvas) return;
        var p    = Na__ImageViewerCount__CanvasPoint(e);
        var over = e.target === na_canvas;

        if (na_press) {
            var dist = Math.sqrt((e.clientX - na_press.x) * (e.clientX - na_press.x) + (e.clientY - na_press.y) * (e.clientY - na_press.y));
            if (dist > NA_DRAG_START_PX) na_press.moved = true;
            if (na_press.kind === 'pan') {
                var ratio = na_core.getRatio();
                na_core.panBy((e.clientX - na_press.lastX) * ratio, (e.clientY - na_press.lastY) * ratio);
                na_press.lastX = e.clientX;
                na_press.lastY = e.clientY;
                return;
            }
            na_press.lastX = e.clientX;
            na_press.lastY = e.clientY;
            if (na_press.kind === 'start' && na_press.moved) {
                if (!Na__ImageViewerCount__OnPhoto(na_press.img)) {
                    na_press = null;
                    Na__ImageViewerCount__Notice('Start on the photo itself.');
                    return;
                }
                Na__ImageViewerCount__StartLine(na_press.img);
                na_press.kind = 'line';
                Na__ImageViewerCount__RefreshBar();
            }
            if (na_press.kind === 'handle' && na_press.moved && !na_drag) {
                na_core.pushHistory();
                na_drag        = { item: na_press.hit.item, part: na_press.hit.part, index: na_press.hit.index };
                na_selectedId  = na_drag.item.id;
                na_snapExclude = na_drag.item;
                na_hover       = null;
            }
        }

        if (na_drag) {
            Na__ImageViewerCount__DragTo(p);
            na_cursor = over ? p : null;
            Na__ImageViewerCount__UpdateCursor();
            Na__ImageViewerCount__RefreshBar();
            na_core.requestDraw();
            return;
        }

        na_cursor = over ? p : null;
        if (na_phase === 'draw' && na_live) {
            if (over) {
                na_snap   = Na__ImageViewerCount__SnapAt(p);
                na_live.b = na_snap.img;
                Na__ImageViewerCount__SetMarker(na_snap.hit);
            }
        } else if (na_phase === 'divide') {
            if (over && Na__ImageViewerCount__FollowPointer(p)) Na__ImageViewerCount__RefreshBar(true);
        } else if (!na_press) {
            na_hover = over ? Na__ImageViewerCount__HitHandle(p) : null;
            na_snap  = over && !na_hover ? Na__ImageViewerCount__SnapAt(p) : null;
            Na__ImageViewerCount__SetMarker(na_snap ? na_snap.hit : null);
        }
        Na__ImageViewerCount__UpdateCursor();
        na_core.requestDraw();
    }

    function Na__ImageViewerCount__OnMouseUp(e) {
        var press = na_press;
        na_press = null;
        if (!na_active || !press) return;
        if (press.kind === 'pan') { Na__ImageViewerCount__UpdateCursor(); return; }

        if (na_drag) {
            na_drag        = null;
            na_snapExclude = null;
            Na__ImageViewerCount__SetMarker(null);
            Na__ImageViewerCount__UpdateCursor();
            Na__ImageViewerCount__RefreshBar(true);
            na_core.requestDraw();
            return;
        }

        var p = Na__ImageViewerCount__CanvasPoint(e);
        if (press.kind === 'line' || press.kind === 'second') {
            Na__ImageViewerCount__FinishLine(p);
        } else if (press.kind === 'divide') {
            if (e.target === na_canvas) {
                Na__ImageViewerCount__FollowPointer(p);
                Na__ImageViewerCount__Commit();
            }
        } else if (press.kind === 'handle') {
            na_selectedId = press.hit.item.id;    // a click on an end selects its count
        } else if (press.kind === 'start') {
            // A click: select the count under it, else let go of the selection,
            // else start a line by clicks.
            if (press.on)                    na_selectedId = press.on.id;
            else if (na_selectedId !== null) na_selectedId = null;
            else if (Na__ImageViewerCount__OnPhoto(press.img)) Na__ImageViewerCount__StartLine(press.img);
            else                             na_notice = 'Start on the photo itself.';
        }
        Na__ImageViewerCount__UpdateCursor();
        Na__ImageViewerCount__RefreshBar(true);
        na_core.requestDraw();
    }

    // While dividing, the wheel is a dial for the count (up for more), so
    // the ticks can be brought onto the joints one step at a time. At any
    // other time it zooms as usual.
    function Na__ImageViewerCount__OnWheel(e) {
        if (!na_active || na_phase !== 'divide' || !na_live || e.target !== na_canvas) return;
        e.preventDefault();
        e.stopPropagation();
        var dy = e.deltaMode === 1 ? e.deltaY * 33 : e.deltaMode === 2 ? e.deltaY * 400 : e.deltaY;
        na_wheelAcc += dy;
        var steps = 0;
        while (na_wheelAcc <= -NA_WHEEL_STEP) { steps++; na_wheelAcc += NA_WHEEL_STEP; }
        while (na_wheelAcc >=  NA_WHEEL_STEP) { steps--; na_wheelAcc -= NA_WHEEL_STEP; }
        if (!steps) return;
        na_notice = '';
        na_live.follow = false;
        Na__ImageViewerCount__Step(steps);
    }

    function Na__ImageViewerCount__OnMouseLeave() {
        if (!na_active || na_drag) return;
        na_cursor = null;
        na_hover  = null;
        if (na_phase !== 'draw') na_snap = null;
        na_core.requestDraw();
    }

    // Capture phase, ahead of the viewer: while the tool is active, digits go
    // to the count (not Fit / 100%), Up and Down step it, and Delete and Esc
    // act on the count.
    function Na__ImageViewerCount__OnKeyCapture(e) {
        if (!na_active) return;
        var tag = e.target && e.target.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        var target  = Na__ImageViewerCount__Target();
        var handled = true;
        if (/^[0-9]$/.test(e.key) && target)                     Na__ImageViewerCount__BeginTyping(e.key);
        else if (e.key === 'ArrowUp' && target)                   { na_notice = ''; Na__ImageViewerCount__Step(1); }
        else if (e.key === 'ArrowDown' && target)                 { na_notice = ''; Na__ImageViewerCount__Step(-1); }
        else if (e.key === 'Enter' && na_phase === 'divide')      Na__ImageViewerCount__Commit();
        else if ((e.key === 'Delete' || e.key === 'Backspace') && !na_phase && na_selectedId !== null) Na__ImageViewerCount__DeleteSelected();
        else if (e.key === 'Escape')                              Na__ImageViewerCount__Escape();
        else handled = false;
        if (!handled) return;
        e.preventDefault();
        e.stopPropagation();
    }

    function Na__ImageViewerCount__Escape() {
        if (na_drag) return;
        na_notice = '';
        if (na_phase) {
            Na__ImageViewerCount__CancelLive();
        } else if (na_selectedId !== null) {
            na_selectedId = null;
        } else {
            Na__ImageViewerCount__SetActive(false);
            return;
        }
        Na__ImageViewerCount__RefreshBar(true);
        na_core.requestDraw();
    }

    // C, for Count, toggles the tool.
    function Na__ImageViewerCount__OnKeyDown(e) {
        var tag = e.target && e.target.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
        if ((e.key === 'c' || e.key === 'C') && !e.ctrlKey && !e.metaKey && !e.altKey) {
            e.preventDefault();
            Na__ImageViewerCount__SetActive(!na_active);
        }
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Initialisation
    // -------------------------------------------------------------------------

    function Na__ImageViewerCount__Init() {
        na_canvas    = na_core.getCanvas();
        na_wrap      = na_canvas ? na_canvas.parentElement : null;
        na_btnTool   = Na__ImageViewerCount__El('naImageViewer_btnCount');
        na_bar       = Na__ImageViewerCount__El('naImageViewer_countBar');
        na_input     = Na__ImageViewerCount__El('naImageViewer_countInput');
        na_btnMinus  = Na__ImageViewerCount__El('naImageViewer_countMinus');
        na_btnPlus   = Na__ImageViewerCount__El('naImageViewer_countPlus');
        na_spacingEl = Na__ImageViewerCount__El('naImageViewer_countSpacing');
        na_dimsEl    = Na__ImageViewerCount__El('naImageViewer_countDims');
        na_btnReset  = Na__ImageViewerCount__El('naImageViewer_countReset');
        na_btnClear  = Na__ImageViewerCount__El('naImageViewer_countClear');
        na_hintEl    = Na__ImageViewerCount__El('naImageViewer_countHint');
        if (!na_canvas) return;

        na_core.registerOverlay(Na__ImageViewerCount__Render);
        na_core.registerHistory(NA_TOOL_NAME, {
            snapshot : Na__ImageViewerCount__Snapshot,
            restore  : Na__ImageViewerCount__Restore
        });
        na_core.onHistoryChanged(Na__ImageViewerCount__OnHistoryChanged);
        if (typeof na_core.registerSnap === 'function') na_core.registerSnap(Na__ImageViewerCount__ProvideSnap);
        na_core.onImageChanged(function() {
            Na__ImageViewerCount__CancelLive();
            na_press       = null;
            na_drag        = null;
            na_hover       = null;
            na_snapExclude = null;
            na_selectedId  = null;
            na_inputError  = '';
            na_notice      = '';
            Na__ImageViewerCount__RefreshBar(true);
        });

        if (na_wrap) na_wrap.addEventListener('mousedown', Na__ImageViewerCount__OnMouseDown, true);
        if (na_wrap) na_wrap.addEventListener('wheel', Na__ImageViewerCount__OnWheel, { capture: true, passive: false });
        window.addEventListener('mousemove', Na__ImageViewerCount__OnMouseMove);
        window.addEventListener('mouseup', Na__ImageViewerCount__OnMouseUp);
        window.addEventListener('keydown', Na__ImageViewerCount__OnKeyCapture, true);
        window.addEventListener('keydown', Na__ImageViewerCount__OnKeyDown);
        na_canvas.addEventListener('mouseleave', Na__ImageViewerCount__OnMouseLeave);
        na_canvas.addEventListener('contextmenu', function(e) { if (na_active) e.preventDefault(); });

        if (na_btnTool)  na_btnTool.addEventListener('click', function() { Na__ImageViewerCount__SetActive(!na_active); });
        if (na_btnMinus) na_btnMinus.addEventListener('click', function() { na_notice = ''; Na__ImageViewerCount__Step(-1); na_btnMinus.blur(); });
        if (na_btnPlus)  na_btnPlus.addEventListener('click', function() { na_notice = ''; Na__ImageViewerCount__Step(1); na_btnPlus.blur(); });
        if (na_btnReset) na_btnReset.addEventListener('click', function() { Na__ImageViewerCount__ResetSpacing(); na_btnReset.blur(); });
        if (na_btnClear) na_btnClear.addEventListener('click', function() { Na__ImageViewerCount__ClearAll(); na_btnClear.blur(); });
        if (na_input) {
            na_input.addEventListener('keydown', function(ev) {
                // Enter sets the count and hands the keys back to the photo.
                if (ev.key === 'Enter') {
                    ev.preventDefault();
                    if (Na__ImageViewerCount__OnInputCommit()) na_input.blur();
                } else if (ev.key === 'Escape') {
                    ev.preventDefault();
                    na_inputError = '';
                    na_input.blur();
                    Na__ImageViewerCount__RefreshBar(true);
                } else if (ev.key === 'ArrowUp' || ev.key === 'ArrowDown') {
                    ev.preventDefault();
                    na_inputError = '';
                    na_input.blur();
                    Na__ImageViewerCount__Step(ev.key === 'ArrowUp' ? 1 : -1);
                }
                ev.stopPropagation();
            });
            na_input.addEventListener('change', Na__ImageViewerCount__OnInputCommit);
            na_input.addEventListener('blur', function() {
                if (!na_inputError) Na__ImageViewerCount__RefreshBar(true);
            });
        }
        Na__ImageViewerCount__RefreshBar(true);
    }

    // Read-only view of the current photo's counts, for the browser tests.
    window.Na__ImageViewer__Count = {
        inspect: function() {
            var key  = Na__ImageViewerCount__Key();
            var dirs = Na__ImageViewerCount__Directions();
            var scale = Na__ImageViewerCount__Scale();
            function describe(item) {
                var sp  = Na__ImageViewerCount__Spacing(item, dirs);
                var len = Na__ImageViewerCount__Lengths(item, sp, scale);
                return {
                    dims    : len ? { overall: len.overall, part: len.part, unit: len.unit, read: len.read } : null,
                    id      : item.id,
                    n       : item.n,
                    a       : { x: item.a.x, y: item.a.y },
                    b       : { x: item.b.x, y: item.b.y },
                    spacing : sp.kind,
                    label   : sp.label,
                    k       : sp.k,
                    manual  : !!item.vp,
                    ticks   : Na__ImageViewerCount__Ticks(item, sp)
                };
            }
            return {
                active   : na_active,
                phase    : na_phase,
                selected : na_selectedId,
                live     : na_live ? describe(na_live) : null,
                counts   : (na_countsByKey[key] || []).map(describe),
                bar      : {
                    open    : !!(na_bar && na_bar.classList.contains('naImageViewer__CountBar--open')),
                    value   : na_input ? na_input.value : '',
                    spacing : na_spacingEl ? na_spacingEl.textContent : '',
                    dims    : na_dimsEl ? na_dimsEl.textContent : '',
                    hint    : na_hintEl ? na_hintEl.textContent : '',
                    error   : na_inputError
                }
            };
        }
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na__ImageViewerCount__Init);
    } else {
        Na__ImageViewerCount__Init();
    }

    // endregion ---------------------------------------------------------------

    // =============================================================================
    // END OF FILE
    // =============================================================================

})();
