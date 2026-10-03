// =============================================================================
// NA POINT CLOUD VIEWER - SETTINGS TAB - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PointCloudViewer__SettingsTab__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PointCloudViewer__SettingsTab
// PURPOSE    : Settings tab: Reload Plugin, the native renderer's status,
//              cache and user-config folders, the technical log and About.
//
// =============================================================================

(function () {
    'use strict';

    var SettingsTab = {};
    var Shell  = window.Na__PointCloudViewer__Shell;
    var Bridge = window.Na__PointCloudViewer__Bridge;

    // -------------------------------------------------------------------------
    // REGION | Render
    // -------------------------------------------------------------------------

    SettingsTab.na_render = function (state) {
        if (!state) return;
        var native = state.nativeEngine || {};
        Shell.na_text('na-settings-native-status', 'Native engine: ' + (native.message || 'status unknown'));

        var paths = state.paths || {};
        Shell.na_text('na-settings-cache-path', paths.cacheFolder || '');
        Shell.na_text('na-settings-user-config-path', paths.userConfigFile || '');

        var plugin = state.plugin || {};
        Shell.na_text('na-settings-about-version', (plugin.name || 'Na Point Cloud Viewer') + ' v' + (plugin.version || '') + ' by Noble Architecture');

        na_render_log(state.log || []);
        document.getElementById('na-settings-reload').disabled = !!(state.job && state.job.isRunning);
    };

    // Newest first. Only warnings and errors carry a level tag.
    function na_render_log(entries) {
        var log = document.getElementById('na-settings-log');
        log.innerHTML = '';
        if (!entries.length) {
            log.appendChild(Shell.na_el('div', 'na-log__empty', 'Nothing logged yet.'));
            return;
        }
        entries.slice().reverse().forEach(function (entry) {
            var row = Shell.na_el('div', 'na-log__row na-log__row--' + (entry.level || 'info'));
            row.appendChild(Shell.na_el('span', 'na-log__time', entry.time || ''));
            row.appendChild(Shell.na_el('span', 'na-log__message', entry.message || ''));
            log.appendChild(row);
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Wiring
    // -------------------------------------------------------------------------

    function na_wire() {
        document.getElementById('na-settings-reload').addEventListener('click', function () {
            Shell.na_set_status('Reloading plugin...', 'info');
            Bridge.na_call('settings_reload_plugin', {});
        });
        document.getElementById('na-settings-open-cache').addEventListener('click', function () {
            Bridge.na_call('open_cache_folder', {});
        });
        document.getElementById('na-settings-open-user-config').addEventListener('click', function () {
            Bridge.na_call('open_user_config_folder', {});
        });
    }

    // endregion ----------------------------------------------------------------

    Shell.na_on('state', SettingsTab.na_render);

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_wire);
    } else {
        na_wire();
    }

    window.Na__PointCloudViewer__SettingsTab = SettingsTab;
})();
