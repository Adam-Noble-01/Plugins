// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN - PATIO GENERATOR
// =============================================================================
//
// FILE       : Na__FacePattern__PatioGenerator__.js
// NAMESPACE  : window.Na__FacePattern__PatioGenerator
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Greedy grid packer with six weighted tile types (1×1 to 3×2
//              module units), clipped to the face polygon.
// CREATED    : 2026
//
// =============================================================================

window.Na__FacePattern__PatioGenerator = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Tile Types
    // -------------------------------------------------------------------------

    var NA_TILE_TYPES = [
        { w: 3, h: 2, weight: 12 },
        { w: 2, h: 3, weight: 12 },
        { w: 2, h: 2, weight: 20 },
        { w: 2, h: 1, weight: 25 },
        { w: 1, h: 2, weight: 25 },
        { w: 1, h: 1, weight: 10 }
    ];

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Grid Packing Helpers
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Return Tile Types Sorted by a Seed-Driven Score
    // ------------------------------------------------------------
    function na_randomizedTileList(seed) {
        var list = NA_TILE_TYPES.slice();
        list.sort(function (a, b) {
            var scoreA = (a.w * a.h) * Math.sin(seed + a.weight);
            var scoreB = (b.w * b.h) * Math.sin(seed + b.weight);
            return scoreB - scoreA;
        });
        return list;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Test Whether a Tile Fits in the Occupancy Grid
    // ------------------------------------------------------------
    function na_canFit(grid, x, y, width, height, maxW, maxH) {
        if (x + width > maxW || y + height > maxH) { return false; }
        for (var ix = 0; ix < width; ix += 1) {
            for (var iy = 0; iy < height; iy += 1) {
                if (grid[x + ix][y + iy]) { return false; }
            }
        }
        return true;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Mark Grid Cells as Occupied
    // ------------------------------------------------------------
    function na_markGrid(grid, x, y, width, height) {
        for (var ix = 0; ix < width; ix += 1) {
            for (var iy = 0; iy < height; iy += 1) {
                grid[x + ix][y + iy] = true;
            }
        }
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Generator
    // -------------------------------------------------------------------------

    // FUNCTION | Generate Patio Tile Polylines for the Selected Face
    // ------------------------------------------------------------
    function na_buildPatio(context) {
        var bounds    = context.faceData.bounds;
        var params    = context.params;
        var moduleSize = Math.max(100, Number(params.module_mm) || 300);
        var joint     = Math.max(0, Number(params.joint_mm) || 0);
        var trimToFace = params.trim_to_face !== false;
        var seed      = Number(params.seed) || Date.now();
        var clipApi   = window.Na__FacePattern__RectClip;
        var rectApi   = window.Na__FacePattern__RectGeometry;

        var overshoot = trimToFace ? 1 : 0;                                     // <-- One spare module ring to trim back
        var originX   = bounds.min_x - (overshoot * moduleSize);
        var originY   = bounds.min_y - (overshoot * moduleSize);
        var gridW = Math.ceil(bounds.width / moduleSize) + (overshoot * 2);
        var gridH = Math.ceil(bounds.height / moduleSize) + (overshoot * 2);
        var grid  = [];
        for (var gx = 0; gx < gridW; gx += 1) {
            grid[gx] = [];
            for (var gy = 0; gy < gridH; gy += 1) {
                grid[gx][gy] = false;
            }
        }

        var rawPolylines = [];
        for (var y = 0; y < gridH; y += 1) {
            for (var x = 0; x < gridW; x += 1) {
                if (grid[x][y]) { continue; }

                var placed     = false;
                var candidates = na_randomizedTileList(seed + (x * 97) + (y * 13));
                for (var index = 0; index < candidates.length; index += 1) {
                    var tile = candidates[index];
                    if (!na_canFit(grid, x, y, tile.w, tile.h, gridW, gridH)) { continue; }

                    na_markGrid(grid, x, y, tile.w, tile.h);
                    placed = true;

                    var rectX = originX + (x * moduleSize) + (joint * 0.5);
                    var rectY = originY + (y * moduleSize) + (joint * 0.5);
                    var rectW = (tile.w * moduleSize) - joint;
                    var rectH = (tile.h * moduleSize) - joint;
                    rawPolylines.push(rectApi.na_makeRectPolyline(rectX, rectY, rectW, rectH));
                    break;
                }

                if (!placed) {
                    na_markGrid(grid, x, y, 1, 1);
                    rawPolylines.push(rectApi.na_makeRectPolyline(
                        originX + (x * moduleSize),
                        originY + (y * moduleSize),
                        moduleSize,
                        moduleSize
                    ));
                }
            }
        }

        var clippedPolylines = [];
        var tileCount        = 0;
        rawPolylines.forEach(function (polyline) {
            var pieces = clipApi.na_unitPolylines(
                polyline[0][0],
                polyline[0][1],
                polyline[1][0] - polyline[0][0],
                polyline[3][1] - polyline[0][1],
                context.faceData,
                trimToFace
            );
            if (!pieces.length) { return; }

            pieces.forEach(function (piece) { clippedPolylines.push(piece); });
            tileCount += 1;
        });

        return {
            polylines: clippedPolylines,
            status: tileCount + ' patio tiles generated' + (trimToFace ? ' (trimmed to face).' : ' (whole tiles only).')
        };
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    return {
        na_generate: na_buildPatio
    };

})();

// =============================================================================
// END OF FILE
// =============================================================================
