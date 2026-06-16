(function () {
    'use strict';

    function na_baseShape(type, centerX, centerY, width, height) {
        var points = [];
        var steps = 56;
        var rx = width * 0.5;
        var ry = height * 0.5;

        for (var index = 0; index <= steps; index += 1) {
            var t = (index / steps) * Math.PI * 2;
            var x = centerX + (Math.cos(t) * rx);
            var yScale = 1;

            if (type === 'topiary') {
                yScale = Math.pow(1 - (Math.abs(Math.cos(t)) * 0.7), 1.15);
            } else if (type === 'wild') {
                yScale = 0.85 + (Math.sin((t * 3) + 0.5) * 0.18);
            }

            var y = centerY + (Math.sin(t) * ry * yScale);
            points.push([x, y]);
        }
        return points;
    }

    function na_applyRoughness(polyline, roughnessPct, leafScale) {
        var roughness = Math.max(0, Math.min(100, Number(roughnessPct) || 0)) / 100;
        if (roughness <= 0) {
            return polyline;
        }

        var output = [];
        var amplitude = Math.max(2, Number(leafScale) || 16) * roughness * 0.5;
        for (var index = 0; index < polyline.length; index += 1) {
            var point = polyline[index];
            var jitterX = (Math.sin((index + 1) * 0.7) * amplitude);
            var jitterY = (Math.cos((index + 1) * 0.6) * amplitude);
            output.push([point[0] + jitterX, point[1] + jitterY]);
        }
        return output;
    }

    function na_generate(context) {
        var bounds = context.faceData.bounds;
        var params = context.params;
        var clipApi = window.Na__FacePattern__PolygonClip;
        var centerX = bounds.min_x + (bounds.width * 0.5);
        var centerY = bounds.min_y + (bounds.height * 0.5);
        if (!clipApi.na_pointInFace([centerX, centerY], context.faceData.outer, context.faceData.holes)) {
            for (var sampleX = bounds.min_x; sampleX <= bounds.max_x; sampleX += Math.max(20, bounds.width / 20)) {
                for (var sampleY = bounds.min_y; sampleY <= bounds.max_y; sampleY += Math.max(20, bounds.height / 20)) {
                    if (clipApi.na_pointInFace([sampleX, sampleY], context.faceData.outer, context.faceData.holes)) {
                        centerX = sampleX;
                        centerY = sampleY;
                        sampleX = bounds.max_x + 1;
                        break;
                    }
                }
            }
        }

        var baseWidth = Math.max(200, Number(params.shrub_width_mm) || bounds.width * 0.75);
        var baseHeight = Math.max(200, Number(params.shrub_height_mm) || bounds.height * 0.75);
        var bestPolyline = null;

        for (var attempt = 0; attempt < 5; attempt += 1) {
            var scale = Math.max(0.25, 1 - (attempt * 0.18));
            var shrub = na_baseShape(
                params.shrub_type || 'round',
                centerX,
                centerY,
                baseWidth * scale,
                baseHeight * scale
            );
            shrub = na_applyRoughness(shrub, params.roughness_pct, params.leaf_scale);

            var allInside = true;
            for (var p = 0; p < shrub.length; p += 1) {
                if (!clipApi.na_pointInFace(shrub[p], context.faceData.outer, context.faceData.holes)) {
                    allInside = false;
                    break;
                }
            }

            if (allInside) {
                bestPolyline = shrub;
                break;
            }
        }

        if (!bestPolyline || bestPolyline.length < 3) {
            var interior = na_findInteriorPoint(bounds, context.faceData.outer, context.faceData.holes, clipApi);
            var radius = 30;
            while (interior && radius >= 2) {
                var fallback = [
                    [interior[0], interior[1] + radius],
                    [interior[0] + (radius * 0.866), interior[1] - (radius * 0.5)],
                    [interior[0] - (radius * 0.866), interior[1] - (radius * 0.5)]
                ];
                if (clipApi.na_pointInFace(fallback[0], context.faceData.outer, context.faceData.holes) &&
                    clipApi.na_pointInFace(fallback[1], context.faceData.outer, context.faceData.holes) &&
                    clipApi.na_pointInFace(fallback[2], context.faceData.outer, context.faceData.holes)) {
                    bestPolyline = fallback;
                    break;
                }
                radius -= 5;
            }
        }

        if (!bestPolyline || bestPolyline.length < 3) {
            return { polylines: [], status: 'Shrub shape did not produce valid clipped linework.' };
        }

        return {
            polylines: [bestPolyline],
            status: 'Shrub silhouette generated.'
        };
    }

    function na_findInteriorPoint(bounds, outer, holes, clipApi) {
        var stepX = Math.max(20, bounds.width / 30);
        var stepY = Math.max(20, bounds.height / 30);
        for (var x = bounds.min_x + stepX; x < bounds.max_x - stepX; x += stepX) {
            for (var y = bounds.min_y + stepY; y < bounds.max_y - stepY; y += stepY) {
                var center = [x, y];
                if (!clipApi.na_pointInFace(center, outer, holes)) {
                    continue;
                }
                if (clipApi.na_pointInFace([x + 10, y], outer, holes) &&
                    clipApi.na_pointInFace([x - 10, y], outer, holes) &&
                    clipApi.na_pointInFace([x, y + 10], outer, holes) &&
                    clipApi.na_pointInFace([x, y - 10], outer, holes)) {
                    return center;
                }
            }
        }
        return null;
    }

    window.Na__FacePattern__ShrubGenerator = {
        na_generate: na_generate
    };
})();
