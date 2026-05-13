// =============================================================================
// NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - UI SHELL
// =============================================================================
//
// FILE       : Na__MeshDecimator__AppCore__UiShell__.js
// NAMESPACE  : window (functions are global so Ruby execute_script can call them)
// AUTHOR     : Adam Noble / Noble Architecture
// PURPOSE    : Handles all UI interactions for the Decimation tab.
//              Reads form options, dispatches to Ruby via the SketchUp bridge,
//              and handles result/error callbacks from Ruby.
//
// PUBLIC FUNCTIONS (called by HTML onclick / Ruby execute_script)
//   Na__MeshDecimator__Ui__Run()                   — read form, call Ruby
//   Na__MeshDecimator__Ui__OnComplete(resultJson)  — render 9-column results table
//   Na__MeshDecimator__Ui__OnError(errorJson)       — render error state
//   Na__MeshDecimator__Ui__OnGroupCount(countJson) — update group count bar
//   Na__MeshDecimator__Ui__ShowStatus(type, msg)   — update status bar message
//   Na__MeshDecimator__Ui__SetLoading(bool)        — toggle loading state
//
// TAB MODULE CONTRACT
//   Na_DecimationUI.na_mount()   — requests group count from Ruby
//   Na_DecimationUI.na_unmount() — no-op
//
// =============================================================================

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | SketchUp Bridge Guard
    // -------------------------------------------------------------------------

    function Na__MeshDecimator__Bridge__IsAvailable() {
        return typeof sketchup !== 'undefined';
    }

    function Na__MeshDecimator__Bridge__CallRuby(fnName, payload) {
        if (!Na__MeshDecimator__Bridge__IsAvailable()) {
            console.warn('[Na__MeshDecimator] SketchUp bridge not available — cannot call: ' + fnName);
            return false;
        }
        if (typeof sketchup[fnName] !== 'function') {
            console.warn('[Na__MeshDecimator] sketchup.' + fnName + ' is not registered');
            return false;
        }
        try {
            if (typeof payload === 'undefined') {
                sketchup[fnName]();
            } else {
                sketchup[fnName](JSON.stringify(payload));
            }
            return true;
        } catch (err) {
            console.error('[Na__MeshDecimator] sketchup.' + fnName + ' threw:', err);
            return false;
        }
    }

    // -------------------------------------------------------------------------
    // REGION | Form Option Reading
    // -------------------------------------------------------------------------

    function Na__MeshDecimator__Ui__ReadFormOptions() {
        return {
            percentage_decimation:            parseFloat(document.getElementById('na-opt-pct-decimation').value) || 25.0,
            maintain_border_edges:            document.getElementById('na-opt-border-edges').checked,
            preserve_material_boundary_edges: document.getElementById('na-opt-material-boundary').checked,
            weld_tolerance_mm:                parseFloat(document.getElementById('na-opt-weld-tolerance').value) || 0.10,
            process_nested_groups:            document.getElementById('na-opt-nested-groups').checked,
            smooth_rebuilt_edges:             document.getElementById('na-opt-smooth-edges').checked,
            max_seconds_per_group:            parseFloat(document.getElementById('na-opt-max-seconds').value) || 10.0,
            max_passes_per_group:             parseInt(document.getElementById('na-opt-max-passes').value, 10) || 4,
            max_candidate_edges_per_pass:     parseInt(document.getElementById('na-opt-max-candidates').value, 10) || 10000
        };
    }

    window.Na__MeshDecimator__Ui__ReadFormOptions = Na__MeshDecimator__Ui__ReadFormOptions;

    // -------------------------------------------------------------------------
    // REGION | Run
    // -------------------------------------------------------------------------

    function Na__MeshDecimator__Ui__Run() {
        var options = Na__MeshDecimator__Ui__ReadFormOptions();

        Na__MeshDecimator__Ui__SetLoading(true);
        Na__MeshDecimator__Ui__HideResults();
        Na__MeshDecimator__Ui__ShowStatus('info', 'Running decimation...');

        var sent = Na__MeshDecimator__Bridge__CallRuby('na_run_decimation', options);

        if (!sent) {
            Na__MeshDecimator__Ui__SetLoading(false);
            Na__MeshDecimator__Ui__ShowStatus('error', 'SketchUp bridge not available.');
        }
    }

    window.Na__MeshDecimator__Ui__Run = Na__MeshDecimator__Ui__Run;

    // -------------------------------------------------------------------------
    // REGION | Result Callbacks (called by Ruby via execute_script)
    // -------------------------------------------------------------------------

    function Na__MeshDecimator__Ui__OnComplete(resultJson) {
        Na__MeshDecimator__Ui__SetLoading(false);

        var result;
        try {
            result = typeof resultJson === 'string' ? JSON.parse(resultJson) : resultJson;
        } catch (e) {
            Na__MeshDecimator__Ui__ShowStatus('error', 'Could not parse result data.');
            return;
        }

        var report = result.report || [];
        Na__MeshDecimator__Ui__RenderResultsTable(report);
        Na__MeshDecimator__Ui__ShowStatus('success', 'Decimation complete — ' + report.length + ' group(s) processed.');
    }

    window.Na__MeshDecimator__Ui__OnComplete = Na__MeshDecimator__Ui__OnComplete;

    function Na__MeshDecimator__Ui__OnError(errorJson) {
        Na__MeshDecimator__Ui__SetLoading(false);

        var err;
        try {
            err = typeof errorJson === 'string' ? JSON.parse(errorJson) : errorJson;
        } catch (e) {
            err = { error: String(errorJson) };
        }

        Na__MeshDecimator__Ui__RenderError(err.error || 'An unknown error occurred.');
        Na__MeshDecimator__Ui__ShowStatus('error', err.error || 'Decimation failed.');
    }

    window.Na__MeshDecimator__Ui__OnError = Na__MeshDecimator__Ui__OnError;

    function Na__MeshDecimator__Ui__OnGroupCount(countJson) {
        var data;
        try {
            data = typeof countJson === 'string' ? JSON.parse(countJson) : countJson;
        } catch (e) { return; }

        var count  = data.count || 0;
        var el     = document.getElementById('na-group-count-value');
        if (el) el.textContent = count + (count === 1 ? ' group' : ' groups');

        var runBtn = document.getElementById('na-btn-run');
        if (runBtn) runBtn.disabled = count === 0;
    }

    window.Na__MeshDecimator__Ui__OnGroupCount = Na__MeshDecimator__Ui__OnGroupCount;

    // -------------------------------------------------------------------------
    // REGION | Status Bar
    // -------------------------------------------------------------------------

    function Na__MeshDecimator__Ui__ShowStatus(type, message) {
        var el = document.getElementById('na-status-message');
        if (!el) return;

        el.textContent = message || '';
        el.className   = 'na-status-bar__message';

        if (type === 'error')   el.classList.add('na-status-bar__message--error');
        if (type === 'success') el.classList.add('na-status-bar__message--success');
        if (type === 'info')    el.classList.add('na-status-bar__message--info');
    }

    window.Na__MeshDecimator__Ui__ShowStatus = Na__MeshDecimator__Ui__ShowStatus;

    // -------------------------------------------------------------------------
    // REGION | Loading State
    // -------------------------------------------------------------------------

    function Na__MeshDecimator__Ui__SetLoading(isLoading) {
        var spinner = document.getElementById('na-run-spinner');
        var runBtn  = document.getElementById('na-btn-run');

        if (isLoading) {
            document.body.classList.add('na-is-loading');
            if (spinner) spinner.classList.add('na-spinner--visible');
            if (runBtn)  runBtn.disabled = true;
        } else {
            document.body.classList.remove('na-is-loading');
            if (spinner) spinner.classList.remove('na-spinner--visible');
            if (runBtn)  runBtn.disabled = false;
        }
    }

    window.Na__MeshDecimator__Ui__SetLoading = Na__MeshDecimator__Ui__SetLoading;

    // -------------------------------------------------------------------------
    // REGION | Results Rendering
    // -------------------------------------------------------------------------

    function Na__MeshDecimator__Ui__HideResults() {
        var panel = document.getElementById('na-results-panel');
        if (panel) panel.classList.remove('na-results-panel--visible');
    }

    // Renders the 9-column results table:
    // Group Name | Input Tri | Input Faces | Input Edges |
    // Output Tri | Output Faces | Output Edges | Reduced % | Status
    function Na__MeshDecimator__Ui__RenderResultsTable(report) {
        var panel = document.getElementById('na-results-panel');
        var tbody = document.getElementById('na-results-tbody');
        if (!panel || !tbody) return;

        tbody.innerHTML = '';

        report.forEach(function (row) {
            var tr = document.createElement('tr');

            var statusClass = row.status === 'complete'
                ? 'na-cell--status-ok'
                : 'na-cell--status-warn';

            tr.innerHTML =
                '<td class="na-cell--name">'   + na_escape_html(row.group_name    || '') + '</td>' +
                '<td class="na-cell--number">' + (row.source_triangles   || 0) + '</td>' +
                '<td class="na-cell--number">' + (row.input_faces        || 0) + '</td>' +
                '<td class="na-cell--number">' + (row.input_edges        || 0) + '</td>' +
                '<td class="na-cell--number">' + (row.result_triangles   || 0) + '</td>' +
                '<td class="na-cell--number">' + (row.output_faces       || 0) + '</td>' +
                '<td class="na-cell--number">' + (row.output_edges       || 0) + '</td>' +
                '<td class="na-cell--number">' + (row.actual_pct         || 0) + '%</td>' +
                '<td class="' + statusClass + '">' + na_escape_html(row.status || '') + '</td>';

            tbody.appendChild(tr);
        });

        panel.classList.add('na-results-panel--visible');
    }

    function Na__MeshDecimator__Ui__RenderError(message) {
        var panel = document.getElementById('na-results-panel');
        var tbody = document.getElementById('na-results-tbody');
        if (!panel || !tbody) return;

        tbody.innerHTML = '<tr><td colspan="9"><div class="na-results-error">' + na_escape_html(message) + '</div></td></tr>';
        panel.classList.add('na-results-panel--visible');
    }

    function na_escape_html(str) {
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    // -------------------------------------------------------------------------
    // REGION | Tab Module — Na_DecimationUI
    // -------------------------------------------------------------------------

    window.Na_DecimationUI = {
        na_mount: function () {
            Na__MeshDecimator__Bridge__CallRuby('na_request_group_count');
        },
        na_unmount: function () {}
    };

    // -------------------------------------------------------------------------
    // REGION | Bootstrap
    // -------------------------------------------------------------------------

    function Na__MeshDecimator__Ui__Init() {
        Na__MeshDecimator__Bridge__CallRuby('na_request_group_count');
    }

    window.Na__MeshDecimator__Bridge__RequestGroupCount = function () {
        Na__MeshDecimator__Bridge__CallRuby('na_request_group_count');
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na__MeshDecimator__Ui__Init);
    } else {
        Na__MeshDecimator__Ui__Init();
    }

})();
