// =============================================================================
// NA COMPONENT EDITOR TOOLS - TAB ROUTER
// =============================================================================
//
// FILE       : Na__ComponentEditorTools__TabRouter__.js
// PURPOSE    : Manage tab navigation - activate panels and sync button states
// CREATED    : 2026
//
// =============================================================================

(function () {
    'use strict';

// -----------------------------------------------------------------------------
// REGION | Module State
// -----------------------------------------------------------------------------

    var Na__ComponentEditorTools__TabRouter = {};
    var na_active_tab = 'gallery';

    var NA_AUDITING_TABS = { overview: true, attributes: true, thumbnail: true, settings: true };

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DOM Helpers
// -----------------------------------------------------------------------------

    function na_tab_buttons() {
        return Array.prototype.slice.call(document.querySelectorAll('.naComponentEditor__TabButton'));
    }

    function na_tab_panels() {
        return Array.prototype.slice.call(document.querySelectorAll('.naComponentEditor__TabPanel'));
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Tab Activation
// -----------------------------------------------------------------------------

    function na_apply_tab_classes(active_tab_id) {
        na_tab_buttons().forEach(function (button_element) {
            var tab_id = button_element.getAttribute('data-tab-id');
            var is_active = tab_id === active_tab_id;
            button_element.classList.toggle('naComponentEditor__TabButton--active', is_active);
        });

        na_tab_panels().forEach(function (panel_element) {
            var tab_id = panel_element.getAttribute('data-tab-id');
            var is_active = tab_id === active_tab_id;
            panel_element.classList.toggle('naComponentEditor__TabPanel--active', is_active);
        });

        var nav = document.querySelector('.naComponentEditor__TabBar');
        if (nav) {
            nav.classList.toggle('naComponentEditor__TabBar--galleryActive', active_tab_id === 'gallery');
            nav.classList.toggle('naComponentEditor__TabBar--indexActive',   active_tab_id === 'index');
        }

        var is_auditing = !!NA_AUDITING_TABS[active_tab_id];
        var is_index    = active_tab_id === 'index';

        var header_actions = document.querySelector('.naComponentEditor__HeaderActions');
        if (header_actions) {
            header_actions.style.display = (is_auditing || is_index) ? '' : 'none';
        }

        var auditing_actions = document.querySelector('.naComponentEditor__AuditingActions');
        if (auditing_actions) {
            auditing_actions.style.display = is_auditing ? 'flex' : 'none';
        }

        var index_actions = document.querySelector('.naComponentEditor__IndexActions');
        if (index_actions) {
            index_actions.style.display = is_index ? 'flex' : 'none';
        }
    }

    function na_bind_tab_buttons() {
        na_tab_buttons().forEach(function (button_element) {
            button_element.addEventListener('click', function () {
                var tab_id = button_element.getAttribute('data-tab-id');
                Na__ComponentEditorTools__TabRouter.Na__ComponentEditorTools__ActivateTab(tab_id, true);
            });
        });
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    var NA_TAB_ACTIVATE_HANDLERS = {
        gallery : function () {
            if (window.Na__ComponentEditorTools__GalleryTab &&
                typeof window.Na__ComponentEditorTools__GalleryTab.Na__ComponentEditorTools__OnTabActivate === 'function') {
                window.Na__ComponentEditorTools__GalleryTab.Na__ComponentEditorTools__OnTabActivate();
            }
        },
        index   : function () {
            if (window.Na__ComponentEditorTools__IndexTab &&
                typeof window.Na__ComponentEditorTools__IndexTab.Na__ComponentEditorTools__OnTabActivate === 'function') {
                window.Na__ComponentEditorTools__IndexTab.Na__ComponentEditorTools__OnTabActivate();
            }
        }
    };

    Na__ComponentEditorTools__TabRouter.Na__ComponentEditorTools__ActivateTab = function (tab_id, notify_ruby) {
        var normalized_tab_id = String(tab_id || '').trim();
        if (!normalized_tab_id) return;

        na_active_tab = normalized_tab_id;
        na_apply_tab_classes(normalized_tab_id);

        if (NA_TAB_ACTIVATE_HANDLERS[normalized_tab_id]) {
            NA_TAB_ACTIVATE_HANDLERS[normalized_tab_id]();
        }

        if (notify_ruby !== false && typeof window.Na__ComponentEditorTools__NotifyActiveTab === 'function') {
            window.Na__ComponentEditorTools__NotifyActiveTab(normalized_tab_id);
        }
    };

    Na__ComponentEditorTools__TabRouter.Na__ComponentEditorTools__CurrentTab = function () {
        return na_active_tab;
    };

    Na__ComponentEditorTools__TabRouter.Na__ComponentEditorTools__Init = function () {
        na_bind_tab_buttons();
        na_apply_tab_classes(na_active_tab);
    };

    window.Na__ComponentEditorTools__TabRouter = Na__ComponentEditorTools__TabRouter;

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Init
// -----------------------------------------------------------------------------

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na__ComponentEditorTools__TabRouter.Na__ComponentEditorTools__Init);
    } else {
        Na__ComponentEditorTools__TabRouter.Na__ComponentEditorTools__Init();
    }

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
