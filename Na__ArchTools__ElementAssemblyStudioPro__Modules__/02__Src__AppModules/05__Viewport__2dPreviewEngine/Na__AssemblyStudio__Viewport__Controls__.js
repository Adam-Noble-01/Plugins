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
// - na_resetView reapplies fit from the supplied fitToContent(config) fn.
// - na_windowResetFitter is a default millimetre box for Window tab configs.
// - na_setupCasementClickTargets delegates opening / transom / glazebar hits.
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix on the public global; internal
//   helpers stay na_*.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Pan & Zoom Interaction
// -----------------------------------------------------------------------------

    // FUNCTION | Attach wheel zoom and drag-pan to the viewport wrapper
    // ------------------------------------------------------------
    function na_setupPanZoom(wrapperElement, svgElement, viewBoxState, interactionState, updateCallback) {
        if (!wrapperElement) {
            console.warn('[NA_VIEWPORT_CONTROLS] na_setupPanZoom called without a wrapperElement');
            return;
        }
        wrapperElement.classList.add('na-viewport-interactive');

        wrapperElement.addEventListener('wheel', function (e) {
            e.preventDefault();
            var zoomFactor = e.deltaY > 0 ? 1.1 : 0.9;
            interactionState.scale *= zoomFactor;
            interactionState.scale = Math.max(0.1, Math.min(10, interactionState.scale));
            viewBoxState.width  *= zoomFactor;
            viewBoxState.height *= zoomFactor;
            if (updateCallback) updateCallback();
        });

        wrapperElement.addEventListener('mousedown', function (e) {
            interactionState.isPanning    = true;
            interactionState.didPan       = false;
            interactionState.panStartPos  = { x: e.clientX, y: e.clientY };
            interactionState.lastMousePos = { x: e.clientX, y: e.clientY };
            wrapperElement.style.cursor   = 'grabbing';
        });

        wrapperElement.addEventListener('mousemove', function (e) {
            if (!interactionState.isPanning) return;
            var totalDx = Math.abs(e.clientX - interactionState.panStartPos.x);
            var totalDy = Math.abs(e.clientY - interactionState.panStartPos.y);
            if (totalDx > 5 || totalDy > 5) interactionState.didPan = true;

            var dx = (e.clientX - interactionState.lastMousePos.x) * interactionState.scale;
            var dy = (e.clientY - interactionState.lastMousePos.y) * interactionState.scale;
            viewBoxState.x -= dx;
            viewBoxState.y -= dy;
            interactionState.lastMousePos = { x: e.clientX, y: e.clientY };
            if (updateCallback) updateCallback();
        });

        wrapperElement.addEventListener('mouseup', function () {
            interactionState.isPanning  = false;
            interactionState.didPan     = false;
            wrapperElement.style.cursor = 'grab';
        });

        wrapperElement.addEventListener('mouseleave', function () {
            interactionState.isPanning  = false;
            interactionState.didPan     = false;
            wrapperElement.style.cursor = 'grab';
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
        interactionState.scale = 1;
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
    function na_setupCasementClickTargets(svgElement, interactionState, clickCallback, transomClickCallback, glazebarClickCallback) {
        if (!svgElement) return;
        if (svgElement._na_clickHandler) {
            svgElement.removeEventListener('click', svgElement._na_clickHandler);
        }

        function handleClick(e) {
            if (interactionState.didPan) return;
            var target = e.target;

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
// REGION | Public API & Global Export
// -----------------------------------------------------------------------------

    window.Na__Viewport__Controls = {
        na_setupPanZoom              : na_setupPanZoom,
        na_updateViewBox             : na_updateViewBox,
        na_resetView                 : na_resetView,
        na_windowResetFitter         : na_windowResetFitter,
        na_setupCasementClickTargets : na_setupCasementClickTargets
    };

    console.log('[NA_VIEWPORT_CONTROLS] Viewport Controls module loaded');

// endregion -------------------------------------------------------------------

})();
