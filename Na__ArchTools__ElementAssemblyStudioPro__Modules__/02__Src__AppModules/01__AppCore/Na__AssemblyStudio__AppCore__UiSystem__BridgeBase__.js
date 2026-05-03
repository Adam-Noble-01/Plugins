// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - BRIDGE BASE (small shared JS helpers)
// =============================================================================
//
// FILE       : Na__AssemblyStudio__AppCore__UiSystem__BridgeBase__.js
// NAMESPACE  : window.Na_BridgeBase
// AUTHOR     : Noble Architecture
// PURPOSE    : Tiny set of shared helpers used by every per-system bridge
//              (Window, Settings, InteriorDoor). Each system bridge keeps its
//              own create/update/live/debounce logic; the only things that
//              were genuinely duplicated across all three bridges are gathered
//              here.
//
// PUBLIC API
//   window.Na_BridgeBase.na_sketchup_available()
//       True iff the SketchUp HtmlDialog bridge is installed.
//   window.Na_BridgeBase.na_status(type, message)
//       Front-end convenience for window.na_showStatus with safety guard.
//   window.Na_BridgeBase.na_log_to_ruby(message)
//       Forward a debug message to Ruby's DebugTools via sketchup.na_jsLog.
//   window.Na_BridgeBase.na_call_ruby(fnName, payload)
//       Safely call sketchup.<fnName>(JSON.stringify(payload)) when the
//       bridge exists. Returns true on success, false otherwise.
// =============================================================================

(function () {
    'use strict';

    var Na_BridgeBase = {};

    Na_BridgeBase.na_sketchup_available = function () {
        return typeof sketchup !== 'undefined';
    };

    Na_BridgeBase.na_status = function (type, message, persistent) {
        if (typeof window.na_showStatus !== 'function') return;
        try { window.na_showStatus(type, message, persistent === true); }
        catch (err) { console.warn('[Na_BridgeBase] na_showStatus failed:', err); }
    };

    Na_BridgeBase.na_log_to_ruby = function (message) {
        if (!Na_BridgeBase.na_sketchup_available())  return;
        if (typeof sketchup.na_jsLog !== 'function') return;
        try { sketchup.na_jsLog(String(message)); }
        catch (err) { console.warn('[Na_BridgeBase] na_jsLog failed:', err); }
    };

    Na_BridgeBase.na_call_ruby = function (fnName, payload) {
        if (!Na_BridgeBase.na_sketchup_available()) return false;
        if (typeof sketchup[fnName] !== 'function') {
            console.warn('[Na_BridgeBase] sketchup.' + fnName + ' unavailable');
            return false;
        }
        try {
            if (typeof payload === 'undefined') {
                sketchup[fnName]();
            } else {
                sketchup[fnName](JSON.stringify(payload));
            }
            return true;
        } catch (err) {
            console.error('[Na_BridgeBase] sketchup.' + fnName + ' threw:', err);
            return false;
        }
    };

    window.Na_BridgeBase = Na_BridgeBase;
})();
