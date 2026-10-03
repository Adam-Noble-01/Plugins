// =============================================================================
// NA POINT CLOUD VIEWER - APP CORE - TAB ROUTER
// =============================================================================
//
// FILE       : Na__PointCloudViewer__AppCore__TabRouter__.js
// NAMESPACE  : window.Na_TabRouter
// PURPOSE    : Page-swap between tab panels (same contract as the other Noble
//              plugins). Remembers the active tab in the user config so the
//              dialog reopens where it was left, including after a reload.
//              A remembered tab that no longer exists falls back to View.
//
// TABS       : view (default) | clipping | settings
//
// =============================================================================

(function () {
    'use strict';

    var Na_TabRouter         = {};
    var na_active_tab_id     = 'view';
    var na_restored_from_state = false;
    var NA_TAB_BUTTON_PREFIX = 'na-tab-button-';
    var NA_TAB_PANEL_PREFIX  = 'na-tab-';

    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    function na_known_tab_ids() {
        var buttons = document.querySelectorAll('.na-tab[data-na-tab-id]');
        return Array.prototype.map.call(buttons, function (button) { return button.getAttribute('data-na-tab-id'); });
    }

    function na_apply_active_classes(activeTabId) {
        na_known_tab_ids().forEach(function (tabId) {
            var isActive = tabId === activeTabId;
            var button   = document.getElementById(NA_TAB_BUTTON_PREFIX + tabId);
            var panel    = document.getElementById(NA_TAB_PANEL_PREFIX + tabId);
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
    // REGION | Public API
    // -------------------------------------------------------------------------

    Na_TabRouter.na_activateTab = function (tabId, options) {
        if (!tabId || na_known_tab_ids().indexOf(tabId) === -1) return;
        na_active_tab_id = tabId;
        na_apply_active_classes(tabId);
        if (!(options && options.silent)) {
            window.Na__PointCloudViewer__Bridge.na_call('ui_remember_tab', { tabId: tabId });
        }
    };

    Na_TabRouter.na_get_active_tab = function () { return na_active_tab_id; };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Init
    // -------------------------------------------------------------------------

    window.Na__PointCloudViewer__Shell.na_on('state', function (state) {
        if (na_restored_from_state || !state || !state.ui) return;
        na_restored_from_state = true;
        Na_TabRouter.na_activateTab(state.ui.activeTab || 'view', { silent: true });
    });

    na_apply_active_classes(na_active_tab_id);
    window.Na_TabRouter = Na_TabRouter;
})();
