(function () {
    'use strict';

    function na_makeRectPolyline(x, y, width, height) {
        return [
            [x, y],
            [x + width, y],
            [x + width, y + height],
            [x, y + height]
        ];
    }

    function na_clipRectToBounds(x, y, width, height, bounds) {
        var minX = Math.max(x, bounds.min_x);
        var minY = Math.max(y, bounds.min_y);
        var maxX = Math.min(x + width, bounds.max_x);
        var maxY = Math.min(y + height, bounds.max_y);

        if (maxX <= minX || maxY <= minY) {
            return null;
        }

        return {
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        };
    }

    function na_centroid(polyline) {
        if (!polyline || !polyline.length) {
            return [0, 0];
        }
        var sumX = 0;
        var sumY = 0;
        polyline.forEach(function (point) {
            sumX += point[0];
            sumY += point[1];
        });
        return [sumX / polyline.length, sumY / polyline.length];
    }

    window.Na__FacePattern__RectGeometry = {
        na_makeRectPolyline: na_makeRectPolyline,
        na_clipRectToBounds: na_clipRectToBounds,
        na_centroid: na_centroid
    };
})();
