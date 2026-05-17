/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR MULTI-FOLDING DOOR SYSTEM - JS<->RUBY BRIDGE (PHASE-1 SCAFFOLD)
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtFold__UiSystem__Bridge__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : JS-side bridge that calls into the Ruby DialogRouter via
                sketchup.callRuby for the Bifold-Door system.
   CREATED    : 17-May-2026

   PHASE-1 NOTE:
   Skeleton only. Phase-2 wires create/update/liveUpdate/measure calls.
   ============================================================================= */

const Na__ExtFold__UiBridge = (function () {

    // FUNCTION | Create a bifold-door from the current dialog config (Phase-2)
    // ------------------------------------------------------------
    function na_create_bifold_door(config_payload) {
        if (!window.sketchup || typeof window.sketchup.createBifoldDoor !== 'function') {
            console.warn('[NA_EXT_FOLD] createBifoldDoor not registered yet (Phase-1 scaffold).');
            return false;
        }
        window.sketchup.createBifoldDoor(JSON.stringify(config_payload || {}));
        return true;
    }

    // FUNCTION | Live-update a selected bifold-door instance (Phase-3.5)
    // ------------------------------------------------------------
    function na_live_update_bifold_door(door_id, config_payload) {
        if (!window.sketchup || typeof window.sketchup.liveUpdateBifoldDoor !== 'function') return false;
        window.sketchup.liveUpdateBifoldDoor(JSON.stringify({ doorId: door_id, config: config_payload }));
        return true;
    }

    return {
        na_create_bifold_door:        na_create_bifold_door,
        na_live_update_bifold_door:   na_live_update_bifold_door
    };
})();

window.Na__ExtFold__UiBridge = Na__ExtFold__UiBridge;
console.log('[NA_EXT_FOLD] UiSystem Bridge loaded (Phase-1 scaffold).');
