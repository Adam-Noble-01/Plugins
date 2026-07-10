// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - UI EVENT TO RUBY API BRIDGE
// =============================================================================
//
// FILE       : Na__AssemblyStudio__InteriorDoorSystem__UiSystem__Bridge__.js
// AUTHOR     : Noble Architecture
// PURPOSE    : Glue layer between the Door tab UI and the Ruby
//              Na__AssemblyStudio::Na__InteriorDoorSystem::Na__DialogRouter callbacks.
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

    window.NA_DOOR_HANDLE_ASSET_PREVIEW_CACHE = window.NA_DOOR_HANDLE_ASSET_PREVIEW_CACHE || {};
    window.NA_DOOR_HANDLE_ASSET_PREVIEW_WARNINGS = window.NA_DOOR_HANDLE_ASSET_PREVIEW_WARNINGS || {};

    // MODULE STATE | Pending Door Measurement Flag
    // ------------------------------------------------------------
    // Set true between window.na_receiveDoorMeasurement and the next
    // create/cancel/clear. Drives the "Create at Measurement Point"
    // button's enabled state so the user can't accidentally consume
    // a stale (or non-existent) measurement.
    window.na_hasPendingDoorMeasurement = false;
    // ---------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | UI Action Hooks (called from HTML onclick handlers)
// -----------------------------------------------------------------------------

    // FUNCTION | UI Action - Create Door At the Cursor (Identity Placement)
    // ------------------------------------------------------------
    // Explicitly discards any cached measurement on the Ruby side
    // before sending the config, so a stale Point A can never sneak
    // in. Mirrors the Window tab's "Create at Cursor" semantics.
    window.na_createDoorAtCursor = function () {
        if (typeof Na_DoorUI === 'undefined') return;
        var json = JSON.stringify(Na_DoorUI.na_get_active_config());

        if (window.sketchup && typeof window.sketchup.na_createDoorAtCursor === 'function') {
            window.sketchup.na_createDoorAtCursor(json);
        } else if (window.sketchup && typeof window.sketchup.na_createDoor === 'function') {
            window.sketchup.na_createDoor(json);
        } else {
            console.warn('[Na_DoorBridge] sketchup.na_createDoorAtCursor not available');
        }
    };
    // ---------------------------------------------------------------

    // FUNCTION | UI Action - Create Door At the Measured Point A
    // ------------------------------------------------------------
    // Only callable while a 3-point measurement is on file. Consumes
    // the cached frame on the Ruby side and never engages a placement
    // tool, so no cursor-follow ghost can appear.
    window.na_createDoorAtMeasurement = function () {
        if (!window.na_hasPendingDoorMeasurement) {
            console.warn('[Na_DoorBridge] na_createDoorAtMeasurement called with no pending measurement');
            if (typeof window.na_showStatus === 'function') {
                window.na_showStatus('warning', 'No door measurement on file - use "Measure Opening" first.');
            }
            return;
        }
        if (typeof Na_DoorUI === 'undefined') return;
        var json = JSON.stringify(Na_DoorUI.na_get_active_config());

        if (window.sketchup && typeof window.sketchup.na_createDoorAtMeasurement === 'function') {
            window.sketchup.na_createDoorAtMeasurement(json);
        } else if (window.sketchup && typeof window.sketchup.na_createDoor === 'function') {
            window.sketchup.na_createDoor(json);
        } else {
            console.warn('[Na_DoorBridge] sketchup.na_createDoorAtMeasurement not available');
        }

        na_setPendingDoorMeasurementAvailable(false);                                // <-- One-shot consume
    };
    // ---------------------------------------------------------------

    // FUNCTION | UI Action - Create New Door (Legacy Smart Entrypoint)
    // ------------------------------------------------------------
    // Backward-compatible wrapper preserved for any inline onclick
    // that still references `na_createDoor()` directly. Routes to
    // the measurement variant when a pick is on file, otherwise to
    // the cursor variant.
    window.na_createDoor = function () {
        if (window.na_hasPendingDoorMeasurement) {
            window.na_createDoorAtMeasurement();
        } else {
            window.na_createDoorAtCursor();
        }
    };
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Toggle the "Create at Measurement Point" Door Button
    // ------------------------------------------------------------
    function na_setPendingDoorMeasurementAvailable(available) {
        window.na_hasPendingDoorMeasurement = !!available;
        var btn = document.getElementById('na-btn-door-create-at-measurement');
        if (!btn) return;

        if (window.na_hasPendingDoorMeasurement) {
            btn.disabled = false;
            btn.classList.add('na-btn-create-measure-ready');
            btn.classList.remove('na-btn-disabled');
        } else {
            btn.disabled = true;
            btn.classList.remove('na-btn-create-measure-ready');
            btn.classList.add('na-btn-disabled');
        }
    }
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
// REGION | Handle Asset Sync (Ruby -> JS)
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Return the ArchitraveProfile descriptor record
    // ------------------------------------------------------------
    function na_door_get_architrave_descriptor() {
        var source = window.NA_DOOR_ARCHITRAVE_CONFIG || [];
        for (var i = 0; i < source.length; i++) {
            if (source[i] && source[i].id === 'Na__DoorConfig__ArchitraveProfileKey') return source[i];
        }
        return null;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Return the HandleAsset descriptor record
    // ------------------------------------------------------------
    function na_door_get_handle_descriptor() {
        var source = window.NA_DOOR_HANDLE_CONFIG || [];
        for (var i = 0; i < source.length; i++) {
            if (source[i] && source[i].id === 'Na__DoorConfig__HandleAssetKey') return source[i];
        }
        return null;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Patch Select DOM Options for a Control ID
    // ------------------------------------------------------------
    function na_door_patch_select_options(controlId, options, selectedValue) {
        var select = document.getElementById(controlId + '-select');
        if (!select) return;
        select.innerHTML = '';

        (options || []).forEach(function (option) {
            var opt = document.createElement('option');
            opt.value = option.value;
            opt.textContent = option.label;
            if (option.value === selectedValue) opt.selected = true;
            select.appendChild(opt);
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Resolve the Active Handle Asset Key
    // ------------------------------------------------------------
    function na_door_get_active_handle_key() {
        if (typeof Na_DoorUI === 'undefined' || typeof Na_DoorUI.na_get_active_config !== 'function') {
            return '';
        }
        var payload = Na_DoorUI.na_get_active_config();
        var config = payload && payload['Na__DoorConfiguration'];
        var key = config && config['Na__DoorConfig__HandleAssetKey'];
        return (key || '').toString().trim();
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Read One Handle Preview Cache Record
    // ------------------------------------------------------------
    function na_door_get_preview_cache_entry(assetKey) {
        if (!assetKey) return null;
        var cache = window.NA_DOOR_HANDLE_ASSET_PREVIEW_CACHE || {};
        return cache[assetKey] || null;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Assert Cache Entry Exists For Selected Handle
    // ------------------------------------------------------------
    function na_door_ensure_preview_cache_entry(assetKey, reason) {
        if (!assetKey) return;
        var entry = na_door_get_preview_cache_entry(assetKey);
        var hasPlan = !!(entry && entry['Na__Asset__Plan2D']);
        var hasElevation = !!(entry && entry['Na__Asset__Elevation2D']);
        if (hasPlan || hasElevation) return;
        console.warn('[Na_DoorBridge] Missing preview cache for handle:', assetKey, '| reason:', reason || 'unspecified');
        window.na_requestDoorHandlePreviewAsset(assetKey);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Emit Preview Warnings to Console + Status
    // ------------------------------------------------------------
    function na_door_emit_preview_warnings(assetKey, warnings) {
        if (!Array.isArray(warnings) || !warnings.length) return;
        var warningText = warnings.join(' | ');
        window.NA_DOOR_HANDLE_ASSET_PREVIEW_WARNINGS[assetKey] = warningText;
        console.warn('[Na_DoorBridge] Handle preview warnings for', assetKey + ':', warningText);
        if (typeof window.na_showStatus === 'function') {
            window.na_showStatus('warning', 'Handle preview contract warning: ' + warningText);
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Request dynamic handle option list from Ruby
    // ------------------------------------------------------------
    window.na_requestDoorHandleAssetOptions = function () {
        if (!window.sketchup || typeof window.sketchup.na_requestDoorHandleAssetOptions !== 'function') return;
        try {
            window.sketchup.na_requestDoorHandleAssetOptions();
        } catch (err) {
            console.warn('[Na_DoorBridge] na_requestDoorHandleAssetOptions failed:', err);
        }
    };
    // ---------------------------------------------------------------

    // FUNCTION | Request dynamic architrave option list from Ruby
    // ------------------------------------------------------------
    window.na_requestDoorArchitraveAssetOptions = function () {
        if (!window.sketchup || typeof window.sketchup.na_requestDoorArchitraveAssetOptions !== 'function') return;
        try {
            window.sketchup.na_requestDoorArchitraveAssetOptions();
        } catch (err) {
            console.warn('[Na_DoorBridge] na_requestDoorArchitraveAssetOptions failed:', err);
        }
    };
    // ---------------------------------------------------------------

    // FUNCTION | Request selected handle preview blocks from Ruby
    // ------------------------------------------------------------
    window.na_requestDoorHandlePreviewAsset = function (assetKey) {
        if (!window.sketchup || typeof window.sketchup.na_requestDoorHandlePreviewAsset !== 'function') return;
        try {
            var resolvedKey = (assetKey || '').toString().trim();
            if (!resolvedKey) resolvedKey = na_door_get_active_handle_key();
            if (!resolvedKey) resolvedKey = 'Na__InteriorDoor__Handle__Default';
            window.sketchup.na_requestDoorHandlePreviewAsset(resolvedKey);
        } catch (err) {
            console.warn('[Na_DoorBridge] na_requestDoorHandlePreviewAsset failed:', err);
        }
    };
    // ---------------------------------------------------------------

    // FUNCTION | Ruby -> JS - Receive dynamic handle options list
    // ------------------------------------------------------------
    window.na_receiveDoorHandleAssetOptions = function (jsonString) {
        try {
            var payload = JSON.parse(jsonString || '{}');
            var options = Array.isArray(payload.options) ? payload.options : [];
            if (!options.length) {
                console.warn('[Na_DoorBridge] No handle options received from Ruby');
                if (typeof window.na_showStatus === 'function') {
                    window.na_showStatus('warning', 'No valid handle assets available for preview.');
                }
                return;
            }

            var descriptor = na_door_get_handle_descriptor();
            if (!descriptor) return;
            descriptor.options = options;

            var activePayload = (typeof Na_DoorUI !== 'undefined' && typeof Na_DoorUI.na_get_active_config === 'function')
                ? Na_DoorUI.na_get_active_config()
                : null;
            var activeConfig = activePayload && activePayload['Na__DoorConfiguration'] ? activePayload['Na__DoorConfiguration'] : null;
            var selectedKey = activeConfig ? activeConfig['Na__DoorConfig__HandleAssetKey'] : null;

            if (!selectedKey || !options.some(function (opt) { return opt.value === selectedKey; })) {
                selectedKey = payload.defaultKey || options[0].value;
                if (activeConfig) {
                    activeConfig['Na__DoorConfig__HandleAssetKey'] = selectedKey;
                    if (typeof Na_DoorUI !== 'undefined' && typeof Na_DoorUI.na_set_active_config === 'function') {
                        Na_DoorUI.na_set_active_config(activePayload);
                    }
                }
            }

            na_door_patch_select_options('Na__DoorConfig__HandleAssetKey', options, selectedKey);
            na_door_ensure_preview_cache_entry(selectedKey, 'asset-options-received');

            // The Exterior Double Door system intentionally reuses this same
            // InteriorDoor__Handles__ asset library rather than duplicating it.
            var exteriorDescriptor = (window.NA_EXT_DOUBLE_DOOR_CONFIG || []).find(function (item) {
                return item && item.id === 'double_door_handle_asset_key';
            });
            if (exteriorDescriptor) {
                exteriorDescriptor.options = options;
                var exteriorConfig = window.Na_DynamicUI &&
                    typeof window.Na_DynamicUI.na_getConfig === 'function'
                    ? window.Na_DynamicUI.na_getConfig()
                    : {};
                var exteriorSelectedKey = exteriorConfig.double_door_handle_asset_key;
                if (!exteriorSelectedKey || !options.some(function (opt) { return opt.value === exteriorSelectedKey; })) {
                    exteriorSelectedKey = payload.defaultKey || options[0].value;
                }
                na_door_patch_select_options('double_door_handle_asset_key', options, exteriorSelectedKey);
            }
        } catch (err) {
            console.error('[Na_DoorBridge] Failed to receive handle asset options:', err);
        }
    };
    // ---------------------------------------------------------------

    // FUNCTION | Ruby -> JS - Receive dynamic architrave options list
    // ------------------------------------------------------------
    window.na_receiveDoorArchitraveAssetOptions = function (jsonString) {
        try {
            var payload = JSON.parse(jsonString || '{}');
            var options = Array.isArray(payload.options) ? payload.options : [];
            if (!options.length) {
                console.warn('[Na_DoorBridge] No architrave options received from Ruby');
                if (typeof window.na_showStatus === 'function') {
                    window.na_showStatus('warning', 'No valid architrave assets available.');
                }
                return;
            }

            var descriptor = na_door_get_architrave_descriptor();
            if (!descriptor) return;
            descriptor.options = options;

            var activePayload = (typeof Na_DoorUI !== 'undefined' && typeof Na_DoorUI.na_get_active_config === 'function')
                ? Na_DoorUI.na_get_active_config()
                : null;
            var activeConfig = activePayload && activePayload['Na__DoorConfiguration'] ? activePayload['Na__DoorConfiguration'] : null;
            var selectedKey = activeConfig ? activeConfig['Na__DoorConfig__ArchitraveProfileKey'] : null;

            if (!selectedKey || !options.some(function (opt) { return opt.value === selectedKey; })) {
                selectedKey = payload.defaultKey || options[0].value;
                if (activeConfig) {
                    activeConfig['Na__DoorConfig__ArchitraveProfileKey'] = selectedKey;
                    if (typeof Na_DoorUI !== 'undefined' && typeof Na_DoorUI.na_set_active_config === 'function') {
                        Na_DoorUI.na_set_active_config(activePayload);
                    }
                }
            }

            na_door_patch_select_options('Na__DoorConfig__ArchitraveProfileKey', options, selectedKey);
        } catch (err) {
            console.error('[Na_DoorBridge] Failed to receive architrave asset options:', err);
        }
    };
    // ---------------------------------------------------------------

    // FUNCTION | Ruby -> JS - Receive one handle preview payload
    // ------------------------------------------------------------
    window.na_receiveDoorHandlePreviewAsset = function (jsonString) {
        try {
            var payload = JSON.parse(jsonString || '{}');
            var key = payload.assetKey;
            if (!key) return;
            var warnings = Array.isArray(payload.warnings) ? payload.warnings : [];

            window.NA_DOOR_HANDLE_ASSET_PREVIEW_CACHE[key] = {
                'Na__Asset__Plan2D'      : payload['Na__Asset__Plan2D'] || null,
                'Na__Asset__Elevation2D' : payload['Na__Asset__Elevation2D'] || null
            };
            na_door_emit_preview_warnings(key, warnings);

            if (!payload['Na__Asset__Plan2D'] && !payload['Na__Asset__Elevation2D']) {
                console.warn('[Na_DoorBridge] Preview payload has no usable 2D blocks for:', key);
                if (typeof window.na_showStatus === 'function') {
                    window.na_showStatus('warning', 'Handle preview payload has no valid Plan2D/Elevation2D data.');
                }
            }

            if (typeof Na_DoorUI !== 'undefined' && typeof Na_DoorUI.na_render === 'function' && typeof Na_DoorUI.na_get_active_config === 'function') {
                var activePayload = Na_DoorUI.na_get_active_config();
                var activeConfig = activePayload && activePayload['Na__DoorConfiguration'];
                if (activeConfig) {
                    Na_DoorUI.na_render(activeConfig);
                }
            }
        } catch (err) {
            console.error('[Na_DoorBridge] Failed to receive handle preview asset:', err);
        }
    };
    // ---------------------------------------------------------------

    // FUNCTION | Public cache helper for deterministic preview checks
    // ------------------------------------------------------------
    window.na_getDoorHandlePreviewCacheEntry = function (assetKey) {
        return na_door_get_preview_cache_entry(assetKey);
    };
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
    //
    // BUGFIX (post-EASP-v2): When a saved door is re-selected from the
    // SketchUp viewport the previous implementation only called
    // Na_DoorUI.na_render(...), which repaints the plan + elevation
    // viewports but does NOT push the loaded values into the slider DOM
    // inputs. The result was a UI that showed stale slider positions
    // while the active config was actually correct. We now call
    // Na_DoorUI.na_mount(payload) when the Doors tab is visible, which
    // is the same path the post-measurement flow uses (see line ~293).
    // na_mount internally sets the active config and rebuilds every
    // section's controls from descriptors, so each slider/select/toggle
    // is freshly bound to the new values.
    window.na_setInitialDoorConfig = function (jsonString) {
        try {
            var payload = JSON.parse(jsonString);
            if (typeof Na_DoorUI !== 'undefined') {
                Na_DoorUI.na_set_active_config(payload);
                if (typeof Na_AppContext !== 'undefined' &&
                    Na_AppContext.na_is_active_tab('doors')) {                 // <-- single source for "is doors visible?"
                    if (typeof Na_DoorUI.na_mount === 'function') {
                        Na_DoorUI.na_mount(payload);                           // <-- Rebuilds slider DOM from new config + renders viewports
                    } else {
                        Na_DoorUI.na_render(payload['Na__DoorConfiguration'] || payload);
                    }
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

        na_setPendingDoorMeasurementAvailable(false);                          // <-- Deselect must not leave the measurement button armed
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
            if (typeof Na_DoorUI.na_render === 'function') {
                Na_DoorUI.na_render(conf);                                    // <-- 1b. Force preview repaint even if remount later fails
            }

            na_door_patch_slider_dom('Na__DoorConfig__OpeningWidth_mm',  widthMm);  // <-- 2a. Direct DOM patch (visible immediately)
            na_door_patch_slider_dom('Na__DoorConfig__OpeningHeight_mm', heightMm); // <-- 2b
            na_door_patch_slider_dom('Na__DoorConfig__WallDepth_mm',     depthMm);  // <-- 2c

            try {
                Na_DoorUI.na_mount(payload);                                  // <-- 3. Refresh elastic ranges + render
            } catch (mountErr) {
                console.error('[Na_DoorBridge] na_mount after measurement failed:', mountErr);
            }

            // If Live Mode is currently active, immediately push the measured
            // dimensions to Ruby so the selected door's 3D geometry updates
            // without requiring an extra manual control nudge.
            if (window.na_doorLiveModeActive &&
                typeof window.na_doorLiveUpdateRequested === 'function') {
                try {
                    window.na_doorLiveUpdateRequested(Na_DoorUI.na_get_active_config());
                } catch (liveErr) {
                    console.error('[Na_DoorBridge] live update after measurement failed:', liveErr);
                }
            }

            na_setPendingDoorMeasurementAvailable(true);                         // <-- Arm the "Create at Measurement Point" button

            if (typeof window.na_showStatus === 'function') {
                window.na_showStatus(
                    'success',
                    'Door opening measured: ' + widthMm + 'mm x ' + heightMm + 'mm x ' + depthMm + 'mm  -  "Create at Measurement Point" is now active.'
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
        na_setPendingDoorMeasurementAvailable(false);                         // <-- Cancelled pick should never leave the measurement button armed
    };
    // ---------------------------------------------------------------

    // INITIALISATION | Sync the "Create at Measurement Point" button on load
    // ------------------------------------------------------------
    // Run once after the DOM has the door tab markup so the class
    // state and the `disabled` attribute are in sync from the very
    // first frame, even before any Ruby callback fires.
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () {
            na_setPendingDoorMeasurementAvailable(false);
        });
    } else {
        na_setPendingDoorMeasurementAvailable(false);
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
