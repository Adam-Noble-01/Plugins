// =============================================================================
// NA NOBLE3D MODELLING TOOLS - IMAGE VIEWER - MEASUREMENT FEATURE
//
// FILE       : Na__Noble3dModellingTools__ImageCarousel__Measurement__.js
// PURPOSE    : Self-contained on-canvas measurement overlay for the Image
//              Viewer. Draws dimension lines that pan/zoom/rotate with the
//              image, sets a reference scale from a known length (metric unit
//              aware), and clears dimensions per image.
//
// DESIGN     : Depends only on window.Na__ImageViewer__Core (defined in the
//              UiBridge). No base-viewer internals are touched; all feature
//              state, parsing, drawing, and interaction live here. Undo/redo
//              and the active tool are shared through the Core, so Ctrl+Z
//              also steps back through the Perspective Angle tool's lines.
//              The reference scale, with the line it was set from, is
//              readable through window.Na__ImageViewer__Measure, so the
//              Count tool can dimension its parts in the same units.
//              Each photo's dimensions and reference are kept in the model
//              (DimensionPersistence.rb), like the Markup tool's marks:
//                dimensions_save(json) -> Ruby holds and writes them
//                Na__ImageViewer__OnDimensionsLoaded(map) <- the model's
//                                      dimensions for the folder's photos
//              In memory points are image space (origin at the photo's
//              centre); in the model photo pixels from the top-left, beside
//              the photo's size.
//              Editing (Select): grab either end of any dimension (14 px reach)
//              and drag it, the other end staying put, with snapping, Ortho,
//              Shift and Rounding as when drawing; drag the line itself to move
//              it all. Type a length and Enter to set it exactly. Esc puts a
//              drag back. One undo step per edit. Moving the reference line
//              re-scales the photo, its known length kept.
//              Ortho guides: while Ortho (or Shift) is in effect, a dashed,
//              half see-through red level line and green plumb line run across
//              the view through the end being placed or dragged.
// =============================================================================

(function() {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Guard - require the viewer Core API
    // -------------------------------------------------------------------------

    var na_core = window.Na__ImageViewer__Core;
    if (!na_core) { return; }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Feature State (per session, keyed by image path)
    // -------------------------------------------------------------------------

    var na_dimsByKey     = {};    // image key -> [ { a:{x,y}, b:{x,y} } ] image space
    var na_scaleByKey    = {};    // image key -> { pxPerMm:Number, unit:'mm'|'cm'|'m', ref:{ a, b, mm } }
    var na_measureMode   = false;
    var na_refMode       = false;
    var na_selectMode    = false;
    var na_pendingPoint  = null;  // first click, image space, while placing a dim
    var na_previewScreen = null;  // live cursor pos, canvas px, for rubber-band
    var na_refPendingDim = null;  // reference line awaiting a typed known value
    var na_selectedDim   = null;  // reference to the currently selected dim object
    var na_sizeByKey     = {};    // image key -> { w, h } once the photo has been shown
    var na_storedByKey   = {};    // image key -> the model's entry, until the photo is shown
    var na_sentByKey     = {};    // image key -> last JSON given to Ruby (or read from it)
    var na_lastSaved     = null;  // Ruby's last answer to a write
    var na_grabbed       = null;  // { dim, part:'a'|'b'|'line', orig:{a,b}, press:{x,y}, startImg, moved, wasRef }
    var na_hoverGrip     = null;  // { dim, part } under the pointer in Select
    var na_suppressClick = false; // the click that ends a press already handled
    var na_lastEnd       = 'b';   // the end a typed length moves
    var na_typed         = '';    // a length being typed for the selected dimension
    var na_cursorScreen  = null;  // snapped pointer, canvas px, before the first point (Ortho guides)
    var na_lastCursor    = null;  // last raw cursor, canvas px, so Shift / F8 can re-aim the preview
    var na_shiftHeld     = false; // Shift held: Ortho's temporary override

    // Tool options, kept between sessions where the dialog allows storage
    var NA_ROUNDING_STEPS = [0, 5, 10, 50, 100, 500, 1000];   // mm; 0 = Off
    var NA_STORE_ORTHO    = 'Na__ImageViewer__Measure__Ortho';
    var NA_STORE_ROUNDING = 'Na__ImageViewer__Measure__RoundingMm';
    var na_orthoOn        = false;
    var na_roundingMm     = 0;

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Appearance Constants
    // -------------------------------------------------------------------------

    var NA_DIM_COLOR      = '#e23b2e';
    var NA_REF_COLOR      = '#1f9d55';
    var NA_PREVIEW_COLOR  = '#2f77d5';
    var NA_SELECTED_COLOR = '#f5a623';
    var NA_LABEL_TEXT     = '#ffffff';
    var NA_LINE_PX        = 1.6;
    var NA_TICK_PX        = 7;
    var NA_FONT_PX        = 12;
    var NA_HIT_TOLERANCE_PX = 9;
    var NA_GRIP_REACH_PX    = 14;    // an end is grabbed this far away, as the Layout Editor's GrabRadiusPx
    var NA_GRIP_PX          = 4.5;   // half the square grip's side
    var NA_DRAG_START_PX    = 3;     // a press moves this far before it is a drag
    var NA_SNAP_END_PX      = 10;    // other dimensions' ends snap within this
    var NA_GUIDE_X_COLOR    = '#d4291c';   // Ortho guides: x (level) red, y (plumb) green,
    var NA_GUIDE_Y_COLOR    = '#178a3a';   // as the Angle tool's red and green axes
    var NA_GUIDE_ALPHA      = 0.5;

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | DOM Handles
    // -------------------------------------------------------------------------

    var na_btnMeasure        = null;
    var na_btnRef            = null;
    var na_btnSelect         = null;
    var na_btnDeleteSelected = null;
    var na_btnClear          = null;
    var na_refOverlay        = null;
    var na_refInput          = null;
    var na_refHint           = null;
    var na_refOk             = null;
    var na_refCancel         = null;
    var na_btnOrtho          = null;
    var na_btnRounding       = null;
    var na_roundingLabel     = null;
    var na_optionsDivider    = null;
    var na_optionsGroup      = null;
    var na_btnSaveImage      = null;

    function Na__ImageViewerMeasure__El(id) {
        return document.getElementById(id);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Per-Image Accessors
    // -------------------------------------------------------------------------

    function Na__ImageViewerMeasure__Dims(key) {
        if (!na_dimsByKey[key]) na_dimsByKey[key] = [];
        return na_dimsByKey[key];
    }

    function Na__ImageViewerMeasure__Scale(key) {
        return na_scaleByKey[key] || null;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | History (Undo / Redo)
    // -------------------------------------------------------------------------
    // The undo history lives in the viewer Core and is shared with the other
    // overlay features. This file tells the Core how to snapshot and restore
    // its own state for an image (dims + scale), and asks for a snapshot
    // before every change. Undo/redo replay snapshots rather than inverse
    // operations, which keeps every action (add, delete, clear,
    // set-reference) correct with one code path.

    function Na__ImageViewerMeasure__CloneDim(dim) {
        return { a: { x: dim.a.x, y: dim.a.y }, b: { x: dim.b.x, y: dim.b.y } };
    }

    // The scale keeps the reference line it was set from (ref), as well as
    // the pixels per millimetre it gives.
    function Na__ImageViewerMeasure__CloneScale(scale) {
        if (!scale) return null;
        var c = { pxPerMm: scale.pxPerMm, unit: scale.unit };
        if (scale.ref) c.ref = { a: { x: scale.ref.a.x, y: scale.ref.a.y }, b: { x: scale.ref.b.x, y: scale.ref.b.y }, mm: scale.ref.mm };
        return c;
    }

    function Na__ImageViewerMeasure__Snapshot(key) {
        var dims  = na_dimsByKey[key] || [];
        var scale = na_scaleByKey[key];
        return {
            dims  : dims.map(Na__ImageViewerMeasure__CloneDim),
            scale : Na__ImageViewerMeasure__CloneScale(scale)
        };
    }

    function Na__ImageViewerMeasure__RestoreSnapshot(key, snap) {
        if (!snap) { delete na_dimsByKey[key]; delete na_scaleByKey[key]; return; }
        na_dimsByKey[key] = snap.dims.map(Na__ImageViewerMeasure__CloneDim);
        if (snap.scale) na_scaleByKey[key] = Na__ImageViewerMeasure__CloneScale(snap.scale);
        else            delete na_scaleByKey[key];
    }

    function Na__ImageViewerMeasure__PushUndo() {
        na_core.pushHistory();
    }

    function Na__ImageViewerMeasure__OnHistoryChanged(reason) {
        if (reason !== 'undo' && reason !== 'redo') return;
        na_grabbed = null;
        na_typed   = '';
        Na__ImageViewerMeasure__Persist(na_core.getImageKey());
        na_selectedDim   = null;
        na_refPendingDim = null;
        Na__ImageViewerMeasure__HideRefOverlay(true);
        Na__ImageViewerMeasure__CancelPending();
        Na__ImageViewerMeasure__RefreshUi();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Keeping Dimensions In The Model
    // -------------------------------------------------------------------------

    var NA_ASPECT_TOL = 0.01;

    function Na__ImageViewerMeasure__Round(v) {
        return Math.round(v * 1000) / 1000;
    }

    // One photo's dimensions as kept in the model: photo pixels from the top-left.
    function Na__ImageViewerMeasure__Serialise(key) {
        var size = na_sizeByKey[key];
        if (!key || !size) return null;
        var hw = size.w / 2, hh = size.h / 2;
        function line(d) {
            return [Na__ImageViewerMeasure__Round(d.a.x + hw), Na__ImageViewerMeasure__Round(d.a.y + hh),
                    Na__ImageViewerMeasure__Round(d.b.x + hw), Na__ImageViewerMeasure__Round(d.b.y + hh)];
        }
        var entry = { path: key, w: size.w, h: size.h, dims: (na_dimsByKey[key] || []).map(line) };
        var scale = na_scaleByKey[key];
        if (scale && scale.pxPerMm > 0) {
            entry.scale = { pxPerMm: Math.round(scale.pxPerMm * 1e9) / 1e9, unit: scale.unit || 'mm' };
            if (scale.ref) entry.scale.ref = line(scale.ref).concat([Na__ImageViewerMeasure__Round(scale.ref.mm)]);
        }
        return entry;
    }

    // Hand a photo's dimensions to Ruby, unless the model already has exactly these.
    function Na__ImageViewerMeasure__Persist(key) {
        var entry = Na__ImageViewerMeasure__Serialise(key);
        if (!entry) return;
        var text = JSON.stringify(entry);
        if (na_sentByKey[key] === text) return;
        na_sentByKey[key] = text;
        if (window.sketchup && typeof window.sketchup.dimensions_save === 'function') {
            window.sketchup.dimensions_save(text);
        }
    }

    // The model's entry for a photo, as dimensions, once its size is known. The
    // same size takes them as they are, another size of the same shape scaled;
    // any other shape is left in the model untouched.
    function Na__ImageViewerMeasure__Materialise(key) {
        var entry = na_storedByKey[key];
        var size  = na_core.getImageSize();
        if (!key || !entry || !size || !size.w || !size.h) return;
        if ((na_dimsByKey[key] && na_dimsByKey[key].length) || na_scaleByKey[key]) { delete na_storedByKey[key]; return; }

        var sw = Number(entry.w), sh = Number(entry.h), k;
        if (!(sw > 0) || !(sh > 0)) { delete na_storedByKey[key]; return; }
        if (sw === size.w && sh === size.h) k = 1;
        else if (Math.abs(sw / sh - size.w / size.h) <= NA_ASPECT_TOL * (sw / sh)) k = size.w / sw;
        else return;

        delete na_storedByKey[key];
        na_sizeByKey[key] = { w: size.w, h: size.h };
        var hw = size.w / 2, hh = size.h / 2;
        function dim(raw) {
            if (!Array.isArray(raw) || raw.length < 4) return null;
            var v = raw.slice(0, 4).map(Number);
            if (!v.every(isFinite)) return null;
            return { a: { x: v[0] * k - hw, y: v[1] * k - hh }, b: { x: v[2] * k - hw, y: v[3] * k - hh } };
        }
        na_dimsByKey[key] = (entry.dims || []).map(dim).filter(Boolean);
        var sc = entry.scale;
        if (sc && Number(sc.pxPerMm) > 0) {
            var scale = { pxPerMm: Number(sc.pxPerMm) * k, unit: sc.unit === 'm' || sc.unit === 'cm' ? sc.unit : 'mm' };
            var ref = dim(sc.ref);
            if (ref && Number(sc.ref[4]) > 0) { ref.mm = Number(sc.ref[4]); scale.ref = ref; }
            na_scaleByKey[key] = scale;
        }
        na_sentByKey[key] = JSON.stringify(Na__ImageViewerMeasure__Serialise(key));
    }

    // Ruby's answer to a folder choice: the model's dimensions for its photos.
    function Na__ImageViewerMeasure__OnLoaded(map) {
        if (!map || typeof map !== 'object') return;
        Object.keys(map).forEach(function(path) {
            var entry = map[path];
            if (!entry || !Array.isArray(entry.dims)) return;
            if ((na_dimsByKey[path] && na_dimsByKey[path].length) || na_scaleByKey[path]) return;   // this session's are newer
            na_storedByKey[path] = entry;
        });
        Na__ImageViewerMeasure__Materialise(na_core.getImageKey());
        Na__ImageViewerMeasure__RefreshUi();
        na_core.requestDraw();
    }

    function Na__ImageViewerMeasure__OnSaved(result) {
        na_lastSaved = result || null;
        if (result && result.ok === false) {
            Na__ImageViewerMeasure__ShowHint('Dimensions not kept in the model: ' + (result.error || 'unknown error'));
        }
    }

    window.Na__ImageViewer__OnDimensionsLoaded = Na__ImageViewerMeasure__OnLoaded;
    window.Na__ImageViewer__DimensionsOnSaved  = Na__ImageViewerMeasure__OnSaved;

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Geometry + Unit Parsing
    // -------------------------------------------------------------------------

    function Na__ImageViewerMeasure__PixelLength(dim) {
        var dx = dim.b.x - dim.a.x;
        var dy = dim.b.y - dim.a.y;
        return Math.sqrt(dx * dx + dy * dy);
    }

    // Parse a known length. Bare number = millimetres; mm / cm / m recognised.
    // Returns { mm:Number, unit:'mm'|'cm'|'m' } or null if unparseable.
    function Na__ImageViewerMeasure__ParseReference(raw) {
        if (raw === null || raw === undefined) return null;
        var s = String(raw).trim().toLowerCase().replace(/\s+/g, '');
        var m = s.match(/^([0-9]*\.?[0-9]+)(mm|cm|m)?$/);
        if (!m) return null;

        var val = parseFloat(m[1]);
        if (!isFinite(val) || val <= 0) return null;

        var unit = m[2] || 'mm';
        var mm;
        if      (unit === 'm')  mm = val * 1000;
        else if (unit === 'cm') mm = val * 10;
        else                    mm = val;

        return { mm: mm, unit: unit };
    }

    function Na__ImageViewerMeasure__FormatByUnit(mm, unit) {
        if (unit === 'm')  return (mm / 1000).toFixed(2) + ' m';
        if (unit === 'cm') return (mm / 10).toFixed(1) + ' cm';
        return Math.round(mm) + ' mm';
    }

    function Na__ImageViewerMeasure__DimLabel(dim, scale) {
        var px = Na__ImageViewerMeasure__PixelLength(dim);
        if (!scale || !scale.pxPerMm) {
            return Math.round(px) + ' units';
        }
        return Na__ImageViewerMeasure__FormatByUnit(px / scale.pxPerMm, scale.unit);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Hit Testing (screen-space distance to a dim's line segment)
    // -------------------------------------------------------------------------

    function Na__ImageViewerMeasure__DistanceToSegment(px, py, p1, p2) {
        var dx     = p2.x - p1.x;
        var dy     = p2.y - p1.y;
        var lenSq  = dx * dx + dy * dy;
        var t      = lenSq > 0 ? ((px - p1.x) * dx + (py - p1.y) * dy) / lenSq : 0;
        t          = Math.max(0, Math.min(1, t));
        var nearX  = p1.x + t * dx;
        var nearY  = p1.y + t * dy;
        var ex     = px - nearX;
        var ey     = py - nearY;
        return Math.sqrt(ex * ex + ey * ey);
    }

    function Na__ImageViewerMeasure__FindDimAt(cx, cy, key) {
        var ratio     = na_core.getRatio();
        var tolerance = NA_HIT_TOLERANCE_PX * ratio;
        var dims      = na_dimsByKey[key] || [];
        var best      = null;
        var bestDist  = tolerance;

        for (var i = 0; i < dims.length; i++) {
            var p1 = na_core.imgToScreen(dims[i].a);
            var p2 = na_core.imgToScreen(dims[i].b);
            var d  = Na__ImageViewerMeasure__DistanceToSegment(cx, cy, p1, p2);
            if (d <= bestDist) { bestDist = d; best = dims[i]; }
        }
        return best;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Overlay Rendering
    // -------------------------------------------------------------------------

    function Na__ImageViewerMeasure__Render(ctx) {
        if (!ctx) return;
        var ratio = na_core.getRatio();
        var key   = na_core.getImageKey();
        if (!key) return;

        var scale = Na__ImageViewerMeasure__Scale(key);
        var dims  = na_dimsByKey[key] || [];

        for (var i = 0; i < dims.length; i++) {
            var isSelected = dims[i] === na_selectedDim;
            Na__ImageViewerMeasure__DrawDim(ctx, ratio, dims[i],
                isSelected ? NA_SELECTED_COLOR : NA_DIM_COLOR,
                Na__ImageViewerMeasure__DimLabel(dims[i], scale), isSelected);
        }

        if (typeof na_core.isExporting === 'function' && na_core.isExporting()) return;

        if (na_refPendingDim) {
            Na__ImageViewerMeasure__DrawDim(ctx, ratio, na_refPendingDim, NA_REF_COLOR,
                Na__ImageViewerMeasure__DimLabel(na_refPendingDim, scale), false);
        }

        if (na_pendingPoint && na_previewScreen) {
            Na__ImageViewerMeasure__DrawPreview(ctx, ratio, scale);
        }

        Na__ImageViewerMeasure__DrawOrthoGuides(ctx, ratio);
    }

    // Where the Ortho guides cross: the free end being placed or dragged, or the
    // pointer before the first point. Null when Ortho is not in effect.
    function Na__ImageViewerMeasure__GuidePoint() {
        if (!Na__ImageViewerMeasure__OrthoHeld(na_shiftHeld)) return null;
        if (na_grabbed && na_grabbed.moved && na_grabbed.part !== 'line') return na_core.imgToScreen(na_grabbed.dim[na_grabbed.part]);
        if (!(na_measureMode || na_refMode) || na_refPendingDim) return null;
        if (na_pendingPoint && na_previewScreen) return na_previewScreen;
        return na_cursorScreen;
    }

    // A red level line and a green plumb line through that point, across the
    // whole view: dashed and half see-through, to line the end up with the
    // photo without hiding it.
    function Na__ImageViewerMeasure__DrawOrthoGuides(ctx, ratio) {
        var p = Na__ImageViewerMeasure__GuidePoint();
        var canvas = na_core.getCanvas();
        if (!p || !canvas) return;
        // Whole device pixels, on the pixel grid: a line that straddles two rows
        // anti-aliases to well under the half strength asked for.
        var w   = Math.max(1, Math.round(ratio));
        var off = w % 2 ? 0.5 : 0;
        var x   = Math.round(p.x - off) + off;
        var y   = Math.round(p.y - off) + off;
        ctx.save();
        ctx.globalAlpha = NA_GUIDE_ALPHA;
        ctx.lineWidth   = w;
        ctx.lineCap     = 'butt';
        ctx.setLineDash([7 * ratio, 6 * ratio]);
        ctx.strokeStyle = NA_GUIDE_X_COLOR;
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(canvas.width, y);
        ctx.stroke();
        ctx.strokeStyle = NA_GUIDE_Y_COLOR;
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, canvas.height);
        ctx.stroke();
        ctx.restore();
    }

    function Na__ImageViewerMeasure__DrawDim(ctx, ratio, dim, color, label, isSelected) {
        var p1 = na_core.imgToScreen(dim.a);
        var p2 = na_core.imgToScreen(dim.b);
        Na__ImageViewerMeasure__StrokeLine(ctx, ratio, p1, p2, color, false, isSelected);
        Na__ImageViewerMeasure__DrawTick(ctx, ratio, p1, p2, color);
        Na__ImageViewerMeasure__DrawTick(ctx, ratio, p2, p1, color);
        if (isSelected) {
            Na__ImageViewerMeasure__DrawGrip(ctx, ratio, p1, color, Na__ImageViewerMeasure__GripState(dim, 'a'));
            Na__ImageViewerMeasure__DrawGrip(ctx, ratio, p2, color, Na__ImageViewerMeasure__GripState(dim, 'b'));
        } else if (na_selectMode && na_hoverGrip && na_hoverGrip.dim === dim && na_hoverGrip.part !== 'line') {
            Na__ImageViewerMeasure__DrawGrip(ctx, ratio, na_hoverGrip.part === 'a' ? p1 : p2, color, 'hover');
        }
        Na__ImageViewerMeasure__DrawLabel(ctx, ratio,
            (p1.x + p2.x) / 2, (p1.y + p2.y) / 2, label, color);
    }

    function Na__ImageViewerMeasure__DrawPreview(ctx, ratio, scale) {
        var p1  = na_core.imgToScreen(na_pendingPoint);
        var p2  = na_previewScreen;
        var end = na_core.screenToImg(p2.x, p2.y);
        var lbl = Na__ImageViewerMeasure__DimLabel({ a: na_pendingPoint, b: end }, scale);
        Na__ImageViewerMeasure__StrokeLine(ctx, ratio, p1, p2, NA_PREVIEW_COLOR, true, false);
        Na__ImageViewerMeasure__DrawLabel(ctx, ratio,
            (p1.x + p2.x) / 2, (p1.y + p2.y) / 2, lbl, NA_PREVIEW_COLOR);
    }

    function Na__ImageViewerMeasure__StrokeLine(ctx, ratio, p1, p2, color, dashed, thick) {
        ctx.save();
        ctx.lineWidth   = (thick ? NA_LINE_PX * 1.8 : NA_LINE_PX) * ratio;
        ctx.strokeStyle = color;
        ctx.lineCap     = 'round';
        if (dashed) ctx.setLineDash([6 * ratio, 5 * ratio]);
        ctx.beginPath();
        ctx.moveTo(p1.x, p1.y);
        ctx.lineTo(p2.x, p2.y);
        ctx.stroke();
        ctx.restore();
    }

    // 'held' (being dragged), 'hover' (under the pointer) or ''.
    function Na__ImageViewerMeasure__GripState(dim, part) {
        if (na_grabbed && na_grabbed.dim === dim && na_grabbed.moved && (na_grabbed.part === part || na_grabbed.part === 'line')) return 'held';
        if (na_hoverGrip && na_hoverGrip.dim === dim && na_hoverGrip.part === part) return 'hover';
        return '';
    }

    // A square grip, as the Layout Editor's: larger and red while held.
    function Na__ImageViewerMeasure__DrawGrip(ctx, ratio, pt, color, state) {
        var half = (state === 'held' ? NA_GRIP_PX * 1.45 : state === 'hover' ? NA_GRIP_PX * 1.25 : NA_GRIP_PX) * ratio;
        ctx.save();
        ctx.fillStyle   = state === 'held' ? NA_DIM_COLOR : state === 'hover' ? '#ffffff' : color;
        ctx.strokeStyle = state === 'hover' ? color : '#ffffff';
        ctx.lineWidth   = (state === 'hover' ? 2 : 1.2) * ratio;
        ctx.beginPath();
        ctx.rect(pt.x - half, pt.y - half, half * 2, half * 2);
        ctx.fill();
        ctx.stroke();
        ctx.restore();
    }

    function Na__ImageViewerMeasure__DrawTick(ctx, ratio, at, toward, color) {
        var dx  = toward.x - at.x;
        var dy  = toward.y - at.y;
        var len = Math.sqrt(dx * dx + dy * dy) || 1;
        var px  = -dy / len;
        var py  =  dx / len;
        var t   = NA_TICK_PX * ratio;
        ctx.save();
        ctx.lineWidth   = NA_LINE_PX * ratio;
        ctx.strokeStyle = color;
        ctx.beginPath();
        ctx.moveTo(at.x - px * t, at.y - py * t);
        ctx.lineTo(at.x + px * t, at.y + py * t);
        ctx.stroke();
        ctx.restore();
    }

    function Na__ImageViewerMeasure__DrawLabel(ctx, ratio, cx, cy, text, color) {
        ctx.save();
        ctx.font         = '600 ' + (NA_FONT_PX * ratio) + 'px "Segoe UI", Arial, sans-serif';
        ctx.textBaseline = 'middle';
        ctx.textAlign    = 'center';

        var padX = 5 * ratio;
        var padY = 3 * ratio;
        var tw   = ctx.measureText(text).width;
        var bw   = tw + padX * 2;
        var bh   = NA_FONT_PX * ratio + padY * 2;

        ctx.fillStyle   = color;
        ctx.strokeStyle = 'rgba(255,255,255,0.9)';
        ctx.lineWidth   = 1 * ratio;
        ctx.beginPath();
        ctx.rect(cx - bw / 2, cy - bh / 2, bw, bh);
        ctx.fill();
        ctx.stroke();

        ctx.fillStyle = NA_LABEL_TEXT;
        ctx.fillText(text, cx, cy + ratio * 0.5);
        ctx.restore();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Mode Management
    // -------------------------------------------------------------------------

    function Na__ImageViewerMeasure__CancelPending() {
        na_cursorScreen  = null;
        na_pendingPoint  = null;
        na_previewScreen = null;
    }

    function Na__ImageViewerMeasure__SetMeasureMode(on) {
        na_measureMode = on;
        if (on) {
            Na__ImageViewerMeasure__LeaveSelect();
            na_refMode     = false;
            na_selectMode  = false;
            na_selectedDim = null;
            Na__ImageViewerMeasure__HideRefOverlay(true);
        }
        Na__ImageViewerMeasure__CancelPending();
        Na__ImageViewerMeasure__RefreshUi();
        na_core.requestDraw();
    }

    function Na__ImageViewerMeasure__SetRefMode(on) {
        na_refMode = on;
        if (on) {
            Na__ImageViewerMeasure__LeaveSelect();
            na_measureMode = false;
            na_selectMode  = false;
            na_selectedDim = null;
        } else {
            Na__ImageViewerMeasure__HideRefOverlay(true);
        }
        Na__ImageViewerMeasure__CancelPending();
        Na__ImageViewerMeasure__RefreshUi();
        na_core.requestDraw();
    }

    function Na__ImageViewerMeasure__SetSelectMode(on) {
        if (!on) Na__ImageViewerMeasure__LeaveSelect();
        na_selectMode = on;
        if (on) {
            na_measureMode = false;
            na_refMode     = false;
            Na__ImageViewerMeasure__HideRefOverlay(true);
        } else {
            na_selectedDim = null;
        }
        Na__ImageViewerMeasure__CancelPending();
        Na__ImageViewerMeasure__RefreshUi();
        na_core.requestDraw();
    }

    function Na__ImageViewerMeasure__LeaveSelect() {
        Na__ImageViewerMeasure__CancelDrag();
        na_hoverGrip = null;
        na_typed     = '';
        Na__ImageViewerMeasure__GripCursor('');
    }

    // By class, not the inline cursor the other tools reset as the pointer moves.
    function Na__ImageViewerMeasure__GripCursor(kind) {
        var canvas = na_core.getCanvas();
        if (!canvas) return;
        if (canvas.classList.contains('naImageViewer__Canvas--grip') !== (kind === 'grip')) canvas.classList.toggle('naImageViewer__Canvas--grip', kind === 'grip');
        if (canvas.classList.contains('naImageViewer__Canvas--moveDim') !== (kind === 'move')) canvas.classList.toggle('naImageViewer__Canvas--moveDim', kind === 'move');
    }

    function Na__ImageViewerMeasure__ExitAllModes() {
        Na__ImageViewerMeasure__LeaveSelect();
        na_measureMode   = false;
        na_refMode       = false;
        na_selectMode    = false;
        na_selectedDim   = null;
        na_refPendingDim = null;
        Na__ImageViewerMeasure__HideRefOverlay(true);
        Na__ImageViewerMeasure__CancelPending();
        Na__ImageViewerMeasure__RefreshUi();
        na_core.requestDraw();
    }

    function Na__ImageViewerMeasure__RefreshUi() {
        Na__ImageViewerMeasure__SyncModeUi();
        Na__ImageViewerMeasure__SyncActionButtons();
    }

    function Na__ImageViewerMeasure__SyncModeUi() {
        var active = na_measureMode || na_refMode || na_selectMode;
        na_core.setPanEnabled(!active);
        if (active) na_core.claimTool('measure', Na__ImageViewerMeasure__ExitAllModes);
        else        na_core.releaseTool('measure');

        if (na_btnMeasure) na_btnMeasure.classList.toggle('naImageViewer__Btn--active', na_measureMode);
        if (na_btnRef)     na_btnRef.classList.toggle('naImageViewer__Btn--active', na_refMode);
        if (na_btnSelect)  na_btnSelect.classList.toggle('naImageViewer__Btn--active', na_selectMode);

        var scale = Na__ImageViewerMeasure__Scale(na_core.getImageKey());
        if (na_btnRef) na_btnRef.classList.toggle('naImageViewer__Btn--hasScale', !!scale);

        Na__ImageViewerMeasure__SyncOptionsUi();

        if (na_measureMode) {
            Na__ImageViewerMeasure__ShowHint((scale
                ? 'Measure: click two points.'
                : 'Measure (no scale yet - shows units). Click two points.')
                + Na__ImageViewerMeasure__OptionsHint() + ' Esc to stop.');
        } else if (na_refMode && !na_refPendingDim) {
            Na__ImageViewerMeasure__ShowHint('Set Reference: click the two ends of a known length.'
                + Na__ImageViewerMeasure__OptionsHint());
        } else if (na_selectMode) {
            var hasScale = !!Na__ImageViewerMeasure__Scale(na_core.getImageKey());
            if (na_typed) {
                Na__ImageViewerMeasure__ShowHint('Length: ' + na_typed + '  Enter to set, Esc to clear.');
            } else if (na_selectedDim) {
                Na__ImageViewerMeasure__ShowHint('Selected: drag an end to move it, or the line to move it all.'
                    + (hasScale ? ' Type a length and Enter to set it.' : '') + ' Delete removes. Esc to deselect.');
            } else {
                Na__ImageViewerMeasure__ShowHint('Select: click a dimension, or grab an end and drag it. Esc to stop.');
            }
        } else if (!na_refPendingDim) {
            Na__ImageViewerMeasure__HideHint();
        }
    }

    // The options section after its own divider: Ortho for Dimension and
    // Reference, Rounding for Dimension once the photo has a reference scale.
    function Na__ImageViewerMeasure__SyncOptionsUi() {
        var showOrtho    = na_measureMode || na_refMode;
        var showRounding = na_measureMode && !!Na__ImageViewerMeasure__Scale(na_core.getImageKey());
        var showAny      = showOrtho || showRounding;
        if (na_optionsDivider) na_optionsDivider.classList.toggle('naImageViewer__ToolOptions--shown', showAny);
        if (na_optionsGroup)   na_optionsGroup.classList.toggle('naImageViewer__ToolOptions--shown', showAny);
        if (na_btnOrtho) {
            na_btnOrtho.style.display = showOrtho ? '' : 'none';
            na_btnOrtho.classList.toggle('naImageViewer__Btn--toggled', na_orthoOn);
            na_btnOrtho.setAttribute('aria-pressed', na_orthoOn ? 'true' : 'false');
        }
        if (na_btnRounding) {
            na_btnRounding.style.display = showRounding ? '' : 'none';
            na_btnRounding.classList.toggle('naImageViewer__Btn--toggled', na_roundingMm > 0);
        }
        if (na_roundingLabel) na_roundingLabel.textContent = na_roundingMm > 0 ? na_roundingMm + ' mm' : 'Round Off';
    }

    function Na__ImageViewerMeasure__OptionsHint() {
        var parts = '';
        if (na_orthoOn) parts += ' Ortho on (F8).';
        if (na_measureMode && na_roundingMm > 0 && Na__ImageViewerMeasure__Scale(na_core.getImageKey())) {
            parts += ' Rounding to ' + na_roundingMm + ' mm.';
        }
        return parts;
    }

    // Undo / Redo buttons are kept in step by the Core's shared history.
    function Na__ImageViewerMeasure__SyncActionButtons() {
        if (na_btnDeleteSelected) na_btnDeleteSelected.disabled = !na_selectedDim;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Reference Value Overlay
    // -------------------------------------------------------------------------

    function Na__ImageViewerMeasure__ShowRefOverlay() {
        if (!na_refOverlay) return;
        na_refOverlay.classList.add('naImageViewer__RefOverlay--visible');
        if (na_refInput) {
            na_refInput.value = '';
            na_refInput.classList.remove('naImageViewer__RefInput--error');
            na_refInput.focus();
        }
        Na__ImageViewerMeasure__ShowHint('Enter the real length (e.g. 1345, 1.35m, 135cm).');
    }

    function Na__ImageViewerMeasure__HideRefOverlay(discard) {
        if (na_refOverlay) na_refOverlay.classList.remove('naImageViewer__RefOverlay--visible');
        if (discard) na_refPendingDim = null;
    }

    function Na__ImageViewerMeasure__ConfirmRef() {
        if (!na_refPendingDim) { Na__ImageViewerMeasure__HideRefOverlay(true); return; }

        var parsed = Na__ImageViewerMeasure__ParseReference(na_refInput ? na_refInput.value : '');
        if (!parsed) {
            if (na_refInput) na_refInput.classList.add('naImageViewer__RefInput--error');
            Na__ImageViewerMeasure__ShowHint('Could not read that. Try 1345, 1.35m or 135cm.');
            return;
        }

        var px = Na__ImageViewerMeasure__PixelLength(na_refPendingDim);
        if (px <= 0) {
            Na__ImageViewerMeasure__ShowHint('Reference line has no length - draw it again.');
            na_refPendingDim = null;
            Na__ImageViewerMeasure__HideRefOverlay(true);
            Na__ImageViewerMeasure__SetRefMode(false);
            return;
        }

        var key = na_core.getImageKey();
        Na__ImageViewerMeasure__PushUndo();
        na_scaleByKey[key] = {
            pxPerMm : px / parsed.mm,
            unit    : parsed.unit,
            ref     : Na__ImageViewerMeasure__CloneDim(na_refPendingDim)
        };
        na_scaleByKey[key].ref.mm = parsed.mm;
        Na__ImageViewerMeasure__Dims(key).push(na_refPendingDim);
        na_refPendingDim = null;
        Na__ImageViewerMeasure__Persist(key);

        Na__ImageViewerMeasure__HideRefOverlay(false);
        na_refMode = false;
        Na__ImageViewerMeasure__RefreshUi();
        Na__ImageViewerMeasure__ShowHint('Scale set. New measurements now read in ' + parsed.unit + '.');
        na_core.requestDraw();
    }

    function Na__ImageViewerMeasure__CancelRef() {
        na_refPendingDim = null;
        Na__ImageViewerMeasure__HideRefOverlay(true);
        Na__ImageViewerMeasure__SetRefMode(false);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Tool Options (Ortho, Rounding)
    // -------------------------------------------------------------------------
    // As in the TrueVision Layout Editor: Ortho (F8) holds the second point
    // level or plumb from the first, the free cursor choosing the axis
    // (|dx| >= |dy| goes level) and a snap only giving the coordinate along
    // it. Shift is AutoCAD's temporary override, Ortho XOR Shift: held with
    // Ortho off it locks, held with Ortho on it frees. The axes are the
    // screen's, so they follow what you see on a rotated photo.
    // Rounding then slides the second point along the line so the length is
    // a whole number of steps (at least one). It needs the reference scale,
    // as millimetres mean nothing without it.

    function Na__ImageViewerMeasure__StoreRead(key) {
        try { return window.localStorage ? window.localStorage.getItem(key) : null; } catch (_e) { return null; }
    }

    function Na__ImageViewerMeasure__StoreWrite(key, value) {
        try { if (window.localStorage) window.localStorage.setItem(key, String(value)); } catch (_e) { /* session only */ }
    }

    function Na__ImageViewerMeasure__OrthoHeld(shiftKey) {
        return na_orthoOn !== !!shiftKey;
    }

    function Na__ImageViewerMeasure__SetOrtho(on) {
        na_orthoOn = !!on;
        Na__ImageViewerMeasure__StoreWrite(NA_STORE_ORTHO, na_orthoOn ? '1' : '0');
        Na__ImageViewerMeasure__ReaimPreview();
        Na__ImageViewerMeasure__RefreshUi();
        if (!na_measureMode && !na_refMode && !na_selectMode && !na_refPendingDim) {
            Na__ImageViewerMeasure__ShowHint(na_orthoOn ? '<Ortho on>' : '<Ortho off>');
        }
    }

    // Click steps forward, right-click back: Off, 5, 10, 50, 100, 500, 1000 mm, Off...
    function Na__ImageViewerMeasure__CycleRounding(dir) {
        var i = NA_ROUNDING_STEPS.indexOf(na_roundingMm);
        if (i === -1) i = 0;
        var n = NA_ROUNDING_STEPS.length;
        na_roundingMm = NA_ROUNDING_STEPS[(i + (dir < 0 ? -1 : 1) + n) % n];
        Na__ImageViewerMeasure__StoreWrite(NA_STORE_ROUNDING, na_roundingMm);
        Na__ImageViewerMeasure__ReaimPreview();
        Na__ImageViewerMeasure__RefreshUi();
    }

    function Na__ImageViewerMeasure__LoadOptions() {
        na_orthoOn = Na__ImageViewerMeasure__StoreRead(NA_STORE_ORTHO) === '1';
        var mm = parseInt(Na__ImageViewerMeasure__StoreRead(NA_STORE_ROUNDING), 10);
        na_roundingMm = NA_ROUNDING_STEPS.indexOf(mm) !== -1 ? mm : 0;
    }

    // The second point for the cursor at (cx, cy) canvas px, with snapping,
    // ortho and rounding applied. Same shape as Snap: { hit, screen, img }.
    function Na__ImageViewerMeasure__EndPoint(cx, cy, shiftKey) {
        if (!na_pendingPoint) return Na__ImageViewerMeasure__Snap(cx, cy);
        var scale = Na__ImageViewerMeasure__Scale(na_core.getImageKey());
        var step  = na_measureMode && na_roundingMm > 0 && scale && scale.pxPerMm ? na_roundingMm : 0;
        return Na__ImageViewerMeasure__EndFrom(na_pendingPoint, cx, cy, Na__ImageViewerMeasure__OrthoHeld(shiftKey), step, scale);
    }

    // A line's free end from its fixed end `from`, for the pointer at (cx, cy).
    function Na__ImageViewerMeasure__EndFrom(from, cx, cy, ortho, step, scale) {
        var snap = Na__ImageViewerMeasure__Snap(cx, cy);
        if (!ortho && !step) return snap;

        var sx = snap.screen.x, sy = snap.screen.y;
        if (ortho) {
            var p1 = na_core.imgToScreen(from);
            if (Math.abs(cx - p1.x) >= Math.abs(cy - p1.y)) sy = p1.y;   // the free cursor picks the axis
            else                                            sx = p1.x;
        }

        var img = (sx === snap.screen.x && sy === snap.screen.y) ? { x: snap.img.x, y: snap.img.y } : na_core.screenToImg(sx, sy);
        if (step) img = Na__ImageViewerMeasure__RoundEnd(from, img, step, scale.pxPerMm);

        var screen = na_core.imgToScreen(img);
        var moved  = Math.abs(screen.x - snap.screen.x) > 0.5 || Math.abs(screen.y - snap.screen.y) > 0.5;
        return { hit: moved ? null : snap.hit, screen: screen, img: img };
    }

    // Slide b along a->b so |ab| is a whole number of steps, at least one.
    function Na__ImageViewerMeasure__RoundEnd(a, b, stepMm, pxPerMm) {
        var dx  = b.x - a.x;
        var dy  = b.y - a.y;
        var len = Math.sqrt(dx * dx + dy * dy);
        if (len <= 0) return { x: b.x, y: b.y };
        var mm  = Math.max(stepMm, Math.round(len / pxPerMm / stepMm) * stepMm);
        var k   = mm * pxPerMm / len;
        return { x: a.x + dx * k, y: a.y + dy * k };
    }

    // Ortho, Shift or Rounding changed with the pointer still: redraw the line.
    function Na__ImageViewerMeasure__ReaimPreview() {
        if (na_grabbed && na_grabbed.moved && na_lastCursor) {
            Na__ImageViewerMeasure__DragTo(na_lastCursor.x, na_lastCursor.y, na_shiftHeld);
            na_core.requestDraw();
            return;
        }
        if (!na_pendingPoint || !na_lastCursor) { na_core.requestDraw(); return; }
        var end = Na__ImageViewerMeasure__EndPoint(na_lastCursor.x, na_lastCursor.y, na_shiftHeld);
        na_previewScreen = end.screen;
        if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(end.hit);
        na_core.requestDraw();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Save Dimensioned Image
    // -------------------------------------------------------------------------
    // Saves the photo as it is marked up (dimensions, reference, counts,
    // angles, markup), at the photo's own size, beside the original:
    //   <name>__DimensionsAdded__.<ext>
    // JPEG and PNG (and WebP) keep their type; a type the browser cannot
    // write (GIF, BMP, TIFF, HEIC) is saved as PNG with a .png name. Ruby
    // writes the file. A photo read straight from disk can taint the canvas
    // in SketchUp's dialog; the picture is then drawn again from the photo's
    // bytes, which Ruby sends as a data URL.

    var NA_SAVE_TYPES = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp' };
    var na_saveWaitingFor = null;   // photo path while Ruby reads its bytes

    function Na__ImageViewerMeasure__Ext(path) {
        var m = /(\.[^.\/\\]+)$/.exec(String(path || ''));
        return m ? m[1] : '';
    }

    function Na__ImageViewerMeasure__SaveImage() {
        var path = na_core.getImageKey();
        if (!path) { Na__ImageViewerMeasure__ShowHint('Open a photo first.'); return; }
        if (!window.sketchup || typeof window.sketchup.save_dimensioned_image !== 'function') {
            Na__ImageViewerMeasure__ShowHint('Saving needs the SketchUp dialog.');
            return;
        }
        Na__ImageViewerMeasure__ShowHint('Saving the dimensioned image...');
        Na__ImageViewerMeasure__EncodeAndSend(path, null);
    }

    function Na__ImageViewerMeasure__EncodeAndSend(path, source) {
        var ext  = Na__ImageViewerMeasure__Ext(path);
        var type = NA_SAVE_TYPES[ext.toLowerCase()] || 'image/png';
        var canvas = na_core.renderExport(source);
        if (!canvas) { Na__ImageViewerMeasure__ShowHint('The photo has not loaded yet.'); return; }

        var dataUrl = null;
        try {
            dataUrl = canvas.toDataURL(type, 0.92);
        } catch (_e) {
            if (source) { Na__ImageViewerMeasure__ShowHint('Could not draw this photo to save it.'); return; }
            if (window.sketchup && typeof window.sketchup.read_image_data === 'function') {
                na_saveWaitingFor = path;
                window.sketchup.read_image_data(path);
            } else {
                Na__ImageViewerMeasure__ShowHint('Could not read this photo to save it.');
            }
            return;
        }
        // A browser that cannot write the type hands back PNG: name it so.
        var wrote = /^data:image\/(png|jpeg|webp)/.exec(dataUrl);
        var outExt = ext;
        if (!wrote || ('image/' + wrote[1]) !== type || !NA_SAVE_TYPES[ext.toLowerCase()]) outExt = '.png';
        window.sketchup.save_dimensioned_image(JSON.stringify({ path: path, ext: outExt, data: dataUrl }));
    }

    // Ruby's answer to read_image_data: { path, data } or { path, error }.
    function Na__ImageViewerMeasure__OnImageData(info) {
        if (!info || info.path !== na_saveWaitingFor) return;
        na_saveWaitingFor = null;
        if (info.error || !info.data) {
            Na__ImageViewerMeasure__ShowHint('Could not read this photo: ' + (info.error || 'no data'));
            return;
        }
        if (info.path !== na_core.getImageKey()) { Na__ImageViewerMeasure__ShowHint('Save stopped: another photo is showing.'); return; }
        var img = new Image();
        img.onload  = function() { Na__ImageViewerMeasure__EncodeAndSend(info.path, img); };
        img.onerror = function() { Na__ImageViewerMeasure__ShowHint('Could not decode this photo to save it.'); };
        img.src = info.data;
    }

    // Ruby's answer to save_dimensioned_image: { ok, path, name, replaced } or { ok:false, error }.
    function Na__ImageViewerMeasure__OnImageSaved(result) {
        if (!result) return;
        if (result.ok) {
            Na__ImageViewerMeasure__ShowHint((result.replaced ? 'Replaced ' : 'Saved ') + result.name + ' beside the photo.');
        } else {
            Na__ImageViewerMeasure__ShowHint('Not saved: ' + (result.error || 'unknown error'));
        }
    }

    window.Na__ImageViewer__OnImageData  = Na__ImageViewerMeasure__OnImageData;
    window.Na__ImageViewer__OnImageSaved = Na__ImageViewerMeasure__OnImageSaved;

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Editing Dimensions (Select)
    // -------------------------------------------------------------------------

    function Na__ImageViewerMeasure__Same(p, q) {
        return !!p && !!q && Math.abs(p.x - q.x) < 1e-6 && Math.abs(p.y - q.y) < 1e-6;
    }

    // Is this dimension the line the photo's scale was set from?
    function Na__ImageViewerMeasure__IsRef(dim, scale) {
        return !!(scale && scale.ref && Na__ImageViewerMeasure__Same(dim.a, scale.ref.a) && Na__ImageViewerMeasure__Same(dim.b, scale.ref.b));
    }

    // The grip under the pointer: an end of the selected dimension first, then
    // any dimension's end, then any dimension's line.
    function Na__ImageViewerMeasure__GripAt(cx, cy, key) {
        var ratio = na_core.getRatio();
        var reach = NA_GRIP_REACH_PX * ratio;
        var dims  = na_dimsByKey[key] || [];
        var best = null, bestD = reach;
        function tryEnds(dim, bonus) {
            ['a', 'b'].forEach(function(part) {
                var s = na_core.imgToScreen(dim[part]);
                var d = Math.sqrt((s.x - cx) * (s.x - cx) + (s.y - cy) * (s.y - cy)) - bonus;
                if (d <= bestD) { bestD = d; best = { dim: dim, part: part }; }
            });
        }
        if (na_selectedDim && dims.indexOf(na_selectedDim) !== -1) tryEnds(na_selectedDim, 2 * ratio);
        for (var i = dims.length - 1; i >= 0; i--) if (dims[i] !== na_selectedDim) tryEnds(dims[i], 0);
        if (best) return best;
        var line = Na__ImageViewerMeasure__FindDimAt(cx, cy, key);
        return line ? { dim: line, part: 'line' } : null;
    }

    // Other dimensions' ends, offered to every tool's snapping (never the
    // dimension being dragged).
    function Na__ImageViewerMeasure__ProvideSnap(cx, cy) {
        var key = na_core.getImageKey();
        if (!key) return null;
        var reach = NA_SNAP_END_PX * na_core.getRatio();
        var dims  = na_dimsByKey[key] || [];
        var best = null, bestD = reach;
        dims.forEach(function(dim) {
            if (na_grabbed && na_grabbed.dim === dim) return;
            ['a', 'b'].forEach(function(part) {
                var s = na_core.imgToScreen(dim[part]);
                var d = Math.sqrt((s.x - cx) * (s.x - cx) + (s.y - cy) * (s.y - cy));
                if (d <= bestD) { bestD = d; best = { img: { x: dim[part].x, y: dim[part].y }, screen: s, kind: 'endpoint', label: 'Dimension end' }; }
            });
        });
        return best;
    }

    function Na__ImageViewerMeasure__CanvasXY(e) {
        var r = na_core.getCanvas().getBoundingClientRect(), k = na_core.getRatio();
        return { x: (e.clientX - r.left) * k, y: (e.clientY - r.top) * k };
    }

    function Na__ImageViewerMeasure__OnMouseDown(e) {
        if (!na_selectMode || e.button !== 0) return;
        var key = na_core.getImageKey();
        if (!key) return;
        var p   = Na__ImageViewerMeasure__CanvasXY(e);
        var hit = Na__ImageViewerMeasure__GripAt(p.x, p.y, key);
        na_suppressClick = true;              // the press decides the selection, not the click after it
        na_typed = '';
        if (!hit) {
            na_selectedDim = null;
            Na__ImageViewerMeasure__RefreshUi();
            na_core.requestDraw();
            return;
        }
        e.preventDefault();
        na_selectedDim = hit.dim;
        if (hit.part !== 'line') na_lastEnd = hit.part;
        na_grabbed = {
            dim      : hit.dim,
            part     : hit.part,
            orig     : Na__ImageViewerMeasure__CloneDim(hit.dim),
            press    : { x: e.clientX, y: e.clientY },
            startImg : na_core.screenToImg(p.x, p.y),
            moved    : false,
            wasRef   : Na__ImageViewerMeasure__IsRef(hit.dim, Na__ImageViewerMeasure__Scale(key))
        };
        Na__ImageViewerMeasure__RefreshUi();
        na_core.requestDraw();
    }

    // The new place of what is held, for the pointer at (cx, cy) canvas px.
    function Na__ImageViewerMeasure__DragTo(cx, cy, shiftKey) {
        var g = na_grabbed, o = g.orig;
        var ortho = Na__ImageViewerMeasure__OrthoHeld(shiftKey);
        if (g.part === 'line') {
            var now = na_core.screenToImg(cx, cy);
            var dx = now.x - g.startImg.x, dy = now.y - g.startImg.y;
            if (ortho) {                        // move level or plumb on screen
                var s0 = na_core.imgToScreen(g.startImg);
                var sx = cx, sy = cy;
                if (Math.abs(cx - s0.x) >= Math.abs(cy - s0.y)) sy = s0.y; else sx = s0.x;
                var held = na_core.screenToImg(sx, sy);
                dx = held.x - g.startImg.x; dy = held.y - g.startImg.y;
            }
            g.dim.a = { x: o.a.x + dx, y: o.a.y + dy };
            g.dim.b = { x: o.b.x + dx, y: o.b.y + dy };
            if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(null);
            return;
        }
        var fixed = g.part === 'a' ? o.b : o.a;
        var scale = Na__ImageViewerMeasure__Scale(na_core.getImageKey());
        var step  = !g.wasRef && na_roundingMm > 0 && scale && scale.pxPerMm ? na_roundingMm : 0;
        var end   = Na__ImageViewerMeasure__EndFrom(fixed, cx, cy, ortho, step, scale);
        g.dim[g.part] = end.img;
        if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(end.hit);
    }

    function Na__ImageViewerMeasure__OnMouseMoveDrag(e) {
        var key = na_core.getImageKey();
        if (!na_grabbed) {
            if (!na_selectMode || e.target !== na_core.getCanvas() || !key) return;
            var q   = Na__ImageViewerMeasure__CanvasXY(e);
            var hov = Na__ImageViewerMeasure__GripAt(q.x, q.y, key);
            var was = na_hoverGrip;
            na_hoverGrip = hov;
            Na__ImageViewerMeasure__GripCursor(hov ? (hov.part === 'line' ? 'move' : 'grip') : '');
            if ((was && (!hov || was.dim !== hov.dim || was.part !== hov.part)) || (!was && hov)) na_core.requestDraw();
            return;
        }
        var dist = Math.sqrt((e.clientX - na_grabbed.press.x) * (e.clientX - na_grabbed.press.x) + (e.clientY - na_grabbed.press.y) * (e.clientY - na_grabbed.press.y));
        if (!na_grabbed.moved && dist < NA_DRAG_START_PX) return;
        na_grabbed.moved = true;
        var p = Na__ImageViewerMeasure__CanvasXY(e);
        na_lastCursor = p;
        na_shiftHeld  = !!e.shiftKey;
        Na__ImageViewerMeasure__DragTo(p.x, p.y, na_shiftHeld);
        Na__ImageViewerMeasure__ShowHint(Na__ImageViewerMeasure__DragHint());
        na_core.requestDraw();
    }

    function Na__ImageViewerMeasure__DragHint() {
        var g = na_grabbed;
        var scale = Na__ImageViewerMeasure__Scale(na_core.getImageKey());
        if (g.wasRef && g.part !== 'line') return 'Moving the reference end: the photo is re-scaled to keep ' + Na__ImageViewerMeasure__FormatByUnit(scale.ref.mm, scale.unit) + '. Esc puts it back.';
        return (g.part === 'line' ? 'Moving the dimension: ' : 'Moving the end: ') + Na__ImageViewerMeasure__DimLabel(g.dim, scale)
            + Na__ImageViewerMeasure__OptionsHint() + ' Esc puts it back.';
    }

    function Na__ImageViewerMeasure__OnMouseUpDrag() {
        var g = na_grabbed;
        if (!g) return;
        na_grabbed = null;
        if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(null);
        if (!g.moved) { Na__ImageViewerMeasure__RefreshUi(); na_core.requestDraw(); return; }
        Na__ImageViewerMeasure__Commit(g.dim, g.orig, Na__ImageViewerMeasure__CloneDim(g.dim), g.wasRef);
    }

    // One undo step: the history must hold the dimension as it was before the edit.
    function Na__ImageViewerMeasure__Commit(dim, before, after, wasRef) {
        var key = na_core.getImageKey();
        dim.a = before.a; dim.b = before.b;
        Na__ImageViewerMeasure__PushUndo();
        dim.a = after.a;  dim.b = after.b;
        var scale = na_scaleByKey[key];
        if (wasRef && scale && scale.ref) {
            var px = Na__ImageViewerMeasure__PixelLength(dim);
            if (px > 0) scale.pxPerMm = px / scale.ref.mm;
            scale.ref.a = { x: dim.a.x, y: dim.a.y };
            scale.ref.b = { x: dim.b.x, y: dim.b.y };
        }
        Na__ImageViewerMeasure__Persist(key);
        Na__ImageViewerMeasure__RefreshUi();
        if (wasRef && scale) Na__ImageViewerMeasure__ShowHint('Reference moved: the photo is re-scaled to keep ' + Na__ImageViewerMeasure__FormatByUnit(scale.ref.mm, scale.unit) + '.');
        na_core.requestDraw();
    }

    function Na__ImageViewerMeasure__CancelDrag() {
        var g = na_grabbed;
        if (!g) return false;
        na_grabbed = null;
        g.dim.a = g.orig.a;
        g.dim.b = g.orig.b;
        if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(null);
        Na__ImageViewerMeasure__RefreshUi();
        na_core.requestDraw();
        return true;
    }

    // A typed length for the selected dimension: digits, a point, then mm, cm or m.
    function Na__ImageViewerMeasure__OnKeyCapture(e) {
        if (!na_selectMode || !na_selectedDim || na_grabbed) return;
        var tag = e.target && e.target.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        var k = e.key;
        var takes = /^[0-9.]$/.test(k) || (na_typed && /^[cm]$/i.test(k)) || (na_typed && (k === 'Backspace' || k === 'Enter' || k === 'Escape'));
        if (!takes) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        if (k === 'Escape')         na_typed = '';
        else if (k === 'Backspace') na_typed = na_typed.slice(0, -1);
        else if (k === 'Enter')     { Na__ImageViewerMeasure__ApplyTyped(); return; }
        else                        na_typed += k.toLowerCase();
        Na__ImageViewerMeasure__RefreshUi();
    }

    function Na__ImageViewerMeasure__ApplyTyped() {
        var key    = na_core.getImageKey();
        var scale  = Na__ImageViewerMeasure__Scale(key);
        var parsed = Na__ImageViewerMeasure__ParseReference(na_typed);
        var dim    = na_selectedDim;
        if (!parsed) { Na__ImageViewerMeasure__ShowHint('Could not read "' + na_typed + '". Try 1250, 1.25m or 125cm.'); return; }
        if (!scale || !scale.pxPerMm) { na_typed = ''; Na__ImageViewerMeasure__ShowHint('Set a reference first: a typed length needs the photo\'s scale.'); return; }
        var px = Na__ImageViewerMeasure__PixelLength(dim);
        if (!(px > 0)) { na_typed = ''; Na__ImageViewerMeasure__ShowHint('This dimension has no length to set.'); return; }
        var wasRef = Na__ImageViewerMeasure__IsRef(dim, scale);
        var before = Na__ImageViewerMeasure__CloneDim(dim);
        var after  = Na__ImageViewerMeasure__CloneDim(dim);
        if (wasRef) {
            // The reference's own length is what the scale comes from: a typed
            // value re-states its known length rather than moving it.
            Na__ImageViewerMeasure__PushUndo();
            scale.ref.mm  = parsed.mm;
            scale.unit    = parsed.unit;
            scale.pxPerMm = px / parsed.mm;
            na_typed = '';
            Na__ImageViewerMeasure__Persist(key);
            Na__ImageViewerMeasure__RefreshUi();
            Na__ImageViewerMeasure__ShowHint('Reference length set to ' + Na__ImageViewerMeasure__FormatByUnit(parsed.mm, parsed.unit) + ': the photo is re-scaled.');
            na_core.requestDraw();
            return;
        }
        var fixed = na_lastEnd === 'a' ? before.b : before.a;
        var moving = na_lastEnd === 'a' ? before.a : before.b;
        var f = parsed.mm * scale.pxPerMm / px;
        after[na_lastEnd] = { x: fixed.x + (moving.x - fixed.x) * f, y: fixed.y + (moving.y - fixed.y) * f };
        na_typed = '';
        Na__ImageViewerMeasure__Commit(dim, before, after, false);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Hint Text
    // -------------------------------------------------------------------------

    function Na__ImageViewerMeasure__ShowHint(text) {
        if (!na_refHint) return;
        na_refHint.textContent = text;
        na_refHint.classList.add('naImageViewer__MeasureHint--visible');
    }

    function Na__ImageViewerMeasure__HideHint() {
        if (na_refHint) na_refHint.classList.remove('naImageViewer__MeasureHint--visible');
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Clear
    // -------------------------------------------------------------------------

    function Na__ImageViewerMeasure__ClearCurrent() {
        var key = na_core.getImageKey();
        if (!key) return;
        Na__ImageViewerMeasure__PushUndo();
        delete na_dimsByKey[key];
        delete na_scaleByKey[key];
        delete na_storedByKey[key];
        // Protractors go too, in this same undo step (the snapshot above holds them).
        if (window.Na__ImageViewer__Protractor) window.Na__ImageViewer__Protractor.clearForUndo();
        Na__ImageViewerMeasure__Persist(key);
        na_refPendingDim = null;
        na_selectedDim   = null;
        Na__ImageViewerMeasure__CancelPending();
        Na__ImageViewerMeasure__HideRefOverlay(true);
        Na__ImageViewerMeasure__RefreshUi();
        Na__ImageViewerMeasure__ShowHint('Dimensions cleared for this image.');
        na_core.requestDraw();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Delete Selected
    // -------------------------------------------------------------------------

    function Na__ImageViewerMeasure__DeleteSelected() {
        if (!na_selectedDim) return;
        var key  = na_core.getImageKey();
        var dims = Na__ImageViewerMeasure__Dims(key);
        var pos  = dims.indexOf(na_selectedDim);
        if (pos === -1) return;

        Na__ImageViewerMeasure__PushUndo();
        dims.splice(pos, 1);
        na_selectedDim = null;
        Na__ImageViewerMeasure__Persist(key);

        Na__ImageViewerMeasure__RefreshUi();
        Na__ImageViewerMeasure__ShowHint('Dimension deleted.');
        na_core.requestDraw();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Canvas Interaction
    // -------------------------------------------------------------------------

    function Na__ImageViewerMeasure__OnCanvasClick(e) {
        var key = na_core.getImageKey();
        if (!key) return;

        if (na_selectMode) {
            if (na_suppressClick) { na_suppressClick = false; return; }
            var ratio = na_core.getRatio();
            na_selectedDim = Na__ImageViewerMeasure__FindDimAt(e.offsetX * ratio, e.offsetY * ratio, key);
            Na__ImageViewerMeasure__RefreshUi();
            na_core.requestDraw();
            return;
        }

        if (!na_measureMode && !na_refMode) return;
        if (na_refMode && na_refPendingDim) return; // waiting on the value overlay

        var pxRatio = na_core.getRatio();
        var snap    = Na__ImageViewerMeasure__EndPoint(e.offsetX * pxRatio, e.offsetY * pxRatio, e.shiftKey);
        var imgPt   = snap.img;

        if (!na_pendingPoint) {
            na_pendingPoint  = imgPt;
            na_previewScreen = snap.screen;
            na_core.requestDraw();
            return;
        }

        var dim = { a: na_pendingPoint, b: imgPt };
        Na__ImageViewerMeasure__CancelPending();

        if (na_refMode) {
            na_refPendingDim = dim;
            Na__ImageViewerMeasure__ShowRefOverlay();
        } else {
            Na__ImageViewerMeasure__PushUndo();
            Na__ImageViewerMeasure__Dims(key).push(dim);
            Na__ImageViewerMeasure__Persist(key);
            Na__ImageViewerMeasure__SyncActionButtons();
        }
        na_core.requestDraw();
    }

    // Points snap to what other tools offer through the Core: guide
    // intersections, endpoints, a point on a guide (Perspective Angle guides).
    function Na__ImageViewerMeasure__Snap(cx, cy) {
        var hit = typeof na_core.snap === 'function' ? na_core.snap(cx, cy) : null;
        return {
            hit    : hit,
            screen : hit ? { x: hit.screen.x, y: hit.screen.y } : { x: cx, y: cy },
            img    : hit ? { x: hit.img.x, y: hit.img.y } : na_core.screenToImg(cx, cy)
        };
    }

    function Na__ImageViewerMeasure__OnCanvasMove(e) {
        if (!na_measureMode && !na_refMode) return;
        if (na_refMode && na_refPendingDim) return; // waiting on the value overlay
        var ratio   = na_core.getRatio();
        na_lastCursor = { x: e.offsetX * ratio, y: e.offsetY * ratio };
        na_shiftHeld  = !!e.shiftKey;
        var snap    = Na__ImageViewerMeasure__EndPoint(na_lastCursor.x, na_lastCursor.y, na_shiftHeld);
        var hadSnap = typeof na_core.getSnapMarker === 'function' && !!na_core.getSnapMarker();
        if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(snap.hit);
        if (na_pendingPoint) na_previewScreen = snap.screen;
        na_cursorScreen = snap.screen;
        if (na_pendingPoint || snap.hit || hadSnap || Na__ImageViewerMeasure__OrthoHeld(na_shiftHeld)) na_core.requestDraw();
    }

    // Ctrl+Z / Ctrl+Y are handled by the Core's shared history.
    function Na__ImageViewerMeasure__OnKeyDown(e) {
        var tag = e.target && e.target.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return; // leave form fields alone

        // Ctrl+S: save this photo with its dimensions beside the original.
        if ((e.ctrlKey || e.metaKey) && !e.altKey && (e.key === 's' || e.key === 'S')) {
            e.preventDefault();
            Na__ImageViewerMeasure__SaveImage();
            return;
        }

        // F8: Ortho on / off, as in AutoCAD and the TrueVision Layout Editor.
        if (e.key === 'F8') {
            e.preventDefault();
            if (!e.repeat) Na__ImageViewerMeasure__SetOrtho(!na_orthoOn);
            return;
        }

        // Shift: Ortho's temporary override, the line follows at once.
        if (e.key === 'Shift') {
            if (!na_shiftHeld) { na_shiftHeld = true; Na__ImageViewerMeasure__ReaimPreview(); }
            return;
        }

        // D: a new dimension. Starts the Dimension tool, or drops a half-drawn one.
        if ((e.key === 'd' || e.key === 'D') && !e.ctrlKey && !e.metaKey && !e.altKey) {
            e.preventDefault();
            if (!na_measureMode) Na__ImageViewerMeasure__SetMeasureMode(true);
            else { Na__ImageViewerMeasure__CancelPending(); na_core.requestDraw(); }
            return;
        }

        if ((e.key === 'Delete' || e.key === 'Backspace') && na_selectedDim) {
            e.preventDefault();
            Na__ImageViewerMeasure__DeleteSelected();
            return;
        }

        if (e.key !== 'Escape') return;
        if (Na__ImageViewerMeasure__CancelDrag()) {
            Na__ImageViewerMeasure__ShowHint('Put back.');
            return;
        }
        if (na_pendingPoint) {
            Na__ImageViewerMeasure__CancelPending();
            na_core.requestDraw();
        } else if (na_refPendingDim) {
            Na__ImageViewerMeasure__CancelRef();
        } else if (na_selectedDim) {
            na_selectedDim = null;
            Na__ImageViewerMeasure__RefreshUi();
            na_core.requestDraw();
        } else if (na_measureMode || na_refMode || na_selectMode) {
            Na__ImageViewerMeasure__ExitAllModes();
        }
    }

    function Na__ImageViewerMeasure__OnKeyUp(e) {
        if (e.key !== 'Shift' || !na_shiftHeld) return;
        na_shiftHeld = false;
        Na__ImageViewerMeasure__ReaimPreview();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Initialisation
    // -------------------------------------------------------------------------

    function Na__ImageViewerMeasure__Init() {
        na_btnMeasure        = Na__ImageViewerMeasure__El('naImageViewer_btnMeasure');
        na_btnRef            = Na__ImageViewerMeasure__El('naImageViewer_btnSetRef');
        na_btnSelect         = Na__ImageViewerMeasure__El('naImageViewer_btnSelect');
        na_btnDeleteSelected = Na__ImageViewerMeasure__El('naImageViewer_btnDeleteSelected');
        na_btnClear          = Na__ImageViewerMeasure__El('naImageViewer_btnClearDims');
        na_refOverlay        = Na__ImageViewerMeasure__El('naImageViewer_refOverlay');
        na_refInput          = Na__ImageViewerMeasure__El('naImageViewer_refInput');
        na_refHint           = Na__ImageViewerMeasure__El('naImageViewer_measureHint');
        na_refOk             = Na__ImageViewerMeasure__El('naImageViewer_refOk');
        na_refCancel         = Na__ImageViewerMeasure__El('naImageViewer_refCancel');
        na_btnOrtho          = Na__ImageViewerMeasure__El('naImageViewer_btnOrtho');
        na_btnRounding       = Na__ImageViewerMeasure__El('naImageViewer_btnRounding');
        na_roundingLabel     = Na__ImageViewerMeasure__El('naImageViewer_roundingLabel');
        na_optionsDivider    = Na__ImageViewerMeasure__El('naImageViewer_toolOptionsDivider');
        na_optionsGroup      = Na__ImageViewerMeasure__El('naImageViewer_toolOptions');
        na_btnSaveImage      = Na__ImageViewerMeasure__El('naImageViewer_btnSaveImage');
        Na__ImageViewerMeasure__LoadOptions();

        na_core.registerOverlay(Na__ImageViewerMeasure__Render);
        na_core.registerHistory('measure', {
            snapshot : Na__ImageViewerMeasure__Snapshot,
            restore  : Na__ImageViewerMeasure__RestoreSnapshot
        });
        na_core.onHistoryChanged(Na__ImageViewerMeasure__OnHistoryChanged);
        na_core.onImageChanged(function() {
            var key  = na_core.getImageKey();
            var size = na_core.getImageSize();
            if (key && size && size.w) na_sizeByKey[key] = { w: size.w, h: size.h };
            Na__ImageViewerMeasure__Materialise(key);
            na_grabbed     = null;
            na_hoverGrip   = null;
            na_typed       = '';
            na_selectedDim = null;
            Na__ImageViewerMeasure__CancelPending();
            na_refPendingDim = null;
            Na__ImageViewerMeasure__HideRefOverlay(true);
            Na__ImageViewerMeasure__RefreshUi();
        });

        var canvas = na_core.getCanvas();
        if (canvas) {
            canvas.addEventListener('click', Na__ImageViewerMeasure__OnCanvasClick);
            canvas.addEventListener('mousemove', Na__ImageViewerMeasure__OnCanvasMove);
            canvas.addEventListener('mousedown', Na__ImageViewerMeasure__OnMouseDown);
            canvas.addEventListener('mouseleave', function() {
                if (!na_cursorScreen || na_pendingPoint) return;
                na_cursorScreen = null;
                na_core.requestDraw();
            });
        }
        window.addEventListener('mousemove', Na__ImageViewerMeasure__OnMouseMoveDrag);
        window.addEventListener('mouseup', Na__ImageViewerMeasure__OnMouseUpDrag);
        window.addEventListener('keydown', Na__ImageViewerMeasure__OnKeyCapture, true);
        if (typeof na_core.registerSnap === 'function') na_core.registerSnap(Na__ImageViewerMeasure__ProvideSnap);
        window.addEventListener('keydown', Na__ImageViewerMeasure__OnKeyDown);
        window.addEventListener('keyup', Na__ImageViewerMeasure__OnKeyUp);
        window.addEventListener('blur', function() { na_shiftHeld = false; });

        if (na_btnSaveImage) na_btnSaveImage.addEventListener('click', Na__ImageViewerMeasure__SaveImage);

        if (na_btnOrtho) na_btnOrtho.addEventListener('click', function() {
            Na__ImageViewerMeasure__SetOrtho(!na_orthoOn);
        });
        if (na_btnRounding) {
            na_btnRounding.addEventListener('click', function() { Na__ImageViewerMeasure__CycleRounding(1); });
            na_btnRounding.addEventListener('contextmenu', function(ev) {
                ev.preventDefault();
                Na__ImageViewerMeasure__CycleRounding(-1);
            });
        }

        if (na_btnMeasure) na_btnMeasure.addEventListener('click', function() {
            Na__ImageViewerMeasure__SetMeasureMode(!na_measureMode);
        });
        if (na_btnRef) na_btnRef.addEventListener('click', function() {
            Na__ImageViewerMeasure__SetRefMode(!na_refMode);
        });
        if (na_btnSelect) na_btnSelect.addEventListener('click', function() {
            Na__ImageViewerMeasure__SetSelectMode(!na_selectMode);
        });
        if (na_btnDeleteSelected) na_btnDeleteSelected.addEventListener('click', Na__ImageViewerMeasure__DeleteSelected);
        if (na_btnClear) na_btnClear.addEventListener('click', Na__ImageViewerMeasure__ClearCurrent);

        if (na_refOk)     na_refOk.addEventListener('click', Na__ImageViewerMeasure__ConfirmRef);
        if (na_refCancel) na_refCancel.addEventListener('click', Na__ImageViewerMeasure__CancelRef);
        if (na_refInput) {
            na_refInput.addEventListener('keydown', function(ev) {
                if (ev.key === 'Enter')       { ev.preventDefault(); Na__ImageViewerMeasure__ConfirmRef(); }
                else if (ev.key === 'Escape') { ev.preventDefault(); Na__ImageViewerMeasure__CancelRef(); }
                ev.stopPropagation();
            });
        }

        Na__ImageViewerMeasure__RefreshUi();
    }

    // Read-only view for the other overlay features: the current photo's
    // reference scale, or null until Set Reference has given it one.
    window.Na__ImageViewer__Measure = {
        getScale: function() {
            return Na__ImageViewerMeasure__CloneScale(Na__ImageViewerMeasure__Scale(na_core.getImageKey()));
        },
        getOptions: function() {
            return { ortho: na_orthoOn, roundingMm: na_roundingMm };
        },
        getSaved: function() { return na_lastSaved; },
        getSelected: function() { return na_selectedDim ? Na__ImageViewerMeasure__CloneDim(na_selectedDim) : null; },
        getTyped: function() { return na_typed; },
        getGuide: function() { var g = Na__ImageViewerMeasure__GuidePoint(); return g ? { x: g.x, y: g.y } : null; },
        getDims: function() {
            return (na_dimsByKey[na_core.getImageKey()] || []).map(Na__ImageViewerMeasure__CloneDim);
        }
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na__ImageViewerMeasure__Init);
    } else {
        Na__ImageViewerMeasure__Init();
    }

    // endregion ---------------------------------------------------------------

    // =============================================================================
    // END OF FILE
    // =============================================================================

})();
