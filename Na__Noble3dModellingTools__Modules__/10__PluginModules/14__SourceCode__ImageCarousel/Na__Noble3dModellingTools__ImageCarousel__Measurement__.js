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
    var na_scaleByKey    = {};    // image key -> { pxPerMm:Number, unit:'mm'|'cm'|'m' }
    var na_measureMode   = false;
    var na_refMode       = false;
    var na_selectMode    = false;
    var na_pendingPoint  = null;  // first click, image space, while placing a dim
    var na_previewScreen = null;  // live cursor pos, canvas px, for rubber-band
    var na_refPendingDim = null;  // reference line awaiting a typed known value
    var na_selectedDim   = null;  // reference to the currently selected dim object

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
    var NA_HANDLE_PX      = 4;
    var NA_HIT_TOLERANCE_PX = 9;

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

    function Na__ImageViewerMeasure__Snapshot(key) {
        var dims  = na_dimsByKey[key] || [];
        var scale = na_scaleByKey[key];
        return {
            dims  : dims.map(Na__ImageViewerMeasure__CloneDim),
            scale : scale ? { pxPerMm: scale.pxPerMm, unit: scale.unit } : null
        };
    }

    function Na__ImageViewerMeasure__RestoreSnapshot(key, snap) {
        if (!snap) { delete na_dimsByKey[key]; delete na_scaleByKey[key]; return; }
        na_dimsByKey[key] = snap.dims.map(Na__ImageViewerMeasure__CloneDim);
        if (snap.scale) na_scaleByKey[key] = { pxPerMm: snap.scale.pxPerMm, unit: snap.scale.unit };
        else            delete na_scaleByKey[key];
    }

    function Na__ImageViewerMeasure__PushUndo() {
        na_core.pushHistory();
    }

    function Na__ImageViewerMeasure__OnHistoryChanged(reason) {
        if (reason !== 'undo' && reason !== 'redo') return;
        na_selectedDim   = null;
        na_refPendingDim = null;
        Na__ImageViewerMeasure__HideRefOverlay(true);
        Na__ImageViewerMeasure__CancelPending();
        Na__ImageViewerMeasure__RefreshUi();
    }

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

        if (na_refPendingDim) {
            Na__ImageViewerMeasure__DrawDim(ctx, ratio, na_refPendingDim, NA_REF_COLOR,
                Na__ImageViewerMeasure__DimLabel(na_refPendingDim, scale), false);
        }

        if (na_pendingPoint && na_previewScreen) {
            Na__ImageViewerMeasure__DrawPreview(ctx, ratio, scale);
        }
    }

    function Na__ImageViewerMeasure__DrawDim(ctx, ratio, dim, color, label, isSelected) {
        var p1 = na_core.imgToScreen(dim.a);
        var p2 = na_core.imgToScreen(dim.b);
        Na__ImageViewerMeasure__StrokeLine(ctx, ratio, p1, p2, color, false, isSelected);
        Na__ImageViewerMeasure__DrawTick(ctx, ratio, p1, p2, color);
        Na__ImageViewerMeasure__DrawTick(ctx, ratio, p2, p1, color);
        if (isSelected) {
            Na__ImageViewerMeasure__DrawHandle(ctx, ratio, p1, color);
            Na__ImageViewerMeasure__DrawHandle(ctx, ratio, p2, color);
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

    function Na__ImageViewerMeasure__DrawHandle(ctx, ratio, pt, color) {
        ctx.save();
        ctx.fillStyle   = color;
        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth   = 1 * ratio;
        ctx.beginPath();
        ctx.arc(pt.x, pt.y, NA_HANDLE_PX * ratio, 0, Math.PI * 2);
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
        na_pendingPoint  = null;
        na_previewScreen = null;
    }

    function Na__ImageViewerMeasure__SetMeasureMode(on) {
        na_measureMode = on;
        if (on) {
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

    function Na__ImageViewerMeasure__ExitAllModes() {
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

        if (na_measureMode) {
            Na__ImageViewerMeasure__ShowHint(scale
                ? 'Measure: click two points. Esc to stop.'
                : 'Measure (no scale yet - shows units). Click two points. Esc to stop.');
        } else if (na_refMode && !na_refPendingDim) {
            Na__ImageViewerMeasure__ShowHint('Set Reference: click the two ends of a known length.');
        } else if (na_selectMode) {
            Na__ImageViewerMeasure__ShowHint(na_selectedDim
                ? 'Selected. Press Delete or click Delete to remove. Esc to deselect.'
                : 'Select: click a dimension line to select it. Esc to stop.');
        } else if (!na_refPendingDim) {
            Na__ImageViewerMeasure__HideHint();
        }
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
        na_scaleByKey[key] = { pxPerMm: px / parsed.mm, unit: parsed.unit };
        Na__ImageViewerMeasure__Dims(key).push(na_refPendingDim);
        na_refPendingDim = null;

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
            var ratio = na_core.getRatio();
            na_selectedDim = Na__ImageViewerMeasure__FindDimAt(e.offsetX * ratio, e.offsetY * ratio, key);
            Na__ImageViewerMeasure__RefreshUi();
            na_core.requestDraw();
            return;
        }

        if (!na_measureMode && !na_refMode) return;
        if (na_refMode && na_refPendingDim) return; // waiting on the value overlay

        var pxRatio = na_core.getRatio();
        var snap    = Na__ImageViewerMeasure__Snap(e.offsetX * pxRatio, e.offsetY * pxRatio);
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
        var snap    = Na__ImageViewerMeasure__Snap(e.offsetX * ratio, e.offsetY * ratio);
        var hadSnap = typeof na_core.getSnapMarker === 'function' && !!na_core.getSnapMarker();
        if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(snap.hit);
        if (na_pendingPoint) na_previewScreen = snap.screen;
        if (na_pendingPoint || snap.hit || hadSnap) na_core.requestDraw();
    }

    // Ctrl+Z / Ctrl+Y are handled by the Core's shared history.
    function Na__ImageViewerMeasure__OnKeyDown(e) {
        var tag = e.target && e.target.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return; // leave form fields alone

        if ((e.key === 'Delete' || e.key === 'Backspace') && na_selectedDim) {
            e.preventDefault();
            Na__ImageViewerMeasure__DeleteSelected();
            return;
        }

        if (e.key !== 'Escape') return;
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

        na_core.registerOverlay(Na__ImageViewerMeasure__Render);
        na_core.registerHistory('measure', {
            snapshot : Na__ImageViewerMeasure__Snapshot,
            restore  : Na__ImageViewerMeasure__RestoreSnapshot
        });
        na_core.onHistoryChanged(Na__ImageViewerMeasure__OnHistoryChanged);
        na_core.onImageChanged(function() {
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
        }
        window.addEventListener('keydown', Na__ImageViewerMeasure__OnKeyDown);

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
