// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - TAB ROUTER
// =============================================================================
//
// FILE       : Na__AssemblyStudio__AppCore__TabRouter__.js
// NAMESPACE  : Na_TabRouter (browser global; legacy name kept for stability)
// AUTHOR     : Noble Architecture
// PURPOSE    : Page-swap router between the tabs inside the shared HtmlDialog.
//              Tabs are discovered from data-na-tab-id in the DOM and from
//              optional `module.na_get_active_config()` exposures, so adding a
//              new tab does not require editing this file.
//
// REFACTOR NOTES (v2 / EASP)
// - Function-name lookup table generalised: any global matching `Na_<TabId>UI`
//   convention is auto-resolved (Na_WindowsUI, Na_DoorsUI, Na_SettingsUI ...).
// - Resolves either `na_get_active_config` (preferred) or the legacy
//   `na_getConfig` so the WindowSystem MainUiLogic stays backward-compatible
//   without forcing a rename of the existing Na_DynamicUI surface.
// - No window/door specific knowledge anywhere in this file.
// =============================================================================

(function () {
    'use strict';

    var Na_TabRouter           = {};
    var na_active_tab_id       = 'windows';
    var NA_TAB_BUTTON_PREFIX   = 'na-tab-button-';
    var NA_TAB_PANEL_PREFIX    = 'na-tab-';

    // -----------------------------------------------------------------------
    // REGION | Module resolution (no hard-coded tab list)
    // -----------------------------------------------------------------------

    var NA_TAB_TO_GLOBAL = {
        windows       : 'Na_DynamicUI',       // Window system kept the historical IIFE name for compatibility
        doors         : 'Na_DoorUI',
        settings      : 'Na_SettingsUI',
        presets       : 'Na_PresetsUI',       // PresetsLibrary gallery page
        preset_editor : 'Na_PresetEditorUI'   // PresetsLibrary editor page
    };

    function na_resolve_tab_module(tabId) {
        var globalName = NA_TAB_TO_GLOBAL[tabId];
        if (!globalName) {
            globalName = 'Na_' + tabId.charAt(0).toUpperCase() + tabId.slice(1) + 'UI';
        }
        return (typeof window[globalName] !== 'undefined') ? window[globalName] : null;
    }

    function na_resolve_initial_config(tabId) {
        var module = na_resolve_tab_module(tabId);
        if (!module) return null;
        if (typeof module.na_get_active_config === 'function') return module.na_get_active_config();
        if (typeof module.na_getConfig === 'function')          return module.na_getConfig();
        return null;
    }

    // -----------------------------------------------------------------------
    // REGION | DOM helpers
    // -----------------------------------------------------------------------

    function na_get_tab_button(tabId) { return document.getElementById(NA_TAB_BUTTON_PREFIX + tabId); }
    function na_get_tab_panel(tabId)  { return document.getElementById(NA_TAB_PANEL_PREFIX  + tabId); }

    function na_each_known_tab_id(callback) {
        var buttons = document.querySelectorAll('[data-na-tab-id]');
        for (var i = 0; i < buttons.length; i++) {
            var tabId = buttons[i].getAttribute('data-na-tab-id');
            if (tabId) callback(tabId);
        }
    }

    function na_apply_active_classes(activeTabId) {
        na_each_known_tab_id(function (tabId) {
            var button   = na_get_tab_button(tabId);
            var panel    = na_get_tab_panel(tabId);
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

    // -----------------------------------------------------------------------
    // REGION | Lifecycle dispatch
    // -----------------------------------------------------------------------

    function na_notify_app_context(tabId) {
        if (typeof Na_AppContext === 'undefined') return;
        if (typeof Na_AppContext.na_on_tab_changed !== 'function') return;
        try { Na_AppContext.na_on_tab_changed(tabId); }
        catch (err) { console.error('[Na_TabRouter] na_on_tab_changed failed:', err); }
    }

    function na_dispatch_unmount(tabId) {
        var module = na_resolve_tab_module(tabId);
        if (module && typeof module.na_unmount === 'function') {
            try { module.na_unmount(); }
            catch (err) { console.error('[Na_TabRouter] na_unmount(' + tabId + ') failed:', err); }
        }
    }

    function na_dispatch_mount(tabId) {
        var module = na_resolve_tab_module(tabId);
        if (!module) return;
        var initialConfig = na_resolve_initial_config(tabId);
        if (typeof module.na_mount === 'function') {
            try { module.na_mount(initialConfig); }
            catch (err) { console.error('[Na_TabRouter] na_mount(' + tabId + ') failed:', err); }
        } else if (typeof module.na_render === 'function' && initialConfig) {
            try { module.na_render(initialConfig); }
            catch (err) { console.error('[Na_TabRouter] na_render(' + tabId + ') failed:', err); }
        }
    }

    // -----------------------------------------------------------------------
    // REGION | Public API
    // -----------------------------------------------------------------------

    Na_TabRouter.na_activateTab = function (tabId) {
        if (!tabId || tabId === na_active_tab_id) return;
        na_dispatch_unmount(na_active_tab_id);
        na_active_tab_id = tabId;
        na_apply_active_classes(tabId);
        na_dispatch_mount(tabId);
        na_notify_app_context(tabId);
    };

    Na_TabRouter.na_get_active_tab = function () { return na_active_tab_id; };

    Na_TabRouter.na_init = function () {
        var activeButton = document.querySelector('.na-tab.na-tab-active');
        if (activeButton) {
            var tabId = activeButton.getAttribute('data-na-tab-id');
            if (tabId) na_active_tab_id = tabId;
        }
        na_apply_active_classes(na_active_tab_id);
        na_dispatch_mount(na_active_tab_id);
        na_notify_app_context(na_active_tab_id);
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na_TabRouter.na_init);
    } else {
        Na_TabRouter.na_init();
    }

    window.Na_TabRouter = Na_TabRouter;
})();
