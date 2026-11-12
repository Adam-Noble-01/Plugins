// =============================================================================
// NA AGENT OUTLINER - UI SYSTEM - AGENT HANDOFF (COPY FOR AGENT)
// =============================================================================
//
// FILE       : Na__AgentOutliner__UiSystem__AgentHandoff__.js
// NAMESPACE  : window.Na__AgentOutliner__Handoff
// MODULE     : Handoff (IIFE)
// AUTHOR     : Noble Architecture
// PURPOSE    : Build the text Adam pastes into a Claude chat: each object's
//              persistent id, type, path, tag, size, what its standard name
//              means, its flag and the latest of its thread, then the footer
//              from the naming standards telling the agent how to answer
// CREATED    : 10-Nov-2026
//
// DESCRIPTION:
// - Copy for Agent copies the text straight to the clipboard and says so in
//   a toast (0.1.13; until 0.1.12 a panel showed it first, with ticks and
//   Copy IDs Only. Adam: "Make the copy for agent button just copy straight
//   to clipboard and avoid this menu ... a simple copy feature with a toasty
//   stating it was successfully copied is enough"). The text always carries
//   paths, tags and sizes, what names and flags mean, and the latest comments.
// - With nothing selected it copies everything waiting for an agent (flags
//   in the inbox and comments no agent has read).
// - Ids are the persistent ids every Na SketchUp MCP tool takes, so the
//   agent can act on the objects without searching for them.
//
// =============================================================================

(function () {
    'use strict';

    var Handoff = {};
    var Shell = null, Store = null;

    // -------------------------------------------------------------------------
    // REGION | Building the Text
    // -------------------------------------------------------------------------

    // FUNCTION | The Handoff Text for Some Objects
    // @param pids {number[]}
    // @return {string}
    Handoff.na_build = function (pids) {
        var S = Store.na_state();
        var lines = [];
        var model = S.model || {};
        lines.push('SketchUp Agent Outliner: ' + pids.length + ' object' + (pids.length === 1 ? '' : 's') + ' for the agent (' + Shell.na_when(Date.now() / 1000) + ')');
        lines.push('Model: ' + (model.title || 'Untitled') + (model.path ? '   ' + model.path : '   (not saved yet)'));
        lines.push('');
        var reach = Store.na_reachable();
        pids.forEach(function (pid, index) {
            var row = Store.na_row(pid);
            if (!row) return;
            var head = (index + 1) + '. ' + row.dn + '   [' + Store.na_type_name(row.k) + ', id ' + row.p + ']';
            if (row.k === 'c') head += '   definition ' + Store.na_def_name(row) + ' (' + Store.na_copies(row) + ' copies)';
            lines.push(head);
            var path = (reach[pid] || [pid]).map(function (id) { var r = Store.na_row(id); return r ? r.dn : String(id); });
            if (path.length > 1) lines.push('   Path: ' + path.join(' > '));
            var facts = ['Tag: ' + (row.t || 'Untagged') + (Store.na_tag_shown(row.t) ? '' : ' (hidden)')];
            if (row.sz) facts.push('Size: ' + Shell.na_size(row.sz) + ' mm');
            if (row.h) facts.push('hidden');
            if (row.l) facts.push('locked');
            lines.push('   ' + facts.join('   '));
            if (row.pre) {
                var entry = Store.na_prefix_entry(row.pre);
                if (entry) lines.push('   Standard name ' + entry.label + ': ' + entry.meaning);
            }
            if (row.nf) {
                var flag = Store.na_flag_type(row.nf);
                lines.push('   Flag: ' + (flag ? flag.label : row.nf) + (row.nfb === 'agent' ? ' (set by an agent)' : '') + (flag ? ': ' + flag.meaning : ''));
            }
            if (row.nc || row.nl) {
                var thread = S.threads[pid];
                if (thread && thread.entries && thread.entries.length) {
                    lines.push('   Thread (' + (thread.status || 'open') + '):');
                    thread.entries.slice(-6).forEach(function (entry) {
                        lines.push('     ' + (entry.author || entry.by) + ', ' + Shell.na_when(Shell.na_iso_seconds(entry.at)) + ': ' + String(entry.text).replace(/\n+/g, ' / '));
                    });
                } else {
                    lines.push('   Thread (' + (row.ns || 'open') + ', ' + (row.nc || 0) + ' comment' + (row.nc === 1 ? '' : 's') + '), latest ' +
                        (row.nlb === 'agent' ? 'from an agent' : 'from Adam') + ': ' + String(row.nl || '').replace(/\n+/g, ' / '));
                }
            }
            var change = Store.na_change(pid);
            if (change && change.ever) {
                lines.push('   Last change: ' + (change.updated > change.created ? 'changed' : 'made') + ' ' + Shell.na_when(change.latest) + ' by ' +
                    (change.by === 'agent' ? 'an agent' : 'Adam') + (change.fields.length ? ' (' + change.fields.join(', ') + ')' : ''));
            }
            lines.push('');
        });
        var footer = S.standards.handoff && S.standards.handoff.footer ? S.standards.handoff.footer : '';
        if (footer) lines.push(footer);
        return lines.join('\n');
    };

    // FUNCTION | Everything Waiting for an Agent (used when nothing is selected)
    Handoff.na_waiting_pids = function () {
        var S = Store.na_state();
        return Object.keys(S.ents).map(Number).filter(function (pid) {
            var row = S.ents[pid];
            return (row.nw || 0) > 0;
        });
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Copy for Agent (0.1.13: straight to the clipboard)
    // -------------------------------------------------------------------------

    // FUNCTION | Copy the Objects' Text for an Agent, and Say So in a Toast
    // @param pids {number[]} the selected objects (empty: what waits for agents)
    Handoff.na_copy = function (pids) {
        pids = (pids || []).slice(0, 200);
        var waiting = false;
        if (!pids.length) {
            pids = Handoff.na_waiting_pids();
            waiting = true;
        }
        if (!pids.length) {
            Shell.na_toast('Select rows first: nothing is waiting for an agent either.', 'warn');
            return Shell.na_set_status('Select rows first (nothing is waiting for an agent either).', 'warn');
        }
        var objects = pids.length + ' object' + (pids.length === 1 ? '' : 's');
        Shell.na_copy(Handoff.na_build(pids), (waiting ? 'Copied the ' + objects + ' waiting for an agent' : 'Copied ' + objects + ' for the agent') + ': paste into Claude.');
    };

    // endregion ----------------------------------------------------------------

    function na_init() {
        Shell = window.Na__AgentOutliner__Shell;
        Store = window.Na__AgentOutliner__Store;
    }

    window.Na__AgentOutliner__Handoff = Handoff;
    window.Na__AgentOutliner__Shell.na_on('init', na_init);
})();

// =============================================================================
// END OF FILE
// =============================================================================
