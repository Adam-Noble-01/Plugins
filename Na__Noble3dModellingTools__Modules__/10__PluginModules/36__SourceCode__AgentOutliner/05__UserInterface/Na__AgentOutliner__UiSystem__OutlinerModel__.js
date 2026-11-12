// =============================================================================
// NA AGENT OUTLINER - UI SYSTEM - OUTLINER MODEL (THE PAGE'S DATA STORE)
// =============================================================================
//
// FILE       : Na__AgentOutliner__UiSystem__OutlinerModel__.js
// NAMESPACE  : window.Na__AgentOutliner__Store
// MODULE     : Store (IIFE)
// AUTHOR     : Noble Architecture
// PURPOSE    : Hold the model's objects as Ruby sent them, and turn them into
//              the list of rows the table shows: the tree (or a flat or
//              grouped list), searched, filtered and sorted
// CREATED    : 10-Nov-2026
//
// DESCRIPTION:
// - THE DATA is a graph, not a list of occurrences: ents (one row per object,
//   keyed by persistent id), defs (each definition's children) and roots. An
//   instance expands into its definition's children, so a component placed 29
//   times is sent once. A row on screen is an OCCURRENCE: the path of ids from
//   the root, joined with '/' as its key.
// - FILTERING keeps a match's parents on screen (dimmed) and opens them, so a
//   match is always seen in place, never torn out of its tree (SketchUp's own
//   filter is names only). "Does this definition hold a match anywhere below"
//   is worked out once per definition, so a big model filters fast.
// - THE SEARCH LANGUAGE is the same as the MCP's agent_outliner find:
//     words, field:value (name def tag type flag by is has prefix id mat note),
//     -term, "a phrase", /pattern/, a | b (OR; side by side is AND)
// - QUICK FILTERS: chips in the same family (change, actor, notes, state) are
//   OR'd, different families AND'd: New + Updated + By Agent = what an agent
//   made or changed.
// - COLOUR GRADING: every change carries who (agent or Adam) and when; the
//   age falls into one of Settings' four bands, and the band sets how strong
//   the row's tint is. Older than the last band, a row is plain again.
// - SORTING: any column, natural order (W2 before W10), Shift adds a second
//   key; in the tree it sorts each group's children.
// - TREE BY TAG (0.1.16): tag folders and tags are the levels, and under each
//   tag its objects are listed as a tree. Every row carries its block (the
//   tag, its colour and depth) so the table can band and wash it.
//
// =============================================================================

(function () {
    'use strict';

    var Store = {};
    var S = {
        model: null, ents: {}, defs: {}, roots: [], tags: {}, status: {}, events: [], seq: 0,
        seen: { user_seq: 0, agent_seq: 0 }, tracking: null, modelNotes: null,
        standards: { prefixes: [], flags: [], handoff: {} }, settings: {}, userName: 'Adam',
        selectionIds: {}, activePath: [],
        view: 'tree', search: '', quick: {}, sort: [{ col: 'name', dir: 1 }],
        expanded: {}, searchCollapsed: {}, groupCollapsed: {},
        rows: [], matchCount: 0, truncated: false, version: 0, threads: {}, history: {}
    };
    var na_expanded_by_model = {};
    var na_sorted_cache = {};
    var na_collator = (window.Intl && Intl.Collator) ? new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' }) : null;

    var NA_MAX_ROWS   = 60000;
    var NA_TYPE_WORDS = { group: 'g', groups: 'g', component: 'c', components: 'c', comp: 'c', image: 'i', images: 'i', section: 's', sections: 's' };
    var NA_TYPE_NAMES = { g: 'Group', c: 'Component', i: 'Image', s: 'Section Plane' };
    var NA_TYPE_ORDER = { g: 1, c: 2, i: 3, s: 4 };
    var NA_FIELDS     = ['name', 'def', 'tag', 'type', 'flag', 'by', 'is', 'has', 'prefix', 'id', 'pid', 'mat', 'note', 'face', 'dir'];

    // Elevation faces (Adam's standard, 11-Nov-2026): SketchUp's default ortho views, a SEGMENT inside a name
    // (SUB__Orangery__DoorHandle__Front__01), with the real-world cardinal after it once the model has an orientation.
    var NA_FACES      = ['Front', 'Back', 'Left', 'Right', 'Top'];
    var NA_CARDINALS  = ['North', 'East', 'South', 'West'];
    var NA_FACE_TURNS = { Front: 0, Left: 1, Back: 2, Right: 3 };

    // FUNCTION | The Face and Cardinal a Name Carries: [face or '', cardinal or '']
    Store.na_face_of = function (name) {
        var parts = String(name || '').split('__');
        for (var i = 0; i < parts.length; i++) {
            if (NA_FACES.indexOf(parts[i]) >= 0) return [parts[i], NA_CARDINALS.indexOf(parts[i + 1]) >= 0 ? parts[i + 1] : ''];
        }
        return ['', ''];
    };

    // FUNCTION | The Cardinal a Face Points To With the Model's Orientation ('' when none)
    Store.na_cardinal_for = function (face) {
        var front = S.model ? S.model.front_faces : '';
        var start = NA_CARDINALS.indexOf(front || '');
        var turns = NA_FACE_TURNS[face];
        return (start < 0 || turns === undefined) ? '' : NA_CARDINALS[(start + turns) % 4];
    };
    Store.na_cardinals = function () { return NA_CARDINALS.slice(); };

    function na_face_chip(face) {
        return { id: 'face_' + face.toLowerCase(), label: face, family: 'face',
                 title: 'On the ' + face + ' elevation: the name carries __' + face + '__ (search face:' + face.toLowerCase() + ')',
                 test: function (r) { return Store.na_face_of(r.n)[0] === face; } };
    }

    // The quick filter chips: id, label, family, and the test.
    var NA_QUICK = [
        { id: 'flagged',  label: 'Flagged',   family: 'notes',  title: 'Carries a flag',                                     test: function (r) { return !!r.nf; } },
        { id: 'notes',    label: 'Notes',     family: 'notes',  title: 'Has a comment thread',                               test: function (r) { return (r.nc || 0) > 0; } },
        { id: 'unread',   label: 'Unread',    family: 'notes',  title: 'An agent wrote something you have not read',         test: function (r) { return (r.nu || 0) > 0; } },
        { id: 'waiting',  label: 'Waiting',   family: 'notes',  title: 'Waiting for an agent: your comments or inbox flags', test: function (r) { return (r.nw || 0) > 0; } },
        { id: 'new',      label: 'New',       family: 'change', title: 'Made within the colour window',                      test: function (r, c) { return !!c && c.kind === 'new'; } },
        { id: 'updated',  label: 'Updated',   family: 'change', title: 'Changed within the colour window',                   test: function (r, c) { return !!c && c.kind === 'updated'; } },
        { id: 'recent',   label: 'Recent',    family: 'change', title: 'New or changed within the second band (Settings)',   test: function (r, c) { return !!c && c.recent; } },
        { id: 'unseen',   label: 'Unseen',    family: 'change', title: 'Changed since you last pressed Mark Seen',           test: function (r, c) { return !!c && c.unseen; } },
        { id: 'agent',    label: 'By Agent',  family: 'actor',  title: 'Last made or changed by an agent',                   test: function (r, c) { return !!c && c.by === 'agent'; } },
        { id: 'user',     label: 'By Me',     family: 'actor',  title: 'Last made or changed by you',                        test: function (r, c) { return !!c && c.by === 'user'; } },
        { id: 'hidden',   label: 'Hidden',    family: 'state',  title: 'Hidden itself, or on a hidden tag',                  test: function (r) { return r.h || !Store.na_tag_shown(r.t); } },
        { id: 'locked',   label: 'Locked',    family: 'state',  title: 'Locked',                                             test: function (r) { return !!r.l; } },
        { id: 'unnamed',  label: 'Unnamed',   family: 'state',  title: 'No name of its own (shows as Group or its definition)', test: function (r) { return !r.n; } },
        { id: 'selected', label: 'Selected',  family: 'state',  title: 'Selected in SketchUp',                               test: function (r) { return !!S.selectionIds[r.p]; } }
    ].concat(NA_FACES.map(na_face_chip));

    // -------------------------------------------------------------------------
    // REGION | Loading Data From Ruby
    // -------------------------------------------------------------------------

    // FUNCTION | A Whole Snapshot (dialog open, Refresh, another model shown)
    Store.na_load_snapshot = function (payload) {
        var oldKey = na_model_key();
        if (oldKey) na_expanded_by_model[oldKey] = S.expanded;

        S.model      = payload.model || null;
        S.ents       = payload.ents || {};
        S.defs       = payload.defs || {};
        S.roots      = payload.roots || [];
        S.tags       = payload.tags || S.tags || {};
        S.status     = payload.status || {};
        S.events     = payload.events || [];
        S.seq        = payload.seq || 0;
        S.seen       = payload.seen || { user_seq: 0, agent_seq: 0 };
        S.tracking   = payload.tracking || null;
        S.modelNotes = payload.model_notes || null;
        S.threads    = {};
        S.history    = {};

        var newKey = na_model_key();
        S.expanded = (newKey && na_expanded_by_model[newKey]) || (newKey === oldKey ? S.expanded : {});
        na_sorted_cache = {};
        Store.na_touch();
    };

    // FUNCTION | A Delta After an Operation, a Comment or a Rename
    Store.na_apply_delta = function (delta) {
        Object.keys(delta.rows || {}).forEach(function (pid) { S.ents[pid] = delta.rows[pid]; });
        (delta.removed || []).forEach(function (pid) { delete S.ents[pid]; });
        Object.keys(delta.defs || {}).forEach(function (key) { S.defs[key] = delta.defs[key]; });
        if (delta.roots) S.roots = delta.roots;
        Object.keys(delta.status || {}).forEach(function (pid) { S.status[pid] = delta.status[pid]; });
        (delta.events || []).forEach(function (event) { S.events.push(event); });
        if (S.events.length > 600) S.events.splice(0, S.events.length - 600);
        if (delta.seq) S.seq = delta.seq;
        na_sorted_cache = {};
        Store.na_touch();
    };

    Store.na_set_state = function (state) {
        if (!state) return;
        S.standards = state.standards || S.standards;
        S.settings  = state.settings || S.settings;
        S.userName  = state.user_name || S.userName;
        S.tracking  = state.tracking || S.tracking;
        na_sorted_cache = {};
        Store.na_touch();
    };

    Store.na_set_tags = function (tags) { S.tags = tags || {}; Store.na_touch(); };

    Store.na_set_selection = function (selection) {
        S.selectionIds = {};
        (selection.ids || []).forEach(function (pid) { S.selectionIds[pid] = true; });
        S.activePath = selection.active || [];
    };

    Store.na_set_seen = function (seen) {
        if (seen && seen.user_seq !== undefined) S.seen.user_seq = seen.user_seq;
        Store.na_touch();
    };

    Store.na_set_thread = function (thread) {
        if (!thread) return;
        if (thread.target === 'model') S.modelNotes = thread; else S.threads[thread.target] = thread;
    };

    Store.na_set_history = function (payload) { S.history[payload.pid] = payload.events || []; };

    Store.na_touch = function () { S.version += 1; };
    Store.na_state = function () { return S; };

    function na_model_key() { return S.model ? (S.model.key || S.model.path || S.model.title) : null; }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Questions About One Object
    // -------------------------------------------------------------------------

    Store.na_row = function (pid) { return S.ents[pid]; };
    Store.na_type_name = function (kind) { return NA_TYPE_NAMES[kind] || ''; };

    Store.na_def_name = function (row) {
        if (!row || !row.d || row.k !== 'c') return '';
        var def = S.defs[row.d];
        return def ? def.n : '';
    };

    Store.na_copies = function (row) {
        if (!row || !row.d) return 0;
        var def = S.defs[row.d];
        return def ? def.ni || 0 : 0;
    };

    Store.na_children = function (row) {
        if (!row || !row.d) return [];
        var def = S.defs[row.d];
        return def && def.ch ? def.ch : [];
    };

    Store.na_tag_shown = function (tag) {
        if (!tag) return true;
        var info = S.tags[tag];
        return !info || info.v !== false;
    };

    Store.na_tag_colour = function (tag) {
        var info = tag ? S.tags[tag] : null;
        return info && info.c ? info.c : '';
    };

    Store.na_flag_type = function (id) {
        var flags = S.standards.flags || [];
        for (var i = 0; i < flags.length; i++) if (flags[i].id === id) return flags[i];
        return null;
    };

    Store.na_prefix_entry = function (label) {
        if (!label) return null;
        var prefixes = S.standards.prefixes || [];
        for (var i = 0; i < prefixes.length; i++) if (prefixes[i].label.toLowerCase() === String(label).toLowerCase()) return prefixes[i];
        return null;
    };

    // The colour window and the recent window, in seconds, from Settings.
    Store.na_windows = function () {
        var grading = S.settings.grading || {};
        var bands = (grading.band_minutes || [5, 30, 120, 1440]).map(Number).filter(function (n) { return n > 0; });
        if (!bands.length) bands = [5, 30, 120, 1440];
        return { bands: bands.map(function (m) { return m * 60; }), coloured: bands[bands.length - 1] * 60, recent: (bands[1] || bands[0]) * 60 };
    };

    // FUNCTION | What Changed About an Object, and How Strongly to Colour It
    // @return {null|{kind, by, band, age, latest, created, updated, fields, tool, recent, unseen, ever}}
    Store.na_change = function (pid) {
        var s = S.status[pid];
        if (!s || s.r) return null;
        var windows = Store.na_windows();
        var now = Date.now() / 1000;
        var created = s.c || 0, updated = s.u || 0;
        var latest = Math.max(created, updated);
        var age = now - latest;
        var info = {
            kind: null, by: updated > created ? (s.ub || s.cb) : (s.cb || s.ub), band: -1, age: age, latest: latest,
            created: created, updated: updated, createdBy: s.cb, updatedBy: s.ub, fields: s.f || [], tool: s.tool || '',
            recent: age <= windows.recent, unseen: (s.s || 0) > (S.seen.user_seq || 0), ever: latest > 0
        };
        if (created && now - created <= windows.coloured) { info.kind = 'new'; info.by = s.cb || info.by; }
        else if (updated && now - updated <= windows.coloured) { info.kind = 'updated'; info.by = s.ub || info.by; }
        if (info.kind) {
            for (var i = 0; i < windows.bands.length; i++) { if (age <= windows.bands[i]) { info.band = i; break; } }
            if (info.band < 0) info.band = windows.bands.length - 1;
        }
        info.recent = info.recent && !!info.kind;
        return info;
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | The Search Language
    // -------------------------------------------------------------------------

    // FUNCTION | Parse a Query Into OR Groups of AND Terms
    Store.na_parse_query = function (text) {
        var source = String(text || '').trim();
        if (!source) return [];
        return source.split(/\s+(?:\||OR)\s+/).map(function (part) {
            var tokens = part.match(/-?"[^"]*"|-?\/(?:[^\/\\]|\\.)+\/i?|\S+/g) || [];
            return tokens.map(na_term).filter(Boolean);
        }).filter(function (group) { return group.length > 0; });
    };

    function na_term(token) {
        var negative = token.charAt(0) === '-' && token.length > 1;
        if (negative) token = token.slice(1);
        var regexMatch = /^\/(.+)\/(i?)$/.exec(token);
        if (regexMatch) {
            try { return { neg: negative, field: 're', value: '', re: new RegExp(regexMatch[1], regexMatch[2]) }; }
            catch (err) { return null; }
        }
        if (token.length >= 2 && token.charAt(0) === '"' && token.charAt(token.length - 1) === '"') token = token.slice(1, -1);
        var field = 'any', value = token;
        var fieldMatch = /^([a-z]+):(.*)$/i.exec(token);
        if (fieldMatch && NA_FIELDS.indexOf(fieldMatch[1].toLowerCase()) >= 0) {
            field = fieldMatch[1].toLowerCase();
            value = fieldMatch[2];
            if (value.length >= 2 && value.charAt(0) === '"' && value.charAt(value.length - 1) === '"') value = value.slice(1, -1);
        }
        if (!value && field === 'any') return null;
        return { neg: negative, field: field, value: value.toLowerCase(), re: null };
    }

    function na_term_hit(term, row, change) {
        var value = term.value;
        var name = ((row.n || '') + ' ' + (row.dn || '')).toLowerCase();
        var def  = Store.na_def_name(row).toLowerCase();
        var tag  = row.t ? row.t.toLowerCase() : 'untagged';
        var flagType = row.nf ? Store.na_flag_type(row.nf) : null;
        var flag = row.nf ? (row.nf + ' ' + (flagType ? flagType.label : '')).toLowerCase() : '';
        var hit;
        switch (term.field) {
            case 're':     hit = term.re.test(row.n || '') || term.re.test(row.dn || '') || term.re.test(Store.na_def_name(row)); break;
            case 'name':   hit = name.indexOf(value) >= 0; break;
            case 'def':    hit = def.indexOf(value) >= 0; break;
            case 'tag':    hit = tag.indexOf(value) >= 0; break;
            case 'type':   hit = row.k === (NA_TYPE_WORDS[value] || value); break;
            case 'flag':   hit = value === 'any' ? !!row.nf : flag.indexOf(value) >= 0; break;
            case 'by':     hit = !!change && change.by === (value === 'me' || value === 'adam' ? 'user' : value); break;
            case 'is':     hit = na_is(value, row, change); break;
            case 'has':    hit = value === 'flag' ? !!row.nf : (value === 'prefix' ? !!row.pre : (row.nc || 0) > 0); break;
            case 'prefix': hit = (row.pre || '').toLowerCase().indexOf(value) === 0; break;
            case 'id':
            case 'pid':    hit = String(row.p) === value; break;
            case 'mat':    hit = (row.m || '').toLowerCase().indexOf(value) >= 0; break;
            case 'note':   hit = (row.nl || '').toLowerCase().indexOf(value) >= 0; break;
            case 'face':   hit = Store.na_face_of(row.n)[0].toLowerCase() === value; break;
            case 'dir':
                var parsed = Store.na_face_of(row.n);
                var dir = (parsed[1] || Store.na_cardinal_for(parsed[0])).toLowerCase();
                hit = !!dir && dir.indexOf(value) === 0;
                break;
            default:
                hit = [name, def, tag, (row.pre || '').toLowerCase(), String(row.p), flag, (row.m || '').toLowerCase(), (row.nl || '').toLowerCase()]
                    .some(function (text) { return text.indexOf(value) >= 0; });
        }
        return term.neg ? !hit : hit;
    }

    function na_is(word, row, change) {
        switch (word) {
            case 'new':      return !!change && change.kind === 'new';
            case 'updated':  return !!change && change.kind === 'updated';
            case 'changed':  return !!change && !!change.kind;
            case 'recent':   return !!change && change.recent;
            case 'unseen':   return !!change && change.unseen;
            case 'hidden':   return !!row.h || !Store.na_tag_shown(row.t);
            case 'visible':  return !row.h && Store.na_tag_shown(row.t);
            case 'locked':   return !!row.l;
            case 'flagged':  return !!row.nf;
            case 'unread':   return (row.nu || 0) > 0;
            case 'waiting':  return (row.nw || 0) > 0;
            case 'unnamed':  return !row.n;
            case 'resolved': return row.ns === 'resolved';
            case 'open':     return row.ns === 'open';
            case 'selected': return !!S.selectionIds[row.p];
            default:         return false;
        }
    }

    // The whole filter as one test, or null when nothing filters.
    function na_compile_filter() {
        var groups = Store.na_parse_query(S.search);
        var families = {};
        NA_QUICK.forEach(function (chip) {
            if (!S.quick[chip.id]) return;
            (families[chip.family] = families[chip.family] || []).push(chip);
        });
        var familyList = Object.keys(families).map(function (key) { return families[key]; });
        if (!groups.length && !familyList.length) return null;
        return function (row) {
            var change = Store.na_change(row.p);
            for (var f = 0; f < familyList.length; f++) {
                if (!familyList[f].some(function (chip) { return chip.test(row, change); })) return false;
            }
            if (!groups.length) return true;
            return groups.some(function (terms) { return terms.every(function (term) { return na_term_hit(term, row, change); }); });
        };
    }

    Store.na_quick_chips = function () { return NA_QUICK; };
    Store.na_filtering = function () { return !!na_compile_filter(); };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Sorting
    // -------------------------------------------------------------------------

    function na_text_compare(a, b) {
        a = a || ''; b = b || '';
        if (na_collator) return na_collator.compare(a, b);
        a = a.toLowerCase(); b = b.toLowerCase();
        return a < b ? -1 : (a > b ? 1 : 0);
    }

    // The value a column sorts by: a string (natural order) or a number.
    Store.na_sort_value = function (col, row) {
        var change;
        switch (col) {
            case 'name':     return row.dn || '';
            case 'status':   change = Store.na_change(row.p); return change && change.kind ? (change.kind === 'new' ? 2 : 1) * 1e10 + change.latest : 0;
            case 'changed':  change = Store.na_change(row.p); return change ? change.latest : 0;
            case 'by':       change = Store.na_change(row.p); return change && change.ever ? (change.by === 'agent' ? 'a' : 'b') : 'z';
            case 'flag':     return row.nf ? na_flag_index(row.nf) : 9999;
            case 'notes':    return -((row.nu || 0) * 1e6 + (row.nw || 0) * 1e3 + (row.nc || 0));
            case 'type':     return NA_TYPE_ORDER[row.k] || 9;
            case 'definition': return Store.na_def_name(row);
            case 'instance': return row.n || '';
            case 'tag':      return row.t || '';
            case 'size':     return row.sz ? Math.abs(row.sz[0] * row.sz[1] * (row.sz[2] || 1)) : -1;
            case 'material': return row.m || '';
            case 'copies':   return Store.na_copies(row);
            case 'prefix':   return row.pre || '';
            case 'pid':      return row.p;
            default:         return '';
        }
    };

    function na_flag_index(id) {
        var flags = S.standards.flags || [];
        for (var i = 0; i < flags.length; i++) if (flags[i].id === id) return i;
        return 999;
    }

    // Each row's sort values are worked out once, then compared: sorting ten
    // thousand rows by Changed must not ask for each change a million times.
    function na_sorted(cacheKey, pids) {
        var signature = cacheKey + '|' + JSON.stringify(S.sort) + '|' + S.version;
        if (na_sorted_cache[cacheKey] && na_sorted_cache[cacheKey].signature === signature) return na_sorted_cache[cacheKey].list;
        var keys = S.sort.length ? S.sort : [{ col: 'name', dir: 1 }];
        var decorated = [];
        pids.forEach(function (pid) {
            var row = S.ents[pid];
            if (!row) return;
            decorated.push({ pid: row.p, name: row.dn || '', values: keys.map(function (key) { return Store.na_sort_value(key.col, row); }) });
        });
        decorated.sort(function (a, b) {
            for (var i = 0; i < keys.length; i++) {
                var va = a.values[i], vb = b.values[i];
                var result = typeof va === 'number' && typeof vb === 'number' ? va - vb : na_text_compare(String(va), String(vb));
                if (result !== 0) return result * keys[i].dir;
            }
            var byName = na_text_compare(a.name, b.name);
            return byName !== 0 ? byName : a.pid - b.pid;
        });
        var list = decorated.map(function (item) { return item.pid; });
        na_sorted_cache[cacheKey] = { signature: signature, list: list };
        return list;
    }

    // FUNCTION | Click a Column: ascending, descending, off (Shift adds a key)
    Store.na_toggle_sort = function (col, additive) {
        var existing = null;
        S.sort.forEach(function (key) { if (key.col === col) existing = key; });
        if (!additive) {
            if (existing && S.sort.length === 1) {
                if (existing.dir === 1) existing.dir = -1;
                else S.sort = col === 'name' ? [{ col: 'name', dir: 1 }] : [];
            } else {
                S.sort = [{ col: col, dir: col === 'changed' || col === 'status' || col === 'notes' ? -1 : 1 }];
            }
        } else if (existing) {
            if (existing.dir === 1) existing.dir = -1;
            else S.sort = S.sort.filter(function (key) { return key.col !== col; });
        } else {
            S.sort.push({ col: col, dir: col === 'changed' || col === 'status' ? -1 : 1 });
        }
        Store.na_touch();
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Building the Rows
    // -------------------------------------------------------------------------

    // FUNCTION | Work Out Every Row the Table Shows
    Store.na_build_rows = function () {
        var predicate = na_compile_filter();
        var out = [];
        var state = { count: 0, truncated: false };
        if (S.view === 'tree') na_build_tree(predicate, out, state);
        else if (Store.na_card_spec()) na_build_card_tree(Store.na_card_spec(), predicate, out, state);   // <-- Tree by Tag, Group by Category
        else na_build_list(predicate, out, state);
        S.rows = out;
        S.matchCount = state.count;
        S.truncated = state.truncated;
        return out;
    };

    function na_build_tree(predicate, out, state) {
        var filter = na_tree_filter(predicate);
        state.counted = {};
        na_walk_rows(S.roots, 'root', [], 0, filter, out, state, { kp: '', base: 0 });
        if (!filter.on) state.count = Object.keys(S.ents).length;
    }

    // FUNCTION | The Search Test for a Tree: does a row match, does a definition hold a match below
    // Each answered once (per object, per definition), so a big model filters fast.
    function na_tree_filter(predicate) {
        var matchMemo = {};
        var holdsMemo = {};
        var filter = { on: !!predicate };
        filter.matches = function (pid) {
            if (matchMemo[pid] === undefined) matchMemo[pid] = !predicate || predicate(S.ents[pid]);
            return matchMemo[pid];
        };
        filter.holds = function (defKey, depth) {
            if (!filter.on) return true;
            if (holdsMemo[defKey] !== undefined) return holdsMemo[defKey];
            holdsMemo[defKey] = false;
            if (depth > 64) return false;
            var def = S.defs[defKey];
            var answer = false;
            if (def && def.ch) {
                for (var i = 0; i < def.ch.length && !answer; i++) {
                    var child = S.ents[def.ch[i]];
                    if (!child) continue;
                    if (filter.matches(child.p) || (child.d && filter.holds(child.d, depth + 1))) answer = true;
                }
            }
            holdsMemo[defKey] = answer;
            return answer;
        };
        // Is a row shown at all: it matches, or something inside it does
        filter.shows = function (row) {
            if (!filter.on) return true;
            return filter.matches(row.p) || (!!row.d && Store.na_children(row).length > 0 && filter.holds(row.d, 0));
        };
        return filter;
    }

    // FUNCTION | List Some Objects (sorted) and, Where Open, Everything Inside Them
    // ctx.kp prefixes every key (Tree by Tag: the block's own, so an object
    // listed in two blocks has two rows, each opening on its own); ctx.base
    // is the indent of the first level; ctx.decorate adds a view's own fields.
    function na_walk_rows(pids, cacheKey, parentPath, level, filter, out, state, ctx) {
        var list = na_sorted(cacheKey, pids);
        for (var i = 0; i < list.length; i++) {
            if (out.length >= NA_MAX_ROWS) { state.truncated = true; return; }
            na_emit_row(S.ents[list[i]], parentPath, level, filter, out, state, ctx);
        }
    }

    function na_emit_row(row, parentPath, level, filter, out, state, ctx) {
        if (!row) return;
        var path = parentPath.concat([row.p]);
        var key = ctx.kp + path.join('/');
        var kids = Store.na_children(row);
        var hasKids = kids.length > 0;
        var match = filter.matches(row.p);
        var below = filter.on && hasKids && filter.holds(row.d, ctx.base + level);
        if (filter.on && !match && !below) return;
        if (filter.on && match && !state.counted[row.p]) { state.counted[row.p] = true; state.count += 1; }
        var open = hasKids && (filter.on ? ((below && !S.searchCollapsed[key]) || !!S.expanded[key]) : !!S.expanded[key]);
        var item = { key: key, path: path, pid: row.p, depth: ctx.base + level, hasKids: hasKids, open: open, match: match, dim: filter.on && !match };
        if (ctx.decorate) ctx.decorate(item, level, parentPath);
        out.push(item);
        if (open) na_walk_rows(kids, row.d, path, level + 1, filter, out, state, ctx);
    }

    // Every object once (its first place in the tree), filtered and sorted,
    // in one list or under group headings.
    function na_build_list(predicate, out, state) {
        var reach = Store.na_reachable();
        var pids = Object.keys(reach).map(Number).filter(function (pid) { return !predicate || predicate(S.ents[pid]); });
        state.count = pids.length;
        pids = na_sorted('list:' + S.view + ':' + (predicate ? S.search + JSON.stringify(S.quick) : ''), pids);
        if (S.view === 'flat') {
            for (var i = 0; i < pids.length && out.length < NA_MAX_ROWS; i++) {
                out.push({ key: 'f:' + pids[i], path: reach[pids[i]], pid: pids[i], depth: 0, hasKids: false, open: false, match: true, dim: false });
            }
            state.truncated = pids.length > NA_MAX_ROWS;
            return;
        }

        var groups = {};
        var order = [];
        pids.forEach(function (pid) {
            var info = na_group_of(S.ents[pid]);
            if (!groups[info.key]) { groups[info.key] = { info: info, pids: [] }; order.push(info.key); }
            groups[info.key].pids.push(pid);
        });
        order.sort(function (a, b) {
            var ga = groups[a].info, gb = groups[b].info;
            if (ga.rank !== gb.rank) return ga.rank - gb.rank;
            return na_text_compare(ga.label, gb.label);
        });
        order.forEach(function (groupKey) {
            if (out.length >= NA_MAX_ROWS) { state.truncated = true; return; }
            var group = groups[groupKey];
            var headerKey = 'g:' + S.view + ':' + groupKey;
            var closed = !!S.groupCollapsed[headerKey];
            out.push({ key: headerKey, header: true, label: group.info.label, colour: group.info.colour || '', count: group.pids.length, open: !closed, depth: 0 });
            if (closed) return;
            group.pids.forEach(function (pid) {
                if (out.length >= NA_MAX_ROWS) { state.truncated = true; return; }
                out.push({ key: headerKey + '|' + pid, path: reach[pid], pid: pid, depth: 1, hasKids: false, open: false, match: true, dim: false });
            });
        });
    }

    // FUNCTION | Which Group a Row Falls Under in the Grouped Views
    function na_group_of(row) {
        var change;
        switch (S.view) {
            case 'group:tag':
                return { key: 't:' + (row.t || ''), label: row.t || 'Untagged', rank: row.t ? 1 : 0, colour: Store.na_tag_colour(row.t) };
            case 'group:type':
                return { key: 'k:' + row.k, label: (NA_TYPE_NAMES[row.k] || 'Other') + 's', rank: NA_TYPE_ORDER[row.k] || 9 };
            case 'group:definition':
                var defName = row.k === 'c' ? Store.na_def_name(row) : (row.k === 'g' ? 'Groups' : (NA_TYPE_NAMES[row.k] || '') + 's');
                return { key: 'd:' + (row.k === 'c' ? row.d : row.k), label: defName, rank: row.k === 'c' ? 1 : 2 };
            case 'group:flag':
                var flag = row.nf ? Store.na_flag_type(row.nf) : null;
                return { key: 'f:' + (row.nf || ''), label: flag ? flag.label : (row.nf || 'No Flag'), rank: row.nf ? na_flag_index(row.nf) : 9999, colour: flag ? flag.colour : '' };
            case 'group:change':
                change = Store.na_change(row.p);
                if (!change || !change.kind) return { key: 'c:none', label: 'Unchanged Recently', rank: 9 };
                var who = change.by === 'agent' ? 'Agent' : 'You';
                var what = change.kind === 'new' ? 'New' : 'Updated';
                return { key: 'c:' + change.kind + ':' + change.by, label: what + ' by ' + who, rank: (change.by === 'agent' ? 0 : 2) + (change.kind === 'new' ? 0 : 1),
                         colour: change.by === 'agent' ? 'var(--na-agent)' : 'var(--na-user)' };
            case 'group:by':
                change = Store.na_change(row.p);
                if (!change || !change.ever) return { key: 'b:none', label: 'No Recorded Change', rank: 9 };
                return { key: 'b:' + change.by, label: change.by === 'agent' ? 'Changed by an Agent' : 'Changed by You', rank: change.by === 'agent' ? 0 : 1,
                         colour: change.by === 'agent' ? 'var(--na-agent)' : 'var(--na-user)' };
            case 'group:prefix':
                var entry = Store.na_prefix_entry(row.pre);
                return { key: 'p:' + (row.pre || ''), label: row.pre ? (row.pre + (entry ? '  (' + entry.category + ')' : '')) : 'No Standard Name', rank: row.pre ? 0 : 1, colour: entry ? entry.colour : '' };
            case 'group:parent':
                var path = Store.na_reachable()[row.p] || [];
                var parent = path.length > 1 ? S.ents[path[path.length - 2]] : null;
                return { key: 'P:' + (parent ? parent.p : 'root'), label: parent ? parent.dn : 'Model Root', rank: parent ? 1 : 0 };
            default:
                return { key: 'all', label: 'All', rank: 0 };
        }
    }

    // FUNCTION | Every Object Reachable From the Root, With Its First Path
    // Each definition is walked once, so a component placed many times costs
    // no more than one placed once.
    var na_reach_cache = { version: -1, map: {} };
    Store.na_reachable = function () {
        if (na_reach_cache.version === S.version) return na_reach_cache.map;
        var map = {};
        var walkedDefs = {};
        var walk = function (pids, parentPath, depth) {
            if (depth > 64) return;
            for (var i = 0; i < pids.length; i++) {
                var row = S.ents[pids[i]];
                if (!row) continue;
                var path = parentPath.concat([row.p]);
                if (!map[row.p]) map[row.p] = path;
                if (row.d && !walkedDefs[row.d] && S.defs[row.d]) {
                    walkedDefs[row.d] = true;
                    walk(S.defs[row.d].ch || [], path, depth + 1);
                }
            }
        };
        walk(S.roots, [], 0);
        na_reach_cache = { version: S.version, map: map };
        return map;
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | The Card Views: Tree by Tag (0.1.16) and Group by Category (0.1.18)
    // -------------------------------------------------------------------------
    // Adam (12-Nov-2026): "A grouping mode that groups by tag, and each group in
    // the outliner is a level then its children indent ... Color the group
    // blocks as per the layer colors and separate the blocks". Then, of the
    // categories of his naming prefixes (Configure): "Create a group by category
    // that appears the same as the group by tag so coloured regions".
    // One engine builds both from a SPEC: which card an object belongs to (its
    // GROUP: its tag, or the naming prefix its name starts with; '' = none),
    // the folders a group sits in (tag folders; the prefix's category), the
    // order of a level, and a card's name and colour. Under each card its
    // objects are a tree, their contents indented below them whatever group
    // those are in.
    // - A BLOCK ROOT is an object in the group with nothing above it in the
    //   same group, so a group's parts in that group are listed inside it, once.
    // - NO GROUP (Untagged, No Standard Name): only top-level objects are block
    //   roots. An object with no group inside a grouped one goes with it (an
    //   untagged part shows and hides with its group's tag; an unnamed part is
    //   part of the named object), so it is listed inside it.
    // - An object in another group inside a block is listed in its parent there
    //   AND at the top of its own group's block.
    // Each object is placed by its first place in the tree (as the grouped
    // views do). Folder names need not be unique, so a folder is keyed by its
    // whole path.
    // - Tree by Tag: Untagged first, as in SketchUp's Tags panel; then the
    //   folders and tags of each level in natural order (01__ before 10__).
    // - Group by Category: the categories, and the prefixes in each, in the
    //   order Adam keeps them in Configure (the Quick Name panel's order); No
    //   Standard Name last. A prefix's card takes the prefix's colour.

    var NA_TT_UNTAGGED = '#94a3b8';
    var NA_TT_FOLDER   = '#7b8798';

    // The order of the naming prefixes and of their categories, as in Configure.
    function na_prefix_order() {
        var order = { prefixes: {}, categories: {} };
        (S.standards.prefixes || []).forEach(function (entry, index) {
            var category = entry.category || 'Other';
            if (order.categories[category] === undefined) order.categories[category] = index;
            var label = String(entry.label || '').toLowerCase();
            if (label && order.prefixes[label] === undefined) order.prefixes[label] = index;
        });
        return order;
    }

    var NA_CARD_SPECS = {
        tagtree: {
            view: 'tagtree', short: 't', none: 'Untagged', unit: ['tag', 'tags'],
            groupOf: function (row) { return row.t || ''; },
            folders: function (tag) {                                                      // <-- Outermost first ([] at the top level)
                var info = tag ? S.tags[tag] : null;
                return info && Array.isArray(info.f) ? info.f : [];
            },
            folderShown: function (tag, depth) {
                var info = tag ? S.tags[tag] : null;
                return !(info && Array.isArray(info.fs) && info.fs[depth] === false);
            },
            colour: function (tag) { return tag ? (Store.na_tag_colour(tag) || NA_TT_UNTAGGED) : NA_TT_UNTAGGED; },
            hidden: function (tag) { return !!tag && !Store.na_tag_shown(tag); },
            rank: function () { return 0; }                                                // <-- All by name: Untagged's name is '', so it comes first
        },
        cattree: {
            view: 'cattree', short: 'p', none: 'No Standard Name', unit: ['prefix', 'prefixes'],
            groupOf: function (row) { return row.pre || ''; },                             // <-- Ruby's match: the longest prefix the name starts with
            folders: function (label) {
                if (!label) return [];
                var entry = Store.na_prefix_entry(label);
                return [entry && entry.category ? entry.category : 'Other'];
            },
            folderShown: function () { return true; },
            colour: function (label) {
                var entry = label ? Store.na_prefix_entry(label) : null;
                return entry && entry.colour ? entry.colour : NA_TT_UNTAGGED;
            },
            hidden: function () { return false; },
            rank: function (item, order) {                                                 // <-- Configure's order; No Standard Name last
                if (item.folder) return order.categories[item.name] !== undefined ? order.categories[item.name] : 1e6;
                if (!item.group) return 2e6;
                var index = order.prefixes[item.group.toLowerCase()];
                return index !== undefined ? index : 1e6;
            }
        }
    };

    // FUNCTION | The Card View's Spec (null for the other views)
    // @param view {string=} a view name; the view on show when left out
    Store.na_card_spec = function (view) {
        var name = view === undefined ? S.view : view;
        return Object.prototype.hasOwnProperty.call(NA_CARD_SPECS, name) ? NA_CARD_SPECS[name] : null;
    };

    function na_card_key(spec, group)       { return 'g:' + spec.view + ':' + spec.short + ':' + group; }
    function na_card_folder_key(spec, path) { return 'g:' + spec.view + ':F:' + JSON.stringify(path); }
    function na_card_prefix(spec, group)    { return spec.short + ':' + encodeURIComponent(group) + '|'; }

    Store.na_card_key        = function (view, group) { return na_card_key(Store.na_card_spec(view), group); };
    Store.na_card_folder_key = function (view, path)  { return na_card_folder_key(Store.na_card_spec(view), path); };
    Store.na_card_prefix     = function (view, group) { return na_card_prefix(Store.na_card_spec(view), group); };

    var na_card_cache = {};

    // FUNCTION | Every Group's Block: its roots and how many objects are in the group
    // @return {Object<string, {group: string, roots: number[], count: number}>} keyed by group ('' = none)
    Store.na_card_blocks = function (view) {
        var spec = Store.na_card_spec(view);
        if (!spec) return {};
        var cached = na_card_cache[spec.view];
        if (cached && cached.version === S.version) return cached.blocks;
        var reach = Store.na_reachable();
        var blocks = {};
        Object.keys(reach).forEach(function (pidText) {
            var row = S.ents[pidText];
            if (!row) return;
            var group = spec.groupOf(row);
            var block = blocks[group] || (blocks[group] = { group: group, roots: [], count: 0 });
            block.count += 1;
            if (na_card_root(spec, row, reach[pidText])) block.roots.push(row.p);
        });
        na_card_cache[spec.view] = { version: S.version, blocks: blocks };
        return blocks;
    };

    // FUNCTION | Is an Object Listed at the Top of Its Group's Block?
    // @param row  {Object}   the object
    // @param path {number[]} its place in the tree, the object last
    function na_card_root(spec, row, path) {
        var group = spec.groupOf(row);
        if (!group) return path.length === 1;
        for (var i = 0; i < path.length - 1; i++) {
            var above = S.ents[path[i]];
            if (above && spec.groupOf(above) === group) return false;
        }
        return true;
    }

    // The levels: folders (keyed by path) holding folders and groups.
    function na_card_levels(spec, groups) {
        var top = { folders: {}, groups: [], path: [] };
        groups.forEach(function (group) {
            var node = top;
            spec.folders(group).forEach(function (name, depth) {
                if (!node.folders[name]) node.folders[name] = { folders: {}, groups: [], path: node.path.concat([name]), name: name, shown: spec.folderShown(group, depth) };
                node = node.folders[name];
            });
            node.groups.push(group);
        });
        return top;
    }

    // A level's entries in order: the view's rank, then by name in natural order.
    function na_card_entries(spec, node, order) {
        var list = [];
        Object.keys(node.folders).forEach(function (name) { list.push({ folder: node.folders[name], name: name }); });
        node.groups.forEach(function (group) { list.push({ group: group, name: group }); });
        list.forEach(function (item) { item.rank = spec.rank(item, order); });
        list.sort(function (a, b) { return a.rank !== b.rank ? a.rank - b.rank : na_text_compare(a.name, b.name); });
        return list;
    }

    function na_build_card_tree(spec, predicate, out, state) {
        var filter = na_tree_filter(predicate);
        var blocks = Store.na_card_blocks(spec.view);
        var reach = Store.na_reachable();
        var order = na_prefix_order();
        state.counted = {};

        // Does a block (or a folder) list anything with the search and filters on?
        var blockShows = function (group) {
            var block = blocks[group];
            if (!block || !block.roots.length) return false;
            for (var i = 0; i < block.roots.length; i++) if (filter.shows(S.ents[block.roots[i]])) return true;
            return false;
        };
        var folderShows = function (node) {
            return node.groups.some(blockShows) || Object.keys(node.folders).some(function (name) { return folderShows(node.folders[name]); });
        };
        var countGroups = function (node) {
            return node.groups.filter(blockShows).length + Object.keys(node.folders).reduce(function (sum, name) { return sum + countGroups(node.folders[name]); }, 0);
        };
        var gapFor = function (depth, parentKey) {
            if (!out.length) return 4;
            if (parentKey && out[out.length - 1].key === parentKey) return 3;                // <-- Just under its own folder
            return depth === 0 ? 10 : 6;
        };

        var level = function (node, depth, bands, parentKey) {
            na_card_entries(spec, node, order).forEach(function (entry) {
                if (out.length >= NA_MAX_ROWS) { state.truncated = true; return; }
                if (entry.folder) folder(entry.folder, depth, bands, parentKey);
                else groupBlock(entry.group, depth, bands, parentKey);
            });
        };

        var folder = function (node, depth, bands, parentKey) {
            if (!folderShows(node)) return;
            var key = na_card_folder_key(spec, node.path);
            var closed = !!S.groupCollapsed[key];
            var own = bands.concat([{ d: depth, kind: 'folder', colour: NA_TT_FOLDER }]);
            var groups = countGroups(node);
            out.push({ key: key, header: true, kind: 'folder', view: spec.view, label: node.name, count: groups, countText: groups + ' ' + spec.unit[groups === 1 ? 0 : 1],
                       open: !closed, hasKids: true, depth: depth, gap: gapFor(depth, parentKey), bands: own, parentKey: parentKey || '',
                       hidden: !node.shown, folderPath: node.path });
            if (!closed) level(node, depth + 1, own, key);
        };

        // A card (kind 'tag': a tag, or a prefix in Group by Category)
        var groupBlock = function (group, depth, bands, parentKey) {
            if (!blockShows(group)) return;
            var block = blocks[group];
            var key = na_card_key(spec, group);
            var closed = !!S.groupCollapsed[key];
            var colour = spec.colour(group);
            var own = bands.concat([{ d: depth, kind: 'tag', colour: colour }]);
            var tt = { group: group, colour: colour, d: depth };
            var start = out.length;
            out.push({ key: key, header: true, kind: 'tag', view: spec.view, group: group, label: group || spec.none, colour: colour, count: block.count,
                       roots: block.roots.length, open: !closed, hasKids: true, depth: depth, gap: gapFor(depth, parentKey), bands: own,
                       parentKey: parentKey || '', hidden: spec.hidden(group), tt: tt });
            if (!closed) {
                var kp = na_card_prefix(spec, group);
                var ctx = {
                    kp: kp, base: depth + 1,
                    decorate: function (item, lvl, parentPath) {
                        item.kp = kp;
                        item.level = lvl;
                        item.inset = 8;
                        item.bands = own;
                        item.tt = tt;
                        item.parentKey = lvl === 0 ? key : kp + parentPath.join('/');
                    }
                };
                var roots = na_sorted(spec.view + ':' + group, block.roots);
                for (var i = 0; i < roots.length; i++) {
                    if (out.length >= NA_MAX_ROWS) { state.truncated = true; break; }
                    var path = reach[roots[i]] || [roots[i]];
                    na_emit_row(S.ents[roots[i]], path.slice(0, -1), 0, filter, out, state, ctx);
                }
            }
            out[out.length - 1].blockEnd = true;                                          // <-- The block's last row closes its card
            out[start].blockStart = true;
        };

        level(na_card_levels(spec, Object.keys(blocks)), 0, [], '');
        if (!filter.on) state.count = Object.keys(reach).length;
    }

    // FUNCTION | Where an Object Is Listed in a Card View (its HOME)
    // Its own group's block; with no group, the block of the nearest grouped
    // object above it (the one SketchUp hides it with, or the named object it
    // is part of), or the no-group card when nothing above it has one. Inside
    // the block, under the topmost object on the path in that group.
    // @param view {string}   'tagtree' or 'cattree'
    // @param path {number[]} the object's place in the tree, the object last
    // @return {{group: string, key: string, open: string[]}|null} the row's key, and the keys to open on the way
    Store.na_card_home = function (view, path) {
        var spec = Store.na_card_spec(view);
        var target = spec && path && path.length ? S.ents[path[path.length - 1]] : null;
        if (!target) return null;
        var group = spec.groupOf(target);
        for (var up = path.length - 2; !group && up >= 0; up--) {
            var above = S.ents[path[up]];
            if (above && spec.groupOf(above)) group = spec.groupOf(above);
        }
        var at = 0;
        if (group) while (at < path.length - 1 && (!S.ents[path[at]] || spec.groupOf(S.ents[path[at]]) !== group)) at += 1;
        var rootPath = Store.na_reachable()[path[at]] || path.slice(0, at + 1);
        var full = rootPath.concat(path.slice(at + 1));
        var kp = na_card_prefix(spec, group);
        var open = [];
        for (var n = rootPath.length; n < full.length; n++) open.push(kp + full.slice(0, n).join('/'));
        return { group: group, key: kp + full.join('/'), open: open };
    };

    // FUNCTION | Open a Card View to Some Objects (following SketchUp's selection)
    // Opens each object's folders, its card and every row on the way to it.
    // @param paths {number[][]}
    // @param view  {string=} the view on show when left out
    // @return {string[]} the keys of the rows it opened to
    Store.na_reveal_cards = function (paths, view) {
        var spec = Store.na_card_spec(view);
        var keys = [];
        if (!spec) return keys;
        (paths || []).slice(0, 50).forEach(function (path) {
            var home = Store.na_card_home(spec.view, path);
            if (!home) return;
            delete S.groupCollapsed[na_card_key(spec, home.group)];
            var folders = spec.folders(home.group);
            for (var i = 1; i <= folders.length; i++) delete S.groupCollapsed[na_card_folder_key(spec, folders.slice(0, i))];
            home.open.forEach(function (key) { S.expanded[key] = true; delete S.searchCollapsed[key]; });
            keys.push(home.key);
        });
        Store.na_touch();
        return keys;
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | View State (expand, search, filters, view mode)
    // -------------------------------------------------------------------------

    Store.na_set_view = function (view) { S.view = view || 'tree'; Store.na_touch(); };
    Store.na_set_search = function (text) { S.search = text || ''; S.searchCollapsed = {}; Store.na_touch(); };
    Store.na_toggle_quick = function (id) { S.quick[id] = !S.quick[id]; if (!S.quick[id]) delete S.quick[id]; S.searchCollapsed = {}; Store.na_touch(); };
    Store.na_clear_quick = function () { S.quick = {}; Store.na_touch(); };

    // FUNCTION | Open or Close One Row (or a group heading)
    Store.na_toggle_open = function (item, open) {
        if (item.header) {
            S.groupCollapsed[item.key] = open === undefined ? !S.groupCollapsed[item.key] : !open;
        } else if (Store.na_filtering()) {
            var wantOpen = open === undefined ? !item.open : open;
            if (wantOpen) { delete S.searchCollapsed[item.key]; S.expanded[item.key] = true; }
            else { S.searchCollapsed[item.key] = true; delete S.expanded[item.key]; }
        } else {
            if (open === undefined ? !S.expanded[item.key] : open) S.expanded[item.key] = true;
            else delete S.expanded[item.key];
        }
        Store.na_touch();
    };

    // FUNCTION | Open a Row and Everything Under It (capped so it cannot freeze)
    // SketchUp's own Expand All can hang on big models; this stops at a row
    // budget and says so.
    Store.na_expand_below = function (item, budget) {
        budget = budget || 5000;
        var opened = 0;
        var walk = function (row, path, depth, kp) {
            if (opened >= budget || depth > 64) return;
            var kids = Store.na_children(row);
            if (!kids.length) return;
            S.expanded[kp + path.join('/')] = true;
            opened += kids.length;
            kids.forEach(function (pid) { var child = S.ents[pid]; if (child) walk(child, path.concat([pid]), depth + 1, kp); });
        };
        if (item) walk(S.ents[item.pid], item.path, 0, item.kp || '');
        else if (Store.na_card_spec()) {                                                      // <-- The card views: every folder, card and block (0.1.16, 0.1.18)
            var spec = Store.na_card_spec();
            Object.keys(S.groupCollapsed).forEach(function (key) { if (key.indexOf('g:' + spec.view + ':') === 0) delete S.groupCollapsed[key]; });
            var blocks = Store.na_card_blocks();
            var reach = Store.na_reachable();
            Object.keys(blocks).forEach(function (group) {
                var kp = Store.na_card_prefix(spec.view, group);
                blocks[group].roots.forEach(function (pid) { var row = S.ents[pid]; if (row) walk(row, reach[pid] || [pid], 0, kp); });
            });
        }
        else S.roots.forEach(function (pid) { var row = S.ents[pid]; if (row) walk(row, [pid], 0, ''); });
        Store.na_touch();
        return { opened: opened, capped: opened >= budget };
    };

    Store.na_collapse_all = function () { S.expanded = {}; S.searchCollapsed = {}; S.groupCollapsed = {}; Store.na_touch(); };

    // FUNCTION | Open or Close the Tree One Level at a Time (the ] and [ keys, 0.1.12)
    // open true (]): every closed row that has children, at the shallowest
    // level that still has one, opens. open false ([): every open row at the
    // deepest open level closes. Reads the rows on show, so a branch opened by
    // hand or a search steps the same way. In the grouped views the group
    // headings are the level above the rows. Returns { level, count, groups }
    // (level 0 = the top rows), or null when there is nothing left to step.
    Store.na_step_level = function (rows, open) {
        var stepping = (rows || []).filter(function (item) {
            if (item.header) return open ? !!S.groupCollapsed[item.key] : !S.groupCollapsed[item.key];
            return item.hasKids && !!item.open !== open;
        });
        if (!stepping.length) return null;
        // Headings step before rows, outermost first (the card views: folders, the cards in them, then each
        // card's rows by their level inside the card, 0.1.16)
        var depthOf = function (item) { return item.header ? (item.depth || 0) - 100 : (item.level !== undefined ? item.level : item.depth); };
        var level = stepping.reduce(function (best, item) {
            return open ? Math.min(best, depthOf(item)) : Math.max(best, depthOf(item));
        }, open ? Infinity : -Infinity);
        var filtering = Store.na_filtering();
        var count = 0;
        stepping.forEach(function (item) {
            if (depthOf(item) !== level) return;
            count += 1;
            if (item.header) { S.groupCollapsed[item.key] = !open; return; }
            if (open) { S.expanded[item.key] = true; delete S.searchCollapsed[item.key]; }
            else { delete S.expanded[item.key]; if (filtering) S.searchCollapsed[item.key] = true; }
        });
        Store.na_touch();
        return { level: level, count: count, groups: level < 0 };
    };

    // FUNCTION | Open Every Row on the Way to a Path
    Store.na_reveal = function (path) {
        for (var i = 1; i < path.length; i++) S.expanded[path.slice(0, i).join('/')] = true;
        delete S.searchCollapsed[path.slice(0, -1).join('/')];
        Store.na_touch();
    };

    // FUNCTION | Open the Group Headings Some Objects Sit Under (the grouped views, 0.1.15)
    // Following SketchUp's selection in Group by Tag (or Type ...) opens the
    // heading the object is listed under, as the tree view opens its parents.
    // @param pids {number[]}
    Store.na_reveal_groups = function (pids) {
        if (S.view === 'tree' || S.view === 'flat' || Store.na_card_spec()) return;      // <-- The card views open with na_reveal_cards
        (pids || []).slice(0, 200).forEach(function (pid) {
            var row = S.ents[pid];
            if (row) delete S.groupCollapsed['g:' + S.view + ':' + na_group_of(row).key];
        });
        Store.na_touch();
    };

    // FUNCTION | The Paths SketchUp's Selection Stands For
    // An object selected inside the open group is that exact occurrence; at
    // the root (or in the flat views) its first place in the tree.
    Store.na_selection_paths = function () {
        var paths = [];
        var reach = Store.na_reachable();
        Object.keys(S.selectionIds).forEach(function (pid) {
            var exact = S.activePath.concat([Number(pid)]);
            var valid = exact.length === 1 || na_path_valid(exact);
            paths.push(valid ? exact : (reach[pid] || [Number(pid)]));
        });
        return paths;
    };

    function na_path_valid(path) {
        if (S.roots.indexOf(path[0]) < 0) return false;
        for (var i = 1; i < path.length; i++) {
            var parent = S.ents[path[i - 1]];
            if (!parent || Store.na_children(parent).indexOf(path[i]) < 0) return false;
        }
        return true;
    }

    // FUNCTION | Do Any of a Row's Contents Carry a Recent Change? (the dot on closed rows)
    Store.na_changes_inside = function (row) {
        if (!row || !row.d) return null;
        var memo = Store._insideMemo || (Store._insideMemo = { version: -1, map: {} });
        if (memo.version !== S.version) { memo.version = S.version; memo.map = {}; }
        var found = null;
        var visit = function (defKey, depth) {
            if (memo.map[defKey] !== undefined) return memo.map[defKey];
            memo.map[defKey] = null;
            if (depth > 64) return null;
            var def = S.defs[defKey];
            var best = null;
            (def && def.ch ? def.ch : []).forEach(function (pid) {
                var change = Store.na_change(pid);
                if (change && change.kind && (!best || change.latest > best.latest)) best = { by: change.by, latest: change.latest, band: change.band };
                var child = S.ents[pid];
                if (child && child.d) {
                    var deeper = visit(child.d, depth + 1);
                    if (deeper && (!best || deeper.latest > best.latest)) best = deeper;
                }
            });
            memo.map[defKey] = best;
            return best;
        };
        found = visit(row.d, 0);
        return found;
    };

    // endregion ----------------------------------------------------------------

    window.Na__AgentOutliner__Store = Store;
})();

// =============================================================================
// END OF FILE
// =============================================================================
