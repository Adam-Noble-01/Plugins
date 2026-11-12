// =============================================================================
// NA AGENT OUTLINER - CHAT TAB
// =============================================================================
//
// FILE       : Na__AgentOutliner__UiSystem__Chat__.js
// NAMESPACE  : window.Na__AgentOutliner__Chat
// MODULE     : Na Agent Outliner (Na Noble3d Modelling Tools)
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Every conversation with agents on this model, laid out like a
//              chat app: the chats (the model's own first, then every object
//              thread), the agents who took part, the open chat as bubbles,
//              and a composer that takes pasted pictures.
// CREATED    : 11-Nov-2026 (0.1.6)
//
// DESCRIPTION:
// - DATA: 'chats' (Ruby's list: one line per thread, the agents, the picture
//   folder) and 'thread' (one whole thread, shared with the Inspector through
//   the Store). The list is asked for when the tab opens and, debounced,
//   whenever a thread, a row delta or a snapshot arrives while it shows; an
//   agent's reply through the MCP pushes rows and its thread, so it appears
//   live.
// - PICTURES: Ctrl+V, drag and drop, or the clip button. A picture over 2,400
//   px or 6 MB is redrawn smaller on a canvas, then sent as base64 in pieces
//   ('chatUpload'); Ruby writes it to the chat folder and answers with its
//   name. Send waits for every picture. Pictures are shown from the folder's
//   file:/// URL (state.chat.url) and open full size in a viewer.
// - SENDING: 'comment' with text and pictures, one undo step. Enter sends,
//   Shift+Enter starts a new line.
// - READING: what agents wrote is marked read after 1.2 s on screen.
// - POINTING (0.1.8): the pick button starts a SketchUp tool; the next object
//   clicked in the viewport arrives on 'chatPicked' and goes in the message as
//   "NAME (id 12345)" where the text cursor was (Shift+click: several). In any
//   message "(id 12345)" is a chip: click selects the object, double-click
//   zooms to it.
//
// =============================================================================

(function () {
    'use strict';

    var Shell, Store, Bridge, View;
    var Chat = {};

    var NA_PART_CHARS = 480000;                                                          // <-- base64 characters per upload piece
    var NA_MAX_SIDE   = 2400;                                                            // <-- Longest side kept, in pixels
    var NA_MAX_BYTES  = 6 * 1024 * 1024;                                                 // <-- Bigger files are redrawn smaller
    var NA_MAX_IMAGES = 8;
    var NA_TYPES      = /^image\/(png|jpeg|gif|webp)$/;
    var NA_FILTERS    = [
        { id: 'all',      label: 'All',         title: 'Every chat on this model' },
        { id: 'unread',   label: 'Unread',      title: 'Agents wrote something you have not read' },
        { id: 'mine',     label: 'For Me',      title: 'An agent answered and waits for you' },
        { id: 'agents',   label: 'With Agents', title: 'You wrote, and no agent has picked it up yet' },
        { id: 'resolved', label: 'Resolved',    title: 'Closed chats' }
    ];

    var C = {
        open: 'model',          // the chat on screen: 'model', a pid, or 'new'
        newPids: [],            // a new chat about these objects
        list: null,             // the last 'chats' payload
        filter: 'all',
        agent: '',              // only this agent's chats ('' for every agent)
        search: '',
        drafts: {},             // text per chat key
        pictures: {},           // per chat key: [{id, name, status, file, thumb, w, h, bytes, error}]
        uploads: {},            // upload id -> { key, picture }
        visible: false,
        listTimer: null,
        readTimer: null,
        poll: null,
        shownKey: null,         // the chat whose messages are drawn
        picking: null,          // { key, caret } while the pick tool waits for a click in SketchUp
        stick: true             // keep the newest message in view
    };

    // -------------------------------------------------------------------------
    // REGION | Small Helpers
    // -------------------------------------------------------------------------

    function na_key(open) { return String(open); }
    function na_is_model(open) { return open === 'model'; }

    function na_target(open, extra) {
        var payload = extra || {};
        if (na_is_model(open)) payload.model = true;
        else if (open === 'new') payload.pids = C.newPids.slice();
        else payload.pids = [Number(open)];
        return payload;
    }

    function na_thread(open) {
        var S = Store.na_state();
        if (na_is_model(open)) return S.modelNotes || null;
        return S.threads[open] || S.threads[Number(open)] || null;
    }

    function na_line(open) {
        var threads = C.list && C.list.threads ? C.list.threads : [];
        for (var i = 0; i < threads.length; i++) if (String(threads[i].target) === String(open)) return threads[i];
        return null;
    }

    function na_title(open) {
        if (na_is_model(open)) return 'Model Chat';
        if (open === 'new') return C.newPids.length === 1 ? na_title(C.newPids[0]) : 'New chat about ' + C.newPids.length + ' objects';
        var row = Store.na_row(Number(open));
        var line = na_line(open);
        return (row && row.dn) || (line && line.name) || ('Object ' + open);
    }

    // 0.1.9: pictures agents send (agt_...) live in their own folder.
    function na_folder_url(file) {
        var state = Shell.na_get_state() || {};
        var chat = state.chat || {};
        if (/^agt_/.test(String(file || '')) && chat.agent_url) return chat.agent_url;
        return chat.url || '';
    }

    Chat.na_picture_url = function (file) { return na_folder_url(file) + encodeURIComponent(file); };

    // A steady colour per agent name, so each agent keeps its own avatar.
    function na_agent_colour(name) {
        var palette = ['#7c3aed', '#2563eb', '#0891b2', '#0d9488', '#4f46e5', '#9333ea', '#0369a1', '#be185d'];
        var hash = 0;
        String(name || '').split('').forEach(function (ch) { hash = (hash * 31 + ch.charCodeAt(0)) >>> 0; });
        return palette[hash % palette.length];
    }

    // "Claude (bay window session)" -> CB, "Claude (lantern session)" -> CL: the
    // session in brackets tells apart agents that share a name.
    function na_initials(name) {
        var text = String(name || '');
        var inner = (text.match(/\(([^)]*)\)/) || [])[1] || '';
        var words = text.replace(/\(.*\)/, '').trim().split(/\s+/).filter(Boolean);
        if (!words.length) return '?';
        var second = inner.trim() ? inner.trim()[0] : (words.length > 1 ? words[1][0] : '');
        return (words[0][0] + second).toUpperCase();
    }

    function na_avatar(name, mine) {
        var avatar = Shell.na_el('span', 'na-chat-avatar' + (mine ? ' na-chat-avatar--me' : ''), mine ? 'Me' : na_initials(name));
        if (!mine) avatar.style.background = na_agent_colour(name);
        avatar.title = mine ? 'You' : name;
        return avatar;
    }

    function na_day_label(seconds) {
        var date = new Date(seconds * 1000);
        var today = new Date();
        var start = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime() / 1000;
        if (seconds >= start) return 'Today';
        if (seconds >= start - 86400) return 'Yesterday';
        var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return date.getDate() + ' ' + months[date.getMonth()] + ' ' + date.getFullYear();
    }

    function na_clock(seconds) {
        var date = new Date(seconds * 1000);
        var pad = function (n) { return (n < 10 ? '0' : '') + n; };
        return pad(date.getHours()) + ':' + pad(date.getMinutes());
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Asking Ruby (debounced)
    // -------------------------------------------------------------------------

    function na_request_list(delay) {
        if (C.listTimer) window.clearTimeout(C.listTimer);
        C.listTimer = window.setTimeout(function () {
            C.listTimer = null;
            Bridge.na_call('getChats', {});
        }, delay === undefined ? 400 : delay);
    }

    function na_request_thread(open) {
        if (open === 'new') return;
        Bridge.na_call('getThread', na_is_model(open) ? { model: true } : { pids: [Number(open)] });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | The Side: agents, filters, the chats
    // -------------------------------------------------------------------------

    function na_render_side() {
        na_render_filters();
        na_render_agents();
        na_render_list();
        na_render_bridge();
    }

    function na_render_filters() {
        var host = Shell.na_clear(document.getElementById('na-chat-filters'));
        var threads = C.list ? C.list.threads : [];
        var counts = {
            all: threads.filter(function (t) { return t.entries > 0; }).length,
            unread: threads.filter(function (t) { return t.unread_by_adam > 0; }).length,
            mine: threads.filter(function (t) { return t.waiting_on === 'user'; }).length,
            agents: threads.filter(function (t) { return t.waiting_on === 'agent'; }).length,
            resolved: threads.filter(function (t) { return t.status === 'resolved'; }).length
        };
        NA_FILTERS.forEach(function (filter) {
            var pill = Shell.na_button(filter.label + (counts[filter.id] ? ' ' + counts[filter.id] : ''), 'na-chat-pill' + (C.filter === filter.id ? ' na-chat-pill--on' : ''), function () {
                C.filter = C.filter === filter.id && filter.id !== 'all' ? 'all' : filter.id;
                na_render_side();
            }, filter.title);
            host.appendChild(pill);
        });
    }

    function na_render_agents() {
        var host = Shell.na_clear(document.getElementById('na-chat-agents'));
        var agents = C.list && C.list.agents ? C.list.agents : [];
        if (!agents.length) {
            host.appendChild(Shell.na_el('p', 'na-chat-agents__none', 'No agent has written on this model yet. Agents sign their messages, so each one shows here with its chats.'));
            return;
        }
        host.appendChild(Shell.na_el('div', 'na-chat-heading', 'Agents on this model'));
        var row = Shell.na_el('div', 'na-chat-agents__row');
        agents.forEach(function (agent) {
            var seconds = Shell.na_iso_seconds(agent.last_at);
            var active = seconds && Date.now() / 1000 - seconds < 3600;
            var chip = Shell.na_el('button', 'na-chat-agent' + (C.agent === agent.author ? ' na-chat-agent--on' : ''));
            chip.type = 'button';
            chip.appendChild(na_avatar(agent.author, false));
            var text = Shell.na_el('span', 'na-chat-agent__text');
            text.appendChild(Shell.na_el('span', 'na-chat-agent__name', agent.author));
            text.appendChild(Shell.na_el('span', 'na-chat-agent__meta', (active ? 'active ' : '') + Shell.na_ago(seconds) + ' \u00b7 ' + agent.chats + ' chat' + (agent.chats === 1 ? '' : 's')));
            chip.appendChild(text);
            if (active) chip.appendChild(Shell.na_el('span', 'na-chat-agent__live'));
            chip.title = agent.author + ': ' + agent.messages + ' message' + (agent.messages === 1 ? '' : 's') + ' in ' + agent.chats + ' chat' + (agent.chats === 1 ? '' : 's') +
                         ', last ' + Shell.na_when(seconds) + '. Click to see only its chats.';
            chip.addEventListener('click', function () { C.agent = C.agent === agent.author ? '' : agent.author; na_render_side(); });
            row.appendChild(chip);
        });
        host.appendChild(row);
    }

    function na_visible_lines() {
        var threads = C.list ? C.list.threads.slice() : [{ target: 'model', entries: 0, agents: [] }];
        var words = C.search.toLowerCase();
        return threads.filter(function (line) {
            var model = line.target === 'model';
            if (C.agent && (line.agents || []).indexOf(C.agent) < 0) return false;
            if (C.filter === 'unread' && !(line.unread_by_adam > 0)) return false;
            if (C.filter === 'mine' && line.waiting_on !== 'user') return false;
            if (C.filter === 'agents' && line.waiting_on !== 'agent') return false;
            if (C.filter === 'resolved' && line.status !== 'resolved') return false;
            if (C.filter !== 'all' && model && !line.entries) return false;
            if (words) {
                var hay = [na_title(line.target), line.last ? line.last.text : '', line.last ? line.last.author : '', (line.agents || []).join(' '), line.path || ''].join(' ').toLowerCase();
                if (hay.indexOf(words) < 0) return false;
            }
            return true;
        }).sort(function (a, b) {
            if (a.target === 'model') return -1;                                          // <-- The model's own chat stays at the top
            if (b.target === 'model') return 1;
            var at = a.last ? Shell.na_iso_seconds(a.last.at) : 0;
            var bt = b.last ? Shell.na_iso_seconds(b.last.at) : 0;
            return bt - at;
        });
    }

    function na_render_list() {
        var host = Shell.na_clear(document.getElementById('na-chat-list'));
        var lines = na_visible_lines();
        if (C.open === 'new') host.appendChild(na_list_item({ target: 'new', entries: 0, agents: [] }, true));
        lines.forEach(function (line) { host.appendChild(na_list_item(line, String(line.target) === String(C.open))); });
        if (!lines.length) host.appendChild(Shell.na_el('p', 'na-chat-empty-list', C.search || C.filter !== 'all' || C.agent ? 'No chat matches.' : 'No chats yet.'));
    }

    function na_list_item(line, active) {
        var model = line.target === 'model';
        var item = Shell.na_el('button', 'na-chat-item' + (active ? ' na-chat-item--active' : '') + (line.status === 'resolved' ? ' na-chat-item--resolved' : ''));
        item.type = 'button';
        var icon = Shell.na_el('span', 'na-chat-item__icon' + (model ? ' na-chat-item__icon--model' : ''));
        if (model) icon.textContent = '\u2726';
        else if (line.target === 'new') icon.textContent = '+';
        else icon.appendChild(View.na_icon(line.kind || (Store.na_row(Number(line.target)) || {}).k || 'g'));
        item.appendChild(icon);

        var body = Shell.na_el('span', 'na-chat-item__body');
        var top = Shell.na_el('span', 'na-chat-item__top');
        top.appendChild(Shell.na_el('span', 'na-chat-item__title', line.target === 'new' ? na_title('new') : na_title(line.target)));
        if (line.last) top.appendChild(Shell.na_el('span', 'na-chat-item__time', Shell.na_ago(Shell.na_iso_seconds(line.last.at))));
        body.appendChild(top);
        var preview = '';
        if (line.target === 'new') preview = 'Write the first message below.';
        else if (line.last) {
            var who = line.last.by === 'user' ? 'You' : (line.last.author || 'Agent');
            var said = line.last.text || (line.last.images ? '[picture]' : '');
            preview = (line.last.kind && line.last.kind !== 'comment') ? who + ': ' + said : who + ': ' + said;
        } else if (model) preview = 'Write to every agent on this model.';
        body.appendChild(Shell.na_el('span', 'na-chat-item__preview', preview));
        item.appendChild(body);

        var badges = Shell.na_el('span', 'na-chat-item__badges');
        if (line.unread_by_adam > 0) badges.appendChild(Shell.na_el('span', 'na-chat-badge na-chat-badge--unread', String(line.unread_by_adam)));
        if (line.waiting_on === 'agent') badges.appendChild(Shell.na_el('span', 'na-chat-badge na-chat-badge--waiting', 'with agent'));
        else if (line.waiting_on === 'user') badges.appendChild(Shell.na_el('span', 'na-chat-badge na-chat-badge--mine', 'for you'));
        if (line.flag) {
            var type = Store.na_flag_type(line.flag);
            var flag = Shell.na_el('span', 'na-chat-badge na-chat-badge--flag', type ? type.label : line.flag);
            if (type) flag.style.setProperty('--na-flag', type.colour);
            badges.appendChild(flag);
        }
        if (line.images) badges.appendChild(Shell.na_el('span', 'na-chat-badge na-chat-badge--pics', '\u25a3 ' + line.images));
        item.appendChild(badges);
        item.title = line.path ? line.path : na_title(line.target);
        item.addEventListener('click', function () { if (line.target !== 'new') Chat.na_open(line.target); });
        return item;
    }

    function na_render_bridge() {
        var host = Shell.na_clear(document.getElementById('na-chat-bridge'));
        var state = Shell.na_get_state() || {};
        var mcp = state.mcp || {};
        var on = mcp.loaded && mcp.running;
        host.appendChild(Shell.na_el('span', 'na-chat-bridge__dot' + (on ? ' na-chat-bridge__dot--on' : '')));
        var text = on ? 'Agent bridge on' : 'Agent bridge off: no agent can reach this model';
        if (on && mcp.last && mcp.last.tool) text += ' \u00b7 last call ' + (mcp.last.time || '') + ' (' + mcp.last.tool + ')';
        host.appendChild(Shell.na_el('span', 'na-chat-bridge__text', text));
        var cache = C.list && C.list.cache ? C.list.cache : null;
        if (cache && cache.files) host.title = cache.files + ' picture' + (cache.files === 1 ? '' : 's') + ' in the chat folder (' + (cache.bytes / 1048576).toFixed(1) + ' MB): ' + cache.folder;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | The Open Chat: header and messages
    // -------------------------------------------------------------------------

    // FUNCTION | Open a Chat ('model', a pid, or the selected objects for a new one)
    Chat.na_open = function (open) {
        C.open = na_is_model(open) || open === 'new' ? open : Number(open);
        C.stick = true;
        C.shownKey = null;
        na_render_side();
        na_render_head();
        na_render_messages();
        na_render_composer();
        na_request_thread(C.open);
        window.setTimeout(function () { var area = document.getElementById('na-chat-text'); if (area) area.focus(); }, 30);
    };

    function na_render_head() {
        var host = Shell.na_clear(document.getElementById('na-chat-head'));
        var open = C.open;
        var title = Shell.na_el('div', 'na-chat-head__title');
        title.appendChild(Shell.na_el('span', 'na-chat-head__name', na_title(open)));
        var sub = '';
        var line = na_line(open);
        if (na_is_model(open)) sub = 'Every agent on this model reads this chat (agent_outliner inbox); agents post their summaries here.';
        else if (open === 'new') sub = C.newPids.map(function (pid) { var row = Store.na_row(pid); return row ? row.dn : pid; }).slice(0, 6).join(', ') + (C.newPids.length > 6 ? ' \u2026' : '');
        else {
            var row = Store.na_row(Number(open));
            sub = (row ? Store.na_type_name(row.k) : (line && line.type) || 'Object') + (line && line.path ? '  \u00b7  ' + line.path : '') + '  \u00b7  id ' + open;
        }
        title.appendChild(Shell.na_el('span', 'na-chat-head__sub', sub));
        host.appendChild(title);

        var actions = Shell.na_el('div', 'na-chat-head__actions');
        if (!na_is_model(open) && open !== 'new') {
            var pid = Number(open);
            var path = Store.na_reachable()[pid] || [pid];
            actions.appendChild(Shell.na_button('Select', null, function () { Bridge.na_call('select', { paths: [path], zoom: false }); }, 'Select it in SketchUp'));
            actions.appendChild(Shell.na_button('Zoom', null, function () { Bridge.na_call('select', { paths: [path], zoom: true }); }, 'Select it and zoom to it'));
            actions.appendChild(Shell.na_button('In Outliner', null, function () { Shell.na_activate_tab('outliner'); Shell.na_emit('revealPid', pid); }, 'Show its row in the Outliner tab'));
            actions.appendChild(Shell.na_button('Flag \u25be', null, function (event) {
                var rect = event.target.getBoundingClientRect();
                View.na_flag_menu_for(rect.left, rect.bottom + 2, [pid]);
            }, 'Flag it for an agent'));
        }
        var thread = na_thread(open);
        var status = thread ? thread.status : (line ? line.status : '');
        if (status && open !== 'new') {
            actions.appendChild(Shell.na_button(status === 'resolved' ? 'Reopen' : 'Resolve', status === 'resolved' ? null : 'naButtonSecondary na-button--small na-chat-resolve', function () {
                Bridge.na_call('setThreadStatus', na_target(open, { status: status === 'resolved' ? 'open' : 'resolved' }));
                na_request_list(300);
            }, status === 'resolved' ? 'Open this chat again' : 'Close this chat: it leaves the agents\u2019 inbox'));
        }
        host.appendChild(actions);
    }

    function na_render_messages() {
        var host = document.getElementById('na-chat-messages');
        var open = C.open;
        var thread = na_thread(open);
        var nearBottom = host.scrollHeight - host.scrollTop - host.clientHeight < 80;
        var keep = C.shownKey === na_key(open) && !nearBottom ? host.scrollTop : null;
        Shell.na_clear(host);
        C.shownKey = na_key(open);

        if (open === 'new') {
            host.appendChild(na_empty('A new chat', 'Your first message goes on ' + (C.newPids.length === 1 ? 'this object' : 'each of these ' + C.newPids.length + ' objects') +
                                      '. Agents find it with agent_outliner inbox and answer here.'));
            return;
        }
        if (!thread) {
            var line = na_line(open);
            if (line && line.entries) { host.appendChild(Shell.na_el('p', 'na-chat-loading', 'Loading the chat\u2026')); return; }
            host.appendChild(na_empty(na_is_model(open) ? 'Talk to every agent on this model' : 'No messages yet',
                na_is_model(open) ? 'Write here, paste screenshots (Ctrl+V), and agents answer in this chat. They read it with agent_outliner inbox.'
                                  : 'Write the first message below. Agents read it with agent_outliner inbox and answer here.'));
            return;
        }
        var entries = thread.entries || [];
        if (!entries.length) { host.appendChild(na_empty('No messages yet', 'Write the first message below.')); return; }

        var lastDay = '';
        var unread = [];
        var dividerDone = false;
        entries.forEach(function (entry, index) {
            var seconds = Shell.na_iso_seconds(entry.at);
            var day = na_day_label(seconds);
            if (day !== lastDay) { host.appendChild(Shell.na_el('div', 'na-chat-day', day)); lastDay = day; }
            if (entry.new_for_adam && !dividerDone) { host.appendChild(Shell.na_el('div', 'na-chat-new-divider', 'New')); dividerDone = true; }
            if (entry.new_for_adam) unread.push(entry.id);
            var previous = entries[index - 1];
            var grouped = previous && previous.kind === 'comment' && entry.kind === 'comment' && previous.by === entry.by && previous.author === entry.author &&
                          seconds - Shell.na_iso_seconds(previous.at) < 300;
            host.appendChild(na_message(entry, grouped));
        });

        if (keep !== null) host.scrollTop = keep;
        else window.setTimeout(function () { host.scrollTop = host.scrollHeight; }, 0);

        if (unread.length && C.visible) {
            if (C.readTimer) window.clearTimeout(C.readTimer);
            C.readTimer = window.setTimeout(function () {
                C.readTimer = null;
                if (!C.visible || C.shownKey !== na_key(open)) return;
                Bridge.na_call('markRead', { ids: unread, pids: na_is_model(open) ? [] : [Number(open)], model: na_is_model(open) });
                na_request_list(600);
            }, 1200);
        }
    }

    function na_empty(title, text) {
        var box = Shell.na_el('div', 'na-chat-empty');
        box.appendChild(Shell.na_el('div', 'na-chat-empty__icon', '\u2726'));
        box.appendChild(Shell.na_el('div', 'na-chat-empty__title', title));
        box.appendChild(Shell.na_el('div', 'na-chat-empty__text', text));
        return box;
    }

    function na_message(entry, grouped) {
        var mine = entry.by === 'user';
        var seconds = Shell.na_iso_seconds(entry.at);
        if (entry.kind && entry.kind !== 'comment') {
            var line = Shell.na_el('div', 'na-chat-event na-chat-event--' + entry.by);
            line.textContent = (mine ? 'You' : (entry.author || 'Agent')) + ': ' + entry.text + '  \u00b7  ' + na_clock(seconds);
            return line;
        }
        var row = Shell.na_el('div', 'na-chat-msg ' + (mine ? 'na-chat-msg--me' : 'na-chat-msg--agent') + (grouped ? ' na-chat-msg--grouped' : '') + (entry.new_for_adam ? ' na-chat-msg--new' : ''));
        if (!mine) row.appendChild(grouped ? Shell.na_el('span', 'na-chat-avatar na-chat-avatar--spacer') : na_avatar(entry.author || 'Agent', false));
        var column = Shell.na_el('div', 'na-chat-msg__column');
        if (!grouped) {
            var meta = Shell.na_el('div', 'na-chat-msg__meta');
            meta.appendChild(Shell.na_el('span', 'na-chat-msg__author', mine ? 'You' : (entry.author || 'Agent')));
            meta.appendChild(Shell.na_el('span', 'na-chat-msg__time', na_clock(seconds)));
            column.appendChild(meta);
        }
        var bubble = Shell.na_el('div', 'na-chat-bubble');
        if (!mine) bubble.style.setProperty('--na-agent-tint', na_agent_colour(entry.author || 'Agent'));
        if (entry.text) bubble.appendChild(Chat.na_rich_text(entry.text, 'na-chat-bubble__text'));
        var pictures = Chat.na_images(entry);
        if (pictures) bubble.appendChild(pictures);
        column.appendChild(bubble);
        var foot = Shell.na_el('div', 'na-chat-msg__foot');
        if (entry.effort) foot.appendChild(Shell.na_el('span', 'na-chat-msg__effort', na_effort_name(entry.effort)));
        if (mine) foot.appendChild(Shell.na_el('span', 'na-chat-msg__tick' + (entry.new_for_agent ? '' : ' na-chat-msg__tick--read'),
                                               entry.new_for_agent ? '\u2713 sent' : '\u2713\u2713 read by an agent'));
        if (grouped) foot.appendChild(Shell.na_el('span', 'na-chat-msg__time', na_clock(seconds)));
        var remove = Shell.na_button('Delete', 'na-chat-msg__delete', function () {
            Shell.na_confirm({ title: 'Delete This Message?', text: 'It is removed from the model (Ctrl+Z in SketchUp brings it back). Its pictures stay in the chat folder.', confirm: 'Delete', danger: true },
                function () { Bridge.na_call('deleteEntry', na_target(C.open, { entry: entry.id })); na_request_list(400); });
        }, 'Delete this message');
        foot.appendChild(remove);
        column.appendChild(foot);
        row.appendChild(column);
        return row;
    }

    // FUNCTION | The Pictures on an Entry (the Inspector's thread uses it too)
    Chat.na_images = function (entry) {
        var images = entry && entry.images ? entry.images : [];
        if (!images.length) return null;
        var grid = Shell.na_el('div', 'na-chat-pics na-chat-pics--' + Math.min(images.length, 3));
        images.forEach(function (image) {
            var tile = Shell.na_el('button', 'na-chat-pic');
            tile.type = 'button';
            if (image.exists === false) {
                tile.classList.add('na-chat-pic--missing');
                tile.appendChild(Shell.na_el('span', 'na-chat-pic__missing', 'Picture not on this PC'));
                tile.title = image.file;
            } else {
                var img = Shell.na_el('img');
                img.alt = image.name || 'Picture';
                img.loading = 'lazy';
                img.src = Chat.na_picture_url(image.file);
                img.addEventListener('error', function () {
                    tile.classList.add('na-chat-pic--missing');
                    Shell.na_clear(tile).appendChild(Shell.na_el('span', 'na-chat-pic__missing', 'Picture not found'));
                });
                tile.appendChild(img);
                tile.title = (image.name || image.file) + (image.w ? '  (' + image.w + ' x ' + image.h + ')' : '') + '. Click to see it full size.';
                tile.addEventListener('click', function () { Chat.na_lightbox(image); });
            }
            grid.appendChild(tile);
        });
        return grid;
    };

    // FUNCTION | A Picture Full Size, Over Everything
    Chat.na_lightbox = function (image) {
        var box = document.getElementById('na-chat-lightbox');
        Shell.na_clear(box);
        var frame = Shell.na_el('div', 'na-chat-lightbox__frame');
        var img = Shell.na_el('img', 'na-chat-lightbox__img');
        img.src = Chat.na_picture_url(image.file);
        img.alt = image.name || 'Picture';
        frame.appendChild(img);
        var bar = Shell.na_el('div', 'na-chat-lightbox__bar');
        bar.appendChild(Shell.na_el('span', 'na-chat-lightbox__name', (image.name || image.file) + (image.w ? '  \u00b7  ' + image.w + ' x ' + image.h + ' px' : '')));
        bar.appendChild(Shell.na_button('Open in Viewer', null, function () { Bridge.na_call('openChatImage', { file: image.file }); }, 'Open it in Windows\u2019 own picture viewer'));
        if (image.path) bar.appendChild(Shell.na_button('Copy Path', null, function () { Shell.na_copy(image.path, 'Copied the picture\u2019s path.'); }, image.path));
        bar.appendChild(Shell.na_button('Close', 'naButton na-button--small', na_close_lightbox));
        frame.appendChild(bar);
        box.appendChild(frame);
        box.classList.remove('na-hidden');
    };

    function na_close_lightbox() { document.getElementById('na-chat-lightbox').classList.add('na-hidden'); }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Object Mentions: "(id 12345)" as a chip that selects the object
    // -------------------------------------------------------------------------

    // FUNCTION | Message Text With Every "(id N)" as a Chip (the Inspector uses it too)
    Chat.na_rich_text = function (text, className) {
        var box = Shell.na_el('div', className || 'na-chat-bubble__text');
        var source = String(text || '');
        var pattern = /\(id (\d{1,15})\)/g;
        var last = 0;
        var match;
        while ((match = pattern.exec(source)) !== null) {
            if (match.index > last) box.appendChild(document.createTextNode(source.slice(last, match.index)));
            box.appendChild(na_ref_chip(Number(match[1])));
            last = match.index + match[0].length;
        }
        if (last < source.length) box.appendChild(document.createTextNode(source.slice(last)));
        return box;
    };

    function na_ref_chip(pid) {
        var row = Store.na_row(pid);
        var chip = Shell.na_el('button', 'na-chat-ref' + (row ? '' : ' na-chat-ref--gone'), 'id ' + pid);
        chip.type = 'button';
        chip.title = row ? row.dn + ': click to select it in SketchUp, double-click to zoom to it'
                         : 'Object ' + pid + ' is not in this model any more (erased, or another model)';
        var path = function () { return Store.na_reachable()[pid] || [pid]; };
        chip.addEventListener('click', function (event) { event.stopPropagation(); if (Store.na_row(pid)) Bridge.na_call('select', { paths: [path()], zoom: false }); });
        chip.addEventListener('dblclick', function (event) { event.stopPropagation(); if (Store.na_row(pid)) Bridge.na_call('select', { paths: [path()], zoom: true }); });
        return chip;
    }

    // A small line icon in the composer's own colour (24 x 24, 1.8 strokes).
    function na_icon(paths) {
        var ns = 'http://www.w3.org/2000/svg';
        var svg = document.createElementNS(ns, 'svg');
        svg.setAttribute('viewBox', '0 0 24 24');
        svg.setAttribute('width', '18');
        svg.setAttribute('height', '18');
        svg.setAttribute('fill', 'none');
        svg.setAttribute('stroke', 'currentColor');
        svg.setAttribute('stroke-width', '1.8');
        svg.setAttribute('stroke-linecap', 'round');
        svg.setAttribute('stroke-linejoin', 'round');
        svg.setAttribute('aria-hidden', 'true');
        paths.forEach(function (d) {
            var path = document.createElementNS(ns, 'path');
            path.setAttribute('d', d);
            svg.appendChild(path);
        });
        return svg;
    }

    var NA_ICON_CLIP = ['M20.5 11.2l-8.4 8.4a5.2 5.2 0 0 1-7.4-7.4l8.4-8.4a3.4 3.4 0 0 1 4.9 4.9l-8.4 8.3a1.7 1.7 0 0 1-2.4-2.4l7.7-7.7'];
    var NA_ICON_PICK = ['M9 9l4.2 11 1.7-4.6 4.6-1.7z', 'M15.2 15.2l4.3 4.3', 'M9 5.2V2.8', 'M5.2 9H2.8', 'M6.2 6.2L4.5 4.5', 'M11.8 6.2l1.7-1.7', 'M6.2 11.8l-1.7 1.7'];

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Pointing at an Object in SketchUp (0.1.8)
    // -------------------------------------------------------------------------

    var NA_PICK_HINT = 'Click an object in SketchUp to put it here \u00b7 right-click: the object around it \u00b7 Ctrl: the part under the cursor \u00b7 Shift+click: several \u00b7 Esc cancels';
    var NA_TYPE_HINT = 'Enter sends \u00b7 Shift+Enter new line \u00b7 Ctrl+V pastes a screenshot \u00b7 drop pictures on the chat \u00b7 the arrow button points at an object in SketchUp';

    // FUNCTION | The Pick Button: start waiting for a click in the viewport, or stop
    function na_toggle_pick(key) {
        if (C.picking) {
            Bridge.na_call('chatPickCancel', {});
            na_pick_finished(false);
            return;
        }
        var area = document.getElementById('na-chat-text');
        var caret = area ? (area.selectionStart === undefined ? area.value.length : area.selectionStart) : (C.drafts[key] || '').length;
        var end = area && area.selectionEnd !== undefined ? area.selectionEnd : caret;
        if (area && end > caret) {                                                       // <-- A selected word is replaced by the object
            area.value = area.value.slice(0, caret) + area.value.slice(end);
            C.drafts[key] = area.value;
        }
        C.picking = { key: key, caret: caret };
        na_render_pick_state();
        Bridge.na_call('chatPick', {});
    }

    function na_render_pick_state() {
        var button = document.getElementById('na-chat-pick');
        var hint = document.getElementById('na-chat-hint');
        var on = !!C.picking && C.picking.key === na_key(C.open);
        if (button) {
            button.classList.toggle('na-chat-pick--on', !!C.picking);
            button.title = C.picking ? 'Waiting for a click in SketchUp: press again (or Esc in SketchUp) to stop'
                                     : 'Point at an object: the next one you click in SketchUp goes in the message where the cursor is';
        }
        if (hint) {
            hint.textContent = on ? NA_PICK_HINT : NA_TYPE_HINT;
            hint.classList.toggle('na-chat-hint--pick', on);
        }
    }

    function na_pick_finished(focus) {
        var key = C.picking ? C.picking.key : null;
        C.picking = null;
        na_render_pick_state();
        if (focus && key === na_key(C.open)) {
            var area = document.getElementById('na-chat-text');
            if (area) area.focus();
        }
    }

    // FUNCTION | Put "NAME (id N)" Where the Cursor Was, Spaced From Its Neighbours
    function na_insert_mention(key, text) {
        var area = document.getElementById('na-chat-text');
        var live = area && na_key(C.open) === key;
        var value = live ? area.value : (C.drafts[key] || '');
        var caret = C.picking && C.picking.key === key ? Math.min(C.picking.caret, value.length) : value.length;
        var before = value.slice(0, caret);
        var after = value.slice(caret);
        var insert = (before && !/\s$/.test(before) ? ' ' : '') + text + (after && /^\s/.test(after) ? '' : ' ');
        value = before + insert + after;
        C.drafts[key] = value;
        if (C.picking && C.picking.key === key) C.picking.caret = caret + insert.length;
        if (live) {
            area.value = value;
            na_grow(area);
            area.setSelectionRange(caret + insert.length, caret + insert.length);
        }
    }

    function na_on_picked(payload) {
        if (!payload) return;
        if (payload.error) Shell.na_set_status(payload.error, 'warn');
        var key = C.picking ? C.picking.key : na_key(C.open);
        (payload.items || []).forEach(function (item) {
            na_insert_mention(key, item.text || ((item.name || 'Object') + ' (id ' + item.pid + ')'));
            Shell.na_set_status('Put ' + (item.name || 'the object') + ' in the message.', 'success');
        });
        if (payload.done) na_pick_finished(!payload.cancelled);
        else if (payload.cancelled) na_pick_finished(false);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | The Composer: text, pictures, send
    // -------------------------------------------------------------------------

    function na_render_composer() {
        var host = Shell.na_clear(document.getElementById('na-chat-composer'));
        var key = na_key(C.open);
        var tray = Shell.na_el('div', 'na-chat-tray');
        tray.id = 'na-chat-tray';
        host.appendChild(tray);

        var row = Shell.na_el('div', 'na-chat-compose-row');
        var clip = Shell.na_button('', 'na-chat-clip', function () { document.getElementById('na-chat-file').click(); },
                                   'Attach pictures (or paste them with Ctrl+V, or drop them on the chat)');
        clip.appendChild(na_icon(NA_ICON_CLIP));
        row.appendChild(clip);
        var pick = Shell.na_button('', 'na-chat-clip na-chat-pick', function () { na_toggle_pick(key); });
        pick.id = 'na-chat-pick';
        pick.appendChild(na_icon(NA_ICON_PICK));
        row.appendChild(pick);
        var file = Shell.na_el('input');
        file.type = 'file';
        file.id = 'na-chat-file';
        file.accept = 'image/png,image/jpeg,image/gif,image/webp';
        file.multiple = true;
        file.className = 'na-hidden';
        file.addEventListener('change', function () {
            Array.prototype.forEach.call(file.files || [], function (one) { na_add_picture(key, one); });
            file.value = '';
        });
        row.appendChild(file);

        var area = Shell.na_el('textarea', 'na-chat-text');
        area.id = 'na-chat-text';
        area.rows = 1;
        area.placeholder = na_is_model(C.open) ? 'Message every agent on this model\u2026' : 'Message an agent about ' + na_title(C.open) + '\u2026';
        area.value = C.drafts[key] || '';
        area.addEventListener('input', function () { C.drafts[key] = area.value; na_grow(area); });
        area.addEventListener('keydown', function (event) {
            event.stopPropagation();
            if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) { event.preventDefault(); na_send(); }
        });
        area.addEventListener('paste', function (event) { na_on_paste(event, key); });
        row.appendChild(area);

        row.appendChild(na_effort_picker());
        var send = Shell.na_button('Send', 'naButton na-chat-send', na_send, 'Send (Enter). Shift+Enter starts a new line.');
        send.id = 'na-chat-send';
        row.appendChild(send);
        host.appendChild(row);
        var hint = Shell.na_el('div', 'na-chat-hint', NA_TYPE_HINT);
        hint.id = 'na-chat-hint';
        host.appendChild(hint);
        na_render_tray();
        na_render_pick_state();
        window.setTimeout(function () { na_grow(area); }, 0);
    }

    // FUNCTION | The Reasoning Effort Picker Beside Send (0.1.14)
    // Adam: "I need a way to set reasoning effort for the messages I send".
    // A Claude session can't change its own effort (the Claude app refuses
    // it), so the effort goes on the message and a dispatcher session sets it
    // for each agent it wakes. Auto leaves the agent's effort as it is. The
    // choice stays until changed, like Claude's own.
    var NA_EFFORTS = [['auto', 'Auto effort'], ['low', 'Low effort'], ['medium', 'Medium effort'], ['high', 'High effort'],
                      ['xhigh', 'Extra High effort'], ['max', 'Max effort']];

    function na_effort() {
        var value = Shell.na_get_pref('chatEffort', 'auto');
        return NA_EFFORTS.some(function (pair) { return pair[0] === value; }) ? value : 'auto';
    }

    function na_effort_picker() {
        var select = Shell.na_el('select', 'na-chat-effort');
        select.id = 'na-chat-effort';
        select.title = 'Reasoning effort for the agents who read this message. A dispatcher session applies it from the agent\u2019s next turn; Auto leaves it as it is.';
        NA_EFFORTS.forEach(function (pair) {
            var option = Shell.na_el('option', null, pair[1]);
            option.value = pair[0];
            select.appendChild(option);
        });
        select.value = na_effort();
        select.classList.toggle('na-chat-effort--set', select.value !== 'auto');
        select.addEventListener('change', function () {
            Shell.na_set_pref('chatEffort', select.value);
            select.classList.toggle('na-chat-effort--set', select.value !== 'auto');
        });
        return select;
    }

    function na_effort_name(value) {
        var pair = NA_EFFORTS.filter(function (item) { return item[0] === value; })[0];
        return pair ? pair[1] : value + ' effort';
    }

    function na_grow(area) {
        area.style.height = 'auto';
        area.style.height = Math.min(180, Math.max(38, area.scrollHeight + 2)) + 'px';
    }

    function na_render_tray() {
        var tray = document.getElementById('na-chat-tray');
        if (!tray) return;
        Shell.na_clear(tray);
        var list = C.pictures[na_key(C.open)] || [];
        tray.classList.toggle('na-hidden', !list.length);
        list.forEach(function (picture) {
            var chip = Shell.na_el('div', 'na-chat-tray__item na-chat-tray__item--' + picture.status);
            if (picture.thumb) {
                var img = Shell.na_el('img');
                img.src = picture.thumb;
                img.alt = picture.name;
                chip.appendChild(img);
            }
            var label = picture.status === 'ready' ? (picture.w ? picture.w + ' x ' + picture.h : 'Ready')
                      : picture.status === 'failed' ? 'Failed' : 'Adding\u2026';
            chip.appendChild(Shell.na_el('span', 'na-chat-tray__label', label));
            if (picture.error) chip.title = picture.error;
            chip.appendChild(Shell.na_button('\u00d7', 'na-chat-tray__remove', function () {
                var all = C.pictures[na_key(C.open)] || [];
                C.pictures[na_key(C.open)] = all.filter(function (item) { return item !== picture; });
                na_render_tray();
            }, 'Take this picture off the message'));
            tray.appendChild(chip);
        });
        var send = document.getElementById('na-chat-send');
        if (send) send.disabled = list.some(function (picture) { return picture.status === 'reading' || picture.status === 'uploading'; });
    }

    function na_on_paste(event, key) {
        var data = event.clipboardData;
        if (!data) return;
        var files = [];
        Array.prototype.forEach.call(data.items || [], function (item) {
            if (item.kind === 'file' && NA_TYPES.test(item.type)) { var one = item.getAsFile(); if (one) files.push(one); }
        });
        if (!files.length && data.files && data.files.length) {
            Array.prototype.forEach.call(data.files, function (one) { if (NA_TYPES.test(one.type)) files.push(one); });
        }
        if (!files.length) return;                                                        // <-- Plain text pastes as usual
        event.preventDefault();
        files.forEach(function (one) { na_add_picture(key, one); });
    }

    // FUNCTION | Add a Picture to the Message Being Written (paste, drop or choose)
    function na_add_picture(key, file) {
        if (!file || !NA_TYPES.test(file.type || '')) return Shell.na_set_status('Only PNG, JPEG, GIF or WebP pictures can go in a chat.', 'warn');
        var list = C.pictures[key] = C.pictures[key] || [];
        if (list.length >= NA_MAX_IMAGES) return Shell.na_set_status('A message can carry ' + NA_MAX_IMAGES + ' pictures at most.', 'warn');
        var picture = { id: 'u' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8), name: file.name && file.name !== 'image.png' ? file.name : 'Pasted picture', status: 'reading' };
        list.push(picture);
        na_render_tray();
        na_prepare(file, function (prepared, error) {
            if (error) { picture.status = 'failed'; picture.error = error; na_render_tray(); return Shell.na_set_status(error, 'warn'); }
            picture.thumb = prepared.dataUrl;
            picture.w = prepared.w;
            picture.h = prepared.h;
            picture.status = 'uploading';
            na_render_tray();
            var base64 = prepared.dataUrl.slice(prepared.dataUrl.indexOf(',') + 1);
            var total = Math.max(1, Math.ceil(base64.length / NA_PART_CHARS));
            C.uploads[picture.id] = { key: key, picture: picture };
            for (var index = 0; index < total; index++) {
                Bridge.na_call('chatUpload', { upload: picture.id, index: index, total: total, name: picture.name, w: prepared.w, h: prepared.h,
                                               data: base64.slice(index * NA_PART_CHARS, (index + 1) * NA_PART_CHARS) });
            }
        });
    }

    // Reads the file, and redraws it smaller when it is very large: PNG stays
    // PNG (crisp screenshots) unless that is still over the limit, then JPEG.
    function na_prepare(file, done) {
        var reader = new FileReader();
        reader.onerror = function () { done(null, 'That picture could not be read.'); };
        reader.onload = function () {
            var dataUrl = String(reader.result || '');
            var img = new Image();
            img.onerror = function () { done(null, 'That file is not a picture this window can show.'); };
            img.onload = function () {
                var w = img.naturalWidth, h = img.naturalHeight;
                var big = Math.max(w, h) > NA_MAX_SIDE || file.size > NA_MAX_BYTES;
                if (!big) return done({ dataUrl: dataUrl, w: w, h: h });
                var scale = Math.min(1, NA_MAX_SIDE / Math.max(w, h));
                var canvas = document.createElement('canvas');
                canvas.width = Math.max(1, Math.round(w * scale));
                canvas.height = Math.max(1, Math.round(h * scale));
                var context = canvas.getContext('2d');
                context.fillStyle = '#ffffff';
                if (file.type === 'image/jpeg') context.fillRect(0, 0, canvas.width, canvas.height);
                context.drawImage(img, 0, 0, canvas.width, canvas.height);
                var smaller = canvas.toDataURL(file.type === 'image/jpeg' ? 'image/jpeg' : 'image/png', 0.92);
                if (smaller.length * 0.75 > NA_MAX_BYTES) {
                    context.globalCompositeOperation = 'destination-over';
                    context.fillRect(0, 0, canvas.width, canvas.height);
                    smaller = canvas.toDataURL('image/jpeg', 0.88);
                }
                done({ dataUrl: smaller, w: canvas.width, h: canvas.height });
            };
            img.src = dataUrl;
        };
        reader.readAsDataURL(file);
    }

    function na_on_upload(result) {
        var job = result && C.uploads[result.upload];
        if (!job) return;
        delete C.uploads[result.upload];
        var picture = job.picture;
        if (result.error) {
            picture.status = 'failed';
            picture.error = result.error;
            Shell.na_set_status(result.error, 'warn');
        } else {
            picture.status = 'ready';
            picture.file = result.file;
            picture.bytes = result.bytes;
            picture.w = result.w || picture.w;
            picture.h = result.h || picture.h;
        }
        if (na_key(C.open) === job.key) na_render_tray();
    }

    // FUNCTION | Send the Message (text and pictures, one undo step)
    function na_send() {
        var key = na_key(C.open);
        var area = document.getElementById('na-chat-text');
        var text = area ? area.value.trim() : '';
        var list = C.pictures[key] || [];
        if (list.some(function (picture) { return picture.status === 'reading' || picture.status === 'uploading'; })) {
            return Shell.na_set_status('Wait a moment: a picture is still being added.', 'info');
        }
        var ready = list.filter(function (picture) { return picture.status === 'ready' && picture.file; });
        if (!text && !ready.length) return Shell.na_set_status('Write a message or paste a picture first.', 'warn');
        if (C.open === 'new' && !C.newPids.length) return Shell.na_set_status('Choose the objects first.', 'warn');
        var payload = na_target(C.open, {
            text: text,
            chat: true,
            images: ready.map(function (picture) { return { file: picture.file, w: picture.w, h: picture.h, name: picture.name }; })
        });
        if (na_effort() !== 'auto') payload.effort = na_effort();
        Bridge.na_call('comment', payload);
        C.drafts[key] = '';
        C.pictures[key] = [];
        if (area) { area.value = ''; na_grow(area); }
        na_render_tray();
        C.stick = true;
        if (C.open === 'new') {
            var first = C.newPids[0];
            C.newPids = [];
            Chat.na_open(first);
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | New Chat, Badge, Wiring
    // -------------------------------------------------------------------------

    // FUNCTION | A New Chat About the Objects Selected in the Outliner
    Chat.na_new = function () {
        var pids = View.na_selected_pids();
        if (!pids.length) {
            Shell.na_set_status('Select objects in the Outliner (or in SketchUp) to start a chat about them. The Model Chat reaches every agent.', 'info');
            return Chat.na_open('model');
        }
        if (pids.length === 1) return Chat.na_open(pids[0]);
        C.newPids = pids.slice(0, 200);
        Chat.na_open('new');
    };

    // The number on the Chat tab: agent messages not read yet.
    function na_update_badge() {
        var badge = document.getElementById('na-chat-badge');
        if (!badge) return;
        var total = 0;
        if (C.list) total = C.list.unread || 0;
        else {
            var ents = Store.na_state().ents || {};
            Object.keys(ents).forEach(function (pid) { total += ents[pid].nu || 0; });
        }
        badge.textContent = total > 99 ? '99+' : String(total);
        badge.classList.toggle('na-hidden', !total);
        badge.title = total ? total + ' message' + (total === 1 ? '' : 's') + ' from agents you have not read' : '';
    }

    function na_on_list(payload) {
        C.list = payload;
        na_update_badge();
        if (!C.visible) return;
        na_render_side();
        na_render_head();
        if (C.open !== 'new' && !na_thread(C.open)) na_request_thread(C.open);
    }

    function na_on_thread(thread) {
        if (!thread) return;
        if (C.visible && String(thread.target) === String(C.open)) {
            na_render_head();
            na_render_messages();
        }
        if (C.visible) na_request_list(500);
    }

    function na_wire() {
        var panel = document.getElementById('na-tab-chat');
        document.getElementById('na-chat-new').addEventListener('click', Chat.na_new);
        var search = document.getElementById('na-chat-search');
        search.addEventListener('input', function () { C.search = search.value.trim(); na_render_list(); });
        search.addEventListener('keydown', function (event) { event.stopPropagation(); if (event.key === 'Escape') { search.value = ''; C.search = ''; na_render_list(); } });

        // Drop pictures anywhere on the open chat
        var main = document.getElementById('na-chat-main');
        var drop = document.getElementById('na-chat-drop');
        var depth = 0;
        main.addEventListener('dragenter', function (event) {
            if (!event.dataTransfer || Array.prototype.indexOf.call(event.dataTransfer.types || [], 'Files') < 0) return;
            depth += 1;
            drop.classList.remove('na-hidden');
        });
        main.addEventListener('dragleave', function () { depth = Math.max(0, depth - 1); if (!depth) drop.classList.add('na-hidden'); });
        main.addEventListener('dragover', function (event) { if (event.dataTransfer) { event.preventDefault(); event.dataTransfer.dropEffect = 'copy'; } });
        main.addEventListener('drop', function (event) {
            event.preventDefault();
            depth = 0;
            drop.classList.add('na-hidden');
            var files = event.dataTransfer ? event.dataTransfer.files : [];
            Array.prototype.forEach.call(files || [], function (one) { na_add_picture(na_key(C.open), one); });
        });
        // A paste of a picture anywhere on the tab goes to the open chat
        panel.addEventListener('paste', function (event) {
            if (event.target && event.target.id === 'na-chat-text') return;
            if (event.target && /INPUT|TEXTAREA/.test(event.target.tagName)) return;
            na_on_paste(event, na_key(C.open));
        });

        var lightbox = document.getElementById('na-chat-lightbox');
        lightbox.addEventListener('click', function (event) { if (event.target === lightbox) na_close_lightbox(); });
        document.addEventListener('keydown', function (event) { if (event.key === 'Escape' && !lightbox.classList.contains('na-hidden')) na_close_lightbox(); });
        document.getElementById('na-chat-messages').addEventListener('scroll', function () {
            var host = document.getElementById('na-chat-messages');
            C.stick = host.scrollHeight - host.scrollTop - host.clientHeight < 80;
        });
    }

    function na_on_tab(tab) {
        var was = C.visible;
        C.visible = tab === 'chat';
        if (C.poll) { window.clearInterval(C.poll); C.poll = null; }
        if (!C.visible) return;
        C.poll = window.setInterval(function () { if (C.visible) na_request_list(0); }, 30000);
        if (!was) {
            na_render_side();
            na_render_head();
            na_render_messages();
            na_render_composer();
        }
        na_request_list(0);
        na_request_thread(C.open);
    }

    function na_init() {
        Shell = window.Na__AgentOutliner__Shell;
        Store = window.Na__AgentOutliner__Store;
        Bridge = window.Na__AgentOutliner__Bridge;
        View = window.Na__AgentOutliner__View;
        na_wire();
        Shell.na_on('tab', na_on_tab);
        Shell.na_on('chats', na_on_list);
        Shell.na_on('chatUpload', na_on_upload);
        Shell.na_on('chatPicked', na_on_picked);
        Shell.na_on('thread', na_on_thread);
        Shell.na_on('delta', function () { na_update_badge(); if (C.visible) na_request_list(700); });
        Shell.na_on('snapshot', function (payload) {
            var key = payload && payload.model ? payload.model.key || payload.model.path || payload.model.title : '';
            if (key === C.modelKey) { if (C.visible) na_request_list(300); return; }       // <-- A Refresh of the same model keeps the open chat
            C.modelKey = key;
            C.list = null;
            C.newPids = [];
            Store.na_state().modelNotes = null;
            na_update_badge();
            if (C.visible) Chat.na_open('model');
            else C.open = 'model';
        });
        Shell.na_on('state', function () { if (C.visible) na_render_bridge(); });
        Shell.na_on('openChat', function (open) { Shell.na_activate_tab('chat'); Chat.na_open(open); });
    }

    window.Na__AgentOutliner__Chat = Chat;
    window.Na__AgentOutliner__Shell.na_on('init', na_init);
})();

// =============================================================================
// END OF FILE
// =============================================================================
