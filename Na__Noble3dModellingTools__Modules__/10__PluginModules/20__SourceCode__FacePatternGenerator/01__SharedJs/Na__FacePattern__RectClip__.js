// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN - RECT CLIP
// =============================================================================
//
// FILE       : Na__FacePattern__RectClip__.js
// NAMESPACE  : window.Na__FacePattern__RectClip
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Trim one pattern unit (an axis-aligned rectangle, or any convex
//              ring, in local face millimetres) back to the selected face
//              perimeter, so patterns can overshoot the face and be cut to the
//              boundary on apply.
// CREATED    : 2026
//
// DESCRIPTION:
// - Sutherland-Hodgman clips the face ring against the unit's half-planes. The
//   clip window is the unit (always convex), so concave face outlines - hips,
//   valleys, dormer cheeks - clip correctly.
// - na_clipUnitRect takes an axis-aligned rectangle; na_clipUnitPolygon takes
//   any convex ring, which is what the rotated and herringbone floor tiling
//   units need. Both run the same window / opening / full-cover logic.
// - Holes are subtracted with a convex half-plane decomposition when the hole
//   footprint inside the unit is convex (window and door openings); concave
//   hole footprints fall back to dropping units centred in the opening.
// - Mirrored by Na__Noble3dModellingTools__FacePatternGenerator__RectClip__.rb
//   so the SVG preview and the applied SketchUp geometry agree.
//
// =============================================================================

window.Na__FacePattern__RectClip = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Constants
    // -------------------------------------------------------------------------

    var NA_EPSILON        = 1e-6;                                               // <-- Millimetre tolerance for on-edge points
    var NA_AREA_FRACTION  = 1e-4;                                               // <-- Sliver / full-cover area tolerance as a rect fraction
    var NA_MIN_AREA_MM2   = 1e-3;                                               // <-- Absolute floor for the sliver area test

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Ring Primitives
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Signed Area of a Closed Ring (Shoelace)
    // ------------------------------------------------------------
    function na_ringArea(ring) {
        if (!ring || ring.length < 3) { return 0; }
        var area = 0;
        for (var index = 0; index < ring.length; index += 1) {
            var current = ring[index];
            var next    = ring[(index + 1) % ring.length];
            area += (current[0] * next[1]) - (next[0] * current[1]);
        }
        return area / 2;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Arithmetic Centroid of a Ring
    // ------------------------------------------------------------
    function na_ringCentroid(ring) {
        var sumX = 0;
        var sumY = 0;
        ring.forEach(function (point) {
            sumX += point[0];
            sumY += point[1];
        });
        return [sumX / ring.length, sumY / ring.length];
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Drop Consecutive Duplicate Vertices Including the Wrap
    // ------------------------------------------------------------
    function na_dedupeRing(ring) {
        if (!ring || ring.length < 2) { return ring || []; }

        var output = [];
        ring.forEach(function (point) {
            var previous = output[output.length - 1];
            if (previous && Math.abs(previous[0] - point[0]) < NA_EPSILON && Math.abs(previous[1] - point[1]) < NA_EPSILON) { return; }
            output.push(point);
        });

        while (output.length > 1) {
            var first = output[0];
            var last  = output[output.length - 1];
            if (Math.abs(first[0] - last[0]) >= NA_EPSILON || Math.abs(first[1] - last[1]) >= NA_EPSILON) { break; }
            output.pop();                                                       // <-- Ring is implicitly closed, no repeated end point
        }

        return output;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Test Whether a Ring Turns the Same Way at Every Corner
    // ------------------------------------------------------------
    function na_isConvexRing(ring) {
        if (!ring || ring.length < 3) { return false; }

        var sign = 0;
        for (var index = 0; index < ring.length; index += 1) {
            var a = ring[index];
            var b = ring[(index + 1) % ring.length];
            var c = ring[(index + 2) % ring.length];
            var cross = ((b[0] - a[0]) * (c[1] - b[1])) - ((b[1] - a[1]) * (c[0] - b[0]));
            if (Math.abs(cross) < NA_EPSILON) { continue; }                     // <-- Collinear run, no turn to judge

            var turn = cross > 0 ? 1 : -1;
            if (sign === 0) { sign = turn; }
            else if (turn !== sign) { return false; }
        }
        return sign !== 0;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Return the Ring Wound Counter-Clockwise
    // ------------------------------------------------------------
    function na_toCounterClockwise(ring) {
        return na_ringArea(ring) < 0 ? ring.slice().reverse() : ring;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Half-Plane Clipping
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Interpolate the Crossing Point Between Two Signed Distances
    // ------------------------------------------------------------
    function na_interpolate(pointA, pointB, distanceA, distanceB) {
        var span = distanceA - distanceB;
        if (Math.abs(span) < 1e-12) { return [pointA[0], pointA[1]]; }

        var ratio = distanceA / span;
        return [
            pointA[0] + ((pointB[0] - pointA[0]) * ratio),
            pointA[1] + ((pointB[1] - pointA[1]) * ratio)
        ];
    }
    // ------------------------------------------------------------

    // FUNCTION | Sutherland-Hodgman Clip of a Ring Against One Half-Plane
    // ------------------------------------------------------------
    // distanceFn returns a positive signed distance for points to keep. The
    // subject ring may be concave; the half-plane is trivially convex.
    function na_clipRingToHalfPlane(ring, distanceFn) {
        if (!ring || ring.length < 3) { return []; }

        var output           = [];
        var previous         = ring[ring.length - 1];
        var previousDistance = distanceFn(previous);

        for (var index = 0; index < ring.length; index += 1) {
            var current         = ring[index];
            var currentDistance = distanceFn(current);

            if (currentDistance >= -NA_EPSILON) {
                if (previousDistance < -NA_EPSILON) {
                    output.push(na_interpolate(previous, current, previousDistance, currentDistance));
                }
                output.push(current);
            } else if (previousDistance >= -NA_EPSILON) {
                output.push(na_interpolate(previous, current, previousDistance, currentDistance));
            }

            previous         = current;
            previousDistance = currentDistance;
        }

        return output;
    }
    // ------------------------------------------------------------

    // FUNCTION | Clip a Ring to an Axis-Aligned Rectangle
    // ------------------------------------------------------------
    function na_clipRingToRect(ring, rect) {
        var result = ring;
        result = na_clipRingToHalfPlane(result, function (point) { return point[0] - rect.minX; });
        result = na_clipRingToHalfPlane(result, function (point) { return rect.maxX - point[0]; });
        result = na_clipRingToHalfPlane(result, function (point) { return point[1] - rect.minY; });
        result = na_clipRingToHalfPlane(result, function (point) { return rect.maxY - point[1]; });
        return na_dedupeRing(result);
    }
    // ------------------------------------------------------------

    // FUNCTION | Clip a Ring to an Arbitrary Convex Window Ring
    // ------------------------------------------------------------
    // The rectangle case above is this with four axis-aligned edges; rotated
    // and herringbone units need the general form. The window is wound
    // counter-clockwise so "inside" is left of every directed edge.
    function na_clipRingToConvex(ring, windowRing) {
        var clipWindow = na_toCounterClockwise(windowRing);
        var result     = ring;

        for (var index = 0; index < clipWindow.length; index += 1) {
            if (!result || result.length < 3) { return []; }

            var edgeStart = clipWindow[index];
            var edgeEnd   = clipWindow[(index + 1) % clipWindow.length];
            var edgeX     = edgeEnd[0] - edgeStart[0];
            var edgeY     = edgeEnd[1] - edgeStart[1];
            if ((edgeX * edgeX) + (edgeY * edgeY) < NA_EPSILON) { continue; }   // <-- Degenerate edge, nothing to clip against

            result = na_clipRingToHalfPlane(result, function (point) {
                return (edgeX * (point[1] - edgeStart[1])) - (edgeY * (point[0] - edgeStart[0]));
            });
        }

        return na_dedupeRing(result);
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Convex Hole Subtraction
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Subtract One Convex Hole Ring from a Set of Regions
    // ------------------------------------------------------------
    // For a counter-clockwise hole, "inside" is left of every directed edge.
    // Walking the edges and peeling off the outside slice of each one yields a
    // disjoint decomposition of region minus hole with no overlaps.
    function na_subtractConvexRing(regions, holeRing, areaTolerance) {
        var hole   = na_toCounterClockwise(holeRing);
        var pieces = [];

        regions.forEach(function (region) {
            var remainder = region;

            for (var index = 0; index < hole.length; index += 1) {
                if (remainder.length < 3) { break; }

                var edgeStart = hole[index];
                var edgeEnd   = hole[(index + 1) % hole.length];
                var edgeX     = edgeEnd[0] - edgeStart[0];
                var edgeY     = edgeEnd[1] - edgeStart[1];
                if ((edgeX * edgeX) + (edgeY * edgeY) < NA_EPSILON) { continue; }

                var outsideSlice = na_clipRingToHalfPlane(remainder, function (point) {
                    return -((edgeX * (point[1] - edgeStart[1])) - (edgeY * (point[0] - edgeStart[0])));
                });
                outsideSlice = na_dedupeRing(outsideSlice);
                if (Math.abs(na_ringArea(outsideSlice)) > areaTolerance) { pieces.push(outsideSlice); }

                remainder = na_dedupeRing(na_clipRingToHalfPlane(remainder, function (point) {
                    return (edgeX * (point[1] - edgeStart[1])) - (edgeY * (point[0] - edgeStart[0]));
                }));
            }
        });

        return pieces;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Unit Clipping
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Trim the Face to One Convex Unit Window, Openings Removed
    // ------------------------------------------------------------
    // clipToWindow trims any ring to the unit; makeWholeUnit is only called on
    // the full-cover path, so the untrimmed ring costs nothing when it is cut.
    function na_clipUnitWindow(clipToWindow, unitArea, makeWholeUnit, outer, holes) {
        if (!(unitArea > 0) || !outer || outer.length < 3) {
            return { polylines: [], full: false };
        }

        var areaTolerance = Math.max(NA_MIN_AREA_MM2, unitArea * NA_AREA_FRACTION);
        var clipApi       = window.Na__FacePattern__PolygonClip;

        var region = clipToWindow(outer);
        if (Math.abs(na_ringArea(region)) <= areaTolerance) { return { polylines: [], full: false }; }

        var regions = [region];
        (holes || []).forEach(function (hole) {
            if (!regions.length || !hole || hole.length < 3) { return; }

            var holeFootprint = clipToWindow(hole);
            if (Math.abs(na_ringArea(holeFootprint)) <= areaTolerance) { return; }   // <-- Opening misses this unit

            if (na_isConvexRing(holeFootprint)) {
                regions = na_subtractConvexRing(regions, holeFootprint, areaTolerance);
                return;
            }

            regions = regions.filter(function (piece) {                             // <-- Concave opening: keep units clear of it
                return !clipApi.na_pointInFace(na_ringCentroid(piece), hole, []);
            });
        });

        if (!regions.length) { return { polylines: [], full: false }; }

        var coveredArea = regions.reduce(function (total, piece) {
            return total + Math.abs(na_ringArea(piece));
        }, 0);

        if (regions.length === 1 && coveredArea >= unitArea - areaTolerance) {
            return { polylines: [makeWholeUnit()], full: true };                     // <-- Whole unit fits, keep the clean outline
        }

        return {
            polylines: regions.filter(function (piece) { return piece.length >= 3; }),
            full: false
        };
    }
    // ------------------------------------------------------------

    // FUNCTION | Trim One Rectangular Pattern Unit to the Face Outline
    // ------------------------------------------------------------
    // Returns { polylines, full } where full flags a unit that survived whole
    // and can therefore stay a clean rectangle (or a component instance).
    function na_clipUnitRect(x, y, width, height, outer, holes) {
        if (width <= 0 || height <= 0) { return { polylines: [], full: false }; }

        var rect = { minX: x, minY: y, maxX: x + width, maxY: y + height };
        return na_clipUnitWindow(
            function (ring) { return na_clipRingToRect(ring, rect); },
            width * height,
            function () { return window.Na__FacePattern__RectGeometry.na_makeRectPolyline(x, y, width, height); },
            outer,
            holes
        );
    }
    // ------------------------------------------------------------

    // FUNCTION | Trim One Convex Polygon Pattern Unit to the Face Outline
    // ------------------------------------------------------------
    // The rotated and herringbone floor units are convex quads rather than
    // axis-aligned rectangles; everything downstream is identical.
    function na_clipUnitPolygon(unitRing, outer, holes) {
        if (!unitRing || unitRing.length < 3) { return { polylines: [], full: false }; }

        return na_clipUnitWindow(
            function (ring) { return na_clipRingToConvex(ring, unitRing); },
            Math.abs(na_ringArea(unitRing)),
            function () { return unitRing; },
            outer,
            holes
        );
    }
    // ------------------------------------------------------------

    // FUNCTION | Build the Polylines for One Unit, Honouring the Trim Toggle
    // ------------------------------------------------------------
    // Trim off keeps only units that sit wholly on the face, matching the
    // "complete elements only" mode; trim on overshoots and cuts to the edge.
    function na_unitPolylines(x, y, width, height, faceData, trimEnabled) {
        if (trimEnabled === false) {
            var rect    = window.Na__FacePattern__RectGeometry.na_makeRectPolyline(x, y, width, height);
            var clipApi = window.Na__FacePattern__PolygonClip;
            var inside  = rect.every(function (point) {
                return clipApi.na_pointInFace(point, faceData.outer, faceData.holes);
            });
            return inside ? [rect] : [];
        }

        return na_clipUnitRect(x, y, width, height, faceData.outer, faceData.holes).polylines;
    }
    // ------------------------------------------------------------

    // FUNCTION | Build the Polylines for One Convex Unit Ring, Honouring the Trim Toggle
    // ------------------------------------------------------------
    function na_unitPolygonPolylines(unitRing, faceData, trimEnabled) {
        if (!unitRing || unitRing.length < 3) { return []; }

        if (trimEnabled === false) {
            var clipApi = window.Na__FacePattern__PolygonClip;
            var inside  = unitRing.every(function (point) {
                return clipApi.na_pointInFace(point, faceData.outer, faceData.holes);
            });
            return inside ? [unitRing] : [];
        }

        return na_clipUnitPolygon(unitRing, faceData.outer, faceData.holes).polylines;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Segment Clipping
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Collect Segment Parameters Where a Ring Is Crossed
    // ------------------------------------------------------------
    function na_collectRingCrossings(startPoint, endPoint, ring, parameters) {
        var deltaX = endPoint[0] - startPoint[0];
        var deltaY = endPoint[1] - startPoint[1];

        for (var index = 0; index < ring.length; index += 1) {
            var edgeStart = ring[index];
            var edgeEnd   = ring[(index + 1) % ring.length];
            var edgeX     = edgeEnd[0] - edgeStart[0];
            var edgeY     = edgeEnd[1] - edgeStart[1];

            var denominator = (deltaX * edgeY) - (deltaY * edgeX);
            if (Math.abs(denominator) < 1e-12) { continue; }                    // <-- Parallel or degenerate edge

            var offsetX = edgeStart[0] - startPoint[0];
            var offsetY = edgeStart[1] - startPoint[1];
            var t = ((offsetX * edgeY) - (offsetY * edgeX)) / denominator;
            var u = ((offsetX * deltaY) - (offsetY * deltaX)) / denominator;
            if (t <= 0 || t >= 1 || u < 0 || u > 1) { continue; }

            parameters.push(t);
        }
    }
    // ------------------------------------------------------------

    // FUNCTION | Clip a Straight Segment to the Face, Returning Inside Runs
    // ------------------------------------------------------------
    function na_clipSegment(startPoint, endPoint, outer, holes) {
        var parameters = [0, 1];
        na_collectRingCrossings(startPoint, endPoint, outer, parameters);
        (holes || []).forEach(function (hole) { na_collectRingCrossings(startPoint, endPoint, hole, parameters); });
        parameters.sort(function (a, b) { return a - b; });

        var clipApi  = window.Na__FacePattern__PolygonClip;
        var segments = [];
        for (var index = 0; index < parameters.length - 1; index += 1) {
            var t0 = parameters[index];
            var t1 = parameters[index + 1];
            if (t1 - t0 < 1e-9) { continue; }

            var midpoint = na_pointAt(startPoint, endPoint, (t0 + t1) / 2);
            if (!clipApi.na_pointInFace(midpoint, outer, holes)) { continue; }

            segments.push([na_pointAt(startPoint, endPoint, t0), na_pointAt(startPoint, endPoint, t1)]);
        }
        return segments;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Evaluate a Point Along a Segment Parameter
    // ------------------------------------------------------------
    function na_pointAt(startPoint, endPoint, t) {
        return [
            startPoint[0] + ((endPoint[0] - startPoint[0]) * t),
            startPoint[1] + ((endPoint[1] - startPoint[1]) * t)
        ];
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    return {
        na_clipRingToRect: na_clipRingToRect,
        na_clipRingToConvex: na_clipRingToConvex,
        na_clipUnitRect: na_clipUnitRect,
        na_clipUnitPolygon: na_clipUnitPolygon,
        na_unitPolylines: na_unitPolylines,
        na_unitPolygonPolylines: na_unitPolygonPolylines,
        na_clipSegment: na_clipSegment,
        na_ringArea: na_ringArea,
        na_isConvexRing: na_isConvexRing
    };

})();

// =============================================================================
// END OF FILE
// =============================================================================
