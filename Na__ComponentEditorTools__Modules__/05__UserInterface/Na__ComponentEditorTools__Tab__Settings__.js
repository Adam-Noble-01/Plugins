// =============================================================================
// NA COMPONENT EDITOR TOOLS - TAB | SETTINGS
// =============================================================================
//
// FILE       : Na__ComponentEditorTools__Tab__Settings__.js
// PURPOSE    : Render and manage the Settings tab event binding
// CREATED    : 2026
//
// =============================================================================

(function () {
    'use strict';

// -----------------------------------------------------------------------------
// REGION | Module State
// -----------------------------------------------------------------------------

    var Na__ComponentEditorTools__SettingsTab = {};
    var na_events_bound = false;

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Event Binding
// -----------------------------------------------------------------------------

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

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    Na__ComponentEditorTools__SettingsTab.Na__ComponentEditorTools__Render = function (_payload) {
        na_bind_events_once();
    };

    window.Na__ComponentEditorTools__SettingsTab = Na__ComponentEditorTools__SettingsTab;

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
