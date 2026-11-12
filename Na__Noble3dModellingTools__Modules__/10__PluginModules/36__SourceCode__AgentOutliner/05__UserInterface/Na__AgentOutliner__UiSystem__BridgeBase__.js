// =============================================================================
// NA AGENT OUTLINER - UI SYSTEM - BRIDGE BASE
// =============================================================================
//
// FILE       : Na__AgentOutliner__UiSystem__BridgeBase__.js
// NAMESPACE  : window.Na__AgentOutliner__Bridge
// MODULE     : Bridge (IIFE)
// AUTHOR     : Noble Architecture
// PURPOSE    : The only code that touches window.sketchup. Two callbacks:
//                na_ao_ready()            ask Ruby for everything
//                na_ao_action(id, json)   every other request
//              Outside SketchUp (a browser preview or the offline smoke test)
//              calls are logged instead, and a stub can stand in.
// CREATED    : 10-Nov-2026
//
// DESCRIPTION:
// - The callbacks can bind a moment after the page parses: ready retries.
// - Every call reports whether it reached Ruby, so nothing waits on a busy
//   state that no answer will ever end.
//
// =============================================================================

(function () {
    'use strict';

    var Bridge = {};

    // -------------------------------------------------------------------------
    // REGION | Availability
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Is SketchUp's Bridge Here?
    // @return {boolean}
    Bridge.na_is_available = function () {
        return typeof window.sketchup !== 'undefined' && typeof window.sketchup.na_ao_action === 'function';
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Calls
    // -------------------------------------------------------------------------

    // FUNCTION | Send One Action to Ruby
    // @param actionId {string}
    // @param payload  {Object}
    // @return {boolean} true when it reached Ruby
    Bridge.na_call = function (actionId, payload) {
        var json = JSON.stringify(payload || {});
        if (!Bridge.na_is_available()) {
            console.info('[Na__AgentOutliner__Bridge] (preview) ' + actionId + ' ' + json);
            return false;
        }
        try {
            window.sketchup.na_ao_action(actionId, json);
            return true;
        } catch (err) {
            console.error('[Na__AgentOutliner__Bridge] ' + actionId + ' failed:', err);
            return false;
        }
    };

    // FUNCTION | Tell Ruby the Page Is Ready (retries while the callback binds)
    Bridge.na_ready = function () {
        var tries = 0;
        (function attempt() {
            if (typeof window.sketchup !== 'undefined' && typeof window.sketchup.na_ao_ready === 'function') {
                window.sketchup.na_ao_ready();
                return;
            }
            tries += 1;
            if (tries < 10) window.setTimeout(attempt, 100);
        })();
    };

    // endregion ----------------------------------------------------------------

    window.Na__AgentOutliner__Bridge = Bridge;
})();

// =============================================================================
// END OF FILE
// =============================================================================
