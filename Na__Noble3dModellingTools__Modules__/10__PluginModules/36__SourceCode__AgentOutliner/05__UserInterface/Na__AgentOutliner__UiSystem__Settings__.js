// =============================================================================
// NA AGENT OUTLINER - UI SYSTEM - SETTINGS TAB
// =============================================================================
//
// FILE       : Na__AgentOutliner__UiSystem__Settings__.js
// NAMESPACE  : window.Na__AgentOutliner__Settings
// MODULE     : Settings (IIFE)
// AUTHOR     : Noble Architecture
// PURPOSE    : The hot reloader (this tool, or all of Noble 3D Tools), change
//              tracking, the colour grading bands and colours, selection
//              behaviour, the agent bridge's status, where the data lives,
//              and the Technical Log
// CREATED    : 10-Nov-2026
//
// DESCRIPTION:
// - The form is filled from Ruby's merged settings and sends only the
//   settings it shows; Ruby coerces each to its default's type and keeps
//   only Adam's differences on this PC.
// - Reload Agent Outliner reloads this tool's Ruby and reopens the dialog
//   (HTML, CSS and JS too). A brand-new menu item still needs a SketchUp
//   restart; new JS files need the dialog reopened, which the reload does.
//
// =============================================================================

(function () {
    'use strict';

    var Settings = {};
    var Shell = null, Store = null, Bridge = null;

    // The form: [group, key, element id, kind]
    var NA_FIELDS = [
        ['user',      'name',             'na-set-user-name',        'text'],
        ['tracking',  'enabled',          'na-set-track-enabled',    'bool'],
        ['tracking',  'count_visibility', 'na-set-track-visibility', 'bool'],
        ['tracking',  'count_lock',       'na-set-track-lock',       'bool'],
        ['tracking',  'keep_days',        'na-set-track-days',       'number'],
        ['tracking',  'max_events',       'na-set-track-max',        'number'],
        ['grading',   'agent_colour',     'na-set-agent-colour',     'text'],
        ['grading',   'user_colour',      'na-set-user-colour',      'text'],
        ['grading',   'status_colours',   'na-set-status-colours',   'bool'],     // <-- Also the Colours switch above the table (0.1.15)
        ['selection', 'mode',             'na-set-select-mode',      'text'],
        ['selection', 'follow_selection', 'na-set-follow',           'bool'],
        ['selection', 'zoom_on_double',   'na-set-zoom-double',      'bool'],
        ['outliner',  'show_images',      'na-set-show-images',      'bool'],
        ['outliner',  'show_sections',    'na-set-show-sections',    'bool'],
        ['debug',     'dev_mode',         'na-set-dev-mode',         'bool']
    ];

    // -------------------------------------------------------------------------
    // REGION | Fill and Read the Form
    // -------------------------------------------------------------------------

    function na_fill(state) {
        var settings = state.settings || {};
        NA_FIELDS.forEach(function (field) {
            var element = document.getElementById(field[2]);
            var group = settings[field[0]] || {};
            var value = group[field[1]];
            if (!element || value === undefined) return;
            if (field[3] === 'bool') element.checked = !!value;
            else element.value = value;
        });
        var bands = (settings.grading && settings.grading.band_minutes) || [5, 30, 120, 1440];
        for (var i = 0; i < 4; i++) {
            var band = document.getElementById('na-set-band-' + i);
            if (band) band.value = bands[i] !== undefined ? bands[i] : '';
        }
        na_render_legend();
        na_render_info(state);
    }

    function na_read() {
        var patch = {};
        NA_FIELDS.forEach(function (field) {
            var element = document.getElementById(field[2]);
            if (!element) return;
            patch[field[0]] = patch[field[0]] || {};
            if (field[3] === 'bool') patch[field[0]][field[1]] = element.checked;
            else if (field[3] === 'number') patch[field[0]][field[1]] = Number(element.value);
            else patch[field[0]][field[1]] = element.value;
        });
        var bands = [0, 1, 2, 3].map(function (i) { return Number(document.getElementById('na-set-band-' + i).value); });
        patch.grading = patch.grading || {};
        patch.grading.band_minutes = bands;
        return patch;
    }

    function na_check(patch) {
        var bands = patch.grading.band_minutes;
        if (bands.some(function (n) { return !isFinite(n) || n <= 0; })) return 'Each colour band is a number of minutes above 0.';
        for (var i = 1; i < bands.length; i++) if (bands[i] <= bands[i - 1]) return 'Each colour band must be longer than the one before it.';
        if (!(patch.tracking.keep_days > 0)) return 'Keep history for at least one day.';
        if (!(patch.tracking.max_events >= 100)) return 'Keep at least 100 changes.';
        return '';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Read-Only Panels
    // -------------------------------------------------------------------------

    function na_render_legend() {
        var host = Shell.na_clear(document.getElementById('na-set-legend'));
        var bands = [0, 1, 2, 3].map(function (i) { return Number(document.getElementById('na-set-band-' + i).value) || 0; });
        var agent = document.getElementById('na-set-agent-colour').value || '#7c3aed';
        var user = document.getElementById('na-set-user-colour').value || '#d97706';
        var alphas = [0.26, 0.17, 0.10, 0.05];
        [['Agent', agent], ['You', user]].forEach(function (pair) {
            var line = Shell.na_el('div', 'na-legend-line');
            line.appendChild(Shell.na_el('span', 'na-legend-who', pair[0]));
            bands.forEach(function (minutes, index) {
                var cell = Shell.na_el('span', 'na-legend-cell', 'up to ' + na_minutes(minutes));
                cell.style.background = Shell.na_rgba(pair[1], alphas[index]);
                cell.style.borderLeft = '3px solid ' + Shell.na_rgba(pair[1], [1, 0.8, 0.55, 0.3][index]);
                line.appendChild(cell);
            });
            host.appendChild(line);
        });
    }

    function na_minutes(minutes) {
        if (minutes < 60) return minutes + ' min';
        if (minutes < 1440) return (Math.round(minutes / 6) / 10) + ' h';
        var days = Math.round(minutes / 144) / 10;
        return days + (days === 1 ? ' day' : ' days');
    }

    function na_render_info(state) {
        Shell.na_text('na-set-version', 'Agent Outliner ' + (state.version || '') + '  \u00b7  SketchUp ' + (state.sketchup || ''));

        var mcp = state.mcp || {};
        var bridge = Shell.na_clear(document.getElementById('na-set-mcp'));
        var line = function (label, value, good) {
            var row = Shell.na_el('div', 'na-kv-row');
            row.appendChild(Shell.na_el('span', 'na-kv-key', label));
            row.appendChild(Shell.na_el('span', 'na-kv-value' + (good === false ? ' na-kv-value--bad' : (good ? ' na-kv-value--good' : '')), value));
            bridge.appendChild(row);
        };
        line('Na SketchUp MCP', mcp.loaded ? 'loaded' + (mcp.version ? ', bridge ' + mcp.version : '') : 'not loaded', !!mcp.loaded);
        line('Bridge', mcp.running ? 'listening for agents' : 'not running', !!mcp.running);
        line('Outliner tools', mcp.tools ? 'agent_outliner and agent_outliner_edit available' : 'not in this MCP yet: update the MCP plugin', !!mcp.tools);
        if (mcp.last) line('Last agent call', mcp.last.time + '  ' + mcp.last.tool + (mcp.last.ok ? '' : ' (failed)') + (mcp.last.message ? ': ' + mcp.last.message : ''));

        var tracking = state.tracking || {};
        var track = Shell.na_clear(document.getElementById('na-set-tracking-info'));
        var tline = function (label, value) {
            var row = Shell.na_el('div', 'na-kv-row');
            row.appendChild(Shell.na_el('span', 'na-kv-key', label));
            row.appendChild(Shell.na_el('span', 'na-kv-value', value));
            track.appendChild(row);
        };
        tline('Objects watched', String(tracking.objects || 0));
        tline('Changes recorded', String(tracking.events || 0) + ' (number ' + (tracking.seq || 0) + ')');
        if (tracking.last_pass) tline('Last check', tracking.last_pass.kind + ', ' + tracking.last_pass.ms + ' ms');
        tline('Agent changes checked', tracking.agent_full === false ? 'by event (this model is large)' : 'in full after every agent call');
        tline('History file', tracking.history_file || 'kept in memory until the model is first saved');

        var paths = state.paths || {};
        var where = Shell.na_clear(document.getElementById('na-set-paths'));
        [['Flags and comments', 'Inside the model, on each object (dictionary Na__AgentOutliner__Notes): they travel with the .skp.', null],
         ['Change history', paths.history || '', 'history'],
         ['Naming standards (shared by git)', paths.standards || '', 'standards'],
         ['Your settings (this PC)', paths.user || '', 'user'],
         ['Chat pictures (this PC)', paths.chat || '', 'chat'],
         ['Pictures agents sent (this PC)', paths.agent_chat || '', 'agent_chat']].forEach(function (item) {
            var row = Shell.na_el('div', 'na-kv-row');
            row.appendChild(Shell.na_el('span', 'na-kv-key', item[0]));
            var value = Shell.na_el('span', 'na-kv-value na-kv-value--path', item[1]);
            row.appendChild(value);
            if (item[2]) row.appendChild(Shell.na_button('Open', null, function () { Bridge.na_call('openFolder', { which: item[2] }); }));
            where.appendChild(row);
        });
    }

    function na_render_log(lines) {
        var pre = document.getElementById('na-set-log');
        pre.textContent = (lines || []).map(function (line) { return line.time + '  ' + line.level.toUpperCase() + '  ' + line.text; }).join('\n') || 'Nothing logged.';
        pre.scrollTop = pre.scrollHeight;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Wiring
    // -------------------------------------------------------------------------

    function na_wire() {
        document.getElementById('na-set-save').addEventListener('click', function () {
            var patch = na_read();
            var problem = na_check(patch);
            if (problem) return Shell.na_set_status(problem, 'warn');
            Bridge.na_call('saveSettings', { settings: patch });
        });
        ['na-set-band-0', 'na-set-band-1', 'na-set-band-2', 'na-set-band-3', 'na-set-agent-colour', 'na-set-user-colour'].forEach(function (id) {
            document.getElementById(id).addEventListener('input', na_render_legend);
        });
        document.getElementById('na-set-reload').addEventListener('click', function () {
            Shell.na_set_status('Reloading the Agent Outliner\u2026', 'info');
            Bridge.na_call('reloadPlugin', {});
        });
        document.getElementById('na-set-reload-all').addEventListener('click', function () {
            Shell.na_confirm({ title: 'Reload All of Noble 3D Tools?', text: 'Every Noble 3D Tools module reloads, and their open dialogs close and reopen.', confirm: 'Reload All' },
                function () { Bridge.na_call('reloadNoble3d', {}); });
        });
        document.getElementById('na-set-mark-seen').addEventListener('click', function () { Bridge.na_call('markChangesSeen', {}); });
        document.getElementById('na-set-clear-history').addEventListener('click', function () {
            Shell.na_confirm({ title: 'Clear This Model\u2019s Change History?', text: 'Every New and Updated mark goes, for you and for agents. Flags and comments stay in the model. This cannot be undone.',
                               confirm: 'Clear History', danger: true }, function () { Bridge.na_call('clearHistory', {}); });
        });
        document.getElementById('na-set-log-refresh').addEventListener('click', function () { Bridge.na_call('getLog', {}); });
        document.getElementById('na-set-open-module').addEventListener('click', function () { Bridge.na_call('openFolder', { which: 'module' }); });
    }

    function na_init() {
        Shell = window.Na__AgentOutliner__Shell;
        Store = window.Na__AgentOutliner__Store;
        Bridge = window.Na__AgentOutliner__Bridge;
        na_wire();
        Shell.na_on('state', na_fill);
        Shell.na_on('log', na_render_log);
        Shell.na_on('tab', function (tab) { if (tab === 'settings') { Bridge.na_call('getLog', {}); Bridge.na_call('getState', {}); } });
    }

    window.Na__AgentOutliner__Settings = Settings;
    window.Na__AgentOutliner__Shell.na_on('init', na_init);
})();

// =============================================================================
// END OF FILE
// =============================================================================
