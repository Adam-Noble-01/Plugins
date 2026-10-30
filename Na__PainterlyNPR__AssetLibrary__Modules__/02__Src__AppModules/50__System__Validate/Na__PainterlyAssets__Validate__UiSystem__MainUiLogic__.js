// =============================================================================
// NA PAINTERLYNPR ASSETS - VALIDATE - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PainterlyAssets__Validate__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PainterlyAssets__ValidateUi
// PURPOSE    : The Validate tab: runs PainterlyNPR's validate and index, and
//              shows the report: the summary, every error and warning on its
//              own line with an ERR or WARN badge, the index's answer, and
//              which Python ran it and when.
// CREATED    : 30-Oct-2026
//
// RUBY CALLS : validate
// LISTENS TO : state, validation
//
// =============================================================================

(function () {
    'use strict';

    var Shell  = window.Na__PainterlyAssets__Shell;
    var Bridge = window.Na__PainterlyAssets__Bridge;

    function na_render(report) {
        var box = Shell.na_clear(document.getElementById('na-validate-report'));
        if (!report) {
            box.appendChild(Shell.na_el('p', 'na-hint', 'Not run yet in this SketchUp session. Authoring an asset or writing an SKP runs it too.'));
            return;
        }

        var head = Shell.na_el('div', 'na-report__head na-report__head--' + (report.ok ? (report.warnings ? 'warn' : 'ok') : 'error'));
        head.appendChild(Shell.na_el('span', 'na-badge ' + (report.ok ? (report.warnings ? 'na-badge--warn' : 'na-badge--ok') : 'na-badge--error'), report.ok ? (report.warnings ? 'WARN' : 'OK') : 'ERR'));
        head.appendChild(Shell.na_el('span', 'na-report__summary', report.summary || ''));
        box.appendChild(head);

        var list = Shell.na_el('ul', 'na-report__items');
        (report.items || []).forEach(function (item) {
            var row = Shell.na_el('li', 'na-report__item');
            row.appendChild(Shell.na_el('span', 'na-badge ' + (item.level === 'error' ? 'na-badge--error' : 'na-badge--warn'), item.level === 'error' ? 'ERR' : 'WARN'));
            row.appendChild(Shell.na_el('span', 'na-report__text', item.text));
            list.appendChild(row);
        });
        if ((report.items || []).length) box.appendChild(list);

        var meta = Shell.na_el('div', 'na-kv');
        var row  = function (label, value) {
            var r = Shell.na_el('div', 'na-kv__row');
            r.appendChild(Shell.na_el('span', 'na-kv__label', label));
            r.appendChild(Shell.na_el('span', 'na-kv__value', value));
            meta.appendChild(r);
        };
        if (report.index) row('Index', (report.index.ok ? '' : 'Not written: ') + report.index.text);
        if (report.reason) row('Run', report.reason + (report.ranAt ? ', ' + report.ranAt : '') + (report.seconds ? ' (' + report.seconds + ' s)' : ''));
        if (report.python) row('Python', report.python);
        box.appendChild(meta);
    }

    function na_wire() {
        document.getElementById('na-validate-run').addEventListener('click', function () {
            if (!Bridge.na_call('validate', {})) Shell.na_set_status('Validate needs SketchUp: this is a preview of the page.', 'warn');
        });
    }

    Shell.na_on('state', function (state) { na_render(state ? state.validation : null); });
    Shell.na_on('validation', na_render);

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_wire);
    } else {
        na_wire();
    }

    window.Na__PainterlyAssets__ValidateUi = { na_render: na_render };
})();

// =============================================================================
// END OF FILE
// =============================================================================
