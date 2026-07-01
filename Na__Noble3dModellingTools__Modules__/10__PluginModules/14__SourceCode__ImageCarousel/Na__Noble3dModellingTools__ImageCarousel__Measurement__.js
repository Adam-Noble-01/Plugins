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
//              state, parsing, drawing, and interaction live here.
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
    // REGION | Feature State (per session, keyed by image index)
    // -------------------------------------------------------------------------

    var na_dimsByIndex   = {};    // index -> [ { a:{x,y}, b:{x,y} } ] image space
    var na_scaleByIndex  = {};    // index -> { pxPerMm:Number, unit:'mm'|'cm'|'m' }
    var na_measureMode   = false;
    var na_refMode       = false;
    var na_selectMode    = false;
    var na_pendingPoint  = null;  // first click, image space, while placing a dim
    var na_previewScreen = null;  // live cursor pos, canvas px, for rubber-band
    var na_refPendingDim = null;  // reference line awaiting a typed known value
    var na_selectedDim   = null;  // reference to the currently selected dim object

    // History (undo/redo), kept per image index as stacks of full state snapshots.
    var na_undoByIndex = {};
    var na_redoByIndex = {};
    var NA_UNDO_LIMIT   = 50;

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
    var na_btnUndo           = null;
    var na_btnRedo           = null;
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

    function Na__ImageViewerMeasure__Dims(idx) {
        if (!na_dimsByIndex[idx]) na_dimsByIndex[idx] = [];
        return na_dimsByIndex[idx];
    }

    function Na__ImageViewerMeasure__Scale(idx) {
        return na_scaleByIndex[idx] || null;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | History (Undo / Redo)
    // -------------------------------------------------------------------------
    // Each undo-able action pushes a full snapshot of the current image's dims
    // + scale onto that image's undo stack before mutating. Undo/redo replay
    // snapshots rather than inverse operations, which keeps every action
    // (add, delete, clear, set-reference) correct with one code path.

    function Na__ImageViewerMeasure__CloneDim(dim) {
        return { a: { x: dim.a.x, y: dim.a.y }, b: { x: dim.b.x, y: dim.b.y } };
    }

    function Na__ImageViewerMeasure__Snapshot(idx) {
        var dims  = na_dimsByIndex[idx] || [];
        var scale = na_scaleByIndex[idx];
        return {
            dims  : dims.map(Na__ImageViewerMeasure__CloneDim),
            scale : scale ? { pxPerMm: scale.pxPerMm, unit: scale.unit } : null
        };
    }

    function Na__ImageViewerMeasure__RestoreSnapshot(idx, snap) {
        na_dimsByIndex[idx] = snap.dims.map(Na__ImageViewerMeasure__CloneDim);
        if (snap.scale) na_scaleByIndex[idx] = { pxPerMm: snap.scale.pxPerMm, unit: snap.scale.unit };
        else            delete na_scaleByIndex[idx];
    }

    function Na__ImageViewerMeasure__PushUndo(idx) {
        if (!na_undoByIndex[idx]) na_undoByIndex[idx] = [];
        na_undoByIndex[idx].push(Na__ImageViewerMeasure__Snapshot(idx));
        if (na_undoByIndex[idx].length > NA_UNDO_LIMIT) na_undoByIndex[idx].shift();
        na_redoByIndex[idx] = []; // a fresh action invalidates the redo history
    }

    function Na__ImageViewerMeasure__Undo() {
        var idx   = na_core.getIndex();
        var stack = na_undoByIndex[idx];
        if (idx < 0 || !stack || !stack.length) return;

        if (!na_redoByIndex[idx]) na_redoByIndex[idx] = [];
        na_redoByIndex[idx].push(Na__ImageViewerMeasure__Snapshot(idx));
        Na__ImageViewerMeasure__RestoreSnapshot(idx, stack.pop());

        na_selectedDim = null;
        Na__ImageViewerMeasure__RefreshUi();
        na_core.requestDraw();
    }

    function Na__ImageViewerMeasure__Redo() {
        var idx   = na_core.getIndex();
        var stack = na_redoByIndex[idx];
        if (idx < 0 || !stack || !stack.length) return;

        if (!na_undoByIndex[idx]) na_undoByIndex[idx] = [];
        na_undoByIndex[idx].push(Na__ImageViewerMeasure__Snapshot(idx));
        Na__ImageViewerMeasure__RestoreSnapshot(idx, stack.pop());

        na_selectedDim = null;
        Na__ImageViewerMeasure__RefreshUi();
        na_core.requestDraw();
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

    function Na__ImageViewerMeasure__FindDimAt(cx, cy, idx) {
        var ratio     = na_core.getRatio();
        var tolerance = NA_HIT_TOLERANCE_PX * ratio;
        var dims      = na_dimsByIndex[idx] || [];
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
        var idx   = na_core.getIndex();
        if (idx < 0) return;

        var scale = Na__ImageViewerMeasure__Scale(idx);
        var dims  = na_dimsByIndex[idx] || [];

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

        if (na_btnMeasure) na_btnMeasure.classList.toggle('naImageViewer__Btn--active', na_measureMode);
        if (na_btnRef)     na_btnRef.classList.toggle('naImageViewer__Btn--active', na_refMode);
        if (na_btnSelect)  na_btnSelect.classList.toggle('naImageViewer__Btn--active', na_selectMode);

        var scale = Na__ImageViewerMeasure__Scale(na_core.getIndex());
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

    function Na__ImageViewerMeasure__SyncActionButtons() {
        var idx       = na_core.getIndex();
        var undoStack = na_undoByIndex[idx];
        var redoStack = na_redoByIndex[idx];
        if (na_btnUndo)           na_btnUndo.disabled = !undoStack || !undoStack.length;
        if (na_btnRedo)           na_btnRedo.disabled = !redoStack || !redoStack.length;
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

        var idx = na_core.getIndex();
        Na__ImageViewerMeasure__PushUndo(idx);
        na_scaleByIndex[idx] = { pxPerMm: px / parsed.mm, unit: parsed.unit };
        Na__ImageViewerMeasure__Dims(idx).push(na_refPendingDim);
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
        var idx = na_core.getIndex();
        if (idx < 0) return;
        Na__ImageViewerMeasure__PushUndo(idx);
        delete na_dimsByIndex[idx];
        delete na_scaleByIndex[idx];
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
        var idx  = na_core.getIndex();
        var dims = Na__ImageViewerMeasure__Dims(idx);
        var pos  = dims.indexOf(na_selectedDim);
        if (pos === -1) return;

        Na__ImageViewerMeasure__PushUndo(idx);
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
        var idx = na_core.getIndex();
        if (idx < 0) return;

        if (na_selectMode) {
            var ratio = na_core.getRatio();
            na_selectedDim = Na__ImageViewerMeasure__FindDimAt(e.offsetX * ratio, e.offsetY * ratio, idx);
            Na__ImageViewerMeasure__RefreshUi();
            na_core.requestDraw();
            return;
        }

        if (!na_measureMode && !na_refMode) return;
        if (na_refMode && na_refPendingDim) return; // waiting on the value overlay

        var pxRatio = na_core.getRatio();
        var cx      = e.offsetX * pxRatio;
        var cy      = e.offsetY * pxRatio;
        var imgPt   = na_core.screenToImg(cx, cy);

        if (!na_pendingPoint) {
            na_pendingPoint  = imgPt;
            na_previewScreen = { x: cx, y: cy };
            na_core.requestDraw();
            return;
        }

        var dim = { a: na_pendingPoint, b: imgPt };
        Na__ImageViewerMeasure__CancelPending();

        if (na_refMode) {
            na_refPendingDim = dim;
            Na__ImageViewerMeasure__ShowRefOverlay();
        } else {
            Na__ImageViewerMeasure__PushUndo(idx);
            Na__ImageViewerMeasure__Dims(idx).push(dim);
            Na__ImageViewerMeasure__SyncActionButtons();
        }
        na_core.requestDraw();
    }

    function Na__ImageViewerMeasure__OnCanvasMove(e) {
        if ((!na_measureMode && !na_refMode) || !na_pendingPoint) return;
        var ratio = na_core.getRatio();
        na_previewScreen = { x: e.offsetX * ratio, y: e.offsetY * ratio };
        na_core.requestDraw();
    }

    function Na__ImageViewerMeasure__OnKeyDown(e) {
        var tag = e.target && e.target.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA') return; // leave text fields alone

        var ctrlOrCmd = e.ctrlKey || e.metaKey;
        var key       = e.key ? e.key.toLowerCase() : '';

        if (ctrlOrCmd && key === 'z' && !e.shiftKey) {
            e.preventDefault();
            Na__ImageViewerMeasure__Undo();
            return;
        }
        if (ctrlOrCmd && (key === 'y' || (key === 'z' && e.shiftKey))) {
            e.preventDefault();
            Na__ImageViewerMeasure__Redo();
            return;
        }
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
        na_btnUndo           = Na__ImageViewerMeasure__El('naImageViewer_btnUndo');
        na_btnRedo           = Na__ImageViewerMeasure__El('naImageViewer_btnRedo');
        na_btnClear          = Na__ImageViewerMeasure__El('naImageViewer_btnClearDims');
        na_refOverlay        = Na__ImageViewerMeasure__El('naImageViewer_refOverlay');
        na_refInput          = Na__ImageViewerMeasure__El('naImageViewer_refInput');
        na_refHint           = Na__ImageViewerMeasure__El('naImageViewer_measureHint');
        na_refOk             = Na__ImageViewerMeasure__El('naImageViewer_refOk');
        na_refCancel         = Na__ImageViewerMeasure__El('naImageViewer_refCancel');

        na_core.registerOverlay(Na__ImageViewerMeasure__Render);
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
        if (na_btnUndo) na_btnUndo.addEventListener('click', Na__ImageViewerMeasure__Undo);
        if (na_btnRedo) na_btnRedo.addEventListener('click', Na__ImageViewerMeasure__Redo);
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
