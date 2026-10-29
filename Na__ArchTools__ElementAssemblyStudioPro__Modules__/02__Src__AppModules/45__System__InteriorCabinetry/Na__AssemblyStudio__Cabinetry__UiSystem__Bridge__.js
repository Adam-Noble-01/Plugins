// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - UI TO RUBY BRIDGE
// =============================================================================
//
// FILE       : Na__AssemblyStudio__Cabinetry__UiSystem__Bridge__.js
// AUTHOR     : Noble Architecture
// PURPOSE    : Glue between the Cabinetry tab and
//              Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__DialogRouter.
// CREATED    : 29-Oct-2026
//
// DOCK ACTIONS (onclick in the HTML)
//   na_createCabinetAtCursor()  start placing units with the mouse
//   na_createCabinetInRun()     (2) insert the unit at the next point of the run
//   na_updateCabinet()          rebuild the selected unit
//   na_clearCabinetRun()        forget the measured run
// Measure Run and Live Mode are dispatched by Na_AppContext for this tab.
//
// RUBY -> JS
//   na_setInitialCabinetConfig(json)   a cabinet was selected
//   na_clearCurrentCabinet()           selection cleared (the design is kept)
//   na_receiveCabinetRun(json)         { active, lengthMm, usedMm }
//   na_cabinetMeasureCancelled()
//   na_setCabinetPlacementActive(bool)
//   na_receiveCabinetAssetOptions(json) handle and leg lists + preview data
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix.
//
// =============================================================================

(function () {
    'use strict';

    var NA_FILL_GAP_MAX_MM = 1000;                                            // <-- A measured run up to the widest UK unit is one gap: the width fills it

    window.na_cabinetLiveModeActive  = false;                                 // <-- Flipped by Na_AppContext.na_dispatch_live_toggle
    window.na_cabinetPlacementActive = false;
    window.NA_CABINET_RUN            = { active: false, lengthMm: 0, usedMm: 0 };
    window.NA_CABINET_ASSET_PREVIEW  = window.NA_CABINET_ASSET_PREVIEW || { handles: {}, legs: {} };

    var na_asset_options_requested = false;

// -----------------------------------------------------------------------------
// REGION | Helpers
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Call a Ruby Callback When SketchUp Has Bound It
    // ------------------------------------------------------------
    function na_call(name, payload) {
        if (!window.sketchup || typeof window.sketchup[name] !== 'function') {
            console.warn('[Na_CabinetBridge] sketchup.' + name + ' not available');
            return false;
        }
        try {
            if (payload === undefined) window.sketchup[name]();
            else window.sketchup[name](typeof payload === 'string' ? payload : JSON.stringify(payload));
            return true;
        } catch (err) {
            console.error('[Na_CabinetBridge] ' + name + ' failed:', err);
            return false;
        }
    }
    // ---------------------------------------------------------------

    function na_payload() {
        return (window.Na_CabinetUI && typeof window.Na_CabinetUI.na_get_active_config === 'function')
            ? window.Na_CabinetUI.na_get_active_config() : null;
    }

    function na_status(type, message) {
        if (typeof window.na_showStatus === 'function') window.na_showStatus(type, message);
    }

    function na_mm(value) {
        return Math.round(Number(value) || 0).toLocaleString('en-GB') + 'mm';
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Dock Actions
// -----------------------------------------------------------------------------

    window.na_createCabinetAtCursor = function () {
        var payload = na_payload();
        if (payload) na_call('na_createCabinetAtCursor', payload);
    };

    window.na_createCabinetInRun = function () {
        if (!window.NA_CABINET_RUN.active) {
            na_status('warning', 'No run measured yet. Use Measure Run first.');
            return;
        }
        var payload = na_payload();
        if (payload) na_call('na_createCabinetInRun', payload);
    };

    window.na_updateCabinet = function () {
        var payload = na_payload();
        if (payload) na_call('na_updateCabinet', payload);
    };

    window.na_clearCabinetRun = function () {
        na_call('na_clearCabinetRun');
    };

    window.na_renameCabinet = function (name) {
        na_call('na_renameCabinet', { name: String(name || '') });
    };

    window.na_requestCabinetAssetOptions = function () {
        if (na_asset_options_requested) return;
        if (na_call('na_requestCabinetAssetOptions')) na_asset_options_requested = true;
    };

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Live Mode and Placement (Called by Na_CabinetUI's Debounce)
// -----------------------------------------------------------------------------

    window.na_cabinetLiveUpdateRequested = function (payload) {
        if (!window.na_cabinetLiveModeActive) return;
        var update = document.getElementById('na-btn-cab-update');
        if (update && update.disabled) return;                                 // <-- Nothing selected to rebuild
        na_call('na_liveUpdateCabinet', payload);
    };

    window.na_cabinetPlacementSyncRequested = function (payload) {
        if (!window.na_cabinetPlacementActive) return;
        na_call('na_syncCabinetPlacementConfig', payload);
    };

    // FUNCTION | Ruby -> JS: Placing Started or Finished
    // ------------------------------------------------------------
    window.na_setCabinetPlacementActive = function (active) {
        window.na_cabinetPlacementActive = !!active;
        var button = document.getElementById('na-btn-cab-create');
        if (button) button.classList.toggle('na-dock__btn--placing', !!active);
    };

    // Tab turns the unit while placing, even when the dialog has the focus.
    document.addEventListener('keydown', function (event) {
        if (!window.na_cabinetPlacementActive || event.key !== 'Tab') return;
        if (!window.Na_AppContext || !window.Na_AppContext.na_is_active_tab('cabinets')) return;
        event.preventDefault();
        na_call('na_cabinetPlacementRotate');
    });

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Measured Run
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Arm or Disarm (2) Insert in Run and Its Readout
    // ------------------------------------------------------------
    function na_paint_run() {
        var run    = window.NA_CABINET_RUN;
        var button = document.getElementById('na-btn-cab-create-at-measurement');
        var left   = run.lengthMm - run.usedMm;
        if (button) {
            button.disabled = !run.active;
            button.classList.toggle('na-btn-disabled', !run.active);
            button.classList.toggle('na-btn-create-measure-ready', !!run.active);
            button.title = run.active ? na_mm(run.lengthMm) + ' run, ' + na_mm(Math.max(0, left)) + ' left' : 'Measure a run first';
        }
        var readout = document.getElementById('na-cab-run-readout');
        if (readout) {
            readout.hidden = !run.active;
            readout.textContent = run.active
                ? 'Run ' + na_mm(run.lengthMm) + ' · ' + na_mm(run.usedMm) + ' used · ' + (left >= 0 ? na_mm(left) + ' left' : na_mm(-left) + ' over')
                : '';
        }
        if (window.Na__Ui__ActionDock) window.Na__Ui__ActionDock.na_refresh_hint();
    }
    // ---------------------------------------------------------------

    // FUNCTION | Ruby -> JS: the Run Was Measured, Filled Further or Cleared
    // ------------------------------------------------------------
    // A fresh run no longer than one unit sets the width to fill it, as a
    // measured opening does on the other tabs; a longer run keeps the width
    // and takes units one after another.
    window.na_receiveCabinetRun = function (json) {
        var data = {};
        try { data = JSON.parse(json || '{}'); } catch (err) { console.error('[Na_CabinetBridge] bad run payload', err); }
        var fresh = data.active && Number(data.usedMm) === 0 && !(window.NA_CABINET_RUN.active && window.NA_CABINET_RUN.usedMm === 0 &&
                                                                    window.NA_CABINET_RUN.lengthMm === Number(data.lengthMm));
        window.NA_CABINET_RUN = { active: !!data.active, lengthMm: Number(data.lengthMm) || 0, usedMm: Number(data.usedMm) || 0 };

        var measure = document.getElementById('na-btn-measure');
        if (measure) measure.classList.remove('na-btn-measure-active');

        if (fresh && window.NA_CABINET_RUN.lengthMm <= NA_FILL_GAP_MAX_MM && window.Na_CabinetUI) {
            window.Na_CabinetUI.na_apply_control_value('Na__CabinetConfig__Width_mm', Math.round(window.NA_CABINET_RUN.lengthMm));
            na_status('success', 'Gap measured: ' + na_mm(window.NA_CABINET_RUN.lengthMm) + '. The unit is set to fill it; press ② Insert in Run.');
        } else if (fresh) {
            na_status('success', 'Run measured: ' + na_mm(window.NA_CABINET_RUN.lengthMm) + '. Each ② Insert in Run places the next unit along it.');
        }
        na_paint_run();
    };

    window.na_cabinetMeasureCancelled = function () {
        var measure = document.getElementById('na-btn-measure');
        if (measure) measure.classList.remove('na-btn-measure-active');
    };

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Selection
// -----------------------------------------------------------------------------

    // FUNCTION | Ruby -> JS: a Cabinet Was Selected
    // ------------------------------------------------------------
    window.na_setInitialCabinetConfig = function (json) {
        var payload;
        try { payload = JSON.parse(json); } catch (err) { console.error('[Na_CabinetBridge] bad cabinet payload', err); return; }
        if (!window.Na_CabinetUI) return;
        window.Na_CabinetUI.na_set_active_config(payload);
        if (window.Na_AppContext && window.Na_AppContext.na_is_active_tab('cabinets')) window.Na_CabinetUI.na_mount();
        var update = document.getElementById('na-btn-cab-update');
        if (update) update.disabled = false;
    };

    // FUNCTION | Ruby -> JS: Nothing Selected (the Design Stays for the Next Unit)
    // ------------------------------------------------------------
    window.na_clearCurrentCabinet = function () {
        var update = document.getElementById('na-btn-cab-update');
        if (update) update.disabled = true;
        if (window.Na_CabinetUI && typeof window.Na_CabinetUI.na_clear_edit_state === 'function') window.Na_CabinetUI.na_clear_edit_state();
    };

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Asset Lists (Handles and Legs)
// -----------------------------------------------------------------------------

    // FUNCTION | Ruby -> JS: Handle and Leg Lists With Their Preview Data
    // ------------------------------------------------------------
    window.na_receiveCabinetAssetOptions = function (json) {
        var data;
        try { data = JSON.parse(json || '{}'); } catch (err) { console.error('[Na_CabinetBridge] bad asset payload', err); return; }
        var handles = Array.isArray(data.handles) ? data.handles : [];
        var legs    = Array.isArray(data.legs) ? data.legs : [];

        handles.forEach(function (entry) { window.NA_CABINET_ASSET_PREVIEW.handles[entry.value] = entry; });
        legs.forEach(function (entry) { window.NA_CABINET_ASSET_PREVIEW.legs[entry.value] = entry; });

        if (!window.Na_CabinetUI) return;
        if (handles.length) {
            window.Na_CabinetUI.na_set_select_options('Na__CabinetConfig__HandleAssetKey',
                handles.map(function (entry) { return { value: entry.value, label: entry.label }; }).concat([{ value: 'None', label: 'No Handles' }]));
        }
        if (legs.length) {
            window.Na_CabinetUI.na_set_select_options('Na__CabinetConfig__LegAssetKey',
                legs.map(function (entry) { return { value: entry.value, label: entry.label }; }));
        }
        window.Na_CabinetUI.na_render();
    };

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Initial State
// -----------------------------------------------------------------------------

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', na_paint_run);
    else na_paint_run();

    // The run hint weighs the unit's width against what is left of the run,
    // so it follows every change to the design while a run is measured.
    if (window.Na_CabinetUI) {
        window.Na_CabinetUI.na_add_change_listener(function () {
            if (window.NA_CABINET_RUN.active && window.Na__Ui__ActionDock) window.Na__Ui__ActionDock.na_refresh_hint();
        });
    }

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
