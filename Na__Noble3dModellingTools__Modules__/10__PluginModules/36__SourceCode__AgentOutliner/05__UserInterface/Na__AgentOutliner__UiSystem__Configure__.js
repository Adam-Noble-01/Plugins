// =============================================================================
// NA AGENT OUTLINER - UI SYSTEM - CONFIGURE TAB
// =============================================================================
//
// FILE       : Na__AgentOutliner__UiSystem__Configure__.js
// NAMESPACE  : window.Na__AgentOutliner__Configure
// MODULE     : Configure (IIFE)
// AUTHOR     : Noble Architecture
// PURPOSE    : Edit the naming standards: the Quick Name prefixes (label,
//              category, mode, colour, what it means for an agent), the flag
//              types, and the footer of the Copy for Agent text
// CREATED    : 10-Nov-2026
//
// DESCRIPTION:
// - Edits are a draft until Save: Ruby validates again and writes the shared
//   standards file (keeping a .bak), then every open part of the dialog uses
//   the new list.
// - A LABEL is letters, numbers and dashes, with double underscores between
//   parts: CAD__SideElevation__Left. Replace mode names an object exactly the
//   label; prefix mode puts label__ in front of the name it had.
// - "Meaning for agents" is what agent_outliner prefixes hands an agent, so
//   write it as an instruction ("Take sizes from it; never move it").
//
// =============================================================================

(function () {
    'use strict';

    var Configure = {};
    var Shell = null, Store = null, Bridge = null;
    var C = { draft: null, dirty: false, issues: [] };
    var NA_LABEL = /^[A-Za-z0-9][A-Za-z0-9\-]*(?:__[A-Za-z0-9][A-Za-z0-9\-]*)*$/;
    var NA_FLAG_ID = /^[a-z][a-z0-9_]{0,39}$/;

    // -------------------------------------------------------------------------
    // REGION | Draft
    // -------------------------------------------------------------------------

    function na_load_draft() {
        var standards = Store.na_state().standards || { prefixes: [], flags: [], handoff: {} };
        C.base = JSON.stringify(standards);
        C.draft = JSON.parse(C.base);
        C.draft.handoff = C.draft.handoff || { footer: '' };
        C.dirty = false;
        C.issues = [];
        Configure.na_render();
    }

    function na_mark_dirty() {
        C.dirty = true;
        C.issues = na_validate();
        na_render_status();
    }

    // The same rules Ruby applies before it writes the file.
    function na_validate() {
        var issues = [];
        var labels = {};
        C.draft.prefixes.forEach(function (entry, index) {
            var where = entry.label || ('Prefix ' + (index + 1));
            if (!entry.label) issues.push(where + ' has no label.');
            else if (!NA_LABEL.test(entry.label)) issues.push(where + ': letters, numbers and dashes, with double underscores between parts.');
            else if (labels[entry.label.toLowerCase()]) issues.push(where + ' is listed twice.');
            labels[(entry.label || '').toLowerCase()] = true;
        });
        var ids = {};
        C.draft.flags.forEach(function (flag, index) {
            var where = flag.label || ('Flag ' + (index + 1));
            if (!NA_FLAG_ID.test(flag.id || '')) issues.push(where + ': its id must be lower case letters, numbers and underscores.');
            else if (ids[flag.id]) issues.push(where + ': the id ' + flag.id + ' is used twice.');
            if (!flag.label) issues.push('Flag ' + (flag.id || index + 1) + ' has no label.');
            ids[flag.id] = true;
        });
        if (!C.draft.flags.length) issues.push('At least one flag type is needed.');
        return issues;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Render
    // -------------------------------------------------------------------------

    // FUNCTION | Draw the Configure Tab From the Draft
    Configure.na_render = function () {
        if (!C.draft) return;
        na_render_prefixes();
        na_render_flags();
        var footer = document.getElementById('na-cfg-footer');
        if (document.activeElement !== footer) footer.value = C.draft.handoff.footer || '';
        na_render_status();
    };

    function na_render_prefixes() {
        var host = Shell.na_clear(document.getElementById('na-cfg-prefixes'));
        var categories = {};
        C.draft.prefixes.forEach(function (entry) { categories[entry.category] = true; });
        var datalist = Shell.na_clear(document.getElementById('na-cfg-categories'));
        Object.keys(categories).forEach(function (name) { var option = Shell.na_el('option'); option.value = name; datalist.appendChild(option); });

        var head = Shell.na_el('div', 'na-cfg-row na-cfg-row--head na-cfg-row--prefix');
        ['', 'Label', 'Category', 'Mode', 'Colour', 'Meaning for agents', 'Gives', ''].forEach(function (text) { head.appendChild(Shell.na_el('span', null, text)); });
        host.appendChild(head);

        C.draft.prefixes.forEach(function (entry, index) {
            var line = Shell.na_el('div', 'na-cfg-row na-cfg-row--prefix');
            line.appendChild(na_mover(C.draft.prefixes, index, na_render_prefixes));

            var label = na_input(entry.label, 'CAD__FrontElevation', function (value) { entry.label = value.trim(); preview.textContent = na_preview(entry); }, NA_LABEL);
            if (entry.label && !NA_LABEL.test(entry.label)) label.classList.add('naInput--bad');
            line.appendChild(label);

            var category = na_input(entry.category, 'CAD Elevations', function (value) { entry.category = value; });
            category.setAttribute('list', 'na-cfg-categories');
            line.appendChild(category);

            var mode = Shell.na_el('select', 'naSelect');
            Shell.na_fill_select(mode, [{ value: 'replace', label: 'Name it exactly' }, { value: 'prefix', label: 'Put in front' }, { value: 'face', label: 'Elevation face (a segment)' }], entry.mode);
            mode.addEventListener('change', function () { entry.mode = mode.value; preview.textContent = na_preview(entry); na_mark_dirty(); });
            line.appendChild(mode);

            var colour = Shell.na_el('input', 'na-cfg-colour');
            colour.type = 'color';
            colour.value = entry.colour || '#64748b';
            colour.addEventListener('input', function () { entry.colour = colour.value; na_mark_dirty(); });
            line.appendChild(colour);

            var meaning = Shell.na_el('textarea', 'naTextarea na-cfg-meaning');
            meaning.value = entry.meaning || '';
            meaning.placeholder = 'What an agent should know or do with an object named so';
            meaning.rows = 2;
            meaning.addEventListener('input', function () { entry.meaning = meaning.value; na_mark_dirty(); });
            line.appendChild(meaning);

            var preview = Shell.na_el('span', 'na-cfg-preview', na_preview(entry));
            line.appendChild(preview);

            line.appendChild(Shell.na_button('\u00d7', 'na-cfg-delete', function () {
                C.draft.prefixes.splice(index, 1);
                na_mark_dirty();
                na_render_prefixes();
            }, 'Remove this prefix (objects already named keep their names)'));
            host.appendChild(line);
        });
    }

    function na_render_flags() {
        var host = Shell.na_clear(document.getElementById('na-cfg-flags'));
        var head = Shell.na_el('div', 'na-cfg-row na-cfg-row--head na-cfg-row--flag');
        ['', 'Id', 'Label', 'Colour', 'Agent inbox', 'Meaning for agents', ''].forEach(function (text) { head.appendChild(Shell.na_el('span', null, text)); });
        host.appendChild(head);

        C.draft.flags.forEach(function (flag, index) {
            var line = Shell.na_el('div', 'na-cfg-row na-cfg-row--flag');
            line.appendChild(na_mover(C.draft.flags, index, na_render_flags));
            var id = na_input(flag.id, 'for_agent', function (value) { flag.id = value.trim(); }, NA_FLAG_ID);
            if (flag.id && !NA_FLAG_ID.test(flag.id)) id.classList.add('naInput--bad');
            id.title = 'Stored on flagged objects: renaming an id leaves objects flagged with the old one';
            line.appendChild(id);
            line.appendChild(na_input(flag.label, 'For Agent', function (value) { flag.label = value; }));

            var colour = Shell.na_el('input', 'na-cfg-colour');
            colour.type = 'color';
            colour.value = flag.colour || '#64748b';
            colour.addEventListener('input', function () { flag.colour = colour.value; na_mark_dirty(); });
            line.appendChild(colour);

            var inboxLabel = Shell.na_el('label', 'na-check');
            var inbox = Shell.na_el('input');
            inbox.type = 'checkbox';
            inbox.checked = !!flag.inbox;
            inbox.addEventListener('change', function () { flag.inbox = inbox.checked; na_mark_dirty(); });
            inboxLabel.appendChild(inbox);
            inboxLabel.appendChild(document.createTextNode('waits for an agent'));
            line.appendChild(inboxLabel);

            var meaning = Shell.na_el('textarea', 'naTextarea na-cfg-meaning');
            meaning.value = flag.meaning || '';
            meaning.rows = 2;
            meaning.addEventListener('input', function () { flag.meaning = meaning.value; na_mark_dirty(); });
            line.appendChild(meaning);

            line.appendChild(Shell.na_button('\u00d7', 'na-cfg-delete', function () {
                C.draft.flags.splice(index, 1);
                na_mark_dirty();
                na_render_flags();
            }, 'Remove this flag type'));
            host.appendChild(line);
        });
    }

    function na_render_status() {
        var status = document.getElementById('na-cfg-status');
        status.textContent = C.dirty ? 'Unsaved changes' : 'Saved';
        status.className = 'na-cfg-status' + (C.dirty ? ' na-cfg-status--dirty' : '');
        var fault = document.getElementById('na-cfg-issues');
        fault.textContent = C.issues.join('  ');
        fault.classList.toggle('na-hidden', !C.issues.length);
        document.getElementById('na-cfg-save').disabled = !C.dirty || C.issues.length > 0;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Small Builders
    // -------------------------------------------------------------------------

    // An input that writes into the draft as Adam types. No redraw on change:
    // a redraw would take the focus from the field he tabs to next.
    function na_input(value, placeholder, onChange, pattern) {
        var input = Shell.na_el('input', 'naInput');
        input.type = 'text';
        input.value = value || '';
        input.placeholder = placeholder || '';
        input.addEventListener('input', function () {
            onChange(input.value);
            if (pattern) input.classList.toggle('naInput--bad', !!input.value.trim() && !pattern.test(input.value.trim()));
            na_mark_dirty();
        });
        return input;
    }

    function na_mover(list, index, rerender) {
        var box = Shell.na_el('span', 'na-cfg-mover');
        box.appendChild(Shell.na_button('\u25b2', 'na-cfg-move', function () {
            if (index === 0) return;
            list.splice(index - 1, 0, list.splice(index, 1)[0]);
            na_mark_dirty();
            rerender();
        }, 'Move up'));
        box.appendChild(Shell.na_button('\u25bc', 'na-cfg-move', function () {
            if (index >= list.length - 1) return;
            list.splice(index + 1, 0, list.splice(index, 1)[0]);
            na_mark_dirty();
            rerender();
        }, 'Move down'));
        return box;
    }

    function na_preview(entry) {
        if (!entry.label) return '';
        if (entry.mode === 'face') return 'SUB__Building__Asset__' + entry.label + '__01';
        return entry.mode === 'prefix' ? entry.label + '__ExistingName' : entry.label;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Wiring and Channels
    // -------------------------------------------------------------------------

    function na_wire() {
        document.getElementById('na-cfg-add-prefix').addEventListener('click', function () {
            var last = C.draft.prefixes[C.draft.prefixes.length - 1];
            C.draft.prefixes.push({ id: '', label: '', category: last ? last.category : 'General', mode: 'replace', colour: '#2563eb', meaning: '' });
            na_mark_dirty();
            na_render_prefixes();
            var inputs = document.querySelectorAll('#na-cfg-prefixes .na-cfg-row--prefix input.naInput');
            if (inputs.length) inputs[inputs.length - 2].focus();
        });
        document.getElementById('na-cfg-add-flag').addEventListener('click', function () {
            C.draft.flags.push({ id: '', label: '', colour: '#64748b', inbox: false, meaning: '' });
            na_mark_dirty();
            na_render_flags();
        });
        document.getElementById('na-cfg-footer').addEventListener('input', function (event) {
            C.draft.handoff.footer = event.target.value;
            na_mark_dirty();
        });
        document.getElementById('na-cfg-save').addEventListener('click', function () {
            C.issues = na_validate();
            if (C.issues.length) return na_render_status();
            Bridge.na_call('saveStandards', { standards: C.draft });
            C.dirty = false;
            na_render_status();
        });
        document.getElementById('na-cfg-revert').addEventListener('click', function () {
            if (!C.dirty) return na_load_draft();
            Shell.na_confirm({ title: 'Throw Away These Edits?', text: 'The standards go back to the saved file.', confirm: 'Revert', danger: true }, na_load_draft);
        });
        document.getElementById('na-cfg-open-folder').addEventListener('click', function () { Bridge.na_call('openFolder', { which: 'standards' }); });
    }

    function na_init() {
        Shell = window.Na__AgentOutliner__Shell;
        Store = window.Na__AgentOutliner__Store;
        Bridge = window.Na__AgentOutliner__Bridge;
        na_wire();
        Shell.na_on('state', function (state) {
            if (!C.dirty) return na_load_draft();
            if (JSON.stringify(state.standards || {}) !== C.base) {
                Shell.na_set_status('The saved standards changed while you were editing: Revert to load them.', 'warn');
            }
        });
        Shell.na_on('standardsIssues', function (payload) {
            C.dirty = true;
            C.issues = payload.issues || [];
            na_render_status();
        });
    }

    window.Na__AgentOutliner__Configure = Configure;
    window.Na__AgentOutliner__Shell.na_on('init', na_init);
})();

// =============================================================================
// END OF FILE
// =============================================================================
