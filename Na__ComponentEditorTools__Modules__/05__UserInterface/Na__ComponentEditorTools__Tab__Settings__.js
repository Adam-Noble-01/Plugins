(function () {
    'use strict';

    var Na__ComponentEditorTools__SettingsTab = {};
    var na_events_bound = false;

    function na_bind_events_once() {
        if (na_events_bound) return;
        na_events_bound = true;

        var reload_button = document.getElementById('na-component-btn-settings-reload');
        if (reload_button) {
            reload_button.addEventListener('click', function () {
                window.Na__ComponentEditorTools__ReloadPlugin();
            });
        }
    }

    Na__ComponentEditorTools__SettingsTab.Na__ComponentEditorTools__Render = function (_payload) {
        na_bind_events_once();
    };

    window.Na__ComponentEditorTools__SettingsTab = Na__ComponentEditorTools__SettingsTab;
})();
