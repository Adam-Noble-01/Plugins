// =============================================================================
// NA PAINTERLYNPR ASSETS - SETTINGS - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PainterlyAssets__Settings__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PainterlyAssets__SettingsUi
// PURPOSE    : The Settings tab: where the PainterlyNPR folder is and how it was
//              found, which Python runs PainterlyNPR's build utility, this
//              PC's overrides for both, Reload Plugin Data, and the technical
//              log behind the plain-English messages.
// CREATED    : 30-Oct-2026
//
// RUBY CALLS : chooseLibrary, resetLibrary, choosePython, resetPython,
//              openFolder, reloadPlugin, refresh
// LISTENS TO : state
//
// =============================================================================

(function () {
    'use strict';

    var Shell  = window.Na__PainterlyAssets__Shell;
    var Bridge = window.Na__PainterlyAssets__Bridge;

    var SOURCES = {
        library : { chosen: 'chosen on this PC (Choose Folder)', 'default': 'found in the default places' },
        python  : { chosen: 'chosen on this PC', config: 'set in the plugin config', found: 'found on this PC', path: 'found on PATH' }
    };

    function na_kv(id, rows) {
        var box = Shell.na_clear(document.getElementById(id));
        rows.forEach(function (row) {
            var r = Shell.na_el('div', 'na-kv__row' + (row[2] ? ' na-kv__row--' + row[2] : ''));
            r.appendChild(Shell.na_el('span', 'na-kv__label', row[0]));
            r.appendChild(Shell.na_el('span', 'na-kv__value', row[1]));
            box.appendChild(r);
        });
    }

    function na_render(state) {
        if (!state) return;
        var library = state.library || {};
        na_kv('na-settings-library', library.found ? [
            ['Folder', library.root],
            ['Library', library.library],
            ['How', SOURCES.library[library.source] || library.source || '']
        ] : [
            ['Folder', 'Not found', 'error'],
            ['Looked in', (library.tried || []).join(', ') || 'nowhere configured']
        ]);

        var python = state.python || {};
        na_kv('na-settings-python', [
            ['Python', python.python || 'No Python 3 found', python.python ? null : 'error'],
            ['How', python.python ? (SOURCES.python[python.source] || python.source) + (python.windowless ? ', windowless (no console window)' : '') : 'Install Python 3, or choose python.exe'],
            ['Utility', python.utility || 'needs the PainterlyNPR folder', python.utilityOk ? null : 'error'],
            ['Run log', python.runLog || '']
        ]);

        na_kv('na-settings-plugin', [
            ['Version', (state.plugin || {}).version || ''],
            ['Catalogue', ((state.catalogue || {}).message || '') + ((state.catalogue || {}).scannedAt ? ', read at ' + state.catalogue.scannedAt : '')]
        ]);

        var log = document.getElementById('na-settings-log');
        log.textContent = (state.log || []).map(function (entry) {
            return entry.time + '  ' + (entry.level === 'info' ? '' : entry.level.toUpperCase() + '  ') + entry.message;
        }).join('\n') || 'Nothing logged yet.';
    }

    function na_wire() {
        var on = function (id, action) {
            document.getElementById(id).addEventListener('click', function () { Bridge.na_call(action, {}); });
        };
        on('na-settings-choose-library', 'chooseLibrary');
        on('na-settings-reset-library', 'resetLibrary');
        on('na-settings-open-library', 'openFolder');
        on('na-settings-choose-python', 'choosePython');
        on('na-settings-reset-python', 'resetPython');
        on('na-settings-refresh', 'refresh');
        document.getElementById('na-settings-reload').addEventListener('click', function () {
            Shell.na_loading_show('Reload Plugin Data', 'Loading every Ruby file again, then reopening this window...');
            if (!Bridge.na_call('reloadPlugin', {})) Shell.na_loading_hide();
        });
    }

    Shell.na_on('state', na_render);

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_wire);
    } else {
        na_wire();
    }

    window.Na__PainterlyAssets__SettingsUi = { na_render: na_render };
})();

// =============================================================================
// END OF FILE
// =============================================================================
