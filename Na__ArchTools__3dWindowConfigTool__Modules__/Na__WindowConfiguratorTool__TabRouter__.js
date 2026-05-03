// =============================================================================
// NA WINDOW CONFIGURATOR TOOL - TAB ROUTER
// =============================================================================
//
// FILE       : Na__WindowConfiguratorTool__TabRouter__.js
// NAMESPACE  : Na_TabRouter (browser global)
// AUTHOR     : Noble Architecture
// PURPOSE    : Page-swap router between the Windows tab and the
//              Interior Doors tab inside the shared HtmlDialog.
// CREATED    : 01-May-2026
//
// DESCRIPTION:
// - Tracks which tab is currently active.
// - On tab switch the router toggles the .na-tab-active and .na-hidden
//   classes on both the tab buttons and the corresponding tab panels.
// - Optional lifecycle hooks - if the active tab module exposes
//     na_unmount() it is called as the user leaves the tab,
//     na_mount(initialConfig) it is called as the user enters the tab.
//   Tabs are free to opt out of either hook.
// - Public API:
//     Na_TabRouter.na_init()                              -> Activate the default tab on dialog load.
//     Na_TabRouter.na_activateTab(tabId)                  -> Imperatively switch to a tab.
//     Na_TabRouter.na_get_active_tab()                    -> Return currently active tab id.
//
// NAMING CONVENTION:
// - Public symbols use Na_ / na_ prefix (browser-global compatible).
//
// =============================================================================


// -----------------------------------------------------------------------------
// REGION | Na_TabRouter Module Definition
// -----------------------------------------------------------------------------

(function () {
    'use strict';

    // MODULE VARIABLES | Tab Router State
    // ------------------------------------------------------------
    var Na_TabRouter = {};                                                    // <-- Public namespace
    var na_active_tab_id        = 'windows';                                  // <-- Default active tab
    var NA_TAB_BUTTON_PREFIX    = 'na-tab-button-';                           // <-- Element id prefix for tab buttons
    var NA_TAB_PANEL_PREFIX     = 'na-tab-';                                  // <-- Element id prefix for tab panels
    // ---------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Internal Helpers
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Resolve the Tab Module for a Given Tab ID
    // ------------------------------------------------------------
    // Returns the namespace exposed by each tab's UI module so the
    // router can dispatch lifecycle hooks. Returns null if the
    // module hasn't loaded (which is fine for tabs that opt out).
    function na_resolve_tab_module(tabId) {
        if (tabId === 'windows') {
            return (typeof Na_DynamicUI !== 'undefined') ? Na_DynamicUI : null;
        }
        if (tabId === 'doors') {
            return (typeof Na_DoorUI !== 'undefined') ? Na_DoorUI : null;
        }
        if (tabId === 'settings') {
            return (typeof Na_SettingsUI !== 'undefined') ? Na_SettingsUI : null;
        }
        return null;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Resolve the Default Initial Config for a Tab
    // ------------------------------------------------------------
    // Each tab module is expected to publish a default config under
    // its own namespace. The router supplies it to na_mount().
    function na_resolve_initial_config(tabId) {
        if (tabId === 'windows') {
            return (typeof Na_DynamicUI !== 'undefined' && Na_DynamicUI.na_get_active_config)
                ? Na_DynamicUI.na_get_active_config()
                : null;
        }
        if (tabId === 'doors') {
            return (typeof Na_DoorUI !== 'undefined' && Na_DoorUI.na_get_active_config)
                ? Na_DoorUI.na_get_active_config()
                : null;
        }
        if (tabId === 'settings') {
            return (typeof Na_SettingsUI !== 'undefined' && Na_SettingsUI.na_get_active_config)
                ? Na_SettingsUI.na_get_active_config()
                : null;
        }
        return null;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Get the Tab Button Element for a Given Tab ID
    // ------------------------------------------------------------
    function na_get_tab_button(tabId) {
        return document.getElementById(NA_TAB_BUTTON_PREFIX + tabId);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Get the Tab Panel Element for a Given Tab ID
    // ------------------------------------------------------------
    function na_get_tab_panel(tabId) {
        return document.getElementById(NA_TAB_PANEL_PREFIX + tabId);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Iterate Every Known Tab ID Discovered in the DOM
    // ------------------------------------------------------------
    // Reads data-na-tab-id from all .na-tab buttons rather than
    // hardcoding ids - this lets future tabs (e.g. a Skylights tab)
    // join without router edits.
    function na_each_known_tab_id(callback) {
        var buttons = document.querySelectorAll('[data-na-tab-id]');
        for (var i = 0; i < buttons.length; i++) {
            var tabId = buttons[i].getAttribute('data-na-tab-id');
            if (tabId) callback(tabId);
        }
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DOM Toggling
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Show / Hide Tab Buttons and Panels
    // ------------------------------------------------------------
    function na_apply_active_classes(activeTabId) {
        na_each_known_tab_id(function (tabId) {
            var button = na_get_tab_button(tabId);
            var panel  = na_get_tab_panel(tabId);
            var isActive = (tabId === activeTabId);

            if (button) {
                button.classList.toggle('na-tab-active', isActive);
                button.setAttribute('aria-selected', isActive ? 'true' : 'false');
            }
            if (panel) {
                panel.classList.toggle('na-tab-active', isActive);
                panel.classList.toggle('na-hidden', !isActive);
            }
        });
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Lifecycle Dispatch
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Notify Na_AppContext After Every Tab Change
    // ------------------------------------------------------------
    // The router owns DOM toggling and lifecycle hooks; the context
    // owns header-button visibility, dispatcher state, and pushing
    // the active tab back to Ruby. Keeping the router single-purpose
    // means the context is the only place to look for those concerns.
    function na_notify_app_context(tabId) {
        if (typeof Na_AppContext === 'undefined') return;
        if (typeof Na_AppContext.na_on_tab_changed !== 'function') return;
        try {
            Na_AppContext.na_on_tab_changed(tabId);
        } catch (err) {
            console.error('[Na_TabRouter] Na_AppContext.na_on_tab_changed failed:', err);
        }
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Fire na_unmount() on a Tab Module if Present
    // ------------------------------------------------------------
    function na_dispatch_unmount(tabId) {
        var module = na_resolve_tab_module(tabId);
        if (module && typeof module.na_unmount === 'function') {
            try {
                module.na_unmount();
            } catch (err) {
                console.error('[Na_TabRouter] na_unmount(' + tabId + ') failed:', err);
            }
        }
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Fire na_mount() on a Tab Module if Present
    // ------------------------------------------------------------
    function na_dispatch_mount(tabId) {
        var module = na_resolve_tab_module(tabId);
        if (!module) return;

        var initialConfig = na_resolve_initial_config(tabId);
        if (typeof module.na_mount === 'function') {
            try {
                module.na_mount(initialConfig);
            } catch (err) {
                console.error('[Na_TabRouter] na_mount(' + tabId + ') failed:', err);
            }
        } else if (typeof module.na_render === 'function' && initialConfig) {
            try {
                module.na_render(initialConfig);
            } catch (err) {
                console.error('[Na_TabRouter] fallback na_render(' + tabId + ') failed:', err);
            }
        }
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    // FUNCTION | Activate a Tab by ID (Performs Full Page-Swap)
    // ------------------------------------------------------------
    Na_TabRouter.na_activateTab = function (tabId) {
        if (!tabId)                       return;
        if (tabId === na_active_tab_id)   return;

        na_dispatch_unmount(na_active_tab_id);
        na_active_tab_id = tabId;
        na_apply_active_classes(tabId);
        na_dispatch_mount(tabId);
        na_notify_app_context(tabId);                                          // <-- v0.11.6 Header buttons + Ruby active-tab cache
    };
    // ---------------------------------------------------------------

    // FUNCTION | Return the Currently Active Tab ID
    // ------------------------------------------------------------
    Na_TabRouter.na_get_active_tab = function () {
        return na_active_tab_id;
    };
    // ---------------------------------------------------------------

    // FUNCTION | Initialise the Tab Router on Dialog Load
    // ------------------------------------------------------------
    // Reads the tab marked .na-tab-active in the DOM, then mounts it
    // so each tab module gets its first na_mount() call exactly once.
    Na_TabRouter.na_init = function () {
        var activeButton = document.querySelector('.na-tab.na-tab-active');
        if (activeButton) {
            var tabId = activeButton.getAttribute('data-na-tab-id');
            if (tabId) na_active_tab_id = tabId;
        }
        na_apply_active_classes(na_active_tab_id);
        na_dispatch_mount(na_active_tab_id);
        na_notify_app_context(na_active_tab_id);                               // <-- v0.11.6 Initial sync after dialog load
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Bootstrap
// -----------------------------------------------------------------------------

    // FUNCTION | Auto-Bootstrap on DOMContentLoaded
    // ------------------------------------------------------------
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na_TabRouter.na_init);
    } else {
        Na_TabRouter.na_init();
    }
    // ---------------------------------------------------------------

    window.Na_TabRouter = Na_TabRouter;                                       // <-- Expose globally for HTML onclick handlers

})();

// =============================================================================
// END OF FILE
// =============================================================================
