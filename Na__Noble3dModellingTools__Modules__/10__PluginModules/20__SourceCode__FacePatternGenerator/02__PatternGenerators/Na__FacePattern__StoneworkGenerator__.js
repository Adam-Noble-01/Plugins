(function () {
    'use strict';

    var SIZE_PRESETS = {
        small: { minW: 100, maxW: 280, minH: 60, maxH: 140 },
        medium: { minW: 150, maxW: 420, minH: 100, maxH: 220 },
        large: { minW: 220, maxW: 620, minH: 150, maxH: 300 }
    };

    function na_random(seed) {
        return window.Na__FacePattern__Noise.na_seededRandom(seed);
    }

    function na_generateCoursed(bounds, preset, seed) {
        var stones = [];
        var y = bounds.min_y;
        var row = 0;
        while (y < bounds.max_y) {
            var rowRand = na_random(seed + (row * 17));
            var courseHeight = preset.minH + ((preset.maxH - preset.minH) * rowRand);
            var x = bounds.min_x;
            while (x < bounds.max_x) {
                var widthRand = na_random(seed + Math.floor(x) + (row * 43));
                var width = preset.minW + ((preset.maxW - preset.minW) * widthRand);
                stones.push({ x: x, y: y, width: width, height: courseHeight });
                x += width;
            }
            y += courseHeight;
            row += 1;
        }
        return stones;
    }

    function na_generateUncoursed(bounds, preset, seed) {
        var stones = [];
        var skyline = [{ x: bounds.min_x, width: bounds.width, y: bounds.min_y }];
        var safety = 0;
        while (safety < 6000) {
            safety += 1;
            skyline.sort(function (a, b) { return a.y - b.y; });
            var segment = skyline[0];
            if (!segment || segment.y >= bounds.max_y) {
                break;
            }

            var width = preset.minW + ((preset.maxW - preset.minW) * na_random(seed + safety * 13));
            width = Math.min(width, segment.width);
            var height = preset.minH + ((preset.maxH - preset.minH) * na_random(seed + safety * 19));
            stones.push({ x: segment.x, y: segment.y, width: width, height: height });

            skyline.shift();
            skyline.push({ x: segment.x, width: width, y: segment.y + height });
            if (segment.width - width > preset.minW * 0.6) {
                skyline.push({ x: segment.x + width, width: segment.width - width, y: segment.y });
            }
        }
        return stones;
    }

    function na_generate(context) {
        var bounds = context.faceData.bounds;
        var params = context.params;
        var preset = SIZE_PRESETS[params.stone_size] || SIZE_PRESETS.medium;
        var pattern = params.pattern_type || 'uncoursed';
        var density = Math.max(0, Math.min(100, Number(params.density_pct) || 50)) / 100;
        var renderMode = params.render_mode || 'continuous';
        var seed = Number(params.seed) || Date.now();
        var mortar = Math.max(0, Number(params.mortar_mm) || 10);
        var clipApi = window.Na__FacePattern__PolygonClip;
        var rectApi = window.Na__FacePattern__RectGeometry;
        var noiseApi = window.Na__FacePattern__Noise;

        var stoneRects = pattern === 'coursed'
            ? na_generateCoursed(bounds, preset, seed)
            : na_generateUncoursed(bounds, preset, seed);

        var polylines = [];
        stoneRects.forEach(function (stone, index) {
            if (renderMode === 'artistic') {
                var noiseVal = noiseApi.na_fbmNoise((stone.x + stone.width) * 0.012, (stone.y + stone.height) * 0.012, seed + index, 3);
                if (noiseVal > density) {
                    return;
                }
            }

            var clippedBounds = rectApi.na_clipRectToBounds(
                stone.x + (mortar * 0.5),
                stone.y + (mortar * 0.5),
                Math.max(1, stone.width - mortar),
                Math.max(1, stone.height - mortar),
                bounds
            );
            if (!clippedBounds) {
                return;
            }

            var rect = rectApi.na_makeRectPolyline(clippedBounds.x, clippedBounds.y, clippedBounds.width, clippedBounds.height);
            var kept = clipApi.na_keepWhenCentroidInside(rect, context.faceData.outer, context.faceData.holes);
            if (!kept) {
                return;
            }

            var clipped = clipApi.na_clipPolyline(kept, context.faceData.outer, context.faceData.holes);
            if (clipped.length >= 3) {
                polylines.push(clipped);
            }
        });

        return {
            polylines: polylines,
            status: polylines.length + ' stone units generated.'
        };
    }

    window.Na__FacePattern__StoneworkGenerator = {
        na_generate: na_generate
    };
})();
