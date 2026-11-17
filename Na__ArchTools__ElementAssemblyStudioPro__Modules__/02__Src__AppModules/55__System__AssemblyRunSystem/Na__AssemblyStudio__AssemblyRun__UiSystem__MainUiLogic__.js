// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__AssemblyStudio__AssemblyRun__UiSystem__MainUiLogic__.js
// NAMESPACE  : Na_RunUI (browser global; the TabRouter's module for tab "runs")
// AUTHOR     : Noble Architecture
// PURPOSE    : The Assembly Run Studio tab: a run of the other tabs' elements
//              set out along a path. Holds the run being described, draws its
//              settings, path, legs and panel types, and asks Ruby for the
//              layout it previews.
// CREATED    : 16-Nov-2026 (V2.7.0)
//
// HOW THE TAB WORKS
// - ONE payload is the truth: na_state.root, the same root Ruby stores on a
//   run ({ metadata, components, configuration }). Every control edits it.
// - After any edit the root goes to Ruby (na_runResolve) and the layout that
//   comes back is drawn. Ruby is the only resolver: this file has no layout
//   rule, so the preview cannot disagree with what is built.
// - The preview itself (two zoomable drawings, their dimensions, the Both /
//   Plan / Elevation / Flip Out tabs) is Na_RunPreview's. This file hands it
//   the layout and the selection, and applies a size typed over a dimension
//   (na_apply_dimension) exactly as its field in the sections would.
// - The defaults, option lists and limits arrive from Ruby too
//   (na_runRequestBootstrap), so the page holds no second copy of them.
// - A run that is not built yet is a DRAFT: Create builds it. A run selected
//   in the model is loaded; its edits are staged here and Update Run applies
//   them in one undo step. Make Panel Unique on a built run goes straight to
//   Ruby, because the new type must copy a real element.
// - Three edits change more of the description than one field: another
//   product for a span, a leg's fill or a panel type, and Flip Inside Out
//   (V2.7.2). Their rules are Ruby's (Na__RunEdits), so the tab, the member
//   banner and the agent tools agree: na_stage sends the description and the
//   edit's name, and the changed description comes back (na_receive_staged).
// - Undo and Redo (V2.7.2) step through the description as it was after
//   each change made here: Ctrl+Z, Ctrl+Y, and the two buttons in the
//   preview's head. See the Undo and redo region.
//
// THE ONE PIECE OF GEOMETRY HERE
// - Leg lengths and turns typed into the Path section become points with
//   na_points_from_rows: start at the first point, head along the first leg,
//   turn LEFT for a positive angle. Reading them back uses Ruby's layout.
//
// NAMING CONVENTION:
// - All custom identifiers use Na_ / na_ prefix.
//
// =============================================================================

(function () {
    'use strict';

    var Na_RunUI = {};

    // -----------------------------------------------------------------------
    // REGION | Constants and state
    // -----------------------------------------------------------------------

    var NA_RESOLVE_DELAY_MS = 140;
    var NA_SECTIONS_ID      = 'na-run-sections';
    var NA_PRODUCTS_ID      = 'na-lay-products-runs';
    var NA_PROBLEMS_ID      = 'na-run-problems';
    var NA_UNDO_ID          = 'na-btn-run-undo';
    var NA_REDO_ID          = 'na-btn-run-redo';
    var NA_TAB_ID           = 'runs';                                           // <-- body[data-na-active-tab] while this tab shows
    var NA_NEW_PRODUCT      = 'new:';                                           // <-- Head of a panel type option that asks for another product
    var NA_HISTORY_LIMIT    = 100;                                              // <-- Steps of Undo kept
    var NA_CHEVRON          = '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2 4l4 4 4-4"/></svg>';

    var NA_MODE_NOTES = {
        Frames   : 'Windows and exterior doors. The path is the framework face, seen from its right (the outside).',
        Cabinets : 'Fitted units. The path is the wall line; the room is on its right.'
    };

    // The first panel type and leg a new draft of each mode starts with.
    var NA_STARTERS = {
        Frames   : { path: [[0, 0], [5400, 0]], type: { Code: 'A', Product: 'double' },              fill: { PanelType: 'A', Count: 3 } },
        Cabinets : { path: [[0, 0], [3000, 0]], type: { Code: 'A', Product: 'base', Width_mm: 600 }, fill: { PanelType: 'A', Infill: 'End' } }
    };

    var na_state = {
        boot      : null,      // <-- Ruby's bootstrap: defaults, option lists, limits, presets
        root      : null,      // <-- The run being described (Ruby's root payload)
        layout    : null,      // <-- The layout Ruby last resolved for it
        runId     : null,      // <-- Id of the run loaded from the model (null = a draft)
        runName   : '',
        copies    : 1,
        dirty     : false,     // <-- Staged edits not yet built
        legsByHand: false,     // <-- The user has changed the draft: a measured path no longer reseeds every leg
        selection : null,      // <-- { leg, span } picked in a preview
        measured  : null,      // <-- A path measured in the model, waiting for Create
        measuredInDraft: false,// <-- The draft's path IS that measured path, as changed here since (Create then builds the draft's)
        pathEdit  : null,      // <-- Run id whose path is open as a red line
        open      : { run: true, columns: false, path: false, legs: true, types: true }
    };
    var na_resolve_timer = null;
    var na_history       = { steps: [], at: -1 };                               // <-- See the Undo and redo region

    // -----------------------------------------------------------------------
    // REGION | Small helpers
    // -----------------------------------------------------------------------

    function na_escape(text) {
        return String(text === null || text === undefined ? '' : text)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    function na_clone(value) { return JSON.parse(JSON.stringify(value)); }

    function na_keys() { return (na_state.boot && na_state.boot.keys) || { metadata: 'Na__AssemblyRunMetadata', components: 'Na__AssemblyRunComponents', configuration: 'Na__AssemblyRunConfiguration', prefix: 'Na__RunConfig__' }; }
    function na_product_label(key) { return ((na_state.boot && na_state.boot.productLabels) || {})[key] || key || ''; }
    function na_products() { return ((na_state.boot && na_state.boot.products) || {})[na_mode()] || []; }
    function na_type_row(code) { var wanted = String(code || '').toUpperCase(); return na_types().filter(function (row) { return String(row.Code || '').toUpperCase() === wanted; })[0] || null; }
    function na_key(short) { return na_keys().prefix + short; }
    function na_config() { return na_state.root ? na_state.root[na_keys().configuration] : null; }
    function na_get(short) { var config = na_config(); return config ? config[na_key(short)] : undefined; }
    function na_mode() { return na_get('Mode') || 'Frames'; }
    function na_is_frames() { return na_mode() === 'Frames'; }
    function na_types() { var config = na_config(); if (!config) return []; if (!Array.isArray(config[na_key('PanelTypes')])) config[na_key('PanelTypes')] = []; return config[na_key('PanelTypes')]; }
    function na_legs() { var config = na_config(); if (!config) return []; if (!Array.isArray(config[na_key('Legs')])) config[na_key('Legs')] = []; return config[na_key('Legs')]; }

    function na_metadata() {
        var list = na_state.root[na_keys().metadata];
        if (!Array.isArray(list) || !list[0]) list = na_state.root[na_keys().metadata] = [{}];
        return list[0];
    }

    function na_send(callback, payload) {
        if (typeof sketchup === 'undefined' || typeof sketchup[callback] !== 'function') {
            console.warn('[Na_RunUI] sketchup.' + callback + ' unavailable');
            return false;
        }
        if (payload === undefined) sketchup[callback]();
        else sketchup[callback](typeof payload === 'string' ? payload : JSON.stringify(payload));
        return true;
    }

    function na_status(type, message) {
        if (typeof window.na_showStatus === 'function') window.na_showStatus(type, message);
    }

    function na_layout_legs() { return (na_state.layout && na_state.layout.legs) || []; }
    function na_layout_type(code) { return (na_state.layout && na_state.layout.types && na_state.layout.types[code]) || {}; }
    function na_leg_count() { var points = na_get('PathPoints') || []; return Math.max(na_get('PathClosed') ? points.length : points.length - 1, 0); }

    // A whole number shows without a trailing .0
    function na_trim(value) {
        if (value === null || value === undefined || value === '') return '';
        var number = Math.round(Number(value) * 10) / 10;
        return String(number);
    }

    // The next free panel type code: A, B ... Z, then AA, AB ... (as Ruby's
    // Na__Defaults.na_next_type_code counts).
    function na_next_code() {
        var taken  = na_types().map(function (row) { return String(row.Code || '').toUpperCase(); });
        var letter = function (index) { return String.fromCharCode(65 + index); };
        var first, second;
        for (first = 0; first < 26; first += 1) {
            if (taken.indexOf(letter(first)) < 0) return letter(first);
        }
        for (first = 0; first < 26; first += 1) {
            for (second = 0; second < 26; second += 1) {
                if (taken.indexOf(letter(first) + letter(second)) < 0) return letter(first) + letter(second);
            }
        }
        return 'A';
    }

    // -----------------------------------------------------------------------
    // REGION | Drafts
    // -----------------------------------------------------------------------

    // FUNCTION | A New Draft of One Mode, From Ruby's Defaults
    // ---------------------------------------------------------------
    function na_new_draft(mode) {
        if (!na_state.boot) return;
        var starter = NA_STARTERS[mode] || NA_STARTERS.Frames;
        na_state.root = na_clone(na_state.boot.defaults[mode] || na_state.boot.defaults.Frames);
        var config = na_config();
        config[na_key('PathPoints')] = na_clone(starter.path);
        config[na_key('PanelTypes')] = [na_clone(starter.type)];
        config[na_key('Legs')]       = [{ Fill: na_clone(starter.fill) }];
        na_state.runId      = null;
        na_state.runName    = '';
        na_state.dirty      = false;
        na_state.legsByHand = false;
        na_state.selection  = null;
        na_state.layout     = null;
        na_state.measuredInDraft = false;
        if (na_state.measured) {
            config[na_key('PathPoints')] = na_clone(na_state.measured.points);
            config[na_key('PathClosed')] = !!na_state.measured.closed;
            na_seed_legs(na_state.measured.legs);
            na_state.measuredInDraft = true;
        }
    }

    // FUNCTION | Give a Measured Path's Legs Their Starting Spans
    // ---------------------------------------------------------------
    // A panel type with no set width takes its width from its leg, so one
    // such type cannot fill legs of different lengths: Ruby refuses the
    // layout ("comes out at 1830mm on one leg and 2705mm on another"). A
    // path measured round a corner landed a new draft in exactly that
    // state (16-Nov-2026). So the legs a measured path brings are given
    // their spans here: legs of one length share a panel type, a new
    // length gets a copy of the first type under the next code, and each
    // leg starts with about one span per starting width of its product
    // (Ruby's productWidths, from the product's own starting values).
    // Rows the user has set are never rewritten: until anything has been
    // changed by hand every leg is seeded, after that only legs with no
    // spans of their own.
    // @param lengths [Array] Ruby's leg rows ({ Length_mm, Turn_deg })
    function na_seed_legs(lengths) {
        var types = na_types();
        var base  = types[0];
        if (!na_is_frames() || !base || base.Width_mm || !Array.isArray(lengths) || lengths.length < 2) return;

        var rows  = na_legs();
        var fresh = !na_state.legsByHand;
        if (fresh) { rows.length = 0; types.splice(1); }                        // <-- Every other type was made by an earlier seeding
        var start     = ((na_state.boot || {}).productWidths || {})[base.Product] || 0;
        var by_length = {};                                                     // <-- Whole-mm leg length -> panel type code
        lengths.forEach(function (leg, index) {
            var length = Number(leg.Length_mm) || 0;
            var key    = String(Math.round(length));
            var row    = rows[index] || (rows[index] = {});
            if ((Array.isArray(row.Items) && row.Items.length) || row.Fill) {   // <-- The user's own: left alone, but its type claims its length
                if (row.Fill && row.Fill.PanelType && !by_length[key]) by_length[key] = row.Fill.PanelType;
                return;
            }
            var code = by_length[key];
            if (!code) {
                if (Object.keys(by_length).length === 0) {
                    code = base.Code;
                } else {
                    code = na_next_code();
                    var copy = na_clone(base);
                    ['ElementId', 'FrameBeforeFuse', 'Auto', 'DerivedFrom', 'UniqueOf'].forEach(function (name) { delete copy[name]; });
                    copy.Code = code;
                    types.push(copy);
                }
                by_length[key] = code;
            }
            row.Fill = { PanelType: code, Count: start > 0 ? Math.max(1, Math.round(length / start)) : 1 };
        });
    }

    // FUNCTION | A Change Was Made: Redraw the Controls, Ask for the Layout
    // ---------------------------------------------------------------
    function na_changed(skip_render) {
        na_state.dirty      = true;
        na_state.legsByHand = true;
        na_history_record();
        if (!skip_render) na_render_sections();
        na_sync_dock();
        na_request_layout();
    }

    function na_request_layout() {
        if (na_resolve_timer) clearTimeout(na_resolve_timer);
        na_resolve_timer = setTimeout(function () {
            na_resolve_timer = null;
            if (na_state.root) na_send('na_runResolve', na_state.root);
        }, NA_RESOLVE_DELAY_MS);
    }

    // -----------------------------------------------------------------------
    // REGION | Undo and redo (V2.7.2)
    // -----------------------------------------------------------------------
    // WHY (Adam, 16-Nov-2026): "On the diagram editor, there is no Ctrl+Z or
    // Ctrl+Y for forward and backwards, so it's really unforgiving."
    //
    // WHAT IS KEPT
    // - The description after every change made here: the root, which run it
    //   is, and whether it has changes not yet built. Undo steps back through
    //   them and Redo forward; a new change after an Undo drops the steps
    //   ahead of it. The last NA_HISTORY_LIMIT steps are kept.
    // WHAT IT COVERS
    // - What is edited in this tab: a draft, and the staged changes of a
    //   built run (New Run and a change of mode included). What is BUILT in
    //   the model is SketchUp's own Undo, one step per build.
    // WHERE A HISTORY STARTS AFRESH (na_history_reset)
    // - A run loaded from the model or just built, the selection leaving it,
    //   and a path measured in the model. From there the description is tied
    //   to something outside this tab: a step back past that point would show
    //   a run, or a path, that is not the one in the model.

    function na_history_snapshot() {
        return JSON.stringify({ root: na_state.root, runId: na_state.runId, runName: na_state.runName, copies: na_state.copies,
                                dirty: na_state.dirty, legsByHand: na_state.legsByHand, measuredInDraft: na_state.measuredInDraft });
    }

    function na_sync_history() {
        var undo = document.getElementById(NA_UNDO_ID);
        var redo = document.getElementById(NA_REDO_ID);
        if (undo) undo.disabled = na_history.at <= 0;
        if (redo) redo.disabled = na_history.at >= na_history.steps.length - 1;
    }

    // FUNCTION | Start the History Afresh From the Description as It Stands
    // ---------------------------------------------------------------
    function na_history_reset() {
        na_history.steps = na_state.root ? [na_history_snapshot()] : [];
        na_history.at    = na_history.steps.length - 1;
        na_sync_history();
    }

    // FUNCTION | The Description Was Changed: Keep It as the Next Step
    // ---------------------------------------------------------------
    function na_history_record() {
        if (!na_state.root) return;
        var snapshot = na_history_snapshot();
        if (na_history.at >= 0 && na_history.steps[na_history.at] === snapshot) return;   // <-- A field set to what it already was
        na_history.steps = na_history.steps.slice(0, na_history.at + 1);
        na_history.steps.push(snapshot);
        if (na_history.steps.length > NA_HISTORY_LIMIT) na_history.steps.shift();
        na_history.at = na_history.steps.length - 1;
        na_sync_history();
    }

    // FUNCTION | Step Back (-1) or Forward (+1) Through the History
    // ---------------------------------------------------------------
    // @return true when the description changed
    function na_history_go(delta) {
        var next = na_history.at + delta;
        if (next < 0 || next >= na_history.steps.length) {
            na_status('info', delta < 0 ? 'Nothing more to undo in this tab. What is built in the model is undone in SketchUp (Edit, Undo).'
                                        : 'Nothing to redo.');
            return false;
        }
        if (typeof Na_RunContextMenu !== 'undefined') Na_RunContextMenu.na_close();
        var held = JSON.parse(na_history.steps[next]);
        na_history.at       = next;
        na_state.root       = held.root;
        na_state.runId      = held.runId;
        na_state.runName    = held.runName;
        na_state.copies     = held.copies;
        na_state.dirty      = held.dirty;
        na_state.legsByHand = held.legsByHand;
        na_state.measuredInDraft = held.measuredInDraft === true;
        na_state.selection  = null;
        na_refresh();
        if (na_resolve_timer) { clearTimeout(na_resolve_timer); na_resolve_timer = null; }
        na_send('na_runResolve', na_state.root);                                // <-- At once: the sections and both drawings wait on this layout
        na_sync_history();
        na_status('info', delta < 0 ? 'Undone.' : 'Redone.');
        return true;
    }

    // FUNCTION | Ctrl+Z, Ctrl+Y and Ctrl+Shift+Z While This Tab Shows
    // ---------------------------------------------------------------
    // A field holding typing that has not been entered yet keeps the
    // browser's own undo of that typing. The box over a dimension stops
    // its keys before they get here (the shared viewport controls).
    function na_on_keydown(event) {
        if (!(event.ctrlKey || event.metaKey) || event.altKey) return;
        var key = String(event.key || '').toLowerCase();
        if (key !== 'z' && key !== 'y') return;
        if (document.body.getAttribute('data-na-active-tab') !== NA_TAB_ID) return;

        var target = event.target || {};
        var tag    = target.tagName ? target.tagName.toLowerCase() : '';
        var text   = tag === 'textarea' || (tag === 'input' && !/^(checkbox|radio|button|range)$/.test(target.type || 'text'));
        if (text && target.value !== target.defaultValue) return;
        event.preventDefault();
        na_history_go(key === 'y' || event.shiftKey ? 1 : -1);
    }

    // -----------------------------------------------------------------------
    // REGION | Edits whose rule is Ruby's (V2.7.2)
    // -----------------------------------------------------------------------

    // FUNCTION | Ask Ruby to Change the Description by a Named Edit
    // ---------------------------------------------------------------
    // Nothing is built: the description comes back changed, with its layout
    // (na_receive_staged), for Update Run or Create to build.
    // @param edit 'span_product' | 'fill_product' | 'type_product' | 'flip'
    // @param args { leg, span (zero-based), code, product } as the edit needs
    function na_stage(edit, args) {
        if (!na_state.root) return false;
        var payload = { root: na_state.root, edit: edit };
        Object.keys(args || {}).forEach(function (name) { payload[name] = args[name]; });
        if (na_send('na_runStageEdit', payload)) return true;
        // No such callback: this page is newer than the Ruby this SketchUp
        // window loaded (the plugin was changed while the window was open).
        na_render_sections();                                                   // <-- The dropdown or switch goes back to what the description says
        na_status('error', 'This SketchUp window is running an older copy of the plugin. Use Reload Scripts, or restart SketchUp, then try again.');
        return false;
    }

    // -----------------------------------------------------------------------
    // REGION | Path: lengths and turns to points
    // -----------------------------------------------------------------------

    // FUNCTION | Leg Rows ({ length, turn }) to Points
    // ---------------------------------------------------------------
    // Starts at start, heads along heading_deg; after each leg turns LEFT
    // by that row's turn (degrees).
    function na_points_from_rows(rows, start, heading_deg) {
        var points  = [[start[0], start[1]]];
        var heading = heading_deg * Math.PI / 180;
        rows.forEach(function (row) {
            var last = points[points.length - 1];
            points.push([Math.round((last[0] + Math.cos(heading) * row.length) * 100) / 100,
                         Math.round((last[1] + Math.sin(heading) * row.length) * 100) / 100]);
            heading += (row.turn || 0) * Math.PI / 180;
        });
        return points;
    }

    // The path as rows, read from Ruby's layout (lengths) and its corners (turns).
    function na_path_rows() {
        var legs    = na_layout_legs();
        var corners = (na_state.layout && na_state.layout.corners) || [];
        return legs.map(function (leg) {
            var corner = corners.filter(function (item) { return item.leg_in === leg.index; })[0];
            return { length: Math.round(leg.length * 10) / 10, turn: corner ? Math.round(corner.turn_deg * 100) / 100 : 0 };
        });
    }

    function na_apply_path_rows(rows) {
        var legs    = na_layout_legs();
        var points  = na_get('PathPoints') || [[0, 0]];
        var heading = legs.length ? legs[0].angle_deg : 0;
        var config  = na_config();
        config[na_key('PathPoints')] = na_points_from_rows(rows, points[0] || [0, 0], heading);
        var leg_rows = na_legs();
        while (leg_rows.length > rows.length) leg_rows.pop();
        na_changed();
    }

    // -----------------------------------------------------------------------
    // REGION | Rendering - shared pieces
    // -----------------------------------------------------------------------

    function na_section(id, title, summary, body) {
        var open = na_state.open[id] !== false;
        return '<section class="na-lay-sec" data-na-run-sec="' + id + '">' +
                 '<div class="na-lay-sec__top"><button type="button" class="na-lay-sec__head" data-na-act="toggle-section" data-na-sec="' + id + '" aria-expanded="' + open + '">' +
                   NA_CHEVRON + '<span class="na-lay-sec__title">' + na_escape(title) + '</span><span class="na-lay-sec__sum">' + na_escape(summary) + '</span>' +
                 '</button></div>' +
                 '<div class="na-lay-sec__body"' + (open ? '' : ' hidden') + '>' + body + '</div>' +
               '</section>';
    }

    function na_field(label, control, note) {
        return '<label class="na-run-field"><span class="na-run-field__label">' + na_escape(label) + '</span>' + control +
               (note ? '<span class="na-run-field__note">' + na_escape(note) + '</span>' : '') + '</label>';
    }

    function na_number(short, extra) {
        var limits = (na_state.boot && na_state.boot.limits && na_state.boot.limits[short]) || [];
        return '<input type="number" class="na-run-input" data-na-act="set" data-na-key="' + short + '" value="' + na_escape(na_trim(na_get(short))) + '"' +
               (limits.length ? ' min="' + limits[0] + '" max="' + limits[1] + '"' : '') + ' step="5"' + (extra || '') + '><i class="na-run-unit">mm</i>';
    }

    function na_select(act, options, value, attributes) {
        return '<select class="na-run-input" data-na-act="' + act + '"' + (attributes || '') + '>' + options.map(function (option) {
            var key   = typeof option === 'string' ? option : option.value;
            var label = typeof option === 'string' ? option : option.label;
            return '<option value="' + na_escape(key) + '"' + (String(key) === String(value) ? ' selected' : '') + '>' + na_escape(label) + '</option>';
        }).join('') + '</select>';
    }

    function na_toggle(short, label) {
        return '<label class="na-run-toggle"><input type="checkbox" data-na-act="set-flag" data-na-key="' + short + '"' + (na_get(short) === true ? ' checked' : '') + '><span>' + na_escape(label) + '</span></label>';
    }

    function na_column_label(kind) {
        return { None: 'Nothing (butt together)', Infill: 'Infill block', Vale260: 'Vale 260 column', Vale290: 'Vale 290 column', Gap: 'Gap (left empty)' }[kind] || kind;
    }

    function na_corner_label(kind) {
        return { Post: 'Corner post', Vale260: 'Vale 260 corner column', Vale290: 'Vale 290 corner column', Open: 'Open (legs stop short)',
                 CornerUnit: 'L-shaped corner unit', Blind: 'Blind corner (first leg runs in)' }[kind] || kind;
    }

    function na_type_options() {
        return na_types().map(function (row) {
            var label = (na_state.boot.productLabels || {})[row.Product] || row.Product || '';
            return { value: row.Code, label: row.Code + '  ·  ' + label };
        });
    }

    // HELPER FUNCTION | A Panel Type Dropdown That Can Also Change the Product
    // ---------------------------------------------------------------
    // Adam, 16-Nov-2026: "on the dropdowns, change the type of panel ...
    // you should be able to make the windows sliding or any of the
    // different elements very easily". Under the run's panel types the
    // list offers every other product of the mode. Picking one is the
    // "another product" edit: its value starts NA_NEW_PRODUCT.
    // @param value the code now chosen (its product is left out of the list)
    function na_type_select(act, value, attributes) {
        var chosen  = na_type_row(value);
        var others  = na_products().filter(function (key) { return !chosen || key !== chosen.Product; });
        var options = na_type_options().map(function (option) {
            return '<option value="' + na_escape(option.value) + '"' + (String(option.value) === String(value) ? ' selected' : '') + '>' + na_escape(option.label) + '</option>';
        }).join('');
        var change  = others.map(function (key) {
            return '<option value="' + NA_NEW_PRODUCT + na_escape(key) + '">' + na_escape(na_product_label(key)) + '</option>';
        }).join('');
        return '<select class="na-run-input" data-na-act="' + act + '"' + (attributes || '') + '>' + options +
               (change ? '<optgroup label="Change to">' + change + '</optgroup>' : '') + '</select>';
    }

    // -----------------------------------------------------------------------
    // REGION | Rendering - the five sections
    // -----------------------------------------------------------------------

    function na_render_run_section() {
        var frames = na_is_frames();
        var name   = na_metadata()['Na__Run__ComponentName'] || '';
        var body   = '<div class="na-run-grid">' +
            na_field('Run name', '<input type="text" class="na-run-input na-run-input--wide" data-na-act="set-name" value="' + na_escape(name) + '" placeholder="e.g. Conservatory__Framework">',
                     'After the fixed ' + (na_state.runId || 'ARN###') + '__AssemblyRun__ head') +
            // Flip Inside Out (V2.7.2). Its switch is the stored SideFlipped; the
            // flip itself is Ruby's (the path turned round), staged by na_stage.
            '<div class="na-run-field na-run-field--full"><label class="na-run-toggle"><input type="checkbox" data-na-act="flip"' +
            (na_get('SideFlipped') === true ? ' checked' : '') + '><span>Flip inside out</span></label>' +
            '<span class="na-run-field__note">' + (frames ? 'The framework faces the other way: its outside, and its columns, on the other side of the path.'
                                                           : 'The units face the other way: the room on the other side of the path.') +
            ' Nothing moves along the path; leg 1 becomes the last leg.</span></div>';
        var fused  = frames && na_get('FuseFramework') === true;
        var joined = frames && (fused || na_get('JoinCills') !== false);                   // <-- Ruby's rule (Na__LayoutResolver): a fused run always joins its cills
        if (frames) {
            body += na_field('Height', na_number('Height_mm'), 'Base to the top of the frames') +
                    '<div class="na-run-field na-run-field--full">' + na_toggle('FuseFramework', 'Fuse the framework') +
                    '<span class="na-run-field__note">The run builds the frame members as one piece with no join lines: each window\'s head and bottom rail, ' +
                    'a mullion between spans, a jamb elsewhere, the corner posts. The windows inside are their casements and glass; doors keep their own head and threshold.</span></div>';
            if (fused) {
                body += na_field('Mullion width', na_number('MullionWidth_mm'), 'Between two spans') +
                        na_field('Jamb width', na_number('JambWidth_mm'), 'Where a span meets a column, a corner or the end');
            }
            // One cill and one window board along the run (V2.7.3; Adam, 17-Nov-2026:
            // "the sill should wrap around all of the sides, and there shouldn't be
            // any join lines"). Fused, the switch is on and fixed.
            body += '<div class="na-run-field na-run-field--full"><label class="na-run-toggle"><input type="checkbox" data-na-act="set-flag" data-na-key="JoinCills"' +
                    (joined ? ' checked' : '') + (fused ? ' disabled' : '') + '><span>One cill along the run</span></label>' +
                    '<span class="na-run-field__note">' + (fused ? 'A fused framework always sits on one cill. ' : '') +
                    'One cill and one window board along the whole run, mitred round every corner, in place of each window\'s own. ' +
                    'Posts and blocks stand on it; a gap, a library column or a window on a sill height breaks it, and a door breaks the board.</span></div>';
            if (joined) {
                body += na_field('Cill height', na_number('CillHeight_mm'), '0 for no cill') +
                        na_field('Cill projection', na_number('CillProjection_mm'), 'Proud of the framework face');
            }
            body += na_field('Post depth', na_number('PostDepth_mm'), 'Mullions, jambs, infill blocks' + (fused ? '; the frames and cill reach back this far' : '')) +
                    na_field('Post inset', na_number('PostInset_mm'), 'Behind the framework face');
        } else {
            body += na_field('Unit depth', na_number('UnitDepth_mm'), 'Carcass depth: corners and infill blocks') +
                    na_field('Infill height', na_number('FillerHeight_mm'), 'When no unit stands beside the block');
        }
        body += '</div>';
        var summary = frames ? (na_trim(na_get('Height_mm')) + ' high' + (fused ? ' · fused, ' + na_trim(na_get('MullionWidth_mm')) + ' mullions' : '') +
                                (joined ? ' · one ' + na_trim(na_get('CillHeight_mm')) + ' cill' : ''))
                             : (na_trim(na_get('UnitDepth_mm')) + ' deep');
        return na_section('run', 'Run', summary, body);
    }

    function na_render_columns_section() {
        var mode    = na_mode();
        var columns = (na_state.boot.columnKinds[mode] || []).map(function (kind) { return { value: kind, label: na_column_label(kind) }; });
        var corners = (na_state.boot.cornerKinds[mode] || []).map(function (kind) { return { value: kind, label: na_corner_label(kind) }; });
        var joint   = na_get('JointColumn');
        var end     = na_get('EndColumn');
        var corner  = na_get('CornerColumn');
        var sized   = function (kind) { return kind === 'Infill' || kind === 'Gap'; };
        var body    = '<div class="na-run-grid">' +
            na_field('Between spans', na_select('set-choice', columns, joint, ' data-na-key="JointColumn"'), 'Where two spans follow each other on a leg') +
            (sized(joint) ? na_field('Width between', na_number('JointWidth_mm')) : '') +
            na_field('At the run\'s ends', na_select('set-choice', columns, end, ' data-na-key="EndColumn"'), 'An open run\'s two free ends') +
            (sized(end) ? na_field('End width', na_number('EndWidth_mm')) : '') +
            na_field('At corners', na_select('set-choice', corners, corner, ' data-na-key="CornerColumn"'), 'Library corner columns and corner units need 90 degrees') +
            (corner === 'Post' ? na_field('Corner post size', na_number('CornerPostSize_mm')) : '') +
            (corner === 'CornerUnit' ? na_field('Corner unit arm', na_number('CornerUnitLeg_mm'), 'Each arm, along its wall') : '') +
            (corner === 'Blind' ? na_field('Front allowance', na_number('FrontAllowance_mm'), 'Clear of the first leg\'s fronts') : '') +
            '</div>';
        return na_section('columns', 'Columns and Corners',
                          na_column_label(joint).split(' (')[0] + ' between · ' + na_corner_label(corner).split(' (')[0], body);
    }

    function na_render_path_section() {
        var closed = na_get('PathClosed') === true;
        var rows   = na_path_rows();
        var body   = '';
        if (na_state.measured) {
            body += '<div class="na-run-note na-run-note--go">A path measured in the model is waiting: Create Run on Path builds along it. ' +
                    '<button type="button" class="na-run-link" data-na-act="clear-measured">Forget it</button></div>';
        }
        body += '<table class="na-run-table"><thead><tr><th>Leg</th><th>Length</th><th>Turn at its end</th><th></th></tr></thead><tbody>';
        rows.forEach(function (row, index) {
            var last = index === rows.length - 1;
            body += '<tr><td>' + (index + 1) + '</td>' +
                    '<td><input type="number" class="na-run-input" data-na-act="path-length" data-na-index="' + index + '" value="' + row.length + '" min="50" step="5"' + (closed ? ' disabled' : '') + '><i class="na-run-unit">mm</i></td>' +
                    '<td>' + (last && !closed ? '<span class="na-run-mute">end of the run</span>'
                                              : '<input type="number" class="na-run-input" data-na-act="path-turn" data-na-index="' + index + '" value="' + row.turn + '" min="-179" max="179" step="5"' + (closed ? ' disabled' : '') + '><i class="na-run-unit">° left</i>') + '</td>' +
                    '<td>' + (rows.length > 1 && !closed ? '<button type="button" class="na-run-x" data-na-act="path-remove" data-na-index="' + index + '" title="Remove this leg">×</button>' : '') + '</td></tr>';
        });
        body += '</tbody></table><div class="na-run-actions">' +
                (closed ? '' : '<button type="button" class="na-run-btn" data-na-act="path-add" data-na-turn="90">+ Leg turning left</button>' +
                               '<button type="button" class="na-run-btn" data-na-act="path-add" data-na-turn="-90">+ Leg turning right</button>') +
                '</div><div class="na-run-note">' + (closed
                    ? 'A closed path is edited in the model: Edit Path draws it as a red line inside the run.'
                    : 'A positive turn is to the left. Measure Path picks the corners in the model; on a built run, Edit Path opens its path as a red line.') + '</div>';
        var total = rows.reduce(function (sum, row) { return sum + row.length; }, 0);
        return na_section('path', 'Path', rows.length + (rows.length === 1 ? ' leg' : ' legs') + ' · ' + Math.round(total) + (closed ? ' · closed' : ''), body);
    }

    // One leg's own item list, as it stands: its Items, or its Fill as laid out.
    function na_leg_items(index) {
        var row = na_legs()[index] || {};
        if (Array.isArray(row.Items) && row.Items.length) return row.Items;
        var laid = (na_layout_legs()[index] || {}).items || [];
        return laid.filter(function (item) { return item.kind === 'Span' || (item.kind === 'Column' && (item.origin === 'Item' || item.origin === 'Fill')); })
                   .map(function (item) { return item.kind === 'Span' ? { Kind: 'Span', PanelType: item.type } : { Kind: 'Column', Column: item.role, Width_mm: Math.round(item.width * 10) / 10 }; });
    }

    function na_render_leg(index) {
        var frames  = na_is_frames();
        var row     = na_legs()[index] || {};
        var laid    = na_layout_legs()[index] || {};
        var listed  = Array.isArray(row.Items) && row.Items.length > 0;
        var fill    = row.Fill || { PanelType: (na_types()[0] || {}).Code };
        var columns = (na_state.boot.columnKinds[na_mode()] || []).filter(function (kind) { return kind !== 'None'; });
        var head    = '<div class="na-run-leg__head"><b>Leg ' + (index + 1) + '</b><span>' + (laid.length ? Math.round(laid.length) + ' long' +
                      (laid.usable !== undefined && Math.abs(laid.usable - laid.length) > 0.5 ? ', ' + Math.round(laid.usable) + ' between its corners' : '') : '') + '</span>' +
                      na_select('leg-mode', [{ value: 'fill', label: 'Fill by rule' }, { value: 'list', label: 'Own list' }], listed ? 'list' : 'fill', ' data-na-leg="' + index + '"') + '</div>';
        var body;
        if (!listed) {
            body = '<div class="na-run-grid">' + na_field('Panel type', na_type_select('fill-type', fill.PanelType, ' data-na-leg="' + index + '"'),
                                                          'Or change to another kind of panel, at the foot of the list');
            if (frames) {
                body += na_field('How many', '<input type="number" class="na-run-input" data-na-act="fill-count" data-na-leg="' + index + '" value="' + (fill.Count || 1) + '" min="1" max="60" step="1">',
                                 'Equal spans; each takes a share of the leg unless its type has a set width');
            } else {
                body += na_field('Left over width', na_select('fill-infill', [
                    { value: 'End', label: 'A narrower unit at the end' }, { value: 'Start', label: 'A narrower unit at the start' },
                    { value: 'Both', label: 'Split between both ends' }, { value: 'Equal', label: 'Every unit the same width' }
                ], fill.Infill || 'End', ' data-na-leg="' + index + '"'), 'Whole units of the type\'s width first');
            }
            body += '</div>';
        } else {
            body = '<div class="na-run-chips">' + row.Items.map(function (item, place) {
                var span = item.Kind === 'Span';
                return '<span class="na-run-chip' + (span ? ' na-run-chip--span' : '') + '">' +
                       (span ? na_type_select('item-type', item.PanelType, ' data-na-leg="' + index + '" data-na-index="' + place + '" title="This span\'s panel type, or another kind of panel (at the foot of the list)"')
                             : na_escape(na_column_label(item.Column).split(' (')[0]) + (item.Column === 'Infill' || item.Column === 'Gap'
                                 ? ' <input type="number" class="na-run-input na-run-input--mini" data-na-act="item-width" data-na-leg="' + index + '" data-na-index="' + place + '" value="' + na_escape(na_trim(item.Width_mm)) + '" step="5">' : '')) +
                       '<button type="button" class="na-run-x" data-na-act="item-remove" data-na-leg="' + index + '" data-na-index="' + place + '" title="Remove">×</button></span>';
            }).join('') + '</div><div class="na-run-actions">' +
                '<button type="button" class="na-run-btn" data-na-act="item-add-span" data-na-leg="' + index + '">+ Span</button>' +
                columns.map(function (kind) {
                    return '<button type="button" class="na-run-btn" data-na-act="item-add-column" data-na-leg="' + index + '" data-na-kind="' + kind + '">+ ' + na_escape(na_column_label(kind).split(' (')[0]) + '</button>';
                }).join('') + '</div>';
        }
        return '<div class="na-run-leg">' + head + body + '</div>';
    }

    function na_render_legs_section() {
        var count = na_leg_count();
        var body  = '';
        for (var index = 0; index < count; index += 1) body += na_render_leg(index);
        var spans = (na_state.layout && na_state.layout.span_count) || 0;
        return na_section('legs', 'Legs and Spans', count + (count === 1 ? ' leg' : ' legs') + ' · ' + spans + (spans === 1 ? ' span' : ' spans'), body);
    }

    function na_render_types_section() {
        var frames   = na_is_frames();
        var products = (na_state.boot.products[na_mode()] || []).map(function (key) { return { value: key, label: (na_state.boot.productLabels || {})[key] || key }; });
        var body = '<table class="na-run-table na-run-table--types"><thead><tr><th>Code</th><th>Panel</th><th>Width</th>' + (frames ? '<th>Sill</th>' : '') + '<th>Spans</th><th></th></tr></thead><tbody>';
        na_types().forEach(function (row, index) {
            var laid    = na_layout_type(String(row.Code || '').toUpperCase());
            var built   = !!row.ElementId;
            var presets = [{ value: '', label: 'its starting values' }].concat((na_state.boot.presets || [])
                .filter(function (preset) { return preset.product === row.Product; })
                .map(function (preset) { return { value: preset.code, label: preset.code + ' ' + preset.name }; }));
            // The product can always be changed (V2.7.2), built or not: the type
            // is then built again from that product's start. Only a type a
            // fill made is fixed: it follows its rule.
            var fixed   = row.Auto === true;
            var source  = built ? '<span class="na-run-built" title="Built: its settings are edited on the element, in its own tab">' + na_escape(row.ElementId) + '</span>' +
                                  '<button type="button" class="na-run-link" data-na-act="type-edit" data-na-code="' + na_escape(row.Code) + '">Edit</button>'
                                : (row.SeedRoot ? '<span class="na-run-mute">' + (row.UniqueOf ? 'a copy of ' + na_escape(row.UniqueOf) : 'settings taken from a tab') + '</span>'
                                                : na_select('type-preset', presets, row.PresetCode || '', ' data-na-index="' + index + '" title="What the panel starts from"'));
            body += '<tr' + (row.Auto === true ? ' class="na-run-row--auto" title="Made by a leg\'s fill rule: it follows the rule"' : '') + '>' +
                    '<td><input type="text" class="na-run-input na-run-input--code" data-na-act="type-code" data-na-index="' + index + '" value="' + na_escape(row.Code) + '" maxlength="6"></td>' +
                    '<td>' + na_select('type-product', products, row.Product, ' data-na-index="' + index + '"' +
                                       (fixed ? ' disabled' : ' title="What every span of this type is. Another choice builds the type again from that panel\'s starting values."')) + source + '</td>' +
                    '<td><input type="number" class="na-run-input" data-na-act="type-width" data-na-index="' + index + '" value="' + na_escape(na_trim(row.Width_mm)) + '" placeholder="' +
                        (laid.width ? na_trim(laid.width) : 'shares') + '" min="100" step="5"' + (row.Auto === true ? ' disabled' : '') + '></td>' +
                    (frames ? '<td><input type="number" class="na-run-input" data-na-act="type-sill" data-na-index="' + index + '" value="' + na_escape(na_trim(row.SillHeight_mm || 0)) + '" min="0" step="5"></td>' : '') +
                    '<td class="na-run-count">' + (laid.count || 0) + '</td>' +
                    '<td>' + ((laid.count || 0) === 0 && na_types().length > 1 ? '<button type="button" class="na-run-x" data-na-act="type-remove" data-na-index="' + index + '" title="Remove this panel type">×</button>' : '') + '</td></tr>';
        });
        body += '</tbody></table><div class="na-run-actions">' +
                '<button type="button" class="na-run-btn" data-na-act="type-add">+ Panel type</button>' +
                '<button type="button" class="na-run-btn" data-na-act="type-from-tab">+ From the ' + (frames ? 'Windows & Ext. Doors' : 'Cabinetry') + ' tab</button></div>' +
                '<div class="na-run-note">Every span of one panel type is the same element: change one in its own tab and they all change. ' +
                'Leave a width empty and the type\'s spans share what their leg has left. Right-click a span in the preview to make it unique, give it another type, ' +
                'or change it to another kind of panel.</div>';
        return na_section('types', 'Panel Types', na_types().map(function (row) { return row.Code; }).join(', '), body);
    }

    // FUNCTION | Draw Every Section From the Root
    // ---------------------------------------------------------------
    function na_render_sections() {
        var host = document.getElementById(NA_SECTIONS_ID);
        if (!host) return;
        if (!na_state.boot || !na_state.root) {
            host.innerHTML = '<div class="na-run-note">Waiting for SketchUp…</div>';
            return;
        }
        host.innerHTML = na_render_run_section() + na_render_columns_section() + na_render_path_section() + na_render_legs_section() + na_render_types_section();
    }

    // FUNCTION | Redraw the Sections Without Losing the Field Being Typed In
    // ---------------------------------------------------------------
    // A layout arrives a moment after a change, by which time the user may
    // be typing in the next field. The field is found again by what it
    // edits, and given back its focus and what was typed so far.
    function na_render_sections_keeping_focus() {
        var host   = document.getElementById(NA_SECTIONS_ID);
        var active = document.activeElement;
        var marks  = ['data-na-act', 'data-na-key', 'data-na-leg', 'data-na-index'];
        var held   = null;
        if (host && active && host.contains(active) && active.getAttribute('data-na-act')) {
            held = { value: active.value, selector: active.tagName.toLowerCase() + marks.map(function (name) {
                var value = active.getAttribute(name);
                return value === null ? '' : '[' + name + '="' + value + '"]';
            }).join('') };
        }
        na_render_sections();
        if (!held) return;
        var again = host.querySelector(held.selector);
        if (!again) return;
        if (again.tagName.toLowerCase() === 'input' && again.type !== 'checkbox') again.value = held.value;
        again.focus();
    }

    function na_render_modes() {
        var host = document.getElementById(NA_PRODUCTS_ID);
        if (!host || !na_state.boot) return;
        var mode = na_mode();
        host.innerHTML = '<div class="na-lay-chipgroup"><b>Run of</b><div>' + (na_state.boot.modes || []).map(function (name) {
            return '<button type="button" class="na-lay-chip' + (name === mode ? ' na-lay-chip--on' : '') + '" data-na-run-mode="' + name + '" aria-pressed="' + (name === mode) +
                   '" title="' + na_escape(NA_MODE_NOTES[name] || name) + '"' + (na_state.runId && name !== mode ? ' disabled' : '') + '>' +
                   (name === 'Frames' ? 'Windows and Doors' : 'Cabinets') + '</button>';
        }).join('') + '</div></div><span class="na-run-modehint">' + na_escape(NA_MODE_NOTES[mode] || '') + '</span>';
    }

    // -----------------------------------------------------------------------
    // REGION | Previews, problems, info strip, dock
    // -----------------------------------------------------------------------

    // The two drawings are Na_RunPreview's (zoom, pan, dimensions, the view
    // tabs and the flip-out): it reads the layout and the selection through
    // the host handed to it in na_wire, and is only told when to draw.
    function na_draw() {
        var layout = na_state.layout;
        if (!layout) return;
        if (typeof Na_RunPreview !== 'undefined') Na_RunPreview.na_draw();

        var box = document.getElementById(NA_PROBLEMS_ID);
        if (box) {
            var rows = (layout.errors || []).map(function (text) { return '<li class="na-run-problem na-run-problem--error">' + na_escape(text) + '</li>'; })
                .concat((layout.warnings || []).map(function (text) { return '<li class="na-run-problem">' + na_escape(text) + '</li>'; }));
            box.innerHTML = rows.join('');
            box.hidden = rows.length === 0;
        }
        var size = document.getElementById('na-preview-size-runs');
        if (size) size.textContent = Math.round(layout.total_length || 0) + ' mm · ' + (layout.span_count || 0) + ' spans';
    }

    function na_sync_info() {
        var strip = document.getElementById('na-run-info');
        if (!strip) return;
        strip.classList.toggle('na-hidden', !na_state.runId);
        var id = document.getElementById('na-info-run-id');
        if (id) id.textContent = na_state.runId || '-';
        var name = document.getElementById('na-info-run-name');
        if (name) name.textContent = na_state.runName + (na_state.copies > 1 ? '  ·  placed ' + na_state.copies + ' times: every copy follows' : '');
        var state = document.getElementById('na-info-run-state');
        if (state) state.textContent = na_state.dirty ? 'changes not built yet: Update Run' : 'as built';
    }

    function na_sync_dock() {
        var ok      = !!(na_state.layout && (na_state.layout.errors || []).length === 0);
        var create  = document.getElementById('na-btn-run-create');
        var on_path = document.getElementById('na-btn-run-create-at-measurement');
        var update  = document.getElementById('na-btn-run-update');
        var edit    = document.getElementById('na-btn-run-editpath');
        if (create)  create.disabled = !ok;
        if (on_path) {
            on_path.disabled = !(ok && na_state.measured);
            on_path.classList.toggle('na-btn-disabled', on_path.disabled);
        }
        if (update)  update.disabled = !(ok && na_state.runId);
        if (edit) {
            edit.disabled    = !na_state.runId && !na_state.pathEdit;
            edit.textContent = na_state.pathEdit ? 'Finish Path Edit' : 'Edit Path';
            edit.classList.toggle('na-btn-success', !!na_state.pathEdit);
        }
        na_sync_info();
    }

    function na_refresh() {
        na_render_modes();
        na_render_sections();
        na_draw();
        na_sync_dock();
    }

    // -----------------------------------------------------------------------
    // REGION | Edits to the root (drafts and staged changes)
    // -----------------------------------------------------------------------

    // Write a leg down as its own list, so one of its spans can be changed.
    function na_list_leg(index) {
        var rows = na_legs();
        while (rows.length <= index) rows.push({});
        var row = rows[index];
        if (!(Array.isArray(row.Items) && row.Items.length)) {
            row.Items = na_leg_items(index);
            if (row.Fill) { row.FillWas = row.Fill; delete row.Fill; }
            na_write_down_types(row.Items);
        }
        return row.Items;
    }

    // A cabinet fill makes the narrower panel types it needs. Until the run
    // is built they are in the layout only. A leg written down as a list
    // names them, so each is given its row here, at the width it has (as
    // Ruby's Na__RunEdits.na_materialise_leg! does): without it the next
    // layout refused the list ("panel type 'B' is not in the list").
    function na_write_down_types(items) {
        items.forEach(function (item) {
            if (item.Kind !== 'Span' || na_type_row(item.PanelType)) return;
            var code = String(item.PanelType || '').toUpperCase();
            var laid = na_layout_type(code);
            if (!laid.product) return;
            var row = { Code: code, Product: laid.product };
            if (laid.width) row.Width_mm = Math.round(laid.width * 10) / 10;
            if (laid.derived_from) row.SeedFrom = laid.derived_from;
            na_types().push(row);
        });
    }

    function na_span_entry(index, span) {
        return na_list_leg(index).filter(function (item) { return item.Kind === 'Span'; })[span];
    }

    function na_recode_everywhere(from, to) {
        na_types().forEach(function (row) {
            if (String(row.Code).toUpperCase() === from) row.Code = to;
            ['DerivedFrom', 'SeedFrom', 'UniqueOf'].forEach(function (key) { if (String(row[key] || '').toUpperCase() === from) row[key] = to; });
        });
        na_legs().forEach(function (leg) {
            (leg.Items || []).forEach(function (item) { if (String(item.PanelType || '').toUpperCase() === from) item.PanelType = to; });
            ['Fill', 'FillWas'].forEach(function (key) { if (leg[key] && String(leg[key].PanelType || '').toUpperCase() === from) leg[key].PanelType = to; });
        });
    }

    // FUNCTION | Give a Panel Type Another Code (Staged)
    // ---------------------------------------------------------------
    function na_recode(from, to) {
        var old_code = String(from || '').trim().toUpperCase();
        var new_code = String(to || '').trim().toUpperCase();
        if (!new_code || new_code === old_code) return false;
        if (!/^[A-Z][A-Z0-9]{0,5}$/.test(new_code)) {
            na_status('warning', '"' + to + '" will not do as a panel type code: a letter, then up to five letters or digits (A, B2, DR1).');
            return false;
        }
        if (na_types().some(function (row) { return String(row.Code).toUpperCase() === new_code; })) {
            na_status('warning', 'Panel type ' + new_code + ' is already on this run.');
            return false;
        }
        na_recode_everywhere(old_code, new_code);
        return true;
    }

    // FUNCTION | Make One Span's Panel Unique
    // ---------------------------------------------------------------
    // A built run: Ruby does it at once (the new type copies the real
    // element). A draft: a copy of the type's row, staged.
    function na_make_unique(leg, span) {
        if (na_state.runId) {
            if (na_state.dirty) { na_status('warning', 'Update Run first: this run has changes that are not built yet.'); return; }
            na_send('na_runMakeUnique', { runId: na_state.runId, leg: leg, span: span });
            return;
        }
        var entry = na_span_entry(leg, span);
        if (!entry) return;
        var source = na_types().filter(function (row) { return String(row.Code).toUpperCase() === String(entry.PanelType).toUpperCase(); })[0];
        if (!source) return;
        var copy = na_clone(source);
        copy.Code = na_next_code();
        copy.UniqueOf = source.Code;
        delete copy.ElementId; delete copy.Auto; delete copy.DerivedFrom;
        var laid = na_layout_type(String(source.Code).toUpperCase());
        if (laid.width) copy.Width_mm = Math.round(laid.width * 10) / 10;
        na_types().push(copy);
        entry.PanelType = copy.Code;
        na_status('success', 'That span is now panel type ' + copy.Code + ', on its own.');
        na_changed();
    }

    function na_set_span_type(leg, span, code) {
        var entry = na_span_entry(leg, span);
        if (!entry) return;
        entry.PanelType = code;
        na_changed();
    }

    // FUNCTION | A Panel Type From Another Tab's Present Settings
    // ---------------------------------------------------------------
    // The new type starts as exactly what that tab would build now.
    function na_type_from_tab() {
        var seed = null, product = null;
        try {
            if (na_is_frames()) {
                seed = typeof window.na_buildFullConfig === 'function' ? window.na_buildFullConfig() : null;
                var values = (seed && seed.windowConfiguration) || {};
                product = values.multifold_mode ? 'bifold' : values.sliding_mode ? 'sliding' : values.double_door_mode ? 'double' :
                          values.ext_single_door_mode ? 'single' : values.sliding_sash_window ? 'sash' : 'casement';
            } else if (typeof Na_CabinetUI !== 'undefined' && typeof Na_CabinetUI.na_get_active_config === 'function') {
                seed = Na_CabinetUI.na_get_active_config();
                var cabinet = (seed && seed.Na__CabinetConfiguration) || {};
                var unit    = cabinet.Na__CabinetConfig__UnitType;
                product = unit === 'Wall' ? 'wall' : unit === 'Tower' ? (cabinet.Na__CabinetConfig__TowerInterior === 'Hanging' ? 'wardrobe' : 'tall') :
                          (cabinet.Na__CabinetConfig__BaseFrontLayout === 'Drawers' ? 'drawers' : 'base');
            }
        } catch (err) { console.warn('[Na_RunUI] could not read the other tab', err); }
        if (!seed) { na_status('warning', 'Open the ' + (na_is_frames() ? 'Windows & Ext. Doors' : 'Cabinetry') + ' tab once, set the element up, then try again.'); return; }
        na_types().push({ Code: na_next_code(), Product: product, SeedRoot: na_clone(seed) });
        na_status('success', 'Panel type added from the other tab\'s settings as it stands now.');
        na_changed();
    }

    // -----------------------------------------------------------------------
    // REGION | Events - the sections (one delegated listener each)
    // -----------------------------------------------------------------------

    function na_number_of(target) {
        var text = String(target.value).trim();
        return text === '' ? null : Number(text);
    }

    function na_on_change(event) {
        var target = event.target;
        var act    = target.getAttribute('data-na-act');
        if (!act || !na_config()) return;
        var config = na_config();
        var leg    = Number(target.getAttribute('data-na-leg'));
        var index  = Number(target.getAttribute('data-na-index'));
        var rows   = na_legs();
        var types  = na_types();

        switch (act) {
        case 'set':        config[na_key(target.getAttribute('data-na-key'))] = na_number_of(target); break;
        case 'set-flag':   config[na_key(target.getAttribute('data-na-key'))] = target.checked; break;
        case 'set-choice': config[na_key(target.getAttribute('data-na-key'))] = target.value; break;
        case 'set-name':   na_metadata()['Na__Run__ComponentName'] = target.value.trim(); break;
        case 'flip':
            // Edit Path draws the path as it is stored: turned round under an
            // open edit, the line would be read back the old way.
            if (na_state.pathEdit) {
                na_status('warning', 'Finish the path edit first, then flip the run.');
                target.checked = !target.checked;
                return;
            }
            na_stage('flip', {});
            return;
        case 'path-length':
        case 'path-turn': {
            var path = na_path_rows();
            if (!path[index]) return;
            if (act === 'path-length') path[index].length = Math.max(na_number_of(target) || 0, 50);
            else path[index].turn = na_number_of(target) || 0;
            na_apply_path_rows(path);
            return;
        }
        case 'leg-mode':
            while (rows.length <= leg) rows.push({});
            if (target.value === 'list') na_list_leg(leg);
            else { rows[leg] = { Fill: rows[leg].FillWas || rows[leg].Fill || { PanelType: (types[0] || {}).Code } }; }
            break;
        case 'fill-type':
        case 'fill-count':
        case 'fill-infill':
            if (act === 'fill-type' && String(target.value).indexOf(NA_NEW_PRODUCT) === 0) {      // <-- "Change to": another product for the leg's fill
                na_stage('fill_product', { leg: leg, product: target.value.slice(NA_NEW_PRODUCT.length) });
                return;
            }
            while (rows.length <= leg) rows.push({});
            rows[leg] = { Fill: rows[leg].Fill || { PanelType: (types[0] || {}).Code } };
            if (act === 'fill-type')   rows[leg].Fill.PanelType = target.value;
            if (act === 'fill-count')  rows[leg].Fill.Count = Math.max(1, Math.round(na_number_of(target) || 1));
            if (act === 'fill-infill') rows[leg].Fill.Infill = target.value;
            break;
        case 'item-type':
            if (String(target.value).indexOf(NA_NEW_PRODUCT) === 0) {                                // <-- "Change to": another product for this one span
                var before = rows[leg].Items.slice(0, index).filter(function (item) { return item.Kind === 'Span'; }).length;
                na_stage('span_product', { leg: leg, span: before, product: target.value.slice(NA_NEW_PRODUCT.length) });
                return;
            }
            rows[leg].Items[index].PanelType = target.value;
            break;
        case 'item-width': rows[leg].Items[index].Width_mm = na_number_of(target); break;
        case 'type-code':
            if (!na_recode(types[index].Code, target.value)) { target.value = types[index].Code; return; }
            break;
        case 'type-product':                                                                     // <-- Every span of the type: Ruby's rule (what the row keeps and drops)
            na_stage('type_product', { code: types[index].Code, product: target.value });
            return;
        case 'type-preset':  if (target.value) types[index].PresetCode = target.value; else delete types[index].PresetCode; break;
        case 'type-width':   if (na_number_of(target) === null) delete types[index].Width_mm; else types[index].Width_mm = na_number_of(target); break;
        case 'type-sill':    types[index].SillHeight_mm = na_number_of(target) || 0; break;
        default: return;
        }
        na_changed();
    }

    function na_on_click(event) {
        var target = event.target.closest ? event.target.closest('[data-na-act]') : null;
        if (!target || !na_config()) return;
        var act   = target.getAttribute('data-na-act');
        var leg   = Number(target.getAttribute('data-na-leg'));
        var index = Number(target.getAttribute('data-na-index'));
        var types = na_types();

        switch (act) {
        case 'toggle-section': {
            var id = target.getAttribute('data-na-sec');
            na_state.open[id] = na_state.open[id] === false;
            na_render_sections();
            return;
        }
        case 'clear-measured': na_send('na_runClearMeasuredPath'); return;
        case 'path-add': {
            var path = na_path_rows();
            path[path.length - 1].turn = Number(target.getAttribute('data-na-turn'));
            path.push({ length: 3000, turn: 0 });
            na_apply_path_rows(path);
            return;
        }
        case 'path-remove': {
            var rows = na_path_rows();
            rows.splice(index, 1);
            na_legs().splice(index, 1);
            na_apply_path_rows(rows);
            return;
        }
        case 'item-remove':     na_list_leg(leg).splice(index, 1); break;
        case 'item-add-span':   na_list_leg(leg).push({ Kind: 'Span', PanelType: (types[0] || {}).Code }); break;
        case 'item-add-column': {
            var kind = target.getAttribute('data-na-kind');
            var item = { Kind: 'Column', Column: kind };
            if (kind === 'Infill' || kind === 'Gap') item.Width_mm = na_get('JointWidth_mm');
            na_list_leg(leg).push(item);
            break;
        }
        case 'type-add':
            types.push({ Code: na_next_code(), Product: (na_state.boot.products[na_mode()] || [])[0] });
            break;
        case 'type-remove':   types.splice(index, 1); break;
        case 'type-from-tab': na_type_from_tab(); return;
        case 'type-edit':     na_edit_type(target.getAttribute('data-na-code')); return;
        default: return;
        }
        na_changed();
    }

    // Select one span of a built type in the model: it loads into its own tab.
    function na_edit_type(code) {
        var legs = na_layout_legs();
        for (var i = 0; i < legs.length; i += 1) {
            var items = legs[i].items || [];
            for (var j = 0; j < items.length; j += 1) {
                if (items[j].kind === 'Span' && items[j].type === String(code).toUpperCase()) {
                    na_send('na_runSelectMember', { runId: na_state.runId, leg: items[j].leg, span: items[j].span });
                    return;
                }
            }
        }
        na_status('warning', 'No span uses panel type ' + code + ' yet.');
    }

    // -----------------------------------------------------------------------
    // REGION | Events - the previews (select a span, its menu, a typed dimension)
    // -----------------------------------------------------------------------
    // Na_RunPreview binds the drawings and calls these three.

    // @param span { leg, span, type } of the span clicked, or null for empty space
    function na_on_preview_select(span) {
        na_state.selection = span ? { leg: span.leg, span: span.span } : null;
        na_draw();
    }

    // FUNCTION | A Size Typed Over a Dimension in a Drawing
    // ---------------------------------------------------------------
    // Sets what the dimension measures, exactly as its field in the
    // sections would (a staged change on a built run). The entry takes the
    // fields' sums and relative entries: '+50' adds 50, '5400/3' works it out.
    // @param  kind  'leg' | 'type' | 'height' | 'sill' | 'joint' (see the drawer)
    // @param  index the leg, or the panel type's place in the layout's types
    // @return { ok: true, changed } | { ok: false, error }
    function na_apply_dimension(kind, index, text) {
        var layout = na_state.layout;
        var config = na_config();
        if (!layout || !config) return { ok: false, error: 'The drawing is not ready' };

        var limits   = (na_state.boot && na_state.boot.limits) || {};
        var minimums = (na_state.boot && na_state.boot.minimums) || {};
        var code     = Object.keys(layout.types || {})[index];
        var row      = na_types().filter(function (item) { return String(item.Code).toUpperCase() === code; })[0];
        var laid     = na_layout_type(code);
        var height   = Number(na_get('Height_mm')) || 0;
        var target   = null;                                                    // <-- { current, min, max, apply }

        switch (kind) {
        case 'leg': {
            var rows = na_path_rows();
            if (!rows[index] || na_get('PathClosed') === true) return { ok: false, error: 'A closed path is edited in the model (Edit Path)' };
            target = { current: rows[index].length, min: minimums.leg || 50, max: Infinity,
                       apply: function (value) { rows[index].length = value; na_apply_path_rows(rows); } };
            break;
        }
        case 'type':
            if (!row) return { ok: false, error: 'That panel type is not on the run' };
            target = { current: laid.width, min: minimums.span || 100, max: Infinity,
                       apply: function (value) { row.Width_mm = value; na_changed(); } };
            break;
        case 'sill':
            if (!row) return { ok: false, error: 'That panel type is not on the run' };
            target = { current: laid.sill || 0, min: 0, max: Math.max(height - (minimums.span || 100), 0),
                       apply: function (value) { row.SillHeight_mm = value; na_changed(); } };
            break;
        case 'height':
        case 'joint': {
            var key   = kind === 'height' ? 'Height_mm' : 'JointWidth_mm';
            var range = limits[key] || [];
            target = { current: Number(na_get(key)), min: range[0], max: range[1],
                       apply: function (value) { config[na_key(key)] = value; na_changed(); } };
            break;
        }
        default:
            return { ok: false, error: 'That dimension cannot be set here' };
        }

        var arithmetic = window.Na__Utils__Arithmetic;
        var value;
        if (arithmetic) {
            var resolved = arithmetic.na_resolve_field_value(text, { currentValue: target.current, min: target.min, max: target.max, allowRelativeMinus: true });
            if (!resolved.ok) return { ok: false, error: resolved.error };
            value = resolved.value;
        } else {
            value = parseFloat(text);
            if (!isFinite(value)) return { ok: false, error: 'Not a number' };
            if (isFinite(target.min)) value = Math.max(target.min, value);
            if (isFinite(target.max)) value = Math.min(target.max, value);
        }
        if (Math.abs(value - target.current) < 0.0005) return { ok: true, changed: false };
        target.apply(value);
        return { ok: true, changed: true };
    }

    // @param span { leg, span, type } of the span right-clicked
    function na_on_preview_menu(event, span) {
        if (!span || typeof Na_RunContextMenu === 'undefined') return;
        event.preventDefault();
        na_state.selection = { leg: span.leg, span: span.span };
        na_draw();

        var laid   = na_layout_type(span.type);
        var shared = (laid.count || 0) > 1;
        var others = na_types().map(function (row) { return String(row.Code).toUpperCase(); }).filter(function (code) { return code !== span.type; });
        var entries = [
            { heading: 'Panel type ' + span.type + '  ·  ' + na_product_label(laid.product) + '  ·  L' + (span.leg + 1) + 'S' + (span.span + 1) },
            { label: 'Make Panel Unique', hint: shared ? 'a new type, a copy of ' + span.type : 'already the only one', disabled: !shared,
              run: function () { na_make_unique(span.leg, span.span); } },
            { label: 'Recode Panel Type…', hint: 'all ' + (laid.count || 0),
              input: { value: span.type, placeholder: 'A, B2, DR1', apply: function (code) { if (na_recode(span.type, code)) na_changed(); } } }
        ];
        if (others.length) entries.push({ separator: true });
        others.forEach(function (code) {
            entries.push({ label: 'Change This Panel to Type ' + code, hint: na_product_label((na_type_row(code) || {}).Product),
                           run: function () { na_set_span_type(span.leg, span.span, code); } });
        });

        // Another kind of panel (V2.7.2; Adam, 16-Nov-2026: "you should be able
        // to make the windows sliding or any of the different elements very
        // easily"). This span alone, or every span of its type. Staged like
        // the rows above: Update Run builds it.
        var kinds = na_products().filter(function (key) { return key !== laid.product; });
        if (kinds.length) {
            entries.push({ separator: true });
            entries.push({ label: 'Change This Panel to', hint: shared ? 'a new type' : 'type ' + span.type + ' changes',
                           choices: kinds.map(function (key) {
                               return { label: na_product_label(key), run: function () { na_stage('span_product', { leg: span.leg, span: span.span, product: key }); } };
                           }) });
            if (shared && !laid.auto) {
                entries.push({ label: 'Change All ' + laid.count + ' of Type ' + span.type + ' to', hint: 'type ' + span.type + ' changes',
                               choices: kinds.map(function (key) {
                                   return { label: na_product_label(key), run: function () { na_stage('type_product', { code: span.type, product: key }); } };
                               }) });
            }
        }
        if (na_state.runId) {
            entries.push({ separator: true });
            entries.push({ label: 'Edit Panel Type ' + span.type + ' in Its Tab', hint: 'selects it in the model',
                           run: function () { na_send('na_runSelectMember', { runId: na_state.runId, leg: span.leg, span: span.span }); } });
        }
        Na_RunContextMenu.na_open(event.clientX, event.clientY, entries);
    }

    // -----------------------------------------------------------------------
    // REGION | Dock actions
    // -----------------------------------------------------------------------

    Na_RunUI.na_measure = function () {
        if (na_send('na_runMeasurePath', { mode: na_mode() })) {
            na_status('info', 'Click each corner of the path, Enter at the last, then click the side the ' + (na_is_frames() ? 'framework is seen from (outside)' : 'units face (the room)') + '.');
        }
    };

    Na_RunUI.na_create = function () {
        if (!na_state.root) return;
        var draft = na_clone(na_state.root);
        var meta  = draft[na_keys().metadata][0] || {};
        delete meta['Na__Run__UniqueId'];
        // A new run builds its own elements: a description loaded from a run
        // in the model must not claim that run's.
        (draft[na_keys().configuration][na_key('PanelTypes')] || []).forEach(function (row) { delete row.ElementId; delete row.FrameBeforeFuse; });
        // A draft that took its path from the measurement holds that path as
        // it has been changed here since (flipped inside out, a leg retyped):
        // Ruby then builds the draft's path at the measured placement. Without
        // the marker Ruby builds the path exactly as it was picked. The key
        // comes with the bootstrap: a Ruby too old to send it would not read it.
        if (na_state.measured && na_state.measuredInDraft && na_keys().draftPath) draft[na_keys().draftPath] = na_keys().draftPathPage;
        na_send('na_runCreate', draft);
    };

    Na_RunUI.na_update = function () {
        if (!na_state.root || !na_state.runId) return;
        na_metadata()['Na__Run__UniqueId'] = na_state.runId;
        na_send('na_runUpdate', na_state.root);
    };

    Na_RunUI.na_edit_path = function () {
        if (na_state.pathEdit) { na_send('na_runFinishPathEdit'); return; }
        if (na_state.dirty) { na_status('warning', 'Update Run first: this run has changes that are not built yet.'); return; }
        na_send('na_runEditPath');
    };

    Na_RunUI.na_new = function () {
        na_new_draft(na_mode());
        na_history_record();                                                    // <-- Undo brings back what New Run replaced
        na_refresh();
        na_request_layout();
    };

    Na_RunUI.na_undo = function () { return na_history_go(-1); };
    Na_RunUI.na_redo = function () { return na_history_go(1); };

    // For the tests that drive the page: where the history stands.
    Na_RunUI.na_get_history_state = function () { return { steps: na_history.steps.length, at: na_history.at }; };

    // -----------------------------------------------------------------------
    // REGION | Ruby -> JS (called by the Bridge file)
    // -----------------------------------------------------------------------

    Na_RunUI.na_receive_bootstrap = function (payload) {
        na_state.boot     = payload;
        na_state.pathEdit = payload.pathEdit || null;
        if (!na_state.root) {
            na_new_draft('Frames');
            na_history_reset();
        }
        na_refresh();
        na_request_layout();
    };

    Na_RunUI.na_receive_layout = function (payload) {
        na_state.layout = payload.layout;
        na_render_sections_keeping_focus();                                     // <-- Counts, widths and leg lengths come from the layout
        na_draw();
        na_sync_dock();
    };

    // FUNCTION | A Staged Edit's Answer From Ruby (V2.7.2)
    // ---------------------------------------------------------------
    // The description as Na__RunEdits changed it, with its layout. A refusal
    // changes nothing: the controls are drawn again from what still stands.
    // @param payload { ok, edit, root, layout, message }
    Na_RunUI.na_receive_staged = function (payload) {
        if (!payload.ok) {
            na_render_sections();
            na_status('warning', payload.message || 'That change could not be made.');
            return;
        }
        na_state.root       = payload.root;
        na_state.layout     = payload.layout;
        na_state.dirty      = true;
        na_state.legsByHand = true;
        if (payload.edit === 'flip') na_state.selection = null;                 // <-- Its legs are numbered from the other end now
        na_history_record();
        na_refresh();
        na_status('success', payload.message + (na_state.runId ? ' Update Run builds it.' : ''));
    };

    // A setting a run stored before it existed reads as Ruby's default
    // (Na__LayoutResolver.na_get does the same), so its field shows that
    // value instead of an empty box (V2.7.3: a run built before the cill
    // settings came in still has its 50mm cill).
    function na_fill_missing_settings(root) {
        var keys     = na_keys();
        var config   = root && root[keys.configuration];
        var mode     = (config && config[keys.prefix + 'Mode']) || 'Frames';
        var defaults = (((na_state.boot || {}).defaults || {})[mode] || {})[keys.configuration];
        if (!config || !defaults) return;
        Object.keys(defaults).forEach(function (key) {
            if (!(key in config)) config[key] = na_clone(defaults[key]);
        });
    }

    // A run selected in the model (or just built): show what it stores.
    Na_RunUI.na_receive_run = function (payload) {
        na_fill_missing_settings(payload.root);
        na_state.root      = payload.root;
        na_state.layout    = payload.layout;
        na_state.runId     = payload.runId;
        na_state.runName   = payload.name || payload.runId;
        na_state.copies    = payload.copies || 1;
        na_state.dirty     = false;
        na_state.legsByHand = true;                                             // <-- A built run's legs are never reseeded
        na_state.selection = null;
        na_state.measuredInDraft = false;                                       // <-- This description is the run's, not the measured path's
        na_history_reset();                                                     // <-- What is built is SketchUp's own Undo from here
        na_refresh();
    };

    // The selection moved off the run: keep its description as a draft to
    // build another like it, no longer tied to the one in the model.
    Na_RunUI.na_clear_run = function () {
        if (!na_state.runId) return;
        na_state.runId = null;
        na_state.runName = '';
        na_state.dirty = false;
        na_history_reset();                                                     // <-- A draft from here: no step back to the run it was
        na_render_modes();
        na_render_sections();
        na_sync_dock();
    };

    Na_RunUI.na_receive_path = function (payload) {
        na_state.measured = payload.active ? payload : null;
        na_state.measuredInDraft = false;
        var button = document.getElementById('na-btn-measure');
        if (button) button.classList.remove('na-btn-measure-active');
        if (payload.active && !na_state.runId && na_config()) {
            na_config()[na_key('PathPoints')] = na_clone(payload.points);
            na_config()[na_key('PathClosed')] = !!payload.closed;
            na_config()[na_key('SideFlipped')] = false;                         // <-- A newly picked path faces the side that was clicked
            var rows = na_legs();
            while (rows.length > payload.legs.length) rows.pop();
            var by_hand = na_state.legsByHand;
            na_seed_legs(payload.legs);
            na_state.measuredInDraft = true;                                    // <-- Create builds this draft's path, at the measured placement
            na_changed();
            na_state.legsByHand = by_hand;                                      // <-- A path arriving is not the user setting the legs
            na_history_reset();                                                 // <-- No step back to the path before the one measured
            return;
        }
        na_render_sections();
        na_sync_dock();
    };

    Na_RunUI.na_set_path_edit = function (payload) {
        na_state.pathEdit = payload.active ? (payload.runId || true) : null;
        na_sync_dock();
    };

    // -----------------------------------------------------------------------
    // REGION | TabRouter contract
    // -----------------------------------------------------------------------

    Na_RunUI.na_get_active_config = function () { return na_state.root; };

    Na_RunUI.na_mount = function () {
        if (typeof Na_RunPreview !== 'undefined') Na_RunPreview.na_tab_shown(true);     // <-- Flips the preview out again if it was when the tab was left
        if (!na_state.boot) {
            na_render_sections();
            na_send('na_runRequestBootstrap');
            return;
        }
        na_refresh();
        if (!na_state.layout) na_request_layout();
    };

    Na_RunUI.na_unmount = function () {
        if (typeof Na_RunContextMenu !== 'undefined') Na_RunContextMenu.na_close();
        if (typeof Na_RunPreview !== 'undefined') Na_RunPreview.na_tab_shown(false);    // <-- A flipped-out preview goes back; the dialog narrows
    };

    // -----------------------------------------------------------------------
    // REGION | Bootstrap
    // -----------------------------------------------------------------------

    function na_wire() {
        var sections = document.getElementById(NA_SECTIONS_ID);
        if (sections) {
            sections.addEventListener('change', na_on_change);
            sections.addEventListener('click', na_on_click);
        }
        var modes = document.getElementById(NA_PRODUCTS_ID);
        if (modes) modes.addEventListener('click', function (event) {
            var chip = event.target.closest ? event.target.closest('[data-na-run-mode]') : null;
            if (!chip || chip.disabled || chip.getAttribute('data-na-run-mode') === na_mode()) return;
            na_new_draft(chip.getAttribute('data-na-run-mode'));
            na_history_record();                                                // <-- Undo brings back the draft of the other mode
            na_refresh();
            na_request_layout();
        });
        if (typeof Na_RunPreview !== 'undefined') {
            Na_RunPreview.na_init({
                layout       : function () { return na_state.layout; },
                selection    : function () { return na_state.selection; },
                closed       : function () { return na_get('PathClosed') === true; },
                product      : na_product_label,
                on_select    : na_on_preview_select,
                on_menu      : na_on_preview_menu,
                on_dimension : na_apply_dimension
            });
        }

        // Undo and Redo: the two buttons in the preview's head, and the keys.
        var undo = document.getElementById(NA_UNDO_ID);
        var redo = document.getElementById(NA_REDO_ID);
        if (undo) undo.addEventListener('click', function () { na_history_go(-1); });
        if (redo) redo.addEventListener('click', function () { na_history_go(1); });
        document.addEventListener('keydown', na_on_keydown);
        na_sync_history();
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', na_wire);
    else na_wire();

    window.Na_RunUI = Na_RunUI;
})();
