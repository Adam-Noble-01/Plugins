// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN - STONEWORK GENERATOR
// =============================================================================
//
// FILE       : Na__FacePattern__StoneworkGenerator__.js
// NAMESPACE  : window.Na__FacePattern__StoneworkGenerator
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Coursed (random-height rows) and Uncoursed skyline packer;
//              size presets, FBM artistic density, setting out on the face,
//              and stone dressing — corner bevel then edge erosion.
// CREATED    : 2026
//
// DESCRIPTION:
// - The layout is generated in pattern space anchored on index 0 and then slid
//   onto the face, so Setting Out and the offsets move the wall rather than
//   re-rolling it.
// - The seed is derived from the Random Seed control, not from the clock, so a
//   wall holds still while roughness and bevel are tuned.
//
// =============================================================================

window.Na__FacePattern__StoneworkGenerator = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Size Presets and Tuning Constants
    // -------------------------------------------------------------------------

    var NA_SIZE_PRESETS = {
        small:  { minW: 100, maxW: 280, minH: 60,  maxH: 140 },
        medium: { minW: 150, maxW: 420, minH: 100, maxH: 220 },
        large:  { minW: 220, maxW: 620, minH: 150, maxH: 300 }
    };

    var NA_ROUGH_FRACTION       = 0.15;                                         // <-- Erosion at 100% eats this much of a stone's short side
    var NA_JOINT_GROW_FRACTION  = 0.45;                                         // <-- Pre-growth into the joint, capped so stones never touch
    var NA_PACK_QUANTUM_MM      = 500;                                          // <-- Uncoursed packing region snaps to this lattice
    var NA_BAND_SAFETY_CAP      = 4000;                                         // <-- Walk limit when marching out to a distant offset
    var NA_MAX_APPLY_SEGMENTS   = 75000;                                        // <-- Mirrors GeometryBuilder NA_MAX_SEGMENTS

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Seeding
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Seeded Random Shortcut
    // ------------------------------------------------------------
    function na_random(seed) {
        return window.Na__FacePattern__Noise.na_seededRandom(seed);
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Coerce a Control Value to a Finite Number
    // ------------------------------------------------------------
    function na_finiteNumber(value) {
        var number = Number(value);
        return isFinite(number) ? number : 0;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Derive a Stable Wall Seed from the Layout Controls
    // ------------------------------------------------------------
    // AppCore stamps params.seed with the clock on every regenerate, which would
    // re-roll the wall on each keystroke. Stonework hashes its own controls
    // instead (FNV-1a), so only the Random Seed box changes the layout.
    function na_wallSeed(params) {
        var key = [
            params.pattern_type || 'coursed',
            params.stone_size || 'medium',
            Math.round(na_finiteNumber(params.seed_value))
        ].join('|');

        var hash = 2166136261;
        for (var index = 0; index < key.length; index += 1) {
            hash ^= key.charCodeAt(index);
            hash = Math.imul(hash, 16777619);
        }
        return hash >>> 0;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Layout Algorithms
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | March an Indexed Run of Bands Across One Axis
    // ------------------------------------------------------------
    // Band 0 starts at the anchor; sizeFn is keyed on the index rather than the
    // position, so the run is fixed in pattern space and only the visible window
    // changes when the layout slides.
    function na_bandsCovering(minValue, maxValue, anchor, sizeFn) {
        var bands = [];
        var index = 0;
        var start = anchor;
        var guard = 0;

        while (start > minValue && guard < NA_BAND_SAFETY_CAP) {                // <-- Walk back to the band straddling the low edge
            index -= 1;
            start -= sizeFn(index);
            guard += 1;
        }

        guard = 0;
        while (start < maxValue && guard < NA_BAND_SAFETY_CAP) {
            var size = sizeFn(index);
            bands.push({ start: start, size: size, index: index });
            start += size;
            index += 1;
            guard += 1;
        }

        return bands;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Generate Coursed Horizontal Stone Rows
    // ------------------------------------------------------------
    // Every course carries its own random phase, so the vertical joints do not
    // line up at the pattern origin the way an unphased index run would.
    function na_generateCoursed(region, preset, seed) {
        var stones = [];

        var rows = na_bandsCovering(region.min_y, region.max_y, 0, function (row) {
            return preset.minH + ((preset.maxH - preset.minH) * na_random(seed + (row * 17)));
        });

        rows.forEach(function (row) {
            var phase = na_random(seed + (row.index * 29) + 7) * preset.maxW;
            var columns = na_bandsCovering(region.min_x, region.max_x, phase, function (column) {
                return preset.minW + ((preset.maxW - preset.minW) * na_random(seed + (row.index * 43) + (column * 7) + 101));
            });

            columns.forEach(function (column) {
                stones.push({ x: column.start, y: row.start, width: column.size, height: row.size });
            });
        });

        return stones;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Generate Uncoursed Skyline-Packed Stones
    // ------------------------------------------------------------
    // The packer is sequential, so it cannot be indexed the way courses can. Its
    // region is snapped to a coarse lattice instead: the wall then slides with
    // the offsets and only repacks when the covered region steps a whole lattice.
    function na_generateUncoursed(region, preset, seed) {
        var minX = Math.floor(region.min_x / NA_PACK_QUANTUM_MM) * NA_PACK_QUANTUM_MM;
        var minY = Math.floor(region.min_y / NA_PACK_QUANTUM_MM) * NA_PACK_QUANTUM_MM;
        var maxX = Math.ceil(region.max_x / NA_PACK_QUANTUM_MM) * NA_PACK_QUANTUM_MM;
        var maxY = Math.ceil(region.max_y / NA_PACK_QUANTUM_MM) * NA_PACK_QUANTUM_MM;

        var stones     = [];
        var skyline    = [{ x: minX, width: maxX - minX, y: minY }];
        var stoneCells = Math.ceil(((maxX - minX) * (maxY - minY)) / (preset.minW * preset.minH));
        var safetyCap  = Math.min(40000, Math.max(6000, stoneCells + 500));      // <-- Scales with the overshoot margin
        var safety     = 0;

        while (safety < safetyCap) {
            safety += 1;
            skyline.sort(function (a, b) { return a.y - b.y; });
            var segment = skyline[0];
            if (!segment || segment.y >= maxY) { break; }

            var width  = preset.minW + ((preset.maxW - preset.minW) * na_random(seed + safety * 13));
            if (segment.width - width <= preset.minW * 0.6) { width = segment.width; }   // <-- Remainder too narrow to re-let, take it all
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
    // REGION | Layout Extent and Setting Out
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
            max_y: bounds.max_y + padY
        };
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Where Pattern-Space Origin Lands on the Face
    // ------------------------------------------------------------
    // From corner puts the first course on the bounding box corner; centred puts
    // a whole average stone across the middle of the face so the cuts balance.
    // Both then take the typed offsets.
    function na_layoutShift(bounds, preset, params) {
        var shiftX;
        var shiftY;

        if (params.setting_out === 'centre') {
            shiftX = ((bounds.min_x + bounds.max_x) * 0.5) - (((preset.minW + preset.maxW) * 0.5) * 0.5);
            shiftY = ((bounds.min_y + bounds.max_y) * 0.5) - (((preset.minH + preset.maxH) * 0.5) * 0.5);
        } else {
            shiftX = bounds.min_x;
            shiftY = bounds.min_y;
        }

        return [
            shiftX + na_finiteNumber(params.offset_x_mm),
            shiftY + na_finiteNumber(params.offset_y_mm)
        ];
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Status Reporting
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Format a Millimetre Value Without Trailing Zeros
    // ------------------------------------------------------------
    function na_formatMm(value) {
        return Math.abs(value % 1) < 0.05 ? String(Math.round(value)) : value.toFixed(1);
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Describe the Dressing and Setting Out in the Status Line
    // ------------------------------------------------------------
    function na_describeSettings(params, roughPct, bevelMm) {
        var notes = [];
        if (roughPct > 0) { notes.push('roughness ' + Math.round(roughPct) + '%'); }
        if (bevelMm > 0)  { notes.push('bevel ' + na_formatMm(bevelMm) + 'mm'); }

        var offsetX = na_finiteNumber(params.offset_x_mm);
        var offsetY = na_finiteNumber(params.offset_y_mm);
        if (offsetX !== 0 || offsetY !== 0) {
            notes.push('offset ' + na_formatMm(offsetX) + ' / ' + na_formatMm(offsetY) + 'mm');
        }

        return notes.length ? ' — ' + notes.join(', ') + '.' : '';
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
        var pattern    = params.pattern_type === 'uncoursed' ? 'uncoursed' : 'coursed';
        var density    = Math.max(0, Math.min(100, Number(params.density_pct) || 50)) / 100;
        var renderMode = params.render_mode || 'continuous';
        var trimToFace = params.trim_to_face !== false;
        var mortar     = Math.max(0, Number(params.mortar_mm) || 0);
        var roughPct   = Math.max(0, Math.min(100, na_finiteNumber(params.roughness_pct)));
        var bevelMm    = Math.max(0, na_finiteNumber(params.bevel_mm));
        var seed       = na_wallSeed(params);
        var clipApi    = window.Na__FacePattern__RectClip;
        var shapeApi   = window.Na__FacePattern__UnitShape;
        var noiseApi   = window.Na__FacePattern__Noise;
        var dressing   = (roughPct > 0 || bevelMm > 0) &&
                         !!(shapeApi && typeof shapeApi.na_dressRing === 'function');   // <-- Clean blocks if UnitShape has not loaded yet

        var layout = na_expandBounds(bounds, preset.maxW, preset.maxH, trimToFace);
        var shift  = na_layoutShift(bounds, preset, params);
        var region = {
            min_x: layout.min_x - shift[0],
            min_y: layout.min_y - shift[1],
            max_x: layout.max_x - shift[0],
            max_y: layout.max_y - shift[1]
        };

        var stoneRects = pattern === 'uncoursed'
            ? na_generateUncoursed(region, preset, seed)
            : na_generateCoursed(region, preset, seed);

        var polylines  = [];
        var stoneCount = 0;
        stoneRects.forEach(function (stone, index) {
            if (renderMode === 'artistic') {
                var noiseVal = noiseApi.na_fbmNoise((stone.x + stone.width) * 0.012, (stone.y + stone.height) * 0.012, seed + index, 3);
                if (noiseVal > density) { return; }
            }

            var unitWidth  = Math.max(1, stone.width - mortar);
            var unitHeight = Math.max(1, stone.height - mortar);
            var amplitude  = (roughPct / 100) * NA_ROUGH_FRACTION * Math.min(unitWidth, unitHeight);
            var grow       = Math.min(amplitude * 0.5, mortar * NA_JOINT_GROW_FRACTION);   // <-- Erosion bites back to roughly the stated joint

            var pieces = clipApi.na_unitPolylines(
                stone.x + shift[0] + (mortar * 0.5) - grow,
                stone.y + shift[1] + (mortar * 0.5) - grow,
                unitWidth + (grow * 2),
                unitHeight + (grow * 2),
                context.faceData,
                trimToFace
            );
            if (!pieces.length) { return; }

            pieces.forEach(function (piece) {                                   // <-- Dress after trimming: erosion only ever cuts inward
                polylines.push(dressing
                    ? shapeApi.na_dressRing(piece, { bevel_mm: bevelMm, amplitude_mm: amplitude, seed: seed })
                    : piece);
            });
            stoneCount += 1;
        });

        var notes    = na_describeSettings(params, roughPct, bevelMm);
        var segments = polylines.reduce(function (total, ring) { return total + ring.length; }, 0);
        var overrun  = segments > NA_MAX_APPLY_SEGMENTS
            ? ' Apply will refuse this — ' + segments + ' segments against a ' + NA_MAX_APPLY_SEGMENTS +
              ' limit. Raise the stone size, or lower Edge Roughness / Corner Bevel.'
            : '';

        return {
            polylines: polylines,
            status: stoneCount + ' stone units generated' +
                (trimToFace ? ' (trimmed to face)' : ' (whole stones only)') +
                (notes || '.') + overrun
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
