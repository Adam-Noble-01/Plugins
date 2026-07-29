// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - APP CONTEXT (UNIFIED STATE)
// =============================================================================
//
// FILE       : Na__AssemblyStudio__AppCore__AppContext__.js
// NAMESPACE  : Na_AppContext (browser global)
// AUTHOR     : Noble Architecture
// PURPOSE    : Single source of truth for the active tab + the global header
//              actions (Measure Opening, Live Mode). Owns per-tab Live state
//              and dispatches to per-tab Ruby callbacks.
//
// REFACTOR NOTES (v2 / EASP)
// - Tab list still hardcodes windows/doors/settings (plus the presets pages)
//   for the v2 rebrand; future tabs (e.g. skylights) will swap this for a
//   registry driven by the AppConfig.tabs array.
// =============================================================================

(function () {
    'use strict';

    var Na_AppContext              = {};

    var NA_BTN_LIVE_ID             = 'na-btn-live';
    var NA_BTN_MEASURE_ID          = 'na-btn-measure';
    var NA_BTN_MEASURE_ACTIVE_CLS  = 'na-btn-measure-active';
    var NA_BTN_LIVE_ACTIVE_CLS     = 'na-btn-live-active';

    var NA_TAB_WINDOWS             = 'windows';
    var NA_TAB_DOORS               = 'doors';
    var NA_TAB_SETTINGS            = 'settings';
    var NA_TAB_PRESETS             = 'presets';
    var NA_TAB_PRESET_EDITOR       = 'preset_editor';

    var NA_PRESETS_MODE_CLS        = 'na-presets-mode';

    var na_live_state = { windows: false, doors: false };

    // -----------------------------------------------------------------------
    // REGION | DOM helpers
    // -----------------------------------------------------------------------

    function na_get_button(buttonId) { return document.getElementById(buttonId); }

    function na_toggle_class(elementId, className, force) {
        var el = document.getElementById(elementId);
        if (!el) return;
        if (typeof force === 'boolean') el.classList.toggle(className, force);
        else                            el.classList.toggle(className);
    }

    function na_set_button_hidden(buttonId, hidden) {
        var btn = na_get_button(buttonId);
        if (!btn) return;
        btn.classList.toggle('na-hidden', !!hidden);
    }

    function na_paint_live_button(isOn) {
        var btn = na_get_button(NA_BTN_LIVE_ID);
        if (!btn) return;
        btn.textContent = isOn ? 'Live Mode ON' : 'Live Mode';
        btn.classList.toggle(NA_BTN_LIVE_ACTIVE_CLS, !!isOn);
    }

    function na_clear_measure_active() {
        na_toggle_class(NA_BTN_MEASURE_ID, NA_BTN_MEASURE_ACTIVE_CLS, false);
    }

    // -----------------------------------------------------------------------
    // REGION | Active tab resolution
    // -----------------------------------------------------------------------

    function na_resolve_active_tab() {
        if (typeof Na_TabRouter !== 'undefined' && typeof Na_TabRouter.na_get_active_tab === 'function') {
            return Na_TabRouter.na_get_active_tab() || NA_TAB_WINDOWS;
        }
        return NA_TAB_WINDOWS;
    }

    function na_publish_active_tab(tabId) {
        if (!tabId || typeof sketchup === 'undefined' || typeof sketchup.na_setActiveTab !== 'function') return;
        try { sketchup.na_setActiveTab(tabId); }
        catch (err) { console.warn('[Na_AppContext] na_setActiveTab push failed:', err); }
    }

    // -----------------------------------------------------------------------
    // REGION | Measure dispatch
    // -----------------------------------------------------------------------

    function na_dispatch_measure_windows() {
        if (typeof sketchup === 'undefined' || typeof sketchup.na_measureOpening !== 'function') {
            console.warn('[Na_AppContext] sketchup.na_measureOpening unavailable');
            if (typeof window.na_showStatus === 'function') {
                window.na_showStatus('warning', 'SketchUp connection not available');
            }
            return;
        }
        na_toggle_class(NA_BTN_MEASURE_ID, NA_BTN_MEASURE_ACTIVE_CLS, true);

        // v1.9.2 - Pass the LIVE window config to Ruby so the measure
        // tool's cill subtraction reflects the latest "Include Cill"
        // toggle / cill_height_mm slider. Without this Ruby falls back
        // to a stale @na_config (or its 50mm defaults) and a freshly
        // opened dialog with cill turned off would still subtract 50mm.
        var configJson = na_resolve_live_window_config_json();
        if (configJson) {
            sketchup.na_measureOpening(configJson);
        } else {
            sketchup.na_measureOpening();                                  // <-- Legacy path (defensive fallback)
        }

        if (typeof window.na_showStatus === 'function') {
            window.na_showStatus('info', 'Click Point A (base corner) in the 3D viewport...');
        }
    }

    // HELPER FUNCTION | Resolve the Live Window Configuration as a JSON String
    // ------------------------------------------------------------
    // Prefers the bridge's `na_buildFullConfig()` (full envelope with
    // metadata) and falls back to a minimal envelope built from
    // `Na_DynamicUI.na_getConfig()` so the Ruby side can always read
    // `windowConfiguration.has_cill` + `cill_height_mm` without
    // re-implementing the merger.
    function na_resolve_live_window_config_json() {
        try {
            if (typeof window.na_buildFullConfig === 'function') {
                return JSON.stringify(window.na_buildFullConfig());
            }
            if (typeof Na_DynamicUI !== 'undefined' && typeof Na_DynamicUI.na_getConfig === 'function') {
                return JSON.stringify({ windowConfiguration: Na_DynamicUI.na_getConfig() });
            }
        } catch (err) {
            console.warn('[Na_AppContext] Failed to serialise live window config:', err);
        }
        return null;
    }

    function na_dispatch_measure_doors() {
        if (typeof sketchup === 'undefined' || typeof sketchup.na_measureDoorOpening !== 'function') {
            console.warn('[Na_AppContext] sketchup.na_measureDoorOpening unavailable');
            if (typeof window.na_showStatus === 'function') {
                window.na_showStatus('warning', 'SketchUp connection not available');
            }
            return;
        }
        na_toggle_class(NA_BTN_MEASURE_ID, NA_BTN_MEASURE_ACTIVE_CLS, true);
        sketchup.na_measureDoorOpening();
        if (typeof window.na_showStatus === 'function') {
            window.na_showStatus('info', 'Click Point A, then Point B, then drag to set wall depth.');
        }
    }

    Na_AppContext.na_dispatch_measure = function () {
        var tab = na_resolve_active_tab();
        if      (tab === NA_TAB_WINDOWS) na_dispatch_measure_windows();
        else if (tab === NA_TAB_DOORS)   na_dispatch_measure_doors();
        else                              console.warn('[Na_AppContext] Measure ignored on tab:', tab);
    };

    // -----------------------------------------------------------------------
    // REGION | Live mode dispatch
    // -----------------------------------------------------------------------

    function na_dispatch_live_toggle_windows() {
        var nextOn = !na_live_state.windows;
        na_live_state.windows = nextOn;
        if (typeof window.na_setLiveModeFlag === 'function') window.na_setLiveModeFlag(nextOn);
        na_paint_live_button(nextOn);
        if (nextOn && typeof window.na_performLiveUpdate === 'function') window.na_performLiveUpdate();
        if (typeof window.na_showStatus === 'function') {
            window.na_showStatus(nextOn ? 'success' : 'info',
                nextOn ? 'Live Mode enabled - select a window to sync changes' : 'Live Mode disabled');
        }
    }

    function na_dispatch_live_toggle_doors() {
        var nextOn = !na_live_state.doors;
        na_live_state.doors = nextOn;
        window.na_doorLiveModeActive = nextOn;
        na_paint_live_button(nextOn);
        if (typeof window.na_showStatus === 'function') {
            window.na_showStatus(nextOn ? 'success' : 'info',
                nextOn ? 'Live Mode enabled - select a door to sync changes' : 'Live Mode disabled');
        }
    }

    Na_AppContext.na_dispatch_live_toggle = function () {
        var tab = na_resolve_active_tab();
        if      (tab === NA_TAB_WINDOWS) na_dispatch_live_toggle_windows();
        else if (tab === NA_TAB_DOORS)   na_dispatch_live_toggle_doors();
        else                              console.warn('[Na_AppContext] Live toggle ignored on tab:', tab);
    };

    // -----------------------------------------------------------------------
    // REGION | Visibility / tab-change hooks
    // -----------------------------------------------------------------------

    // Presets pages get the same chrome treatment as Settings: no Live Mode,
    // no Measure Opening. They additionally flip body.na-presets-mode so the
    // stylesheet can swap the main tab strip for the presets tab strip.
    function na_is_presets_tab(tabId) {
        return (tabId === NA_TAB_PRESETS || tabId === NA_TAB_PRESET_EDITOR);
    }

    function na_sync_presets_mode(tabId) {
        document.body.classList.toggle(NA_PRESETS_MODE_CLS, na_is_presets_tab(tabId));
    }

    Na_AppContext.na_apply_visibility = function () {
        var tab      = na_resolve_active_tab();
        var hideBoth = (tab === NA_TAB_SETTINGS) || na_is_presets_tab(tab);
        na_set_button_hidden(NA_BTN_LIVE_ID,    hideBoth);
        na_set_button_hidden(NA_BTN_MEASURE_ID, hideBoth);
    };

    function na_sync_live_button_to_tab() {
        var tab  = na_resolve_active_tab();
        var isOn = (tab === NA_TAB_WINDOWS) ? na_live_state.windows :
                   (tab === NA_TAB_DOORS)   ? na_live_state.doors   : false;
        na_paint_live_button(isOn);
    }

    Na_AppContext.na_on_tab_changed = function (tabId) {
        na_clear_measure_active();
        Na_AppContext.na_apply_visibility();
        na_sync_presets_mode(tabId || na_resolve_active_tab());
        na_sync_live_button_to_tab();
        na_publish_active_tab(tabId || na_resolve_active_tab());
    };

    // -----------------------------------------------------------------------
    // REGION | Pass-through API
    // -----------------------------------------------------------------------

    Na_AppContext.na_get_active_tab = function () { return na_resolve_active_tab(); };
    Na_AppContext.na_is_active_tab  = function (tabId) { return na_resolve_active_tab() === tabId; };

    Na_AppContext.na_activateTab = function (tabId) {
        if (typeof Na_TabRouter === 'undefined' || typeof Na_TabRouter.na_activateTab !== 'function') {
            console.warn('[Na_AppContext] Na_TabRouter unavailable for tab switch');
            return;
        }
        Na_TabRouter.na_activateTab(tabId);
    };

    // -----------------------------------------------------------------------
    // REGION | Bootstrap
    // -----------------------------------------------------------------------

    Na_AppContext.na_init = function () {
        Na_AppContext.na_apply_visibility();
        na_sync_presets_mode(na_resolve_active_tab());
        na_sync_live_button_to_tab();
        na_clear_measure_active();
        na_publish_active_tab(na_resolve_active_tab());
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na_AppContext.na_init);
    } else {
        Na_AppContext.na_init();
    }

    window.Na_AppContext = Na_AppContext;
})();
