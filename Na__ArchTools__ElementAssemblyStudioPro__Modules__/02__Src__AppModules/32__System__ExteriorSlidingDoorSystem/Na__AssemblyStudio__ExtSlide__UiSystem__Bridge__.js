/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SLIDING DOOR SYSTEM - JS<->RUBY BRIDGE (PHASE-1 SCAFFOLD)
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtSlide__UiSystem__Bridge__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : JS-side bridge that calls into the Ruby DialogRouter via
                sketchup.callRuby for the Sliding-Door system.
   CREATED    : 17-May-2026

   PHASE-1 NOTE:
   Skeleton only. Phase-2 wires create/update/liveUpdate/measure calls.
   ============================================================================= */

const Na__ExtSlide__UiBridge = (function () {

    // FUNCTION | Create a sliding-door from the current dialog config (Phase-2)
    // ------------------------------------------------------------
    function na_create_sliding_door(config_payload) {
        if (!window.sketchup || typeof window.sketchup.createSlidingDoor !== 'function') {
            console.warn('[NA_EXT_SLIDE] createSlidingDoor not registered yet (Phase-1 scaffold).');
            return false;
        }
        window.sketchup.createSlidingDoor(JSON.stringify(config_payload || {}));
        return true;
    }

    // FUNCTION | Live-update a selected sliding-door instance (Phase-3.5)
    // ------------------------------------------------------------
    function na_live_update_sliding_door(door_id, config_payload) {
        if (!window.sketchup || typeof window.sketchup.liveUpdateSlidingDoor !== 'function') return false;
        window.sketchup.liveUpdateSlidingDoor(JSON.stringify({ doorId: door_id, config: config_payload }));
        return true;
    }

    return {
        na_create_sliding_door:       na_create_sliding_door,
        na_live_update_sliding_door:  na_live_update_sliding_door
    };
})();

window.Na__ExtSlide__UiBridge = Na__ExtSlide__UiBridge;
console.log('[NA_EXT_SLIDE] UiSystem Bridge loaded (Phase-1 scaffold).');
