// =============================================================================
// NA PROFILE TOOLS - APP CORE - APP CONTEXT
// =============================================================================
//
// FILE       : Na__ProfileTools__AppCore__AppContext__.js
// NAMESPACE  : window.Na_AppContext
// PURPOSE    : Lightweight shared context for cross-tab communication.
//              Provides a named event bus for the tab system.
//
// =============================================================================

(function () {
    'use strict';

    var Na_AppContext = {};
    var na_listeners = {};

    // -------------------------------------------------------------------------
    // REGION | Event Bus
    // -------------------------------------------------------------------------

    Na_AppContext.na_subscribe = function (eventName, callback) {
        if (!na_listeners[eventName]) na_listeners[eventName] = [];
        na_listeners[eventName].push(callback);
    };

    Na_AppContext.na_dispatch = function (eventName, payload) {
        var handlers = na_listeners[eventName] || [];
        handlers.forEach(function (handler) {
            try { handler(payload); }
            catch (err) { console.error('[Na_AppContext] Handler for ' + eventName + ' failed:', err); }
        });
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Tab Change Hook
    // -------------------------------------------------------------------------

    Na_AppContext.na_on_tab_changed = function (tabId) {
        Na_AppContext.na_dispatch('na_tab_changed', { tabId: tabId });
    };

    // endregion ----------------------------------------------------------------

    window.Na_AppContext = Na_AppContext;

    // endregion ----------------------------------------------------------------
})();
