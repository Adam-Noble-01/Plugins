(function () {
    'use strict';

    var Na__ComponentEditorTools__TabRouter = {};
    var na_active_tab = 'overview';

    function na_tab_buttons() {
        return Array.prototype.slice.call(document.querySelectorAll('.naComponentEditor__TabButton'));
    }

    function na_tab_panels() {
        return Array.prototype.slice.call(document.querySelectorAll('.naComponentEditor__TabPanel'));
    }

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
    }

    function na_bind_tab_buttons() {
        na_tab_buttons().forEach(function (button_element) {
            button_element.addEventListener('click', function () {
                var tab_id = button_element.getAttribute('data-tab-id');
                Na__ComponentEditorTools__TabRouter.Na__ComponentEditorTools__ActivateTab(tab_id, true);
            });
        });
    }

    Na__ComponentEditorTools__TabRouter.Na__ComponentEditorTools__ActivateTab = function (tab_id, notify_ruby) {
        var normalized_tab_id = String(tab_id || '').trim();
        if (!normalized_tab_id) return;

        na_active_tab = normalized_tab_id;
        na_apply_tab_classes(normalized_tab_id);

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

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na__ComponentEditorTools__TabRouter.Na__ComponentEditorTools__Init);
    } else {
        Na__ComponentEditorTools__TabRouter.Na__ComponentEditorTools__Init();
    }
})();
