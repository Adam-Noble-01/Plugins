// =============================================================================
// NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - STATISTICS TAB UI LOGIC
// =============================================================================
//
// FILE       : Na__MeshDecimator__Statistics__UiLogic__.js
// NAMESPACE  : window.Na_StatisticsUI
// AUTHOR     : Adam Noble / Noble Architecture
// PURPOSE    : Owns the Statistics tab.  Accumulates results across every
//              Run Decimation call so the user can compare runs as they work.
//              Each run appends rows; a Purge Stats button resets the table.
//
// TAB MODULE CONTRACT (Na_TabRouter convention)
//   Na_StatisticsUI.na_mount()   — renders body into #na-statistics-body
//   Na_StatisticsUI.na_unmount() — clears DOM only; data survives
//
// PUBLIC API (called by UiShell + button onclick)
//   Na_StatisticsUI.na_add_run_result(report_array) — append rows from one run
//   Na__MeshDecimator__Statistics__Purge()          — global onclick target
//
// =============================================================================

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | State
    // -------------------------------------------------------------------------

    var NA_BODY_ID       = 'na-statistics-body';
    var na_run_counter   = 0;
    var na_rows          = [];  // { run, engine, elapsed_seconds, group_name,
                                //   source_triangles, input_faces, input_edges, result_triangles, output_faces,
                                //   output_edges, actual_pct, status }

    // -------------------------------------------------------------------------
    // REGION | HTML Escaping
    // -------------------------------------------------------------------------

    function na_esc(str) {
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function na_format_elapsed_time(seconds) {
        var totalSeconds = Number(seconds) || 0;
        if (totalSeconds > 0 && totalSeconds < 1) return '&lt;00:01';

        var rounded = Math.round(totalSeconds);
        var minutes = Math.floor(rounded / 60);
        var secondsPart = rounded % 60;

        return String(minutes).padStart(2, '0') + ':' + String(secondsPart).padStart(2, '0');
    }

    // -------------------------------------------------------------------------
    // REGION | Table Rendering
    // -------------------------------------------------------------------------

    function na_build_table_html() {
        if (na_rows.length === 0) {
            return '<div class="na-statistics-empty">No decimation runs recorded yet. Run Decimation to populate this tab.</div>';
        }

        var html = '<table class="na-results-table">';
        html += '<thead><tr>';
        html += '<th>Run</th>';
        html += '<th>Engine</th>';
        html += '<th>Time</th>';
        html += '<th>Group Name</th>';
        html += '<th>Input Tri</th>';
        html += '<th>Input Faces</th>';
        html += '<th>Input Edges</th>';
        html += '<th>Output Tri</th>';
        html += '<th>Output Faces</th>';
        html += '<th>Output Edges</th>';
        html += '<th>Reduced</th>';
        html += '<th>Status</th>';
        html += '</tr></thead>';
        html += '<tbody>';

        na_rows.forEach(function (row) {
            var statusClass = row.status === 'complete' ? 'na-cell--status-ok' : 'na-cell--status-warn';
            html += '<tr>';
            html += '<td class="na-cell--run">#' + row.run + '</td>';
            html += '<td>' + na_esc(row.engine || 'Ruby') + '</td>';
            html += '<td class="na-cell--number" title="' + (row.elapsed_seconds || 0) + ' seconds">' + na_format_elapsed_time(row.elapsed_seconds) + '</td>';
            html += '<td class="na-cell--name">' + na_esc(row.group_name || '') + '</td>';
            html += '<td class="na-cell--number">' + (row.source_triangles  || 0) + '</td>';
            html += '<td class="na-cell--number">' + (row.input_faces       || 0) + '</td>';
            html += '<td class="na-cell--number">' + (row.input_edges       || 0) + '</td>';
            html += '<td class="na-cell--number">' + (row.result_triangles  || 0) + '</td>';
            html += '<td class="na-cell--number">' + (row.output_faces      || 0) + '</td>';
            html += '<td class="na-cell--number">' + (row.output_edges      || 0) + '</td>';
            html += '<td class="na-cell--number">' + (row.actual_pct        || 0) + '%</td>';
            html += '<td class="' + statusClass + '">' + na_esc(row.status || '') + '</td>';
            html += '</tr>';
        });

        html += '</tbody></table>';
        return html;
    }

    function na_count_runs() {
        if (na_rows.length === 0) return 0;
        return na_run_counter;
    }

    // -------------------------------------------------------------------------
    // REGION | Body Rendering
    // -------------------------------------------------------------------------

    function na_render_into_body(body) {
        var runCount  = na_count_runs();
        var rowCount  = na_rows.length;

        var headerHtml =
            '<div class="na-statistics-header">' +
            '<span class="na-statistics-run-count">' +
            '<strong>' + runCount + '</strong> run' + (runCount === 1 ? '' : 's') +
            ' &nbsp;·&nbsp; <strong>' + rowCount + '</strong> group' + (rowCount === 1 ? '' : 's') +
            '</span>' +
            '<button type="button" class="na-btn na-btn--danger" onclick="Na__MeshDecimator__Statistics__Purge()">Purge Stats</button>' +
            '</div>';

        var tableHtml =
            '<div class="na-card na-statistics-card">' +
            na_build_table_html() +
            '</div>';

        body.innerHTML = headerHtml + tableHtml;
    }

    function na_refresh_body() {
        var body = document.getElementById(NA_BODY_ID);
        if (!body) return;
        na_render_into_body(body);
    }

    // -------------------------------------------------------------------------
    // REGION | Public API — Tab Module Contract
    // -------------------------------------------------------------------------

    var Na_StatisticsUI = {};

    Na_StatisticsUI.na_mount = function () {
        var body = document.getElementById(NA_BODY_ID);
        if (!body) return;
        na_render_into_body(body);
    };

    Na_StatisticsUI.na_unmount = function () {
        var body = document.getElementById(NA_BODY_ID);
        if (body) body.innerHTML = '';
    };

    // -------------------------------------------------------------------------
    // REGION | Public API — Data Accumulation
    // -------------------------------------------------------------------------

    Na_StatisticsUI.na_add_run_result = function (report_array) {
        if (!Array.isArray(report_array) || report_array.length === 0) return;
        na_run_counter += 1;
        var run = na_run_counter;
        report_array.forEach(function (row) {
            na_rows.push({
                run:              run,
                engine:           row.engine           || 'Ruby',
                elapsed_seconds:  row.elapsed_seconds  || 0,
                group_name:       row.group_name       || '',
                source_triangles: row.source_triangles || 0,
                input_faces:      row.input_faces      || 0,
                input_edges:      row.input_edges      || 0,
                result_triangles: row.result_triangles || 0,
                output_faces:     row.output_faces     || 0,
                output_edges:     row.output_edges     || 0,
                actual_pct:       row.actual_pct       || 0,
                status:           row.status           || ''
            });
        });
        na_refresh_body();
    };

    Na_StatisticsUI.na_purge = function () {
        na_run_counter = 0;
        na_rows        = [];
        na_refresh_body();
    };

    // -------------------------------------------------------------------------
    // REGION | Global onclick Target (HTML button)
    // -------------------------------------------------------------------------

    window.Na__MeshDecimator__Statistics__Purge = function () {
        Na_StatisticsUI.na_purge();
    };

    window.Na_StatisticsUI = Na_StatisticsUI;

    // -------------------------------------------------------------------------

})();
