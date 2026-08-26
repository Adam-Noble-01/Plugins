// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN - STONEWORK GENERATOR
// =============================================================================
//
// FILE       : Na__FacePattern__StoneworkGenerator__.js
// NAMESPACE  : window.Na__FacePattern__StoneworkGenerator
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Coursed (random-height rows) and Uncoursed skyline packer;
//              size presets and FBM artistic density mode.
// CREATED    : 2026
//
// =============================================================================

window.Na__FacePattern__StoneworkGenerator = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Size Presets
    // -------------------------------------------------------------------------

    var NA_SIZE_PRESETS = {
        small:  { minW: 100, maxW: 280, minH: 60,  maxH: 140 },
        medium: { minW: 150, maxW: 420, minH: 100, maxH: 220 },
        large:  { minW: 220, maxW: 620, minH: 150, maxH: 300 }
    };

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Layout Algorithms
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Seeded Random Shortcut
    // ------------------------------------------------------------
    function na_random(seed) {
        return window.Na__FacePattern__Noise.na_seededRandom(seed);
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Generate Coursed Horizontal Stone Rows
    // ------------------------------------------------------------
    function na_generateCoursed(bounds, preset, seed) {
        var stones = [];
        var y = bounds.min_y;
        var row = 0;
        while (y < bounds.max_y) {
            var rowRand       = na_random(seed + (row * 17));
            var courseHeight  = preset.minH + ((preset.maxH - preset.minH) * rowRand);
            var x = bounds.min_x;
            while (x < bounds.max_x) {
                var widthRand = na_random(seed + Math.floor(x) + (row * 43));
                var width     = preset.minW + ((preset.maxW - preset.minW) * widthRand);
                stones.push({ x: x, y: y, width: width, height: courseHeight });
                x += width;
            }
            y += courseHeight;
            row += 1;
        }
        return stones;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Generate Uncoursed Skyline-Packed Stones
    // ------------------------------------------------------------
    function na_generateUncoursed(bounds, preset, seed) {
        var stones     = [];
        var skyline    = [{ x: bounds.min_x, width: bounds.width, y: bounds.min_y }];
        var stoneCells = Math.ceil((bounds.width * bounds.height) / (preset.minW * preset.minH));
        var safetyCap  = Math.min(40000, Math.max(6000, stoneCells + 500));      // <-- Scales with the overshoot margin
        var safety     = 0;
        while (safety < safetyCap) {
            safety += 1;
            skyline.sort(function (a, b) { return a.y - b.y; });
            var segment = skyline[0];
            if (!segment || segment.y >= bounds.max_y) { break; }

            var width  = preset.minW + ((preset.maxW - preset.minW) * na_random(seed + safety * 13));
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
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Layout Extent
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Grow the Layout Box by One Stone so Edge Units Exist to Trim
    // ------------------------------------------------------------
    function na_expandBounds(bounds, marginX, marginY, trimEnabled) {
        var padX = trimEnabled ? marginX : 0;
        var padY = trimEnabled ? marginY : 0;
        return {
            min_x: bounds.min_x - padX,
            min_y: bounds.min_y - padY,
            max_x: bounds.max_x + padX,
            max_y: bounds.max_y + padY,
            width: bounds.width + (padX * 2),
            height: bounds.height + (padY * 2)
        };
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Generator
    // -------------------------------------------------------------------------

    // FUNCTION | Generate Stonework Polylines for the Selected Face
    // ------------------------------------------------------------
    function na_generate(context) {
        var bounds     = context.faceData.bounds;
        var params     = context.params;
        var preset     = NA_SIZE_PRESETS[params.stone_size] || NA_SIZE_PRESETS.medium;
        var pattern    = params.pattern_type || 'uncoursed';
        var density    = Math.max(0, Math.min(100, Number(params.density_pct) || 50)) / 100;
        var renderMode = params.render_mode || 'continuous';
        var trimToFace = params.trim_to_face !== false;
        var seed       = Number(params.seed) || Date.now();
        var mortar     = Math.max(0, Number(params.mortar_mm) || 10);
        var clipApi    = window.Na__FacePattern__RectClip;
        var noiseApi   = window.Na__FacePattern__Noise;

        var layout     = na_expandBounds(bounds, preset.maxW, preset.maxH, trimToFace);
        var stoneRects = pattern === 'coursed'
            ? na_generateCoursed(layout, preset, seed)
            : na_generateUncoursed(layout, preset, seed);

        var polylines  = [];
        var stoneCount = 0;
        stoneRects.forEach(function (stone, index) {
            if (renderMode === 'artistic') {
                var noiseVal = noiseApi.na_fbmNoise((stone.x + stone.width) * 0.012, (stone.y + stone.height) * 0.012, seed + index, 3);
                if (noiseVal > density) { return; }
            }

            var pieces = clipApi.na_unitPolylines(
                stone.x + (mortar * 0.5),
                stone.y + (mortar * 0.5),
                Math.max(1, stone.width - mortar),
                Math.max(1, stone.height - mortar),
                context.faceData,
                trimToFace
            );
            if (!pieces.length) { return; }

            pieces.forEach(function (piece) { polylines.push(piece); });
            stoneCount += 1;
        });

        return {
            polylines: polylines,
            status: stoneCount + ' stone units generated' + (trimToFace ? ' (trimmed to face).' : ' (whole stones only).')
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
