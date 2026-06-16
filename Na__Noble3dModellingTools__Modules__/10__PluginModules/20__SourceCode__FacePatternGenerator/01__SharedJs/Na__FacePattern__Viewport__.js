// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN - VIEWPORT
// =============================================================================
//
// FILE       : Na__FacePattern__Viewport__.js
// NAMESPACE  : window.Na__FacePattern__Viewport
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : SVG viewBox-state pan/zoom, bounds computation, and fit padding
//              — shared by SvgPreview and pattern generators.
// CREATED    : 2026
//
// =============================================================================

window.Na__FacePattern__Viewport = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Bounds Computation
    // -------------------------------------------------------------------------

    // FUNCTION | Compute Axis-Aligned Bounds from an Array of Polylines
    // ------------------------------------------------------------
    function na_computeBounds(polylines) {
        var minX = Infinity;
        var minY = Infinity;
        var maxX = -Infinity;
        var maxY = -Infinity;

        (polylines || []).forEach(function (polyline) {
            (polyline || []).forEach(function (point) {
                minX = Math.min(minX, point[0]);
                minY = Math.min(minY, point[1]);
                maxX = Math.max(maxX, point[0]);
                maxY = Math.max(maxY, point[1]);
            });
        });

        if (!isFinite(minX) || !isFinite(minY) || !isFinite(maxX) || !isFinite(maxY)) {
            return { minX: 0, minY: 0, maxX: 1000, maxY: 1000, width: 1000, height: 1000 };
        }

        return {
            minX: minX,
            minY: minY,
            maxX: maxX,
            maxY: maxY,
            width: Math.max(1, maxX - minX),
            height: Math.max(1, maxY - minY)
        };
    }
    // ------------------------------------------------------------

    // FUNCTION | Build a Padded ViewBox from Content Bounds
    // ------------------------------------------------------------
    function na_buildViewBox(bounds, paddingRatio) {
        var padX = bounds.width * (paddingRatio || 0.06);
        var padY = bounds.height * (paddingRatio || 0.06);
        return {
            minX: bounds.minX - padX,
            minY: bounds.minY - padY,
            width: bounds.width + (padX * 2),
            height: bounds.height + (padY * 2)
        };
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Pan and Zoom Interaction
    // -------------------------------------------------------------------------

    // FUNCTION | Attach Wheel-Zoom and Drag-Pan to a Viewport Wrapper
    // ------------------------------------------------------------
    function na_attachPanZoom(wrapper, state, onChange) {
        var dragging = false;
        var lastX = 0;
        var lastY = 0;

        wrapper.addEventListener('wheel', function (event) {
            event.preventDefault();
            var zoom = event.deltaY < 0 ? 0.92 : 1.08;
            state.width  *= zoom;
            state.height *= zoom;
            onChange();
        }, { passive: false });

        wrapper.addEventListener('mousedown', function (event) {
            dragging = true;
            lastX = event.clientX;
            lastY = event.clientY;
            wrapper.style.cursor = 'grabbing';
        });

        window.addEventListener('mousemove', function (event) {
            if (!dragging) { return; }

            var dx = event.clientX - lastX;
            var dy = event.clientY - lastY;
            lastX = event.clientX;
            lastY = event.clientY;

            var rect = wrapper.getBoundingClientRect();
            if (rect.width <= 0 || rect.height <= 0) { return; }

            state.minX -= (dx / rect.width) * state.width;
            state.minY += (dy / rect.height) * state.height;
            onChange();
        });

        window.addEventListener('mouseup', function () {
            dragging = false;
            wrapper.style.cursor = 'grab';
        });
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    return {
        na_computeBounds: na_computeBounds,
        na_buildViewBox: na_buildViewBox,
        na_attachPanZoom: na_attachPanZoom
    };

})();

// =============================================================================
// END OF FILE
// =============================================================================
