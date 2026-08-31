// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN - FLOOR TILING GENERATOR
// =============================================================================
//
// FILE       : Na__FacePattern__FloorTilingGenerator__.js
// NAMESPACE  : window.Na__FacePattern__FloorTilingGenerator
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Rectangular floor tile / paving slab layouts — stack bond,
//              running (brick) bond at any course offset, herringbone and
//              basketweave — at any pattern rotation, with an optional joint.
// CREATED    : 2026
//
// DESCRIPTION:
// - Every layout is built in a rotated "pattern space" whose origin sits at the
//   face bounding-box centre (or its min corner for corner setting out). Units
//   are emitted as four-point rings already rotated back into face-local
//   millimetres, then trimmed by Na__FacePattern__RectClip.
// - Joint 0 draws a gapless hatch: neighbouring tiles share their edge, which
//   is what a plan-scale floor finish wants. Any joint above 0 insets each unit
//   inside its lattice cell so every gap reads the same width.
// - Herringbone uses the general lattice u = (Lj + Wj, Lj - Wj), v = (-Wj, Wj)
//   over cell sizes Lj = length + joint and Wj = width + joint. Its determinant
//   is exactly two cell areas, so the pair tiles the plane gaplessly at any
//   tile proportion, not only the classic 2:1.
//
// =============================================================================

window.Na__FacePattern__FloorTilingGenerator = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Bond Definitions and Limits
    // -------------------------------------------------------------------------

    var NA_BOND_FAMILY = {
        stack:           'grid',
        running_half:    'grid',
        running_third:   'grid',
        running_quarter: 'grid',
        stack_diagonal:  'grid',
        herringbone:     'herringbone',
        herringbone_45:  'herringbone',
        basketweave:     'basketweave'
    };

    var NA_BOND_LABELS = {
        stack:           'stack bond',
        running_half:    'running bond',
        running_third:   'running bond',
        running_quarter: 'running bond',
        stack_diagonal:  'diagonal stack bond',
        herringbone:     'herringbone',
        herringbone_45:  'herringbone',
        basketweave:     'basketweave'
    };

    var NA_MIN_TILE_MM     = 5;                                                 // <-- Floor on either tile dimension
    var NA_MAX_UNIT_COUNT  = 24000;                                             // <-- Preview guard against a runaway cell count
    var NA_MAX_WEAVE_COUNT = 12;                                                // <-- Courses per basketweave block

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Pattern Space Frame
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Build the Rotated Frame Mapping Pattern Space to Face Space
    // ------------------------------------------------------------
    function na_buildFrame(bounds, rotationDeg) {
        var radians = ((Number(rotationDeg) || 0) * Math.PI) / 180;
        return {
            cos:   Math.cos(radians),
            sin:   Math.sin(radians),
            pivot: [bounds.min_x + (bounds.width * 0.5), bounds.min_y + (bounds.height * 0.5)]
        };
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Map a Pattern-Space Point into Face-Local Millimetres
    // ------------------------------------------------------------
    function na_toFaceSpace(point, frame) {
        return [
            (point[0] * frame.cos) - (point[1] * frame.sin) + frame.pivot[0],
            (point[0] * frame.sin) + (point[1] * frame.cos) + frame.pivot[1]
        ];
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Map a Face-Local Point back into Pattern Space
    // ------------------------------------------------------------
    function na_toPatternSpace(point, frame) {
        var dx = point[0] - frame.pivot[0];
        var dy = point[1] - frame.pivot[1];
        return [
            (dx * frame.cos) + (dy * frame.sin),
            (dy * frame.cos) - (dx * frame.sin)
        ];
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Pattern-Space Bounding Box Covering the Whole Face
    // ------------------------------------------------------------
    // The map is linear, so the extremes of the rotated box sit on the four
    // face bounding-box corners; padding leaves whole units to trim back.
    function na_patternExtent(bounds, frame, pad) {
        var corners = [
            [bounds.min_x, bounds.min_y],
            [bounds.max_x, bounds.min_y],
            [bounds.max_x, bounds.max_y],
            [bounds.min_x, bounds.max_y]
        ];

        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        corners.forEach(function (corner) {
            var point = na_toPatternSpace(corner, frame);
            if (point[0] < minX) { minX = point[0]; }
            if (point[0] > maxX) { maxX = point[0]; }
            if (point[1] < minY) { minY = point[1]; }
            if (point[1] > maxY) { maxY = point[1]; }
        });

        return { minX: minX - pad, minY: minY - pad, maxX: maxX + pad, maxY: maxY + pad };
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Build One Pattern-Space Unit as a Face-Space Ring
    // ------------------------------------------------------------
    function na_unitRing(x, y, width, height, frame) {
        return [
            na_toFaceSpace([x, y], frame),
            na_toFaceSpace([x + width, y], frame),
            na_toFaceSpace([x + width, y + height], frame),
            na_toFaceSpace([x, y + height], frame)
        ];
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Layout Geometry
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Resolve Tile Sizes, Joint and Derived Block Metrics
    // ------------------------------------------------------------
    function na_resolveGeometry(params) {
        var tileLength = Math.max(NA_MIN_TILE_MM, Number(params.tile_length_mm) || 600);
        var tileWidth  = Math.max(NA_MIN_TILE_MM, Number(params.tile_width_mm) || 400);
        var joint      = Math.max(0, Number(params.joint_mm) || 0);
        var bond       = NA_BOND_FAMILY[params.bond] ? params.bond : 'stack';

        var geometry = {
            bond:       bond,
            family:     NA_BOND_FAMILY[bond],
            tileLength: tileLength,
            tileWidth:  tileWidth,
            joint:      joint,
            lengthStep: tileLength + joint,
            widthStep:  tileWidth + joint,
            weaveCount: 1,
            weaveWidth: tileWidth,
            blockSide:  tileLength
        };

        if (geometry.family !== 'basketweave') { return geometry; }

        // Basketweave blocks must be square to interlock, so the block side is
        // the tile length and the course width is fitted to divide it exactly.
        var count = Math.round(tileLength / tileWidth);
        if (!isFinite(count) || count < 1)     { count = 1; }
        if (count > NA_MAX_WEAVE_COUNT)        { count = NA_MAX_WEAVE_COUNT; }

        var weaveWidth = (tileLength - ((count - 1) * joint)) / count;
        if (weaveWidth < NA_MIN_TILE_MM) {
            count      = 1;
            weaveWidth = tileLength;
        }

        geometry.weaveCount = count;
        geometry.weaveWidth = weaveWidth;
        return geometry;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Pattern-Space Origin for the Chosen Setting Out
    // ------------------------------------------------------------
    // The nudge is applied in pattern space, so a rotated layout still slides
    // along its own grid rather than across it. Every builder derives its row,
    // column and lattice ranges from this origin, so shifting it only changes
    // which indices are visited - coverage stays complete at any offset.
    function na_layoutOrigin(geometry, frame, bounds, params) {
        var base;
        if (params.setting_out === 'corner') {
            base = na_toPatternSpace([bounds.min_x, bounds.min_y], frame);
        } else if (geometry.family === 'basketweave') {
            base = [-geometry.blockSide * 0.5, -geometry.blockSide * 0.5];      // <-- Whole block centred on the face
        } else {
            base = [-geometry.tileLength * 0.5, -geometry.tileWidth * 0.5];     // <-- Whole tile centred on the face
        }

        return [
            base[0] + na_finiteNumber(params.offset_x_mm),
            base[1] + na_finiteNumber(params.offset_y_mm)
        ];
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Coerce a Control Value to a Finite Number
    // ------------------------------------------------------------
    function na_finiteNumber(value) {
        var number = Number(value);
        return isFinite(number) ? number : 0;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Grid Bonds - Stack and Running
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Emit Stack / Running Bond Units across the Extent
    // ------------------------------------------------------------
    // The course shift accumulates, so a one-third offset runs 0, 1/3, 2/3, 0
    // rather than alternating; a one-half offset gives the familiar brick bond.
    function na_buildGridUnits(extent, geometry, frame, origin, offsetFraction) {
        var pitchX = geometry.lengthStep;
        var pitchY = geometry.widthStep;
        var units  = [];

        var firstRow = Math.floor((extent.minY - origin[1]) / pitchY) - 1;
        var lastRow  = Math.ceil((extent.maxY - origin[1]) / pitchY) + 1;

        for (var row = firstRow; row <= lastRow; row += 1) {
            var y        = origin[1] + (row * pitchY);
            var shift    = ((row * offsetFraction) % 1) * pitchX;
            var firstCol = Math.floor((extent.minX - origin[0] - shift) / pitchX) - 1;
            var lastCol  = Math.ceil((extent.maxX - origin[0] - shift) / pitchX) + 1;

            for (var col = firstCol; col <= lastCol; col += 1) {
                var x = origin[0] + shift + (col * pitchX);
                units.push(na_unitRing(x, y, geometry.tileLength, geometry.tileWidth, frame));
            }
        }

        return units;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Herringbone
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Emit Herringbone Tile Pairs across the Extent
    // ------------------------------------------------------------
    // Each lattice point carries one lying tile (L x W) and one standing tile
    // (W x L) hard against its right-hand end. With u = (Lj + Wj, Lj - Wj) and
    // v = (-Wj, Wj) the determinant is 2 x Lj x Wj — exactly the pair's cell
    // area — so the pair tiles the plane at any tile proportion.
    function na_buildHerringboneUnits(extent, geometry, frame, origin) {
        var lengthStep = geometry.lengthStep;
        var widthStep  = geometry.widthStep;
        var uVec = [lengthStep + widthStep, lengthStep - widthStep];
        var vVec = [-widthStep, widthStep];
        var det  = (uVec[0] * vVec[1]) - (uVec[1] * vVec[0]);
        if (Math.abs(det) < 1e-9) { return []; }

        var corners = [
            [extent.minX, extent.minY],
            [extent.maxX, extent.minY],
            [extent.maxX, extent.maxY],
            [extent.minX, extent.maxY]
        ];

        var minM = Infinity, maxM = -Infinity, minN = Infinity, maxN = -Infinity;
        corners.forEach(function (corner) {
            var dx = corner[0] - origin[0];
            var dy = corner[1] - origin[1];
            var m  = ((dx * vVec[1]) - (dy * vVec[0])) / det;
            var n  = ((uVec[0] * dy) - (uVec[1] * dx)) / det;
            if (m < minM) { minM = m; }
            if (m > maxM) { maxM = m; }
            if (n < minN) { minN = n; }
            if (n > maxN) { maxN = n; }
        });

        var firstM = Math.floor(minM) - 2;
        var lastM  = Math.ceil(maxM) + 2;
        var firstN = Math.floor(minN) - 2;
        var lastN  = Math.ceil(maxN) + 2;
        var units  = [];

        for (var m = firstM; m <= lastM; m += 1) {
            for (var n = firstN; n <= lastN; n += 1) {
                var px = origin[0] + (m * uVec[0]) + (n * vVec[0]);
                var py = origin[1] + (m * uVec[1]) + (n * vVec[1]);
                units.push(na_unitRing(px, py, geometry.tileLength, geometry.tileWidth, frame));
                units.push(na_unitRing(px + lengthStep, py, geometry.tileWidth, geometry.tileLength, frame));
            }
        }

        return units;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Basketweave
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Emit Alternating Basketweave Blocks across the Extent
    // ------------------------------------------------------------
    function na_buildBasketweaveUnits(extent, geometry, frame, origin) {
        var blockPitch = geometry.blockSide + geometry.joint;
        var stripPitch = geometry.weaveWidth + geometry.joint;
        var units      = [];

        var firstCol = Math.floor((extent.minX - origin[0]) / blockPitch) - 1;
        var lastCol  = Math.ceil((extent.maxX - origin[0]) / blockPitch) + 1;
        var firstRow = Math.floor((extent.minY - origin[1]) / blockPitch) - 1;
        var lastRow  = Math.ceil((extent.maxY - origin[1]) / blockPitch) + 1;

        for (var row = firstRow; row <= lastRow; row += 1) {
            for (var col = firstCol; col <= lastCol; col += 1) {
                var blockX = origin[0] + (col * blockPitch);
                var blockY = origin[1] + (row * blockPitch);
                var lying  = ((((col + row) % 2) + 2) % 2) === 0;                // <-- Alternate block orientation, negatives included

                for (var strip = 0; strip < geometry.weaveCount; strip += 1) {
                    if (lying) {
                        units.push(na_unitRing(
                            blockX,
                            blockY + (strip * stripPitch),
                            geometry.blockSide,
                            geometry.weaveWidth,
                            frame
                        ));
                    } else {
                        units.push(na_unitRing(
                            blockX + (strip * stripPitch),
                            blockY,
                            geometry.weaveWidth,
                            geometry.blockSide,
                            frame
                        ));
                    }
                }
            }
        }

        return units;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Status Reporting
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Format a Millimetre Value to One Decimal at Most
    // ------------------------------------------------------------
    function na_formatMm(value) {
        return (Math.round(value * 10) / 10).toString();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Describe the Resolved Layout for the Status Bar
    // ------------------------------------------------------------
    function na_describeLayout(geometry, params, offsetFraction) {
        var bondText = NA_BOND_LABELS[geometry.bond] || 'stack bond';
        var sizeText = na_formatMm(geometry.tileLength) + ' × ' + na_formatMm(geometry.tileWidth) + 'mm';

        if (geometry.family === 'grid' && offsetFraction > 0) {
            bondText += ' at ' + Math.round(offsetFraction * 100) + '% offset';
        }

        if (geometry.family === 'basketweave') {
            sizeText = geometry.weaveCount + ' × ' + na_formatMm(geometry.blockSide) +
                ' × ' + na_formatMm(geometry.weaveWidth) + 'mm per block';
            if (Math.abs(geometry.weaveWidth - geometry.tileWidth) > 0.05) {
                sizeText += ' (width fitted from ' + na_formatMm(geometry.tileWidth) + 'mm)';
            }
        }

        var rotation  = na_finiteNumber(params.rotation_deg);
        var jointText = geometry.joint > 0 ? na_formatMm(geometry.joint) + 'mm joint' : 'gapless';
        var text      = sizeText + ', ' + bondText + ', ' + jointText;
        if (rotation !== 0) { text += ', rotated ' + na_formatMm(rotation) + '°'; }

        var offsetX = na_finiteNumber(params.offset_x_mm);
        var offsetY = na_finiteNumber(params.offset_y_mm);
        if (offsetX !== 0 || offsetY !== 0) {
            text += ', offset ' + na_formatMm(offsetX) + ' / ' + na_formatMm(offsetY) + 'mm';
        }
        return text;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Generator
    // -------------------------------------------------------------------------

    // FUNCTION | Generate Floor Tiling Polylines for the Selected Face
    // ------------------------------------------------------------
    function na_generate(context) {
        var bounds     = context.faceData.bounds;
        var params     = context.params;
        var geometry   = na_resolveGeometry(params);
        var trimToFace = params.trim_to_face !== false;
        var clipApi    = window.Na__FacePattern__RectClip;

        var frame  = na_buildFrame(bounds, params.rotation_deg);
        var pad    = trimToFace ? geometry.lengthStep + geometry.widthStep : 0;
        var extent = na_patternExtent(bounds, frame, pad);
        var origin = na_layoutOrigin(geometry, frame, bounds, params);

        var cellArea   = Math.max(1, geometry.lengthStep * geometry.widthStep);
        var extentArea = (extent.maxX - extent.minX) * (extent.maxY - extent.minY);
        var estimated  = extentArea / cellArea;
        if (estimated > NA_MAX_UNIT_COUNT) {
            return {
                polylines: [],
                status: 'Tile size too small for this face — around ' + Math.round(estimated) +
                    ' units against a ' + NA_MAX_UNIT_COUNT + ' limit. Increase the tile size or the joint.'
            };
        }

        var offsetFraction = Math.max(0, Math.min(100, Number(params.offset_pct) || 0)) / 100;
        var units;
        if (geometry.family === 'herringbone') {
            units = na_buildHerringboneUnits(extent, geometry, frame, origin);
        } else if (geometry.family === 'basketweave') {
            units = na_buildBasketweaveUnits(extent, geometry, frame, origin);
        } else {
            units = na_buildGridUnits(extent, geometry, frame, origin, offsetFraction);
        }

        var polylines = [];
        var tileCount = 0;
        units.forEach(function (unit) {
            var pieces = clipApi.na_unitPolygonPolylines(unit, context.faceData, trimToFace);
            if (!pieces.length) { return; }

            pieces.forEach(function (piece) { polylines.push(piece); });
            tileCount += 1;
        });

        return {
            polylines: polylines,
            status: tileCount + ' floor tiles generated — ' +
                na_describeLayout(geometry, params, offsetFraction) +
                (trimToFace ? ' (trimmed to face).' : ' (whole tiles only).')
        };
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    return {
        na_generate: na_generate
    };

})();

// =============================================================================
// END OF FILE
// =============================================================================
