// =============================================================================
// NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - TAB ROUTER
// =============================================================================
//
// FILE       : Na__MeshDecimator__AppCore__TabRouter__.js
// NAMESPACE  : window.Na_TabRouter
// AUTHOR     : Adam Noble / Noble Architecture
// PURPOSE    : Page-swap router for the 3-tab HtmlDialog.
//              Adapted from Na__AssemblyStudio__AppCore__TabRouter__.js.
//
//              Tabs are discovered from data-na-tab-id attributes in the DOM
//              so adding a new tab does not require editing this file.
//
// TAB MODULE CONVENTION
//   Each tab is backed by an optional global matching Na_<TabId>UI:
//     Na_DecimationUI  — exposes na_mount / na_unmount lifecycle hooks
//     Na_AboutUI       — (static content, no JS module required)
//     Na_SettingsUI    — renders settings body on na_mount
//
// PUBLIC API
//   Na_TabRouter.na_activateTab(tabId)
//   Na_TabRouter.na_get_active_tab()
//
// =============================================================================

(function () {
    'use strict';

    var Na_TabRouter         = {};
    var na_active_tab_id     = 'decimation';
    var NA_TAB_BUTTON_PREFIX = 'na-tab-button-';
    var NA_TAB_PANEL_PREFIX  = 'na-tab-';

    // -------------------------------------------------------------------------
    // REGION | Module Resolution
    // -------------------------------------------------------------------------

    function Na__MeshDecimator__TabRouter__ResolveModule(tabId) {
        var globalName = 'Na_' + tabId.charAt(0).toUpperCase() + tabId.slice(1) + 'UI';
        return (typeof window[globalName] !== 'undefined') ? window[globalName] : null;
    }

    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    function Na__MeshDecimator__TabRouter__GetButton(tabId) {
        return document.getElementById(NA_TAB_BUTTON_PREFIX + tabId);
    }

    function Na__MeshDecimator__TabRouter__GetPanel(tabId) {
        return document.getElementById(NA_TAB_PANEL_PREFIX + tabId);
    }

    function Na__MeshDecimator__TabRouter__EachKnownTabId(callback) {
        var buttons = document.querySelectorAll('[data-na-tab-id]');
        for (var i = 0; i < buttons.length; i++) {
            var tabId = buttons[i].getAttribute('data-na-tab-id');
            if (tabId) callback(tabId);
        }
    }

    function Na__MeshDecimator__TabRouter__ApplyActiveClasses(activeTabId) {
        Na__MeshDecimator__TabRouter__EachKnownTabId(function (tabId) {
            var button   = Na__MeshDecimator__TabRouter__GetButton(tabId);
            var panel    = Na__MeshDecimator__TabRouter__GetPanel(tabId);
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

    // -------------------------------------------------------------------------
    // REGION | Lifecycle Dispatch
    // -------------------------------------------------------------------------

    function Na__MeshDecimator__TabRouter__DispatchUnmount(tabId) {
        var mod = Na__MeshDecimator__TabRouter__ResolveModule(tabId);
        if (mod && typeof mod.na_unmount === 'function') {
            try { mod.na_unmount(); }
            catch (err) { console.error('[Na_TabRouter] na_unmount(' + tabId + ') failed:', err); }
        }
    }

    function Na__MeshDecimator__TabRouter__DispatchMount(tabId) {
        var mod = Na__MeshDecimator__TabRouter__ResolveModule(tabId);
        if (!mod) return;
        if (typeof mod.na_mount === 'function') {
            try { mod.na_mount(); }
            catch (err) { console.error('[Na_TabRouter] na_mount(' + tabId + ') failed:', err); }
        }
    }

    // -------------------------------------------------------------------------
    // REGION | Public API
    // -------------------------------------------------------------------------

    Na_TabRouter.na_activateTab = function (tabId) {
        if (!tabId || tabId === na_active_tab_id) return;
        Na__MeshDecimator__TabRouter__DispatchUnmount(na_active_tab_id);
        na_active_tab_id = tabId;
        Na__MeshDecimator__TabRouter__ApplyActiveClasses(tabId);
        Na__MeshDecimator__TabRouter__DispatchMount(tabId);
    };

    Na_TabRouter.na_get_active_tab = function () {
        return na_active_tab_id;
    };

    Na_TabRouter.na_init = function () {
        var activeButton = document.querySelector('.na-tab.na-tab-active');
        if (activeButton) {
            var tabId = activeButton.getAttribute('data-na-tab-id');
            if (tabId) na_active_tab_id = tabId;
        }
        Na__MeshDecimator__TabRouter__ApplyActiveClasses(na_active_tab_id);
        Na__MeshDecimator__TabRouter__DispatchMount(na_active_tab_id);
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na_TabRouter.na_init);
    } else {
        Na_TabRouter.na_init();
    }

    window.Na_TabRouter = Na_TabRouter;

})();
