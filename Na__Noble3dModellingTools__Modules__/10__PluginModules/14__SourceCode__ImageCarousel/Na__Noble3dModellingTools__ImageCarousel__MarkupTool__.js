// =============================================================================
// NA NOBLE3D MODELLING TOOLS - IMAGE VIEWER - MARKUP TOOL
//
// FILE       : Na__Noble3dModellingTools__ImageCarousel__MarkupTool__.js
// PURPOSE    : Mark up a photo with a pen, a highlighter in a choice of colours
//              and an eraser, from a floating toolbar over the photo. The marks
//              sit on the photo itself, so they pan, zoom and rotate with it,
//              and they are kept in the SketchUp model, one entry per photo, so
//              they are there again the next time the model is opened.
//
// DESIGN     : Self-contained feature file, like the Measurement overlay and the
//              Count tool. It talks to the viewer through
//              window.Na__ImageViewer__Core (drawing, shared undo history,
//              active-tool hand-off) and to Ruby through the SketchUp bridge:
//                markup_save(json)  -> Ruby checks and holds a photo's marks,
//                                      then writes them to the model dictionary
//                Na__ImageViewer__OnMarkupLoaded(map)  <- the model's marks for
//                                      the photos in the chosen folder
//                Na__ImageViewer__MarkupOnSaved(result) <- the write has landed
//              A stroke is { k:'pen'|'hl', c:'#rrggbb', w:image px, p:[x,y,...] }.
//              In memory the points are in the viewer's image space (origin at
//              the photo's centre). In the model they are in photo pixels (origin
//              at the top-left) with the photo's size beside them, so a stroke
//              lands on the same detail whatever the viewer is doing, and a copy
//              of the photo at another size (same shape) takes the marks scaled.
//              Strokes are never edited in place: the shared undo history keeps
//              plain copies of the list, and the eraser swaps strokes for new ones.
//
// INTERACTION: The Markup button opens the toolbar: pen (P), highlighter (H),
//              eraser (E). Drag on the photo to mark. Click the chosen tool again,
//              or the circles button, for its colours and sizes. The eraser takes
//              whole marks (Stroke) or rubs out part of one (Part). Right-drag pans
//              and the wheel zooms without leaving the tool; Ctrl+Z and Ctrl+Y
//              step through the marks with everything else; Esc closes the
//              options, then the tool. Marks stay on the photo under every other
//              tool.
// =============================================================================

(function() {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Guard - require the viewer Core API
    // -------------------------------------------------------------------------

    var na_core = window.Na__ImageViewer__Core;
    if (!na_core) { return; }
    if (typeof na_core.registerHistory !== 'function' || typeof na_core.claimTool !== 'function') { return; }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Constants
    // -------------------------------------------------------------------------

    var NA_TOOL_NAME    = 'markup';
    var NA_HL_ALPHA     = 0.42;     // a highlighter stroke is this opaque: the photo shows through
    var NA_MIN_STEP_PX  = 1.5;      // screen px the pointer travels before the next point is kept
    var NA_SIMPLIFY_PX  = 0.45;     // screen px a finished stroke may stray from the pointer's path
    var NA_ERASE_STEP   = 0.5;      // the eraser samples the pointer's path every half radius
    var NA_MAX_POINTS   = 20000;    // points in one stroke
    var NA_MAX_STROKES  = 5000;     // strokes on one photo
    var NA_ASPECT_TOL   = 0.01;     // how far a photo's shape may differ from the one marked
    var NA_TOAST_MS     = 2400;
    var NA_PRECISION    = 100;      // marks are kept to 0.01 of a photo pixel

    var NA_TOOLS = {
        pen: {
            label   : 'Pen',
            colours : [
                { c: '#1b1f24', n: 'Black'  },
                { c: '#e23b2e', n: 'Red'    },
                { c: '#f28c28', n: 'Orange' },
                { c: '#1f9d55', n: 'Green'  },
                { c: '#2f77d5', n: 'Blue'   },
                { c: '#ffffff', n: 'White'  }
            ],
            sizes   : [ { s: 2, n: 'Fine' }, { s: 4, n: 'Medium' }, { s: 8, n: 'Thick' } ]
        },
        hl: {
            label   : 'Highlighter',
            colours : [
                { c: '#ffe600', n: 'Yellow' },
                { c: '#7cf03d', n: 'Green'  },
                { c: '#ff6fb5', n: 'Pink'   },
                { c: '#37c9ff', n: 'Blue'   },
                { c: '#ff9d2e', n: 'Orange' },
                { c: '#b57cff', n: 'Purple' }
            ],
            sizes   : [ { s: 14, n: 'Narrow' }, { s: 24, n: 'Medium' }, { s: 40, n: 'Wide' } ]
        },
        eraser: {
            label   : 'Eraser',
            sizes   : [ { s: 8, n: 'Small' }, { s: 14, n: 'Medium' }, { s: 24, n: 'Large' } ]
        }
    };

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Feature State
    // -------------------------------------------------------------------------

    var na_active      = false;
    var na_tool        = 'hl';                                       // the picture's toolbar opens on the highlighter
    var na_pen         = { colour: '#1b1f24', size: 4 };             // size: screen px at the time of marking
    var na_hl          = { colour: '#ffe600', size: 24 };
    var na_eraser      = { mode: 'stroke', size: 14 };               // size: the eraser's radius, screen px

    var na_marksByKey    = {};    // image key -> [ stroke ], image space (origin at the photo's centre)
    var na_sizeByKey     = {};    // image key -> { w, h }: the photo's pixel size
    var na_storedByKey   = {};    // image key -> the model's entry, until the photo is shown and it becomes strokes
    var na_mismatchByKey = {};    // image key -> { w, h } of marks in the model that do not fit this photo
    var na_sentByKey     = {};    // image key -> the text last sent to (or read back from) the model

    var na_live        = null;    // the stroke being drawn
    var na_erase       = null;    // { last, pushed, changed } while the eraser is down
    var na_press       = null;    // a right or middle press that pans
    var na_cursor      = null;    // pointer in canvas px while over the photo
    var na_drawQueued  = false;
    var na_flyoutOpen  = false;
    var na_barDrag     = null;    // { dx, dy } while the toolbar is dragged by its grip
    var na_barMoved    = false;
    var na_toastTimer  = null;
    var na_lastSave    = null;    // the last answer Ruby sent for a write

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | DOM Handles
    // -------------------------------------------------------------------------

    var na_canvas     = null;
    var na_wrap       = null;
    var na_btnTool    = null;
    var na_bar        = null;
    var na_pill       = null;
    var na_grip       = null;
    var na_btnOptions = null;
    var na_btnDone    = null;
    var na_flyout     = null;
    var na_toast      = null;
    var na_toolBtns   = {};

    function Na__ImageViewerMarkup__El(id) {
        return document.getElementById(id);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Small Helpers
    // -------------------------------------------------------------------------

    function Na__ImageViewerMarkup__Key() {
        return na_core.getImageKey();
    }

    function Na__ImageViewerMarkup__Round(v) {
        return Math.round(v * NA_PRECISION) / NA_PRECISION;
    }

    function Na__ImageViewerMarkup__Esc(text) {
        return String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    // The pen or highlighter settings, whichever tool is chosen.
    function Na__ImageViewerMarkup__Ink() {
        return na_tool === 'pen' ? na_pen : na_hl;
    }

    function Na__ImageViewerMarkup__List(key) {
        if (!na_marksByKey[key]) na_marksByKey[key] = [];
        return na_marksByKey[key];
    }

    function Na__ImageViewerMarkup__HasMarks(key) {
        if (!key) return false;
        var list = na_marksByKey[key];
        if (list) return list.length > 0;
        var stored = na_storedByKey[key];
        return !!(stored && stored.strokes && stored.strokes.length && !na_mismatchByKey[key]);
    }

    // The pointer in canvas pixels, as the other tools take it.
    function Na__ImageViewerMarkup__CanvasPoint(e) {
        var rect  = na_canvas.getBoundingClientRect();
        var ratio = na_core.getRatio();
        return { x: (e.clientX - rect.left) * ratio, y: (e.clientY - rect.top) * ratio };
    }

    // The pointer on the photo, in image space. inside says whether it is over the
    // photo itself; clamp holds a point that is not inside to the photo's edge.
    function Na__ImageViewerMarkup__ImagePoint(e, clamp) {
        var p    = Na__ImageViewerMarkup__CanvasPoint(e);
        var img  = na_core.screenToImg(p.x, p.y);
        var size = na_core.getImageSize();
        var hw   = size.w / 2, hh = size.h / 2;
        var inside = Math.abs(img.x) <= hw && Math.abs(img.y) <= hh;
        if (clamp) {
            img.x = Math.max(-hw, Math.min(hw, img.x));
            img.y = Math.max(-hh, Math.min(hh, img.y));
        }
        return { x: img.x, y: img.y, inside: inside };
    }

    // Screen px to photo px at the current zoom: marks keep the size they were
    // made at on the screen, and scale with the photo from then on.
    function Na__ImageViewerMarkup__ToImagePx(screenPx) {
        return screenPx * na_core.getRatio() / na_core.getZoom();
    }

    function Na__ImageViewerMarkup__ScheduleDraw() {
        if (na_drawQueued) return;
        na_drawQueued = true;
        window.requestAnimationFrame(function() {
            na_drawQueued = false;
            na_core.requestDraw();
        });
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Per-Image State And History
    // -------------------------------------------------------------------------
    // The undo history lives in the viewer Core and is shared with the other
    // tools. A snapshot is a copy of the stroke list: strokes are never edited
    // in place, so the strokes themselves can be shared between snapshots.

    function Na__ImageViewerMarkup__Snapshot(key) {
        return (na_marksByKey[key] || []).slice();
    }

    function Na__ImageViewerMarkup__Restore(key, snap) {
        if (snap) na_marksByKey[key] = snap.slice();
        else      delete na_marksByKey[key];
    }

    function Na__ImageViewerMarkup__OnHistoryChanged(reason) {
        if (reason !== 'undo' && reason !== 'redo') return;
        na_live  = null;
        na_erase = null;
        Na__ImageViewerMarkup__Changed(Na__ImageViewerMarkup__Key());
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Saving To The Model And Reading It Back
    // -------------------------------------------------------------------------

    // One photo's marks as they are kept in the model: photo pixels, origin at the
    // photo's top-left, to 0.01 px, beside the photo's size.
    function Na__ImageViewerMarkup__Serialise(key) {
        var size = na_sizeByKey[key];
        if (!key || !size) return null;
        var halfW = size.w / 2, halfH = size.h / 2;
        var list  = na_marksByKey[key] || [];
        return {
            path    : key,
            w       : size.w,
            h       : size.h,
            strokes : list.map(function(s) {
                var p = new Array(s.p.length);
                for (var i = 0; i < s.p.length; i += 2) {
                    p[i]     = Na__ImageViewerMarkup__Round(s.p[i] + halfW);
                    p[i + 1] = Na__ImageViewerMarkup__Round(s.p[i + 1] + halfH);
                }
                return { k: s.k, c: s.c, w: Math.max(0.01, Na__ImageViewerMarkup__Round(s.w)), p: p };
            })
        };
    }

    // Hand a photo's marks to Ruby, unless the model already has exactly these.
    function Na__ImageViewerMarkup__Send(key) {
        var entry = Na__ImageViewerMarkup__Serialise(key);
        if (!entry) return;
        var text = JSON.stringify(entry);
        if (na_sentByKey[key] === text) return;
        na_sentByKey[key] = text;
        if (window.sketchup && typeof window.sketchup.markup_save === 'function') {
            window.sketchup.markup_save(text);
        }
    }

    // The marks of a photo changed: save them, and bring the buttons up to date.
    function Na__ImageViewerMarkup__Changed(key) {
        if (key) Na__ImageViewerMarkup__Send(key);
        Na__ImageViewerMarkup__SyncMarkers();
        Na__ImageViewerMarkup__RefreshBar();
        na_core.requestDraw();
    }

    // Turn the model's entry for a photo into strokes, now the photo's own size is
    // known. The same size takes the marks as they are; another size of the same
    // shape takes them scaled; any other shape is left alone, in the model.
    function Na__ImageViewerMarkup__Materialise(key) {
        var entry = na_storedByKey[key];
        var size  = na_core.getImageSize();
        if (!key || !entry || na_marksByKey[key] || !size || !size.w || !size.h) return;

        var sw = Number(entry.w), sh = Number(entry.h);
        if (!(sw > 0) || !(sh > 0)) { delete na_storedByKey[key]; return; }

        var scale;
        if (sw === size.w && sh === size.h) {
            scale = 1;
        } else if (Math.abs(sw / sh - size.w / size.h) <= NA_ASPECT_TOL * (sw / sh)) {
            scale = size.w / sw;
        } else {
            na_mismatchByKey[key] = { w: sw, h: sh };
            return;
        }

        delete na_mismatchByKey[key];
        delete na_storedByKey[key];
        na_sizeByKey[key] = { w: size.w, h: size.h };
        var halfW = size.w / 2, halfH = size.h / 2;
        var strokes = [];
        (entry.strokes || []).forEach(function(raw) {
            if (!raw || (raw.k !== 'pen' && raw.k !== 'hl') || !Array.isArray(raw.p) || raw.p.length < 2 || raw.p.length % 2) return;
            var p = new Array(raw.p.length);
            for (var i = 0; i < raw.p.length; i++) {
                var v = Number(raw.p[i]);
                if (!isFinite(v)) return;
                p[i] = v * scale - (i % 2 ? halfH : halfW);
            }
            strokes.push({ k: raw.k, c: String(raw.c || '#e23b2e'), w: Math.max(0.01, Number(raw.w) * scale) || 1, p: p });
        });
        na_marksByKey[key] = strokes;
        na_sentByKey[key]  = JSON.stringify(Na__ImageViewerMarkup__Serialise(key));
    }

    // Ruby's answer to a folder choice: the model's marks for the photos in it.
    function Na__ImageViewerMarkup__OnLoaded(map) {
        if (!map || typeof map !== 'object') return;
        Object.keys(map).forEach(function(path) {
            var entry = map[path];
            if (!entry || !Array.isArray(entry.strokes)) return;
            if (na_marksByKey[path]) return;            // this session's marks are newer than the model's
            na_storedByKey[path] = entry;
            delete na_mismatchByKey[path];
        });
        Na__ImageViewerMarkup__Materialise(Na__ImageViewerMarkup__Key());
        Na__ImageViewerMarkup__SyncMarkers();
        Na__ImageViewerMarkup__RefreshBar();
        na_core.requestDraw();
    }

    // Ruby's answer to a write.
    function Na__ImageViewerMarkup__OnSaved(result) {
        na_lastSave = result || null;
        if (!result) return;
        if (result.ok) {
            var wrote = (result.saved || []).some(function(item) { return item && item.written; });
            if (wrote) Na__ImageViewerMarkup__Toast('Markup saved in the model');
        } else {
            if (result.path) delete na_sentByKey[result.path];
            Na__ImageViewerMarkup__Toast('Markup not saved: ' + (result.error || 'unknown error'), true);
        }
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Stroke Geometry
    // -------------------------------------------------------------------------

    // Douglas-Peucker on a flat [x, y, ...] list: a finished stroke keeps the
    // points that carry its shape, and no more.
    function Na__ImageViewerMarkup__Simplify(p, eps) {
        var n = p.length / 2;
        if (n <= 2 || !(eps > 0)) return p;
        var keep = new Uint8Array(n);
        keep[0] = 1; keep[n - 1] = 1;
        var stack = [0, n - 1];
        var e2 = eps * eps;
        while (stack.length) {
            var last = stack.pop(), first = stack.pop();
            var ax = p[2 * first], ay = p[2 * first + 1], bx = p[2 * last], by = p[2 * last + 1];
            var dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy;
            var far = -1, farIndex = -1;
            for (var i = first + 1; i < last; i++) {
                var px = p[2 * i], py = p[2 * i + 1], d2;
                if (len2 === 0) {
                    d2 = (px - ax) * (px - ax) + (py - ay) * (py - ay);
                } else {
                    var t = ((px - ax) * dx + (py - ay) * dy) / len2;
                    t = Math.max(0, Math.min(1, t));
                    var qx = ax + t * dx - px, qy = ay + t * dy - py;
                    d2 = qx * qx + qy * qy;
                }
                if (d2 > far) { far = d2; farIndex = i; }
            }
            if (far > e2) {
                keep[farIndex] = 1;
                stack.push(first, farIndex, farIndex, last);
            }
        }
        var out = [];
        for (var k = 0; k < n; k++) if (keep[k]) out.push(p[2 * k], p[2 * k + 1]);
        return out;
    }

    function Na__ImageViewerMarkup__DistSqToSeg(px, py, ax, ay, bx, by) {
        var dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy;
        var t = len2 > 0 ? ((px - ax) * dx + (py - ay) * dy) / len2 : 0;
        t = Math.max(0, Math.min(1, t));
        var ex = px - (ax + t * dx), ey = py - (ay + t * dy);
        return ex * ex + ey * ey;
    }

    // A stroke's box, with its pen's reach, kept on the stroke (it never changes).
    function Na__ImageViewerMarkup__Bounds(s) {
        if (s.bb) return s.bb;
        var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (var i = 0; i < s.p.length; i += 2) {
            if (s.p[i] < x0) x0 = s.p[i];
            if (s.p[i] > x1) x1 = s.p[i];
            if (s.p[i + 1] < y0) y0 = s.p[i + 1];
            if (s.p[i + 1] > y1) y1 = s.p[i + 1];
        }
        var pad = s.w / 2;
        s.bb = { x0: x0 - pad, y0: y0 - pad, x1: x1 + pad, y1: y1 + pad };
        return s.bb;
    }

    function Na__ImageViewerMarkup__NearBounds(s, c, r) {
        var bb = Na__ImageViewerMarkup__Bounds(s);
        return !(c.x < bb.x0 - r || c.x > bb.x1 + r || c.y < bb.y0 - r || c.y > bb.y1 + r);
    }

    // Does the eraser disc (centre c, radius r, photo px) touch the stroke's ink?
    function Na__ImageViewerMarkup__StrokeHit(s, c, r) {
        if (!Na__ImageViewerMarkup__NearBounds(s, c, r)) return false;
        var reach = s.w / 2 + r, reach2 = reach * reach, p = s.p, n = p.length;
        if (n === 2) {
            var dx = p[0] - c.x, dy = p[1] - c.y;
            return dx * dx + dy * dy <= reach2;
        }
        for (var i = 0; i < n - 2; i += 2) {
            if (Na__ImageViewerMarkup__DistSqToSeg(c.x, c.y, p[i], p[i + 1], p[i + 2], p[i + 3]) <= reach2) return true;
        }
        return false;
    }

    // The stroke with the eraser disc taken out of its ink: null when the disc
    // misses it, else the pieces left (none when it took the lot). The cut is at
    // the disc's radius plus the pen's own, so the round end of each piece stops
    // at the disc's edge.
    function Na__ImageViewerMarkup__ClipByDisc(s, c, r) {
        if (!Na__ImageViewerMarkup__NearBounds(s, c, r)) return null;
        var R = s.w / 2 + r, R2 = R * R, p = s.p, n = p.length;
        if (n === 2) {
            var qx = p[0] - c.x, qy = p[1] - c.y;
            return qx * qx + qy * qy <= R2 ? [] : null;
        }
        var runs = [], cur = null, touched = false;
        for (var i = 0; i < n - 2; i += 2) {
            var ax = p[i], ay = p[i + 1], bx = p[i + 2], by = p[i + 3];
            var dx = bx - ax, dy = by - ay;
            var fx = ax - c.x, fy = ay - c.y;
            var A = dx * dx + dy * dy, B = 2 * (fx * dx + fy * dy), C = fx * fx + fy * fy - R2;
            var t0 = 1, t1 = 0;                      // t0 >= t1: the segment misses the disc
            if (A > 0) {
                var disc = B * B - 4 * A * C;
                if (disc > 0) {
                    var root = Math.sqrt(disc);
                    t0 = Math.max(0, (-B - root) / (2 * A));
                    t1 = Math.min(1, (-B + root) / (2 * A));
                }
            } else if (C <= 0) {
                t0 = 0; t1 = 1;
            }
            if (t0 >= t1) {
                if (!cur) cur = [ax, ay];
                cur.push(bx, by);
                continue;
            }
            touched = true;
            if (t0 > 0) {
                if (!cur) cur = [ax, ay];
                cur.push(ax + dx * t0, ay + dy * t0);
            }
            if (cur) { runs.push(cur); cur = null; }
            if (t1 < 1) cur = [ax + dx * t1, ay + dy * t1, bx, by];
        }
        if (cur) runs.push(cur);
        if (!touched) return null;
        return runs.map(function(pts) { return { k: s.k, c: s.c, w: s.w, p: pts }; });
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Overlay Rendering
    // -------------------------------------------------------------------------

    // The viewer's image-to-canvas transform as the six numbers of a canvas
    // transform, read off the Core so the viewer's maths stays single-sourced.
    function Na__ImageViewerMarkup__ViewMatrix() {
        var o  = na_core.imgToScreen({ x: 0, y: 0 });
        var ex = na_core.imgToScreen({ x: 1, y: 0 });
        var ey = na_core.imgToScreen({ x: 0, y: 1 });
        return { a: ex.x - o.x, b: ex.y - o.y, c: ey.x - o.x, d: ey.y - o.y, e: o.x, f: o.y };
    }

    // One stroke, in image space (the canvas is already in the photo's frame).
    // The whole stroke is one path, so where it crosses itself the highlighter
    // does not double up. A single point is a dot.
    function Na__ImageViewerMarkup__DrawStroke(ctx, s) {
        var p = s.p, n = p.length;
        if (n < 2) return;
        ctx.save();
        ctx.globalAlpha = s.k === 'hl' ? NA_HL_ALPHA : 1;
        if (n === 2 || (n === 4 && p[0] === p[2] && p[1] === p[3])) {
            ctx.beginPath();
            ctx.arc(p[0], p[1], s.w / 2, 0, Math.PI * 2);
            ctx.fillStyle = s.c;
            ctx.fill();
        } else {
            ctx.beginPath();
            ctx.moveTo(p[0], p[1]);
            if (n === 4) {
                ctx.lineTo(p[2], p[3]);
            } else {
                for (var i = 2; i < n - 2; i += 2) {
                    ctx.quadraticCurveTo(p[i], p[i + 1], (p[i] + p[i + 2]) / 2, (p[i + 1] + p[i + 3]) / 2);
                }
                ctx.lineTo(p[n - 2], p[n - 1]);
            }
            ctx.lineWidth   = s.w;
            ctx.strokeStyle = s.c;
            ctx.stroke();
        }
        ctx.restore();
    }

    function Na__ImageViewerMarkup__Render(ctx) {
        if (!ctx) return;
        var key = Na__ImageViewerMarkup__Key();
        if (!key) return;

        var list = na_marksByKey[key] || [];
        if (list.length || na_live) {
            var m = Na__ImageViewerMarkup__ViewMatrix();
            ctx.save();
            ctx.transform(m.a, m.b, m.c, m.d, m.e, m.f);
            ctx.lineCap  = 'round';
            ctx.lineJoin = 'round';
            for (var i = 0; i < list.length; i++) Na__ImageViewerMarkup__DrawStroke(ctx, list[i]);
            if (na_live) Na__ImageViewerMarkup__DrawStroke(ctx, na_live);
            ctx.restore();
        }
        if (na_active && na_cursor && !na_press) Na__ImageViewerMarkup__DrawBrush(ctx);
    }

    // A ring at the pointer the size of the mark it would make (the eraser's disc).
    function Na__ImageViewerMarkup__DrawBrush(ctx) {
        var ratio  = na_core.getRatio();
        var eraser = na_tool === 'eraser';
        var radius = Math.max(2 * ratio, (eraser ? na_eraser.size : Na__ImageViewerMarkup__Ink().size / 2) * ratio);
        ctx.save();
        if (!eraser) {
            ctx.globalAlpha = 0.35;
            ctx.fillStyle   = Na__ImageViewerMarkup__Ink().colour;
            ctx.beginPath();
            ctx.arc(na_cursor.x, na_cursor.y, radius, 0, Math.PI * 2);
            ctx.fill();
            ctx.globalAlpha = 1;
        }
        [['rgba(255, 255, 255, 0.92)', 3], ['#1b1f24', 1.2]].forEach(function(pen) {
            ctx.beginPath();
            ctx.arc(na_cursor.x, na_cursor.y, radius, 0, Math.PI * 2);
            ctx.strokeStyle = pen[0];
            ctx.lineWidth   = pen[1] * ratio;
            ctx.stroke();
        });
        ctx.restore();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Marking
    // -------------------------------------------------------------------------

    function Na__ImageViewerMarkup__BeginStroke(img) {
        var ink = Na__ImageViewerMarkup__Ink();
        var key = Na__ImageViewerMarkup__Key();
        var size = na_core.getImageSize();
        na_sizeByKey[key] = { w: size.w, h: size.h };
        na_live = { k: na_tool, c: ink.colour, w: Na__ImageViewerMarkup__ToImagePx(ink.size), p: [img.x, img.y] };
    }

    // Keep the point when the pointer has moved far enough from the last kept one.
    function Na__ImageViewerMarkup__ExtendStroke(img) {
        if (!na_live || na_live.p.length / 2 >= NA_MAX_POINTS) return false;
        var p = na_live.p, n = p.length;
        var step = Na__ImageViewerMarkup__ToImagePx(NA_MIN_STEP_PX);
        var dx = img.x - p[n - 2], dy = img.y - p[n - 1];
        if (dx * dx + dy * dy < step * step) return false;
        p.push(img.x, img.y);
        return true;
    }

    function Na__ImageViewerMarkup__FinishStroke(img) {
        var s = na_live;
        na_live = null;
        if (!s) return;
        var key = Na__ImageViewerMarkup__Key();

        if (img && s.p.length / 2 < NA_MAX_POINTS) {
            var n = s.p.length;
            if (s.p[n - 2] !== img.x || s.p[n - 1] !== img.y) s.p.push(img.x, img.y);
        }
        s.p = Na__ImageViewerMarkup__Simplify(s.p, Na__ImageViewerMarkup__ToImagePx(NA_SIMPLIFY_PX));

        var list = Na__ImageViewerMarkup__List(key);
        if (list.length >= NA_MAX_STROKES) {
            Na__ImageViewerMarkup__Toast('This photo already has all the markup it can hold.', true);
            na_core.requestDraw();
            return;
        }
        na_core.pushHistory();
        list.push(s);
        Na__ImageViewerMarkup__Changed(key);
    }

    function Na__ImageViewerMarkup__CancelStroke() {
        na_live = null;
        na_core.requestDraw();
    }

    // The first change in an eraser drag takes the undo snapshot, so a drag that
    // touches nothing leaves nothing to undo.
    function Na__ImageViewerMarkup__BeginErase() {
        if (!na_erase || na_erase.pushed) return;
        na_core.pushHistory();
        na_erase.pushed = true;
    }

    // Take the eraser's disc at one point of the photo out of the marks.
    function Na__ImageViewerMarkup__EraseAt(img) {
        var list = na_marksByKey[Na__ImageViewerMarkup__Key()];
        if (!list || !list.length) return false;
        var r = Na__ImageViewerMarkup__ToImagePx(na_eraser.size);
        var changed = false;
        for (var i = list.length - 1; i >= 0; i--) {
            if (na_eraser.mode === 'part') {
                var pieces = Na__ImageViewerMarkup__ClipByDisc(list[i], img, r);
                if (!pieces) continue;
                Na__ImageViewerMarkup__BeginErase();
                list.splice.apply(list, [i, 1].concat(pieces));
                changed = true;
            } else if (Na__ImageViewerMarkup__StrokeHit(list[i], img, r)) {
                Na__ImageViewerMarkup__BeginErase();
                list.splice(i, 1);
                changed = true;
            }
        }
        if (changed && na_erase) na_erase.changed = true;
        return changed;
    }

    // The eraser's path between two pointer positions, sampled so a fast drag
    // cannot jump over a mark.
    function Na__ImageViewerMarkup__EraseAlong(from, to) {
        var r  = Na__ImageViewerMarkup__ToImagePx(na_eraser.size);
        var dx = to.x - from.x, dy = to.y - from.y;
        var steps = Math.max(1, Math.ceil(Math.sqrt(dx * dx + dy * dy) / (r * NA_ERASE_STEP)));
        for (var k = 1; k <= steps; k++) {
            Na__ImageViewerMarkup__EraseAt({ x: from.x + dx * k / steps, y: from.y + dy * k / steps });
        }
    }

    function Na__ImageViewerMarkup__FinishErase() {
        var erase = na_erase;
        na_erase = null;
        if (erase && erase.changed) Na__ImageViewerMarkup__Changed(Na__ImageViewerMarkup__Key());
        else                        na_core.requestDraw();
    }

    function Na__ImageViewerMarkup__ClearAll() {
        var key  = Na__ImageViewerMarkup__Key();
        var list = key ? na_marksByKey[key] : null;
        if (!list || !list.length) return;
        na_core.pushHistory();
        na_marksByKey[key] = [];
        Na__ImageViewerMarkup__Changed(key);
        Na__ImageViewerMarkup__Toast('Markup cleared from this photo');
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Tool State
    // -------------------------------------------------------------------------

    // Stop marking: let go of anything half done. The marks stay.
    function Na__ImageViewerMarkup__Reset() {
        na_active      = false;
        na_live        = null;
        na_erase       = null;
        na_press       = null;
        na_cursor      = null;
        na_flyoutOpen  = false;
        na_barDrag     = null;
        Na__ImageViewerMarkup__HideToast();
    }

    // Another tool took the canvas.
    function Na__ImageViewerMarkup__Release() {
        Na__ImageViewerMarkup__Reset();
        Na__ImageViewerMarkup__UpdateCursor();
        Na__ImageViewerMarkup__RefreshBar();
        na_core.requestDraw();
    }

    function Na__ImageViewerMarkup__SetActive(on) {
        if (on) {
            na_active = true;
            na_core.claimTool(NA_TOOL_NAME, Na__ImageViewerMarkup__Release);
            if (!Na__ImageViewerMarkup__Key()) Na__ImageViewerMarkup__Toast('Choose a folder of photos first.');
        } else {
            Na__ImageViewerMarkup__Reset();
            na_core.releaseTool(NA_TOOL_NAME);
        }
        Na__ImageViewerMarkup__UpdateCursor();
        Na__ImageViewerMarkup__RefreshBar();
        Na__ImageViewerMarkup__ClampBar();
        na_core.requestDraw();
    }

    function Na__ImageViewerMarkup__SetTool(tool) {
        if (!NA_TOOLS[tool]) return;
        na_tool       = tool;
        na_flyoutOpen = false;
        na_live       = null;
        na_erase      = null;
        Na__ImageViewerMarkup__RefreshBar();
        na_core.requestDraw();
    }

    function Na__ImageViewerMarkup__UpdateCursor() {
        if (!na_canvas) return;
        var cursor = '';
        if (na_active) cursor = na_press ? 'grabbing' : 'crosshair';
        if (na_canvas.style.cursor !== cursor) na_canvas.style.cursor = cursor;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Toolbar And Options
    // -------------------------------------------------------------------------

    function Na__ImageViewerMarkup__RefreshBar() {
        if (na_btnTool) {
            na_btnTool.classList.toggle('naImageViewer__Btn--active', na_active);
            na_btnTool.classList.toggle('naImageViewer__Btn--hasMarkup', Na__ImageViewerMarkup__HasMarks(Na__ImageViewerMarkup__Key()));
        }
        if (!na_bar) return;
        na_bar.classList.toggle('naImageViewer__MarkupBar--open', na_active);
        if (!na_active) return;

        na_bar.style.setProperty('--naMarkup-pen', na_pen.colour);
        na_bar.style.setProperty('--naMarkup-hl', na_hl.colour);
        Object.keys(na_toolBtns).forEach(function(tool) {
            var on = tool === na_tool;
            na_toolBtns[tool].classList.toggle('naImageViewer__MarkupTool--active', on);
            na_toolBtns[tool].setAttribute('aria-pressed', on ? 'true' : 'false');
        });
        if (na_btnOptions) {
            na_btnOptions.classList.toggle('naImageViewer__MarkupTool--open', na_flyoutOpen);
            na_btnOptions.setAttribute('aria-expanded', na_flyoutOpen ? 'true' : 'false');
        }
        if (na_flyout) {
            na_flyout.classList.toggle('naImageViewer__MarkupFlyout--open', na_flyoutOpen);
            if (na_flyoutOpen) Na__ImageViewerMarkup__BuildFlyout();
        }
    }

    // The options for the chosen tool: its colours and sizes, and for the eraser
    // what it takes and a way to clear the photo.
    function Na__ImageViewerMarkup__BuildFlyout() {
        var def  = NA_TOOLS[na_tool];
        var html = '<div class="naImageViewer__MarkupFlyTitle">' + def.label + '</div>';
        var cur  = na_tool === 'eraser' ? na_eraser : Na__ImageViewerMarkup__Ink();

        if (def.colours) {
            html += '<div class="naImageViewer__MarkupRow" role="group" aria-label="Colour">';
            def.colours.forEach(function(colour) {
                var on = colour.c === cur.colour;
                html += '<button type="button" class="naImageViewer__MarkupSwatch' + (on ? ' naImageViewer__MarkupSwatch--on' : '') + '"'
                      + ' data-act="colour" data-value="' + colour.c + '" style="--swatch:' + colour.c + '"'
                      + ' title="' + colour.n + '" aria-label="' + colour.n + '" aria-pressed="' + (on ? 'true' : 'false') + '"></button>';
            });
            html += '</div>';
        } else {
            html += '<div class="naImageViewer__MarkupSegmented" role="group" aria-label="What the eraser takes">';
            [['stroke', 'Stroke', 'Takes a whole mark at a touch'], ['part', 'Part', 'Rubs out only the part you pass over']].forEach(function(mode) {
                var on = na_eraser.mode === mode[0];
                html += '<button type="button" class="naImageViewer__MarkupSeg' + (on ? ' naImageViewer__MarkupSeg--on' : '') + '"'
                      + ' data-act="mode" data-value="' + mode[0] + '" title="' + mode[2] + '" aria-pressed="' + (on ? 'true' : 'false') + '">' + mode[1] + '</button>';
            });
            html += '</div>';
        }

        html += '<div class="naImageViewer__MarkupRow" role="group" aria-label="Size">';
        def.sizes.forEach(function(size) {
            var on  = size.s === cur.size;
            var dot = na_tool === 'eraser' ? Math.min(20, size.s * 0.9 + 2) : (na_tool === 'pen' ? size.s + 3 : Math.min(20, size.s * 0.5 + 4));
            html += '<button type="button" class="naImageViewer__MarkupSize' + (on ? ' naImageViewer__MarkupSize--on' : '') + '"'
                  + ' data-act="size" data-value="' + size.s + '" title="' + size.n + '" aria-label="' + size.n + '" aria-pressed="' + (on ? 'true' : 'false') + '">'
                  + '<span class="naImageViewer__MarkupDot" style="width:' + dot + 'px;height:' + dot + 'px"></span></button>';
        });
        html += '</div>';

        if (na_tool === 'eraser') {
            var has = Na__ImageViewerMarkup__HasMarks(Na__ImageViewerMarkup__Key());
            html += '<button type="button" class="naImageViewer__MarkupLink" data-act="clear"' + (has ? '' : ' disabled') + '>Clear all markup on this photo</button>';
        }
        na_flyout.innerHTML = html;
    }

    function Na__ImageViewerMarkup__OnFlyoutClick(e) {
        var btn = e.target && e.target.closest ? e.target.closest('[data-act]') : null;
        if (!btn || btn.disabled) return;
        var act = btn.getAttribute('data-act'), value = btn.getAttribute('data-value');
        if (act === 'colour' && na_tool !== 'eraser') {
            Na__ImageViewerMarkup__Ink().colour = value;
        } else if (act === 'size') {
            (na_tool === 'eraser' ? na_eraser : Na__ImageViewerMarkup__Ink()).size = Number(value);
        } else if (act === 'mode') {
            na_eraser.mode = value === 'part' ? 'part' : 'stroke';
        } else if (act === 'clear') {
            Na__ImageViewerMarkup__ClearAll();
        }
        Na__ImageViewerMarkup__RefreshBar();
        na_core.requestDraw();
    }

    function Na__ImageViewerMarkup__ToggleFlyout() {
        na_flyoutOpen = !na_flyoutOpen;
        Na__ImageViewerMarkup__RefreshBar();
    }

    function Na__ImageViewerMarkup__CloseFlyout() {
        if (!na_flyoutOpen) return;
        na_flyoutOpen = false;
        Na__ImageViewerMarkup__RefreshBar();
    }

    // A tool's button: the first press chooses it, the next one opens its options.
    function Na__ImageViewerMarkup__OnToolClick(tool) {
        if (tool === na_tool) Na__ImageViewerMarkup__ToggleFlyout();
        else                  Na__ImageViewerMarkup__SetTool(tool);
    }

    // Keep the toolbar's own state on the photo's thumbnail and the Markup button:
    // a dot on every photo that has marks.
    function Na__ImageViewerMarkup__SyncMarkers() {
        var thumbs = document.querySelectorAll('.naImageViewer__Thumb');
        var images = typeof na_core.getImages === 'function' ? na_core.getImages() : [];
        for (var i = 0; i < thumbs.length; i++) {
            thumbs[i].classList.toggle('naImageViewer__Thumb--marked', !!images[i] && Na__ImageViewerMarkup__HasMarks(images[i]));
        }
        if (na_btnTool) na_btnTool.classList.toggle('naImageViewer__Btn--hasMarkup', Na__ImageViewerMarkup__HasMarks(Na__ImageViewerMarkup__Key()));
    }

    // A quiet line under the toolbar: saved, not saved, nothing to mark yet.
    function Na__ImageViewerMarkup__Toast(text, isError) {
        if (!na_toast) return;
        na_toast.textContent = text;
        na_toast.classList.toggle('naImageViewer__MarkupToast--error', !!isError);
        na_toast.classList.add('naImageViewer__MarkupToast--visible');
        if (na_toastTimer) window.clearTimeout(na_toastTimer);
        na_toastTimer = window.setTimeout(Na__ImageViewerMarkup__HideToast, NA_TOAST_MS);
    }

    function Na__ImageViewerMarkup__HideToast() {
        if (na_toastTimer) { window.clearTimeout(na_toastTimer); na_toastTimer = null; }
        if (na_toast) na_toast.classList.remove('naImageViewer__MarkupToast--visible');
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Moving The Toolbar
    // -------------------------------------------------------------------------

    function Na__ImageViewerMarkup__PlaceBar(left, top) {
        var wrap = na_wrap.getBoundingClientRect();
        var pill = na_pill.getBoundingClientRect();
        var bar  = na_bar.getBoundingClientRect();
        left = Math.max(4, Math.min(wrap.width - bar.width - 4, left));
        top  = Math.max(4, Math.min(wrap.height - pill.height - 4, top));
        na_bar.style.left      = left + 'px';
        na_bar.style.top       = top + 'px';
        na_bar.style.transform = 'none';
        na_barMoved = true;
    }

    function Na__ImageViewerMarkup__OnGripDown(e) {
        if (e.button !== 0 || !na_bar || !na_wrap) return;
        e.preventDefault();
        e.stopPropagation();
        Na__ImageViewerMarkup__CloseFlyout();
        var bar = na_bar.getBoundingClientRect();
        na_barDrag = { dx: e.clientX - bar.left, dy: e.clientY - bar.top };
    }

    function Na__ImageViewerMarkup__OnBarDrag(e) {
        if (!na_barDrag) return;
        var wrap = na_wrap.getBoundingClientRect();
        Na__ImageViewerMarkup__PlaceBar(e.clientX - wrap.left - na_barDrag.dx, e.clientY - wrap.top - na_barDrag.dy);
    }

    // A moved toolbar stays inside the photo's pane when the window is resized.
    function Na__ImageViewerMarkup__ClampBar() {
        if (!na_barMoved || !na_bar || !na_wrap || !na_active) return;
        var wrap = na_wrap.getBoundingClientRect(), bar = na_bar.getBoundingClientRect();
        Na__ImageViewerMarkup__PlaceBar(bar.left - wrap.left, bar.top - wrap.top);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Canvas Interaction
    // -------------------------------------------------------------------------

    // Capture phase on the canvas wrapper, ahead of the viewer's own pan: while
    // the tool is active every press on the photo is ours.
    function Na__ImageViewerMarkup__OnMouseDown(e) {
        if (!na_active || e.target !== na_canvas) return;
        e.stopPropagation();
        e.preventDefault();
        Na__ImageViewerMarkup__CloseFlyout();
        if (!Na__ImageViewerMarkup__Key()) {
            Na__ImageViewerMarkup__Toast('Choose a folder of photos first.');
            return;
        }
        if (e.button !== 0) {                              // right or middle: pan
            na_press = { lastX: e.clientX, lastY: e.clientY };
            Na__ImageViewerMarkup__UpdateCursor();
            return;
        }
        var img = Na__ImageViewerMarkup__ImagePoint(e, false);
        na_cursor = Na__ImageViewerMarkup__CanvasPoint(e);
        if (!img.inside) return;                           // a mark starts on the photo itself
        if (na_tool === 'eraser') {
            na_erase = { last: { x: img.x, y: img.y }, pushed: false, changed: false };
            Na__ImageViewerMarkup__EraseAt(img);
        } else {
            Na__ImageViewerMarkup__BeginStroke(img);
        }
        na_core.requestDraw();
    }

    function Na__ImageViewerMarkup__OnMouseMove(e) {
        if (na_barDrag) { Na__ImageViewerMarkup__OnBarDrag(e); return; }
        if (!na_active || !na_canvas) return;
        var over = e.target === na_canvas;

        if (na_press) {
            var ratio = na_core.getRatio();
            na_core.panBy((e.clientX - na_press.lastX) * ratio, (e.clientY - na_press.lastY) * ratio);
            na_press.lastX = e.clientX;
            na_press.lastY = e.clientY;
            return;
        }

        if (na_live || na_erase) {
            if (!(e.buttons & 1)) {                        // the button came up outside the window
                Na__ImageViewerMarkup__FinishGesture(e);
                return;
            }
            var img = Na__ImageViewerMarkup__ImagePoint(e, true);
            if (na_live) {
                Na__ImageViewerMarkup__ExtendStroke(img);
            } else {
                Na__ImageViewerMarkup__EraseAlong(na_erase.last, img);
                na_erase.last = { x: img.x, y: img.y };
            }
        }
        na_cursor = over ? Na__ImageViewerMarkup__CanvasPoint(e) : null;
        Na__ImageViewerMarkup__ScheduleDraw();
    }

    function Na__ImageViewerMarkup__FinishGesture(e) {
        var img = Na__ImageViewerMarkup__ImagePoint(e, true);
        if (na_live)       Na__ImageViewerMarkup__FinishStroke(img);
        else if (na_erase) Na__ImageViewerMarkup__FinishErase();
    }

    function Na__ImageViewerMarkup__OnMouseUp(e) {
        if (na_barDrag) { na_barDrag = null; return; }
        if (!na_active) return;
        if (na_press) {
            na_press = null;
            Na__ImageViewerMarkup__UpdateCursor();
            return;
        }
        if (na_live || na_erase) Na__ImageViewerMarkup__FinishGesture(e);
    }

    function Na__ImageViewerMarkup__OnMouseLeave() {
        if (!na_active || na_live || na_erase) return;
        na_cursor = null;
        na_core.requestDraw();
    }

    // Capture phase, ahead of the viewer: P, H and E choose the tool, Esc steps
    // back (the stroke in hand, the options, then the tool). Ctrl+Z and Ctrl+Y
    // are left to the Core's shared history.
    function Na__ImageViewerMarkup__OnKeyCapture(e) {
        if (!na_active) return;
        var tag = e.target && e.target.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        var k = e.key ? e.key.toLowerCase() : '';
        var handled = true;
        if      (k === 'p') Na__ImageViewerMarkup__SetTool('pen');
        else if (k === 'h') Na__ImageViewerMarkup__SetTool('hl');
        else if (k === 'e') Na__ImageViewerMarkup__SetTool('eraser');
        else if (e.key === 'Escape') Na__ImageViewerMarkup__Escape();
        else handled = false;
        if (!handled) return;
        e.preventDefault();
        e.stopPropagation();
    }

    function Na__ImageViewerMarkup__Escape() {
        if (na_erase)         Na__ImageViewerMarkup__FinishErase();
        else if (na_live)     Na__ImageViewerMarkup__CancelStroke();
        else if (na_flyoutOpen) Na__ImageViewerMarkup__CloseFlyout();
        else                  Na__ImageViewerMarkup__SetActive(false);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Initialisation
    // -------------------------------------------------------------------------

    function Na__ImageViewerMarkup__Init() {
        na_canvas     = na_core.getCanvas();
        na_wrap       = na_canvas ? na_canvas.parentElement : null;
        na_btnTool    = Na__ImageViewerMarkup__El('naImageViewer_btnMarkup');
        na_bar        = Na__ImageViewerMarkup__El('naImageViewer_markupBar');
        na_pill       = Na__ImageViewerMarkup__El('naImageViewer_markupPill');
        na_grip       = Na__ImageViewerMarkup__El('naImageViewer_markupGrip');
        na_btnOptions = Na__ImageViewerMarkup__El('naImageViewer_markupOptions');
        na_btnDone    = Na__ImageViewerMarkup__El('naImageViewer_markupDone');
        na_flyout     = Na__ImageViewerMarkup__El('naImageViewer_markupFlyout');
        na_toast      = Na__ImageViewerMarkup__El('naImageViewer_markupToast');
        na_toolBtns   = {
            pen    : Na__ImageViewerMarkup__El('naImageViewer_markupPen'),
            hl     : Na__ImageViewerMarkup__El('naImageViewer_markupHl'),
            eraser : Na__ImageViewerMarkup__El('naImageViewer_markupEraser')
        };
        if (!na_canvas || !na_wrap) return;

        na_core.registerOverlay(Na__ImageViewerMarkup__Render);
        na_core.registerHistory(NA_TOOL_NAME, {
            snapshot : Na__ImageViewerMarkup__Snapshot,
            restore  : Na__ImageViewerMarkup__Restore
        });
        na_core.onHistoryChanged(Na__ImageViewerMarkup__OnHistoryChanged);
        na_core.onImageChanged(function() {
            na_live   = null;
            na_erase  = null;
            na_press  = null;
            na_cursor = null;
            var key  = Na__ImageViewerMarkup__Key();
            var size = na_core.getImageSize();
            if (key && size && size.w) na_sizeByKey[key] = { w: size.w, h: size.h };
            Na__ImageViewerMarkup__Materialise(key);
            Na__ImageViewerMarkup__SyncMarkers();
            Na__ImageViewerMarkup__RefreshBar();
            Na__ImageViewerMarkup__UpdateCursor();
            na_core.requestDraw();
        });

        na_wrap.addEventListener('mousedown', Na__ImageViewerMarkup__OnMouseDown, true);
        window.addEventListener('mousemove', Na__ImageViewerMarkup__OnMouseMove);
        window.addEventListener('mouseup', Na__ImageViewerMarkup__OnMouseUp);
        window.addEventListener('keydown', Na__ImageViewerMarkup__OnKeyCapture, true);
        window.addEventListener('resize', Na__ImageViewerMarkup__ClampBar);
        na_canvas.addEventListener('mouseleave', Na__ImageViewerMarkup__OnMouseLeave);
        na_canvas.addEventListener('contextmenu', function(e) { if (na_active) e.preventDefault(); });
        document.addEventListener('mousedown', function(e) {
            if (na_flyoutOpen && na_bar && !na_bar.contains(e.target)) Na__ImageViewerMarkup__CloseFlyout();
        }, true);

        if (na_btnTool)    na_btnTool.addEventListener('click', function() { Na__ImageViewerMarkup__SetActive(!na_active); });
        if (na_btnDone)    na_btnDone.addEventListener('click', function() { Na__ImageViewerMarkup__SetActive(false); });
        if (na_btnOptions) na_btnOptions.addEventListener('click', Na__ImageViewerMarkup__ToggleFlyout);
        if (na_grip)       na_grip.addEventListener('mousedown', Na__ImageViewerMarkup__OnGripDown);
        if (na_flyout)     na_flyout.addEventListener('click', Na__ImageViewerMarkup__OnFlyoutClick);
        Object.keys(na_toolBtns).forEach(function(tool) {
            if (na_toolBtns[tool]) na_toolBtns[tool].addEventListener('click', function() { Na__ImageViewerMarkup__OnToolClick(tool); });
        });
        // Clicking a toolbar button must not take the keys away from the photo.
        if (na_bar) na_bar.addEventListener('mousedown', function(e) { if (e.target.closest && e.target.closest('button')) e.preventDefault(); });

        Na__ImageViewerMarkup__RefreshBar();
    }

    window.Na__ImageViewer__OnMarkupLoaded = Na__ImageViewerMarkup__OnLoaded;
    window.Na__ImageViewer__MarkupOnSaved  = Na__ImageViewerMarkup__OnSaved;

    // Read-only view of the markup state, for the browser tests.
    window.Na__ImageViewer__Markup = {
        inspect: function() {
            var key = Na__ImageViewerMarkup__Key();
            return {
                active   : na_active,
                tool     : na_tool,
                flyout   : na_flyoutOpen,
                pen      : { colour: na_pen.colour, size: na_pen.size },
                hl       : { colour: na_hl.colour, size: na_hl.size },
                eraser   : { mode: na_eraser.mode, size: na_eraser.size },
                live     : !!na_live,
                strokes  : (na_marksByKey[key] || []).map(function(s) { return { k: s.k, c: s.c, w: s.w, n: s.p.length / 2, p: s.p.slice() }; }),
                stored   : Object.keys(na_storedByKey),
                mismatch : na_mismatchByKey[key] || null,
                marked   : Na__ImageViewerMarkup__HasMarks(key),
                lastSave : na_lastSave,
                toast    : na_toast && na_toast.classList.contains('naImageViewer__MarkupToast--visible') ? na_toast.textContent : '',
                bar      : na_bar ? { open: na_bar.classList.contains('naImageViewer__MarkupBar--open'), moved: na_barMoved } : null
            };
        },
        serialise: function(key) {
            return Na__ImageViewerMarkup__Serialise(key || Na__ImageViewerMarkup__Key());
        }
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na__ImageViewerMarkup__Init);
    } else {
        Na__ImageViewerMarkup__Init();
    }

    // endregion ---------------------------------------------------------------

    // =============================================================================
    // END OF FILE
    // =============================================================================

})();
