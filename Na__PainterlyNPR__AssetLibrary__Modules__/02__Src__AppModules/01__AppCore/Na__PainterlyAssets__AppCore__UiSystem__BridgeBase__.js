// =============================================================================
// NA PAINTERLYNPR ASSETS - APP CORE - UI SYSTEM - BRIDGE BASE
// =============================================================================
//
// FILE       : Na__PainterlyAssets__AppCore__UiSystem__BridgeBase__.js
// NAMESPACE  : window.Na__PainterlyAssets__Bridge
// PURPOSE    : The only code that touches window.sketchup. Two callbacks:
//                na_npr_dialog_ready()           - ask Ruby for the full state
//                na_npr_action(actionId, json)   - every other request
//              Outside SketchUp (a browser preview) calls are logged instead.
// CREATED    : 30-Oct-2026
//
// =============================================================================

(function () {
    'use strict';

    var Bridge = {};

    // -------------------------------------------------------------------------
    // REGION | Availability
    // -------------------------------------------------------------------------

    Bridge.na_is_available = function () {
        return typeof window.sketchup !== 'undefined' && typeof window.sketchup.na_npr_action === 'function';
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Calls
    // -------------------------------------------------------------------------

    // Returns whether the request reached Ruby, so a caller never waits on a
    // busy state that nothing will end.
    Bridge.na_call = function (actionId, payload) {
        var json = JSON.stringify(payload || {});
        if (!Bridge.na_is_available()) {
            console.info('[Na__PainterlyAssets__Bridge] (preview) ' + actionId + ' ' + json);
            return false;
        }
        try {
            window.sketchup.na_npr_action(actionId, json);
            return true;
        } catch (err) {
            console.error('[Na__PainterlyAssets__Bridge] ' + actionId + ' failed:', err);
            return false;
        }
    };

    // The callbacks can bind a moment after the page parses: retry briefly.
    Bridge.na_ready = function () {
        var tries = 0;
        (function attempt() {
            if (typeof window.sketchup !== 'undefined' && typeof window.sketchup.na_npr_dialog_ready === 'function') {
                window.sketchup.na_npr_dialog_ready();
                return;
            }
            tries += 1;
            if (tries < 8) window.setTimeout(attempt, 100);
        })();
    };

    // Shows the loading overlay first, lets Chromium paint it, THEN calls
    // Ruby, so a long step (building a tree's proxy) never starts behind a
    // frozen, unchanged dialog.
    Bridge.na_call_after_paint = function (actionId, payload, title, status) {
        if (window.Na__PainterlyAssets__Shell) window.Na__PainterlyAssets__Shell.na_loading_show(title, status);
        window.requestAnimationFrame(function () {
            window.setTimeout(function () {
                if (!Bridge.na_call(actionId, payload) && window.Na__PainterlyAssets__Shell) {
                    window.Na__PainterlyAssets__Shell.na_loading_hide();
                }
            }, 40);
        });
    };

    // endregion ----------------------------------------------------------------

    window.Na__PainterlyAssets__Bridge = Bridge;
})();

// =============================================================================
// END OF FILE
// =============================================================================
