// =============================================================================
// NA WINDOW CONFIGURATOR TOOL - SETTINGS TAB UI EVENT TO RUBY API BRIDGE
// =============================================================================
//
// FILE       : Na__WindowConfiguratorTool__SettingsTab__UiEventToRubyApiBridge__.js
// AUTHOR     : Noble Architecture
// PURPOSE    : Settings-tab onclick handlers. Each handler delegates to the
//              shared sketchup.* action callbacks registered by the Ruby
//              DialogManager.
// CREATED    : 01-May-2026
//
// DESCRIPTION:
// - Exposes three top-level functions invoked from inline onclick handlers
//   built by Na__WindowConfiguratorTool__SettingsTab__UiLogic__.js:
//     * na_settingsReloadScripts() -> sketchup.na_reloadScripts
//     * na_settingsExport2D()      -> sketchup.na_settingsExport2D
//     * na_settingsExport3D()      -> sketchup.na_settingsExport3D
// - Provides a small status helper so the user gets feedback inside the
//   shared status bar (na_showStatus) when the click is dispatched. The
//   Ruby action callbacks themselves print full results to the SketchUp
//   Ruby Console.
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Internal Helpers
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Send a Status Message Through the Shared Status Bar
    // ------------------------------------------------------------
    function na_settings_status(type, message) {
        if (typeof window.na_showStatus === 'function') {
            window.na_showStatus(type, message);
        } else {
            console.log('[NA_SETTINGS] ' + type + ' : ' + message);
        }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Verify SketchUp Bridge is Available
    // ------------------------------------------------------------
    function na_settings_sketchup_available() {
        return (typeof window.sketchup !== 'undefined') && window.sketchup;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public onclick Handlers
// -----------------------------------------------------------------------------

    // FUNCTION | Settings - Trigger the Reload-Scripts Developer Action
    // ------------------------------------------------------------
    // Delegates to the existing Ruby na_reloadScripts callback. The Ruby
    // side closes the dialog as part of the reload flow.
    window.na_settingsReloadScripts = function () {
        if (!na_settings_sketchup_available()) {
            na_settings_status('warning', 'SketchUp connection not available - reload skipped.');
            return;
        }
        na_settings_status('info', 'Reloading plugin scripts...');
        window.sketchup.na_reloadScripts();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Settings - Run the 2D CAD Object JSON Exporter
    // ------------------------------------------------------------
    // Delegates to Ruby na_settingsExport2D, which calls
    // Na__DevTools::Na__JsonExporter2D.na_run_export.
    window.na_settingsExport2D = function () {
        if (!na_settings_sketchup_available()) {
            na_settings_status('warning', 'SketchUp connection not available - export skipped.');
            return;
        }
        na_settings_status('info', 'Running 2D exporter - check the Ruby Console for output.');
        window.sketchup.na_settingsExport2D();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Settings - Run the Unified 2D + 3D Asset JSON Exporter
    // ------------------------------------------------------------
    // Delegates to Ruby na_settingsExport3D, which calls
    // Na__DevTools::Na__JsonExporter3D.na_run_export.
    window.na_settingsExport3D = function () {
        if (!na_settings_sketchup_available()) {
            na_settings_status('warning', 'SketchUp connection not available - export skipped.');
            return;
        }
        na_settings_status('info', 'Running 3D exporter - check the Ruby Console for output.');
        window.sketchup.na_settingsExport3D();
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
