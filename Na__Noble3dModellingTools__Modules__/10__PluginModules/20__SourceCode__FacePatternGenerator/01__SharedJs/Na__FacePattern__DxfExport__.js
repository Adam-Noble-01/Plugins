// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN - DXF EXPORT
// =============================================================================
//
// FILE       : Na__FacePattern__DxfExport__.js
// NAMESPACE  : window.Na__FacePattern__DxfExport
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Write DXF LINE entities from preview polylines and trigger a
//              filename Blob download from the dialog.
// CREATED    : 2026
//
// =============================================================================

window.Na__FacePattern__DxfExport = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | DXF Generation
    // -------------------------------------------------------------------------

    // FUNCTION | Convert Polylines to a Minimal DXF ENTITIES Section
    // ------------------------------------------------------------
    function na_toDxf(polylines) {
        var lines = ['0', 'SECTION', '2', 'ENTITIES'];

        (polylines || []).forEach(function (polyline) {
            if (!polyline || polyline.length < 2) { return; }
            for (var index = 0; index < polyline.length - 1; index += 1) {
                var startPoint = polyline[index];
                var endPoint   = polyline[index + 1];
                lines.push('0', 'LINE');
                lines.push('8', '0');
                lines.push('10', startPoint[0].toFixed(6));
                lines.push('20', startPoint[1].toFixed(6));
                lines.push('30', '0.0');
                lines.push('11', endPoint[0].toFixed(6));
                lines.push('21', endPoint[1].toFixed(6));
                lines.push('31', '0.0');
            }
        });

        lines.push('0', 'ENDSEC', '0', 'EOF');
        return lines.join('\n');
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Download
    // -------------------------------------------------------------------------

    // FUNCTION | Trigger a Browser Download of the DXF File
    // ------------------------------------------------------------
    function na_download(polylines, filenamePrefix) {
        var dxf  = na_toDxf(polylines);
        var blob = new Blob([dxf], { type: 'application/dxf' });
        var url  = URL.createObjectURL(blob);
        var link = document.createElement('a');
        link.href = url;
        link.download = (filenamePrefix || 'FacePattern') + '_' + Date.now() + '.dxf';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    return {
        na_toDxf: na_toDxf,
        na_download: na_download
    };

})();

// =============================================================================
// END OF FILE
// =============================================================================
