(function () {
    'use strict';

    function na_pointInRing(point, ring) {
        var inside = false;
        var i = 0;
        var j = ring.length - 1;
        for (; i < ring.length; i += 1) {
            var xi = ring[i][0];
            var yi = ring[i][1];
            var xj = ring[j][0];
            var yj = ring[j][1];

            var intersects = ((yi > point[1]) !== (yj > point[1])) &&
                (point[0] < (((xj - xi) * (point[1] - yi)) / (yj - yi + 1e-9)) + xi);
            if (intersects) {
                inside = !inside;
            }
            j = i;
        }
        return inside;
    }

    function na_pointInFace(point, outer, holes) {
        if (!na_pointInRing(point, outer)) {
            return false;
        }
        var holeIndex = 0;
        var holeList = holes || [];
        for (; holeIndex < holeList.length; holeIndex += 1) {
            if (na_pointInRing(point, holeList[holeIndex])) {
                return false;
            }
        }
        return true;
    }

    function na_lineIntersection(a, b, c, d) {
        var denominator = ((a[0] - b[0]) * (c[1] - d[1])) - ((a[1] - b[1]) * (c[0] - d[0]));
        if (Math.abs(denominator) < 1e-9) {
            return null;
        }

        var pre = (a[0] * b[1]) - (a[1] * b[0]);
        var post = (c[0] * d[1]) - (c[1] * d[0]);
        var x = ((pre * (c[0] - d[0])) - ((a[0] - b[0]) * post)) / denominator;
        var y = ((pre * (c[1] - d[1])) - ((a[1] - b[1]) * post)) / denominator;

        var inAB = (x >= Math.min(a[0], b[0]) - 1e-6 && x <= Math.max(a[0], b[0]) + 1e-6 &&
                    y >= Math.min(a[1], b[1]) - 1e-6 && y <= Math.max(a[1], b[1]) + 1e-6);
        var inCD = (x >= Math.min(c[0], d[0]) - 1e-6 && x <= Math.max(c[0], d[0]) + 1e-6 &&
                    y >= Math.min(c[1], d[1]) - 1e-6 && y <= Math.max(c[1], d[1]) + 1e-6);
        if (!inAB || !inCD) {
            return null;
        }
        return [x, y];
    }

    function na_segmentIntersections(startPoint, endPoint, ring) {
        var intersections = [];
        for (var index = 0; index < ring.length; index += 1) {
            var nextIndex = (index + 1) % ring.length;
            var hit = na_lineIntersection(startPoint, endPoint, ring[index], ring[nextIndex]);
            if (hit) {
                intersections.push(hit);
            }
        }
        return intersections;
    }

    function na_uniquePoints(points) {
        var seen = {};
        var output = [];
        points.forEach(function (point) {
            var key = point[0].toFixed(5) + '|' + point[1].toFixed(5);
            if (!seen[key]) {
                seen[key] = true;
                output.push(point);
            }
        });
        return output;
    }

    function na_clipPolyline(polyline, outer, holes) {
        if (!polyline || polyline.length < 2) {
            return [];
        }

        var clipped = [];
        for (var index = 0; index < polyline.length; index += 1) {
            var point = polyline[index];
            if (na_pointInFace(point, outer, holes)) {
                clipped.push(point);
            }

            if (index < polyline.length - 1) {
                var nextPoint = polyline[index + 1];
                var hits = na_segmentIntersections(point, nextPoint, outer);
                na_uniquePoints(hits).forEach(function (hitPoint) {
                    clipped.push(hitPoint);
                });
            }
        }

        return na_uniquePoints(clipped);
    }

    function na_keepWhenCentroidInside(polyline, outer, holes) {
        if (!polyline || polyline.length < 3) {
            return null;
        }
        var sumX = 0;
        var sumY = 0;
        polyline.forEach(function (point) {
            sumX += point[0];
            sumY += point[1];
        });
        var centroid = [sumX / polyline.length, sumY / polyline.length];
        return na_pointInFace(centroid, outer, holes) ? polyline : null;
    }

    window.Na__FacePattern__PolygonClip = {
        na_pointInFace: na_pointInFace,
        na_clipPolyline: na_clipPolyline,
        na_keepWhenCentroidInside: na_keepWhenCentroidInside
    };
})();
