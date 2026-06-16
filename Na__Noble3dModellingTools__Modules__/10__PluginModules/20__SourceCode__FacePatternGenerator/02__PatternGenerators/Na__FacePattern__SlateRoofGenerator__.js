(function () {
    'use strict';

    var PRESETS = {
        slate_600x300_100: { length: 600, width: 300, headlap: 100 },
        slate_500x300_100: { length: 500, width: 300, headlap: 100 },
        slate_500x250_100: { length: 500, width: 250, headlap: 100 },
        slate_460x220_80: { length: 460, width: 220, headlap: 80 },
        slate_400x250_75: { length: 400, width: 250, headlap: 75 },
        custom: { length: 500, width: 250, headlap: 100 }
    };

    function na_getSlateOptions(params) {
        var preset = PRESETS[params.preset_key] || PRESETS.custom;
        return {
            slateLength: Number(params.slate_length_mm) || preset.length,
            slateWidth: Number(params.slate_width_mm) || preset.width,
            headlap: Number(params.headlap_mm) || preset.headlap,
            sideGap: Math.max(0, Number(params.side_gap_mm) || 0),
            stagger: params.stagger !== false
        };
    }

    function na_generate(context) {
        var bounds = context.faceData.bounds;
        var params = context.params;
        var options = na_getSlateOptions(params);
        var visibleGauge = (options.slateLength - options.headlap) / 2;
        if (visibleGauge <= 0 || options.slateWidth <= 0) {
            return { polylines: [], status: 'Slate settings are invalid.' };
        }

        var clipApi = window.Na__FacePattern__PolygonClip;
        var rectApi = window.Na__FacePattern__RectGeometry;
        var xStep = options.slateWidth + options.sideGap;
        var yStep = visibleGauge;
        var polylines = [];
        var row = 0;

        for (var y = bounds.min_y - yStep; y <= bounds.max_y + yStep; y += yStep) {
            var rowOffset = options.stagger && (row % 2 === 1) ? -(xStep * 0.5) : 0;
            for (var x = bounds.min_x - xStep + rowOffset; x <= bounds.max_x + xStep; x += xStep) {
                var slate = rectApi.na_makeRectPolyline(x, y, options.slateWidth, visibleGauge);
                var inside = true;
                slate.forEach(function (point) {
                    if (!clipApi.na_pointInFace(point, context.faceData.outer, context.faceData.holes)) {
                        inside = false;
                    }
                });
                if (inside) {
                    polylines.push(slate);
                }
            }
            row += 1;
        }

        return {
            polylines: polylines,
            status: polylines.length + ' slate previews generated.',
            slateOptions: options,
            visibleGauge: visibleGauge
        };
    }

    window.Na__FacePattern__SlateRoofGenerator = {
        na_generate: na_generate
    };
})();
