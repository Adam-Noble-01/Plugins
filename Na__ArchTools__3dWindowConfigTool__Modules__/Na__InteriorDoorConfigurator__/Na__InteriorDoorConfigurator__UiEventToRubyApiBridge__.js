// =============================================================================
// NA INTERIOR DOOR CONFIGURATOR - UI EVENT TO RUBY API BRIDGE
// =============================================================================
//
// FILE       : Na__InteriorDoorConfigurator__UiEventToRubyApiBridge__.js
// AUTHOR     : Noble Architecture
// PURPOSE    : Glue layer between the Door tab UI and the Ruby
//              Na__InteriorDoorConfigurator::Na__DialogRouter callbacks.
// CREATED    : 01-May-2026
//
// DESCRIPTION:
// - Mirrors the responsibilities of the Window tab bridge but for door
//   actions. The Ruby side exposes these add_action_callback names:
//     * na_createDoor          (config_json)
//     * na_updateDoor          (config_json)
//     * na_liveUpdateDoor      (config_json)
//     * na_measureDoorOpening
//     * na_doorRequestConfig
//     * na_doorJsLog           (message)
// - Ruby talks back via these globals on the JS side:
//     * window.na_setInitialDoorConfig(json_string)
//     * window.na_clearCurrentDoor()
//     * window.na_receiveDoorMeasurement(width_mm, height_mm, depth_mm,
//                                       origin_x_in, origin_y_in, origin_z_in)
//     * window.na_doorMeasureCancelled()
//
// v0.11.6 - The per-tab `Live Mode` and `Measure Door Opening` buttons
// have been retired. The global header buttons are wired through
// Na_AppContext.na_dispatch_live_toggle() and na_dispatch_measure(),
// which read the active tab and call window.na_doorLiveModeActive +
// sketchup.na_measureDoorOpening as needed. This file therefore only
// declares the door-side flag the dispatcher mutates, plus the Ruby
// callbacks below.
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | UI Action Hooks (called from HTML onclick handlers)
// -----------------------------------------------------------------------------

    // FUNCTION | UI Action - Create New Door
    // ------------------------------------------------------------
    window.na_createDoor = function () {
        if (typeof Na_DoorUI === 'undefined') return;
        var payload = Na_DoorUI.na_get_active_config();
        var json    = JSON.stringify(payload);

        if (window.sketchup && typeof window.sketchup.na_createDoor === 'function') {
            window.sketchup.na_createDoor(json);
        } else {
            console.warn('[Na_DoorBridge] sketchup.na_createDoor not available');
        }
    };
    // ---------------------------------------------------------------

    // FUNCTION | UI Action - Update Existing Door
    // ------------------------------------------------------------
    window.na_updateDoor = function () {
        if (typeof Na_DoorUI === 'undefined') return;
        var payload = Na_DoorUI.na_get_active_config();
        var json    = JSON.stringify(payload);

        if (window.sketchup && typeof window.sketchup.na_updateDoor === 'function') {
            window.sketchup.na_updateDoor(json);
        }
    };
    // ---------------------------------------------------------------

    // MODULE STATE | Live Mode Flag (Mutated by Na_AppContext)
    // ------------------------------------------------------------
    // The door tab's live-mode boolean. Na_AppContext.na_dispatch_live_toggle()
    // flips this when the user clicks the global Live Mode button while the
    // Doors tab is active, and na_doorLiveUpdateRequested below early-returns
    // if it is still false. There is no longer a window.na_toggleDoorLiveMode
    // or window.na_measureDoorOpening - both onclick handlers were removed
    // when the door tab's secondary header was deleted in v0.11.6.
    window.na_doorLiveModeActive = false;
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Live Update Hook (consumed by Na_DoorUI's debounced loop)
// -----------------------------------------------------------------------------

    // FUNCTION | Forward a Debounced Live Update to Ruby
    // ------------------------------------------------------------
    // Wired to Na_DoorUI internally. Only fires when Live Mode is on.
    window.na_doorLiveUpdateRequested = function (configPayload) {
        if (!window.na_doorLiveModeActive)              return;
        if (!window.sketchup)                           return;
        if (typeof window.sketchup.na_liveUpdateDoor !== 'function') return;

        try {
            window.sketchup.na_liveUpdateDoor(JSON.stringify(configPayload));
        } catch (err) {
            console.error('[Na_DoorBridge] Live update serialise failed:', err);
        }
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Ruby -> JS Callbacks
// -----------------------------------------------------------------------------

    // FUNCTION | Ruby -> JS - Receive Initial Door Config From Ruby
    // ------------------------------------------------------------
    // Called by Na__DialogRouter.na_send_door_config_to_dialog with a
    // JSON string representation of the full door payload.
    window.na_setInitialDoorConfig = function (jsonString) {
        try {
            var payload = JSON.parse(jsonString);
            if (typeof Na_DoorUI !== 'undefined') {
                Na_DoorUI.na_set_active_config(payload);
                if (typeof Na_AppContext !== 'undefined' &&
                    Na_AppContext.na_is_active_tab('doors')) {                 // <-- v0.11.6 single source for "is doors visible?"
                    Na_DoorUI.na_render(payload['Na__DoorConfiguration'] || payload);
                }
            }

            var btnUpdate = document.getElementById('na-btn-door-update');
            if (btnUpdate) btnUpdate.disabled = false;
        } catch (err) {
            console.error('[Na_DoorBridge] Failed to parse door config JSON:', err);
        }
    };
    // ---------------------------------------------------------------

    // FUNCTION | Ruby -> JS - Clear the Currently Loaded Door
    // ------------------------------------------------------------
    // v0.11.6 - Now performs a full reset of the door tab, not just
    // the Update button. With the new tab-aware SelectionObserver
    // this fires more often (any deselect or off-tab selection clears
    // both tabs), so a half-reset would leak the previous door's
    // config into the next selection.
    window.na_clearCurrentDoor = function () {
        var btnUpdate = document.getElementById('na-btn-door-update');
        if (btnUpdate) btnUpdate.disabled = true;

        var descInput = document.getElementById('na-info-door-description');   // <-- Reset the description input
        if (descInput) descInput.value = '';

        var infoSection = document.getElementById('na-door-info');             // <-- Hide the info block (defensive)
        if (infoSection) infoSection.classList.add('na-hidden');

        if (typeof Na_DoorUI !== 'undefined' &&                                // <-- Replace working config with the descriptor defaults
            typeof Na_DoorUI.na_reset_to_default === 'function') {
            try {
                Na_DoorUI.na_reset_to_default();
            } catch (resetErr) {
                console.warn('[Na_DoorBridge] Na_DoorUI.na_reset_to_default failed:', resetErr);
            }
        }
    };
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Locate a Descriptor by its Configuration Key
    // ------------------------------------------------------------
    // Walks every descriptor array exported by the door config module
    // and returns the first descriptor whose `id` matches. Returns null
    // when the key is unknown to the descriptor set so callers can keep
    // patching DOM nodes regardless.
    function na_door_lookup_descriptor(id) {
        var sources = [
            window.NA_DOOR_OPENING_CONFIG,
            window.NA_DOOR_PANEL_TAB_CONFIG,
            window.NA_DOOR_ARCHITRAVE_CONFIG,
            window.NA_DOOR_HANDLE_CONFIG,
            window.NA_DOOR_OPTIONS_CONFIG
        ];
        for (var i = 0; i < sources.length; i++) {
            var arr = sources[i] || [];
            for (var j = 0; j < arr.length; j++) {
                if (arr[j] && arr[j].id === id) return arr[j];
            }
        }
        return null;
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | Patch a Live Slider Triple (slider + input + display)
    // ------------------------------------------------------------
    // Updates the three DOM nodes the door UI builds for every slider:
    //     <id>-slider   <-- range input
    //     <id>-input    <-- number input
    //     <id>-display  <-- inline value label
    // If the measured value exceeds the descriptor's static `max`, the
    // descriptor and both inputs have their `max` widened in-place so
    // the value sticks instead of clamping. Returns true on a successful
    // patch, false if the slider DOM nodes are not currently mounted
    // (e.g. user is on the Windows tab).
    function na_door_patch_slider_dom(id, valueMm) {
        if (typeof valueMm !== 'number' || isNaN(valueMm)) return false;

        var slider  = document.getElementById(id + '-slider');                // <-- Range input
        var input   = document.getElementById(id + '-input');                 // <-- Number input
        var display = document.getElementById(id + '-display');               // <-- Value label
        if (!slider && !input && !display) return false;                      // <-- Not mounted - silent skip

        var descriptor = na_door_lookup_descriptor(id);                       // Resolve descriptor for elastic max
        if (descriptor && typeof descriptor.max === 'number') {
            if (valueMm > descriptor.max) {
                descriptor.max = valueMm;                                     // <-- Widen descriptor in-place
                if (slider) slider.max = String(descriptor.max);
                if (input)  input.max  = String(descriptor.max);
            }
        }

        var unitSuffix = (descriptor && descriptor.unit) ? descriptor.unit : 'mm';
        if (slider)  slider.value      = String(valueMm);
        if (input)   input.value       = String(valueMm);
        if (display) display.textContent = valueMm + unitSuffix;
        return true;
    }
    // ------------------------------------------------------------


    // FUNCTION | Ruby -> JS - Receive Measurement Result From the 3-Point Tool
    // ------------------------------------------------------------
    // The Ruby tool passes the dimensions plus the origin Point A
    // expressed in inches. Point A is cached server-side and consumed
    // by the next na_createDoor as the insertion origin. On the JS
    // side we do three things, in order, so that a failure in any one
    // step does not silently kill the others:
    //   1. Update the working config so the next na_createDoor /
    //      na_updateDoor sends the measured values to Ruby.
    //   2. Patch the live slider DOM directly so the user sees the
    //      values immediately, even if a downstream re-mount throws.
    //   3. Trigger Na_DoorUI.na_mount() to keep elastic ranges and the
    //      viewport renderer in sync going forward.
    // Wrapped in try/catch and logged so a regression is loud, not
    // silent.
    window.na_receiveDoorMeasurement = function (widthMm, heightMm, depthMm /*, originXIn, originYIn, originZIn */) {
        // v0.11.7 - Entry log so the Ruby Console shows what arrived from
        // the Ruby bridge. The Ruby side now Float-casts every numeric
        // argument before interpolation, so anything arriving here that
        // ISN'T a JS number is a regression and we want it loud.
        console.log(
            '[Na_DoorBridge] na_receiveDoorMeasurement called',
            'widthMm=', widthMm, 'heightMm=', heightMm, 'depthMm=', depthMm
        );

        if (typeof Na_DoorUI === 'undefined') {
            console.warn('[Na_DoorBridge] Na_DoorUI not loaded; ignoring measurement');
            return;
        }

        if (typeof widthMm  !== 'number' || isNaN(widthMm)  ||
            typeof heightMm !== 'number' || isNaN(heightMm) ||
            typeof depthMm  !== 'number' || isNaN(depthMm)) {
            console.error(
                '[Na_DoorBridge] na_receiveDoorMeasurement got bad args - ignoring',
                widthMm, heightMm, depthMm
            );
            if (typeof window.na_showStatus === 'function') {
                window.na_showStatus('error', 'Door measurement data corrupted - check Ruby Console.');
            }
            return;
        }

        try {
            var payload = Na_DoorUI.na_get_active_config();
            var conf    = payload && payload['Na__DoorConfiguration'];
            if (!conf) {
                console.warn('[Na_DoorBridge] Active config has no Na__DoorConfiguration block');
                return;
            }

            conf['Na__DoorConfig__OpeningWidth_mm']  = widthMm;
            conf['Na__DoorConfig__OpeningHeight_mm'] = heightMm;
            conf['Na__DoorConfig__WallDepth_mm']     = depthMm;

            Na_DoorUI.na_set_active_config(payload);                          // <-- 1. Working config snapshot

            na_door_patch_slider_dom('Na__DoorConfig__OpeningWidth_mm',  widthMm);  // <-- 2a. Direct DOM patch (visible immediately)
            na_door_patch_slider_dom('Na__DoorConfig__OpeningHeight_mm', heightMm); // <-- 2b
            na_door_patch_slider_dom('Na__DoorConfig__WallDepth_mm',     depthMm);  // <-- 2c

            try {
                Na_DoorUI.na_mount(payload);                                  // <-- 3. Refresh elastic ranges + render
            } catch (mountErr) {
                console.error('[Na_DoorBridge] na_mount after measurement failed:', mountErr);
            }

            if (typeof window.na_showStatus === 'function') {
                window.na_showStatus(
                    'success',
                    'Door opening measured: ' + widthMm + 'mm x ' + heightMm + 'mm x ' + depthMm + 'mm  -  Insert at Point A queued.'
                );
            }
        } catch (err) {
            console.error('[Na_DoorBridge] na_receiveDoorMeasurement failed:', err);
            if (typeof window.na_showStatus === 'function') {
                window.na_showStatus('error', 'Door measurement update failed - check Ruby Console.');
            }
        }

        var btn = document.getElementById('na-btn-measure');                  // <-- Unified global Measure Opening button
        if (btn) btn.classList.remove('na-btn-measure-active');
    };
    // ---------------------------------------------------------------

    // FUNCTION | Ruby -> JS - Notify That the User Cancelled Measurement
    // ------------------------------------------------------------
    window.na_doorMeasureCancelled = function () {
        var btn = document.getElementById('na-btn-measure');                  // <-- Unified global Measure Opening button
        if (btn) btn.classList.remove('na-btn-measure-active');
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
