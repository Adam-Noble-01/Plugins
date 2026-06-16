(function () {
    'use strict';

    function na_fillPatternSelector() {
        var selector = document.getElementById('naFacePat_patternType');
        selector.innerHTML = '';
        window.Na__FacePattern__UiConfig.na_patternEntries().forEach(function (entry) {
            var option = document.createElement('option');
            option.value = entry.key;
            option.textContent = entry.label;
            selector.appendChild(option);
        });
        selector.value = 'patio';
    }

    function na_log(message) {
        if (window.sketchup && window.sketchup.na_js_log) {
            window.sketchup.na_js_log(String(message));
        }
    }

    function na_boot() {
        na_fillPatternSelector();

        window.Na__FacePattern__AppCore.na_init({
            onApply: function (payload) {
                if (window.sketchup && window.sketchup.na_apply_pattern) {
                    window.sketchup.na_apply_pattern(JSON.stringify(payload));
                } else {
                    window.Na__FacePattern__AppCore.na_setStatus('SketchUp bridge unavailable in browser preview mode.', false);
                }
            }
        });

        document.getElementById('naFacePat_patternType').addEventListener('change', function (event) {
            window.Na__FacePattern__AppCore.na_setPattern(event.target.value);
        });

        document.getElementById('naFacePat_btnApply').addEventListener('click', function () {
            window.Na__FacePattern__AppCore.na_applyPattern();
        });

        document.getElementById('naFacePat_btnResetView').addEventListener('click', function () {
            window.Na__FacePattern__AppCore.na_resetView();
        });

        document.getElementById('naFacePat_btnDownloadDxf').addEventListener('click', function () {
            window.Na__FacePattern__AppCore.na_downloadDxf();
        });

        document.getElementById('naFacePat_btnRefreshFace').addEventListener('click', function () {
            if (window.sketchup && window.sketchup.na_refresh_face) {
                window.sketchup.na_refresh_face('');
            } else {
                window.Na__FacePattern__AppCore.na_setStatus('Face refresh only works inside SketchUp.', false);
            }
        });

        if (window.sketchup && window.sketchup.na_dialog_ready) {
            window.sketchup.na_dialog_ready('');
        } else {
            na_log('SketchUp bridge not found; running in browser preview mode.');
        }
    }

    document.addEventListener('DOMContentLoaded', na_boot);
})();
