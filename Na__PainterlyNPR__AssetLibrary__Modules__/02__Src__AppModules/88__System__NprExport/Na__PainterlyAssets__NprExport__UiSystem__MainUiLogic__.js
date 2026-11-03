// =============================================================================
// NA PAINTERLYNPR ASSETS - NPR EXPORT - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PainterlyAssets__NprExport__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PainterlyAssets__NprExportUi
// PURPOSE    : The NPR Export window: shows the model's export settings, sends
//              every change back (Ruby keeps them in the model), Export and
//              Cancel, the progress and the report.
// CREATED    : 01-Nov-2026 (v0.3.0)
//
// RUBY CALLS : settings, export, calibration, cancel, chooseFolder, openFolder,
//              resetExport, saveLook, loadLook, restoreBackup, refresh
// LISTENS TO : state, derived, progress, report, status
//
// - The settings object is the model's, whole: a key this page does not show
//   goes back to Ruby as it came, so nothing a newer version kept is lost.
// - A field being typed in is never redrawn under the cursor.
//
// =============================================================================

(function () {
    'use strict';

    var Bridge = window.Na__PainterlyAssets__Bridge;

    // -------------------------------------------------------------------------
    // REGION | State
    // -------------------------------------------------------------------------

    var SEND_MS    = 350;
    var STATUS_MS  = 6000;
    var FORMAT_HINTS = {
        png  : 'Carries its resolution, so it prints at the sheet\'s size at 100%.',
        jpeg : 'A smaller file than a PNG, its resolution written in it too. Paint and paper keep best at a high quality.',
        pdf  : 'A true-size page: the sheet itself, the picture at the resolution below. Print it at 100% (actual size), never fitted to the page.'
    };

    var S = {
        state     : null,
        settings  : null,
        sendTimer : null,
        running   : false,
        dismissed : '',
        statusTimer : null
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Helpers
    // -------------------------------------------------------------------------

    function na_id(id) { return document.getElementById(id); }

    function na_el(tag, className, text) {
        var el = document.createElement(tag);
        if (className) el.className = className;
        if (text !== undefined && text !== null) el.textContent = text;
        return el;
    }

    function na_clear(el) {
        while (el && el.firstChild) el.removeChild(el.firstChild);
        return el;
    }

    function na_focused(el) { return el && document.activeElement === el; }

    function na_radios(name) { return document.querySelectorAll('input[name="' + name + '"]'); }

    function na_set_radio(name, value) {
        Array.prototype.forEach.call(na_radios(name), function (input) { input.checked = input.value === value; });
    }

    function na_bytes(bytes) {
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + ' MB';
        return Math.max(1, Math.round(bytes / 1024)) + ' kB';
    }

    function na_pixels(dpi) {
        var sheet = (S.state && S.state.Sheet) || { widthMm: 420, heightMm: 297, name: 'A3' };
        var per = dpi / 25.4;
        return [Math.round(sheet.widthMm * per), Math.round(sheet.heightMm * per), sheet];
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Receive
    // -------------------------------------------------------------------------

    window.Na__PainterlyAssets__Receive = function (channel, payload) {
        try {
            if (channel === 'state') na_on_state(payload);
            else if (channel === 'derived') na_on_derived(payload);
            else if (channel === 'progress') na_on_progress(payload);
            else if (channel === 'report') na_on_report(payload);
            else if (channel === 'status') na_status(payload.message, payload.level);
        } catch (err) {
            console.error('[NPR Export] ' + channel + ':', err);
        }
    };

    function na_on_state(state) {
        S.state = state;
        S.settings = JSON.parse(JSON.stringify(state.Settings || {}));
        S.settings.scenes = (state.Scenes || []).filter(function (scene) { return scene.Ticked; })   // <-- As Ruby found them (by id, else by name): a scene gone is let go
            .map(function (scene) { return { pid: scene.Pid, name: scene.Name }; });
        S.running = !!state.Running;
        na_id('na-export-model').textContent = (state.Model && state.Model.Title) || '';
        na_render_settings();
        na_render_scenes();
        na_on_derived(state);
        na_render_running();
    }

    function na_on_derived(derived) {
        if (S.state) {
            S.state.Folder = derived.Folder;
            S.state.Preview = derived.Preview;
            S.state.Record = derived.Record;
        }
        na_render_folder(derived.Folder || {});
        na_id('na-export-preview').textContent = derived.Preview ? 'The first picture: ' + derived.Preview : '';
        na_render_record(derived.Record || {});
    }

    function na_on_progress(progress) {
        S.running = !!progress.Running;
        var line = na_id('na-export-progress');
        line.textContent = progress.Text || '';
        line.dataset.level = progress.Level || 'info';
        line.hidden = !progress.Text;
        if (S.running) na_id('na-export-report').hidden = true;
        na_render_running();
    }

    function na_on_report(report) {
        S.running = false;
        na_render_running();
        var line = na_id('na-export-progress');
        var files = report.Files || [];
        var failed = report.Failed || [];
        var text = report.Cancelled ? 'Cancelled. ' : '';
        text += files.length === 1 ? '1 picture written' : files.length + ' pictures written';
        if (failed.length) text += ', ' + failed.length + ' not';
        text += ' in ' + report.Seconds + ' s.';
        if (report.Problem) text = report.Problem + ' ' + text;
        line.textContent = text;
        line.dataset.level = report.Ok ? 'success' : (files.length ? 'warn' : 'error');
        line.hidden = false;

        var box = na_clear(na_id('na-export-report'));
        files.forEach(function (file) {
            var row = na_el('div', 'na-export-report__row');
            row.appendChild(na_el('span', 'na-export-report__name', file.name));
            var bits = [];
            if (file.width && file.height) bits.push(file.width + ' \u00d7 ' + file.height + ' px');
            bits.push(na_bytes(file.bytes || 0));
            if (file.seconds) bits.push(file.seconds + ' s');
            row.appendChild(na_el('span', 'na-export-report__meta', bits.join(', ')));
            box.appendChild(row);
        });
        failed.forEach(function (item) {
            var row = na_el('div', 'na-export-report__row na-export-report__row--failed');
            row.appendChild(na_el('span', 'na-export-report__name', item.label));
            row.appendChild(na_el('span', 'na-export-report__meta', item.message));
            box.appendChild(row);
        });
        if (files.length) {
            var open = na_el('button', 'naButtonSecondary na-button--small', 'Open Folder');
            open.type = 'button';
            open.addEventListener('click', function () { Bridge.na_call('openFolder', {}); });
            var row = na_el('div', 'na-button-row');
            row.appendChild(open);
            box.appendChild(row);
        }
        box.hidden = !(files.length || failed.length);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Render
    // -------------------------------------------------------------------------

    function na_render_settings() {
        var s = S.settings || {};
        na_set_radio('na-export-views', s.views);
        na_id('na-export-scenes').hidden = s.views !== 'scenes';
        na_set_radio('na-export-format', s.format);
        na_id('na-export-format-hint').textContent = FORMAT_HINTS[s.format] || '';
        na_id('na-export-quality-row').hidden = s.format !== 'jpeg';
        var quality = na_id('na-export-quality');
        if (!na_focused(quality)) quality.value = s.jpegQuality;
        na_id('na-export-quality-value').textContent = s.jpegQuality + '%';
        na_render_dpi();
        na_set_radio('na-export-folder-mode', s.folderMode);
        var sub = na_id('na-export-subfolder');
        if (!na_focused(sub)) sub.value = s.subfolder || '';
        sub.disabled = s.folderMode !== 'besideModel';
        na_id('na-export-chosen-path').textContent = s.folderMode === 'chosen' ? (s.folder || 'None chosen yet') : (s.folder ? 'Last chosen: ' + s.folder : '');
        var name = na_id('na-export-name');
        if (!na_focused(name)) name.value = s.fileName || '';
        na_set_radio('na-export-exists', s.ifExists);
        na_id('na-export-open-after').checked = s.openFolder === true;
        na_id('na-export-open-files').checked = s.openFile === true;
    }

    function na_render_dpi() {
        var s = S.settings || {};
        var presets = (S.state && S.state.DpiPresets) || [127, 150, 200, 254, 300, 400, 600];
        var limits = (S.state && S.state.DpiLimits) || [50, 1200];
        var chips = na_clear(na_id('na-export-dpi-chips'));
        presets.forEach(function (dpi) {
            var chip = na_el('button', 'na-export-chip' + (dpi === s.dpi ? ' na-export-chip--on' : ''), dpi === 127 ? '127 (screen)' : String(dpi));
            chip.type = 'button';
            chip.setAttribute('aria-pressed', dpi === s.dpi ? 'true' : 'false');
            chip.addEventListener('click', function () { na_change('dpi', dpi); });
            chips.appendChild(chip);
        });
        var custom = na_id('na-export-dpi');
        custom.min = limits[0];
        custom.max = limits[1];
        if (!na_focused(custom)) custom.value = s.dpi;
        var px = na_pixels(s.dpi || 300);
        var sheet = px[2];
        na_id('na-export-size').textContent = px[0] + ' \u00d7 ' + px[1] + ' px at ' + s.dpi + ' dpi, on the engine\'s sheet: ' +
            (sheet.name ? sheet.name + ', ' : '') + Math.round(sheet.widthMm) + ' \u00d7 ' + Math.round(sheet.heightMm) + ' mm.';
        na_id('na-export-dpi-hint').textContent = s.dpi >= 500 ?
            'At ' + s.dpi + ' dpi the engine needs a large graphics card (it draws the whole sheet at once). If it cannot, the report says so: export at 300.' :
            'The same drawing at any resolution: every pen width is its millimetres on the sheet, so a higher resolution is sharper, never different.';
    }

    function na_render_scenes() {
        var list = na_clear(na_id('na-export-scenes-list'));
        var scenes = (S.state && S.state.Scenes) || [];
        if (!scenes.length) {
            list.appendChild(na_el('p', 'na-hint', 'This model has no scenes. Add them in SketchUp (View > Animation > Add Scene), then press Refresh.'));
        }
        var ticked = {};
        ((S.settings && S.settings.scenes) || []).forEach(function (scene) { ticked[scene.pid] = true; });
        scenes.forEach(function (scene) {
            var label = na_el('label', 'na-check na-export-scene');
            var box = document.createElement('input');
            box.type = 'checkbox';
            box.checked = !!ticked[scene.Pid];
            box.addEventListener('change', function () { na_tick_scene(scene, box.checked); });
            label.appendChild(box);
            label.appendChild(document.createTextNode(' ' + scene.Name));
            if (!scene.Camera) label.appendChild(na_el('span', 'na-export-scene__note', 'keeps no camera: the view\'s'));
            list.appendChild(label);
        });
        na_count_scenes();
    }

    function na_count_scenes() {
        var count = ((S.settings && S.settings.scenes) || []).length;
        var total = ((S.state && S.state.Scenes) || []).length;
        na_id('na-export-scenes-count').textContent = total ? count + ' of ' + total + ' ticked' : '';
    }

    function na_render_folder(folder) {
        var box = na_clear(na_id('na-export-folder'));
        if (folder.Problem) {
            box.appendChild(na_el('span', 'na-export-folder__problem', folder.Problem));
        } else if (folder.Path) {
            box.appendChild(na_el('span', 'na-export-folder__path', folder.Path));
            if (!folder.Exists) box.appendChild(na_el('span', 'na-export-folder__note', folder.Make ? ' (made with the first export)' : ''));
        }
        na_id('na-export-open-folder').disabled = !(folder.Path && folder.Exists);
    }

    function na_render_record(record) {
        var line = na_id('na-export-record');
        var text;
        if (record.State === 'readOnly') text = record.Problem || 'This model\'s NPR settings are read-only.';
        else if (record.HasExport) text = 'These settings are kept in this model (revision ' + record.Revision + ', ' + record.SavedText + '), and the look with them.';
        else text = 'The plugin\'s defaults. The first change is kept in this model.';
        line.textContent = text;
        line.dataset.level = record.State === 'readOnly' ? 'warn' : 'info';
        var backup = record.Backup || {};
        var box = na_id('na-export-backup');
        box.hidden = !(backup.offer && String(backup.savedText || '') !== S.dismissed);
        na_id('na-export-backup-text').textContent = backup.reason || '';
    }

    function na_render_running() {
        na_id('na-export-go').disabled = S.running;
        na_id('na-export-cancel').hidden = !S.running;
        Array.prototype.forEach.call(document.querySelectorAll('[data-calibration]'), function (button) { button.disabled = S.running; });
    }

    function na_status(message, level) {
        var bar = na_id('na-status-bar');
        clearTimeout(S.statusTimer);
        if (!message) { bar.classList.add('na-hidden'); return; }
        na_id('na-status-message').textContent = message;
        bar.className = 'na-status-bar' + (level && level !== 'info' ? ' na-status-bar--' + level : '');
        if (level === 'info' || level === 'success') S.statusTimer = setTimeout(function () { bar.classList.add('na-hidden'); }, STATUS_MS);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Changes Back to Ruby
    // -------------------------------------------------------------------------

    function na_change(key, value) {
        if (!S.settings) return;
        S.settings[key] = value;
        na_render_settings();
        na_send_soon();
    }

    function na_send_soon() {
        clearTimeout(S.sendTimer);
        S.sendTimer = setTimeout(na_send_now, SEND_MS);
    }

    function na_send_now() {
        clearTimeout(S.sendTimer);
        S.sendTimer = null;
        if (S.settings) Bridge.na_call('settings', { Settings: S.settings });
    }

    function na_tick_scene(scene, on) {
        var list = (S.settings.scenes || []).filter(function (entry) { return entry.pid !== scene.Pid; });
        if (on) list.push({ pid: scene.Pid, name: scene.Name });
        S.settings.scenes = na_in_model_order(list);
        na_count_scenes();
        na_send_soon();
    }

    function na_in_model_order(list) {
        var order = ((S.state && S.state.Scenes) || []).map(function (scene) { return scene.Pid; });
        return list.slice().sort(function (a, b) { return order.indexOf(a.pid) - order.indexOf(b.pid); });
    }

    function na_insert_token(token) {
        var input = na_id('na-export-name');
        var start = input.selectionStart === null ? input.value.length : input.selectionStart;
        var end = input.selectionEnd === null ? input.value.length : input.selectionEnd;
        input.value = input.value.slice(0, start) + token + input.value.slice(end);
        input.focus();
        input.setSelectionRange(start + token.length, start + token.length);
        S.settings.fileName = input.value;
        na_send_soon();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Wire
    // -------------------------------------------------------------------------

    function na_wire() {
        Array.prototype.forEach.call(na_radios('na-export-views'), function (input) {
            input.addEventListener('change', function () { na_change('views', input.value); });
        });
        Array.prototype.forEach.call(na_radios('na-export-format'), function (input) {
            input.addEventListener('change', function () { na_change('format', input.value); });
        });
        Array.prototype.forEach.call(na_radios('na-export-folder-mode'), function (input) {
            input.addEventListener('change', function () {
                na_change('folderMode', input.value);
                if (input.value === 'chosen' && !S.settings.folder) Bridge.na_call('chooseFolder', {});
            });
        });
        Array.prototype.forEach.call(na_radios('na-export-exists'), function (input) {
            input.addEventListener('change', function () { na_change('ifExists', input.value); });
        });
        na_id('na-export-quality').addEventListener('input', function (event) {
            S.settings.jpegQuality = Number(event.target.value);
            na_id('na-export-quality-value').textContent = event.target.value + '%';
            na_send_soon();
        });
        na_id('na-export-dpi').addEventListener('change', function (event) {
            var limits = (S.state && S.state.DpiLimits) || [50, 1200];
            var dpi = Math.round(Number(event.target.value));
            if (!(dpi > 0)) dpi = S.settings.dpi;
            na_change('dpi', Math.max(limits[0], Math.min(limits[1], dpi)));
        });
        na_id('na-export-subfolder').addEventListener('input', function (event) { S.settings.subfolder = event.target.value; na_send_soon(); });
        na_id('na-export-name').addEventListener('input', function (event) { S.settings.fileName = event.target.value; na_send_soon(); });
        na_id('na-export-open-after').addEventListener('change', function (event) { na_change('openFolder', event.target.checked); });
        na_id('na-export-open-files').addEventListener('change', function (event) { na_change('openFile', event.target.checked); });
        Array.prototype.forEach.call(document.querySelectorAll('.na-export-token'), function (button) {
            button.addEventListener('click', function () { na_insert_token(button.dataset.token); });
        });
        na_id('na-export-scenes-all').addEventListener('click', function () {
            S.settings.scenes = ((S.state && S.state.Scenes) || []).map(function (scene) { return { pid: scene.Pid, name: scene.Name }; });
            na_render_scenes();
            na_send_soon();
        });
        na_id('na-export-scenes-none').addEventListener('click', function () {
            S.settings.scenes = [];
            na_render_scenes();
            na_send_soon();
        });
        na_id('na-export-scenes-refresh').addEventListener('click', function () { na_send_now(); Bridge.na_call('refresh', {}); });
        na_id('na-export-choose').addEventListener('click', function () { na_send_now(); Bridge.na_call('chooseFolder', {}); });
        na_id('na-export-open-folder').addEventListener('click', function () { Bridge.na_call('openFolder', {}); });
        na_id('na-export-save-look').addEventListener('click', function () { Bridge.na_call('saveLook', {}); });
        na_id('na-export-load-look').addEventListener('click', function () { Bridge.na_call('loadLook', {}); });
        na_id('na-export-reset').addEventListener('click', function () { clearTimeout(S.sendTimer); Bridge.na_call('resetExport', {}); });
        na_id('na-export-restore').addEventListener('click', function () { na_id('na-export-backup').hidden = true; Bridge.na_call('restoreBackup', {}); });
        na_id('na-export-not-now').addEventListener('click', function () {
            var backup = (S.state && S.state.Record && S.state.Record.Backup) || {};
            S.dismissed = String(backup.savedText || '');
            na_id('na-export-backup').hidden = true;
        });
        Array.prototype.forEach.call(document.querySelectorAll('[data-calibration]'), function (button) {
            button.addEventListener('click', function () {
                clearTimeout(S.sendTimer);
                Bridge.na_call('calibration', { Settings: S.settings, Which: button.dataset.calibration });
            });
        });
        na_id('na-export-go').addEventListener('click', function () {
            clearTimeout(S.sendTimer);
            na_id('na-export-report').hidden = true;
            Bridge.na_call('export', { Settings: S.settings });
        });
        na_id('na-export-cancel').addEventListener('click', function () { Bridge.na_call('cancel', {}); });
        window.addEventListener('focus', function () { if (!S.running && !S.sendTimer) Bridge.na_call('refresh', {}); });   // <-- Scenes added in SketchUp meanwhile
    }

    // endregion ----------------------------------------------------------------

    na_wire();
    Bridge.na_ready();

    window.Na__PainterlyAssets__NprExportUi = { na_state: function () { return S; } };
})();

// =============================================================================
// END OF FILE
// =============================================================================
