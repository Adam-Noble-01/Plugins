// =============================================================================
// NA NOBLE3D MODELLING TOOLS - PNG TO LINEWORK - TRACE ENGINE
// =============================================================================
//
// FILE       : Na__Noble3dModellingTools__PngToLinework__TraceEngine__.js
// NAMESPACE  : window.Na__PngToLinework__TraceEngine
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Raster-to-vector pipeline - decode PNG, verify alpha channel,
//              binarise, trace (centerline or outline), simplify, scale to mm.
// CREATED    : 2026
//
// PIPELINE:
// decode -> alpha check -> binarise on alpha threshold ->
//   centerline : Zhang-Suen thinning -> skeleton path walking
//   outline    : marching squares    -> segment chaining
// -> scale px to mm (Y flipped to model Y-up) -> RDP simplify ->
//    minimum-segment spacing filter -> detail cull -> centre on
//    bounding-box centre -> FINAL vertex merge (weld) pass
//
// =============================================================================

window.Na__PngToLinework__TraceEngine = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Constants
    // -------------------------------------------------------------------------

    var NA_MAX_TRACE_DIMENSION = 2048;                                        // <-- Downscale guard against UI lockups
    var NA_THINNING_MAX_PASSES = 200;
    var NA_OPAQUE_ALPHA_FLOOR  = 250;                                         // <-- Pixels below this alpha prove transparency exists

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Image Decoding
    // -------------------------------------------------------------------------

    // FUNCTION | Decode a Data-URI PNG to ImageData (Downscaled if Oversized)
    // ------------------------------------------------------------
    function na_decodeImage(dataUri) {
        return new Promise(function (resolve, reject) {
            var image = new Image();
            image.onload = function () {
                try {
                    var scale  = Math.min(1, NA_MAX_TRACE_DIMENSION / Math.max(image.naturalWidth, image.naturalHeight));
                    var width  = Math.max(1, Math.round(image.naturalWidth * scale));
                    var height = Math.max(1, Math.round(image.naturalHeight * scale));

                    var canvas    = document.createElement('canvas');
                    canvas.width  = width;
                    canvas.height = height;
                    var context = canvas.getContext('2d', { willReadFrequently: true });
                    context.drawImage(image, 0, 0, width, height);

                    resolve({
                        imageData     : context.getImageData(0, 0, width, height),
                        width         : width,
                        height        : height,
                        naturalWidth  : image.naturalWidth,
                        naturalHeight : image.naturalHeight,
                        wasDownscaled : scale < 1
                    });
                } catch (decodeError) {
                    reject(decodeError);
                }
            };
            image.onerror = function () { reject(new Error('The PNG could not be decoded.')); };
            image.src = dataUri;
        });
    }
    // ------------------------------------------------------------

    // FUNCTION | Confirm the Image Actually Uses Its Alpha Channel
    // ------------------------------------------------------------
    function na_hasAlphaVariation(imageData) {
        var data = imageData.data;
        for (var i = 3; i < data.length; i += 4) {
            if (data[i] < NA_OPAQUE_ALPHA_FLOOR) { return true; }
        }
        return false;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Binarisation (Padded Grid)
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Build a 1px Zero-Padded Solidity Grid from Alpha
    // ------------------------------------------------------------
    function na_binarise(imageData, alphaThreshold) {
        var width   = imageData.width;
        var height  = imageData.height;
        var padW    = width + 2;
        var padH    = height + 2;
        var grid    = new Uint8Array(padW * padH);
        var data    = imageData.data;

        for (var y = 0; y < height; y++) {
            var rowOffset = y * width;
            var padOffset = (y + 1) * padW + 1;
            for (var x = 0; x < width; x++) {
                if (data[(rowOffset + x) * 4 + 3] >= alphaThreshold) {
                    grid[padOffset + x] = 1;
                }
            }
        }
        return { grid: grid, padW: padW, padH: padH };
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Centerline Mode - Zhang-Suen Thinning
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Thin the Solid Grid to a 1px Skeleton In Place
    // ------------------------------------------------------------
    function na_thinSkeleton(grid, padW, padH) {
        var deletions = [];
        var changed   = true;
        var passes    = 0;

        while (changed && passes < NA_THINNING_MAX_PASSES) {
            changed = false;
            for (var sub = 0; sub < 2; sub++) {
                deletions.length = 0;
                for (var y = 1; y < padH - 1; y++) {
                    var row = y * padW;
                    for (var x = 1; x < padW - 1; x++) {
                        var i = row + x;
                        if (!grid[i]) { continue; }

                        var p2 = grid[i - padW];
                        var p3 = grid[i - padW + 1];
                        var p4 = grid[i + 1];
                        var p5 = grid[i + padW + 1];
                        var p6 = grid[i + padW];
                        var p7 = grid[i + padW - 1];
                        var p8 = grid[i - 1];
                        var p9 = grid[i - padW - 1];

                        var solidNeighbours = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9;
                        if (solidNeighbours < 2 || solidNeighbours > 6) { continue; }

                        var transitions = 0;
                        if (!p2 && p3) { transitions++; }
                        if (!p3 && p4) { transitions++; }
                        if (!p4 && p5) { transitions++; }
                        if (!p5 && p6) { transitions++; }
                        if (!p6 && p7) { transitions++; }
                        if (!p7 && p8) { transitions++; }
                        if (!p8 && p9) { transitions++; }
                        if (!p9 && p2) { transitions++; }
                        if (transitions !== 1) { continue; }

                        if (sub === 0) {
                            if (p2 * p4 * p6 !== 0) { continue; }
                            if (p4 * p6 * p8 !== 0) { continue; }
                        } else {
                            if (p2 * p4 * p8 !== 0) { continue; }
                            if (p2 * p6 * p8 !== 0) { continue; }
                        }
                        deletions.push(i);
                    }
                }
                if (deletions.length) {
                    changed = true;
                    for (var d = 0; d < deletions.length; d++) { grid[deletions[d]] = 0; }
                }
            }
            passes++;
        }
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Walk the 1px Skeleton into Pixel-Space Polylines
    // ------------------------------------------------------------
    function na_skeletonToPolylines(grid, padW, padH) {
        var total       = padW * padH;
        var offsets     = [-padW, -padW + 1, 1, padW + 1, padW, padW - 1, -1, -padW - 1];
        var degree      = new Uint8Array(total);
        var visitedPair = {};
        var polylines   = [];
        var i, n;

        for (i = padW; i < total - padW; i++) {
            if (!grid[i]) { continue; }
            var count = 0;
            for (n = 0; n < 8; n++) { if (grid[i + offsets[n]]) { count++; } }
            degree[i] = count;
        }

        function na_pairKey(a, b) { return a < b ? (a * total + b) : (b * total + a); }
        function na_isNode(idx)   { return grid[idx] === 1 && degree[idx] !== 2; }

        function na_walkPath(startIdx, nextIdx) {
            var path = [startIdx, nextIdx];
            visitedPair[na_pairKey(startIdx, nextIdx)] = true;
            var prev = startIdx;
            var cur  = nextIdx;

            while (!na_isNode(cur)) {
                var advanced = false;
                for (var k = 0; k < 8; k++) {
                    var nb = cur + offsets[k];
                    if (!grid[nb] || nb === prev) { continue; }
                    if (visitedPair[na_pairKey(cur, nb)]) { continue; }
                    visitedPair[na_pairKey(cur, nb)] = true;
                    path.push(nb);
                    prev = cur;
                    cur  = nb;
                    advanced = true;
                    break;
                }
                if (!advanced) { break; }                                     // <-- Closed loop returned to start, or dead end
            }
            return path;
        }

        for (i = padW; i < total - padW; i++) {                               // <-- Pass 1: walk from every node (endpoint / junction)
            if (!na_isNode(i)) { continue; }
            for (n = 0; n < 8; n++) {
                var nb = i + offsets[n];
                if (!grid[nb] || visitedPair[na_pairKey(i, nb)]) { continue; }
                polylines.push(na_walkPath(i, nb));
            }
        }

        for (i = padW; i < total - padW; i++) {                               // <-- Pass 2: pure cycles with no junction pixels
            if (!grid[i] || degree[i] !== 2) { continue; }
            for (n = 0; n < 8; n++) {
                var nb2 = i + offsets[n];
                if (!grid[nb2] || visitedPair[na_pairKey(i, nb2)]) { continue; }
                polylines.push(na_walkPath(i, nb2));
                break;
            }
        }

        return polylines.map(function (path) {
            return path.map(function (idx) {
                return [(idx % padW) - 1, Math.floor(idx / padW) - 1];        // <-- Remove the 1px padding offset
            });
        });
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Outline Mode - Marching Squares
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Extract Closed Contour Loops via Marching Squares
    // ------------------------------------------------------------
    function na_outlineToPolylines(grid, padW, padH) {
        var segments  = [];
        var keyScale  = padW * 4;                                             // <-- Endpoint keys use doubled coordinates

        function na_addSegment(x1, y1, x2, y2) {
            segments.push([x1, y1, x2, y2]);
        }

        for (var y = 0; y < padH - 1; y++) {
            var row = y * padW;
            for (var x = 0; x < padW - 1; x++) {
                var tl = grid[row + x];
                var tr = grid[row + x + 1];
                var bl = grid[row + padW + x];
                var br = grid[row + padW + x + 1];
                var caseIndex = tl * 8 + tr * 4 + br * 2 + bl * 1;
                if (caseIndex === 0 || caseIndex === 15) { continue; }

                var top    = [x + 0.5, y      ];
                var right  = [x + 1,   y + 0.5];
                var bottom = [x + 0.5, y + 1  ];
                var left   = [x,       y + 0.5];

                switch (caseIndex) {
                    case 1:  na_addSegment(left[0], left[1], bottom[0], bottom[1]);   break;
                    case 2:  na_addSegment(bottom[0], bottom[1], right[0], right[1]); break;
                    case 3:  na_addSegment(left[0], left[1], right[0], right[1]);     break;
                    case 4:  na_addSegment(top[0], top[1], right[0], right[1]);       break;
                    case 5:  na_addSegment(top[0], top[1], left[0], left[1]);
                             na_addSegment(bottom[0], bottom[1], right[0], right[1]); break;
                    case 6:  na_addSegment(top[0], top[1], bottom[0], bottom[1]);     break;
                    case 7:  na_addSegment(top[0], top[1], left[0], left[1]);         break;
                    case 8:  na_addSegment(top[0], top[1], left[0], left[1]);         break;
                    case 9:  na_addSegment(top[0], top[1], bottom[0], bottom[1]);     break;
                    case 10: na_addSegment(top[0], top[1], right[0], right[1]);
                             na_addSegment(bottom[0], bottom[1], left[0], left[1]);   break;
                    case 11: na_addSegment(top[0], top[1], right[0], right[1]);       break;
                    case 12: na_addSegment(left[0], left[1], right[0], right[1]);     break;
                    case 13: na_addSegment(bottom[0], bottom[1], right[0], right[1]); break;
                    case 14: na_addSegment(left[0], left[1], bottom[0], bottom[1]);   break;
                }
            }
        }

        return na_chainSegments(segments, keyScale);
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Chain Loose Segments into Continuous Polylines
    // ------------------------------------------------------------
    function na_chainSegments(segments, keyScale) {
        var endpointMap = {};
        var used        = new Uint8Array(segments.length);
        var polylines   = [];
        var s;

        function na_pointKey(x, y) { return (x * 2) * keyScale + (y * 2); }

        for (s = 0; s < segments.length; s++) {
            var keys = [na_pointKey(segments[s][0], segments[s][1]), na_pointKey(segments[s][2], segments[s][3])];
            for (var e = 0; e < 2; e++) {
                if (!endpointMap[keys[e]]) { endpointMap[keys[e]] = []; }
                endpointMap[keys[e]].push(s);
            }
        }

        function na_takeNextSegment(x, y, excludeIdx) {
            var candidates = endpointMap[na_pointKey(x, y)] || [];
            for (var c = 0; c < candidates.length; c++) {
                var idx = candidates[c];
                if (used[idx] || idx === excludeIdx) { continue; }
                return idx;
            }
            return -1;
        }

        for (s = 0; s < segments.length; s++) {
            if (used[s]) { continue; }
            used[s] = 1;
            var seg  = segments[s];
            var path = [[seg[0], seg[1]], [seg[2], seg[3]]];

            var guard = segments.length + 2;
            while (guard-- > 0) {                                             // <-- Extend forward until the loop closes
                var tail = path[path.length - 1];
                var idx  = na_takeNextSegment(tail[0], tail[1], -1);
                if (idx < 0) { break; }
                used[idx] = 1;
                var next = segments[idx];
                if (next[0] === tail[0] && next[1] === tail[1]) {
                    path.push([next[2], next[3]]);
                } else {
                    path.push([next[0], next[1]]);
                }
            }
            polylines.push(path.map(function (point) {
                return [point[0] - 1, point[1] - 1];                          // <-- Remove the 1px padding offset
            }));
        }
        return polylines;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Simplification
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Ramer-Douglas-Peucker Polyline Simplification
    // ------------------------------------------------------------
    function na_simplifyRdp(points, epsilon) {
        if (points.length < 3) { return points.slice(); }

        var keep  = new Uint8Array(points.length);
        keep[0]   = 1;
        keep[points.length - 1] = 1;
        var stack = [[0, points.length - 1]];

        while (stack.length) {
            var range = stack.pop();
            var a = range[0];
            var b = range[1];
            var ax = points[a][0], ay = points[a][1];
            var bx = points[b][0], by = points[b][1];
            var dx = bx - ax, dy = by - ay;
            var lengthSq = dx * dx + dy * dy;
            var maxDistSq = -1;
            var maxIndex  = -1;

            for (var i = a + 1; i < b; i++) {
                var px = points[i][0], py = points[i][1];
                var distSq;
                if (lengthSq === 0) {
                    var ddx = px - ax, ddy = py - ay;
                    distSq = ddx * ddx + ddy * ddy;
                } else {
                    var cross = (px - ax) * dy - (py - ay) * dx;
                    distSq = (cross * cross) / lengthSq;
                }
                if (distSq > maxDistSq) { maxDistSq = distSq; maxIndex = i; }
            }

            if (maxDistSq > epsilon * epsilon) {
                keep[maxIndex] = 1;
                stack.push([a, maxIndex]);
                stack.push([maxIndex, b]);
            }
        }

        var result = [];
        for (var k = 0; k < points.length; k++) {
            if (keep[k]) { result.push(points[k]); }
        }
        return result;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Enforce Minimum Vertex Spacing Along a Polyline
    // ------------------------------------------------------------
    function na_enforceMinSegment(points, minLengthMm) {
        if (points.length < 3) { return points.slice(); }

        var result = [points[0]];
        var minSq  = minLengthMm * minLengthMm;

        for (var i = 1; i < points.length - 1; i++) {
            var last = result[result.length - 1];
            var dx = points[i][0] - last[0];
            var dy = points[i][1] - last[1];
            if (dx * dx + dy * dy >= minSq) { result.push(points[i]); }
        }
        result.push(points[points.length - 1]);
        return result;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Final Vertex Merge (Weld) Pass
    // -------------------------------------------------------------------------

    // FUNCTION | Weld All Vertices Within a Distance to Their Cluster Centroid
    // ------------------------------------------------------------
    // Runs as the FINAL pipeline step so it cannot interfere with tracing,
    // simplification, culling, or centring. Clusters are built with union-find
    // over a spatial hash grid, then every vertex snaps to its cluster centroid.
    // Collapsed segments and degenerate polylines are dropped, which removes
    // the small tessellation boxes left at skeleton junctions.
    function na_mergeVertices(polylines, mergeDistanceMm) {
        if (!mergeDistanceMm || mergeDistanceMm <= 0 || !polylines.length) { return polylines; }

        var points = [];
        var p, i;
        for (p = 0; p < polylines.length; p++) {
            for (i = 0; i < polylines[p].length; i++) { points.push(polylines[p][i]); }
        }

        var count  = points.length;
        var parent = new Int32Array(count);
        for (i = 0; i < count; i++) { parent[i] = i; }

        function na_findRoot(index) {
            while (parent[index] !== index) {
                parent[index] = parent[parent[index]];                        // <-- Path halving
                index = parent[index];
            }
            return index;
        }

        function na_unionClusters(a, b) {
            var rootA = na_findRoot(a);
            var rootB = na_findRoot(b);
            if (rootA !== rootB) { parent[rootB] = rootA; }
        }

        var cellSize   = mergeDistanceMm;
        var distanceSq = mergeDistanceMm * mergeDistanceMm;
        var grid       = {};

        for (i = 0; i < count; i++) {                                         // <-- Spatial hash keeps pairing O(n)
            var cellX = Math.floor(points[i][0] / cellSize);
            var cellY = Math.floor(points[i][1] / cellSize);

            for (var gx = cellX - 1; gx <= cellX + 1; gx++) {
                for (var gy = cellY - 1; gy <= cellY + 1; gy++) {
                    var bucket = grid[gx + '_' + gy];
                    if (!bucket) { continue; }
                    for (var b = 0; b < bucket.length; b++) {
                        var j  = bucket[b];
                        var dx = points[i][0] - points[j][0];
                        var dy = points[i][1] - points[j][1];
                        if (dx * dx + dy * dy <= distanceSq) { na_unionClusters(i, j); }
                    }
                }
            }

            var ownKey = cellX + '_' + cellY;
            if (!grid[ownKey]) { grid[ownKey] = []; }
            grid[ownKey].push(i);
        }

        var sumX = {}, sumY = {}, num = {};                                   // <-- Centroid accumulation per cluster root
        for (i = 0; i < count; i++) {
            var root = na_findRoot(i);
            sumX[root] = (sumX[root] || 0) + points[i][0];
            sumY[root] = (sumY[root] || 0) + points[i][1];
            num[root]  = (num[root]  || 0) + 1;
        }

        var welded = [];
        var cursor = 0;
        for (p = 0; p < polylines.length; p++) {
            var rebuilt = [];
            for (i = 0; i < polylines[p].length; i++) {
                var clusterRoot = na_findRoot(cursor++);
                var mergedX = sumX[clusterRoot] / num[clusterRoot];
                var mergedY = sumY[clusterRoot] / num[clusterRoot];
                var last = rebuilt[rebuilt.length - 1];
                if (!last || last[0] !== mergedX || last[1] !== mergedY) {    // <-- Drop segments collapsed to zero length
                    rebuilt.push([mergedX, mergedY]);
                }
            }
            if (rebuilt.length >= 2) { welded.push(rebuilt); }                // <-- Drop polylines collapsed to a point
        }
        return welded;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Full Trace Pipeline
    // -------------------------------------------------------------------------

    // FUNCTION | Trace a Decoded Image into Centred Millimetre Polylines
    // ------------------------------------------------------------
    function na_trace(decoded, options) {
        var binarised = na_binarise(decoded.imageData, options.alphaThreshold);
        var pixelPolylines;

        if (options.traceMode === 'outline') {
            pixelPolylines = na_outlineToPolylines(binarised.grid, binarised.padW, binarised.padH);
        } else {
            na_thinSkeleton(binarised.grid, binarised.padW, binarised.padH);
            pixelPolylines = na_skeletonToPolylines(binarised.grid, binarised.padW, binarised.padH);
        }

        var mmPerPx       = options.realWidthMm / decoded.width;
        var imageHeightMm = decoded.height * mmPerPx;
        var rdpEpsilonMm  = Math.max(options.minSegmentMm * 0.5, mmPerPx * 0.5);

        var minPathLengthMm = options.minPathLengthMm || 0;
        var mmPolylines = [];
        for (var p = 0; p < pixelPolylines.length; p++) {
            var scaled = pixelPolylines[p].map(function (point) {
                return [point[0] * mmPerPx, (decoded.height - point[1]) * mmPerPx];   // <-- Flip image Y-down to model Y-up
            });
            var simplified = na_simplifyRdp(scaled, rdpEpsilonMm);
            simplified     = na_enforceMinSegment(simplified, options.minSegmentMm);
            if (simplified.length < 2) { continue; }
            if (minPathLengthMm > 0 && na_polylineLength(simplified) < minPathLengthMm) { continue; }   // <-- Detail cull
            mmPolylines.push(simplified);
        }

        var centred = na_centrePolylines(mmPolylines);
        var welded  = na_mergeVertices(centred.polylines, options.vertexMergeMm || 0);   // <-- FINAL pass: collapse junction tessellation
        var stats   = na_computeStats(welded);

        return {
            polylines     : welded,
            stats         : stats,
            wasDownscaled : decoded.wasDownscaled,
            mmPerPx       : mmPerPx,
            imageOverlay  : {                                                 // <-- Source-image placement in centred mm space
                minX     : 0 - centred.centreX,
                minY     : 0 - centred.centreY,
                widthMm  : options.realWidthMm,
                heightMm : imageHeightMm
            }
        };
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Total Length of a Polyline in Millimetres
    // ------------------------------------------------------------
    function na_polylineLength(points) {
        var total = 0;
        for (var i = 1; i < points.length; i++) {
            var dx = points[i][0] - points[i - 1][0];
            var dy = points[i][1] - points[i - 1][1];
            total += Math.sqrt(dx * dx + dy * dy);
        }
        return total;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Centre All Polylines on Their Bounding-Box Centre
    // ------------------------------------------------------------
    function na_centrePolylines(polylines) {
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        var p, i;

        for (p = 0; p < polylines.length; p++) {
            for (i = 0; i < polylines[p].length; i++) {
                var point = polylines[p][i];
                if (point[0] < minX) { minX = point[0]; }
                if (point[0] > maxX) { maxX = point[0]; }
                if (point[1] < minY) { minY = point[1]; }
                if (point[1] > maxY) { maxY = point[1]; }
            }
        }

        if (!isFinite(minX)) { return { polylines: [], centreX: 0, centreY: 0 }; }

        var centreX = (minX + maxX) / 2;
        var centreY = (minY + maxY) / 2;

        var centred = polylines.map(function (polyline) {
            return polyline.map(function (point) {
                return [point[0] - centreX, point[1] - centreY];
            });
        });

        return { polylines: centred, centreX: centreX, centreY: centreY };
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Compute Polyline / Vertex / Segment Counts
    // ------------------------------------------------------------
    function na_computeStats(polylines) {
        var vertexCount  = 0;
        var segmentCount = 0;
        for (var p = 0; p < polylines.length; p++) {
            vertexCount  += polylines[p].length;
            segmentCount += polylines[p].length - 1;
        }
        return {
            polylineCount : polylines.length,
            vertexCount   : vertexCount,
            segmentCount  : segmentCount
        };
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    return {
        na_decodeImage       : na_decodeImage,
        na_hasAlphaVariation : na_hasAlphaVariation,
        na_trace             : na_trace
    };

})();

// =============================================================================
// END OF FILE
// =============================================================================
