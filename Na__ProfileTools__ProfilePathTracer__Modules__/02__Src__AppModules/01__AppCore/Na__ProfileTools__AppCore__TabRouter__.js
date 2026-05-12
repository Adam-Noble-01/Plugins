// =============================================================================
// NA PROFILE TOOLS - APP CORE - TAB ROUTER
// =============================================================================
//
// FILE       : Na__ProfileTools__AppCore__TabRouter__.js
// NAMESPACE  : window.Na_TabRouter
// PURPOSE    : Page-swap router between the three tabs inside the HtmlDialog.
//              Tab modules are resolved by a small lookup table so adding
//              new tabs does not require editing this file.
//
// TABS       : apply-profile | gallery | settings
//
// =============================================================================

(function () {
    'use strict';

    var Na_TabRouter          = {};
    var na_active_tab_id      = 'apply-profile';
    var NA_TAB_BUTTON_PREFIX  = 'na-tab-button-';
    var NA_TAB_PANEL_PREFIX   = 'na-tab-';

    // -------------------------------------------------------------------------
    // REGION | Module Resolution
    // -------------------------------------------------------------------------

    var NA_TAB_TO_GLOBAL = {
        'apply-profile'  : 'Na__ProfileTools__ApplyProfile__Tab',
        'create-profile' : 'Na__ProfileTools__CreateNewProfile__Tab',
        'gallery'        : 'Na__ProfileTools__Gallery__Tab',
        'settings'       : 'Na__ProfileTools__Settings__Tab'
    };

    function na_resolve_tab_module(tabId) {
        var globalName = NA_TAB_TO_GLOBAL[tabId];
        if (!globalName) {
            globalName = 'Na__ProfileTools__' + tabId.charAt(0).toUpperCase() + tabId.slice(1) + '__Tab';
        }
        return (typeof window[globalName] !== 'undefined') ? window[globalName] : null;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

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

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Lifecycle Dispatch
    // -------------------------------------------------------------------------

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
        if (typeof module.na_mount === 'function') {
            try { module.na_mount(); }
            catch (err) { console.error('[Na_TabRouter] na_mount(' + tabId + ') failed:', err); }
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public API
    // -------------------------------------------------------------------------

    Na_TabRouter.na_activateTab = function (tabId) {
        if (!tabId || tabId === na_active_tab_id) return;
        na_dispatch_unmount(na_active_tab_id);
        na_active_tab_id = tabId;
        na_apply_active_classes(tabId);
        na_dispatch_mount(tabId);
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
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na_TabRouter.na_init);
    } else {
        Na_TabRouter.na_init();
    }

    window.Na_TabRouter = Na_TabRouter;

    // endregion ----------------------------------------------------------------
})();
