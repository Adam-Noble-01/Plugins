// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN GENERATOR - APP CORE
// =============================================================================
//
// FILE       : Na__Noble3dModellingTools__FacePatternGenerator__AppCore__.js
// NAMESPACE  : window.Na__FacePattern__AppCore
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Central state machine — face data, pattern key, polylines —
//              regenerate preview, apply to SketchUp, and export DXF.
// CREATED    : 2026
//
// =============================================================================

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Module State
    // -------------------------------------------------------------------------

    var na_state = {
        faceData: null,
        patternKey: 'patio',
        polylines: [],
        rotationSteps: 0,
        onApply: null
    };

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Pattern Dispatch
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Resolve the Generator Module for a Pattern Key
    // ------------------------------------------------------------
    function na_patternGeneratorForKey(key) {
        if (key === 'brickwork') { return window.Na__FacePattern__BrickworkGenerator; }
        if (key === 'stonework') { return window.Na__FacePattern__StoneworkGenerator; }
        if (key === 'shrub')     { return window.Na__FacePattern__ShrubGenerator; }
        if (key === 'slate')     { return window.Na__FacePattern__SlateRoofGenerator; }
        if (key === 'rosemary')  { return window.Na__FacePattern__RosemaryRoofGenerator; }
        return window.Na__FacePattern__PatioGenerator;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Normalise Control Values Before Generation / Apply
    // ------------------------------------------------------------
    function na_normalizeValues(values) {
        var normalized = {};
        Object.keys(values).forEach(function (key) {
            normalized[key] = values[key];
        });
        if (normalized.stagger !== undefined) {
            normalized.stagger = String(normalized.stagger) === 'true';
        }
        if (normalized.trim_to_face !== undefined) {
            normalized.trim_to_face = String(normalized.trim_to_face) === 'true';
        }
        normalized.seed = Date.now();
        return normalized;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Face Canvas Rotation
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Rotate a Local 2D Point 90 Degrees Clockwise
    // ------------------------------------------------------------
    function na_rotatePoint90(point) {
        return [point[1], -point[0]];
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Recompute Axis-Aligned Bounds from Outline Points
    // ------------------------------------------------------------
    function na_boundsFromPoints(points) {
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        points.forEach(function (point) {
            if (point[0] < minX) { minX = point[0]; }
            if (point[0] > maxX) { maxX = point[0]; }
            if (point[1] < minY) { minY = point[1]; }
            if (point[1] > maxY) { maxY = point[1]; }
        });
        return { min_x: minX, min_y: minY, max_x: maxX, max_y: maxY, width: maxX - minX, height: maxY - minY };
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Rotate the Loaded Face Payload 90 Degrees Clockwise
    // ------------------------------------------------------------
    // Points map (x, y) -> (y, -x); the basis follows as x' = y, y' = -x so
    // world positions are unchanged and the frame stays right-handed.
    function na_rotateFaceDataInPlace() {
        var data = na_state.faceData;
        data.outer = data.outer.map(na_rotatePoint90);
        data.holes = (data.holes || []).map(function (hole) { return hole.map(na_rotatePoint90); });
        data.bounds = na_boundsFromPoints(data.outer);
        if (data.basis && data.basis.x_axis && data.basis.y_axis) {
            var oldX = data.basis.x_axis;
            data.basis.x_axis = data.basis.y_axis;
            data.basis.y_axis = [-oldX[0], -oldX[1], -oldX[2]];
        }
    }
    // ------------------------------------------------------------

    // FUNCTION | Rotate the Face Canvas 90 Degrees Clockwise and Regenerate
    // ------------------------------------------------------------
    function na_rotateFace90() {
        if (!na_state.faceData) {
            window.Na__FacePattern__DynamicUI.na_setStatus('Load a face before rotating the canvas.', false);
            return;
        }
        na_state.rotationSteps = (na_state.rotationSteps + 1) % 4;
        na_rotateFaceDataInPlace();
        na_updateFaceMeta();
        na_regenerate();
        window.Na__FacePattern__DynamicUI.na_setStatus(
            'Face canvas rotated to ' + (na_state.rotationSteps * 90) + '° clockwise — preview regenerated.',
            true
        );
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Face Metadata
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Update the Toolbar Face Bounds Readout
    // ------------------------------------------------------------
    function na_updateFaceMeta() {
        var metaEl = document.getElementById('naFacePat_faceMeta');
        if (!metaEl || !na_state.faceData || !na_state.faceData.bounds) { return; }

        var b = na_state.faceData.bounds;
        metaEl.textContent = 'Face bounds: ' + b.width.toFixed(1) + 'mm × ' + b.height.toFixed(1) + 'mm';
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Preview Regeneration
    // -------------------------------------------------------------------------

    // FUNCTION | Regenerate the Pattern Preview from Current Control Values
    // ------------------------------------------------------------
    function na_regenerate() {
        if (!na_state.faceData) {
            window.Na__FacePattern__DynamicUI.na_setStatus('Waiting for selected face from SketchUp.', false);
            return;
        }

        var values    = window.Na__FacePattern__DynamicUI.na_getValues();
        var generator = na_patternGeneratorForKey(na_state.patternKey);
        var result    = generator.na_generate({
            faceData: na_state.faceData,
            params: na_normalizeValues(values)
        });

        na_state.polylines = result.polylines || [];
        window.Na__FacePattern__SvgPreview.na_render(na_state.faceData, na_state.polylines);
        window.Na__FacePattern__DynamicUI.na_setStatus(result.status || 'Preview updated.', true);
    }
    // ------------------------------------------------------------

    // FUNCTION | Switch Pattern Type and Rebuild the Dynamic Control Panel
    // ------------------------------------------------------------
    function na_setPattern(patternKey) {
        na_state.patternKey = patternKey;
        var config = window.Na__FacePattern__UiConfig.na_getPatternConfig(patternKey);
        window.Na__FacePattern__DynamicUI.na_setFields(config.fields);
        na_regenerate();
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Actions
    // -------------------------------------------------------------------------

    // FUNCTION | Build the Apply Payload and Send to Ruby via the Bridge
    // ------------------------------------------------------------
    function na_applyPattern() {
        if (!na_state.faceData) {
            window.Na__FacePattern__DynamicUI.na_setStatus('No face data to apply.', false);
            return;
        }
        if (!na_state.onApply) { return; }

        var values  = na_normalizeValues(window.Na__FacePattern__DynamicUI.na_getValues());
        var payload = {
            pattern_type: na_state.patternKey,
            params: values,
            polylines: na_state.polylines,
            basis: na_state.faceData.basis,
            rotation_steps: na_state.rotationSteps,
            lift_mm: Number(values.lift_mm) || 0,
            close_paths: true,
            group_name: 'Na Face Pattern - ' + na_state.patternKey
        };

        if (na_state.patternKey === 'slate') {
            payload.preset_key      = values.preset_key;
            payload.slate_length_mm = Number(values.slate_length_mm) || 500;
            payload.slate_width_mm  = Number(values.slate_width_mm) || 250;
            payload.headlap_mm      = Number(values.headlap_mm) || 100;
            payload.side_gap_mm     = Number(values.side_gap_mm) || 0;
            payload.stagger         = values.stagger !== false;
            payload.trim_to_face    = values.trim_to_face !== false;
        }

        if (na_state.patternKey === 'rosemary') {
            payload.preset_key        = values.preset_key;
            payload.tile_length_mm    = Number(values.tile_length_mm) || 265;
            payload.tile_width_mm     = Number(values.tile_width_mm) || 165;
            payload.headlap_mm        = Number(values.headlap_mm) || 65;
            payload.side_gap_mm       = Number(values.side_gap_mm) || 0;
            payload.base_thickness_mm = Math.max(0, Number(values.base_thickness_mm) || 0);
            payload.stagger           = values.stagger !== false;
            payload.trim_to_face      = values.trim_to_face !== false;
        }

        na_state.onApply(payload);
        window.Na__FacePattern__DynamicUI.na_setStatus('Applying pattern to SketchUp model...', true);
    }
    // ------------------------------------------------------------

    // FUNCTION | Export the Current Preview Polylines as a DXF File
    // ------------------------------------------------------------
    function na_downloadDxf() {
        if (!na_state.polylines || !na_state.polylines.length) {
            window.Na__FacePattern__DynamicUI.na_setStatus('Generate a preview before exporting DXF.', false);
            return;
        }
        window.Na__FacePattern__DxfExport.na_download(na_state.polylines, 'Na_FacePattern_' + na_state.patternKey);
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Ruby-Facing Entry Points
    // -------------------------------------------------------------------------

    // FUNCTION | Receive Face Payload Pushed from Ruby
    // ------------------------------------------------------------
    function na_setFaceData(facePayload) {
        na_state.faceData = facePayload;
        na_state.rotationSteps = 0;                                             // <-- Fresh payload arrives unrotated
        na_updateFaceMeta();
        na_regenerate();
    }
    // ------------------------------------------------------------

    // FUNCTION | Receive a Status Message Pushed from Ruby
    // ------------------------------------------------------------
    function na_setStatus(message, success) {
        window.Na__FacePattern__DynamicUI.na_setStatus(message, success);
    }
    // ------------------------------------------------------------

    // FUNCTION | Initialise AppCore and Mount Sub-Modules
    // ------------------------------------------------------------
    function na_init(options) {
        na_state.onApply = options.onApply;

        window.Na__FacePattern__DynamicUI.na_mount({
            containerId: 'naFacePat_dynamicControls',
            statusId: 'naFacePat_status',
            onChange: function () { na_regenerate(); }
        });

        window.Na__FacePattern__SvgPreview.na_init('naFacePat_svg', 'naFacePat_svgWrapper');
        na_setPattern(na_state.patternKey);
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    window.Na__FacePattern__AppCore = {
        na_init: na_init,
        na_setFaceData: na_setFaceData,
        na_setPattern: na_setPattern,
        na_applyPattern: na_applyPattern,
        na_rotateFace90: na_rotateFace90,
        na_downloadDxf: na_downloadDxf,
        na_resetView: function () {
            window.Na__FacePattern__SvgPreview.na_resetView(na_state.faceData, na_state.polylines);
        },
        na_setStatus: na_setStatus
    };

    window.Na__FacePattern__SetFaceData = na_setFaceData;
    window.Na__FacePattern__SetStatus   = na_setStatus;

})();

// =============================================================================
// END OF FILE
// =============================================================================
