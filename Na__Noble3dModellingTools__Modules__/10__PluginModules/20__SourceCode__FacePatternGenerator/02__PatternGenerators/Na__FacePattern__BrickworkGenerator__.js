(function () {
    'use strict';

    var BRICK_SIZES = {
        imperial: { width: 215, height: 65, header: 102.5 },
        metric: { width: 230, height: 76, header: 110 }
    };

    function na_getCourseBricks(courseIndex, params, bounds) {
        var system = BRICK_SIZES[params.unit_system] || BRICK_SIZES.imperial;
        var mortar = Math.max(0, Number(params.mortar_mm) || 0);
        var bond = params.bond_type || 'stretcher';
        var bricks = [];

        if (bond === 'flemish') {
            var flemishUnit = (system.width + mortar) + (system.header + mortar);
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
            var isStretcher = courseIndex % 2 === 0;
            var widthEnglish = isStretcher ? system.width : system.header;
            var unitEnglish = widthEnglish + mortar;
            var offsetEnglish = isStretcher && (Math.floor(courseIndex / 2) % 2 === 1) ? unitEnglish * 0.5 : 0;
            var xe = bounds.min_x - offsetEnglish;
            while (xe < bounds.max_x + widthEnglish) {
                bricks.push({ x: xe, width: widthEnglish });
                xe += unitEnglish;
            }
            return bricks;
        }

        var stretcherUnit = system.width + mortar;
        var stretcherOffset = courseIndex % 2 === 1 ? stretcherUnit * 0.5 : 0;
        var xs = bounds.min_x - stretcherOffset;
        while (xs < bounds.max_x + system.width) {
            bricks.push({ x: xs, width: system.width });
            xs += stretcherUnit;
        }
        return bricks;
    }

    function na_generate(context) {
        var bounds = context.faceData.bounds;
        var params = context.params;
        var system = BRICK_SIZES[params.unit_system] || BRICK_SIZES.imperial;
        var mortar = Math.max(0, Number(params.mortar_mm) || 10);
        var renderMode = params.render_mode || 'continuous';
        var density = Math.max(0, Math.min(100, Number(params.density_pct) || 50)) / 100;
        var courseHeight = system.height + mortar;
        var clipApi = window.Na__FacePattern__PolygonClip;
        var noiseApi = window.Na__FacePattern__Noise;
        var rectApi = window.Na__FacePattern__RectGeometry;

        var polylines = [];
        var courseIndex = 0;
        for (var y = bounds.min_y; y <= bounds.max_y + courseHeight; y += courseHeight) {
            var bricks = na_getCourseBricks(courseIndex, params, bounds);
            bricks.forEach(function (brick) {
                if (renderMode === 'artistic') {
                    var nx = (brick.x + (brick.width * 0.5)) * 0.015;
                    var ny = (y + (system.height * 0.5)) * 0.015;
                    if (noiseApi.na_fbmNoise(nx, ny, Number(params.seed) || 0, 3) > density) {
                        return;
                    }
                }

                var clippedRect = rectApi.na_clipRectToBounds(brick.x, y, brick.width, system.height, bounds);
                if (!clippedRect) {
                    return;
                }

                var rect = rectApi.na_makeRectPolyline(clippedRect.x, clippedRect.y, clippedRect.width, clippedRect.height);
                var kept = clipApi.na_keepWhenCentroidInside(rect, context.faceData.outer, context.faceData.holes);
                if (!kept) {
                    return;
                }

                var clipped = clipApi.na_clipPolyline(kept, context.faceData.outer, context.faceData.holes);
                if (clipped.length >= 3) {
                    polylines.push(clipped);
                }
            });
            courseIndex += 1;
        }

        return {
            polylines: polylines,
            status: polylines.length + ' brick units generated.'
        };
    }

    window.Na__FacePattern__BrickworkGenerator = {
        na_generate: na_generate
    };
})();
