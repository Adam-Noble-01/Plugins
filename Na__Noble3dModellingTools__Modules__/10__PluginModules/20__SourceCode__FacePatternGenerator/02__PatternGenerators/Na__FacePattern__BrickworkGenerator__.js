// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN - BRICKWORK GENERATOR
// =============================================================================
//
// FILE       : Na__FacePattern__BrickworkGenerator__.js
// NAMESPACE  : window.Na__FacePattern__BrickworkGenerator
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Stretcher / Flemish / English bond courses with Imperial and
//              Metric brick sizes; FBM artistic density mode.
// CREATED    : 2026
//
// =============================================================================

window.Na__FacePattern__BrickworkGenerator = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Brick Size Presets
    // -------------------------------------------------------------------------

    var NA_BRICK_SIZES = {
        imperial: { width: 215, height: 65, header: 102.5 },
        metric:   { width: 230, height: 76, header: 110 }
    };

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Bond Layout
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Compute Brick Positions for One Course Row
    // ------------------------------------------------------------
    function na_getCourseBricks(courseIndex, params, bounds) {
        var system = NA_BRICK_SIZES[params.unit_system] || NA_BRICK_SIZES.imperial;
        var mortar = Math.max(0, Number(params.mortar_mm) || 0);
        var bond   = params.bond_type || 'stretcher';
        var bricks = [];

        if (bond === 'flemish') {
            var flemishUnit   = (system.width + mortar) + (system.header + mortar);
            var flemishOffset = courseIndex % 2 === 1 ? flemishUnit * 0.5 : 0;
            var xf = bounds.min_x - flemishOffset;
            var stretcher = true;
            while (xf < bounds.max_x + system.width) {
                var width = stretcher ? system.width : system.header;
                bricks.push({ x: xf, width: width });
                xf += width + mortar;
                stretcher = !stretcher;
            }
            return bricks;
        }

        if (bond === 'english') {
            var isStretcher   = courseIndex % 2 === 0;
            var widthEnglish  = isStretcher ? system.width : system.header;
            var unitEnglish   = widthEnglish + mortar;
            var offsetEnglish = isStretcher && (Math.floor(courseIndex / 2) % 2 === 1) ? unitEnglish * 0.5 : 0;
            var xe = bounds.min_x - offsetEnglish;
            while (xe < bounds.max_x + widthEnglish) {
                bricks.push({ x: xe, width: widthEnglish });
                xe += unitEnglish;
            }
            return bricks;
        }

        var stretcherUnit   = system.width + mortar;
        var stretcherOffset = courseIndex % 2 === 1 ? stretcherUnit * 0.5 : 0;
        var xs = bounds.min_x - stretcherOffset;
        while (xs < bounds.max_x + system.width) {
            bricks.push({ x: xs, width: system.width });
            xs += stretcherUnit;
        }
        return bricks;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Generator
    // -------------------------------------------------------------------------

    // FUNCTION | Generate Brickwork Polylines for the Selected Face
    // ------------------------------------------------------------
    function na_generate(context) {
        var bounds     = context.faceData.bounds;
        var params     = context.params;
        var system     = NA_BRICK_SIZES[params.unit_system] || NA_BRICK_SIZES.imperial;
        var mortar     = Math.max(0, Number(params.mortar_mm) || 10);
        var renderMode = params.render_mode || 'continuous';
        var density    = Math.max(0, Math.min(100, Number(params.density_pct) || 50)) / 100;
        var courseHeight = system.height + mortar;
        var clipApi    = window.Na__FacePattern__PolygonClip;
        var noiseApi   = window.Na__FacePattern__Noise;
        var rectApi    = window.Na__FacePattern__RectGeometry;

        var polylines  = [];
        var courseIndex = 0;
        for (var y = bounds.min_y; y <= bounds.max_y + courseHeight; y += courseHeight) {
            var bricks = na_getCourseBricks(courseIndex, params, bounds);
            bricks.forEach(function (brick) {
                if (renderMode === 'artistic') {
                    var nx = (brick.x + (brick.width * 0.5)) * 0.015;
                    var ny = (y + (system.height * 0.5)) * 0.015;
                    if (noiseApi.na_fbmNoise(nx, ny, Number(params.seed) || 0, 3) > density) { return; }
                }

                var clippedRect = rectApi.na_clipRectToBounds(brick.x, y, brick.width, system.height, bounds);
                if (!clippedRect) { return; }

                var rect = rectApi.na_makeRectPolyline(clippedRect.x, clippedRect.y, clippedRect.width, clippedRect.height);
                var kept = clipApi.na_keepWhenCentroidInside(rect, context.faceData.outer, context.faceData.holes);
                if (!kept) { return; }

                var clipped = clipApi.na_clipPolyline(kept, context.faceData.outer, context.faceData.holes);
                if (clipped.length >= 3) { polylines.push(clipped); }
            });
            courseIndex += 1;
        }

        return {
            polylines: polylines,
            status: polylines.length + ' brick units generated.'
        };
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    return {
        na_generate: na_generate
    };

})();

// =============================================================================
// END OF FILE
// =============================================================================
