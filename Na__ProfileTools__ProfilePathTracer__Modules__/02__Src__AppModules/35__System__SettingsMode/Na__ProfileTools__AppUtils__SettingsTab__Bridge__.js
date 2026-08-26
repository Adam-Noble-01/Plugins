// =============================================================================
// NA PROFILE TOOLS - APP UTILS - SETTINGS TAB - BRIDGE
// =============================================================================
//
// FILE       : Na__ProfileTools__AppUtils__SettingsTab__Bridge__.js
// NAMESPACE  : window.na_profiletools_settings*
// PURPOSE    : Global onclick handlers for the Settings tab buttons.
//              Each function delegates to the shared bridge module.
//
// =============================================================================

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Status Helper
    // -------------------------------------------------------------------------

    function na_status(message) {
        if (typeof window.Na__ProfilePathTracer__Ui__SetStatusFromBridge === 'function') {
            window.Na__ProfilePathTracer__Ui__SetStatusFromBridge(message);
        }
        var statusEl = document.getElementById('na-status-message');
        if (statusEl) statusEl.textContent = message || '';
        var statusBar = document.getElementById('na-status-bar');
        if (statusBar) statusBar.classList.remove('na-hidden');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Settings Actions
    // -------------------------------------------------------------------------

    window.na_profiletools_settingsReloadPlugin = function () {
        na_status('Reloading plugin...');
        if (window.Na__ProfilePathTracer__Bridge__ReloadPlugin) {
            window.Na__ProfilePathTracer__Bridge__ReloadPlugin();
        } else if (window.Na__ProfileTools__BridgeBase) {
            window.Na__ProfileTools__BridgeBase.Na__BridgeBase__CallSafe('na_profilepathtracer_reload_plugin');
        } else {
            na_status('Reload bridge is not available.');
        }
    };

    window.na_profiletools_settingsRefreshEdgeMaterials = function () {
        na_status('Refreshing edge materials from URL...');
        if (window.Na__ProfilePathTracer__Bridge__RefreshEdgeMaterials) {
            window.Na__ProfilePathTracer__Bridge__RefreshEdgeMaterials();
        } else if (window.Na__ProfileTools__BridgeBase) {
            window.Na__ProfileTools__BridgeBase.Na__BridgeBase__CallSafe('na_profilepathtracer_refresh_edge_materials');
        } else {
            na_status('Refresh edge materials bridge is not available.');
        }
    };

    window.na_profiletools_settingsPurgeEdgeMaterialsCache = function () {
        var confirmed = window.confirm(
            'This will delete the edge materials cache file and download a fresh copy from the server.\n\nProceed?'
        );
        if (!confirmed) {
            na_status('Cache purge cancelled.');
            return;
        }

        na_status('Purging edge materials cache...');
        if (window.Na__ProfilePathTracer__Bridge__PurgeEdgeMaterialsCache) {
            window.Na__ProfilePathTracer__Bridge__PurgeEdgeMaterialsCache();
        } else if (window.Na__ProfileTools__BridgeBase) {
            window.Na__ProfileTools__BridgeBase.Na__BridgeBase__CallSafe('na_profilepathtracer_purge_edge_materials_cache');
        } else {
            na_status('Purge edge materials bridge is not available.');
        }
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Dynamic Regeneration Actions
    // -------------------------------------------------------------------------

    window.na_profiletools_settingsOpenPathEditor = function () {
        na_status('Opening selected trace path for editing...');
        if (window.Na__ProfileTools__BridgeBase) {
            window.Na__ProfileTools__BridgeBase.Na__BridgeBase__CallSafe('na_profilepathtracer_open_path_editor');
        } else if (window.sketchup) {
            window.sketchup.na_profilepathtracer_open_path_editor();
        } else {
            na_status('Open path bridge is not available.');
        }
    };

    window.na_profiletools_settingsDynRegenEnableAll = function () {
        na_status('Enabling Dynamic Regeneration on all profile traces...');
        if (window.Na__ProfileTools__BridgeBase) {
            window.Na__ProfileTools__BridgeBase.Na__BridgeBase__CallSafe('na_profilepathtracer_dynregen_enable_all');
        } else if (window.sketchup) {
            window.sketchup.na_profilepathtracer_dynregen_enable_all();
        } else {
            na_status('DynRegen enable-all bridge is not available.');
        }
    };

    window.na_profiletools_settingsDynRegenDisableAll = function () {
        na_status('Disabling Dynamic Regeneration on all profile traces...');
        if (window.Na__ProfileTools__BridgeBase) {
            window.Na__ProfileTools__BridgeBase.Na__BridgeBase__CallSafe('na_profilepathtracer_dynregen_disable_all');
        } else if (window.sketchup) {
            window.sketchup.na_profilepathtracer_dynregen_disable_all();
        } else {
            na_status('DynRegen disable-all bridge is not available.');
        }
    };

    window.na_profiletools_settingsDynRegenDetachAll = function () {
        var confirmed = window.confirm(
            'This will detach all active Dynamic Regeneration observers without disabling the stored flag.\n\nProceed?'
        );
        if (!confirmed) {
            na_status('Detach all observers cancelled.');
            return;
        }
        na_status('Detaching all Dynamic Regeneration observers...');
        if (window.Na__ProfileTools__BridgeBase) {
            window.Na__ProfileTools__BridgeBase.Na__BridgeBase__CallSafe('na_profilepathtracer_dynregen_detach_all');
        } else if (window.sketchup) {
            window.sketchup.na_profilepathtracer_dynregen_detach_all();
        } else {
            na_status('DynRegen detach-all bridge is not available.');
        }
    };

    // endregion ----------------------------------------------------------------
})();
