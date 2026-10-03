// =============================================================================
// NA POINT CLOUD VIEWER - APP CORE - UI SYSTEM - MAIN SHELL
// =============================================================================
//
// FILE       : Na__PointCloudViewer__AppCore__UiSystem__MainShell__.js
// NAMESPACE  : window.Na__PointCloudViewer__Shell
//              window.Na__PointCloudViewer__Receive  (Ruby -> JS entry point)
// PURPOSE    : Routes Ruby pushes to subscribers, owns the status bar, the
//              full-dialog loading overlay and shared formatting helpers.
//
// CHANNELS   : state | lasHeader | progress | jobFinished | status
//
// =============================================================================

(function () {
    'use strict';

    var Shell          = {};
    var na_listeners   = {};
    var na_last_state  = null;

    // -------------------------------------------------------------------------
    // REGION | Subscriptions + Receive
    // -------------------------------------------------------------------------

    Shell.na_on = function (channel, handler) {
        (na_listeners[channel] = na_listeners[channel] || []).push(handler);
    };

    Shell.na_get_state = function () { return na_last_state; };

    function na_emit(channel, payload) {
        (na_listeners[channel] || []).forEach(function (handler) {
            try { handler(payload); }
            catch (err) { console.error('[Na__PointCloudViewer__Shell] ' + channel + ' handler failed:', err); }
        });
    }

    window.Na__PointCloudViewer__Receive = function (channel, payload) {
        if (channel === 'state') { na_last_state = payload; }
        if (channel === 'progress')    { na_on_progress(payload); }
        if (channel === 'jobFinished') { na_on_job_finished(payload); }
        if (channel === 'status')      { Shell.na_set_status(payload.message, payload.level); }
        na_emit(channel, payload);
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Status Bar
    // -------------------------------------------------------------------------

    Shell.na_set_status = function (message, level) {
        var bar = document.getElementById('na-status-bar');
        var text = document.getElementById('na-status-message');
        if (!bar || !text) return;
        text.textContent = message || '';
        bar.className = 'na-status-bar na-status-bar--' + (level || 'info');
        if (!message) bar.classList.add('na-hidden');
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Loading Overlay
    // -------------------------------------------------------------------------

    Shell.na_loading_show = function (title, status, percent) {
        var overlay = document.getElementById('na-loading-overlay');
        if (!overlay) return;
        document.getElementById('na-loading-title').textContent  = title || 'Working...';
        document.getElementById('na-loading-status').textContent = status || '';
        na_set_percent(percent);
        document.getElementById('na-loading-cancel').disabled = false;
        overlay.classList.remove('na-hidden');
    };

    Shell.na_loading_hide = function () {
        var overlay = document.getElementById('na-loading-overlay');
        if (overlay) overlay.classList.add('na-hidden');
    };

    // Indeterminate (striped) when the percentage is not honestly measurable.
    function na_set_percent(percent) {
        var progress = document.getElementById('na-loading-progress');
        var bar      = document.getElementById('na-loading-bar');
        var label    = document.getElementById('na-loading-percent');
        var known    = typeof percent === 'number' && isFinite(percent);
        progress.classList.toggle('na-progress--indeterminate', !known);
        bar.style.width   = known ? Math.max(0, Math.min(100, percent)) + '%' : '35%';
        label.textContent = known ? Math.round(percent) + '%' : '';
    }

    function na_on_progress(payload) {
        Shell.na_loading_show(payload.title, payload.status, payload.percent);
    }

    function na_on_job_finished(payload) {
        Shell.na_loading_hide();
        var level = payload.outcome === 'done' ? 'success' : (payload.outcome === 'cancelled' ? 'warn' : 'error');
        if (payload.message) Shell.na_set_status(payload.message, level);
    }

    function na_wire_cancel() {
        var cancel = document.getElementById('na-loading-cancel');
        if (!cancel) return;
        cancel.addEventListener('click', function () {
            cancel.disabled = true;
            document.getElementById('na-loading-status').textContent = 'Cancelling after the current step...';
            window.Na__PointCloudViewer__Bridge.na_call('job_cancel', {});
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Formatting Helpers
    // -------------------------------------------------------------------------

    Shell.na_format_int = function (value) {
        if (value === null || value === undefined || isNaN(value)) return '';
        return Math.round(value).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    };

    Shell.na_text = function (id, text) {
        var element = document.getElementById(id);
        if (element) element.textContent = text;
    };

    // Plain DOM builder: keeps tab code free of innerHTML string escaping.
    Shell.na_el = function (tag, className, text) {
        var element = document.createElement(tag);
        if (className) element.className = className;
        if (text !== undefined && text !== null) element.textContent = text;
        return element;
    };

    Shell.na_stat_grid = function (containerId, rows) {
        var grid = document.getElementById(containerId);
        if (!grid) return;
        grid.innerHTML = '';
        rows.forEach(function (row) {
            grid.appendChild(Shell.na_el('span', 'na-stat-grid__label', row[0]));
            grid.appendChild(Shell.na_el('span', 'na-stat-grid__value', row[1]));
        });
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Init
    // -------------------------------------------------------------------------

    function na_init() {
        na_wire_cancel();
        window.Na__PointCloudViewer__Bridge.na_ready();
    }

    window.Na__PointCloudViewer__Shell = Shell;

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_init);
    } else {
        window.setTimeout(na_init, 0);
    }
})();
