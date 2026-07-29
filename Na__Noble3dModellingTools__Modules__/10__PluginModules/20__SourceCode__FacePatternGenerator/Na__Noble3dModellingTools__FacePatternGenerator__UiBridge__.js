// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN GENERATOR - UI BRIDGE
// =============================================================================
//
// FILE       : Na__Noble3dModellingTools__FacePatternGenerator__UiBridge__.js
// NAMESPACE  : window.Na__FacePattern__* (Ruby-facing entry points)
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Wire the dialog controls to AppCore, fill the pattern selector,
//              and round-trip apply / refresh requests to Ruby.
// CREATED    : 2026
//
// RUBY -> JS : Na__FacePattern__SetFaceData(payload)
//              Na__FacePattern__SetStatus(message, success)
// JS -> RUBY : sketchup.na_dialog_ready / na_refresh_face / na_apply_pattern
//
// =============================================================================

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Shorthand for getElementById
    // ------------------------------------------------------------
    function na_el(id) { return document.getElementById(id); }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Send a Log Line to the Ruby Console
    // ------------------------------------------------------------
    function na_log(message) {
        if (window.sketchup && window.sketchup.na_js_log) {
            window.sketchup.na_js_log(String(message));
        }
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Pattern Selector
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Populate the Pattern Type Dropdown from UiConfig
    // ------------------------------------------------------------
    function na_fillPatternSelector() {
        var selector = na_el('naFacePat_patternType');
        selector.innerHTML = '';
        window.Na__FacePattern__UiConfig.na_patternEntries().forEach(function (entry) {
            var option = document.createElement('option');
            option.value = entry.key;
            option.textContent = entry.label;
            selector.appendChild(option);
        });
        selector.value = 'patio';
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Control Wiring
    // -------------------------------------------------------------------------

    // FUNCTION | Attach All Control and Button Listeners
    // ------------------------------------------------------------
    function na_attachListeners() {
        na_el('naFacePat_patternType').addEventListener('change', function (event) {
            window.Na__FacePattern__AppCore.na_setPattern(event.target.value);
        });

        na_el('naFacePat_btnApply').addEventListener('click', function () {
            window.Na__FacePattern__AppCore.na_applyPattern();
        });

        na_el('naFacePat_btnResetView').addEventListener('click', function () {
            window.Na__FacePattern__AppCore.na_resetView();
        });

        na_el('naFacePat_btnDownloadDxf').addEventListener('click', function () {
            window.Na__FacePattern__AppCore.na_downloadDxf();
        });

        na_el('naFacePat_btnRotateFace').addEventListener('click', function () {
            window.Na__FacePattern__AppCore.na_rotateFace90();
        });

        na_el('naFacePat_btnRefreshFace').addEventListener('click', function () {
            if (window.sketchup && window.sketchup.na_refresh_face) {
                window.sketchup.na_refresh_face('');
            } else {
                window.Na__FacePattern__AppCore.na_setStatus('Face refresh only works inside SketchUp.', false);
            }
        });
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Boot
    // -------------------------------------------------------------------------

    // FUNCTION | Initialise the Dialog on DOMContentLoaded
    // ------------------------------------------------------------
    function na_boot() {
        na_fillPatternSelector();

        window.Na__FacePattern__AppCore.na_init({
            onApply: function (payload) {
                if (window.sketchup && window.sketchup.na_apply_pattern) {
                    window.sketchup.na_apply_pattern(JSON.stringify(payload));
                } else {
                    window.Na__FacePattern__AppCore.na_setStatus('SketchUp bridge unavailable (browser preview mode).', false);
                }
            }
        });

        na_attachListeners();

        if (window.sketchup && window.sketchup.na_dialog_ready) {
            window.sketchup.na_dialog_ready('');                                    // <-- Ask Ruby to push the pre-selected face
        } else {
            na_log('SketchUp bridge not found; running in browser preview mode.');
        }
    }
    // ------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', na_boot);

    // endregion ---------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
