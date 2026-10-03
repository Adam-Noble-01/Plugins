// =============================================================================
// NA POINT CLOUD VIEWER - APP CORE - UI SYSTEM - BRIDGE BASE
// =============================================================================
//
// FILE       : Na__PointCloudViewer__AppCore__UiSystem__BridgeBase__.js
// NAMESPACE  : window.Na__PointCloudViewer__Bridge
// PURPOSE    : The only code that touches window.sketchup. Two callbacks:
//                na_pcv_dialog_ready()           - ask Ruby for full state
//                na_pcv_action(actionId, json)   - every other request
//              Outside SketchUp (a browser preview) calls are logged instead.
//
// =============================================================================

(function () {
    'use strict';

    var Na__PointCloudViewer__Bridge = {};

    // -------------------------------------------------------------------------
    // REGION | Availability
    // -------------------------------------------------------------------------

    Na__PointCloudViewer__Bridge.na_is_available = function () {
        return typeof window.sketchup !== 'undefined' && typeof window.sketchup.na_pcv_action === 'function';
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Calls
    // -------------------------------------------------------------------------

    Na__PointCloudViewer__Bridge.na_call = function (actionId, payload) {
        var json = JSON.stringify(payload || {});
        if (!Na__PointCloudViewer__Bridge.na_is_available()) {
            console.info('[Na__PointCloudViewer__Bridge] (preview) ' + actionId + ' ' + json);
            return false;
        }
        try {
            window.sketchup.na_pcv_action(actionId, json);
            return true;
        } catch (err) {
            console.error('[Na__PointCloudViewer__Bridge] ' + actionId + ' failed:', err);
            return false;
        }
    };

    Na__PointCloudViewer__Bridge.na_ready = function () {
        if (typeof window.sketchup !== 'undefined' && typeof window.sketchup.na_pcv_dialog_ready === 'function') {
            window.sketchup.na_pcv_dialog_ready();
        }
    };

    // Shows the page's loading overlay first, lets Chromium paint it, THEN
    // calls Ruby - so a long task never starts behind a frozen, blank dialog.
    Na__PointCloudViewer__Bridge.na_call_after_paint = function (actionId, payload, title, status) {
        if (window.Na__PointCloudViewer__Shell) {
            window.Na__PointCloudViewer__Shell.na_loading_show(title, status, null);
        }
        window.requestAnimationFrame(function () {
            window.setTimeout(function () {
                Na__PointCloudViewer__Bridge.na_call(actionId, payload);
            }, 40);
        });
    };

    // endregion ----------------------------------------------------------------

    window.Na__PointCloudViewer__Bridge = Na__PointCloudViewer__Bridge;
})();
