(function () {
    'use strict';

    var na_state = {
        svg: null,
        wrapper: null,
        viewBox: { minX: 0, minY: 0, width: 1000, height: 1000 },
        attached: false
    };

    function na_formatPoints(polyline) {
        return polyline.map(function (point) {
            return point[0].toFixed(3) + ',' + (-point[1]).toFixed(3);
        }).join(' ');
    }

    function na_applyViewBox() {
        var vb = na_state.viewBox;
        na_state.svg.setAttribute('viewBox', vb.minX.toFixed(3) + ' ' + (-vb.minY - vb.height).toFixed(3) + ' ' + vb.width.toFixed(3) + ' ' + vb.height.toFixed(3));
    }

    function na_render(faceData, polylines) {
        if (!na_state.svg) {
            return;
        }

        var allPolylines = [];
        if (faceData && faceData.outer) {
            allPolylines.push(faceData.outer);
            (faceData.holes || []).forEach(function (hole) { allPolylines.push(hole); });
        }
        (polylines || []).forEach(function (polyline) { allPolylines.push(polyline); });

        var bounds = window.Na__FacePattern__Viewport.na_computeBounds(allPolylines);
        na_state.viewBox = window.Na__FacePattern__Viewport.na_buildViewBox(bounds, 0.08);
        na_applyViewBox();

        var markup = [];
        if (faceData && faceData.outer) {
            markup.push('<polyline points="' + na_formatPoints(faceData.outer) + '" fill="none" stroke="#7a8798" stroke-width="2" stroke-dasharray="12,8" vector-effect="non-scaling-stroke"/>');
            (faceData.holes || []).forEach(function (hole) {
                markup.push('<polyline points="' + na_formatPoints(hole) + '" fill="none" stroke="#8c96a5" stroke-width="1.5" stroke-dasharray="6,6" vector-effect="non-scaling-stroke"/>');
            });
        }

        (polylines || []).forEach(function (polyline) {
            markup.push('<polyline points="' + na_formatPoints(polyline) + '" fill="none" stroke="#1f2933" stroke-width="1.4" vector-effect="non-scaling-stroke"/>');
        });

        na_state.svg.innerHTML = markup.join('');
    }

    function na_resetView(faceData, polylines) {
        var allPolylines = [];
        if (faceData && faceData.outer) { allPolylines.push(faceData.outer); }
        (faceData && faceData.holes ? faceData.holes : []).forEach(function (hole) { allPolylines.push(hole); });
        (polylines || []).forEach(function (polyline) { allPolylines.push(polyline); });
        var bounds = window.Na__FacePattern__Viewport.na_computeBounds(allPolylines);
        na_state.viewBox = window.Na__FacePattern__Viewport.na_buildViewBox(bounds, 0.08);
        na_applyViewBox();
    }

    function na_init(svgId, wrapperId) {
        na_state.svg = document.getElementById(svgId);
        na_state.wrapper = document.getElementById(wrapperId);
        if (!na_state.svg || !na_state.wrapper) {
            return false;
        }

        if (!na_state.attached) {
            window.Na__FacePattern__Viewport.na_attachPanZoom(na_state.wrapper, na_state.viewBox, na_applyViewBox);
            na_state.attached = true;
        }
        na_applyViewBox();
        return true;
    }

    window.Na__FacePattern__SvgPreview = {
        na_init: na_init,
        na_render: na_render,
        na_resetView: na_resetView
    };
})();
