// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - VIEWPORT CONTROLS
// =============================================================================
//
// FILE       : Na__AssemblyStudio__Viewport__Controls__.js
// NAMESPACE  : window.Na__Viewport__Controls (legacy global preserved)
// AUTHOR     : Noble Architecture
// PURPOSE    : Generic pan / zoom / reset and window-style casement click
//              target wiring. Fit-to-content and click callbacks are
//              caller-supplied so this module stays system-agnostic.
//
// DESCRIPTION:
// - na_setupPanZoom binds wheel + drag on the wrapper; viewBoxState and
//   interactionState are mutated in place; updateCallback refreshes the SVG.
//   CAD style since V2.2.0: the wheel zooms about the point under the
//   cursor, a drag (left or middle button) keeps the drawing under the
//   cursor, and a double click on empty canvas (or a middle button double
//   press) fits the drawing again.
// - na_resetView reapplies fit from the supplied fitToContent(config) fn.
// - na_windowResetFitter is a default millimetre box for Window tab configs.
// - na_setupCasementClickTargets delegates opening / transom / glazebar hits.
// - na_setupDimensionEditing (V2.2.0) opens a text box over a dimension the
//   generator marked editable; the caller decides what a typed size means.
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix on the public global; internal
//   helpers stay na_*.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Pan & Zoom Interaction (CAD Style, V2.2.0)
// -----------------------------------------------------------------------------
// Before V2.2.0 the wheel scaled the viewBox's width and height but never
// moved its origin, so every zoom closed in on (or backed away from) the
// top left corner, and a drag moved the drawing at a speed set by a scale
// number unrelated to the canvas. Both now work through the SVG's screen
// matrix: the point under the cursor stays put while zooming, and the
// drawing follows the cursor exactly while panning.

    // CONSTANTS | Zoom Response and Limits
    // ------------------------------------------------------------
    var NA_ZOOM_RATE_PER_PIXEL = 0.0015;                                    // <-- One wheel notch (100 px of delta) zooms about 16%
    var NA_ZOOM_MAX_STEP_PX    = 400;                                       // <-- Caps a single wheel event
    var NA_ZOOM_IN_LIMIT       = 60;                                        // <-- Closest: 1/60 of the fitted width across the canvas
    var NA_ZOOM_OUT_LIMIT      = 6;                                         // <-- Furthest: 6 times the fitted width
    var NA_PAN_THRESHOLD_PX    = 5;                                         // <-- Movement that turns a press into a pan (and swallows its click)
    var NA_DOUBLE_PRESS_MS     = 400;                                       // <-- Middle button double press window
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Screen Point to SVG User Units
    // ------------------------------------------------------------
    // Through the live screen matrix, so the letterboxing of
    // preserveAspectRatio, the viewBox and the canvas size all count.
    function na_clientToSvg(svgElement, clientX, clientY) {
        if (!svgElement || typeof svgElement.getScreenCTM !== 'function') return null;
        var matrix = svgElement.getScreenCTM();
        if (!matrix) return null;
        var inverse = matrix.inverse();
        return {
            x: (inverse.a * clientX) + (inverse.c * clientY) + inverse.e,
            y: (inverse.b * clientX) + (inverse.d * clientY) + inverse.f
        };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | SVG Units per Screen Pixel
    // ------------------------------------------------------------
    function na_unitsPerPixel(svgElement) {
        var matrix = (svgElement && typeof svgElement.getScreenCTM === 'function') ? svgElement.getScreenCTM() : null;
        return (matrix && matrix.a) ? (1 / matrix.a) : 1;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Press on a Dimension or Its Edit Box
    // ------------------------------------------------------------
    // A dimension opens its edit box and the box takes its own clicks, so
    // neither may start a pan.
    function na_isEditTarget(target) {
        return !!(target && target.closest && target.closest('.na-dim-edit, .na-dim-editor'));
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Double Click Landed on Empty Canvas
    // ------------------------------------------------------------
    // Anything the preview lets you click (a casement, a transom, a glaze
    // bar, a lead cell, a dimension) keeps its double click for itself.
    function na_isEmptyCanvas(target) {
        if (!target || !target.closest) return true;
        return !target.closest('[class*="click-target"], .na-dim-edit, .na-dim-editor');
    }
    // ---------------------------------------------------------------

    // FUNCTION | Attach wheel zoom and drag-pan to the viewport wrapper
    // ------------------------------------------------------------
    // @param {Object} options - Optional (V2.2.0):
    //        {Function} onZoomExtents - Fit the drawing again (double click)
    function na_setupPanZoom(wrapperElement, svgElement, viewBoxState, interactionState, updateCallback, options) {
        if (!wrapperElement) {
            console.warn('[NA_VIEWPORT_CONTROLS] na_setupPanZoom called without a wrapperElement');
            return;
        }
        var settings = options || {};
        wrapperElement.classList.add('na-viewport-interactive');

        function na_refresh() {
            if (updateCallback) updateCallback();
            na_positionDimensionEditor(wrapperElement);                     // <-- An open edit box follows its value
        }

        function na_zoomExtents() {
            if (typeof settings.onZoomExtents === 'function') settings.onZoomExtents();
            na_positionDimensionEditor(wrapperElement);
        }

        // Wheel: zoom about the point under the cursor
        wrapperElement.addEventListener('wheel', function (e) {
            e.preventDefault();
            var point = na_clientToSvg(svgElement, e.clientX, e.clientY);
            if (!point || !(viewBoxState.width > 0)) return;

            var deltaPx = e.deltaY * (e.deltaMode === 1 ? 33 : (e.deltaMode === 2 ? 400 : 1));
            deltaPx = Math.max(-NA_ZOOM_MAX_STEP_PX, Math.min(NA_ZOOM_MAX_STEP_PX, deltaPx));
            var fitWidth = interactionState.fitWidth > 0 ? interactionState.fitWidth : viewBoxState.width;
            var targetWidth = viewBoxState.width * Math.pow(1 + NA_ZOOM_RATE_PER_PIXEL, deltaPx);
            targetWidth = Math.max(fitWidth / NA_ZOOM_IN_LIMIT, Math.min(fitWidth * NA_ZOOM_OUT_LIMIT, targetWidth));
            var factor = targetWidth / viewBoxState.width;
            if (!isFinite(factor) || Math.abs(factor - 1) < 1e-6) return;

            viewBoxState.x = point.x - ((point.x - viewBoxState.x) * factor);
            viewBoxState.y = point.y - ((point.y - viewBoxState.y) * factor);
            viewBoxState.width  *= factor;
            viewBoxState.height *= factor;
            interactionState.scale    = fitWidth / viewBoxState.width;     // <-- Zoom level, 1 = fitted
            interactionState.userView = true;
            na_refresh();
        }, { passive: false });

        // Drag: the drawing stays under the cursor. Tracked on the window so
        // a drag that leaves the canvas keeps going until the button is up.
        function na_onPanMove(e) {
            if (!interactionState.isPanning) return;
            if (!interactionState.didPan) {
                var totalDx = Math.abs(e.clientX - interactionState.panStartPos.x);
                var totalDy = Math.abs(e.clientY - interactionState.panStartPos.y);
                if (totalDx <= NA_PAN_THRESHOLD_PX && totalDy <= NA_PAN_THRESHOLD_PX) return;   // <-- Still a click
                interactionState.didPan = true;
            }
            var unitsPerPixel = na_unitsPerPixel(svgElement);
            viewBoxState.x -= (e.clientX - interactionState.lastMousePos.x) * unitsPerPixel;
            viewBoxState.y -= (e.clientY - interactionState.lastMousePos.y) * unitsPerPixel;
            interactionState.lastMousePos = { x: e.clientX, y: e.clientY };
            interactionState.userView     = true;
            na_refresh();
        }

        function na_onPanEnd() {
            window.removeEventListener('mousemove', na_onPanMove);
            window.removeEventListener('mouseup', na_onPanEnd);
            interactionState.isPanning  = false;
            wrapperElement.style.cursor = '';
            // didPan stays set until the next press, so the click this
            // release fires reads as the end of a pan, not a pick.
        }

        wrapperElement.addEventListener('mousedown', function (e) {
            if (e.button !== 0 && e.button !== 1) return;                   // <-- Left or middle button pans
            interactionState.didPan = false;
            if (na_isEditTarget(e.target)) return;                          // <-- A dimension opens its edit box instead
            if (e.button === 1) {
                e.preventDefault();                                         // <-- No autoscroll cursor
                var now = Date.now();
                if (now - (interactionState.lastMiddlePress || 0) < NA_DOUBLE_PRESS_MS) {
                    interactionState.lastMiddlePress = 0;
                    na_zoomExtents();
                    return;
                }
                interactionState.lastMiddlePress = now;
            }
            interactionState.isPanning    = true;
            interactionState.panStartPos  = { x: e.clientX, y: e.clientY };
            interactionState.lastMousePos = { x: e.clientX, y: e.clientY };
            wrapperElement.style.cursor   = 'grabbing';
            window.addEventListener('mousemove', na_onPanMove);
            window.addEventListener('mouseup', na_onPanEnd);
        });

        // Double click on empty canvas: fit the drawing again
        wrapperElement.addEventListener('dblclick', function (e) {
            if (!na_isEmptyCanvas(e.target)) return;
            na_zoomExtents();
        });
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | ViewBox Application
// -----------------------------------------------------------------------------

    // FUNCTION | Push viewBoxState onto the root SVG element
    // ------------------------------------------------------------
    function na_updateViewBox(svgElement, viewBoxState) {
        if (!svgElement) return;
        svgElement.setAttribute('viewBox',
            viewBoxState.x + ' ' + viewBoxState.y + ' ' + viewBoxState.width + ' ' + viewBoxState.height);
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | View Reset & Default Window Fitter
// -----------------------------------------------------------------------------

    // FUNCTION | Reset pan/zoom state and re-fit using caller-supplied fitter
    // ------------------------------------------------------------
    // Also forgets the user's zoom (userView) and records the fitted width,
    // which the wheel measures its zoom limits against.
    function na_resetView(svgElement, viewBoxState, interactionState, config, fitToContent) {
        if (typeof fitToContent !== 'function') {
            console.warn('[NA_VIEWPORT_CONTROLS] na_resetView called without fitToContent fn');
            return;
        }
        var fit           = fitToContent(config) || {};
        viewBoxState.x      = (typeof fit.x      === 'number') ? fit.x      : 0;
        viewBoxState.y      = (typeof fit.y      === 'number') ? fit.y      : 0;
        viewBoxState.width  = (typeof fit.width  === 'number') ? fit.width  : 1;
        viewBoxState.height = (typeof fit.height === 'number') ? fit.height : 1;
        interactionState.scale    = 1;
        interactionState.userView = false;
        interactionState.fitWidth = viewBoxState.width;
        na_updateViewBox(svgElement, viewBoxState);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Stock millimetre viewBox for window/bifold/sliding configs
    // ------------------------------------------------------------
    // Phase-9: All three modes (window, multifold, sliding) now share the
    // `width_mm` / `height_mm` keys driven by the WindowSystem dimension
    // sliders. Legacy `bifold_door_opening_*_mm` /
    // `sliding_door_opening_*_mm` keys are still read as a fallback so any
    // pre-Phase-9 saved blob that has not yet been migrated by the load
    // helper still auto-fits at the correct scale.
    function na_windowResetFitter(config) {
        var padding = 200;
        var widthMm;
        var heightMm;

        if (config && config.multifold_mode === true) {
            widthMm  = Number(config.width_mm  || config.bifold_door_opening_width_mm  || 3600);
            heightMm = Number(config.height_mm || config.bifold_door_opening_height_mm || 2100);
        } else if (config && config.sliding_mode === true) {
            widthMm  = Number(config.width_mm  || config.sliding_door_opening_width_mm  || 2400);
            heightMm = Number(config.height_mm || config.sliding_door_opening_height_mm || 2100);
        } else {
            widthMm  = (config && config.width_mm)  || 900;
            heightMm = (config && config.height_mm) || 1200;
        }

        return {
            x      : -padding,
            y      : -heightMm - padding,
            width  : widthMm  + (padding * 2),
            height : heightMm + (padding * 2)
        };
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Opening / Transom / Glazebar Click Targets
// -----------------------------------------------------------------------------

    // FUNCTION | Wire delegated click handling on SVG for preview hit targets
    // ------------------------------------------------------------
    // leadLineClickCallback (V2.2.1, optional) receives the clicked lead
    // line's key ("opening:cell:panel:sash:col:row:h|v:number").
    function na_setupCasementClickTargets(svgElement, interactionState, clickCallback, transomClickCallback, glazebarClickCallback, leadedCellClickCallback, leadLineClickCallback) {
        if (!svgElement) return;
        if (svgElement._na_clickHandler) {
            svgElement.removeEventListener('click', svgElement._na_clickHandler);
        }

        function handleClick(e) {
            if (interactionState.didPan) return;
            var target = e.target;

            if (target.classList.contains('na-lead-line-click-target')) {
                var leadKey = target.getAttribute('data-lead-key');
                if (leadKey && leadLineClickCallback) leadLineClickCallback(leadKey);
                return;
            }

            if (target.classList.contains('na-glazebar-click-target')) {
                var openingIndex = parseInt(target.dataset.openingIndex, 10);
                var cellIndex    = parseInt(target.dataset.cellIndex,    10);
                var panelIndex   = parseInt(target.dataset.panelIndex,   10);
                var sashIndex    = parseInt(target.dataset.sashIndex,    10);
                var barIndex     = parseInt(target.dataset.barIndex,     10);
                var orientation  = target.dataset.orientation;
                if (isNaN(openingIndex) || isNaN(cellIndex) || isNaN(panelIndex) ||
                    isNaN(sashIndex) || isNaN(barIndex) ||
                    (orientation !== 'horizontal' && orientation !== 'vertical')) return;
                if (glazebarClickCallback) glazebarClickCallback(openingIndex, cellIndex, panelIndex, sashIndex, orientation, barIndex);
                return;
            }

            if (target.classList.contains('na-leaded-cell-click-target')) {
                var openingIndexL = parseInt(target.dataset.openingIndex, 10);
                var cellIndexL    = parseInt(target.dataset.cellIndex,    10);
                var panelIndexL   = parseInt(target.dataset.panelIndex,   10);
                var sashIndexL    = parseInt(target.dataset.sashIndex,    10);
                var colIndex      = parseInt(target.dataset.col,          10);
                var rowIndex      = parseInt(target.dataset.row,          10);
                if (isNaN(openingIndexL) || isNaN(cellIndexL) || isNaN(panelIndexL) ||
                    isNaN(sashIndexL) || isNaN(colIndex) || isNaN(rowIndex)) return;
                if (leadedCellClickCallback) leadedCellClickCallback(openingIndexL, cellIndexL, panelIndexL, sashIndexL, colIndex, rowIndex);
                return;
            }

            if (target.classList.contains('na-transom-click-target')) {
                var openingIndexT = parseInt(target.dataset.openingIndex, 10);
                var transomIndex  = parseInt(target.dataset.transomIndex, 10);
                if (isNaN(openingIndexT) || isNaN(transomIndex)) return;
                if (transomClickCallback) transomClickCallback(openingIndexT, transomIndex);
                return;
            }

            if (!target.classList.contains('na-opening-click-target')) return;
            var openingIndexO = parseInt(target.dataset.openingIndex, 10);
            var cellIndexO    = parseInt(target.dataset.cellIndex,    10);
            var panelIndexO   = parseInt(target.dataset.panelIndex,   10);
            if (isNaN(openingIndexO) || isNaN(cellIndexO) || isNaN(panelIndexO)) return;
            if (clickCallback) clickCallback(openingIndexO, cellIndexO, panelIndexO);
        }

        svgElement.addEventListener('click', handleClick);
        svgElement._na_clickHandler = handleClick;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Dimension Edit In Place (V2.2.0)
// -----------------------------------------------------------------------------
// The Vale Lantern Designer pattern. A value the generator marks editable is
// a <g class="na-dim-edit"> carrying data-dim-kind, data-dim-index,
// data-dim-value and data-dim-label. One click opens a small text box over
// it with its text selected; Enter or clicking away applies it, Escape
// cancels. What a typed size means is the caller's business:
// onCommit(kind, index, text) returns { ok, error }. An entry it cannot
// read on Enter reopens the box, marked, so it can be put right.

    var na_dim_session = null;                                              // <-- One open edit box in the whole dialog

    // FUNCTION | Bind Click-To-Edit on One Preview SVG
    // ------------------------------------------------------------
    // Delegated on the SVG element itself, which survives every re-paint
    // (only its contents are replaced), so this binds once.
    function na_setupDimensionEditing(wrapperElement, svgElement, interactionState, onCommit) {
        if (!wrapperElement || !svgElement || svgElement._na_dimEditBound) return;
        svgElement._na_dimEditBound = true;

        svgElement.addEventListener('click', function (e) {
            if (interactionState && interactionState.didPan) return;
            var group = (e.target && e.target.closest) ? e.target.closest('.na-dim-edit') : null;
            if (!group || !svgElement.contains(group)) return;
            na_openDimensionEditor(wrapperElement, group, onCommit, null);
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | A Value as the Edit Box Shows It (As Drawn, No Unit)
    // ------------------------------------------------------------
    function na_formatEditValue(value) {
        var rounded = Math.round(Number(value) * 10) / 10;
        return isFinite(rounded) ? String(rounded) : '';
    }
    // ---------------------------------------------------------------

    // FUNCTION | Open the Edit Box Over One Dimension Value
    // ------------------------------------------------------------
    // @param {Object|null} retry - { text, error } to reopen a rejected entry
    function na_openDimensionEditor(wrapperElement, group, onCommit, retry) {
        na_closeDimensionEditor();

        var shown = na_formatEditValue(group.getAttribute('data-dim-value'));
        var label = group.getAttribute('data-dim-label') || 'Dimension';
        var input = document.createElement('input');
        input.type = 'text';
        input.className = 'na-dim-editor';
        input.setAttribute('autocomplete', 'off');
        input.setAttribute('spellcheck', 'false');
        input.setAttribute('aria-label', label);
        input.value = retry ? retry.text : shown;
        input.title = retry ? retry.error : (label + ': type a size or a sum. Enter applies, Esc cancels.');
        if (retry) input.classList.add('na-dim-editor--error');
        wrapperElement.appendChild(input);

        var session = {
            wrapper : wrapperElement,
            group   : group,
            input   : input,
            kind    : group.getAttribute('data-dim-kind'),
            index   : parseInt(group.getAttribute('data-dim-index'), 10) || 0,
            shown   : shown,
            onCommit: onCommit
        };
        na_dim_session = session;
        group.classList.add('na-dim-edit--active');
        na_positionDimensionEditor(wrapperElement);

        input.addEventListener('keydown', function (ev) {
            ev.stopPropagation();                                           // <-- Keys belong to the box, not the dialog's shortcuts
            if (ev.key === 'Enter') {
                ev.preventDefault();
                na_commitDimensionEditor(session, false);
            } else if (ev.key === 'Escape') {
                ev.preventDefault();
                na_closeDimensionEditor();
            }
        });
        input.addEventListener('input', function () {
            input.classList.remove('na-dim-editor--error');
        });
        input.addEventListener('blur', function () { na_commitDimensionEditor(session, true); });
        input.addEventListener('mousedown', function (ev) { ev.stopPropagation(); });   // <-- Selecting text never pans
        input.addEventListener('dblclick', function (ev) { ev.stopPropagation(); });    // <-- Nor fits the view

        input.focus();
        input.select();
    }
    // ---------------------------------------------------------------

    // FUNCTION | Apply What Was Typed
    // ------------------------------------------------------------
    // The box closes first: removing a focused box fires its blur, and the
    // cleared session stops that blur committing a second time.
    function na_commitDimensionEditor(session, fromBlur) {
        if (!session || na_dim_session !== session) return;
        var text = session.input.value;
        na_closeDimensionEditor();
        if (String(text).trim() === session.shown) return;                 // <-- Untouched: nothing to rebuild
        var result = (typeof session.onCommit === 'function')
            ? session.onCommit(session.kind, session.index, text)
            : null;
        if (result && result.ok === false && !fromBlur && session.group.isConnected) {
            na_openDimensionEditor(session.wrapper, session.group, session.onCommit, {
                text : text,
                error: result.error || 'Could not read that size'
            });
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Close the Edit Box Without Applying It
    // ------------------------------------------------------------
    // Also called before every re-paint of the window preview.
    function na_closeDimensionEditor() {
        var session = na_dim_session;
        if (!session) return;
        na_dim_session = null;
        if (session.group) session.group.classList.remove('na-dim-edit--active');
        if (session.input && session.input.parentNode) session.input.parentNode.removeChild(session.input);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Keep the Edit Box Centred on Its Value
    // ------------------------------------------------------------
    // Positioned inside the canvas wrapper (position: relative), so it
    // follows its value through a zoom or a pan and stays on the canvas.
    function na_positionDimensionEditor(wrapperElement) {
        var session = na_dim_session;
        if (!session || (wrapperElement && session.wrapper !== wrapperElement)) return;
        if (!session.group.isConnected) {
            na_closeDimensionEditor();
            return;
        }
        var anchor = session.group.querySelector('text') || session.group;
        var anchorRect = anchor.getBoundingClientRect();
        var hostRect = session.wrapper.getBoundingClientRect();
        var width = session.input.offsetWidth || 90;
        var height = session.input.offsetHeight || 26;
        var left = anchorRect.left - hostRect.left - session.wrapper.clientLeft + (anchorRect.width / 2) - (width / 2);
        var top = anchorRect.top - hostRect.top - session.wrapper.clientTop + (anchorRect.height / 2) - (height / 2);
        left = Math.max(2, Math.min(session.wrapper.clientWidth - width - 2, left));
        top = Math.max(2, Math.min(session.wrapper.clientHeight - height - 2, top));
        session.input.style.left = left + 'px';
        session.input.style.top = top + 'px';
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API & Global Export
// -----------------------------------------------------------------------------

    window.Na__Viewport__Controls = {
        na_setupPanZoom              : na_setupPanZoom,
        na_updateViewBox             : na_updateViewBox,
        na_resetView                 : na_resetView,
        na_windowResetFitter         : na_windowResetFitter,
        na_setupCasementClickTargets : na_setupCasementClickTargets,
        na_setupDimensionEditing     : na_setupDimensionEditing,        // <-- V2.2.0
        na_closeDimensionEditor      : na_closeDimensionEditor,         // <-- V2.2.0
        na_clientToSvg               : na_clientToSvg                   // <-- V2.2.0
    };

    console.log('[NA_VIEWPORT_CONTROLS] Viewport Controls module loaded');

// endregion -------------------------------------------------------------------

})();
