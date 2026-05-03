// =============================================================================
// NA WINDOW CONFIGURATOR TOOL - APP CONTEXT (UNIFIED STATE MANAGER)
// =============================================================================
//
// FILE       : Na__WindowConfiguratorTool__AppContext__.js
// NAMESPACE  : Na_AppContext (browser global)
// AUTHOR     : Noble Architecture
// PURPOSE    : Single source of truth for which tab is active and where
//              the global header buttons (Measure Opening / Live Mode)
//              should dispatch their actions.
// CREATED    : 01-May-2026
//
// DESCRIPTION:
// - Sits on top of Na_TabRouter and adds three concerns the router does
//   not own:
//     1. Dispatching the global Measure Opening button to the correct
//        per-tab Ruby callback (na_measureOpening for the Windows tab,
//        na_measureDoorOpening for the Doors tab).
//     2. Owning the per-tab Live Mode boolean and dispatching the
//        global Live Mode toggle to the correct per-tab pipeline.
//     3. Showing / hiding the global header buttons depending on the
//        active tab (the Settings tab has neither button).
// - Also pushes the active tab id back to the Ruby DialogManager via
//   sketchup.na_setActiveTab so the SelectionObserver can pre-decide
//   routing without round-tripping through execute_script.
// - Exposes Na_AppContext.na_is_active_tab(tabId) so other JS modules
//   stop asking Na_TabRouter directly. Single read site for "what
//   tab is visible right now?".
//
// PUBLIC API:
//   Na_AppContext.na_init()                  Bootstrap once on dialog load.
//   Na_AppContext.na_get_active_tab()        Pass-through to Na_TabRouter.
//   Na_AppContext.na_is_active_tab(tabId)    Convenience equality check.
//   Na_AppContext.na_activateTab(tabId)      Programmatic tab switch (Ruby uses this).
//   Na_AppContext.na_dispatch_measure()      Wired to global "Measure Opening" onclick.
//   Na_AppContext.na_dispatch_live_toggle()  Wired to global "Live Mode" onclick.
//   Na_AppContext.na_on_tab_changed(tabId)   Called by Na_TabRouter after every switch.
//   Na_AppContext.na_apply_visibility()      Re-apply button show/hide for the active tab.
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Module State
// -----------------------------------------------------------------------------

    var Na_AppContext              = {};                                       // <-- Public namespace

    var NA_BTN_LIVE_ID             = 'na-btn-live';                            // <-- Global header live-mode button id
    var NA_BTN_MEASURE_ID          = 'na-btn-measure';                         // <-- Global header measure button id
    var NA_BTN_MEASURE_ACTIVE_CLS  = 'na-btn-measure-active';                  // <-- Unified active-class for measure button
    var NA_BTN_LIVE_ACTIVE_CLS     = 'na-btn-live-active';                     // <-- Existing active-class for live-mode button

    var NA_TAB_WINDOWS             = 'windows';                                // <-- Tab id constants
    var NA_TAB_DOORS               = 'doors';
    var NA_TAB_SETTINGS            = 'settings';

    var na_live_state = {                                                      // <-- Per-tab Live Mode state
        windows : false,
        doors   : false
    };

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Internal Helpers - DOM
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Resolve a Header Button by ID
    // ------------------------------------------------------------
    function na_get_button(buttonId) {
        return document.getElementById(buttonId);
    }
    // ---------------------------------------------------------------


    // HELPER FUNCTION | Toggle a Class on an Element by ID
    // ------------------------------------------------------------
    function na_toggle_class(elementId, className, force) {
        var el = document.getElementById(elementId);
        if (!el) return;
        if (typeof force === 'boolean') {
            el.classList.toggle(className, force);
        } else {
            el.classList.toggle(className);
        }
    }
    // ---------------------------------------------------------------


    // HELPER FUNCTION | Set a Button's Hidden State
    // ------------------------------------------------------------
    function na_set_button_hidden(buttonId, hidden) {
        var btn = na_get_button(buttonId);
        if (!btn) return;
        btn.classList.toggle('na-hidden', !!hidden);
    }
    // ---------------------------------------------------------------


    // HELPER FUNCTION | Set the Live Button Label and Active Class
    // ------------------------------------------------------------
    function na_paint_live_button(isOn) {
        var btn = na_get_button(NA_BTN_LIVE_ID);
        if (!btn) return;
        btn.textContent = isOn ? 'Live Mode ON' : 'Live Mode';
        btn.classList.toggle(NA_BTN_LIVE_ACTIVE_CLS, !!isOn);
    }
    // ---------------------------------------------------------------


    // HELPER FUNCTION | Clear the Measure Button Active Visual State
    // ------------------------------------------------------------
    function na_clear_measure_active() {
        na_toggle_class(NA_BTN_MEASURE_ID, NA_BTN_MEASURE_ACTIVE_CLS, false);
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Internal Helpers - Active-Tab Resolution
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Resolve the Currently Active Tab ID
    // ------------------------------------------------------------
    // Single read site for "what tab is visible right now?". Falls
    // back to NA_TAB_WINDOWS so any defensive caller never gets undef.
    function na_resolve_active_tab() {
        if (typeof Na_TabRouter !== 'undefined' &&
            typeof Na_TabRouter.na_get_active_tab === 'function') {
            return Na_TabRouter.na_get_active_tab() || NA_TAB_WINDOWS;
        }
        return NA_TAB_WINDOWS;
    }
    // ---------------------------------------------------------------


    // HELPER FUNCTION | Push the Active Tab ID Back to Ruby DialogManager
    // ------------------------------------------------------------
    // The Ruby SelectionObserver pre-decides whether to load a
    // window or a door before signalling Na_AppContext to switch tabs.
    // It needs a synchronous way to know which tab the user is
    // currently looking at; UI::HtmlDialog#execute_script does not
    // return a value, so we mirror the pattern used by the measure
    // origin and push the id whenever it changes.
    function na_publish_active_tab(tabId) {
        if (!tabId) return;
        if (typeof sketchup === 'undefined') return;
        if (typeof sketchup.na_setActiveTab !== 'function') return;
        try {
            sketchup.na_setActiveTab(tabId);
        } catch (err) {
            console.warn('[Na_AppContext] na_setActiveTab push failed:', err);
        }
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Dispatch - Measure Opening
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Dispatch Measure for the Windows Tab (Two-Point)
    // ------------------------------------------------------------
    function na_dispatch_measure_windows() {
        if (typeof sketchup === 'undefined' || typeof sketchup.na_measureOpening !== 'function') {
            console.warn('[Na_AppContext] sketchup.na_measureOpening unavailable');
            if (typeof window.na_showStatus === 'function') {
                window.na_showStatus('warning', 'SketchUp connection not available');
            }
            return;
        }

        na_toggle_class(NA_BTN_MEASURE_ID, NA_BTN_MEASURE_ACTIVE_CLS, true);
        sketchup.na_measureOpening();
        if (typeof window.na_showStatus === 'function') {
            window.na_showStatus('info', 'Click Point A (base corner) in the 3D viewport...');
        }
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Dispatch Measure for the Doors Tab (Three-Point)
    // ------------------------------------------------------------
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
    // ---------------------------------------------------------------


    // FUNCTION | Public Dispatcher - Global Measure Opening Button
    // ------------------------------------------------------------
    Na_AppContext.na_dispatch_measure = function () {
        var tab = na_resolve_active_tab();
        if (tab === NA_TAB_WINDOWS) {
            na_dispatch_measure_windows();
        } else if (tab === NA_TAB_DOORS) {
            na_dispatch_measure_doors();
        } else {
            console.warn('[Na_AppContext] Measure dispatch ignored on tab:', tab);
        }
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Dispatch - Live Mode Toggle
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Toggle Live Mode for the Windows Tab
    // ------------------------------------------------------------
    function na_dispatch_live_toggle_windows() {
        var nextOn = !na_live_state.windows;
        na_live_state.windows = nextOn;

        if (typeof window.na_setLiveModeFlag === 'function') {
            window.na_setLiveModeFlag(nextOn);                                 // <-- Sets the bridge module's na_liveModeEnabled boolean
        }

        na_paint_live_button(nextOn);

        if (nextOn && typeof window.na_performLiveUpdate === 'function') {
            window.na_performLiveUpdate();                                     // <-- Sync the currently selected window once
        }

        if (typeof window.na_showStatus === 'function') {
            window.na_showStatus(
                nextOn ? 'success' : 'info',
                nextOn ? 'Live Mode enabled - select a window to sync changes' : 'Live Mode disabled'
            );
        }
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Toggle Live Mode for the Doors Tab
    // ------------------------------------------------------------
    function na_dispatch_live_toggle_doors() {
        var nextOn = !na_live_state.doors;
        na_live_state.doors = nextOn;
        window.na_doorLiveModeActive = nextOn;                                 // <-- Door bridge reads this flag in na_doorLiveUpdateRequested

        na_paint_live_button(nextOn);

        if (typeof window.na_showStatus === 'function') {
            window.na_showStatus(
                nextOn ? 'success' : 'info',
                nextOn ? 'Live Mode enabled - select a door to sync changes' : 'Live Mode disabled'
            );
        }
    }
    // ---------------------------------------------------------------


    // FUNCTION | Public Dispatcher - Global Live Mode Button
    // ------------------------------------------------------------
    Na_AppContext.na_dispatch_live_toggle = function () {
        var tab = na_resolve_active_tab();
        if (tab === NA_TAB_WINDOWS) {
            na_dispatch_live_toggle_windows();
        } else if (tab === NA_TAB_DOORS) {
            na_dispatch_live_toggle_doors();
        } else {
            console.warn('[Na_AppContext] Live toggle dispatch ignored on tab:', tab);
        }
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Visibility & Tab-Change Hooks
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Hide / Show the Global Header Buttons by Active Tab
    // ------------------------------------------------------------
    // Settings hides both buttons. Windows + Doors show both. Future
    // tabs that opt out can append themselves to the deny-list here.
    Na_AppContext.na_apply_visibility = function () {
        var tab           = na_resolve_active_tab();
        var hideBoth      = (tab === NA_TAB_SETTINGS);
        na_set_button_hidden(NA_BTN_LIVE_ID,    hideBoth);
        na_set_button_hidden(NA_BTN_MEASURE_ID, hideBoth);
    };
    // ---------------------------------------------------------------


    // SUB FUNCTION | Sync the Live Button Visual to the Active Tab's Live State
    // ------------------------------------------------------------
    function na_sync_live_button_to_tab() {
        var tab    = na_resolve_active_tab();
        var isOn   = (tab === NA_TAB_WINDOWS) ? na_live_state.windows :
                     (tab === NA_TAB_DOORS)   ? na_live_state.doors   : false;
        na_paint_live_button(isOn);
    }
    // ---------------------------------------------------------------


    // FUNCTION | Tab-Change Notification (Called by Na_TabRouter)
    // ------------------------------------------------------------
    // Resets any in-flight measurement visual, repaints the Live
    // button to reflect the new tab's stored Live state, and pushes
    // the new tab id to Ruby. Idempotent.
    Na_AppContext.na_on_tab_changed = function (tabId) {
        na_clear_measure_active();
        Na_AppContext.na_apply_visibility();
        na_sync_live_button_to_tab();
        na_publish_active_tab(tabId || na_resolve_active_tab());
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public Pass-Through API
// -----------------------------------------------------------------------------

    // FUNCTION | Get the Active Tab ID
    // ------------------------------------------------------------
    Na_AppContext.na_get_active_tab = function () {
        return na_resolve_active_tab();
    };
    // ---------------------------------------------------------------


    // FUNCTION | Equality Check Against the Active Tab ID
    // ------------------------------------------------------------
    Na_AppContext.na_is_active_tab = function (tabId) {
        return na_resolve_active_tab() === tabId;
    };
    // ---------------------------------------------------------------


    // FUNCTION | Programmatically Switch Tabs (Ruby Uses This)
    // ------------------------------------------------------------
    // Forwarded to Na_TabRouter. Ruby calls this via execute_script
    // when the SelectionObserver detects the user clicked a component
    // on a tab they are not currently viewing.
    Na_AppContext.na_activateTab = function (tabId) {
        if (typeof Na_TabRouter === 'undefined' ||
            typeof Na_TabRouter.na_activateTab !== 'function') {
            console.warn('[Na_AppContext] Na_TabRouter unavailable for tab switch');
            return;
        }
        Na_TabRouter.na_activateTab(tabId);
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Bootstrap
// -----------------------------------------------------------------------------

    // FUNCTION | Initialize Na_AppContext on Dialog Load
    // ------------------------------------------------------------
    // Runs after Na_TabRouter so the controller can read the
    // initial tab id. Idempotent - safe to call again after Reload
    // Scripts.
    Na_AppContext.na_init = function () {
        Na_AppContext.na_apply_visibility();
        na_sync_live_button_to_tab();
        na_clear_measure_active();
        na_publish_active_tab(na_resolve_active_tab());
    };
    // ---------------------------------------------------------------


    // Auto-bootstrap once the DOM is ready. Na_TabRouter installs its
    // own DOMContentLoaded handler that runs first because its script
    // tag appears before this one in UiLayout.html.
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na_AppContext.na_init);
    } else {
        Na_AppContext.na_init();
    }

    window.Na_AppContext = Na_AppContext;                                      // <-- Expose globally for HTML onclick handlers

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
