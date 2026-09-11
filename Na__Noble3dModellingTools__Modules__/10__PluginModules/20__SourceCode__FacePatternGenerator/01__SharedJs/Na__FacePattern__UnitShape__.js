// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN - UNIT SHAPE
// =============================================================================
//
// FILE       : Na__FacePattern__UnitShape__.js
// NAMESPACE  : window.Na__FacePattern__UnitShape
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Dresses a clean unit ring into a worked stone outline — corner
//              bevel first, then noise erosion broken off the edges.
// CREATED    : 2026
//
// DESCRIPTION:
// - Bevel runs before erosion, so a tumbled stone reads as a rounded block that
//   has then weathered, not as a rough block with rounded points bolted on.
// - Erosion displacement is inward only. A ring already trimmed to the face can
//   therefore be dressed without any risk of the stone climbing back off it.
// - The noise field is sampled in face space from one wall-level seed, so
//   neighbouring stones weather in step and a joint reads as a real joint.
//
// =============================================================================

window.Na__FacePattern__UnitShape = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Tuning Constants
    // -------------------------------------------------------------------------

    var NA_MIN_EDGE_MM         = 0.5;                                           // <-- Shorter than this and two points count as one
    var NA_BEVEL_SEGMENTS      = 3;                                             // <-- Chords drawn across one rounded corner
    var NA_BEVEL_EDGE_FRACTION = 0.45;                                          // <-- A corner may eat at most this much of either edge
    var NA_MAX_EDGE_SEGMENTS   = 6;                                             // <-- Cap on points inserted along one edge
    var NA_MIN_SEGMENT_MM      = 8;                                             // <-- Shortest erosion segment worth drawing
    var NA_SEGMENT_PER_AMP     = 1.6;                                           // <-- Segment length tracks the erosion depth
    var NA_NOISE_SCALE         = 0.02;                                          // <-- 1/mm, a 50mm base wavelength for the erosion field
    var NA_NOISE_OCTAVES       = 3;
    var NA_MAX_AMP_FRACTION    = 0.30;                                          // <-- Erosion never eats more than this of the short side

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Ring Helpers
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Signed Shoelace Area of a Closed Ring
    // ------------------------------------------------------------
    function na_signedArea(ring) {
        var total = 0;
        for (var index = 0; index < ring.length; index += 1) {
            var current = ring[index];
            var next    = ring[(index + 1) % ring.length];
            total += (current[0] * next[1]) - (next[0] * current[1]);
        }
        return total * 0.5;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Drop Repeated Points and Return a Counter-Clockwise Ring
    // ------------------------------------------------------------
    // Inward normals are derived from the winding, so the ring must be turned
    // the right way round before anything is displaced.
    function na_cleanRing(ring) {
        var cleaned = [];
        ring.forEach(function (point) {
            var last = cleaned[cleaned.length - 1];
            if (last && Math.abs(point[0] - last[0]) < NA_MIN_EDGE_MM && Math.abs(point[1] - last[1]) < NA_MIN_EDGE_MM) { return; }
            cleaned.push([point[0], point[1]]);
        });

        var first = cleaned[0];
        var final = cleaned[cleaned.length - 1];
        if (cleaned.length > 2 && first && final &&
            Math.abs(first[0] - final[0]) < NA_MIN_EDGE_MM && Math.abs(first[1] - final[1]) < NA_MIN_EDGE_MM) {
            cleaned.pop();                                                      // <-- Ring arrived explicitly closed, drop the repeat
        }

        if (cleaned.length < 3) { return null; }
        return na_signedArea(cleaned) < 0 ? cleaned.reverse() : cleaned;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Test Whether a Counter-Clockwise Ring Turns Back on Itself
    // ------------------------------------------------------------
    // A whole stone is convex and its short side bounds every thickness in it.
    // A ring cut against a notched face is not, and can carry a tab far thinner
    // than its own extent — which is what the clearance guard below is for.
    function na_isConcaveRing(ring) {
        var count = ring.length;
        for (var index = 0; index < count; index += 1) {
            var previous = ring[(index - 1 + count) % count];
            var current  = ring[index];
            var next     = ring[(index + 1) % count];
            var cross = ((current[0] - previous[0]) * (next[1] - current[1])) -
                        ((current[1] - previous[1]) * (next[0] - current[0]));
            if (cross < -1e-9) { return true; }
        }
        return false;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | How Far a Point May Travel Inward Before It Meets the Far Side
    // ------------------------------------------------------------
    // Casts the inward direction against the ring's own edges and returns the
    // first hit. Half of that is a safe bite: a 1mm tab left by a trim is then
    // nibbled rather than eaten straight through and out the other side.
    function na_inwardClearance(ring, index, dirX, dirY) {
        var origin = ring[index];
        var count  = ring.length;
        var best   = Infinity;

        for (var edge = 0; edge < count; edge += 1) {
            if (edge === index || ((edge + 1) % count) === index) { continue; } // <-- The two edges meeting at the point itself
            var a = ring[edge];
            var b = ring[(edge + 1) % count];
            var edgeX = b[0] - a[0];
            var edgeY = b[1] - a[1];

            var denominator = (dirX * edgeY) - (dirY * edgeX);
            if (Math.abs(denominator) < 1e-12) { continue; }                    // <-- Ray runs parallel to this edge

            var offsetX = a[0] - origin[0];
            var offsetY = a[1] - origin[1];
            var along   = ((offsetX * edgeY) - (offsetY * edgeX)) / denominator;
            var across  = ((offsetX * dirY) - (offsetY * dirX)) / denominator;

            if (along > 1e-6 && across >= 0 && across <= 1 && along < best) { best = along; }
        }

        return best;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Axis-Aligned Extent of a Ring
    // ------------------------------------------------------------
    function na_ringExtent(ring) {
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        ring.forEach(function (point) {
            if (point[0] < minX) { minX = point[0]; }
            if (point[0] > maxX) { maxX = point[0]; }
            if (point[1] < minY) { minY = point[1]; }
            if (point[1] > maxY) { maxY = point[1]; }
        });
        return { width: maxX - minX, height: maxY - minY };
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Corner Bevel
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Replace Every Corner with a Quadratic Arc
    // ------------------------------------------------------------
    // Each corner is cut back by the bevel radius along both of its edges and
    // rejoined through a quadratic Bezier whose control point is the corner
    // itself, so the arc leaves and meets its edges tangentially.
    function na_bevelRing(ring, radius) {
        var beveled = [];
        var count   = ring.length;

        for (var index = 0; index < count; index += 1) {
            var previous = ring[(index - 1 + count) % count];
            var current  = ring[index];
            var next     = ring[(index + 1) % count];

            var inX  = current[0] - previous[0];
            var inY  = current[1] - previous[1];
            var outX = next[0] - current[0];
            var outY = next[1] - current[1];
            var inLength  = Math.sqrt((inX * inX) + (inY * inY));
            var outLength = Math.sqrt((outX * outX) + (outY * outY));

            if (inLength < NA_MIN_EDGE_MM || outLength < NA_MIN_EDGE_MM) {
                beveled.push(current);
                continue;
            }

            if (((inX * outY) - (inY * outX)) <= 0) {                           // <-- Reflex or straight on a CCW ring
                beveled.push(current);                                          //     A notch in an offcut is a cut, not a weathered
                continue;                                                       //     corner, and arcing it would leave the face
            }

            var cut = Math.min(radius, inLength * NA_BEVEL_EDGE_FRACTION, outLength * NA_BEVEL_EDGE_FRACTION);
            if (cut < NA_MIN_EDGE_MM) {
                beveled.push(current);
                continue;
            }

            var startX = current[0] - ((inX / inLength) * cut);
            var startY = current[1] - ((inY / inLength) * cut);
            var endX   = current[0] + ((outX / outLength) * cut);
            var endY   = current[1] + ((outY / outLength) * cut);

            for (var step = 0; step <= NA_BEVEL_SEGMENTS; step += 1) {
                var t   = step / NA_BEVEL_SEGMENTS;
                var inv = 1 - t;
                beveled.push([
                    (inv * inv * startX) + (2 * inv * t * current[0]) + (t * t * endX),
                    (inv * inv * startY) + (2 * inv * t * current[1]) + (t * t * endY)
                ]);
            }
        }

        return beveled;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Edge Erosion
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Insert Intermediate Points Along Every Edge
    // ------------------------------------------------------------
    // Erosion can only bite where there is a vertex to move, so a long clean
    // edge is broken into segments roughly the size of the bite itself.
    function na_subdivideRing(ring, segmentLength) {
        var dense = [];
        var count = ring.length;

        for (var index = 0; index < count; index += 1) {
            var start = ring[index];
            var end   = ring[(index + 1) % count];
            dense.push(start);

            var deltaX = end[0] - start[0];
            var deltaY = end[1] - start[1];
            var length = Math.sqrt((deltaX * deltaX) + (deltaY * deltaY));
            var pieces = Math.max(1, Math.min(NA_MAX_EDGE_SEGMENTS, Math.round(length / segmentLength)));

            for (var step = 1; step < pieces; step += 1) {
                var t = step / pieces;
                dense.push([start[0] + (deltaX * t), start[1] + (deltaY * t)]);
            }
        }

        return dense;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Pull Every Point Inward by a Noise-Driven Depth
    // ------------------------------------------------------------
    // Direction is the bisector of the two edge normals meeting at the point.
    // Both are normalised first: a raw sum is length-weighted, so a long edge
    // meeting a short one would swing the bisector away from the true inward
    // direction — which is exactly what happens at the seam a concave clip
    // leaves behind. Depth runs 0..amplitude off one FBM field, so the ring is
    // only ever eaten into, never grown.
    function na_displaceRing(ring, amplitude, seed) {
        var noiseApi = window.Na__FacePattern__Noise;
        var count    = ring.length;
        var eroded   = [];
        var guarded  = na_isConcaveRing(ring);                                  // <-- Only an offcut needs the per-point clearance cast

        for (var index = 0; index < count; index += 1) {
            var previous = ring[(index - 1 + count) % count];
            var current  = ring[index];
            var next     = ring[(index + 1) % count];

            var inX  = current[1] - previous[1];                                // <-- Outward normal of a CCW edge is (dy, -dx)
            var inY  = previous[0] - current[0];
            var outX = next[1] - current[1];
            var outY = current[0] - next[0];
            var inLength  = Math.sqrt((inX * inX) + (inY * inY));
            var outLength = Math.sqrt((outX * outX) + (outY * outY));
            if (inLength < 1e-9 || outLength < 1e-9) {
                eroded.push(current);
                continue;
            }

            var normalX = (inX / inLength) + (outX / outLength);
            var normalY = (inY / inLength) + (outY / outLength);
            var length  = Math.sqrt((normalX * normalX) + (normalY * normalY));
            if (length < 1e-6) {                                                // <-- Edges double back on themselves, no inward to find
                eroded.push(current);
                continue;
            }

            var stepX = normalX / length;
            var stepY = normalY / length;
            var depth = amplitude * noiseApi.na_fbmNoise(
                current[0] * NA_NOISE_SCALE,
                current[1] * NA_NOISE_SCALE,
                seed,
                NA_NOISE_OCTAVES
            );

            if (guarded) {
                depth = Math.min(depth, na_inwardClearance(ring, index, -stepX, -stepY) * 0.5);
            }

            eroded.push([
                current[0] - (stepX * depth),
                current[1] - (stepY * depth)
            ]);
        }

        return eroded;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Dressing Pass
    // -------------------------------------------------------------------------

    // FUNCTION | Bevel Then Erode One Unit Ring
    // ------------------------------------------------------------
    // options: { bevel_mm, amplitude_mm, seed }. Returns the ring untouched when
    // neither dressing step has anything to do, so zero settings cost nothing.
    function na_dressRing(ring, options) {
        if (!ring || ring.length < 3) { return ring; }

        var bevelMm     = Math.max(0, Number(options.bevel_mm) || 0);
        var amplitudeMm = Math.max(0, Number(options.amplitude_mm) || 0);
        if (bevelMm < NA_MIN_EDGE_MM && amplitudeMm < NA_MIN_EDGE_MM) { return ring; }

        var working = na_cleanRing(ring);
        if (!working) { return ring; }

        var extent    = na_ringExtent(working);
        var shortSide = Math.min(extent.width, extent.height);
        if (shortSide < NA_MIN_EDGE_MM * 4) { return ring; }                    // <-- Sliver offcut, leave it exactly as cut

        var bevel     = Math.min(bevelMm, shortSide * NA_BEVEL_EDGE_FRACTION);
        var amplitude = Math.min(amplitudeMm, shortSide * NA_MAX_AMP_FRACTION);
        var seed      = Number(options.seed) || 0;

        if (bevel >= NA_MIN_EDGE_MM) { working = na_bevelRing(working, bevel); }

        if (amplitude >= NA_MIN_EDGE_MM) {
            var segmentLength = Math.max(NA_MIN_SEGMENT_MM, amplitude * NA_SEGMENT_PER_AMP);
            working = na_displaceRing(na_subdivideRing(working, segmentLength), amplitude, seed);
        }

        return working.length >= 3 ? working : ring;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    return {
        na_dressRing: na_dressRing
    };

})();

// =============================================================================
// END OF FILE
// =============================================================================
