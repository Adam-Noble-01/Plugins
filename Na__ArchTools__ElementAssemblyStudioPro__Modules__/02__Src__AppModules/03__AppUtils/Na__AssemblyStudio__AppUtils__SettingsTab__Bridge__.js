// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - SETTINGS TAB BRIDGE
// =============================================================================
//
// FILE       : Na__AssemblyStudio__AppUtils__SettingsTab__Bridge__.js
// AUTHOR     : Noble Architecture
// PURPOSE    : Registers Settings-tab globals that forward to SketchUp Ruby
//              action_callbacks (na_reloadScripts, na_settingsExport2D/3D)
//              after optional Na_BridgeBase routing.
//
// DESCRIPTION:
// - Prefers Na_BridgeBase for status UX and unified sketchup delegation.
// - Falls back to window.na_showStatus and direct sketchup[fn]() when slim.
//
// NAMING CONVENTION:
// - Window onclick entry points remain na_settings* — HTML contract.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Internal — Status & Ruby Invocation
// -----------------------------------------------------------------------------

    // FUNCTION | Bubble a toast/status line via BridgeBase or fallback
    // ------------------------------------------------------------
    function na_status(type, message) {
        if (typeof Na_BridgeBase !== 'undefined' && Na_BridgeBase.na_status) {
            Na_BridgeBase.na_status(type, message);
        } else if (typeof window.na_showStatus === 'function') {
            window.na_showStatus(type, message);
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Call Ruby callback fn_name safely
    // ------------------------------------------------------------
    function na_call_ruby(fn_name) {
        if (typeof Na_BridgeBase !== 'undefined' && Na_BridgeBase.na_call_ruby) {
            return Na_BridgeBase.na_call_ruby(fn_name);
        }
        if (typeof sketchup === 'undefined' || typeof sketchup[fn_name] !== 'function') return false;
        try {
            sketchup[fn_name]();
            return true;
        }
        catch (err) {
            console.error('[Na_Settings] sketchup.' + fn_name + ' failed:', err);
            return false;
        }
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Settings Tab — SketchUp Boundaries (window globals)
// -----------------------------------------------------------------------------

    // FUNCTION | Reload every Ruby plugin file under Assembly Studio roots
    // ------------------------------------------------------------
    window.na_settingsReloadScripts = function () {
        na_status('info', 'Reloading plugin scripts...');
        if (!na_call_ruby('na_reloadScripts')) {
            na_status('warning', 'SketchUp connection not available - reload skipped.');
        }
    };
    // ---------------------------------------------------------------

    // FUNCTION | Run the 2D asset JSON exporter (selection rules in Ruby/docs)
    // ------------------------------------------------------------
    window.na_settingsExport2D = function () {
        na_status('info', 'Running 2D exporter - check the Ruby Console for output.');
        if (!na_call_ruby('na_settingsExport2D')) {
            na_status('warning', 'SketchUp connection not available - export skipped.');
        }
    };
    // ---------------------------------------------------------------

    // FUNCTION | Run the unified Na__Asset exporter for 3D packs
    // ------------------------------------------------------------
    window.na_settingsExport3D = function () {
        na_status('info', 'Running 3D exporter - check the Ruby Console for output.');
        if (!na_call_ruby('na_settingsExport3D')) {
            na_status('warning', 'SketchUp connection not available - export skipped.');
        }
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


    console.log('[NA_SETTINGS_BRIDGE] Settings tab SketchUp bridge loaded');

})();
