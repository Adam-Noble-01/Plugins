(function () {
    'use strict';

    var na_state = {
        faceData: null,
        patternKey: 'patio',
        polylines: [],
        onApply: null
    };

    function na_patternGeneratorForKey(key) {
        if (key === 'brickwork') { return window.Na__FacePattern__BrickworkGenerator; }
        if (key === 'stonework') { return window.Na__FacePattern__StoneworkGenerator; }
        if (key === 'shrub') { return window.Na__FacePattern__ShrubGenerator; }
        if (key === 'slate') { return window.Na__FacePattern__SlateRoofGenerator; }
        return window.Na__FacePattern__PatioGenerator;
    }

    function na_updateFaceMeta() {
        var metaEl = document.getElementById('naFacePat_faceMeta');
        if (!metaEl || !na_state.faceData || !na_state.faceData.bounds) {
            return;
        }

        var b = na_state.faceData.bounds;
        metaEl.textContent = 'Face bounds: ' + b.width.toFixed(1) + 'mm × ' + b.height.toFixed(1) + 'mm';
    }

    function na_normalizeValues(values) {
        var normalized = {};
        Object.keys(values).forEach(function (key) {
            normalized[key] = values[key];
        });
        if (normalized.stagger !== undefined) {
            normalized.stagger = String(normalized.stagger) === 'true';
        }
        normalized.seed = Date.now();
        return normalized;
    }

    function na_regenerate() {
        if (!na_state.faceData) {
            window.Na__FacePattern__DynamicUI.na_setStatus('Waiting for selected face from SketchUp.', false);
            return;
        }

        var values = window.Na__FacePattern__DynamicUI.na_getValues();
        var generator = na_patternGeneratorForKey(na_state.patternKey);
        var result = generator.na_generate({
            faceData: na_state.faceData,
            params: na_normalizeValues(values)
        });

        na_state.polylines = result.polylines || [];
        window.Na__FacePattern__SvgPreview.na_render(na_state.faceData, na_state.polylines);
        window.Na__FacePattern__DynamicUI.na_setStatus(result.status || 'Preview updated.', true);
    }

    function na_setPattern(patternKey) {
        na_state.patternKey = patternKey;
        var config = window.Na__FacePattern__UiConfig.na_getPatternConfig(patternKey);
        window.Na__FacePattern__DynamicUI.na_setFields(config.fields);
        na_regenerate();
    }

    function na_applyPattern() {
        if (!na_state.faceData) {
            window.Na__FacePattern__DynamicUI.na_setStatus('No face data to apply.', false);
            return;
        }
        if (!na_state.onApply) {
            return;
        }

        var values = na_normalizeValues(window.Na__FacePattern__DynamicUI.na_getValues());
        var payload = {
            pattern_type: na_state.patternKey,
            params: values,
            polylines: na_state.polylines,
            basis: na_state.faceData.basis,
            lift_mm: Number(values.lift_mm) || 0,
            close_paths: true,
            group_name: 'Na Face Pattern - ' + na_state.patternKey
        };

        if (na_state.patternKey === 'slate') {
            payload.preset_key = values.preset_key;
            payload.slate_length_mm = Number(values.slate_length_mm) || 500;
            payload.slate_width_mm = Number(values.slate_width_mm) || 250;
            payload.headlap_mm = Number(values.headlap_mm) || 100;
            payload.side_gap_mm = Number(values.side_gap_mm) || 0;
            payload.stagger = values.stagger !== false;
        }

        na_state.onApply(payload);
        window.Na__FacePattern__DynamicUI.na_setStatus('Applying pattern to SketchUp model...', true);
    }

    function na_downloadDxf() {
        if (!na_state.polylines || !na_state.polylines.length) {
            window.Na__FacePattern__DynamicUI.na_setStatus('Generate a preview before exporting DXF.', false);
            return;
        }
        window.Na__FacePattern__DxfExport.na_download(na_state.polylines, 'Na_FacePattern_' + na_state.patternKey);
    }

    function na_setFaceData(facePayload) {
        na_state.faceData = facePayload;
        na_updateFaceMeta();
        na_regenerate();
    }

    function na_setStatus(message, success) {
        window.Na__FacePattern__DynamicUI.na_setStatus(message, success);
    }

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

    window.Na__FacePattern__AppCore = {
        na_init: na_init,
        na_setFaceData: na_setFaceData,
        na_setPattern: na_setPattern,
        na_applyPattern: na_applyPattern,
        na_downloadDxf: na_downloadDxf,
        na_resetView: function () {
            window.Na__FacePattern__SvgPreview.na_resetView(na_state.faceData, na_state.polylines);
        },
        na_setStatus: na_setStatus
    };

    window.Na__FacePattern__SetFaceData = na_setFaceData;
    window.Na__FacePattern__SetStatus = na_setStatus;
})();
