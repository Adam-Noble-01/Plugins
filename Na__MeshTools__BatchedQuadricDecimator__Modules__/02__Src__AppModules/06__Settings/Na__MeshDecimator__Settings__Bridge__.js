// =============================================================================
// NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - SETTINGS TAB BRIDGE
// =============================================================================
//
// FILE       : Na__MeshDecimator__Settings__Bridge__.js
// AUTHOR     : Adam Noble / Noble Architecture
// PURPOSE    : Window globals that forward Settings tab button clicks to
//              the matching SketchUp Ruby action_callbacks.
//
//              Mirrors Na__AssemblyStudio__AppUtils__SettingsTab__Bridge__.js.
//
// WINDOW GLOBALS EXPOSED
//   na_settingsReloadScripts()  — calls sketchup.na_reload_scripts
//
// =============================================================================

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Internal Helpers
    // -------------------------------------------------------------------------

    function Na__MeshDecimator__Settings__ShowStatus(type, message) {
        if (typeof Na__MeshDecimator__Ui__ShowStatus === 'function') {
            Na__MeshDecimator__Ui__ShowStatus(type, message);
        }
    }

    function Na__MeshDecimator__Settings__CallRuby(fnName) {
        if (typeof sketchup === 'undefined' || typeof sketchup[fnName] !== 'function') {
            console.warn('[Na__Settings] sketchup.' + fnName + ' unavailable');
            Na__MeshDecimator__Settings__ShowStatus('warning', 'SketchUp connection not available.');
            return false;
        }
        try {
            sketchup[fnName]();
            return true;
        } catch (err) {
            console.error('[Na__Settings] sketchup.' + fnName + ' threw:', err);
            return false;
        }
    }

    // -------------------------------------------------------------------------
    // REGION | Settings Tab Window Globals
    // -------------------------------------------------------------------------

    window.na_settingsReloadScripts = function () {
        Na__MeshDecimator__Settings__ShowStatus('info', 'Reloading plugin scripts — dialog will reopen...');
        Na__MeshDecimator__Settings__CallRuby('na_reload_scripts');
    };

    // -------------------------------------------------------------------------

})();
