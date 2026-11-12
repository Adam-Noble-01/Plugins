// =============================================================================
// NA AGENT OUTLINER - UI SYSTEM - MAIN SHELL
// =============================================================================
//
// FILE       : Na__AgentOutliner__UiSystem__MainShell__.js
// NAMESPACE  : window.Na__AgentOutliner__Shell
//              window.Na__AgentOutliner__Receive      (Ruby -> JS entry point)
//              window.Na__AgentOutliner__ReceivePart  (a big payload, in parts)
// MODULE     : Shell (IIFE)
// AUTHOR     : Noble Architecture
// PURPOSE    : Routes Ruby's pushes to the tab scripts; owns the tabs, the
//              header chips, the status bar, the in-dialog confirm and prompt,
//              the copy-to-clipboard path and the shared DOM, time and colour
//              helpers every other script uses
// CREATED    : 10-Nov-2026
//
// CHANNELS   : state | snapshot | delta | selection | tags | thread | history |
//              status | log | seen | model | standardsIssues | icons (0.1.15)
//              (and 'tab' when a tab is shown, from here)
//
// =============================================================================

(function () {
    'use strict';

    var Shell        = {};
    var na_listeners = {};
    var na_state     = null;
    var na_parts     = {};
    var na_confirm_action = null;
    var na_prompt_action  = null;
    var na_status_timer   = null;
    var na_toast_timer    = null;

    // -------------------------------------------------------------------------
    // REGION | Subscriptions and Receive
    // -------------------------------------------------------------------------

    // FUNCTION | Listen to a Channel
    // @param channel {string}
    // @param handler {Function}
    Shell.na_on = function (channel, handler) {
        (na_listeners[channel] = na_listeners[channel] || []).push(handler);
    };

    Shell.na_get_state = function () { return na_state; };

    function na_emit(channel, payload) {
        (na_listeners[channel] || []).forEach(function (handler) {
            try { handler(payload); }
            catch (err) { console.error('[Na__AgentOutliner__Shell] ' + channel + ' handler failed:', err); }
        });
    }
    Shell.na_emit = na_emit;

    window.Na__AgentOutliner__Receive = function (channel, payload) {
        if (channel === 'state') {
            na_state = payload;
            na_apply_state(payload);
        }
        if (channel === 'icons') na_set_icons(payload);
        if (channel === 'status') Shell.na_set_status(payload.message, payload.level);
        if (channel === 'toast') Shell.na_toast(payload.message, payload.level);
        if (channel === 'snapshot' && payload && payload.model) na_apply_model(payload.model);
        if (channel === 'model') na_apply_model(payload);
        na_emit(channel, payload);
    };

    // A payload over Ruby's chunk size arrives as numbered parts.
    window.Na__AgentOutliner__ReceivePart = function (channel, index, total, text) {
        var bucket = na_parts[channel];
        if (!bucket || bucket.total !== total || index === 0) bucket = na_parts[channel] = { total: total, parts: [], got: 0 };
        if (bucket.parts[index] === undefined) bucket.got += 1;
        bucket.parts[index] = text;
        if (bucket.got < total) return;
        delete na_parts[channel];
        var payload;
        try { payload = JSON.parse(bucket.parts.join('')); }
        catch (err) {
            console.error('[Na__AgentOutliner__Shell] a ' + channel + ' payload did not join:', err);
            Shell.na_set_status('The model data arrived damaged: press Refresh.', 'error');
            return;
        }
        window.Na__AgentOutliner__Receive(channel, payload);
    };

    function na_apply_state(state) {
        var version = state && state.version ? state.version : '';
        Shell.na_text('na-brand-version', 'by Noble Architecture' + (version ? ', version ' + version : ''));
        na_apply_mcp(state ? state.mcp : null);
        na_apply_grading(state && state.settings ? state.settings.grading : null);
        if (!Shell.na_started && state) {
            Shell.na_started = true;
            var ui = state.ui || {};
            Shell.na_activate_tab(ui.tab || 'outliner', false);
        }
    }

    function na_apply_model(model) {
        var chip = document.getElementById('na-model-chip');
        if (!chip) return;
        if (!model) { chip.textContent = 'No model'; chip.title = ''; return; }
        chip.textContent = model.title + (model.modified ? ' *' : '');
        chip.title = model.path ? model.path : 'Not saved yet: its change history is kept from its first save.';
    }

    function na_apply_mcp(mcp) {
        var chip = document.getElementById('na-mcp-chip');
        if (!chip) return;
        var on = mcp && mcp.loaded && mcp.running;
        chip.className = 'na-mcp-chip ' + (on ? (mcp.tools ? 'na-mcp-chip--on' : 'na-mcp-chip--partial') : 'na-mcp-chip--off');
        chip.textContent = on ? (mcp.tools ? 'Agent bridge on' : 'Agent bridge on (no outliner tools)') : 'Agent bridge off';
        chip.title = on
            ? 'Na SketchUp MCP ' + (mcp.version || '') + (mcp.tools ? ': agents can use agent_outliner and agent_outliner_edit.' : ': update the MCP plugin to give agents the outliner tools.')
            : 'The Na SketchUp MCP is not running in this SketchUp, so no agent can reach the model.';
    }

    // The two actor colours become CSS variables every row reads.
    function na_apply_grading(grading) {
        if (!grading) return;
        var root = document.documentElement;
        if (grading.agent_colour) root.style.setProperty('--na-agent', grading.agent_colour);
        if (grading.user_colour)  root.style.setProperty('--na-user', grading.user_colour);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Status Bar
    // -------------------------------------------------------------------------

    // FUNCTION | Show a Line on the Status Bar (info lines fade after a while)
    // @param message {string}
    // @param level   {string} info | success | warn | error
    Shell.na_set_status = function (message, level) {
        var bar  = document.getElementById('na-status-bar');
        var text = document.getElementById('na-status-message');
        if (!bar || !text) return;
        text.textContent = message || '';
        bar.className = 'na-status-bar na-status-bar--' + (level || 'info');
        if (!message) bar.classList.add('na-hidden');
        if (na_status_timer) window.clearTimeout(na_status_timer);
        if (message && (level === 'info' || level === 'success')) {
            na_status_timer = window.setTimeout(function () { bar.classList.add('na-status-bar--quiet'); }, 9000);
        }
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Tabs
    // -------------------------------------------------------------------------

    // FUNCTION | Show a Tab
    // @param tabId    {string} outliner | configure | settings
    // @param remember {boolean} false when restoring the remembered tab
    Shell.na_activate_tab = function (tabId, remember) {
        var found = false;
        Array.prototype.forEach.call(document.querySelectorAll('.na-tab'), function (button) {
            var on = button.getAttribute('data-na-tab-id') === tabId;
            found = found || on;
            button.classList.toggle('na-tab-active', on);
            button.setAttribute('aria-selected', on ? 'true' : 'false');
        });
        if (!found) return Shell.na_activate_tab('outliner', remember);
        Array.prototype.forEach.call(document.querySelectorAll('.na-tab-panel'), function (panel) {
            panel.classList.toggle('na-hidden', panel.getAttribute('data-na-tab-id') !== tabId);
        });
        if (remember !== false) Shell.na_set_pref('tab', tabId);
        na_emit('tab', tabId);
    };

    function na_wire_tabs() {
        Array.prototype.forEach.call(document.querySelectorAll('.na-tab'), function (button) {
            button.addEventListener('click', function () { Shell.na_activate_tab(button.getAttribute('data-na-tab-id')); });
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Remembered Preferences (debounced: one write per burst)
    // -------------------------------------------------------------------------

    var na_pref_timers = {};

    // FUNCTION | Remember a Piece of Dialog State on This PC
    // @param key   {string}
    // @param value {*}
    Shell.na_set_pref = function (key, value) {
        if (na_state) { na_state.ui = na_state.ui || {}; na_state.ui[key] = value; }
        if (na_pref_timers[key]) window.clearTimeout(na_pref_timers[key]);
        na_pref_timers[key] = window.setTimeout(function () {
            delete na_pref_timers[key];
            window.Na__AgentOutliner__Bridge.na_call('setPref', { key: key, value: value });
        }, 450);
    };

    Shell.na_get_pref = function (key, fallback) {
        var ui = na_state && na_state.ui ? na_state.ui : {};
        return ui[key] === undefined || ui[key] === null ? fallback : ui[key];
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | In-Dialog Confirm and Prompt (Cancel first, the action last)
    // -------------------------------------------------------------------------

    // FUNCTION | Ask Before Something That Cannot Be Taken Back Easily
    // @param options   {{ title: string, text: string, confirm: string, danger: boolean }}
    // @param onConfirm {Function} called only on the confirm button
    Shell.na_confirm = function (options, onConfirm) {
        Shell.na_text('na-confirm-title', options.title || 'Are you sure?');
        Shell.na_text('na-confirm-text', options.text || '');
        var go = document.getElementById('na-confirm-go');
        go.textContent = options.confirm || 'Continue';
        go.className = options.danger ? 'naButton naButton--danger' : 'naButton';
        na_confirm_action = onConfirm;
        document.getElementById('na-confirm').classList.remove('na-hidden');
        go.focus();
    };

    // FUNCTION | Ask for a Line or a Paragraph of Text
    // @param options  {{ title, label, value, placeholder, confirm, multiline, hint, extra }}
    // @param onAnswer {Function(text, extraChecked)}
    Shell.na_prompt = function (options, onAnswer) {
        Shell.na_text('na-prompt-title', options.title || '');
        Shell.na_text('na-prompt-label', options.label || '');
        Shell.na_text('na-prompt-hint', options.hint || '');
        var line = document.getElementById('na-prompt-input');
        var area = document.getElementById('na-prompt-area');
        var field = options.multiline ? area : line;
        line.classList.toggle('na-hidden', !!options.multiline);
        area.classList.toggle('na-hidden', !options.multiline);
        field.value = options.value || '';
        field.placeholder = options.placeholder || '';
        var extra = document.getElementById('na-prompt-extra');
        var extraBox = document.getElementById('na-prompt-extra-box');
        extra.classList.toggle('na-hidden', !options.extra);
        extraBox.checked = false;
        Shell.na_text('na-prompt-extra-label', options.extra || '');
        Shell.na_text('na-prompt-go', options.confirm || 'Save');
        na_prompt_action = function () { onAnswer(field.value, extraBox.checked); };
        document.getElementById('na-prompt').classList.remove('na-hidden');
        window.setTimeout(function () { field.focus(); field.select(); }, 0);
    };

    function na_wire_modals() {
        var closeConfirm = function () {
            na_confirm_action = null;                                                    // <-- Cancel dispatches nothing
            document.getElementById('na-confirm').classList.add('na-hidden');
        };
        document.getElementById('na-confirm-cancel').addEventListener('click', closeConfirm);
        document.getElementById('na-confirm-go').addEventListener('click', function () {
            var action = na_confirm_action;
            closeConfirm();
            if (typeof action === 'function') action();
        });

        var closePrompt = function () {
            na_prompt_action = null;
            document.getElementById('na-prompt').classList.add('na-hidden');
        };
        var goPrompt = function () {
            var action = na_prompt_action;
            closePrompt();
            if (typeof action === 'function') action();
        };
        document.getElementById('na-prompt-cancel').addEventListener('click', closePrompt);
        document.getElementById('na-prompt-go').addEventListener('click', goPrompt);
        document.getElementById('na-prompt-input').addEventListener('keydown', function (event) {
            if (event.key === 'Enter') { event.preventDefault(); goPrompt(); }
            if (event.key === 'Escape') { event.preventDefault(); closePrompt(); }
        });
        document.getElementById('na-prompt-area').addEventListener('keydown', function (event) {
            if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) { event.preventDefault(); goPrompt(); }
            if (event.key === 'Escape') { event.preventDefault(); closePrompt(); }
        });
        document.addEventListener('keydown', function (event) {
            if (event.key !== 'Escape') return;
            if (!document.getElementById('na-confirm').classList.contains('na-hidden')) closeConfirm();
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Clipboard
    // -------------------------------------------------------------------------

    // FUNCTION | Copy Text: the page first, then Ruby's clip.exe as a fallback
    // @param text    {string}
    // @param message {string} the status line on success
    // 0.1.13: every copy also says so in a toast. Through Ruby (the last
    // resort) the toast comes back from Ruby once clip has the text.
    Shell.na_copy = function (text, message) {
        var done = function () {
            Shell.na_set_status(message || 'Copied.', 'success');
            Shell.na_toast(message || 'Copied.', 'success');
        };
        var fallback = function () {
            if (na_copy_with_textarea(text)) return done();
            window.Na__AgentOutliner__Bridge.na_call('copyText', { text: text, message: message || '' });
        };
        try {
            if (navigator.clipboard && window.isSecureContext) {
                navigator.clipboard.writeText(text).then(done, fallback);
                return;
            }
        } catch (err) { /* fall through to the older route */ }
        fallback();
    };

    // FUNCTION | A Short Note That Fades Away (0.1.13)
    // @param message {string}
    // @param level   {string} success (a tick) or warn (an exclamation mark)
    Shell.na_toast = function (message, level) {
        var toast = document.getElementById('na-toast');
        if (!toast) {
            toast = document.createElement('div');
            toast.id = 'na-toast';
            toast.setAttribute('role', 'status');
            toast.setAttribute('aria-live', 'polite');
            document.body.appendChild(toast);
        }
        toast.className = 'na-toast na-toast--' + (level === 'warn' ? 'warn' : 'success');
        toast.textContent = '';
        toast.appendChild(Shell.na_el('span', 'na-toast__mark', level === 'warn' ? '!' : '\u2713'));
        toast.appendChild(document.createTextNode(String(message || '')));
        void toast.offsetWidth;                                                     // restart the fade when one toast follows another
        toast.classList.add('na-toast--shown');
        window.clearTimeout(na_toast_timer);
        na_toast_timer = window.setTimeout(function () { toast.classList.remove('na-toast--shown'); }, 2600);
    };

    function na_copy_with_textarea(text) {
        var area = document.createElement('textarea');
        area.value = text;
        area.setAttribute('readonly', '');
        area.style.position = 'fixed';
        area.style.left = '-9999px';
        document.body.appendChild(area);
        area.select();
        var ok = false;
        try { ok = document.execCommand('copy'); } catch (err) { ok = false; }
        document.body.removeChild(area);
        return ok;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    Shell.na_text = function (id, text) {
        var element = document.getElementById(id);
        if (element) element.textContent = text;
    };

    // HELPER FUNCTION | Make an Element (no innerHTML: names are never parsed as markup)
    // @param tag       {string}
    // @param className {string}
    // @param text      {string}
    // @return {HTMLElement}
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

    Shell.na_button = function (label, className, onClick, title) {
        var button = Shell.na_el('button', className || 'naButtonSecondary na-button--small', label);
        button.type = 'button';
        if (title) button.title = title;
        if (onClick) button.addEventListener('click', onClick);
        return button;
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
            if (String(value) === String(selected)) option.selected = true;
            select.appendChild(option);
        });
    };

    // Long names joined with __ have no natural break: offer one after each run.
    Shell.na_breakable = function (element, text) {
        Shell.na_clear(element);
        String(text || '').split(/(__)/).forEach(function (part) {
            element.appendChild(document.createTextNode(part));
            if (part === '__') element.appendChild(document.createElement('wbr'));
        });
        return element;
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Icons (0.1.15: Adam, "add icons the UI is too textual based")
    // -------------------------------------------------------------------------
    // Ruby sends the SVGs in UiIcons__DialogIcons__AgentOutliner once a page
    // ('icons': { Flag: '<svg ...>', ... }). Any element with data-na-icon gets
    // its picture inline, so CSS colours it (currentColor). Parsed as SVG and
    // imported, never set as innerHTML. A missing icon leaves the element
    // empty: the button keeps its label, aria-label and tooltip.

    var na_icon_text = {};
    var na_icon_parsed = {};

    function na_set_icons(icons) {
        na_icon_text = icons || {};
        na_icon_parsed = {};
        Shell.na_paint_icons(document);
    }

    function na_icon_node(name) {
        if (!na_icon_text[name]) return null;
        if (!na_icon_parsed[name]) {
            try {
                var doc = new DOMParser().parseFromString(na_icon_text[name], 'image/svg+xml');
                var svg = doc.documentElement;
                if (!svg || svg.nodeName.toLowerCase() !== 'svg' || doc.getElementsByTagName('parsererror').length) return null;
                svg.removeAttribute('width');
                svg.removeAttribute('height');
                svg.setAttribute('aria-hidden', 'true');
                svg.setAttribute('focusable', 'false');
                na_icon_parsed[name] = svg;
            } catch (err) {
                return null;
            }
        }
        return document.importNode(na_icon_parsed[name], true);
    }

    // FUNCTION | Fill Every Empty [data-na-icon] Inside an Element
    // @param root {Element|Document}
    Shell.na_paint_icons = function (root) {
        if (!root || !root.querySelectorAll) return;
        var holders = root.querySelectorAll('[data-na-icon]');
        if (root.getAttribute && root.getAttribute('data-na-icon')) holders = [root].concat(Array.prototype.slice.call(holders));
        Array.prototype.forEach.call(holders, function (holder) {
            var name = holder.getAttribute('data-na-icon');
            if (holder.getAttribute('data-na-icon-painted') === name) return;
            var svg = na_icon_node(name);
            if (!svg) return;
            Shell.na_clear(holder);
            holder.appendChild(svg);
            holder.setAttribute('data-na-icon-painted', name);
        });
    };

    // FUNCTION | A New Icon Element (painted now if the icons have arrived)
    // @param name {string} Flag, QuickName ... (the file name's middle part)
    // @return {HTMLElement}
    Shell.na_svg_icon = function (name) {
        var span = Shell.na_el('span', 'na-svg-icon');
        span.setAttribute('data-na-icon', name);
        Shell.na_paint_icons(span);
        return span;
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Time, Size and Colour Helpers
    // -------------------------------------------------------------------------

    // FUNCTION | "just now", "4 min ago", "2 h ago", "yesterday", "3 days ago"
    // @param seconds {number} epoch seconds
    Shell.na_ago = function (seconds) {
        if (!seconds) return '';
        var age = Date.now() / 1000 - seconds;
        if (age < 45) return 'just now';
        if (age < 3600) return Math.round(age / 60) + ' min ago';
        if (age < 86400) return Math.round(age / 3600) + ' h ago';
        if (age < 172800) return 'yesterday';
        return Math.round(age / 86400) + ' days ago';
    };

    // FUNCTION | "10-Nov 14:05" (Adam's date order)
    Shell.na_when = function (seconds) {
        if (!seconds) return '';
        var date = new Date(seconds * 1000);
        var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        var pad = function (n) { return (n < 10 ? '0' : '') + n; };
        return pad(date.getDate()) + '-' + months[date.getMonth()] + ' ' + pad(date.getHours()) + ':' + pad(date.getMinutes());
    };

    Shell.na_iso_seconds = function (iso) {
        var time = Date.parse(iso || '');
        return isFinite(time) ? time / 1000 : 0;
    };

    // FUNCTION | 4000 x 300 x 2500 (mm, whole numbers unless small)
    Shell.na_size = function (size) {
        if (!size || size.length < 2) return '';
        return size.map(function (value) {
            var number = Number(value) || 0;
            return Math.abs(number) >= 100 ? String(Math.round(number)) : String(Math.round(number * 10) / 10);
        }).join(' x ');
    };

    // FUNCTION | #rrggbb plus an alpha, as rgba()
    Shell.na_rgba = function (hex, alpha) {
        var match = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex || '');
        if (!match) return 'rgba(100,116,139,' + alpha + ')';
        return 'rgba(' + parseInt(match[1], 16) + ',' + parseInt(match[2], 16) + ',' + parseInt(match[3], 16) + ',' + alpha + ')';
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Init
    // -------------------------------------------------------------------------

    function na_init() {
        na_wire_tabs();
        na_wire_modals();
        na_emit('init', null);
        window.Na__AgentOutliner__Bridge.na_ready();
    }

    window.Na__AgentOutliner__Shell = Shell;

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_init);
    } else {
        window.setTimeout(na_init, 0);
    }
})();

// =============================================================================
// END OF FILE
// =============================================================================
