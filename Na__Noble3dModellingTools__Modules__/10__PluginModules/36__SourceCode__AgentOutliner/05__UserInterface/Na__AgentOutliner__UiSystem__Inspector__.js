// =============================================================================
// NA AGENT OUTLINER - UI SYSTEM - INSPECTOR (THE SIDE PANEL)
// =============================================================================
//
// FILE       : Na__AgentOutliner__UiSystem__Inspector__.js
// NAMESPACE  : window.Na__AgentOutliner__Inspector
// MODULE     : Inspector (IIFE)
// AUTHOR     : Noble Architecture
// PURPOSE    : The panel beside the table: one object's details, flag, comment
//              thread with Adam and the agents, and change history; several
//              objects' bulk actions; with nothing selected, the recent
//              activity of both Adam and the agents, and the model's thread
// CREATED    : 10-Nov-2026
//
// DESCRIPTION:
// - THE THREAD reads like a chat: Adam's entries on the right, an agent's on
//   the left in the agent colour, flags and resolutions as small lines
//   between. Ctrl+Enter sends. An agent entry Adam has not read is marked
//   New and counted as read after it has been on screen for a moment (that
//   is kept on this PC, never written into the model).
// - SHARED DEFINITIONS: an object inside a component placed several times is
//   the same object in every copy, so its flag, comments, name and hidden
//   state show in all of them. The panel says so before Adam acts.
// - THE PANEL CAN BE NARROWED or closed (drag its edge; the button in its
//   corner); its width is remembered.
//
// =============================================================================

(function () {
    'use strict';

    var Inspector = {};
    var Shell = null, Store = null, Bridge = null, View = null;
    var I = { mode: 'auto', pid: null, pids: [], digest: '', readTimer: null, historyFor: null, open: true, draft: {} };

    // -------------------------------------------------------------------------
    // REGION | Render
    // -------------------------------------------------------------------------

    // FUNCTION | Draw the Panel for the Current Selection (or the model)
    Inspector.na_render = function () {
        var host = document.getElementById('na-inspector-body');
        if (!host) return;
        na_save_draft();
        Shell.na_clear(host);
        if (I.mode === 'model') return na_render_model_thread(host);
        if (I.pids.length === 1) return na_render_object(host, I.pids[0]);
        if (I.pids.length > 1) return na_render_many(host, I.pids);
        na_render_activity(host);
    };

    function na_render_object(host, pid) {
        var row = Store.na_row(pid);
        if (!row) { host.appendChild(Shell.na_el('p', 'na-hint', 'That object is no longer in the model.')); return; }
        var S = Store.na_state();

        // Heading: icon, name, type, id
        var head = Shell.na_el('div', 'na-insp-head');
        head.appendChild(View.na_icon(row.k));
        var title = Shell.na_el('div', 'na-insp-title');
        Shell.na_breakable(title, row.dn);
        head.appendChild(title);
        host.appendChild(head);
        var sub = Shell.na_el('div', 'na-insp-sub');
        sub.appendChild(Shell.na_el('span', null, Store.na_type_name(row.k)));
        var idChip = Shell.na_button('id ' + row.p, 'na-insp-id', function () { Shell.na_copy(String(row.p), 'Copied id ' + row.p + '.'); }, 'Copy the persistent id agents use');
        sub.appendChild(idChip);
        host.appendChild(sub);

        // Actions
        var actions = Shell.na_el('div', 'na-insp-actions');
        actions.appendChild(Shell.na_button('Select', null, function () { na_select(false); }));
        actions.appendChild(Shell.na_button('Zoom', null, function () { na_select(true); }));
        actions.appendChild(Shell.na_button(row.h ? 'Show' : 'Hide', null, function () { Bridge.na_call('setHidden', { pids: [pid], hidden: !row.h }); }));
        if (row.k === 'g' || row.k === 'c') actions.appendChild(Shell.na_button(row.l ? 'Unlock' : 'Lock', null, function () { Bridge.na_call('setLocked', { pids: [pid], locked: !row.l }); }));
        actions.appendChild(Shell.na_button('Rename', null, function () {
            Shell.na_prompt({ title: 'Rename', label: 'Name', value: row.n || '', confirm: 'Rename' }, function (text) { Bridge.na_call('rename', { pids: [pid], name: text }); });
        }));
        actions.appendChild(Shell.na_button('Tag\u2026', null, function (event) {
            var rect = event.target.getBoundingClientRect();
            window.Na__AgentOutliner__View.na_tag_picker(Math.max(4, rect.right - 300), rect.bottom + 2, [pid]);
        }, 'Change its tag (T in the table)'));
        actions.appendChild(Shell.na_button('Copy for Agent', 'naButton na-button--small', function () { window.Na__AgentOutliner__Handoff.na_copy([pid]); }));
        host.appendChild(actions);

        var shared = na_shared_note(pid);
        if (shared) host.appendChild(Shell.na_el('p', 'na-note na-note--inline', shared));

        // Facts
        var facts = Shell.na_el('dl', 'na-insp-facts');
        na_fact(facts, 'Name', row.n || '(no name of its own)');
        if (row.k === 'c') na_fact(facts, 'Definition', Store.na_def_name(row) + '  (' + Store.na_copies(row) + ' cop' + (Store.na_copies(row) === 1 ? 'y' : 'ies') + ')');
        na_fact(facts, 'Tag', (row.t || 'Untagged') + (Store.na_tag_shown(row.t) ? '' : '  (hidden tag)'));
        if (row.m) na_fact(facts, 'Material', row.m);
        if (row.sz) na_fact(facts, 'Size', Shell.na_size(row.sz) + ' mm');
        var path = na_path_of(pid);
        if (path.length > 1) {
            var crumbs = Shell.na_el('span', 'na-insp-crumbs');
            path.forEach(function (id, index) {
                var r = Store.na_row(id);
                if (index) crumbs.appendChild(Shell.na_el('span', 'na-insp-crumbs__sep', '\u203a'));
                crumbs.appendChild(Shell.na_el('span', index === path.length - 1 ? 'na-insp-crumbs__here' : null, r ? r.dn : String(id)));
            });
            na_fact(facts, 'Path', crumbs);
        }
        if (row.pre) {
            var entry = Store.na_prefix_entry(row.pre);
            na_fact(facts, 'Standard Name', row.pre + (entry ? ': ' + entry.meaning : ''));
        }
        var change = Store.na_change(pid);
        if (change && change.ever) {
            var text = [];
            if (change.created) text.push('Made ' + Shell.na_when(change.created) + ' by ' + (change.createdBy === 'agent' ? 'an agent' : 'you'));
            if (change.updated) text.push('Changed ' + Shell.na_when(change.updated) + ' by ' + (change.updatedBy === 'agent' ? 'an agent' : 'you') +
                (change.fields.length ? ' (' + change.fields.join(', ') + ')' : ''));
            if (change.tool) text.push('Last MCP tool: ' + change.tool.replace('__', ' '));
            na_fact(facts, 'History', text.join('. ') + '.');
        }
        host.appendChild(facts);

        // Flag
        host.appendChild(Shell.na_el('h4', 'na-insp-section', 'Flag'));
        var flags = Shell.na_el('div', 'na-insp-flags');
        (S.standards.flags || []).forEach(function (flag) {
            var on = row.nf === flag.id;
            var chip = Shell.na_button(flag.label, 'na-flag-chip' + (on ? ' na-flag-chip--on' : ''), function () {
                if (on) Bridge.na_call('unflag', { pids: [pid] });
                else Bridge.na_call('flag', { pids: [pid], flag: flag.id });
            }, flag.meaning + (flag.inbox ? ' (goes to the agent inbox)' : ''));
            chip.style.setProperty('--na-flag', flag.colour);
            flags.appendChild(chip);
        });
        host.appendChild(flags);
        if (row.nf && row.nfb === 'agent') host.appendChild(Shell.na_el('p', 'na-hint', 'An agent set this flag for you.'));

        // Thread
        na_render_thread(host, pid, S.threads[pid], row);

        // History
        var historyHead = Shell.na_el('div', 'na-insp-section-row');
        historyHead.appendChild(Shell.na_el('h4', 'na-insp-section', 'Change History'));
        historyHead.appendChild(Shell.na_button(I.historyFor === pid ? 'Refresh' : 'Show', null, function () {
            I.historyFor = pid;
            Bridge.na_call('getHistory', { pid: pid });
        }));
        host.appendChild(historyHead);
        if (I.historyFor === pid && S.history[pid]) host.appendChild(na_history_list(S.history[pid]));
    }

    function na_render_thread(host, pid, thread, row) {
        var headRow = Shell.na_el('div', 'na-insp-section-row');
        headRow.appendChild(Shell.na_el('h4', 'na-insp-section', pid === 'model' ? 'Model Thread' : 'Comments'));
        headRow.appendChild(Shell.na_button('Open in Chat', null, function () { Shell.na_emit('openChat', pid); }, 'The whole conversation in the Chat tab, where you can paste pictures'));
        var status = thread ? thread.status : (row ? row.ns : '');
        if (status) {
            headRow.appendChild(Shell.na_el('span', 'na-thread-status na-thread-status--' + status, status === 'resolved' ? 'Resolved' : 'Open'));
            headRow.appendChild(Shell.na_button(status === 'resolved' ? 'Reopen' : 'Resolve', null, function () {
                Bridge.na_call('setThreadStatus', na_target(pid, { status: status === 'resolved' ? 'open' : 'resolved' }));
            }));
        }
        host.appendChild(headRow);

        var list = Shell.na_el('div', 'na-thread');
        var unread = [];
        if (!thread && row && (row.nc || row.nf)) {
            list.appendChild(Shell.na_el('p', 'na-hint', 'Loading the thread\u2026'));
        } else if (!thread || !thread.entries || !thread.entries.length) {
            list.appendChild(Shell.na_el('p', 'na-hint', pid === 'model'
                ? 'Nothing yet. Agents leave summaries of their work here; you can write to every agent at once.'
                : 'No comments yet. Write one below: an agent reads it with agent_outliner inbox and answers here.'));
        } else {
            thread.entries.forEach(function (entry) {
                list.appendChild(na_entry_element(pid, entry));
                if (entry.new_for_adam) unread.push(entry.id);
            });
        }
        host.appendChild(list);
        window.setTimeout(function () { list.scrollTop = list.scrollHeight; }, 0);

        // Composer
        var composer = Shell.na_el('div', 'na-composer');
        var area = Shell.na_el('textarea', 'naTextarea na-composer__text');
        area.id = 'na-composer-text';
        area.placeholder = pid === 'model' ? 'A message for every agent working on this model\u2026' : 'Ask an agent, or answer one\u2026';
        area.value = I.draft[pid] || '';
        area.addEventListener('input', function () { I.draft[pid] = area.value; });
        var send = function () {
            var text = area.value.trim();
            if (!text) return Shell.na_set_status('Write something first: the comment is empty.', 'warn');
            var flagToo = document.getElementById('na-composer-flag');
            if (flagToo && flagToo.checked && pid !== 'model') Bridge.na_call('flag', { pids: [pid], flag: 'for_agent', text: text });
            else Bridge.na_call('comment', na_target(pid, { text: text }));
            I.draft[pid] = '';
            area.value = '';
        };
        area.addEventListener('keydown', function (event) {
            if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) { event.preventDefault(); send(); }
            event.stopPropagation();
        });
        composer.appendChild(area);
        var bar = Shell.na_el('div', 'na-composer__bar');
        if (pid !== 'model') {
            var label = Shell.na_el('label', 'na-check');
            var box = Shell.na_el('input');
            box.type = 'checkbox';
            box.id = 'na-composer-flag';
            box.checked = !row || !row.nf;
            label.appendChild(box);
            label.appendChild(document.createTextNode('Flag For Agent'));
            label.title = 'Puts it in the agent inbox with this comment at the top';
            bar.appendChild(label);
        }
        bar.appendChild(Shell.na_el('span', 'na-composer__keys', 'Ctrl+Enter'));
        bar.appendChild(Shell.na_button('Send to Agent', 'naButton na-button--small', send));
        composer.appendChild(bar);
        host.appendChild(composer);

        if (unread.length) {
            if (I.readTimer) window.clearTimeout(I.readTimer);
            I.readTimer = window.setTimeout(function () {
                I.readTimer = null;
                Bridge.na_call('markRead', { ids: unread, pids: pid === 'model' ? [] : [pid], model: pid === 'model' });
            }, 1500);
        }
    }

    function na_entry_element(pid, entry) {
        var mine = entry.by === 'user';
        if (entry.kind && entry.kind !== 'comment') {
            var line = Shell.na_el('div', 'na-entry-system na-entry-system--' + entry.by);
            line.textContent = (entry.author || (mine ? 'You' : 'Agent')) + ': ' + entry.text + '  \u00b7  ' + Shell.na_when(Shell.na_iso_seconds(entry.at));
            return line;
        }
        var bubble = Shell.na_el('div', 'na-entry ' + (mine ? 'na-entry--user' : 'na-entry--agent') + (entry.new_for_adam ? ' na-entry--new' : ''));
        var meta = Shell.na_el('div', 'na-entry__meta');
        meta.appendChild(Shell.na_el('span', 'na-entry__author', entry.author || (mine ? 'You' : 'Agent')));
        meta.appendChild(Shell.na_el('span', 'na-entry__time', Shell.na_when(Shell.na_iso_seconds(entry.at))));
        if (entry.new_for_adam) meta.appendChild(Shell.na_el('span', 'na-entry__new', 'New'));
        if (mine && entry.new_for_agent) meta.appendChild(Shell.na_el('span', 'na-entry__waiting', 'not read by an agent yet'));
        var remove = Shell.na_button('\u00d7', 'na-entry__delete', function () {
            Shell.na_confirm({ title: 'Delete This Comment?', text: 'It is removed from the model (Ctrl+Z in SketchUp brings it back).', confirm: 'Delete', danger: true },
                function () { Bridge.na_call('deleteEntry', na_target(pid, { entry: entry.id })); });
        }, 'Delete this comment');
        meta.appendChild(remove);
        bubble.appendChild(meta);
        if (entry.text) {
            var chat = window.Na__AgentOutliner__Chat;
            bubble.appendChild(chat ? chat.na_rich_text(entry.text, 'na-entry__text') : Shell.na_el('div', 'na-entry__text', entry.text));
        }
        var pictures = window.Na__AgentOutliner__Chat ? window.Na__AgentOutliner__Chat.na_images(entry) : null;
        if (pictures) bubble.appendChild(pictures);
        return bubble;
    }

    function na_history_list(events) {
        var list = Shell.na_el('div', 'na-history');
        if (!events.length) { list.appendChild(Shell.na_el('p', 'na-hint', 'No recorded changes.')); return list; }
        events.slice().reverse().forEach(function (event) {
            var line = Shell.na_el('div', 'na-history__line na-history__line--' + event.by);
            var what = event.kind === 'new' ? 'Made' : (event.kind === 'removed' ? 'Erased' : 'Changed ' + (event.fields || []).join(', '));
            line.appendChild(Shell.na_el('span', 'na-history__when', Shell.na_when(event.t)));
            line.appendChild(Shell.na_el('span', 'na-history__who', event.by === 'agent' ? 'Agent' : 'You'));
            line.appendChild(Shell.na_el('span', 'na-history__what', what + (event.via ? ' (' + event.via + ')' : '') + (event.tool ? '  \u00b7  ' + event.tool.replace('__', ' ') : '')));
            list.appendChild(line);
        });
        return list;
    }

    function na_render_many(host, pids) {
        host.appendChild(Shell.na_el('div', 'na-insp-title', pids.length + ' objects selected'));
        var counts = {};
        pids.forEach(function (pid) { var row = Store.na_row(pid); if (row) counts[row.k] = (counts[row.k] || 0) + 1; });
        host.appendChild(Shell.na_el('p', 'na-hint', Object.keys(counts).map(function (k) { return counts[k] + ' ' + Store.na_type_name(k).toLowerCase() + (counts[k] === 1 ? '' : 's'); }).join(', ') + '.'));

        var actions = Shell.na_el('div', 'na-insp-actions');
        actions.appendChild(Shell.na_button('Select', null, function () { na_select(false); }));
        actions.appendChild(Shell.na_button('Zoom', null, function () { na_select(true); }));
        actions.appendChild(Shell.na_button('Hide', null, function () { Bridge.na_call('setHidden', { pids: pids, hidden: true }); }));
        actions.appendChild(Shell.na_button('Show', null, function () { Bridge.na_call('setHidden', { pids: pids, hidden: false }); }));
        actions.appendChild(Shell.na_button('Rename All\u2026', null, function () { View.na_start_rename({ key: '', pid: pids[0] }); }));
        actions.appendChild(Shell.na_button('Find and Replace\u2026', null, function () { View.na_replace_names(pids); }));
        host.appendChild(actions);

        host.appendChild(Shell.na_el('h4', 'na-insp-section', 'Flag All'));
        var flags = Shell.na_el('div', 'na-insp-flags');
        (Store.na_state().standards.flags || []).forEach(function (flag) {
            var chip = Shell.na_button(flag.label, 'na-flag-chip', function () { Bridge.na_call('flag', { pids: pids, flag: flag.id }); }, flag.meaning);
            chip.style.setProperty('--na-flag', flag.colour);
            flags.appendChild(chip);
        });
        flags.appendChild(Shell.na_button('Clear', 'na-flag-chip', function () { Bridge.na_call('unflag', { pids: pids }); }));
        host.appendChild(flags);

        host.appendChild(Shell.na_el('h4', 'na-insp-section', 'For an Agent'));
        var agent = Shell.na_el('div', 'na-insp-actions');
        agent.appendChild(Shell.na_button('Comment on Each\u2026', null, function () { View.na_comment(pids); }));
        agent.appendChild(Shell.na_button('Copy for Agent', 'naButton na-button--small', function () { window.Na__AgentOutliner__Handoff.na_copy(pids); }));
        agent.appendChild(Shell.na_button('Copy IDs', null, function () { Shell.na_copy(JSON.stringify(pids), 'Copied ' + pids.length + ' ids.'); }));
        host.appendChild(agent);
    }

    function na_render_activity(host) {
        var S = Store.na_state();
        host.appendChild(Shell.na_el('div', 'na-insp-title', 'Recent Activity'));
        host.appendChild(Shell.na_el('p', 'na-hint', 'What you and the agents made or changed, newest first. Click a line to find it.'));
        var actions = Shell.na_el('div', 'na-insp-actions');
        actions.appendChild(Shell.na_button('Model Thread', null, function () { Inspector.na_show_model_thread(); }));
        actions.appendChild(Shell.na_button('Mark Changes Seen', null, function () { Bridge.na_call('markChangesSeen', {}); }, 'The Unseen filter then shows only what changes after now'));
        host.appendChild(actions);

        var list = Shell.na_el('div', 'na-activity');
        var events = (S.events || []).slice(-80).reverse();
        if (!events.length) {
            list.appendChild(Shell.na_el('p', 'na-hint', S.tracking && S.tracking.enabled === false
                ? 'Change tracking is off (Settings).'
                : 'Nothing recorded yet. Changes made from now on, by you or an agent, appear here.'));
        }
        var windows = Store.na_windows();
        events.forEach(function (event) {
            var line = Shell.na_el('div', 'na-activity__line na-activity__line--' + event.by);
            var age = Date.now() / 1000 - event.t;
            var band = windows.bands.findIndex(function (b) { return age <= b; });
            line.classList.add('na-activity__line--band' + (band < 0 ? 4 : band));
            line.appendChild(Shell.na_el('span', 'na-activity__who', event.by === 'agent' ? 'Agent' : 'You'));
            var what = event.kind === 'new' ? 'made' : (event.kind === 'removed' ? 'erased' : 'changed ' + (event.fields || []).join(', '));
            var text = Shell.na_el('span', 'na-activity__text');
            text.appendChild(document.createTextNode(what + ' '));
            text.appendChild(Shell.na_el('b', null, event.name || ('#' + event.pid)));
            if (event.via) text.appendChild(document.createTextNode(' (' + event.via + ')'));
            line.appendChild(text);
            line.appendChild(Shell.na_el('span', 'na-activity__when', Shell.na_ago(event.t)));
            line.title = Shell.na_when(event.t) + (event.tool ? '  \u00b7  MCP ' + event.tool.replace('__', ' ') : '');
            if (event.kind !== 'removed' && Store.na_row(event.pid)) {
                line.classList.add('na-activity__line--link');
                line.addEventListener('click', function () { Shell.na_emit('revealPid', event.pid); });
            }
            list.appendChild(line);
        });
        host.appendChild(list);
    }

    function na_render_model_thread(host) {
        var S = Store.na_state();
        var head = Shell.na_el('div', 'na-insp-section-row');
        head.appendChild(Shell.na_el('div', 'na-insp-title', 'Model: ' + (S.model ? S.model.title : '')));
        head.appendChild(Shell.na_button('Back', null, function () { I.mode = 'auto'; Inspector.na_render(); }));
        host.appendChild(head);
        host.appendChild(Shell.na_el('p', 'na-hint', 'A thread for the whole model: agents post summaries of their work here, and you can write to every agent at once.'));
        na_render_thread(host, 'model', S.modelNotes, null);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Helpers
    // -------------------------------------------------------------------------

    function na_fact(list, label, value) {
        list.appendChild(Shell.na_el('dt', null, label));
        var dd = Shell.na_el('dd');
        if (value instanceof HTMLElement) dd.appendChild(value); else dd.textContent = value;
        list.appendChild(dd);
    }

    function na_target(pid, extra) {
        var payload = pid === 'model' ? { model: true } : { pids: [pid] };
        Object.keys(extra || {}).forEach(function (key) { payload[key] = extra[key]; });
        return payload;
    }

    function na_select(zoom) {
        var items = View.na_selected_items();
        if (!items.length) return;
        Bridge.na_call('select', { paths: items.map(function (item) { return item.path; }), zoom: zoom });
    }

    function na_path_of(pid) {
        var items = View.na_selected_items();
        for (var i = 0; i < items.length; i++) if (items[i].pid === pid && items[i].path) return items[i].path;
        return Store.na_reachable()[pid] || [pid];
    }

    // "Inside a component placed N times": the same object in every copy.
    function na_shared_note(pid) {
        var path = na_path_of(pid);
        for (var i = 0; i < path.length - 1; i++) {
            var parent = Store.na_row(path[i]);
            if (parent && parent.k === 'c' && Store.na_copies(parent) > 1) {
                return 'This sits inside ' + Store.na_def_name(parent) + ', placed ' + Store.na_copies(parent) +
                    ' times: its name, flag, comments and hidden state are the same in every copy.';
            }
        }
        return '';
    }

    function na_digest(pid) {
        var row = Store.na_row(pid);
        return row ? [row.nc, row.nla, row.nu, row.nw, row.nf, row.ns].join('|') : '';
    }

    function na_save_draft() {
        var area = document.getElementById('na-composer-text');
        if (area && I.draftPid !== undefined) I.draft[I.draftPid] = area.value;
        I.draftPid = I.mode === 'model' ? 'model' : (I.pids.length === 1 ? I.pids[0] : undefined);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Surface and Channels
    // -------------------------------------------------------------------------

    // FUNCTION | Show the Model's Own Thread
    Inspector.na_show_model_thread = function () {
        I.mode = 'model';
        Bridge.na_call('getThread', { model: true });
        Inspector.na_render();
    };

    function na_on_selection(items) {
        var seen = {};
        var pids = [];
        (items || []).forEach(function (item) { if (!seen[item.pid]) { seen[item.pid] = true; pids.push(item.pid); } });
        var single = pids.length === 1 ? pids[0] : null;
        var digest = single ? na_digest(single) : '';
        var rowDigest = single ? na_row_digest(single) : '';
        var changed = pids.join(',') !== I.pids.join(',');
        var notesMoved = !!single && digest !== I.digest;
        var rowMoved = !!single && rowDigest !== I.rowDigest;
        if (changed && I.mode === 'model') I.mode = 'auto';
        if (single && (changed || notesMoved)) {
            var row = Store.na_row(single);
            if (row && (row.nc || row.nf || row.nu || row.nw)) Bridge.na_call('getThread', { pids: [single] });
            else Store.na_state().threads[single] = { status: '', entries: [], target: single };
        }
        I.pids = pids;
        I.digest = digest;
        I.rowDigest = rowDigest;
        if (changed || notesMoved || rowMoved) Inspector.na_render();                      // <-- Never redraw under Adam's typing for a mere table refresh
    }

    function na_row_digest(pid) {
        var row = Store.na_row(pid);
        var change = Store.na_change(pid);
        return row ? JSON.stringify([row.n, row.dn, row.h, row.l, row.t, row.m, row.sz, row.pre, change ? change.latest : 0]) : '';
    }

    function na_wire_splitter() {
        var splitter = document.getElementById('na-ol-splitter');
        var panel = document.getElementById('na-ol-inspector');
        var width = Number(Shell.na_get_pref('inspectorWidth', 380)) || 380;
        panel.style.width = width + 'px';
        splitter.addEventListener('mousedown', function (event) {
            event.preventDefault();
            var startX = event.clientX, startW = panel.offsetWidth;
            var move = function (e) { panel.style.width = Math.max(260, Math.min(760, startW - (e.clientX - startX))) + 'px'; };
            var up = function () {
                document.removeEventListener('mousemove', move);
                document.removeEventListener('mouseup', up);
                Shell.na_set_pref('inspectorWidth', panel.offsetWidth);
                window.dispatchEvent(new Event('resize'));
            };
            document.addEventListener('mousemove', move);
            document.addEventListener('mouseup', up);
        });
        document.getElementById('na-inspector-toggle').addEventListener('click', function () {
            I.open = !I.open;
            document.getElementById('na-ol-body').classList.toggle('na-ol-body--closed', !I.open);
            Shell.na_set_pref('inspectorOpen', I.open);
            window.dispatchEvent(new Event('resize'));
        });
    }

    function na_init() {
        Shell = window.Na__AgentOutliner__Shell;
        Store = window.Na__AgentOutliner__Store;
        Bridge = window.Na__AgentOutliner__Bridge;
        View = window.Na__AgentOutliner__View;
        na_wire_splitter();

        Shell.na_on('uiSelection', na_on_selection);
        Shell.na_on('thread', function (thread) {
            Store.na_set_thread(thread);
            if ((thread.target === 'model' && I.mode === 'model') || (I.pids.length === 1 && String(I.pids[0]) === String(thread.target))) Inspector.na_render();
            else if (thread.target === 'model' && !I.pids.length) Inspector.na_render();
        });
        Shell.na_on('history', function (payload) { Store.na_set_history(payload); if (I.pids[0] === payload.pid) Inspector.na_render(); });
        Shell.na_on('snapshot', function () { I.historyFor = null; Inspector.na_render(); });
        Shell.na_on('delta', function (delta) { if (!I.pids.length && delta.events && delta.events.length) Inspector.na_render(); });
        Shell.na_on('focusThread', function (pid) {
            window.setTimeout(function () { var area = document.getElementById('na-composer-text'); if (area) area.focus(); }, 50);
        });
        Shell.na_on('focusHistory', function (pid) { I.historyFor = pid; Bridge.na_call('getHistory', { pid: pid }); });
        Shell.na_on('focusModelThread', function () { Inspector.na_show_model_thread(); });
        Shell.na_on('state', function (state) {
            var ui = state.ui || {};
            var open = ui.inspectorOpen === false ? false : true;
            I.open = open;
            document.getElementById('na-ol-body').classList.toggle('na-ol-body--closed', !open);
            if (!I.widthRestored && Number(ui.inspectorWidth) > 0) {                          // <-- Saved width arrives with the first state, after init
                I.widthRestored = true;
                document.getElementById('na-ol-inspector').style.width = Math.max(260, Math.min(760, Number(ui.inspectorWidth))) + 'px';
            }
        });
        Shell.na_on('revealPid', function (pid) {
            var path = Store.na_reachable()[pid];
            if (!path) return;
            if (Store.na_state().view === 'tree') Store.na_reveal(path);
            else if (Store.na_state().view === 'tagtree') Store.na_reveal_tag_tree([path]);     // <-- Its own card (0.1.16)
            View.na_render();
            Bridge.na_call('select', { paths: [path], zoom: false });
        });
        Inspector.na_render();
    }

    window.Na__AgentOutliner__Inspector = Inspector;
    window.Na__AgentOutliner__Shell.na_on('init', na_init);
})();

// =============================================================================
// END OF FILE
// =============================================================================
