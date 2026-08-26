// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN - ROSEMARY ROOF GENERATOR
// =============================================================================
//
// FILE       : Na__FacePattern__RosemaryRoofGenerator__.js
// NAMESPACE  : window.Na__FacePattern__RosemaryRoofGenerator
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : British plain tile (Rosemary style) course tiling preview —
//              double-lap gauge, half-bond stagger, UK plain tile presets.
//              Apply delegates to Ruby RosemaryBuilder.
// CREATED    : 2026
//
// NOTE:
// Standard UK plain tile is 265x165mm (BS EN 1304 / BS 5534) with a minimum
// 65mm headlap giving the classic 100mm maximum gauge. Rosemary linear cover
// is 166.5mm = 165mm tile + 1.5mm shunt, hence the default side gap.
// Preview uses an all-corners-inside point test; partial edge tiles appear on
// Apply via Ruby face.classify_point but not in the SVG preview.
//
// =============================================================================

window.Na__FacePattern__RosemaryRoofGenerator = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Presets
    // -------------------------------------------------------------------------

    var NA_PRESETS = {
        rosemary_265x165_65: { length: 265, width: 165, headlap: 65 },
        rosemary_265x165_75: { length: 265, width: 165, headlap: 75 },
        rosemary_265x165_85: { length: 265, width: 165, headlap: 85 },
        custom:              { length: 265, width: 165, headlap: 65 }
    };

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Options
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Resolve Tile Dimensions from Preset or Custom Params
    // ------------------------------------------------------------
    function na_getTileOptions(params) {
        var preset = NA_PRESETS[params.preset_key] || NA_PRESETS.custom;
        return {
            tileLength:    Number(params.tile_length_mm) || preset.length,
            tileWidth:     Number(params.tile_width_mm) || preset.width,
            headlap:       Number(params.headlap_mm) || preset.headlap,
            sideGap:       Math.max(0, Number(params.side_gap_mm) || 0),
            baseThickness: Math.max(0, Number(params.base_thickness_mm) || 0),
            stagger:       params.stagger !== false,
            trimToFace:    params.trim_to_face !== false
        };
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Base Line Emission
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Push the Visible Tile End Line for One Course Tile
    // ------------------------------------------------------------
    // Trimmed tiles clip the base line to the face so it stops at the verge
    // rather than running out past the trimmed tile outline.
    function na_pushBaseLines(polylines, x, y, options, faceData) {
        var startPoint = [x, y + options.baseThickness];
        var endPoint   = [x + options.tileWidth, y + options.baseThickness];

        if (!options.trimToFace) {
            polylines.push([startPoint, endPoint]);
            return;
        }

        window.Na__FacePattern__RectClip
            .na_clipSegment(startPoint, endPoint, faceData.outer, faceData.holes)
            .forEach(function (segment) { polylines.push(segment); });
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Generator
    // -------------------------------------------------------------------------

    // FUNCTION | Generate Plain Tile Course Preview Polylines for the Selected Face
    // ------------------------------------------------------------
    function na_generate(context) {
        var bounds  = context.faceData.bounds;
        var params  = context.params;
        var options = na_getTileOptions(params);
        var visibleGauge = (options.tileLength - options.headlap) / 2;

        if (visibleGauge <= 0 || options.tileWidth <= 0) {
            return { polylines: [], status: 'Rosemary tile settings are invalid.' };
        }

        var clipApi = window.Na__FacePattern__RectClip;
        var xStep   = options.tileWidth + options.sideGap;
        var yStep   = visibleGauge;
        var drawBase  = options.baseThickness > 0 && options.baseThickness < visibleGauge;
        var polylines = [];
        var tileCount = 0;
        var row = 0;

        for (var y = bounds.min_y - yStep; y <= bounds.max_y + yStep; y += yStep) {
            var rowOffset = options.stagger && (row % 2 === 1) ? -(xStep * 0.5) : 0;
            for (var x = bounds.min_x - xStep + rowOffset; x <= bounds.max_x + xStep; x += xStep) {
                var pieces = clipApi.na_unitPolylines(
                    x, y, options.tileWidth, visibleGauge, context.faceData, options.trimToFace
                );
                if (!pieces.length) { continue; }

                pieces.forEach(function (piece) { polylines.push(piece); });
                tileCount += 1;

                if (drawBase) {
                    na_pushBaseLines(polylines, x, y, options, context.faceData);
                }
            }
            row += 1;
        }

        return {
            polylines: polylines,
            status: tileCount + ' rosemary tile previews generated' + (options.trimToFace ? ' (trimmed to face).' : ' (whole tiles only).'),
            tileOptions: options,
            visibleGauge: visibleGauge
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
