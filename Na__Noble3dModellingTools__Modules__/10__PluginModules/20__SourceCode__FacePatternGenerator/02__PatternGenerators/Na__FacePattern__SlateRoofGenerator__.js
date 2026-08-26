// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN - SLATE ROOF GENERATOR
// =============================================================================
//
// FILE       : Na__FacePattern__SlateRoofGenerator__.js
// NAMESPACE  : window.Na__FacePattern__SlateRoofGenerator
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Course tiling preview — visible gauge, half-bond stagger, six
//              UK presets. Apply delegates to Ruby SlateBuilder.
// CREATED    : 2026
//
// NOTE:
// With Trim to Face Edges on (default) the course grid overshoots the face and
// every slate is cut back to the face perimeter by RectClip, so hips, valleys
// and verges fill completely. Off keeps only whole, untrimmed slates.
//
// =============================================================================

window.Na__FacePattern__SlateRoofGenerator = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Presets
    // -------------------------------------------------------------------------

    var NA_PRESETS = {
        slate_600x300_100: { length: 600, width: 300, headlap: 100 },
        slate_500x300_100: { length: 500, width: 300, headlap: 100 },
        slate_500x250_100: { length: 500, width: 250, headlap: 100 },
        slate_460x220_80:  { length: 460, width: 220, headlap: 80 },
        slate_400x250_75:  { length: 400, width: 250, headlap: 75 },
        custom:            { length: 500, width: 250, headlap: 100 }
    };

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Options
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Resolve Slate Dimensions from Preset or Custom Params
    // ------------------------------------------------------------
    function na_getSlateOptions(params) {
        var preset = NA_PRESETS[params.preset_key] || NA_PRESETS.custom;
        return {
            slateLength: Number(params.slate_length_mm) || preset.length,
            slateWidth:  Number(params.slate_width_mm) || preset.width,
            headlap:     Number(params.headlap_mm) || preset.headlap,
            sideGap:     Math.max(0, Number(params.side_gap_mm) || 0),
            stagger:     params.stagger !== false,
            trimToFace:  params.trim_to_face !== false
        };
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Generator
    // -------------------------------------------------------------------------

    // FUNCTION | Generate Slate Course Preview Polylines for the Selected Face
    // ------------------------------------------------------------
    function na_generate(context) {
        var bounds  = context.faceData.bounds;
        var params  = context.params;
        var options = na_getSlateOptions(params);
        var visibleGauge = (options.slateLength - options.headlap) / 2;

        if (visibleGauge <= 0 || options.slateWidth <= 0) {
            return { polylines: [], status: 'Slate settings are invalid.' };
        }

        var clipApi = window.Na__FacePattern__RectClip;
        var xStep   = options.slateWidth + options.sideGap;
        var yStep   = visibleGauge;
        var polylines  = [];
        var slateCount = 0;
        var row = 0;

        for (var y = bounds.min_y - yStep; y <= bounds.max_y + yStep; y += yStep) {
            var rowOffset = options.stagger && (row % 2 === 1) ? -(xStep * 0.5) : 0;
            for (var x = bounds.min_x - xStep + rowOffset; x <= bounds.max_x + xStep; x += xStep) {
                var pieces = clipApi.na_unitPolylines(
                    x, y, options.slateWidth, visibleGauge, context.faceData, options.trimToFace
                );
                if (!pieces.length) { continue; }

                pieces.forEach(function (piece) { polylines.push(piece); });
                slateCount += 1;
            }
            row += 1;
        }

        return {
            polylines: polylines,
            status: slateCount + ' slate previews generated' + (options.trimToFace ? ' (trimmed to face).' : ' (whole slates only).'),
            slateOptions: options,
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
