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
    var na_clear_armed = false;
    var na_clear_timer = null;
    var na_last_state  = null;

    function na_disarm_clear() {
        if (na_clear_timer) window.clearTimeout(na_clear_timer);
        na_clear_timer = null;
        na_clear_armed = false;
    }

    // -------------------------------------------------------------------------
    // REGION | Render
    // -------------------------------------------------------------------------

    SettingsTab.na_render = function (state) {
        if (!state) return;
        na_last_state = state;
        var native = state.nativeEngine || {};
        Shell.na_text('na-settings-native-status', 'Native engine: ' + (native.message || 'status unknown'));

        var paths = state.paths || {};
        Shell.na_text('na-settings-cache-path', paths.cacheFolder || '');
        var caches = state.pointCaches || { count: 0, bytes: 0 };
        Shell.na_text('na-settings-cache-stats', caches.count
            ? 'Point caches: ' + caches.count + ' (' + (caches.bytes / 1e6).toFixed(0) + ' MB)'
            : 'No point caches yet. One is saved with the next LAS import.');
        var clear = document.getElementById('na-settings-clear-cache');
        if (!caches.count) na_disarm_clear();
        clear.disabled = !caches.count;
        clear.textContent = na_clear_armed ? 'Click again to clear' : 'Clear Point Caches';
        clear.classList.toggle('na-button--danger', na_clear_armed);
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
        document.getElementById('na-settings-clear-cache').addEventListener('click', function () {
            if (!na_clear_armed) {
                na_clear_armed = true;
                na_clear_timer = window.setTimeout(function () {
                    na_disarm_clear();
                    if (na_last_state) SettingsTab.na_render(na_last_state);
                }, 3000);
                if (na_last_state) SettingsTab.na_render(na_last_state);
                return;
            }
            na_disarm_clear();
            Bridge.na_call('cache_clear', {});
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
