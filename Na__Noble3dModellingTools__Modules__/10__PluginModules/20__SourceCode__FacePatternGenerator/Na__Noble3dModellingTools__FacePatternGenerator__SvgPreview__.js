// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN GENERATOR - SVG PREVIEW VIEWPORT
// =============================================================================
//
// FILE       : Na__Noble3dModellingTools__FacePatternGenerator__SvgPreview__.js
// NAMESPACE  : window.Na__FacePattern__SvgPreview
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Two-layer SVG renderer — face boundary overlay plus pattern
//              polylines — with pan/zoom via the shared Viewport module.
// CREATED    : 2026
//
// COORDINATES:
// Face and pattern polylines arrive in local millimetres with model Y-up;
// SVG Y is negated at render time so the drawing reads the right way up.
//
// =============================================================================

window.Na__FacePattern__SvgPreview = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Module State
    // -------------------------------------------------------------------------

    var NA_FIT_PADDING_RATIO = 0.08;                                            // <-- 8% margin around content on fit

    var na_state = {
        svg: null,
        wrapper: null,
        viewBox: { minX: 0, minY: 0, width: 1000, height: 1000 },
        attached: false
    };

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Initialisation
    // -------------------------------------------------------------------------

    // FUNCTION | Bind the Preview to Its SVG and Wrapper Elements
    // ------------------------------------------------------------
    function na_init(svgId, wrapperId) {
        na_state.svg     = document.getElementById(svgId);
        na_state.wrapper = document.getElementById(wrapperId);
        if (!na_state.svg || !na_state.wrapper) { return false; }

        if (!na_state.attached) {
            window.Na__FacePattern__Viewport.na_attachPanZoom(na_state.wrapper, na_state.viewBox, na_applyViewBox);
            na_state.attached = true;
        }
        na_applyViewBox();
        return true;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | ViewBox Helpers
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Format a Polyline for SVG (Y Negated)
    // ------------------------------------------------------------
    function na_formatPoints(polyline) {
        return polyline.map(function (point) {
            return point[0].toFixed(3) + ',' + (-point[1]).toFixed(3);
        }).join(' ');
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Pick the SVG Element that Closes a Ring but Not a Run
    // ------------------------------------------------------------
    // Rings of three or more points are closed shapes (tiles, face outlines);
    // two-point runs are open lines such as the rosemary tile base line.
    function na_shapeTag(polyline) {
        return polyline.length >= 3 ? 'polygon' : 'polyline';
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Write the ViewBox State to the SVG Element
    // ------------------------------------------------------------
    function na_applyViewBox() {
        var vb = na_state.viewBox;
        na_state.svg.setAttribute(
            'viewBox',
            vb.minX.toFixed(3) + ' ' + (-vb.minY - vb.height).toFixed(3) + ' ' +
            vb.width.toFixed(3) + ' ' + vb.height.toFixed(3)
        );
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Collect All Polylines for Bounds Computation
    // ------------------------------------------------------------
    function na_collectPolylines(faceData, polylines) {
        var allPolylines = [];
        if (faceData && faceData.outer) {
            allPolylines.push(faceData.outer);
            (faceData.holes || []).forEach(function (hole) { allPolylines.push(hole); });
        }
        (polylines || []).forEach(function (polyline) { allPolylines.push(polyline); });
        return allPolylines;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Rendering
    // -------------------------------------------------------------------------

    // FUNCTION | Render Face Boundary Overlay and Pattern Polylines
    // ------------------------------------------------------------
    function na_render(faceData, polylines) {
        if (!na_state.svg) { return; }

        var bounds = window.Na__FacePattern__Viewport.na_computeBounds(na_collectPolylines(faceData, polylines));
        na_state.viewBox = window.Na__FacePattern__Viewport.na_buildViewBox(bounds, NA_FIT_PADDING_RATIO);
        na_applyViewBox();

        var markup = [];

        if (faceData && faceData.outer) {
            markup.push(
                '<polygon points="' + na_formatPoints(faceData.outer) + '" fill="none" stroke="#7a8798" ' +
                'stroke-width="2" stroke-dasharray="12,8" vector-effect="non-scaling-stroke"/>'
            );
            (faceData.holes || []).forEach(function (hole) {
                markup.push(
                    '<polygon points="' + na_formatPoints(hole) + '" fill="none" stroke="#8c96a5" ' +
                    'stroke-width="1.5" stroke-dasharray="6,6" vector-effect="non-scaling-stroke"/>'
                );
            });
        }

        (polylines || []).forEach(function (polyline) {
            var tag = na_shapeTag(polyline);
            markup.push(
                '<' + tag + ' points="' + na_formatPoints(polyline) + '" fill="none" stroke="#1f2933" ' +
                'stroke-width="1.4" vector-effect="non-scaling-stroke"/>'
            );
        });

        na_state.svg.innerHTML = markup.join('');
    }
    // ------------------------------------------------------------

    // FUNCTION | Reset the View to Fit the Current Content
    // ------------------------------------------------------------
    function na_resetView(faceData, polylines) {
        var bounds = window.Na__FacePattern__Viewport.na_computeBounds(na_collectPolylines(faceData, polylines));
        na_state.viewBox = window.Na__FacePattern__Viewport.na_buildViewBox(bounds, NA_FIT_PADDING_RATIO);
        na_applyViewBox();
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    return {
        na_init: na_init,
        na_render: na_render,
        na_resetView: na_resetView
    };

})();

// =============================================================================
// END OF FILE
// =============================================================================
