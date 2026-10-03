// =============================================================================
// NA POINT CLOUD VIEWER - LAS IMPORT - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PointCloudViewer__LasImport__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PointCloudViewer__LasImport
// PURPOSE    : Import LAS panel on the View tab. Ruby reads the header and
//              pushes 'lasHeader'; this shows the report and the unit choice.
//              Import stays disabled until a unit is chosen - nothing is ever
//              assumed. Each unit option shows the real size it would give.
//
// =============================================================================

(function () {
    'use strict';

    var LasImport = {};
    var Shell  = window.Na__PointCloudViewer__Shell;
    var Bridge = window.Na__PointCloudViewer__Bridge;

    var na_header = null;
    var na_unit   = null;

    // -------------------------------------------------------------------------
    // REGION | Render
    // -------------------------------------------------------------------------

    function na_card() { return document.getElementById('na-las-import-card'); }

    function na_select_unit(key) {
        na_unit = key;
        var options = document.querySelectorAll('#na-las-unit-options .na-unit-option');
        Array.prototype.forEach.call(options, function (option) {
            option.classList.toggle('na-unit-option--active', option.getAttribute('data-na-unit') === key);
        });
        document.getElementById('na-las-import-go').disabled = !key;
    }

    function na_render_units(header) {
        var wrap = document.getElementById('na-las-unit-options');
        wrap.innerHTML = '';
        (header.unitOptions || []).forEach(function (unit) {
            var button = Shell.na_el('button', 'na-unit-option');
            button.type = 'button';
            button.setAttribute('data-na-unit', unit.key);
            button.appendChild(Shell.na_el('span', 'na-unit-option__label', unit.label));
            button.appendChild(Shell.na_el('span', 'na-unit-option__size', unit.sizeText));
            button.addEventListener('click', function () { na_select_unit(unit.key); });
            wrap.appendChild(button);
        });
    }

    LasImport.na_show = function (header) {
        na_header = header;
        Shell.na_text('na-las-file-name', header.fileName);
        Shell.na_stat_grid('na-las-report', header.rows || []);
        na_render_units(header);
        Shell.na_text('na-las-unit-note', header.unitNote || '');
        na_select_unit(header.suggestedUnit || null);
        na_card().classList.remove('na-hidden');
        if (window.Na_TabRouter) window.Na_TabRouter.na_activateTab('view');
        na_card().scrollIntoView({ block: 'nearest' });
        Shell.na_set_status('Check the report and choose the units, then press Import.', 'info');
    };

    LasImport.na_hide = function () {
        na_card().classList.add('na-hidden');
        na_header = null;
        na_unit = null;
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Wiring
    // -------------------------------------------------------------------------

    function na_wire() {
        document.getElementById('na-view-import-las').addEventListener('click', function () {
            Shell.na_set_status('Choose a LAS file...', 'info');
            Bridge.na_call('las_pick_file', {});
        });
        document.getElementById('na-las-import-cancel').addEventListener('click', function () {
            LasImport.na_hide();
            Shell.na_set_status('Import cancelled.', 'info');
        });
        document.getElementById('na-las-import-go').addEventListener('click', function () {
            if (!na_header || !na_unit) return;
            var payload = { path: na_header.path, sourceUnit: na_unit, headerMs: na_header.headerMs };
            var title = 'Importing ' + na_header.fileName;
            LasImport.na_hide();
            Bridge.na_call_after_paint('las_import_start', payload, title, 'Opening the LAS file...');
        });
    }

    // endregion ----------------------------------------------------------------

    Shell.na_on('lasHeader', LasImport.na_show);

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_wire);
    } else {
        na_wire();
    }

    window.Na__PointCloudViewer__LasImport = LasImport;
})();
