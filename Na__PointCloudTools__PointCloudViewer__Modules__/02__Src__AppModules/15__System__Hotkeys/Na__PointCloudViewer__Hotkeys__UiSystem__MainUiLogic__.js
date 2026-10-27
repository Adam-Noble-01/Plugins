// =============================================================================
// NA POINT CLOUD VIEWER - HOTKEYS - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PointCloudViewer__Hotkeys__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PointCloudViewer__Hotkeys
// PURPOSE    : Settings > Keyboard Shortcuts (v0.13.0): every shortcut command,
//              the key(s) SketchUp has given it, a key it shares with another
//              command, and the button that opens SketchUp's Shortcuts page.
//
// STATE: state.hotkeys (Ruby reads the keys from Sketchup.get_shortcuts). Keys
//   are set in SketchUp's own Preferences, so the list is read again when this
//   window gets the focus back while Settings shows, and when Settings opens.
//
// =============================================================================

(function () {
    'use strict';

    var Hotkeys = {};
    var Shell   = window.Na__PointCloudViewer__Shell;
    var Bridge  = window.Na__PointCloudViewer__Bridge;

    // -------------------------------------------------------------------------
    // REGION | Render
    // -------------------------------------------------------------------------

    function na_row(command) {
        var row = Shell.na_el('div', 'na-hotkey' + (command.separatorBefore ? ' na-hotkey--group' : ''));
        row.title = command.path || '';
        var head = Shell.na_el('div', 'na-hotkey__head');
        head.appendChild(Shell.na_el('span', 'na-hotkey__name', command.menuText));
        var keys = Shell.na_el('span', 'na-hotkey__keys');
        if (command.keys && command.keys.length) {
            command.keys.forEach(function (key) { keys.appendChild(Shell.na_el('kbd', 'na-key-chip', key)); });
        } else {
            keys.appendChild(Shell.na_el('span', 'na-hotkey__none', 'No key'));
        }
        head.appendChild(keys);
        row.appendChild(head);
        if (command.summary) row.appendChild(Shell.na_el('p', 'na-hotkey__summary', command.summary));
        (command.clashes || []).forEach(function (clash) {
            row.appendChild(Shell.na_el('p', 'na-hotkey__clash', clash.key + ' is also given to ' + clash.with + '.'));
        });
        if (command.inMenu === false) {
            row.appendChild(Shell.na_el('p', 'na-hotkey__clash', 'Not in the Extensions menu yet: Reload Plugin adds it.'));
        }
        return row;
    }

    Hotkeys.na_render = function (state) {
        var hotkeys = state && state.hotkeys;
        if (!hotkeys) return;
        var list = document.getElementById('na-hotkey-list');
        list.innerHTML = '';
        if (!hotkeys.isAvailable) {
            list.appendChild(Shell.na_el('p', 'na-note', hotkeys.problem || 'The keyboard shortcuts could not be listed.'));
            return;
        }
        var commands = hotkeys.commands || [];
        commands.forEach(function (command) { list.appendChild(na_row(command)); });
        var given = commands.filter(function (command) { return command.keys && command.keys.length; }).length;
        Shell.na_text('na-hotkeys-note', given
            ? given + ' of ' + commands.length + ' commands have a key. This list is read again when you come back to this window.'
            : 'None of these commands has a key yet. This list is read again when you come back to this window.');
        document.getElementById('na-hotkeys-open').disabled = !hotkeys.canOpenPreferences;
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Wiring
    // -------------------------------------------------------------------------

    function na_settings_showing() {
        return !!window.Na_TabRouter && window.Na_TabRouter.na_get_active_tab() === 'settings';
    }

    function na_wire() {
        document.getElementById('na-hotkeys-open').addEventListener('click', function () {
            Bridge.na_call('hotkeys_open_preferences', {});
        });
        // Keys are given in SketchUp's own Preferences: read them again on return
        window.addEventListener('focus', function () {
            if (na_settings_showing()) Bridge.na_call('state_refresh', {});
        });
        var hook = function () {
            if (!window.Na_TabRouter) return false;
            window.Na_TabRouter.na_on_change(function (tabId) {
                if (tabId === 'settings') Bridge.na_call('state_refresh', {});
            });
            return true;
        };
        if (!hook()) window.setTimeout(hook, 0);   // the router loads after this file
    }

    // endregion ----------------------------------------------------------------

    Shell.na_on('state', Hotkeys.na_render);

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_wire);
    } else {
        na_wire();
    }

    window.Na__PointCloudViewer__Hotkeys = Hotkeys;
})();
