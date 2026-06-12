// =============================================================================
// NA NOBLE3D MODELLING TOOLS - PNG TO LINEWORK - SVG PREVIEW VIEWPORT
// =============================================================================
//
// FILE       : Na__Noble3dModellingTools__PngToLinework__SvgPreview__.js
// NAMESPACE  : window.Na__PngToLinework__SvgPreview
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Pan / zoom SVG viewport for the traced linework preview, using
//              the viewBox-state pattern from the Element Assembly Studio
//              2D preview engine (simplified standalone copy).
// CREATED    : 2026
//
// COORDINATES:
// Trace polylines arrive in centred millimetres with model Y-up; SVG Y is
// negated at render time so the drawing reads the right way up.
//
// =============================================================================

window.Na__PngToLinework__SvgPreview = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Module State
    // -------------------------------------------------------------------------

    var NA_FIT_PADDING_FACTOR = 0.10;                                         // <-- 10% margin around content on reset
    var NA_PAN_DRAG_THRESHOLD = 5;                                            // <-- Pixels before a click becomes a pan

    var svgElement     = null;
    var wrapperElement = null;
    var viewBoxState   = { x: -500, y: -500, width: 1000, height: 1000 };
    var contentBounds  = null;
    var panState       = { active: false, startX: 0, startY: 0, originX: 0, originY: 0 };

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Initialisation and Interaction
    // -------------------------------------------------------------------------

    // FUNCTION | Bind the Preview to Its SVG and Wrapper Elements
    // ------------------------------------------------------------
    function na_init(svgId, wrapperId) {
        svgElement     = document.getElementById(svgId);
        wrapperElement = document.getElementById(wrapperId);
        if (!svgElement || !wrapperElement) { return; }

        wrapperElement.addEventListener('wheel', na_onWheel, { passive: false });
        wrapperElement.addEventListener('mousedown', na_onMouseDown);
        window.addEventListener('mousemove', na_onMouseMove);
        window.addEventListener('mouseup', na_onMouseUp);
        na_updateViewBox();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Zoom Anchored at the Cursor Position
    // ------------------------------------------------------------
    function na_onWheel(event) {
        event.preventDefault();
        var rect       = wrapperElement.getBoundingClientRect();
        var fractionX  = (event.clientX - rect.left) / rect.width;
        var fractionY  = (event.clientY - rect.top) / rect.height;
        var zoomFactor = event.deltaY > 0 ? 1.1 : 0.9;

        viewBoxState.x      += fractionX * viewBoxState.width * (1 - zoomFactor);
        viewBoxState.y      += fractionY * viewBoxState.height * (1 - zoomFactor);
        viewBoxState.width  *= zoomFactor;
        viewBoxState.height *= zoomFactor;
        na_updateViewBox();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Begin a Potential Pan Drag
    // ------------------------------------------------------------
    function na_onMouseDown(event) {
        panState.active  = true;
        panState.moved   = false;
        panState.startX  = event.clientX;
        panState.startY  = event.clientY;
        panState.originX = viewBoxState.x;
        panState.originY = viewBoxState.y;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Pan the ViewBox While Dragging
    // ------------------------------------------------------------
    function na_onMouseMove(event) {
        if (!panState.active) { return; }

        var deltaX = event.clientX - panState.startX;
        var deltaY = event.clientY - panState.startY;
        if (!panState.moved && Math.abs(deltaX) < NA_PAN_DRAG_THRESHOLD && Math.abs(deltaY) < NA_PAN_DRAG_THRESHOLD) { return; }

        panState.moved = true;
        var rect = wrapperElement.getBoundingClientRect();
        viewBoxState.x = panState.originX - (deltaX / rect.width) * viewBoxState.width;
        viewBoxState.y = panState.originY - (deltaY / rect.height) * viewBoxState.height;
        na_updateViewBox();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | End the Pan Drag
    // ------------------------------------------------------------
    function na_onMouseUp() {
        panState.active = false;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Write the ViewBox State to the SVG Element
    // ------------------------------------------------------------
    function na_updateViewBox() {
        if (!svgElement) { return; }
        svgElement.setAttribute(
            'viewBox',
            viewBoxState.x + ' ' + viewBoxState.y + ' ' + viewBoxState.width + ' ' + viewBoxState.height
        );
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Rendering
    // -------------------------------------------------------------------------

    // FUNCTION | Render Trace Polylines (and Optional Source Image) as SVG
    // ------------------------------------------------------------
    function na_render(traceResult, renderOptions) {
        if (!svgElement) { return; }

        var markup = '';

        if (renderOptions.showSource && renderOptions.sourceDataUri && traceResult.imageOverlay) {
            var overlay = traceResult.imageOverlay;
            markup += '<image href="' + renderOptions.sourceDataUri + '" ' +
                      'x="' + overlay.minX.toFixed(2) + '" ' +
                      'y="' + (-(overlay.minY + overlay.heightMm)).toFixed(2) + '" ' +
                      'width="' + overlay.widthMm.toFixed(2) + '" ' +
                      'height="' + overlay.heightMm.toFixed(2) + '" ' +
                      'opacity="0.22" preserveAspectRatio="none"/>';
        }

        var polylines = traceResult.polylines || [];
        for (var p = 0; p < polylines.length; p++) {
            var points = polylines[p];
            var coords = new Array(points.length);
            for (var i = 0; i < points.length; i++) {
                coords[i] = points[i][0].toFixed(2) + ',' + (-points[i][1]).toFixed(2);   // <-- Negate Y for SVG
            }
            markup += '<polyline points="' + coords.join(' ') + '" fill="none" stroke="#1e1e1e" ' +
                      'stroke-width="1" vector-effect="non-scaling-stroke" stroke-linecap="round" stroke-linejoin="round"/>';
        }

        markup += '<circle cx="0" cy="0" r="3" fill="none" stroke="#4a90d9" stroke-width="1.5" vector-effect="non-scaling-stroke"/>' +
                  '<line x1="-6" y1="0" x2="6" y2="0" stroke="#4a90d9" stroke-width="1" vector-effect="non-scaling-stroke"/>' +
                  '<line x1="0" y1="-6" x2="0" y2="6" stroke="#4a90d9" stroke-width="1" vector-effect="non-scaling-stroke"/>';

        svgElement.innerHTML = markup;
        contentBounds = na_computeContentBounds(polylines, traceResult.imageOverlay);
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Compute Content Bounds in SVG Coordinate Space
    // ------------------------------------------------------------
    function na_computeContentBounds(polylines, imageOverlay) {
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;

        for (var p = 0; p < polylines.length; p++) {
            for (var i = 0; i < polylines[p].length; i++) {
                var x =  polylines[p][i][0];
                var y = -polylines[p][i][1];
                if (x < minX) { minX = x; }
                if (x > maxX) { maxX = x; }
                if (y < minY) { minY = y; }
                if (y > maxY) { maxY = y; }
            }
        }

        if (!isFinite(minX) && imageOverlay) {
            minX = imageOverlay.minX;
            maxX = imageOverlay.minX + imageOverlay.widthMm;
            minY = -(imageOverlay.minY + imageOverlay.heightMm);
            maxY = -imageOverlay.minY;
        }

        if (!isFinite(minX)) { return null; }
        return { minX: minX, minY: minY, maxX: maxX, maxY: maxY };
    }
    // ------------------------------------------------------------

    // FUNCTION | Reset the View to Fit the Traced Content
    // ------------------------------------------------------------
    function na_resetView() {
        if (!contentBounds || !svgElement) { return; }

        var contentWidth  = Math.max(contentBounds.maxX - contentBounds.minX, 1);
        var contentHeight = Math.max(contentBounds.maxY - contentBounds.minY, 1);
        var paddingX      = contentWidth * NA_FIT_PADDING_FACTOR;
        var paddingY      = contentHeight * NA_FIT_PADDING_FACTOR;

        var fitted = {
            x      : contentBounds.minX - paddingX,
            y      : contentBounds.minY - paddingY,
            width  : contentWidth + paddingX * 2,
            height : contentHeight + paddingY * 2
        };

        var rect = wrapperElement.getBoundingClientRect();                     // <-- Match the wrapper aspect so fit fills the pane
        if (rect.width > 0 && rect.height > 0) {
            var wrapperAspect = rect.width / rect.height;
            var fittedAspect  = fitted.width / fitted.height;
            if (fittedAspect < wrapperAspect) {
                var extraWidth = fitted.height * wrapperAspect - fitted.width;
                fitted.x     -= extraWidth / 2;
                fitted.width += extraWidth;
            } else {
                var extraHeight = fitted.width / wrapperAspect - fitted.height;
                fitted.y      -= extraHeight / 2;
                fitted.height += extraHeight;
            }
        }

        viewBoxState = fitted;
        na_updateViewBox();
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    return {
        na_init      : na_init,
        na_render    : na_render,
        na_resetView : na_resetView
    };

})();

// =============================================================================
// END OF FILE
// =============================================================================
