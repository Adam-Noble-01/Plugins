// =============================================================================
// NA PROFILE TOOLS - APP CORE - UI SYSTEM - BRIDGE BASE
// =============================================================================
//
// FILE       : Na__ProfileTools__AppCore__UiSystem__BridgeBase__.js
// NAMESPACE  : window.Na__ProfileTools__BridgeBase
// PURPOSE    : Shared SketchUp bridge utilities: availability check, safe call
//              wrapper, and global status setter for any tab module.
//
// =============================================================================

(function () {
    'use strict';

    var Na__ProfileTools__BridgeBase = {};

    // -------------------------------------------------------------------------
    // REGION | Bridge Availability
    // -------------------------------------------------------------------------

    Na__ProfileTools__BridgeBase.Na__BridgeBase__IsAvailable = function () {
        return typeof window.sketchup !== 'undefined';
    };

    Na__ProfileTools__BridgeBase.Na__BridgeBase__HasCallback = function (callbackName) {
        return Na__ProfileTools__BridgeBase.Na__BridgeBase__IsAvailable() &&
               typeof window.sketchup[callbackName] === 'function';
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Safe Call
    // -------------------------------------------------------------------------

    Na__ProfileTools__BridgeBase.Na__BridgeBase__CallSafe = function (callbackName, jsonArg) {
        if (!Na__ProfileTools__BridgeBase.Na__BridgeBase__HasCallback(callbackName)) {
            console.warn('[Na__BridgeBase] Callback not available: ' + callbackName);
            return false;
        }
        try {
            if (jsonArg !== undefined) {
                window.sketchup[callbackName](typeof jsonArg === 'string' ? jsonArg : JSON.stringify(jsonArg));
            } else {
                window.sketchup[callbackName]();
            }
            return true;
        } catch (err) {
            console.error('[Na__BridgeBase] Call failed for ' + callbackName + ':', err);
            return false;
        }
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Status Helper
    // -------------------------------------------------------------------------

    Na__ProfileTools__BridgeBase.Na__BridgeBase__SetStatus = function (message) {
        if (typeof window.Na__ProfilePathTracer__Ui__SetStatusFromBridge === 'function') {
            window.Na__ProfilePathTracer__Ui__SetStatusFromBridge(message);
            return;
        }
        var statusEl = document.getElementById('na-status-message');
        if (statusEl) statusEl.textContent = message || '';
    };

    // endregion ----------------------------------------------------------------

    window.Na__ProfileTools__BridgeBase = Na__ProfileTools__BridgeBase;

    // endregion ----------------------------------------------------------------
})();
