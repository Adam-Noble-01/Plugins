// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN - RECT GEOMETRY
// =============================================================================
//
// FILE       : Na__FacePattern__RectGeometry__.js
// NAMESPACE  : window.Na__FacePattern__RectGeometry
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Rectangle polyline creation, bounds clipping, and centroid —
//              replaces the Maker.js Line-path pattern from the prototypes.
// CREATED    : 2026
//
// =============================================================================

window.Na__FacePattern__RectGeometry = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Rectangle Construction
    // -------------------------------------------------------------------------

    // FUNCTION | Build a Closed Rectangle as a Four-Point Polyline
    // ------------------------------------------------------------
    function na_makeRectPolyline(x, y, width, height) {
        return [
            [x, y],
            [x + width, y],
            [x + width, y + height],
            [x, y + height]
        ];
    }
    // ------------------------------------------------------------

    // FUNCTION | Clip a Rectangle to an Axis-Aligned Bounds Box
    // ------------------------------------------------------------
    function na_clipRectToBounds(x, y, width, height, bounds) {
        var minX = Math.max(x, bounds.min_x);
        var minY = Math.max(y, bounds.min_y);
        var maxX = Math.min(x + width, bounds.max_x);
        var maxY = Math.min(y + height, bounds.max_y);

        if (maxX <= minX || maxY <= minY) { return null; }

        return {
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        };
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Centroid
    // -------------------------------------------------------------------------

    // FUNCTION | Compute the Arithmetic Mean of Polyline Vertices
    // ------------------------------------------------------------
    function na_centroid(polyline) {
        if (!polyline || !polyline.length) { return [0, 0]; }
        var sumX = 0;
        var sumY = 0;
        polyline.forEach(function (point) {
            sumX += point[0];
            sumY += point[1];
        });
        return [sumX / polyline.length, sumY / polyline.length];
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    return {
        na_makeRectPolyline: na_makeRectPolyline,
        na_clipRectToBounds: na_clipRectToBounds,
        na_centroid: na_centroid
    };

})();

// =============================================================================
// END OF FILE
// =============================================================================
