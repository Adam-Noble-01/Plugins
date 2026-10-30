// =============================================================================
// NA PAINTERLYNPR ASSETS - APP CORE - UI SYSTEM - MAIN SHELL
// =============================================================================
//
// FILE       : Na__PainterlyAssets__AppCore__UiSystem__MainShell__.js
// NAMESPACE  : window.Na__PainterlyAssets__Shell
//              window.Na__PainterlyAssets__Receive  (Ruby -> JS entry point)
// PURPOSE    : Routes Ruby's pushes to the tab scripts, owns the tabs, the
//              status bar, the loading overlay, the busy state, the in-dialog
//              confirm and the shared DOM and formatting helpers.
// CREATED    : 30-Oct-2026
//
// CHANNELS   : state | catalogue | selection | plan | authored | validation |
//              busy | status   (and 'tab' when a tab is shown, from here)
//
// =============================================================================

(function () {
    'use strict';

    var Shell        = {};
    var na_listeners = {};
    var na_state     = null;
    var na_confirm_action = null;

    // -------------------------------------------------------------------------
    // REGION | Subscriptions + Receive
    // -------------------------------------------------------------------------

    Shell.na_on = function (channel, handler) {
        (na_listeners[channel] = na_listeners[channel] || []).push(handler);
    };

    Shell.na_get_state = function () { return na_state; };

    function na_emit(channel, payload) {
        (na_listeners[channel] || []).forEach(function (handler) {
            try { handler(payload); }
            catch (err) { console.error('[Na__PainterlyAssets__Shell] ' + channel + ' handler failed:', err); }
        });
    }

    window.Na__PainterlyAssets__Receive = function (channel, payload) {
        if (channel === 'state') {
            na_state = payload;
            na_apply_state(payload);
        }
        if (channel === 'catalogue' && na_state)  { na_state.catalogue  = payload; }
        if (channel === 'validation' && na_state) { na_state.validation = payload; }
        if (channel === 'status') {
            Shell.na_loading_hide();
            Shell.na_set_status(payload.message, payload.level);
        }
        if (channel === 'busy') { na_set_busy(payload.busy, payload.label); }
        na_emit(channel, payload);
    };

    function na_apply_state(state) {
        var version = state && state.plugin ? state.plugin.version : '';
        Shell.na_text('na-brand-version', 'by Noble Architecture' + (version ? ', version ' + version : ''));
        if (!Shell.na_started && state && state.prefs) {
            Shell.na_started = true;
            Shell.na_activate_tab(state.prefs.tab || 'catalogue', false);
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Status Bar, Loading Overlay, Busy
    // -------------------------------------------------------------------------

    Shell.na_set_status = function (message, level) {
        var bar  = document.getElementById('na-status-bar');
        var text = document.getElementById('na-status-message');
        if (!bar || !text) return;
        text.textContent = message || '';
        bar.className = 'na-status-bar na-status-bar--' + (level || 'info');
        if (!message) bar.classList.add('na-hidden');
    };

    Shell.na_loading_show = function (title, status) {
        var overlay = document.getElementById('na-loading-overlay');
        if (!overlay) return;
        Shell.na_text('na-loading-title', title || 'Working...');
        Shell.na_text('na-loading-status', status || '');
        overlay.classList.remove('na-hidden');
    };

    Shell.na_loading_hide = function () {
        var overlay = document.getElementById('na-loading-overlay');
        if (overlay) overlay.classList.add('na-hidden');
    };

    // While PainterlyNPR's build utility runs, every button that would start
    // another run is held (the CSS reads body.na-busy); Ruby ends it on every
    // path, success or not.
    function na_set_busy(busy, label) {
        document.body.classList.toggle('na-busy', !!busy);
        if (busy && label) Shell.na_set_status(label, 'info');
    }

    Shell.na_is_busy = function () {
        return document.body.classList.contains('na-busy');
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Tabs
    // -------------------------------------------------------------------------

    Shell.na_activate_tab = function (tabId, remember) {
        var found = false;
        Array.prototype.forEach.call(document.querySelectorAll('.na-tab'), function (button) {
            var on = button.getAttribute('data-na-tab-id') === tabId;
            found = found || on;
            button.classList.toggle('na-tab-active', on);
            button.setAttribute('aria-selected', on ? 'true' : 'false');
        });
        if (!found) tabId = 'catalogue';
        Array.prototype.forEach.call(document.querySelectorAll('.na-tab-panel'), function (panel) {
            panel.classList.toggle('na-hidden', panel.getAttribute('data-na-tab-id') !== tabId);
        });
        if (remember !== false) window.Na__PainterlyAssets__Bridge.na_call('setPref', { key: 'tab', value: tabId });
        na_emit('tab', tabId);
    };

    function na_wire_tabs() {
        Array.prototype.forEach.call(document.querySelectorAll('.na-tab'), function (button) {
            button.addEventListener('click', function () { Shell.na_activate_tab(button.getAttribute('data-na-tab-id')); });
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | In-Dialog Confirm (Cancel first, the action last)
    // -------------------------------------------------------------------------

    // FUNCTION | Ask Before Something That Writes Many Files
    // @param options {{ title: string, text: string, confirm: string }}
    // @param onConfirm {Function} called only on the confirm button
    Shell.na_confirm = function (options, onConfirm) {
        Shell.na_text('na-confirm-title', options.title || 'Are you sure?');
        Shell.na_text('na-confirm-text', options.text || '');
        Shell.na_text('na-confirm-go', options.confirm || 'Continue');
        na_confirm_action = onConfirm;
        document.getElementById('na-confirm').classList.remove('na-hidden');
    };

    function na_wire_confirm() {
        var close = function () {
            na_confirm_action = null;                                                                    // <-- Cancel dispatches nothing
            document.getElementById('na-confirm').classList.add('na-hidden');
        };
        document.getElementById('na-confirm-cancel').addEventListener('click', close);
        document.getElementById('na-confirm-go').addEventListener('click', function () {
            var action = na_confirm_action;
            close();
            if (typeof action === 'function') action();
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | DOM and Formatting Helpers
    // -------------------------------------------------------------------------

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

    Shell.na_clear = function (element) {
        while (element && element.firstChild) element.removeChild(element.firstChild);
        return element;
    };

    // As the PainterlyNPR drawer shows it: millimetres under a metre.
    Shell.na_format_height = function (metres) {
        if (typeof metres !== 'number' || !isFinite(metres) || metres <= 0) return '';
        return metres < 1 ? Math.round(metres * 1000) + ' mm' : metres.toFixed(1) + ' m';
    };

    // PlantersAndPots -> Planters And Pots
    Shell.na_split_camel = function (text) {
        return String(text || '').replace(/([a-z])([A-Z])/g, '$1 $2');
    };

    // A row of <option>s; items are strings or { value, label }.
    Shell.na_fill_select = function (select, items, selected) {
        if (!select) return;
        Shell.na_clear(select);
        (items || []).forEach(function (item) {
            var value  = typeof item === 'object' && item !== null ? item.value : item;
            var label  = typeof item === 'object' && item !== null ? item.label : item;
            var option = Shell.na_el('option', null, label);
            option.value = value;
            if (value === selected) option.selected = true;
            select.appendChild(option);
        });
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Init
    // -------------------------------------------------------------------------

    function na_init() {
        na_wire_tabs();
        na_wire_confirm();
        window.Na__PainterlyAssets__Bridge.na_ready();
    }

    window.Na__PainterlyAssets__Shell = Shell;

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_init);
    } else {
        window.setTimeout(na_init, 0);
    }
})();

// =============================================================================
// END OF FILE
// =============================================================================
